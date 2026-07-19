import Foundation
import Observation
import UIKit

struct VisualKeyword: Hashable, Sendable {
    let value: String
    let confidence: Double
}

struct BellPhotoSuggestions: Sendable {
    let tags: [String]
    let recognizedText: [RecognizedTextFeature]
    let visualKeywords: [VisualKeyword]
    let title: SuggestedFieldValue<String>?
    let notes: SuggestedFieldValue<String>?
    let material: SuggestedFieldValue<BellMaterial>?
    let condition: SuggestedFieldValue<ItemCondition>?
    let customMaterialName: SuggestedFieldValue<String>?
    let suggestedYear: SuggestedFieldValue<Int>?
    let suggestedGeo: SuggestedFieldValue<GeoPoint>?
    let suggestedTags: [SuggestedFieldValue<String>]
    let debugInfo: BellPhotoAnalysisDebugInfo?

    static let empty = BellPhotoSuggestions(
        tags: [],
        recognizedText: [],
        visualKeywords: [],
        title: nil,
        notes: nil,
        material: nil,
        condition: nil,
        customMaterialName: nil,
        suggestedYear: nil,
        suggestedGeo: nil,
        suggestedTags: [],
        debugInfo: nil
    )

    var hasSuggestions: Bool {
        !recognizedText.isEmpty
            || !visualKeywords.isEmpty
            || title != nil
            || notes != nil
            || material != nil
            || condition != nil
            || customMaterialName != nil
            || suggestedYear != nil
            || suggestedGeo != nil
            || !suggestedTags.isEmpty
    }
}

struct BellPhotoAnalysisDebugInfo: Sendable {
    let prompt: String
    let input: String
    let output: String
    let visionTags: String
    let ocrText: String

    init(prompt: String, input: String, output: String, visionTags: String = "", ocrText: String = "") {
        self.prompt = prompt
        self.input = input
        self.output = output
        self.visionTags = visionTags
        self.ocrText = ocrText
    }
}

protocol BellPhotoSuggestionMapping: Sendable {
    func map(
        analysis: PhotoAnalysisResult,
        semanticFeatures: SemanticPhotoFeatures
    ) async -> BellPhotoSuggestions
}

struct DefaultBellPhotoSuggestionMapper: BellPhotoSuggestionMapping {
    init() {}

    func map(
        analysis: PhotoAnalysisResult,
        semanticFeatures: SemanticPhotoFeatures
    ) async -> BellPhotoSuggestions {
        let recognizedText = analysis.main.recognizedText
        let visualFeatures = semanticFeatures.rawVisualKeywords
        let visualKeywords = makeVisualKeywords(from: visualFeatures)
        let suggestedTags = visualFeatures.map {
            SuggestedFieldValue(value: $0.label, confidence: $0.confidence)
        }
        let tags = suggestedTags.map(\.value)

        return BellPhotoSuggestions(
            tags: tags,
            recognizedText: recognizedText,
            visualKeywords: visualKeywords,
            title: nil,
            notes: nil,
            material: nil,
            condition: nil,
            customMaterialName: nil,
            suggestedYear: nil,
            suggestedGeo: nil,
            suggestedTags: suggestedTags,
            debugInfo: nil
        )
    }

    private func makeVisualKeywords(from visualFeatures: [SemanticPhotoFeature]) -> [VisualKeyword] {
        visualFeatures
            .filter { $0.confidence >= 0.28 }
            .map {
                VisualKeyword(value: $0.label, confidence: $0.confidence)
            }
    }
}

@MainActor
@Observable
final class BellPhotoAnalysisController {
    enum Field {
        case title
        case notes
        case material
        case condition
        case customMaterialName
        case suggestedYear
        case suggestedGeo
        case suggestedTags
    }

    private(set) var isAnalyzing = false
    private(set) var suggestions: BellPhotoSuggestions = .empty

    private let service: any PhotoAnalysisService
    private let semanticExtractor: any SemanticPhotoFeatureExtracting
    private let mapper: any BellPhotoSuggestionMapping

    init() {
        self.service = DefaultPhotoAnalysisService()
        self.semanticExtractor = SemanticPhotoFeatureExtractor()
        self.mapper = DefaultBellPhotoSuggestionMapper()
    }

    init(
        service: any PhotoAnalysisService,
        semanticExtractor: any SemanticPhotoFeatureExtracting,
        mapper: any BellPhotoSuggestionMapping
    ) {
        self.service = service
        self.semanticExtractor = semanticExtractor
        self.mapper = mapper
    }

    var hasSuggestions: Bool {
        isAnalyzing || suggestions.hasSuggestions
    }

    func analyze(image: UIImage) {
        guard let cgImage = image.cgImage else {
            isAnalyzing = false
            return
        }

        isAnalyzing = true

        Task {
            let analysis = await service.analyze(image: cgImage)
            let semanticFeatures = await semanticExtractor.extractFeatures(from: analysis)
            let mapped = await mapper.map(
                analysis: analysis,
                semanticFeatures: semanticFeatures
            )
            await MainActor.run {
                self.suggestions = mapped
                self.isAnalyzing = false
            }
        }
    }

    func dismiss(_ field: Field) {
        suggestions = BellPhotoSuggestions(
            tags: suggestions.tags,
            recognizedText: suggestions.recognizedText,
            visualKeywords: suggestions.visualKeywords,
            title: field == .title ? nil : suggestions.title,
            notes: field == .notes ? nil : suggestions.notes,
            material: field == .material ? nil : suggestions.material,
            condition: field == .condition ? nil : suggestions.condition,
            customMaterialName: field == .customMaterialName ? nil : suggestions.customMaterialName,
            suggestedYear: field == .suggestedYear ? nil : suggestions.suggestedYear,
            suggestedGeo: field == .suggestedGeo ? nil : suggestions.suggestedGeo,
            suggestedTags: field == .suggestedTags ? [] : suggestions.suggestedTags,
            debugInfo: suggestions.debugInfo
        )
    }

    func clear() {
        suggestions = .empty
        isAnalyzing = false
    }
}
