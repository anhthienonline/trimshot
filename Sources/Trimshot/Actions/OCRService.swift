import Foundation
import Vision

enum OCRError: LocalizedError {
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .noTextFound: "No readable text in the selection."
        }
    }
}

/// Pulls text out of a capture with Vision, entirely on-device.
enum OCRService {

    /// Preferred order. Vietnamese first so diacritics are modelled properly; English is
    /// kept alongside because UI screenshots mix the two constantly.
    ///
    /// The Vietnamese tag really is `vi-VT` and not `vi-VN` — that is the identifier
    /// Vision reports, region subtag and all. Using the correct-looking `vi-VN` silently
    /// drops Vietnamese and leaves you with English-only recognition, which mangles every
    /// accented word.
    private static let preferredLanguages = ["vi-VT", "en-US"]

    /// Everything Vision can recognise here, and which of those we will actually ask for.
    /// Exposed for diagnostics: the language set depends on the revision and on the macOS
    /// version, so a silent fallback needs to be visible.
    static func languageReport() -> (available: [String], chosen: [String]) {
        let request = makeRequest()
        let available = (try? request.supportedRecognitionLanguages()) ?? []
        return (available, supportedLanguages(for: request))
    }

    /// `CGImage` is immutable but not marked `Sendable`, so it needs a box to cross into a
    /// detached task.
    private struct ImageBox: @unchecked Sendable {
        let image: CGImage
    }

    /// Off-main-thread recognition.
    ///
    /// `.accurate` Vision recognition on a large selection takes long enough to freeze the
    /// UI — the overlay stays on screen while it runs, so a blocked main thread means a
    /// frozen screen. Callers stay on the main actor and just await this.
    static func recognizeText(in image: CGImage) async throws -> String {
        let box = ImageBox(image: image)
        return try await Task.detached(priority: .userInitiated) {
            try recognizeText(inSync: box.image)
        }.value
    }

    static func recognizeText(inSync image: CGImage) throws -> String {
        let request = makeRequest()
        request.recognitionLanguages = supportedLanguages(for: request)

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results, !observations.isEmpty else {
            throw OCRError.noTextFound
        }

        let text = readingOrder(observations)
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")

        guard !text.isEmpty else { throw OCRError.noTextFound }
        return text
    }

    /// Revision 3 is what makes this useful: revision 1 knows only English and revision 2
    /// only six European languages, while revision 3 covers thirty including Vietnamese.
    /// `.fast` is likewise limited to six languages, so accurate is not optional here.
    private static func makeRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let best = VNRecognizeTextRequest.supportedRevisions.max()
        if let best, best >= 3 {
            request.revision = best
        }
        return request
    }

    /// Vision rejects the whole request if it is handed a language it cannot do, and the
    /// set varies by OS version — so ask first and fall back to English.
    private static func supportedLanguages(for request: VNRecognizeTextRequest) -> [String] {
        let available = (try? request.supportedRecognitionLanguages()) ?? []
        let usable = preferredLanguages.filter(available.contains)
        return usable.isEmpty ? ["en-US"] : usable
    }

    /// Vision's ordering is not guaranteed, so sort top-to-bottom then left-to-right.
    /// Normalised coordinates put the origin at the bottom-left, hence the descending Y.
    private static func readingOrder(
        _ observations: [VNRecognizedTextObservation]
    ) -> [VNRecognizedTextObservation] {
        observations.sorted { lhs, rhs in
            let lhsTop = lhs.boundingBox.maxY
            let rhsTop = rhs.boundingBox.maxY
            // Treat lines within half a line-height of each other as the same row.
            let tolerance = max(lhs.boundingBox.height, rhs.boundingBox.height) * 0.5
            if abs(lhsTop - rhsTop) > tolerance {
                return lhsTop > rhsTop
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
    }
}
