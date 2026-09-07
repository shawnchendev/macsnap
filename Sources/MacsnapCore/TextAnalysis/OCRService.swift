import Foundation
import CoreGraphics
import Vision

public enum OCRService {
    /// Recognizes text from a CGImage using Apple's Vision framework.
    public static func recognizeText(from image: CGImage) async -> (text: String, error: String?) {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { req, err in
                if let err = err {
                    continuation.resume(returning: ("", err.localizedDescription))
                    return
                }
                guard let observations = req.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: ("", nil))
                    return
                }
                let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
                let fullText = recognizedStrings.joined(separator: "\n")
                continuation.resume(returning: (fullText, nil))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            // Respect OMASNAP_OCR_LANGS / MACSNAP_OCR_LANGS if configured
            if let customLangs = ProcessInfo.processInfo.environment["MACSNAP_OCR_LANGS"] ??
                                 ProcessInfo.processInfo.environment["OMASNAP_OCR_LANGS"] {
                let langs = customLangs.split(separator: "+").map { String($0) }
                if !langs.isEmpty {
                    request.recognitionLanguages = langs
                }
            }

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: ("", error.localizedDescription))
            }
        }
    }
}
