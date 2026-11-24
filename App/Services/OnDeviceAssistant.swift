import Foundation
import SecondBrainCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether Apple's on-device model can write answers right now, and what to tell the person if not.
enum AssistantAvailability: Equatable {
    case ready, needsNewerIOS, notSupported, turnedOff, downloading, unavailable

    var message: String {
        switch self {
        case .ready: return "Apple Intelligence is ready."
        case .needsNewerIOS: return "Written answers need iOS 26 or later. The guides below still work."
        case .notSupported: return "This iPhone doesn't support Apple Intelligence, so Ask shows guides only."
        case .turnedOff: return "Turn on Apple Intelligence in Settings › Apple Intelligence & Siri to get written answers."
        case .downloading: return "Apple Intelligence is still getting ready on this iPhone. Try again a little later."
        case .unavailable: return "Written answers aren't available right now. The guides below still work."
        }
    }
}

enum AssistantError: Error { case unavailable }

/// Writes answers with Apple's on-device model (Foundation Models, iOS 26+). Nothing leaves the phone,
/// it works offline, and the core app never depends on it.
enum OnDeviceAssistant {
    static var availability: AssistantAvailability {
        if PersistenceController.isUITesting { return .unavailable }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return modelAvailability() }
        #endif
        return .needsNewerIOS
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func modelAvailability() -> AssistantAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .notSupported
            case .appleIntelligenceNotEnabled: return .turnedOff
            case .modelNotReady: return .downloading
            @unknown default: return .unavailable
            }
        @unknown default:
            return .unavailable
        }
    }
    #endif

    /// A short answer grounded in the best-matching guides (and the person's own store steps).
    static func answer(question: String, guides: [CoachGuide], role: UserRole?, storeSteps: [String: String]) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), availability == .ready {
            let session = LanguageModelSession(instructions: AskAssistant.instructions(role: role))
            let prompt = AskAssistant.prompt(question: question, guides: guides, storeSteps: storeSteps)
            let response = try await session.respond(to: prompt)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw AssistantError.unavailable
    }
}
