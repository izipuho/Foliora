import CoreGraphics
import Testing
import UIKit
@testable import Foliora_Bells

@MainActor
struct BellPhotoAnalysisIncrementalTests {
    @Test
    func addedPhotoIsAnalyzedWithoutReprocessingInitialPhotos() async {
        let service = BellIncrementalRecordingPhotoAnalysisService()
        let controller = BellPhotoAnalysisController(
            service: service,
            semanticExtractor: BellIncrementalSemanticExtractor(),
            mapper: DefaultBellPhotoSuggestionMapper()
        )

        controller.analyze(images: [makeImage(), makeImage()])
        await waitUntilAnalysisFinishes(controller)

        #expect(controller.suggestions.title?.value == "2")

        controller.analyzeAddedPhoto(
            assetID: UUID(),
            image: makeImage()
        )
        await waitUntilAnalysisFinishes(controller)

        let batchSizes = await service.recordedBatchSizes()
        #expect(batchSizes == [2, 1])
        #expect(controller.suggestions.title?.value == "3")
    }

    private func waitUntilAnalysisFinishes(_ controller: BellPhotoAnalysisController) async {
        for _ in 0..<500 {
            if !controller.isAnalyzing {
                return
            }
            await Task.yield()
        }

        Issue.record("Bell photo analysis did not finish.")
    }

    private func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
}

private actor BellIncrementalRecordingPhotoAnalysisService: PhotoAnalysisService {
    private var batchSizes: [Int] = []
    private var evidenceIndex = 0

    func analyze(image: CGImage) async -> PhotoAnalysisResult {
        evidenceIndex += 1
        return result(index: evidenceIndex)
    }

    func analyze(images: [CGImage]) async -> MultiPhotoAnalysisResult {
        batchSizes.append(images.count)

        let results = images.map { _ -> PhotoAnalysisResult in
            evidenceIndex += 1
            return result(index: evidenceIndex)
        }

        return MultiPhotoAnalysisResult(photos: results)
    }

    func recordedBatchSizes() -> [Int] {
        batchSizes
    }

    private func result(index: Int) -> PhotoAnalysisResult {
        PhotoAnalysisResult(
            mainObjectImage: nil,
            mainObjectRegion: nil,
            main: PhotoAnalysisFeatureScope(
                classifications: [
                    VisionFeature(label: "evidence-\(index)", confidence: 1)
                ],
                recognizedText: [],
                recognizedObjects: [],
                recognizedBarcodes: []
            ),
            background: .empty
        )
    }
}

private struct BellIncrementalSemanticExtractor: SemanticPhotoFeatureExtracting {
    func extractFeatures(from analysis: PhotoAnalysisResult) async -> SemanticPhotoFeatures {
        SemanticPhotoFeatures(
            features: [
                SemanticPhotoFeature(
                    kind: .subject,
                    value: String(analysis.main.classifications.count),
                    confidence: 1,
                    source: .semanticModel
                )
            ]
        )
    }
}
