import CoreGraphics
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct SemanticPhotoFeatures: Hashable, Sendable, Codable {
    let features: [SemanticPhotoFeature]

    static let empty = SemanticPhotoFeatures(features: [])

    init(features: [SemanticPhotoFeature]) {
        self.features = features
    }

    func features(ofKind kind: SemanticPhotoFeatureKind) -> [SemanticPhotoFeature] {
        features.filter { $0.kind == kind }
    }
}

enum SemanticPhotoFeatureKind: String, Hashable, Sendable, Codable {
    case subject
    case material
    case condition
    case place
    case text
    case style
    case visualKeyword
    case recognizedText
}

struct SemanticPhotoFeature: Hashable, Sendable, Codable {
    let kind: SemanticPhotoFeatureKind
    let value: String
    let confidence: Double
    let source: SemanticPhotoFeatureSource

    var label: String {
        value
    }

    init(
        kind: SemanticPhotoFeatureKind,
        value: String,
        confidence: Double,
        source: SemanticPhotoFeatureSource
    ) {
        self.kind = kind
        self.value = value
        self.confidence = confidence
        self.source = source
    }

    init(label: String, confidence: Double, source: SemanticPhotoFeatureSource) {
        let kind: SemanticPhotoFeatureKind
        switch source {
        case .vision:
            kind = .visualKeyword
        case .ocr:
            kind = .recognizedText
        case .vlm:
            kind = .subject
        }

        self.init(
            kind: kind,
            value: label,
            confidence: confidence,
            source: source
        )
    }
}

enum SemanticPhotoFeatureSource: String, Hashable, Sendable, Codable {
    case vision
    case ocr
    case vlm
}

struct SemanticPhotoVisualFeature: Hashable, Sendable {
    let label: String
    let confidence: Double
}

struct SemanticPhotoVLMInput: Sendable {
    let mainObjectImage: CGImage?
    let visualFeatures: [SemanticPhotoVisualFeature]
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

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@Generable
struct SemanticPhotoVLMGeneratedFeature {
    @Guide(description: "A concise, universal semantic fact visible in the image or confirmed by input context.")
    let value: String

    @Guide(description: "Confidence from 0 to 1.", .range(0.0...1.0))
    let confidence: Double
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@Generable
struct SemanticPhotoVLMGeneratedResponse {
    @Guide(description: "Visible subjects or object categories.")
    let subjects: [SemanticPhotoVLMGeneratedFeature]

    @Guide(description: "Visible or context-confirmed material hints.")
    let materialHints: [SemanticPhotoVLMGeneratedFeature]

    @Guide(description: "Visible or context-confirmed condition hints.")
    let conditionHints: [SemanticPhotoVLMGeneratedFeature]

    @Guide(description: "Visible or context-confirmed place or origin hints.")
    let placeHints: [SemanticPhotoVLMGeneratedFeature]

    @Guide(description: "Text entities visible in OCR context or the image.")
    let textEntities: [SemanticPhotoVLMGeneratedFeature]

    @Guide(description: "Visible style, pattern, color, or decorative hints.")
    let styleHints: [SemanticPhotoVLMGeneratedFeature]
}
#endif

#if canImport(FoundationModels) && compiler(>=6.4)
struct AppleFoundationModelsSemanticPhotoVLMExtractor: SemanticPhotoVLMExtracting {
    func extractFeatures(from input: SemanticPhotoVLMInput) async -> SemanticPhotoVLMOutput {
        guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *),
              let image = input.mainObjectImage else {
            return .empty
        }

        do {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                return .empty
            }

            let session = LanguageModelSession(
                model: model,
                instructions: instructions
            )
            let response = try await session.respond(
                generating: SemanticPhotoVLMGeneratedResponse.self,
                options: GenerationOptions(sampling: .greedy)
            ) {
                promptText(for: input)
                Attachment(image)
            }

            return output(from: response.content)
        } catch {
            return .empty
        }
    }

    private var instructions: String {
        """
        Extract universal semantic facts from a photo.
        Use only facts that are visible in the image or confirmed by the provided Vision features or OCR context.
        Do not infer, guess, or invent unknown details.
        Return general semantic facts only.
        Do not use any knowledge of bell cards, bell-specific fields, catalog autofill, or app data-entry needs.
        Every confidence value must be in the range 0...1.
        """
    }

    private func promptText(for input: SemanticPhotoVLMInput) -> String {
        """
        Analyze the attached main object image together with this already-filtered context.
        Do not run or assume any additional Vision or OCR analysis.

        Vision features:
        \(encodedVisualFeatures(input.visualFeatures))

        OCR context:
        \(encodedRecognizedText(input.recognizedText))
        """
    }

    private func encodedVisualFeatures(_ features: [SemanticPhotoVisualFeature]) -> String {
        let promptItems = features.map {
            SemanticPhotoVLMPromptFeature(
                value: $0.label,
                confidence: $0.confidence
            )
        }

        return encodedPromptJSON(promptItems)
    }

    private func encodedRecognizedText(_ text: [RecognizedTextFeature]) -> String {
        let promptItems = text.map {
            SemanticPhotoVLMPromptFeature(
                value: $0.text,
                confidence: $0.confidence
            )
        }

        return encodedPromptJSON(promptItems)
    }

