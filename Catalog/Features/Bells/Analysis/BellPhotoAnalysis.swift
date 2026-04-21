import Foundation
import Observation
import UIKit

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
        !recognizedText.isEmpty || !visualKeywords.isEmpty || title != nil || notes != nil || material != nil || condition != nil || customMaterialName != nil || suggestedYear != nil || suggestedGeo != nil || !suggestedTags.isEmpty
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
    func map(analysis: PhotoAnalysisResult) async -> BellPhotoSuggestions
}

protocol BellSemanticInferring: Sendable {
    func infer(
        visionFeatures: [VisionFeature],
        tags: [NormalizedVisionTag],
        recognizedText: [RecognizedTextFeature],
        visualKeywords: [VisualKeyword],
        language: BellAnalysisLanguage
    ) async -> BellSemanticInferenceResult
}

struct BellSemanticInferenceResult: Sendable {
    let summary: BellPhotoSemanticSummary?
    let debugInfo: BellPhotoAnalysisDebugInfo?
}

struct DefaultBellPhotoSuggestionMapper: BellPhotoSuggestionMapping {
    init() {}

    func map(analysis: PhotoAnalysisResult) async -> BellPhotoSuggestions {
        let tags = analysis.tags
        let recognizedText = analysis.recognizedText
        let visualKeywords = analysis.visualKeywords

        return BellPhotoSuggestions(
            tags: tags,
            recognizedText: recognizedText,
            visualKeywords: visualKeywords,
            title: nil,
            notes: nil,
            material: nil,
            condition: nil,
            customMaterialName: nil,
            suggestedYear: analysis.year.map { SuggestedFieldValue(value: $0, confidence: 0.86) },
            suggestedGeo: analysis.geo.map { SuggestedFieldValue(value: $0, confidence: 0.78) },
            suggestedTags: makeSuggestedTags(from: analysis),
            debugInfo: makeDebugInfo(from: analysis)
        )
    }

    private func makeSuggestedTags(from analysis: PhotoAnalysisResult) -> [SuggestedFieldValue<String>] {
        analysis.tags.map { SuggestedFieldValue(value: $0, confidence: 0.7) }
    }

    private func makeDebugInfo(from analysis: PhotoAnalysisResult) -> BellPhotoAnalysisDebugInfo {
        let visionTags = """
        Raw Vision labels:
        \(debugLines(analysis.visionFeatures) { "\($0.label) — \(debugConfidence($0.confidence))" })

        Normalized Vision tags:
        \(debugLines(analysis.normalizedTags) { "\($0.tag.rawValue) — \(debugConfidence($0.confidence))" })

        Visual keywords:
        \(debugLines(analysis.visualKeywords) { "\($0.value) — \(debugConfidence($0.confidence))" })
        """
        let ocrText = debugLines(analysis.recognizedText) { "\"\($0.text)\" — \(debugConfidence($0.confidence))" }
        let input = """
        Tags:
        \(debugLines(analysis.tags) { $0 })

        OCR:
        \(ocrText)
        """
        let output = """
        year: \(analysis.year.map(String.init) ?? "nil")
        geo: \(analysis.geo.map { "\($0.name) (\($0.latitude), \($0.longitude))" } ?? "nil")
        """

        return BellPhotoAnalysisDebugInfo(
            prompt: "Vision + OCR + CLGeocoder pipeline. Foundation Models disabled.",
            input: input,
            output: output,
            visionTags: visionTags,
            ocrText: ocrText
        )
    }

    private func debugLines<Element>(_ values: [Element], line: (Element) -> String) -> String {
        guard !values.isEmpty else { return "none" }
        return values
            .map { "- \(line($0))" }
            .joined(separator: "\n")
    }

    private func debugConfidence(_ confidence: Double) -> String {
        confidence.formatted(.number.precision(.fractionLength(2)))
    }

    private func makeTitleSuggestion(from semanticSummary: BellPhotoSemanticSummary?) -> SuggestedFieldValue<String>? {
        guard let value = semanticSummary?.title?.nilIfBlank else { return nil }
        return SuggestedFieldValue(value: value, confidence: semanticSummary?.confidence ?? 0.82)
    }

