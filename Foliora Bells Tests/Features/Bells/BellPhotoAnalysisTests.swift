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
    func semanticExtractionDeduplicatesMainEvidenceAcrossPhotos() async {
        let analysis = MultiPhotoAnalysisResult(
            photos: [
                photo(
                    classifications: [
                        VisionFeature(label: "Bell", confidence: 0.6),
                        VisionFeature(label: "ceramic", confidence: 0.7)
                    ],
                    text: [recognizedText("Made in Italy", confidence: 0.5)]
                ),
                photo(
                    classifications: [
                        VisionFeature(label: "bell", confidence: 0.9)
                    ],
                    text: [recognizedText("made in italy", confidence: 0.8)]
                )
            ]
        )
        let extractor = SemanticPhotoFeatureExtractor(
            tagFilter: PassthroughTagFilter(),
            semanticExtractor: EmptySemanticExtractor()
        )

        let result = await extractor.extractFeatures(from: analysis)
        let visualKeywords = result.features(ofKind: .visualKeyword)
        let recognizedText = result.features(ofKind: .recognizedText)

        #expect(visualKeywords.map(\.value) == ["bell", "ceramic"])
        #expect(visualKeywords.first?.confidence == 0.9)
        #expect(recognizedText.map(\.value) == ["made in italy"])
        #expect(recognizedText.first?.confidence == 0.8)
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
    func mapperSuggestsColorFromLocalPixelAnalysisWithoutSemanticFeatures() async {
        let analysis = MultiPhotoAnalysisResult(
            photos: [
                PhotoAnalysisResult(
                    mainObjectImage: nil,
                    mainObjectRegion: nil,
                    main: .empty,
                    background: .empty,
                    colorSamples: [
                        PhotoColorSample(hue: 2, saturation: 0.82, brightness: 0.76, proportion: 0.91)
                    ]
                )
            ]
        )

        let suggestions = await DefaultBellPhotoSuggestionMapper().map(
            analysis: analysis,
            semanticFeatures: .empty
        )

        #expect(suggestions.color?.value == .red)
        #expect(suggestions.color?.confidence == 0.91)
    }

    @Test
    func mapperDoesNotSuggestMulticoloredForSingleColorAcrossPhotos() async {
        let analysis = MultiPhotoAnalysisResult(
            photos: [
                photo(colorSamples: [
                    PhotoColorSample(hue: 2, saturation: 0.82, brightness: 0.76, proportion: 0.72),
                    PhotoColorSample(hue: 8, saturation: 0.55, brightness: 0.48, proportion: 0.20)
                ]),
                photo(colorSamples: [
                    PhotoColorSample(hue: 4, saturation: 0.78, brightness: 0.68, proportion: 0.65),
                    PhotoColorSample(hue: 12, saturation: 0.48, brightness: 0.42, proportion: 0.25)
                ])
            ]
        )

        let suggestions = await DefaultBellPhotoSuggestionMapper().map(
            analysis: analysis,
            semanticFeatures: .empty
        )

        #expect(suggestions.color?.value == .red)
    }

    @Test
    func mapperIgnoresNeutralHighlightsWhenDetectingMulticolored() async {
        let analysis = MultiPhotoAnalysisResult(
            photos: [
                photo(colorSamples: [
                    PhotoColorSample(hue: 42, saturation: 0.72, brightness: 0.72, proportion: 0.55),
                    PhotoColorSample(hue: nil, saturation: 0.05, brightness: 0.98, proportion: 0.28),
                    PhotoColorSample(hue: nil, saturation: 0.08, brightness: 0.12, proportion: 0.17)
                ])
            ]
        )

        let suggestions = await DefaultBellPhotoSuggestionMapper().map(
            analysis: analysis,
            semanticFeatures: .empty
        )

        #expect(suggestions.color?.value == .gold)
    }

    @Test
    func mapperSuggestsMulticoloredForDistinctChromaticRegionsInOnePhoto() async {
        let analysis = MultiPhotoAnalysisResult(
            photos: [
                photo(colorSamples: [
                    PhotoColorSample(hue: 2, saturation: 0.82, brightness: 0.72, proportion: 0.38),
                    PhotoColorSample(hue: 220, saturation: 0.76, brightness: 0.68, proportion: 0.34),
                    PhotoColorSample(hue: nil, saturation: 0.04, brightness: 0.96, proportion: 0.18)
                ])
            ]
        )

        let suggestions = await DefaultBellPhotoSuggestionMapper().map(
            analysis: analysis,
            semanticFeatures: .empty
        )

        #expect(suggestions.color?.value == .multicolored)
    }

    @Test
    func localColorAnalyzerFindsDominantPixelColor() {
        let image = makeSolidImage(red: 1, green: 0, blue: 0)

        let samples = LocalPhotoColorAnalyzer().analyze(image)

        #expect(samples.count == 1)
        #expect(samples.first?.hue == 0)
        #expect(samples.first?.proportion == 1)
    }

    @Test
    func mapperSuggestsColorFromSemanticStyleFeatures() async {
        let suggestions = await DefaultBellPhotoSuggestionMapper().map(
            analysis: MultiPhotoAnalysisResult(photos: []),
            semanticFeatures: SemanticPhotoFeatures(
                features: [
                    SemanticPhotoFeature(
                        kind: .style,
                        value: "blue and white floral pattern",
                        confidence: 0.87,
                        source: .semanticModel
                    )
                ]
            )
        )

        #expect(suggestions.color?.value == .multicolored)
        #expect(suggestions.color?.confidence == 0.87)
    }

    @Test
    func mapperDoesNotInferColorFromMaterialFeatures() async {
        let suggestions = await DefaultBellPhotoSuggestionMapper().map(
            analysis: MultiPhotoAnalysisResult(photos: []),
            semanticFeatures: SemanticPhotoFeatures(
                features: [
                    SemanticPhotoFeature(
                        kind: .material,
                        value: "gold",
                        confidence: 0.99,
                        source: .semanticModel
                    )
                ]
            )
        )

        #expect(suggestions.color == nil)
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
        backgroundText: [RecognizedTextFeature] = [],
        colorSamples: [PhotoColorSample] = []
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
            ),
            colorSamples: colorSamples
        )
    }

    private func recognizedText(
        _ value: String,
        confidence: Double = 1
    ) -> RecognizedTextFeature {
        RecognizedTextFeature(
            text: value,
            confidence: confidence,
            boundingBox: .zero
        )
    }

    private func makeSolidImage(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 32,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        )!
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return context.makeImage()!
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