    private func encodedPromptJSON<T: Encodable>(_ value: T) -> String {
        (try? JSONEncoder().encode(value))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    private func output(from response: SemanticPhotoVLMGeneratedResponse) -> SemanticPhotoVLMOutput {
        SemanticPhotoVLMOutput(
            subjects: features(from: response.subjects, kind: .subject),
            materialHints: features(from: response.materialHints, kind: .material),
            conditionHints: features(from: response.conditionHints, kind: .condition),
            placeHints: features(from: response.placeHints, kind: .place),
            textEntities: features(from: response.textEntities, kind: .text),
            styleHints: features(from: response.styleHints, kind: .style)
        )
    }

    private func features(
        from generatedFeatures: [SemanticPhotoVLMGeneratedFeature],
        kind: SemanticPhotoFeatureKind
    ) -> [SemanticPhotoFeature] {
        generatedFeatures.compactMap { generatedFeature in
            let value = generatedFeature.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                return nil
            }

            return SemanticPhotoFeature(
                kind: kind,
                value: value,
                confidence: min(max(generatedFeature.confidence, 0), 1),
                source: .vlm
            )
        }
    }
}
#else
struct AppleFoundationModelsSemanticPhotoVLMExtractor: SemanticPhotoVLMExtracting {
    func extractFeatures(from input: SemanticPhotoVLMInput) async -> SemanticPhotoVLMOutput {
        .empty
    }
}
#endif

private struct SemanticPhotoVLMPromptFeature: Encodable {
    let value: String
    let confidence: Double
}

protocol SemanticPhotoTagFiltering: Sendable {
    func filterTags(_ tags: [SemanticPhotoVisualFeature]) async -> [SemanticPhotoVisualFeature]
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

    func filterTags(_ tags: [SemanticPhotoVisualFeature]) async -> [SemanticPhotoVisualFeature] {
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
                    .map { Self.normalizedLabel($0.tag) }
            )
            let filteredTags = tags.filter { acceptedTags.contains(Self.normalizedLabel($0.label)) }

            return filteredTags
        } catch {
            return []
        }
    }

    private var systemPrompt: String {
        """
        You filter visual recognition tags for semantic photo analysis.
        Remove noisy, overly generic, background, and technical tags.
        Keep only tags useful for describing visible photo content.
        Return only a JSON array without markdown or explanations.
        Each returned item must use exactly one input tag and a confidence from 0 to 1.
        Do not invent new tags.
        """
    }

    private func userPrompt(for tags: [SemanticPhotoVisualFeature]) -> String {
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

    private static func normalizedLabel(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

protocol SemanticPhotoFeatureExtracting: Sendable {
    func extractFeatures(from analysis: PhotoAnalysisResult) async -> SemanticPhotoFeatures
}

struct SemanticPhotoFeatureExtractor: SemanticPhotoFeatureExtracting {
    private let tagFilter: any SemanticPhotoTagFiltering
    private let vlmExtractor: (any SemanticPhotoVLMExtracting)?

    init(
        tagFilter: any SemanticPhotoTagFiltering,
        vlmExtractor: (any SemanticPhotoVLMExtracting)? = nil
    ) {
        self.tagFilter = tagFilter
        self.vlmExtractor = vlmExtractor
    }

    func extractFeatures(from analysis: PhotoAnalysisResult) async -> SemanticPhotoFeatures {
        let visionFeatures =
            visionFeatures(from: analysis.main) +
            visionFeatures(from: analysis.background)
        let recognizedText = analysis.main.recognizedText + analysis.background.recognizedText
        let filteredVisionFeatures = await filterVisionFeatures(visionFeatures)
        let ocrFeatures = recognizedText.map {
            SemanticPhotoFeature(
                kind: .recognizedText,
                value: $0.text,
                confidence: $0.confidence,
                source: .ocr
            )
        }
        let vlmOutput = await vlmExtractor?.extractFeatures(
            from: SemanticPhotoVLMInput(
                mainObjectImage: analysis.mainObjectImage,
                visualFeatures: vlmVisualFeatures(from: filteredVisionFeatures),
                recognizedText: recognizedText
            )
        ) ?? .empty
        let vlmFeatures = features(from: vlmOutput)

        let features =
            filteredVisionFeatures +
            ocrFeatures +
            vlmFeatures

        return SemanticPhotoFeatures(features: features)
    }

    private func visionFeatures(
        from scope: PhotoAnalysisFeatureScope
    ) -> [SemanticPhotoFeature] {
        scope.classifications.map {
            SemanticPhotoFeature(
                kind: .visualKeyword,
                value: $0.label,
                confidence: $0.confidence,
                source: .vision
            )
        } + scope.recognizedObjects.flatMap { object in
            object.labels.map {
                SemanticPhotoFeature(
                    kind: .visualKeyword,
                    value: $0.label,
                    confidence: $0.confidence,
                    source: .vision
                )
            }
        }
    }

    private func filterVisionFeatures(
        _ features: [SemanticPhotoFeature]
    ) async -> [SemanticPhotoFeature] {
        let visualFeatures = vlmVisualFeatures(from: features)
        let filteredVisualFeatures = await tagFilter.filterTags(visualFeatures)

        return filteredVisualFeatures.map {
            SemanticPhotoFeature(
                kind: .visualKeyword,
                value: $0.label,
                confidence: $0.confidence,
                source: .vision
            )
        }
    }

    private func vlmVisualFeatures(
        from features: [SemanticPhotoFeature]
    ) -> [SemanticPhotoVisualFeature] {
        features.map {
            SemanticPhotoVisualFeature(
                label: $0.value,
                confidence: $0.confidence
            )
        }
    }

    private func features(from output: SemanticPhotoVLMOutput) -> [SemanticPhotoFeature] {
        output.subjects +
        output.materialHints +
        output.conditionHints +
        output.placeHints +
        output.textEntities +
        output.styleHints
    }
}
