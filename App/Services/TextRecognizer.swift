import Foundation
import ImageIO
import SwiftUI
import UIKit
import Vision
import VisionKit
import SecondBrainCore

/// Reads printed or handwritten text from photos and scanned pages with Apple's Vision framework.
/// Everything happens on the iPhone; photos aren't saved or sent anywhere.
enum TextRecognizer {
    static func text(in images: [UIImage]) async -> String {
        var pages: [String] = []
        for image in images {
            let page = await recognize(image)
            if !page.isEmpty { pages.append(page) }
        }
        return pages.joined(separator: "\n\n")
    }

    static func recognize(_ image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                try? handler.perform([request])
                let boxes: [TextBox] = (request.results ?? []).compactMap { observation in
                    guard let best = observation.topCandidates(1).first else { return nil }
                    let box = observation.boundingBox
                    return TextBox(text: best.string, x: box.minX, y: box.minY, width: box.width, height: box.height)
                }
                continuation.resume(returning: RecognizedText.text(from: boxes))
            }
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// Apple's document camera: finds the page edges and flattens each page.
struct DocumentScanner: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish, onCancel: onCancel) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onCancel() }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onCancel() }
    }
}
