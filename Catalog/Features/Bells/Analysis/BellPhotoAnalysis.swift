import Foundation
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

struct BellPhotoAnalysisResult: Sendable {
    let visionFeatures: [VisionFeature]
    let tags: [NormalizedVisionTag]
    let recognizedText: [RecognizedTextFeature]
    let visualKeywords: [VisualKeyword]
    let title: SuggestedFieldValue<String>?
    let notes: SuggestedFieldValue<String>?
    let material: SuggestedFieldValue<BellMaterial>?
    let condition: SuggestedFieldValue<ItemCondition>?
    let customMaterialName: SuggestedFieldValue<String>?
    let suggestedTags: [SuggestedFieldValue<String>]

    static let empty = BellPhotoAnalysisResult(
        visionFeatures: [],
        tags: [],
        recognizedText: [],
        visualKeywords: [],
        title: nil,
        notes: nil,
        material: nil,
        condition: nil,
        customMaterialName: nil,
        suggestedTags: []
    )

    var hasSuggestions: Bool {
        !recognizedText.isEmpty || !visualKeywords.isEmpty || title != nil || notes != nil || material != nil || condition != nil || customMaterialName != nil || !suggestedTags.isEmpty
    }
}

protocol BellPhotoSuggestionMapping: Sendable {
    func map(analysis: PhotoAnalysisResult) async -> BellPhotoAnalysisResult
}

protocol BellSemanticInferring: Sendable {
    func infer(
        visionFeatures: [VisionFeature],
        tags: [NormalizedVisionTag],
        recognizedText: [RecognizedTextFeature],
        visualKeywords: [VisualKeyword],
        language: BellAnalysisLanguage
    ) async -> BellPhotoSemanticSummary?
}

struct DefaultBellPhotoSuggestionMapper: BellPhotoSuggestionMapping {
    private let semanticInferer: any BellSemanticInferring
    private let language: BellAnalysisLanguage

    init(
        semanticInferer: any BellSemanticInferring = FoundationModelBellSemanticInferer(),
        language: BellAnalysisLanguage = .current
    ) {
        self.semanticInferer = semanticInferer
        self.language = language
    }

    func map(analysis: PhotoAnalysisResult) async -> BellPhotoAnalysisResult {
        let visionFeatures = analysis.visionFeatures
        let tags = analysis.tags
        let recognizedText = analysis.recognizedText
        let visualKeywords = analysis.visualKeywords
        let semanticSummary = await semanticInferer.infer(
            visionFeatures: visionFeatures,
            tags: tags,
            recognizedText: recognizedText,
            visualKeywords: visualKeywords,
            language: language
        )
        let titleSuggestion = makeTitleSuggestion(from: semanticSummary)
        let notesSuggestion = makeNotesSuggestion(from: semanticSummary)
        let materialSuggestion = makeMaterialSuggestion(from: semanticSummary)
        let conditionSuggestion = makeConditionSuggestion(from: semanticSummary)
        let customMaterialSuggestion = makeCustomMaterialSuggestion(from: semanticSummary, materialSuggestion: materialSuggestion)
        let suggestedTags = makeSuggestedTags(from: semanticSummary)

        return BellPhotoAnalysisResult(
            visionFeatures: visionFeatures,
            tags: tags,
            recognizedText: recognizedText,
            visualKeywords: visualKeywords,
            title: titleSuggestion,
            notes: notesSuggestion,
            material: materialSuggestion,
            condition: conditionSuggestion,
            customMaterialName: customMaterialSuggestion,
            suggestedTags: suggestedTags
        )
    }

    private func makeTitleSuggestion(from semanticSummary: BellPhotoSemanticSummary?) -> SuggestedFieldValue<String>? {
        guard let value = semanticSummary?.title?.nilIfBlank else { return nil }
        return SuggestedFieldValue(value: value, confidence: semanticSummary?.confidence ?? 0.82)
    }

    private func makeNotesSuggestion(from semanticSummary: BellPhotoSemanticSummary?) -> SuggestedFieldValue<String>? {
        guard let value = semanticSummary?.notes?.nilIfBlank else { return nil }
        return SuggestedFieldValue(value: value, confidence: semanticSummary?.confidence ?? 0.78)
    }

    private func makeMaterialSuggestion(from semanticSummary: BellPhotoSemanticSummary?) -> SuggestedFieldValue<BellMaterial>? {
        guard let value = material(from: semanticSummary?.material) else { return nil }
        return SuggestedFieldValue(value: value, confidence: semanticSummary?.confidence ?? 0.78)
    }

