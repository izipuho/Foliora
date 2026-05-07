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

protocol SemanticPhotoTagFiltering: Sendable {
    func filterTags(_ tags: [PhotoTag]) async -> [PhotoTag]
}

struct PassthroughSemanticPhotoTagFilter: SemanticPhotoTagFiltering {
    func filterTags(_ tags: [PhotoTag]) async -> [PhotoTag] {
        tags
    }
}

protocol LocalLLMClient: Sendable {
    func complete(_ request: LocalLLMRequest) async throws -> LocalLLMResponse
}

struct LocalLLMRequest: Sendable {
    let systemPrompt: String
    let userPrompt: String
    let temperature: Double
    let maxTokens: Int
}

struct LocalLLMResponse: Sendable {
    let text: String
}

struct LocalLLMTagFilterItem: Decodable, Sendable {
    let tag: String
    let confidence: Double
}

private struct LocalLLMTagFilterPromptItem: Encodable {
    let tag: String
    let confidence: Double
}

struct LocalLLMSemanticPhotoTagFilter: SemanticPhotoTagFiltering {
    private let client: any LocalLLMClient

    init(client: any LocalLLMClient) {
        self.client = client
    }

    func filterTags(_ tags: [PhotoTag]) async -> [PhotoTag] {
        guard !tags.isEmpty else {
            return []
        }

        do {
            let response = try await client.complete(
                LocalLLMRequest(
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt(for: tags),
                    temperature: 0.0,
                    maxTokens: 512
                )
            )
            let items = try JSONDecoder().decode(
                [LocalLLMTagFilterItem].self,
                from: Data(response.text.utf8)
            )
            let acceptedTags = Set(
                items
                    .filter { $0.confidence >= 0.5 }
                    .map(\.tag)
            )
            let filteredTags = tags.filter { acceptedTags.contains($0.label) }

            return filteredTags.isEmpty ? tags : filteredTags
        } catch {
            return tags
        }
    }

    private var systemPrompt: String {
        """
        You filter visual recognition tags for semantic photo analysis.
        Remove noisy, overly generic, background, and technical tags.
        Keep only tags useful for describing a souvenir bell: material, shape, objects, characters, animals, plants, geography, culture, symbols, and inscriptions.
        Return only a JSON array without markdown or explanations.
        Each returned item must use exactly one input tag and a confidence from 0 to 1.
        Do not invent new tags.
        """
    }

    private func userPrompt(for tags: [PhotoTag]) -> String {
        let promptItems = tags.map {
            LocalLLMTagFilterPromptItem(
                tag: $0.label,
                confidence: $0.confidence
            )
        }
        let encodedTags = (try? JSONEncoder().encode(promptItems))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        return """
        Input tags:
        \(encodedTags)

        Return a subset in this exact JSON format:
        [
          { "tag": "ceramic", "confidence": 0.95 }
        ]
        """
    }
}

protocol SemanticPhotoFeatureExtracting: Sendable {
    func extractFeatures(from analysis: PhotoAnalysisResult) async -> SemanticPhotoFeatures
}

struct SemanticPhotoFeatureExtractor: SemanticPhotoFeatureExtracting {
    private let tagFilter: any SemanticPhotoTagFiltering
    private let vlmExtractor: (any SemanticPhotoVLMExtracting)?

    init(
        tagFilter: any SemanticPhotoTagFiltering = PassthroughSemanticPhotoTagFilter(),
        vlmExtractor: (any SemanticPhotoVLMExtracting)? = nil
    ) {
        self.tagFilter = tagFilter
        self.vlmExtractor = vlmExtractor
    }

    func extractFeatures(from analysis: PhotoAnalysisResult) async -> SemanticPhotoFeatures {
        let allTags = analysis.main.allTags + analysis.background.allTags
        let recognizedText = analysis.main.recognizedText + analysis.background.recognizedText
        let semanticTags = await tagFilter.filterTags(allTags)
        let vlmOutput = await vlmExtractor?.extractFeatures(
            from: SemanticPhotoVLMInput(
                mainObjectImage: analysis.mainObjectImage,
                allTags: semanticTags,
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
