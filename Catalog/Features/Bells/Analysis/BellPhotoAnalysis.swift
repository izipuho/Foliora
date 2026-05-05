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
    func map(analysis: PhotoAnalysisResult) async -> BellPhotoSuggestions
}

struct DefaultBellPhotoSuggestionMapper: BellPhotoSuggestionMapping {
    init() {}

    func map(analysis: PhotoAnalysisResult) async -> BellPhotoSuggestions {
        let recognizedText = analysis.main.recognizedText + analysis.background.recognizedText
        let analysisTags = analysis.main.allTags + analysis.background.allTags
        let visualKeywords = makeVisualKeywords(from: analysisTags)
        let year = extractYear(from: recognizedText)
        let tags = makeTags(
            analysisTags: analysisTags,
            recognizedText: recognizedText,
            year: year
        )

        return BellPhotoSuggestions(
            tags: tags,
            recognizedText: recognizedText,
            visualKeywords: visualKeywords,
            title: nil,
            notes: nil,
            material: nil,
            condition: nil,
            customMaterialName: nil,
            suggestedYear: year.map { SuggestedFieldValue(value: $0, confidence: 0.86) },
            suggestedGeo: nil,
            suggestedTags: tags.map { SuggestedFieldValue(value: $0, confidence: 0.7) },
            debugInfo: makeDebugInfo(
                analysis: analysis,
                tags: tags,
                visualKeywords: visualKeywords,
                year: year
            )
        )
    }

    private func makeVisualKeywords(from analysisTags: [PhotoTag]) -> [VisualKeyword] {
        analysisTags
            .filter { $0.confidence >= 0.28 }
            .map { VisualKeyword(value: $0.label, confidence: $0.confidence) }
    }

    private func makeTags(
        analysisTags: [PhotoTag],
        recognizedText: [RecognizedTextFeature],
        year: Int?
    ) -> [String] {
        let visionTags = analysisTags
            .filter { $0.confidence >= 0.28 }
            .map(\.label)

        let ocrTags = recognizedText.flatMap { feature in
            tags(fromRecognizedText: feature.text, excludingYear: year)
        }

        return deduplicate(visionTags + ocrTags)
    }

    private func tags(fromRecognizedText text: String, excludingYear year: Int?) -> [String] {
        text
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
            .filter { token in
                guard let parsed = Int(token) else { return true }
                return parsed != year
            }
    }

    private func extractYear(from recognizedText: [RecognizedTextFeature]) -> Int? {
        let text = recognizedText
            .map(\.text)
            .joined(separator: " ")

        guard let regex = try? NSRegularExpression(pattern: #"\b(18\d{2}|19\d{2}|20\d{2})\b"#) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)

        return matches
            .compactMap { match -> Int? in
                guard let range = Range(match.range(at: 1), in: text) else { return nil }
                return Int(text[range])
            }
            .filter { (1800...2099).contains($0) }
            .sorted()
            .first
    }

    private func deduplicate(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }

            return trimmed
        }
    }

    private func makeDebugInfo(
        analysis: PhotoAnalysisResult,
        tags: [String],
        visualKeywords: [VisualKeyword],
        year: Int?
    ) -> BellPhotoAnalysisDebugInfo {
        let recognizedText = analysis.main.recognizedText + analysis.background.recognizedText
        let analysisTags = analysis.main.allTags + analysis.background.allTags
        let visionTags = """
        Analysis tags:
        \(debugLines(analysisTags) { "\($0.label) — \(debugConfidence($0.confidence))" })

        Visual keywords:
        \(debugLines(visualKeywords) { "\($0.value) — \(debugConfidence($0.confidence))" })
        """
        let ocrText = debugLines(recognizedText) { "\"\($0.text)\" — \(debugConfidence($0.confidence))" }
        let input = """
        Analysis tags:
        \(debugLines(analysisTags) { "\($0.label) — \(debugConfidence($0.confidence))" })

        OCR:
        \(ocrText)
        """
        let output = """
        tags: \(tags.joined(separator: ", "))
        year: \(year.map(String.init) ?? "nil")
        geo: nil
        """

        return BellPhotoAnalysisDebugInfo(
            prompt: "Deterministic mapper from raw Vision + OCR. No model prompt.",
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
