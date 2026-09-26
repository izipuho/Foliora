import CoreGraphics
import Dispatch
import Foundation
import Testing
import UIKit
@testable import Foliora_Books

@MainActor
struct BookPhotoAnalysisPartialFailureTests {
    @Test
    func continuesWhenOnePhotoOCRFailsAndAnotherProvidesText() async {
        let failure = textRecognitionFailure()
        let analysis = MultiPhotoAnalysisResult(
            photos: [
                photo(failures: [failure]),
                photo(text: [recognizedText("Useful Title")])
            ]
        )
        let controller = BookPhotoAnalysisController(
            service: StaticPhotoAnalysisService(result: analysis),
            identifierExtractor: EmptyBookIdentifierExtractor(),
            bibliographicExtractor: EchoBookBibliographicExtractor()
        )

        controller.analyze(images: [makeImage(), makeImage()])
        await waitUntilAnalysisFinishes(controller)

        #expect(controller.analysisError == nil)
        #expect(controller.photoAnalysisFailures == [failure])
        #expect(controller.suggestions.title?.value == "Useful Title")
    }

    @Test
    func reportsTextRecognitionFailureWhenNoPhotoProvidesOCR() async {
        let failure = textRecognitionFailure()
        let analysis = MultiPhotoAnalysisResult(
            photos: [
                photo(failures: [failure]),
                photo()
            ]
        )

        do {
            _ = try await BookBibliographicExtractor().extract(from: analysis)
            Issue.record("Expected textRecognitionFailed when no photo provides OCR.")
        } catch let error as BookBibliographicExtractionError {
            switch error {
            case .textRecognitionFailed(let reportedFailure):
                #expect(reportedFailure == failure)
            case .modelUnavailable, .unknownModelAvailability:
                Issue.record("Bibliographic extraction reached Foundation Models without usable OCR.")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func timeoutFinishesAnalysisWhenBibliographicExtractorIgnoresCancellation() async {
        let analysis = MultiPhotoAnalysisResult(
            photos: [
                photo(text: [recognizedText("Visible Title")])
            ]
        )
        let controller = BookPhotoAnalysisController(
            service: StaticPhotoAnalysisService(result: analysis),
            identifierExtractor: EmptyBookIdentifierExtractor(),
            bibliographicExtractor: NeverCompletingBookBibliographicExtractor(),
            bibliographicTimeout: .milliseconds(10)
        )

        controller.analyze(images: [makeImage()])
        await withCheckedContinuation { continuation in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                continuation.resume()
            }
        }

        #expect(!controller.isAnalyzing)
        guard let error = controller.analysisError as? BookPhotoAnalysisError else {
            Issue.record("Expected bibliographic timeout.")
            return
        }
        if case .bibliographicTimeout = error {
            // Expected.
        } else {
            Issue.record("Expected bibliographic timeout, got \(error).")
        }
    }

    private func waitUntilAnalysisFinishes(_ controller: BookPhotoAnalysisController) async {
        for _ in 0..<200 where controller.isAnalyzing {
            await Task.yield()
        }
        #expect(!controller.isAnalyzing)
    }

    private func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    private func photo(
        text: [RecognizedTextFeature] = [],
        failures: [PhotoAnalysisFailure] = []
    ) -> PhotoAnalysisResult {
        PhotoAnalysisResult(
            mainObjectImage: nil,
            mainObjectRegion: nil,
            main: PhotoAnalysisFeatureScope(
                classifications: [],
                recognizedText: text,
                recognizedObjects: [],
                recognizedBarcodes: []
            ),
            background: .empty,
            failures: failures
        )
    }

    private func recognizedText(_ value: String) -> RecognizedTextFeature {
        RecognizedTextFeature(
            text: value,
            confidence: 0.9,
            boundingBox: .zero
        )
    }

    private func textRecognitionFailure() -> PhotoAnalysisFailure {
        PhotoAnalysisFailure(
            stage: .textRecognition,
            error: NSError(
                domain: "BookPhotoAnalysisPartialFailureTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "OCR failed"]
            )
        )
    }
}

private struct StaticPhotoAnalysisService: PhotoAnalysisService {
    let result: MultiPhotoAnalysisResult

    func analyze(image: CGImage) async -> PhotoAnalysisResult {
        result.photos.first ?? .empty
    }

    func analyze(images: [CGImage]) async -> MultiPhotoAnalysisResult {
        result
    }
}

private struct EmptyBookIdentifierExtractor: BookIdentifierExtracting {
    nonisolated func extract(
        from analysis: MultiPhotoAnalysisResult
    ) -> [SuggestedFieldValue<BookIdentifier>] {
        []
    }
}

private struct EchoBookBibliographicExtractor: BookBibliographicExtracting {
    func extract(
        from analysis: MultiPhotoAnalysisResult
    ) async throws -> BookBibliographicExtraction {
        let text = analysis.photos
            .flatMap { $0.main.recognizedText }
            .first?.text

        return BookBibliographicExtraction(
            title: text.map { SuggestedFieldValue(value: $0, confidence: 0.9) },
            authors: [],
            publisher: nil,
            publicationYear: nil,
            languageCode: nil,
            series: nil,
            volumeNumber: nil
        )
    }
}

private struct NeverCompletingBookBibliographicExtractor: BookBibliographicExtracting {
    func extract(
        from analysis: MultiPhotoAnalysisResult
    ) async throws -> BookBibliographicExtraction {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                continuation.resume()
            }
        }
        return .empty
    }
}