    private func makeCustomMaterialSuggestion(
        from semanticSummary: BellPhotoSemanticSummary?,
        materialSuggestion: SuggestedFieldValue<BellMaterial>?
    ) -> SuggestedFieldValue<String>? {
        guard materialSuggestion?.value == .other else { return nil }
        guard let value = semanticSummary?.customMaterialName?.nilIfBlank else { return nil }
        return SuggestedFieldValue(value: value, confidence: semanticSummary?.confidence ?? 0.74)
    }

    private func makeConditionSuggestion(from semanticSummary: BellPhotoSemanticSummary?) -> SuggestedFieldValue<ItemCondition>? {
        guard let value = condition(from: semanticSummary?.condition) else { return nil }
        return SuggestedFieldValue(value: value, confidence: semanticSummary?.confidence ?? 0.74)
    }

    private func makeSuggestedTags(from semanticSummary: BellPhotoSemanticSummary?) -> [SuggestedFieldValue<String>] {
        guard let semanticSummary else { return [] }

        var seen = Set<String>()
        return semanticSummary.tags.compactMap { rawTag in
            guard let value = rawTag.nilIfBlank else { return nil }
            let normalized = value.lowercased()
            guard seen.insert(normalized).inserted else { return nil }
            return SuggestedFieldValue(value: value, confidence: semanticSummary.confidence)
        }
    }

    private func material(from rawValue: String?) -> BellMaterial? {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "brass", "латунь", "латунный", "латунная": return .brass
        case "bronze", "бронза", "бронзовый", "бронзовая": return .bronze
        case "ceramic", "керамика", "керамический", "керамическая": return .ceramic
        case "porcelain", "фарфор", "фарфоровый", "фарфоровая": return .porcelain
        case "glass", "стекло", "стеклянный", "стеклянная": return .glass
        case "wood", "дерево", "деревянный", "деревянная": return .wood
        case "silver", "серебро", "серебряный", "серебряная": return .silver
        case "other", "другое", "иной", "неизвестно", "unknown": return .other
        default: return nil
        }
    }

    private func condition(from rawValue: String?) -> ItemCondition? {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mint", "идеальное", "идеальный", "отличное", "отличный": return .mint
        case "good", "хорошее", "хороший": return .good
        case "worn", "изношенное", "изношенный", "потертое", "потертый": return .worn
        case "damaged", "поврежденное", "поврежденный", "сломанное", "сломанный": return .damaged
        case "needsrestoration", "needs_restoration", "требует реставрации", "реставрация": return .needsRestoration
        default: return nil
        }
    }
}

struct BellPhotoSemanticSummary: Codable, Sendable {
    let title: String?
    let notes: String?
    let material: String?
    let customMaterialName: String?
    let condition: String?
    let tags: [String]
    let confidence: Double

    init(
        title: String?,
        notes: String?,
        material: String?,
        customMaterialName: String?,
        condition: String?,
        tags: [String],
        confidence: Double
    ) {
        self.title = title
        self.notes = notes
        self.material = material
        self.customMaterialName = customMaterialName
        self.condition = condition
        self.tags = tags
        self.confidence = confidence
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case notes
        case material
        case customMaterialName
        case condition
        case tags
        case confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        material = try container.decodeIfPresent(String.self, forKey: .material)
        customMaterialName = try container.decodeIfPresent(String.self, forKey: .customMaterialName)
        condition = try container.decodeIfPresent(String.self, forKey: .condition)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.72
    }
}

struct FoundationModelBellSemanticInferer: BellSemanticInferring {
    func infer(
        visionFeatures: [VisionFeature],
        tags: [NormalizedVisionTag],
        recognizedText: [RecognizedTextFeature],
        visualKeywords: [VisualKeyword],
        language: BellAnalysisLanguage
    ) async -> BellPhotoSemanticSummary? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let visionList = visionFeatures.map { "\($0.label):\($0.confidence)" }.joined(separator: ", ")
            let tagList = tags.map { "\($0.tag.rawValue):\($0.confidence)" }.joined(separator: ", ")
            let textList = recognizedText.map { "\($0.text):\($0.confidence)" }.joined(separator: ", ")
            let keywordList = visualKeywords.map { "\($0.value):\($0.confidence)" }.joined(separator: ", ")

            let session = LanguageModelSession(
                instructions: """
                You infer structured semantic suggestions for a bell photo.
                Output strictly valid JSON with keys:
                title, notes, material, customMaterialName, condition, tags, confidence.
                Constraints:
                - title and notes must be in \(language.outputLanguageName)
                - title must be specific, concise, and useful for a collector
                - avoid generic outputs like "bell", "decorative bell", "figurine bell" unless no better specificity exists
                - prefer concrete visible subject matter when supported by the signals
                - material must be one of: brass, bronze, ceramic, porcelain, glass, wood, silver, other, or null
                - customMaterialName is only allowed when material is other; otherwise use null
                - condition must be one of: mint, good, worn, damaged, needsRestoration, or null
                - tags must be short user-facing tags in \(language.outputLanguageName)
                - do not invent country, city, year, brand, or provenance
                - if certainty is low for a field, return null or omit specificity
                """
            )

