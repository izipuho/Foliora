import Foundation
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

struct BellPhotoAnalysisResult: Sendable {
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
        tags: [NormalizedVisionTag],
        recognizedText: [RecognizedTextFeature],
        visualKeywords: [VisualKeyword],
        language: BellAnalysisLanguage
    ) async -> BellPhotoSemanticSummary?
}

protocol BellTitleGenerating: Sendable {
    func generateTitle(
        from tags: [NormalizedVisionTag],
        recognizedText: [RecognizedTextFeature],
        visualKeywords: [VisualKeyword]
    ) async -> SuggestedFieldValue<String>?
}

struct DefaultBellPhotoSuggestionMapper: BellPhotoSuggestionMapping {
    private let semanticInferer: any BellSemanticInferring
    private let titleGenerator: any BellTitleGenerating
    private let language: BellAnalysisLanguage

    init(
        semanticInferer: any BellSemanticInferring = FoundationModelBellSemanticInferer(),
        titleGenerator: any BellTitleGenerating = FoundationModelBellTitleGenerator(),
        language: BellAnalysisLanguage = .current
    ) {
        self.semanticInferer = semanticInferer
        self.titleGenerator = titleGenerator
        self.language = language
    }

    func map(analysis: PhotoAnalysisResult) async -> BellPhotoAnalysisResult {
        let tags = analysis.tags
        let recognizedText = analysis.recognizedText
        let visualKeywords = analysis.visualKeywords
        let semanticSummary = await semanticInferer.infer(
            tags: tags,
            recognizedText: recognizedText,
            visualKeywords: visualKeywords,
            language: language
        )
        let titleSuggestion = await makeTitleSuggestion(
            from: tags,
            recognizedText: recognizedText,
            visualKeywords: visualKeywords,
            semanticSummary: semanticSummary
        )
        let notesSuggestion = makeNotesSuggestion(
            from: tags,
            visualKeywords: visualKeywords,
            titleSuggestion: titleSuggestion,
            semanticSummary: semanticSummary
        )
        let materialSuggestion = makeMaterialSuggestion(
            from: tags,
            recognizedText: recognizedText,
            semanticSummary: semanticSummary
        )
        let conditionSuggestion = makeConditionSuggestion(from: tags, semanticSummary: semanticSummary)
        let customMaterialSuggestion = makeCustomMaterialSuggestion(
            from: tags,
            recognizedText: recognizedText,
            materialSuggestion: materialSuggestion
        )
        let suggestedTags = makeSuggestedTags(
            from: tags,
            visualKeywords: visualKeywords,
            materialSuggestion: materialSuggestion,
            semanticSummary: semanticSummary
        )

        return BellPhotoAnalysisResult(
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

    private func makeTitleSuggestion(
        from tags: [NormalizedVisionTag],
        recognizedText: [RecognizedTextFeature],
        visualKeywords: [VisualKeyword],
        semanticSummary: BellPhotoSemanticSummary?
    ) async -> SuggestedFieldValue<String>? {
        if let semanticTitle = semanticSummary?.title?.nilIfBlank {
            return SuggestedFieldValue(value: semanticTitle, confidence: semanticSummary?.confidence ?? 0.82)
        }

        let filteredRecognizedText = titleRelevantText(from: recognizedText)

        if let generated = await titleGenerator.generateTitle(
            from: tags,
            recognizedText: filteredRecognizedText,
            visualKeywords: visualKeywords
        ) {
            return generated
        }

        return SuggestedFieldValue(
            value: heuristicTitle(from: tags, recognizedText: filteredRecognizedText, visualKeywords: visualKeywords),
            confidence: tags.isEmpty && filteredRecognizedText.isEmpty ? 0.35 : 0.56
        )
    }

    private func makeNotesSuggestion(
        from tags: [NormalizedVisionTag],
        visualKeywords: [VisualKeyword],
        titleSuggestion: SuggestedFieldValue<String>?,
        semanticSummary: BellPhotoSemanticSummary?
    ) -> SuggestedFieldValue<String>? {
        if let semanticNotes = semanticSummary?.notes?.nilIfBlank {
            return SuggestedFieldValue(value: semanticNotes, confidence: semanticSummary?.confidence ?? 0.78)
        }

        let materialName = inferredMaterialLabel(from: tags)
        let subjectName = preferredSubjectWord(from: visualKeywords)

        let text: String
        switch (language, materialName, subjectName) {
        case (.russian, let material?, let subject?):
            text = "\(material) колокольчик в виде \(language.objectCase(of: subject))."
        case (.russian, let material?, nil):
            text = "\(material) декоративный колокольчик."
        case (.russian, nil, let subject?):
            text = "Декоративный колокольчик в виде \(language.objectCase(of: subject))."
        case (.russian, nil, nil):
            text = "Декоративный колокольчик."
        case (.english, let material?, let subject?):
            text = "\(material) bell shaped like a \(subject.lowercased())."
        case (.english, let material?, nil):
            text = "Decorative \(material.lowercased()) bell."
        case (.english, nil, let subject?):
            text = "Decorative bell shaped like a \(subject.lowercased())."
        case (.english, nil, nil):
            text = "Decorative bell."
        }

        return SuggestedFieldValue(value: text, confidence: titleSuggestion?.confidence ?? 0.58)
    }

    private func makeMaterialSuggestion(
        from tags: [NormalizedVisionTag],
        recognizedText: [RecognizedTextFeature],
        semanticSummary: BellPhotoSemanticSummary?
    ) -> SuggestedFieldValue<BellMaterial>? {
        if let semanticMaterial = material(from: semanticSummary?.material) {
            return SuggestedFieldValue(value: semanticMaterial, confidence: semanticSummary?.confidence ?? 0.78)
        }

        if let brassText = textConfidence(matchingAny: ["brass", "латун"], in: recognizedText) {
            return SuggestedFieldValue(value: .brass, confidence: brassText)
        }
        if let bronzeText = textConfidence(matchingAny: ["bronze", "бронз"], in: recognizedText) {
            return SuggestedFieldValue(value: .bronze, confidence: bronzeText)
        }
        if let porcelainText = textConfidence(matchingAny: ["porcelain", "фарфор"], in: recognizedText) {
            return SuggestedFieldValue(value: .porcelain, confidence: porcelainText)
        }
        if let ceramicText = textConfidence(matchingAny: ["ceramic", "керами"], in: recognizedText) {
            return SuggestedFieldValue(value: .ceramic, confidence: ceramicText)
        }
        if let glassText = textConfidence(matchingAny: ["glass", "crystal", "стекл", "хруст"], in: recognizedText) {
            return SuggestedFieldValue(value: .glass, confidence: glassText)
        }
        if let woodText = textConfidence(matchingAny: ["wood", "дерев"], in: recognizedText) {
            return SuggestedFieldValue(value: .wood, confidence: woodText)
        }
        if let silverText = textConfidence(matchingAny: ["silver", "сереб"], in: recognizedText) {
            return SuggestedFieldValue(value: .silver, confidence: silverText)
        }

        if let brass = confidence(for: .brass, in: tags) {
            return SuggestedFieldValue(value: .brass, confidence: brass)
        }
        if let bronze = confidence(for: .bronze, in: tags) {
            return SuggestedFieldValue(value: .bronze, confidence: bronze)
        }
        if let porcelain = confidence(for: .porcelain, in: tags) {
            return SuggestedFieldValue(value: .porcelain, confidence: porcelain)
        }
        if let ceramic = confidence(for: .ceramic, in: tags) {
            return SuggestedFieldValue(value: .ceramic, confidence: ceramic)
        }
        if let glass = confidence(for: .glass, in: tags) {
            return SuggestedFieldValue(value: .glass, confidence: glass)
        }
        if let wood = confidence(for: .wood, in: tags) {
            return SuggestedFieldValue(value: .wood, confidence: wood)
        }
        if let silver = confidence(for: .silver, in: tags) {
            return SuggestedFieldValue(value: .silver, confidence: silver)
        }

        if tags.contains(where: { $0.tag == .decorative }) && !tags.contains(where: { $0.tag == .metal }) {
            return SuggestedFieldValue(value: .ceramic, confidence: 0.38)
        }
        if let stone = confidence(for: .stone, in: tags) {
            return SuggestedFieldValue(value: .other, confidence: stone)
        }
        if let plastic = confidence(for: .plastic, in: tags) {
            return SuggestedFieldValue(value: .other, confidence: plastic)
        }

        return nil
    }

    private func makeCustomMaterialSuggestion(
        from tags: [NormalizedVisionTag],
        recognizedText: [RecognizedTextFeature],
        materialSuggestion: SuggestedFieldValue<BellMaterial>?
    ) -> SuggestedFieldValue<String>? {
        guard materialSuggestion?.value == .other else { return nil }

        if let stoneText = textConfidence(matchingAny: ["stone", "marble", "кам", "мрамор"], in: recognizedText) {
            return SuggestedFieldValue(value: "Stone", confidence: stoneText)
        }
        if let plasticText = textConfidence(matchingAny: ["plastic", "polymer", "resin", "пласт", "полимер", "смола"], in: recognizedText) {
            return SuggestedFieldValue(value: "Plastic", confidence: plasticText)
        }
        if let stone = confidence(for: .stone, in: tags) {
            return SuggestedFieldValue(value: "Stone", confidence: stone)
        }
        if let plastic = confidence(for: .plastic, in: tags) {
            return SuggestedFieldValue(value: "Plastic", confidence: plastic)
        }

        return nil
    }

    private func makeConditionSuggestion(
        from tags: [NormalizedVisionTag],
        semanticSummary: BellPhotoSemanticSummary?
    ) -> SuggestedFieldValue<ItemCondition>? {
        if let semanticCondition = condition(from: semanticSummary?.condition) {
            return SuggestedFieldValue(value: semanticCondition, confidence: semanticSummary?.confidence ?? 0.74)
        }

        if let damaged = confidence(for: .damaged, in: tags), damaged >= 0.70 {
            return SuggestedFieldValue(value: .damaged, confidence: damaged)
        }
        if let worn = confidence(for: .worn, in: tags), worn >= 0.62 {
            return SuggestedFieldValue(value: .worn, confidence: worn)
        }

        let antique = confidence(for: .antique, in: tags) ?? 0
        let vintage = confidence(for: .vintage, in: tags) ?? 0
        if max(antique, vintage) >= 0.66 {
            return SuggestedFieldValue(value: .worn, confidence: max(antique, vintage))
        }

        return SuggestedFieldValue(value: .good, confidence: 0.55)
    }

    private func heuristicTitle(
        from tags: [NormalizedVisionTag],
        recognizedText: [RecognizedTextFeature],
        visualKeywords: [VisualKeyword]
    ) -> String {
        var words: [String] = []

        if let inscriptionTitle = inscriptionTitleCandidate(from: recognizedText) {
            return inscriptionTitle
        }

        if tags.contains(where: { $0.tag == .decorative }) {
            words.append(language.decorativeWord)
        } else if tags.contains(where: { $0.tag == .antique || $0.tag == .vintage }) {
            words.append(language.vintageWord)
        }

        if let materialWord = inferredMaterialLabel(from: tags) {
            words.append(materialWord)
        }

        if let subjectWord = preferredSubjectWord(from: visualKeywords) {
            words.append(subjectWord)
        }

        words.append(language.bellWord)
        return words.prefix(5).joined(separator: " ")
    }

    private func confidence(for tag: PhotoSemanticTag, in tags: [NormalizedVisionTag]) -> Double? {
        tags.first(where: { $0.tag == tag })?.confidence
    }

    private func textConfidence(matchingAny needles: [String], in recognizedText: [RecognizedTextFeature]) -> Double? {
        recognizedText
            .filter { feature in
                let haystack = feature.text.lowercased()
                return feature.confidence >= 0.68 && needles.contains(where: { haystack.contains($0) })
            }
            .map(\.confidence)
            .max()
    }

    private func titleRelevantText(from recognizedText: [RecognizedTextFeature]) -> [RecognizedTextFeature] {
        let titleKeywords = [
            "bell", "handbell", "cowbell",
            "колокол", "колоколь",
            "brass", "bronze", "ceramic", "porcelain", "glass", "wood", "silver",
            "латун", "бронз", "керами", "фарфор", "стекл", "хруст", "дерев", "сереб"
        ]

        return recognizedText.filter { feature in
            guard feature.confidence >= 0.72 else { return false }
            let text = feature.text.lowercased()
            return titleKeywords.contains(where: { text.contains($0) })
        }
    }

    private func inscriptionTitleCandidate(from recognizedText: [RecognizedTextFeature]) -> String? {
        recognizedText
            .filter { $0.confidence >= 0.82 }
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { text in
                let words = text.split(whereSeparator: \.isWhitespace)
                let lowered = text.lowercased()
                let containsKnownWord =
                    lowered.contains("bell") ||
                    lowered.contains("колокол") ||
                    lowered.contains("колоколь") ||
                    lowered.contains("brass") ||
                    lowered.contains("bronze") ||
                    lowered.contains("ceramic") ||
                    lowered.contains("porcelain") ||
                    lowered.contains("glass")

                let digits = text.unicodeScalars.filter(CharacterSet.decimalDigits.contains)
                return !text.isEmpty &&
                    words.count <= 4 &&
                    text.rangeOfCharacter(from: .letters) != nil &&
                    digits.isEmpty &&
                    containsKnownWord
            }
    }

    private func preferredSubjectWord(from visualKeywords: [VisualKeyword]) -> String? {
        visualKeywords
            .filter { $0.confidence >= 0.28 }
            .map(\.value)
            .compactMap { keyword in
                switch keyword {
                case "hedgehog": return language.subjectWordHedgehog
                case "owl": return language.subjectWordOwl
                case "bird": return language.subjectWordBird
                case "cat": return language.subjectWordCat
                case "dog": return language.subjectWordDog
                case "animal": return language.subjectWordAnimal
                default: return nil
                }
            }
            .first
    }

    private func makeSuggestedTags(
        from tags: [NormalizedVisionTag],
        visualKeywords: [VisualKeyword],
        materialSuggestion: SuggestedFieldValue<BellMaterial>?,
        semanticSummary: BellPhotoSemanticSummary?
    ) -> [SuggestedFieldValue<String>] {
        var suggestions: [SuggestedFieldValue<String>] = []

        if let semanticTags = semanticSummary?.tags, !semanticTags.isEmpty {
            suggestions.append(contentsOf: semanticTags.compactMap {
                guard let value = $0.nilIfBlank else { return nil }
                return SuggestedFieldValue(value: value, confidence: semanticSummary?.confidence ?? 0.76)
            })
        }

        if tags.contains(where: { $0.tag == .decorative }) {
            suggestions.append(SuggestedFieldValue(value: language.tagDecorative, confidence: 0.72))
        }

        for keyword in visualKeywords.prefix(3) where keyword.confidence >= 0.28 {
            switch keyword.value {
            case "hedgehog", "owl", "bird", "cat", "dog", "animal", "figurine":
                suggestions.append(SuggestedFieldValue(value: localizedTagValue(for: keyword.value), confidence: keyword.confidence))
            default:
                break
            }
        }

        if let materialSuggestion {
            switch materialSuggestion.value {
            case .ceramic:
                suggestions.append(SuggestedFieldValue(value: language.tagCeramic, confidence: materialSuggestion.confidence))
            case .porcelain:
                suggestions.append(SuggestedFieldValue(value: language.tagPorcelain, confidence: materialSuggestion.confidence))
            case .glass:
                suggestions.append(SuggestedFieldValue(value: language.tagGlass, confidence: materialSuggestion.confidence))
            case .wood:
                suggestions.append(SuggestedFieldValue(value: language.tagWood, confidence: materialSuggestion.confidence))
            default:
                break
            }
        }

        var seen = Set<String>()
        return suggestions.filter { seen.insert($0.value.lowercased()).inserted }
    }

    private func localizedTagValue(for keyword: String) -> String {
        switch keyword {
        case "hedgehog": return language.tagHedgehog
        case "owl": return language.tagOwl
        case "bird": return language.tagBird
        case "cat": return language.tagCat
        case "dog": return language.tagDog
        case "animal": return language.tagAnimal
        case "figurine": return language.tagFigurine
        default: return keyword
        }
    }

    private func inferredMaterialLabel(from tags: [NormalizedVisionTag]) -> String? {
        if tags.contains(where: { $0.tag == .brass }) { return language.materialBrass }
        if tags.contains(where: { $0.tag == .bronze }) { return language.materialBronze }
        if tags.contains(where: { $0.tag == .porcelain }) { return language.materialPorcelain }
        if tags.contains(where: { $0.tag == .ceramic }) { return language.materialCeramic }
        if tags.contains(where: { $0.tag == .glass }) { return language.materialGlass }
        if tags.contains(where: { $0.tag == .wood }) { return language.materialWood }
        if tags.contains(where: { $0.tag == .silver }) { return language.materialSilver }
        if tags.contains(where: { $0.tag == .decorative }) && !tags.contains(where: { $0.tag == .metal }) {
            return language.materialCeramic
        }
        return nil
    }

    private func material(from rawValue: String?) -> BellMaterial? {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "brass": return .brass
        case "bronze": return .bronze
        case "ceramic": return .ceramic
        case "porcelain": return .porcelain
        case "glass": return .glass
        case "wood": return .wood
        case "silver": return .silver
        case "other": return .other
        default: return nil
        }
    }

    private func condition(from rawValue: String?) -> ItemCondition? {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mint": return .mint
        case "good": return .good
        case "worn": return .worn
        case "damaged": return .damaged
        case "needsrestoration": return .needsRestoration
        case "needs_restoration": return .needsRestoration
        default: return nil
        }
    }
}

