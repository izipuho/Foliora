import CoreGraphics
import Testing
@testable import Foliora_Bells

struct BellPhotoAnalysisTests {
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
        text: [RecognizedTextFeature] = []
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
            background: .empty
        )
    }

    private func recognizedText(_ value: String) -> RecognizedTextFeature {
        RecognizedTextFeature(
            text: value,
            confidence: 1,
            boundingBox: .zero
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
