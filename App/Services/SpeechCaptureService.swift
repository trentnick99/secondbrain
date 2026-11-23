import AVFoundation
import Foundation
import Observation
import Speech

/// Voice capture using Apple's Speech framework. Uses on-device recognition whenever the device
/// supports it, so captures stay on the iPhone and work without a connection. Typing and the
/// keyboard's dictation key always remain available as fallbacks.
@MainActor
@Observable
final class SpeechCaptureService {
    enum State: Equatable {
        case idle
        case preparing
        case listening
        case unavailable(String)
    }

    private(set) var state: State = .idle
    private(set) var transcript: String = ""
    private(set) var isOnDevice: Bool = false

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    var isListening: Bool { state == .listening || state == .preparing }

    func toggle() async {
        if isListening { stop() } else { await start() }
    }

    func start() async {
        guard !isListening else { return }
        transcript = ""
        state = .preparing

        let speechStatus = await Self.requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            state = .unavailable("Speech recognition is turned off for Second Brain. You can enable it in iOS Settings, or use the keyboard's microphone key.")
            return
        }
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            state = .unavailable("Microphone access is off. Enable it in iOS Settings, or type your capture.")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable("Speech recognition isn't available right now. Try the keyboard's dictation key.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
                isOnDevice = true
            } else {
                isOnDevice = false
            }

            guard Self.installTap(on: engine, request: request) else {
                state = .unavailable("No microphone input is available.")
                return
            }
            engine.prepare()
            try engine.start()

            self.engine = engine
            self.request = request
            self.recognitionTask = Self.startRecognition(recognizer: recognizer, request: request) { [weak self] text, finished in
                Task { @MainActor in
                    guard let self else { return }
                    if let text { self.transcript = text }
                    if finished { self.stop() }
                }
            }
            state = .listening
        } catch {
            stop()
            state = .unavailable("Couldn't start listening: \(error.localizedDescription)")
        }
    }

    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognitionTask?.finish()
        engine = nil
        request = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if case .unavailable = state { return }
        state = .idle
    }

    func reset() {
        stop()
        transcript = ""
        state = .idle
    }

    // MARK: Non-isolated helpers (audio callbacks arrive on background threads)

    nonisolated private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    nonisolated private static func installTap(on engine: AVAudioEngine, request: SFSpeechAudioBufferRecognitionRequest) -> Bool {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        return true
    }

    nonisolated private static func startRecognition(recognizer: SFSpeechRecognizer,
                                                     request: SFSpeechAudioBufferRecognitionRequest,
                                                     handler: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            handler(text, finished)
        }
    }
}