struct BellPhotoSemanticSummary: Codable, Sendable {
    let title: String?
    let notes: String?
    let material: String?
    let condition: String?
    let tags: [String]
    let confidence: Double

    init(
        title: String?,
        notes: String?,
        material: String?,
        condition: String?,
        tags: [String],
        confidence: Double
    ) {
        self.title = title
        self.notes = notes
        self.material = material
        self.condition = condition
        self.tags = tags
        self.confidence = confidence
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case notes
        case material
        case condition
        case tags
        case confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        material = try container.decodeIfPresent(String.self, forKey: .material)
        condition = try container.decodeIfPresent(String.self, forKey: .condition)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.72
    }
}

struct FoundationModelBellSemanticInferer: BellSemanticInferring {
    func infer(
        tags: [NormalizedVisionTag],
        recognizedText: [RecognizedTextFeature],
        visualKeywords: [VisualKeyword],
        language: BellAnalysisLanguage
    ) async -> BellPhotoSemanticSummary? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let tagList = tags.map { "\($0.tag.rawValue):\($0.confidence)" }.joined(separator: ", ")
            let textList = recognizedText.map { "\($0.text):\($0.confidence)" }.joined(separator: ", ")
            let keywordList = visualKeywords.map { "\($0.value):\($0.confidence)" }.joined(separator: ", ")