            do {
                let response = try await session.respond(
                    to: """
                    Raw vision labels: \(visionList)
                    Normalized tags: \(tagList)
                    Recognized text: \(textList)
                    Visual keywords: \(keywordList)
                    Return only JSON.
                    """
                )

                return parseSemanticSummary(from: response.content)
            } catch {
                return nil
            }
        }
        #endif

        return nil
    }

    private func extractJSONObject(from raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}") else {
            return nil
        }

        return String(raw[start...end])
    }

    private func parseSemanticSummary(from raw: String) -> BellPhotoSemanticSummary? {
        guard let json = extractJSONObject(from: raw),
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let title = stringValue(for: ["title", "name"], in: object)
        let notes = stringValue(for: ["notes", "description", "summary"], in: object)
        let material = stringValue(for: ["material"], in: object)
        let customMaterialName = stringValue(for: ["customMaterialName", "custom_material_name"], in: object)
        let condition = stringValue(for: ["condition"], in: object)
        let tags = arrayOfStringsValue(for: ["tags", "keywords"], in: object)
        let confidence = doubleValue(for: ["confidence"], in: object) ?? 0.72

        let summary = BellPhotoSemanticSummary(
            title: title,
            notes: notes,
            material: material,
            customMaterialName: customMaterialName,
            condition: condition,
            tags: tags,
            confidence: confidence
        )

        if title == nil, notes == nil, material == nil, customMaterialName == nil, condition == nil, tags.isEmpty {
            return nil
        }

        return summary
    }

    private func stringValue(for keys: [String], in object: [String: Any]) -> String? {
        for key in keys {
            if let value = object[key] as? String, let normalized = value.nilIfBlank {
                return normalized
            }
        }
        return nil
    }

    private func arrayOfStringsValue(for keys: [String], in object: [String: Any]) -> [String] {
        for key in keys {
            if let values = object[key] as? [String] {
                return values.compactMap(\.nilIfBlank)
            }

            if let value = object[key] as? String {
                return value
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .compactMap(\.nilIfBlank)
            }
        }

        return []
    }

    private func doubleValue(for keys: [String], in object: [String: Any]) -> Double? {
        for key in keys {
            if let value = object[key] as? Double {
                return value
            }
            if let value = object[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = object[key] as? String, let parsed = Double(value) {
                return parsed
            }
        }

        return nil
    }
}

enum BellAnalysisLanguage: Sendable {
    case english
    case russian

    static var current: BellAnalysisLanguage {
        let identifier = Locale.autoupdatingCurrent.identifier.lowercased()
        return identifier.hasPrefix("ru") ? .russian : .english
    }

    var outputLanguageName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Russian"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class BellPhotoAnalysisController: ObservableObject {
    enum Field {
        case title
        case notes
        case material
        case condition
        case customMaterialName
        case suggestedTags
    }

    @Published private(set) var isAnalyzing = false
    @Published private(set) var result: BellPhotoAnalysisResult = .empty

    private let service: any PhotoAnalysisService
    private let mapper: any BellPhotoSuggestionMapping

    init(
        service: any PhotoAnalysisService = DefaultPhotoAnalysisService(),
        mapper: any BellPhotoSuggestionMapping = DefaultBellPhotoSuggestionMapper()
    ) {
        self.service = service
        self.mapper = mapper
    }

    var hasSuggestions: Bool {
        isAnalyzing || result.hasSuggestions
    }

    func analyze(image: UIImage) {
        isAnalyzing = true

        Task {
            let analysis = await service.analyze(image: image)
            let mapped = await mapper.map(analysis: analysis)
            await MainActor.run {
                self.result = mapped
                self.isAnalyzing = false
            }
        }
    }

    func dismiss(_ field: Field) {
        result = BellPhotoAnalysisResult(
            visionFeatures: result.visionFeatures,
            tags: result.tags,
            recognizedText: result.recognizedText,
            visualKeywords: result.visualKeywords,
            title: field == .title ? nil : result.title,
            notes: field == .notes ? nil : result.notes,
            material: field == .material ? nil : result.material,
            condition: field == .condition ? nil : result.condition,
            customMaterialName: field == .customMaterialName ? nil : result.customMaterialName,
            suggestedTags: field == .suggestedTags ? [] : result.suggestedTags
        )
    }

    func clear() {
        result = .empty
        isAnalyzing = false
    }
}
