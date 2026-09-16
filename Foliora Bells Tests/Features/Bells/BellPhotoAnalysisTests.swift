import CoreGraphics
import Testing
@testable import Foliora_Bells

struct BellPhotoAnalysisTests {
    @Test
    func multiPhotoAnalysisPreservesInputOrder() async {
        let service = DelayedPhotoAnalysisService()
        let images = [makeImage(width: 1), makeImage(width: 2)]

        let result = await service.analyze(images: images)

        #expect(result.photos.map { $0.main.classifications.first?.label } == ["1", "2"])
    }

    @Test
    func semanticExtractionCombinesMainEvidenceAcrossPhotos() async {
        let analysis = MultiPhotoAnalysisResult(
            photos: [
                photo(
                    classifications: [VisionFeature(label: "bell", confidence: 0.9)],
                    text: [recognizedText("front")]
                ),
                photo(
                    classifications: [VisionFeature(label: "ceramic", confidence: 0.8)],
                    text: [recognizedText("back")]
                )
            ]
        )
        let extractor = SemanticPhotoFeatureExtractor(
            tagFilter: PassthroughTagFilter(),
            semanticExtractor: EmptySemanticExtractor()
        )

        let result = await extractor.extractFeatures(from: analysis)

        #expect(Set(result.features(ofKind: .visualKeyword).map(\.value)) == ["bell", "ceramic"])
        #expect(Set(result.features(ofKind: .recognizedText).map(\.value)) == ["front", "back"])
    }

    @Test
    func semanticExtractionIgnoresBackgroundEvidenceAcrossPhotos() async {
        let analysis = MultiPhotoAnalysisResult(
            photos: [
                photo(
                    classifications: [VisionFeature(label: "bell", confidence: 0.9)],
                    text: [recognizedText("front")],
                    backgroundClassifications: [VisionFeature(label: "table", confidence: 1)],
                    backgroundText: [recognizedText("receipt")]
                ),
                photo(
                    classifications: [VisionFeature(label: "ceramic", confidence: 0.8)],
                    text: [recognizedText("back")],
                    backgroundClassifications: [VisionFeature(label: "wall", confidence: 1)],
                    backgroundText: [recognizedText("poster")]
                )
            ]
        )
        let extractor = SemanticPhotoFeatureExtractor(
            tagFilter: PassthroughTagFilter(),
            semanticExtractor: EmptySemanticExtractor()
        )

        let result = await extractor.extractFeatures(from: analysis)

        #expect(Set(result.features(ofKind: .visualKeyword).map(\.value)) == ["bell", "ceramic"])
        #expect(Set(result.features(ofKind: .recognizedText).map(\.value)) == ["front", "back"])
    }

    @Test
    func mapperCombinesRecognizedTextAcrossPhotos() async {
        let analysis = MultiPhotoAnalysisResult(
            photos: [
                photo(text: [recognizedText("front")]),
                photo(text: [recognizedText("back")])
            ]
        )

        let suggestions = await DefaultBellPhotoSuggestionMapper().map(
            analysis: analysis,
            semanticFeatures: .empty
        )

        #expect(suggestions.recognizedText.map(\.text) == ["front", "back"])
    }

    private func photo(
        classifications: [VisionFeature] = [],
        text: [RecognizedTextFeature] = [],
        backgroundClassifications: [VisionFeature] = [],
        backgroundText: [RecognizedTextFeature] = []
    ) -> PhotoAnalysisResult {
        PhotoAnalysisResult(
            mainObjectImage: nil,
            mainObjectRegion: nil,
            main: PhotoAnalysisFeatureScope(
                classifications: classifications,
                recognizedText: text,
                recognizedObjects: [],
                recognizedBarcodes: []
            ),
            background: PhotoAnalysisFeatureScope(
                classifications: backgroundClassifications,
                recognizedText: backgroundText,
                recognizedObjects: [],
                recognizedBarcodes: []
            )
        )
    }

    private func recognizedText(_ value: String) -> RecognizedTextFeature {
        RecognizedTextFeature(
            text: value,
            confidence: 1,
            boundingBox: .zero
        )
    }

    private func makeImage(width: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }
}

private struct DelayedPhotoAnalysisService: PhotoAnalysisService {
    func analyze(image: CGImage) async -> PhotoAnalysisResult {
        if image.width == 1 {
            try? await Task.sleep(for: .milliseconds(30))
        }

        return PhotoAnalysisResult(
            mainObjectImage: nil,
            mainObjectRegion: nil,
            main: PhotoAnalysisFeatureScope(
                classifications: [
                    VisionFeature(label: String(image.width), confidence: 1)
                ],
                recognizedText: [],
                recognizedObjects: [],
                recognizedBarcodes: []
            ),
            background: .empty
        )
    }
}

private struct PassthroughTagFilter: SemanticPhotoTagFiltering {
    func filterTags(_ tags: [SemanticPhotoVisualFeature]) async -> [SemanticPhotoVisualFeature] {
        tags
    }
}

private struct EmptySemanticExtractor: SemanticPhotoSemanticExtracting {
    func extractFeatures(from input: SemanticPhotoSemanticInput) async -> SemanticPhotoSemanticOutput {
        .empty
    }
}