            let session = LanguageModelSession(
                instructions: """
                You infer structured semantic suggestions for a bell photo.
                Output strictly valid JSON with keys:
                title, notes, material, condition, tags, confidence.
                Constraints:
                - title and notes must be in \(language.outputLanguageName)
                - title must be specific, concise, and useful for a collector
                - avoid generic outputs like "bell", "decorative bell", "figurine bell" unless no better specificity exists
                - prefer concrete visible subject matter when supported by the signals
                - material must be one of: brass, bronze, ceramic, porcelain, glass, wood, silver, other, or null
                - condition must be one of: mint, good, worn, damaged, needsRestoration, or null
                - tags must be short user-facing tags in \(language.outputLanguageName)
                - do not invent country, city, year, brand, or provenance
                - if certainty is low for a field, return null or omit specificity
                """
            )

            do {
                let response = try await session.respond(
                    to: """
                    Normalized tags: \(tagList)
                    Recognized text: \(textList)
                    Visual keywords: \(keywordList)
                    Return only JSON.
                    """
                )

                guard let json = extractJSONObject(from: response.content),
                      let data = json.data(using: .utf8) else {
                    return nil
                }

                let decoder = JSONDecoder()
                return try decoder.decode(BellPhotoSemanticSummary.self, from: data)
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
}

struct FoundationModelBellTitleGenerator: BellTitleGenerating {
    func generateTitle(
        from tags: [NormalizedVisionTag],
        recognizedText: [RecognizedTextFeature],
        visualKeywords: [VisualKeyword]
    ) async -> SuggestedFieldValue<String>? {
        guard !tags.isEmpty || !recognizedText.isEmpty || !visualKeywords.isEmpty else {
            return SuggestedFieldValue(value: "Bell", confidence: 0.35)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let tagList = tags.map(\.tag.rawValue).joined(separator: ", ")
            let textList = recognizedText.map(\.text).joined(separator: ", ")
            let keywordList = visualKeywords.map(\.value).joined(separator: ", ")
            let session = LanguageModelSession(
                instructions: """
                You generate short, generic bell titles.
                Keep output between 2 and 4 words, with a hard maximum of 5 words.
                You may use recognized inscription text only when it is clearly generic and short.
                Prefer concrete decorative subject words like hedgehog or owl when they are present.
                Do not mention country, city, year, brand, maker, or speculative facts.
                Output must be in \(BellAnalysisLanguage.current.outputLanguageName).
                Return only the title text.
                """
            )

            do {
                let response = try await session.respond(
                    to: "Vision tags: \(tagList). Recognized text: \(textList). Visual keywords: \(keywordList). Generate one concise human-readable title for a bell."
                )
                let sanitized = sanitizeTitle(response.content)
                return SuggestedFieldValue(value: sanitized, confidence: 0.74)
            } catch {
                return nil
            }
        }
        #endif

        return nil
    }

