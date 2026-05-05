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
        let recognizedText = analysis.main.recognizedText
        let analysisTags = makeAnalysisTags(from: analysis)
        let visualKeywords = makeVisualKeywords(from: analysisTags)
        let tags = makeTags(analysisTags: analysisTags)

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
            suggestedTags: tags.map { SuggestedFieldValue(value: $0, confidence: 0.7) },
            debugInfo: makeDebugInfo(
                analysis: analysis,
                tags: tags,
                visualKeywords: visualKeywords,
                year: nil
            )
        )
    }


    private func makeAnalysisTags(from analysis: PhotoAnalysisResult) -> [PhotoTag] {
        deduplicateTags(analysis.main.allTags)
            .sorted { lhs, rhs in
                lhs.confidence > rhs.confidence
            }
    }

    private func deduplicateTags(_ tags: [PhotoTag]) -> [PhotoTag] {
        var bestByLabel: [String: PhotoTag] = [:]

        for tag in tags {
            let label = tag.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { continue }

            let key = label.lowercased()
            if let existing = bestByLabel[key], existing.confidence >= tag.confidence {
                continue
            }

            bestByLabel[key] = PhotoTag(label: label, confidence: tag.confidence)
        }

        return Array(bestByLabel.values)
    }

    private func makeVisualKeywords(from analysisTags: [PhotoTag]) -> [VisualKeyword] {
        analysisTags
            .filter { $0.confidence >= 0.28 }
            .map { VisualKeyword(value: $0.label, confidence: $0.confidence) }
    }

    private func makeTags(analysisTags: [PhotoTag]) -> [String] {
        let visionTags = analysisTags
            .filter { $0.confidence >= 0.28 }
            .map(\.label)

        return deduplicate(visionTags)
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
        let recognizedText = analysis.main.recognizedText
        let analysisTags = makeAnalysisTags(from: analysis)
        let visionTags = """
        Analysis tags:
        \(debugLines(analysisTags) { "\($0.label) — \(debugConfidence($0.confidence))" })

        Visual keywords:
        \(debugLines(visualKeywords) { "\($0.value) — \(debugConfidence($0.confidence))" })
        """
        let ocrText = debugLines(recognizedText) { "\"\($0.text)\" — \(debugConfidence($0.confidence))" }
        let input = """
        mainObjectImage: \(analysis.mainObjectImage == nil ? "nil" : "present")

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
            prompt: "Deterministic mapper from PhotoAnalysisResult. No model prompt.",
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
