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
        let visualFeatures = sortedNonEmptyFeatures(
            from: semanticFeatures,
            ofKinds: [.visualKeyword]
        )
        let visualKeywords = makeVisualKeywords(from: visualFeatures)
        let title = sortedNonEmptyFeatures(
            from: semanticFeatures,
            ofKinds: [.subject]
        ).first.map {
            SuggestedFieldValue(value: $0.value, confidence: $0.confidence)
        }
        let suggestedTags = makeSuggestedTags(from: semanticFeatures)
        let tags = suggestedTags.map(\.value)
        let materialFeature = sortedNonEmptyFeatures(
            from: semanticFeatures,
            ofKinds: [.material]
        ).first
        let material = materialFeature.map {
            SuggestedFieldValue(value: mapMaterial($0.value), confidence: $0.confidence)
        }
        let customMaterialName = materialFeature.flatMap { feature -> SuggestedFieldValue<String>? in
            mapMaterial(feature.value) == .other
                ? SuggestedFieldValue(value: feature.value, confidence: feature.confidence)
                : nil
        }
        let condition = sortedNonEmptyFeatures(
            from: semanticFeatures,
            ofKinds: [.condition]
        ).first.flatMap { feature in
            mapCondition(feature.value).map { condition in
                SuggestedFieldValue(value: condition, confidence: feature.confidence)
            }
        }
        let notesFeatures = sortedNonEmptyFeatures(
            from: semanticFeatures,
            ofKinds: [.style, .text]
        )
        let notes = makeNotes(from: notesFeatures)

        return BellPhotoSuggestions(
            tags: tags,
            recognizedText: recognizedText,
            visualKeywords: visualKeywords,
            title: title,
            notes: notes,
            material: material,
            condition: condition,
            customMaterialName: customMaterialName,
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
                VisualKeyword(value: $0.value, confidence: $0.confidence)
            }
    }

    private func makeSuggestedTags(from semanticFeatures: SemanticPhotoFeatures) -> [SuggestedFieldValue<String>] {
        sortedNonEmptyFeatures(
            from: semanticFeatures,
            ofKinds: [.subject, .style, .place, .text, .visualKeyword]
        ).map {
            SuggestedFieldValue(value: $0.value, confidence: $0.confidence)
        }
    }

    private func makeNotes(from features: [SemanticPhotoFeature]) -> SuggestedFieldValue<String>? {
        let values = features.map(\.value)
        guard !values.isEmpty else {
            return nil
        }

        return SuggestedFieldValue(
            value: values.joined(separator: ", "),
            confidence: features.map(\.confidence).max() ?? 0
        )
    }

    private func sortedNonEmptyFeatures(
        from semanticFeatures: SemanticPhotoFeatures,
        ofKinds kinds: Set<SemanticPhotoFeatureKind>
    ) -> [SemanticPhotoFeature] {
        semanticFeatures.features
            .compactMap { feature -> SemanticPhotoFeature? in
                let value = feature.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard kinds.contains(feature.kind), !value.isEmpty else {
                    return nil
                }

                return SemanticPhotoFeature(
                    kind: feature.kind,
                    value: value,
                    confidence: feature.confidence,
                    source: feature.source
                )
            }
            .sorted { $0.confidence > $1.confidence }
    }

    private func mapMaterial(_ value: String) -> BellMaterial {
        switch normalizedEnumValue(value) {
        case BellMaterial.metall.rawValue, "metal":
            return .metall
        case BellMaterial.brass.rawValue:
            return .brass
        case BellMaterial.bronze.rawValue:
            return .bronze
        case BellMaterial.silver.rawValue:
            return .silver
        case BellMaterial.gold.rawValue:
            return .gold
        case BellMaterial.ceramic.rawValue:
            return .ceramic
        case BellMaterial.porcelain.rawValue:
            return .porcelain
        case BellMaterial.glass.rawValue:
            return .glass
        case BellMaterial.wood.rawValue:
            return .wood
        default:
            return .other
        }
    }

    private func mapCondition(_ value: String) -> ItemCondition? {
        let normalizedValue = normalizedEnumValue(value)

        return ItemCondition.allCases.first {
            normalizedEnumValue($0.rawValue) == normalizedValue
                || normalizedEnumValue(String(describing: $0)) == normalizedValue
            }
    }

    private func normalizedEnumValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
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