    private func sanitizeTitle(_ raw: String) -> String {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))

        let collapsed = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .prefix(5)
            .joined(separator: " ")

        return collapsed.isEmpty ? "Bell" : collapsed
    }
}

enum BellAnalysisLanguage: Sendable {
    case english
    case russian

    static var current: BellAnalysisLanguage {
        let identifier = Locale.preferredLanguages.first?.lowercased() ?? ""
        return identifier.hasPrefix("ru") ? .russian : .english
    }

    var outputLanguageName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Russian"
        }
    }

    var bellWord: String { self == .russian ? "колокольчик" : "Bell" }
    var decorativeWord: String { self == .russian ? "Декоративный" : "Decorative" }
    var vintageWord: String { self == .russian ? "Винтажный" : "Vintage" }

    var materialBrass: String { self == .russian ? "Латунный" : "Brass" }
    var materialBronze: String { self == .russian ? "Бронзовый" : "Bronze" }
    var materialCeramic: String { self == .russian ? "Керамический" : "Ceramic" }
    var materialPorcelain: String { self == .russian ? "Фарфоровый" : "Porcelain" }
    var materialGlass: String { self == .russian ? "Стеклянный" : "Glass" }
    var materialWood: String { self == .russian ? "Деревянный" : "Wooden" }
    var materialSilver: String { self == .russian ? "Серебряный" : "Silver" }

    var subjectWordHedgehog: String { self == .russian ? "Ёжик" : "Hedgehog" }
    var subjectWordOwl: String { self == .russian ? "Сова" : "Owl" }
    var subjectWordBird: String { self == .russian ? "Птица" : "Bird" }
    var subjectWordCat: String { self == .russian ? "Кот" : "Cat" }
    var subjectWordDog: String { self == .russian ? "Собака" : "Dog" }
    var subjectWordFigurine: String { self == .russian ? "Фигурка" : "Figurine" }
    var subjectWordAnimal: String { self == .russian ? "Животное" : "Animal" }

    var tagDecorative: String { self == .russian ? "декоративный" : "decorative" }
    var tagCeramic: String { self == .russian ? "керамика" : "ceramic" }
    var tagPorcelain: String { self == .russian ? "фарфор" : "porcelain" }
    var tagGlass: String { self == .russian ? "стекло" : "glass" }
    var tagWood: String { self == .russian ? "дерево" : "wood" }
    var tagHedgehog: String { self == .russian ? "ежик" : "hedgehog" }
    var tagOwl: String { self == .russian ? "сова" : "owl" }
    var tagBird: String { self == .russian ? "птица" : "bird" }
    var tagCat: String { self == .russian ? "кот" : "cat" }
    var tagDog: String { self == .russian ? "собака" : "dog" }
    var tagAnimal: String { self == .russian ? "животное" : "animal" }
    var tagFigurine: String { self == .russian ? "фигурка" : "figurine" }

    func objectCase(of subject: String) -> String {
        switch (self, subject) {
        case (.russian, "Ёжик"): return "ёжика"
        case (.russian, "Сова"): return "совы"
        case (.russian, "Птица"): return "птицы"
        case (.russian, "Кот"): return "кота"
        case (.russian, "Собака"): return "собаки"
        case (.russian, "Фигурка"): return "фигурки"
        case (.russian, "Животное"): return "животного"
        default: return subject.lowercased()
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
