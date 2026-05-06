import Foundation
import UIKit

struct SemanticPhotoFeatures: Sendable {
    let subjects: [SemanticPhotoFeature]
    let materialHints: [SemanticPhotoFeature]
    let conditionHints: [SemanticPhotoFeature]
    let placeHints: [SemanticPhotoFeature]
    let textEntities: [SemanticPhotoFeature]
    let styleHints: [SemanticPhotoFeature]
    let rawVisualKeywords: [SemanticPhotoFeature]
    let rawRecognizedText: [SemanticPhotoFeature]

    static let empty = SemanticPhotoFeatures(
        subjects: [],
        materialHints: [],
        conditionHints: [],
        placeHints: [],
        textEntities: [],
        styleHints: [],
        rawVisualKeywords: [],
        rawRecognizedText: []
    )
}

struct SemanticPhotoFeature: Hashable, Sendable {
    let label: String
    let confidence: Double
    let source: SemanticPhotoFeatureSource
}

enum SemanticPhotoFeatureSource: Hashable, Sendable {
    case vision
    case ocr
    case vlm
}

struct SemanticPhotoVLMInput: Sendable {
    let mainObjectImage: UIImage?
    let allTags: [PhotoTag]
    let recognizedText: [RecognizedTextFeature]
}

struct SemanticPhotoVLMOutput: Sendable {
    let subjects: [SemanticPhotoFeature]
    let materialHints: [SemanticPhotoFeature]
    let conditionHints: [SemanticPhotoFeature]
    let placeHints: [SemanticPhotoFeature]
    let textEntities: [SemanticPhotoFeature]
    let styleHints: [SemanticPhotoFeature]

    static let empty = SemanticPhotoVLMOutput(
        subjects: [],
        materialHints: [],
        conditionHints: [],
        placeHints: [],
        textEntities: [],
        styleHints: []
    )
}

protocol SemanticPhotoVLMExtracting: Sendable {
    func extractFeatures(from input: SemanticPhotoVLMInput) async -> SemanticPhotoVLMOutput
}

protocol SemanticPhotoFeatureExtracting: Sendable {
    func extractFeatures(from analysis: PhotoAnalysisResult) async -> SemanticPhotoFeatures
}

struct SemanticPhotoFeatureExtractor: SemanticPhotoFeatureExtracting {
    private let vlmExtractor: (any SemanticPhotoVLMExtracting)?

    init(vlmExtractor: (any SemanticPhotoVLMExtracting)? = nil) {
        self.vlmExtractor = vlmExtractor
    }

    func extractFeatures(from analysis: PhotoAnalysisResult) async -> SemanticPhotoFeatures {
        let allTags = analysis.main.allTags + analysis.background.allTags
        let recognizedText = analysis.main.recognizedText + analysis.background.recognizedText
        let vlmOutput = await vlmExtractor?.extractFeatures(
            from: SemanticPhotoVLMInput(
                mainObjectImage: analysis.mainObjectImage,
                allTags: allTags,
                recognizedText: recognizedText
            )
        ) ?? .empty

        return SemanticPhotoFeatures(
            subjects: vlmOutput.subjects,
            materialHints: vlmOutput.materialHints,
            conditionHints: vlmOutput.conditionHints,
            placeHints: vlmOutput.placeHints,
            textEntities: vlmOutput.textEntities,
            styleHints: vlmOutput.styleHints,
            rawVisualKeywords: allTags.map {
                SemanticPhotoFeature(
                    label: $0.label,
                    confidence: $0.confidence,
                    source: .vision
                )
            },
            rawRecognizedText: recognizedText.map {
                SemanticPhotoFeature(
                    label: $0.text,
                    confidence: $0.confidence,
                    source: .ocr
                )
            }
        )
    }
}