    private func makeNotesSuggestion(from semanticSummary: BellPhotoSemanticSummary?) -> SuggestedFieldValue<String>? {
        guard let semanticSummary else { return nil }
        let value = [
            semanticSummary.notes?.nilIfBlank,
            semanticSummary.subject.map { String.localizedStringWithFormat(String(localized: "editor.photo_analysis.subject_format"), $0) },
            semanticSummary.inferredOrigin.map { String.localizedStringWithFormat(String(localized: "editor.photo_analysis.origin_format"), $0) },
            semanticSummary.styleEra.map { String.localizedStringWithFormat(String(localized: "editor.photo_analysis.style_format"), $0) }
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfBlank
        guard let value else { return nil }
        return SuggestedFieldValue(value: value, confidence: semanticSummary.confidence)
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
        let rawTags = semanticSummary.tags + [
            semanticSummary.material,
            semanticSummary.styleEra,
            semanticSummary.subject,
            semanticSummary.inferredOrigin
        ].compactMap { $0 }

        return rawTags.compactMap { rawTag in
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
    let subject: String?
    let inferredOrigin: String?
    let styleEra: String?
    let material: String?
    let customMaterialName: String?
    let condition: String?
    let tags: [String]
    let confidence: Double

    init(
        title: String?,
        notes: String?,
        subject: String?,
        inferredOrigin: String?,
        styleEra: String?,
        material: String?,
        customMaterialName: String?,
        condition: String?,
        tags: [String],
        confidence: Double
    ) {
        self.title = title
        self.notes = notes
        self.subject = subject
        self.inferredOrigin = inferredOrigin
        self.styleEra = styleEra
        self.material = material
        self.customMaterialName = customMaterialName
        self.condition = condition
        self.tags = tags
        self.confidence = confidence
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case notes
        case subject
        case inferredOrigin
        case styleEra
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
        subject = try container.decodeIfPresent(String.self, forKey: .subject)
        inferredOrigin = try container.decodeIfPresent(String.self, forKey: .inferredOrigin)
        styleEra = try container.decodeIfPresent(String.self, forKey: .styleEra)
        material = try container.decodeIfPresent(String.self, forKey: .material)
        customMaterialName = try container.decodeIfPresent(String.self, forKey: .customMaterialName)
        condition = try container.decodeIfPresent(String.self, forKey: .condition)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.72
    }
}

#if false
struct FoundationModelBellSemanticInferer: BellSemanticInferring {
    func infer(
        visionFeatures: [VisionFeature],
        tags: [NormalizedVisionTag],
        recognizedText: [RecognizedTextFeature],
        visualKeywords: [VisualKeyword],
        language: BellAnalysisLanguage
    ) async -> BellSemanticInferenceResult {
        let input = debugInput(
            visionFeatures: visionFeatures,
            tags: tags,
            recognizedText: recognizedText,
            visualKeywords: visualKeywords
        )
        let visionTagsDebug = debugVisionTags(
            visionFeatures: visionFeatures,
            tags: tags,
            visualKeywords: visualKeywords
        )
        let ocrTextDebug = debugOCRText(recognizedText)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let prompt = """
            You are an art historian specializing in campanology and collectible bells.
            Analyze visual signals and OCR inscriptions to create a professional exhibit-card draft.

            Output strictly valid JSON with keys:
            title, subject, material, inferred_origin, style_era, condition, tags, suggested_notes, customMaterialName, confidence.

            Constraints:
            - title, subject, tags, and suggested_notes must be in \(language.outputLanguageName)
            - do not use "Bell" or "Колокольчик" in title when a more specific name is possible
            - if OCR text contains a city, place, or event, title should prefer: [city/event] + [form/character]
            - if the item is figurative, identify the character or animal in subject, e.g. "Lady with basket", "Cat with bow", "Hedgehog figurine"
            - material must be one of: brass, bronze, ceramic, porcelain, glass, wood, silver, other, or null
            - if unsure between ceramic and porcelain, infer from glossy/smooth/fine visual signals; otherwise use lower confidence
            - customMaterialName is only allowed when material is other; otherwise use null
            - condition must be one of: mint, good, worn, damaged, needsRestoration, or null
            - inferred_origin must only use OCR text evidence; never infer country/city/provenance from visual style alone
            - style_era should be one of a concise user-facing style labels such as Vintage, Modern, Souvenir, Religious, Folk, or null
            - tags must include useful material/style/subject/color tags when supported by signals
            - suggested_notes must be one professional sentence about the item's visible appearance
            - if data is weak, lower confidence and leave unsupported fields null; do not invent year, brand, country, city, or provenance
            """

            let session = LanguageModelSession(
                instructions: prompt
            )

            do {
                let response = try await session.respond(to: input)
                let output = response.content

                return BellSemanticInferenceResult(
                    summary: parseSemanticSummary(from: output),
                    debugInfo: BellPhotoAnalysisDebugInfo(
                        prompt: prompt,
                        input: input,
                        output: output,
                        visionTags: visionTagsDebug,
                        ocrText: ocrTextDebug
                    )
                )
            } catch {
                return BellSemanticInferenceResult(
                    summary: nil,
                    debugInfo: BellPhotoAnalysisDebugInfo(
                        prompt: prompt,
                        input: input,
                        output: error.localizedDescription,
                        visionTags: visionTagsDebug,
                        ocrText: ocrTextDebug
                    )
                )
            }
        }
        #endif

        return BellSemanticInferenceResult(
            summary: nil,
            debugInfo: BellPhotoAnalysisDebugInfo(
                prompt: "Foundation Models unavailable",
                input: input,
                output: "No model response",
                visionTags: visionTagsDebug,
                ocrText: ocrTextDebug
            )
        )
    }

    private func debugVisionTags(
        visionFeatures: [VisionFeature],
        tags: [NormalizedVisionTag],
        visualKeywords: [VisualKeyword]
    ) -> String {
        """
        Raw Vision labels:
        \(debugLines(visionFeatures) { "\($0.label) — \(debugConfidence($0.confidence))" })

        Normalized Vision tags:
        \(debugLines(tags) { "\($0.tag.rawValue) — \(debugConfidence($0.confidence))" })

        Visual keywords:
        \(debugLines(visualKeywords) { "\($0.value) — \(debugConfidence($0.confidence))" })
        """
    }

    private func debugOCRText(_ recognizedText: [RecognizedTextFeature]) -> String {
        debugLines(recognizedText) { "\"\($0.text)\" — \(debugConfidence($0.confidence))" }
    }

    private func debugInput(
        visionFeatures: [VisionFeature],
        tags: [NormalizedVisionTag],
        recognizedText: [RecognizedTextFeature],
        visualKeywords: [VisualKeyword]
    ) -> String {
        """
        Raw vision labels (\(visionFeatures.count)):
        \(debugLines(visionFeatures) { "\($0.label) — \(debugConfidence($0.confidence))" })

        Normalized tags (\(tags.count)):
        \(debugLines(tags) { "\($0.tag.rawValue) — \(debugConfidence($0.confidence))" })

        Recognized text / OCR (\(recognizedText.count)):
        \(debugLines(recognizedText) { "\"\($0.text)\" — \(debugConfidence($0.confidence))" })

        Visual keywords (\(visualKeywords.count)):
        \(debugLines(visualKeywords) { "\($0.value) — \(debugConfidence($0.confidence))" })

        JSON field aliases accepted by parser:
        suggested_notes may also be notes; inferred_origin may also be inferredOrigin; style_era may also be styleEra.
        Return only JSON.
        """
    }

    private func debugLines<Element>(_ values: [Element], line: (Element) -> String) -> String {
        guard !values.isEmpty else { return "none" }
        return values
            .map { "- \(line($0))" }
            .joined(separator: "\n")
    }

    private func debugConfidence(_ confidence: Double) -> String {
        confidence.formatted(.number.precision(.fractionLength(2)))
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
        let notes = stringValue(for: ["suggested_notes", "suggestedNotes", "notes", "description", "summary"], in: object)
        let subject = stringValue(for: ["subject", "shape", "character"], in: object)
        let inferredOrigin = stringValue(for: ["inferred_origin", "inferredOrigin", "origin"], in: object)
        let styleEra = stringValue(for: ["style_era", "styleEra", "style", "era"], in: object)
        let material = stringValue(for: ["material"], in: object)
        let customMaterialName = stringValue(for: ["customMaterialName", "custom_material_name"], in: object)
        let condition = stringValue(for: ["condition"], in: object)
        let tags = arrayOfStringsValue(for: ["tags", "keywords"], in: object)
        let confidence = doubleValue(for: ["confidence"], in: object) ?? 0.72

        let summary = BellPhotoSemanticSummary(
            title: title,
            notes: notes,
            subject: subject,
            inferredOrigin: inferredOrigin,
            styleEra: styleEra,
            material: material,
            customMaterialName: customMaterialName,
            condition: condition,
            tags: tags,
            confidence: confidence
        )

        if title == nil, notes == nil, subject == nil, inferredOrigin == nil, styleEra == nil, material == nil, customMaterialName == nil, condition == nil, tags.isEmpty {
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
#endif

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
    private let mapper: any BellPhotoSuggestionMapping

    init(
        service: any PhotoAnalysisService = DefaultPhotoAnalysisService(),
        mapper: any BellPhotoSuggestionMapping = DefaultBellPhotoSuggestionMapper()
    ) {
        self.service = service
        self.mapper = mapper
    }

    var hasSuggestions: Bool {
        isAnalyzing || suggestions.hasSuggestions
    }

    func analyze(image: UIImage) {
        isAnalyzing = true

        Task {
            let analysis = await service.analyze(image: image)
            let mapped = await mapper.map(analysis: analysis)
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
