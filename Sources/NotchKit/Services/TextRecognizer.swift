import Foundation
import Vision

/// Reads the text in an image with Vision, entirely on this Mac.
enum TextRecognizer {
    /// Bigger images are skipped; screenshots are a few megabytes at most.
    static let maximumBytes = 30_000_000

    /// The image's text, line by line, or nil when there's none.
    static func text(in imageData: Data) async -> String? {
        guard imageData.count <= maximumBytes else { return nil }
        return await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            do {
                try VNImageRequestHandler(data: imageData).perform([request])
            } catch {
                return nil
            }
            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }.value
    }
}
