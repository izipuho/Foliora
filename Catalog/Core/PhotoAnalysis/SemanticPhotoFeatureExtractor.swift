import Foundation
import FoundationModels

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
        case .semanticModel:
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
    case semanticModel = "vlm"
}

struct SemanticPhotoVisualFeature: Hashable, Sendable {
    let label: String
    let confidence: Double
}

struct SemanticPhotoSemanticInput: Sendable {
    let visualFeatures: [SemanticPhotoVisualFeature]
    let recognizedText: [RecognizedTextFeature]
}

struct SemanticPhotoSemanticOutput: Sendable {
    let subjects: [SemanticPhotoFeature]
    let materialHints: [SemanticPhotoFeature]
    let conditionHints: [SemanticPhotoFeature]
    let placeHints: [SemanticPhotoFeature]
    let textEntities: [SemanticPhotoFeature]
    let styleHints: [SemanticPhotoFeature]

    static let empty = SemanticPhotoSemanticOutput(
        subjects: [],
        materialHints: [],
        conditionHints: [],
        placeHints: [],
        textEntities: [],
        styleHints: []
    )
}

protocol SemanticPhotoSemanticExtracting: Sendable {
    func extractFeatures(from input: SemanticPhotoSemanticInput) async -> SemanticPhotoSemanticOutput
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@Generable
struct SemanticPhotoGeneratedFeature {
    @Guide(description: "A concise, universal semantic fact visible in the image or confirmed by input context.")
    let value: String

    @Guide(description: "Confidence from 0 to 1.", .range(0.0...1.0))
    let confidence: Double
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@Generable
struct SemanticPhotoGeneratedResponse {
    @Guide(description: "Visible subjects or object categories.")
    let subjects: [SemanticPhotoGeneratedFeature]

    @Guide(description: "Visible or context-confirmed material hints.")
    let materialHints: [SemanticPhotoGeneratedFeature]

    @Guide(description: "Visible or context-confirmed condition hints.")
    let conditionHints: [SemanticPhotoGeneratedFeature]

    @Guide(description: "Visible or context-confirmed place or origin hints.")
    let placeHints: [SemanticPhotoGeneratedFeature]

    @Guide(description: "Text entities visible in OCR context or the image.")
    let textEntities: [SemanticPhotoGeneratedFeature]

    @Guide(description: "Visible style, pattern, color, or decorative hints.")
    let styleHints: [SemanticPhotoGeneratedFeature]
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@Generable
struct SemanticPhotoTagFilterGeneratedItem {
    @Guide(description: "One exact tag copied from the input tags.")
    let tag: String

    @Guide(description: "Confidence from 0 to 1.", .range(0.0...1.0))
    let confidence: Double
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@Generable
struct SemanticPhotoTagFilterGeneratedResponse {
    @Guide(description: "Filtered subset of the input tags. Do not include tags that were not provided.")
    let tags: [SemanticPhotoTagFilterGeneratedItem]
}

struct AppleFoundationModelsSemanticPhotoExtractor: SemanticPhotoSemanticExtracting {
    func extractFeatures(from input: SemanticPhotoSemanticInput) async -> SemanticPhotoSemanticOutput {
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
                generating: SemanticPhotoGeneratedResponse.self,
                options: GenerationOptions(sampling: .greedy)
            ) {
                promptText(for: input)
            }

            return output(from: response.content)
        } catch {
            return .empty
        }
    }

    private var instructions: String {
        """
        Extract universal semantic facts from system Vision and OCR results.
        Do not claim that any feature is directly visible to you.
        Create universal semantic facts only from the provided input features.
        Do not add details that are not confirmed by the input context.
        Return general semantic facts only.
        Every confidence value must be in the range 0...1.
        """
    }

    private func promptText(for input: SemanticPhotoSemanticInput) -> String {
        """
        Analyze these already-collected results from system Vision and OCR APIs.
        Do not run or assume any additional Vision or OCR analysis.

        Vision features:
        \(encodedVisualFeatures(input.visualFeatures))

        OCR context:
        \(encodedRecognizedText(input.recognizedText))
        """
    }

    private func encodedVisualFeatures(_ features: [SemanticPhotoVisualFeature]) -> String {
        let promptItems = features.map {
            SemanticPhotoPromptFeature(
                value: $0.label,
                confidence: $0.confidence
            )
        }

        return encodedPromptJSON(promptItems)
    }

    private func encodedRecognizedText(_ text: [RecognizedTextFeature]) -> String {
        let promptItems = text.map {
            SemanticPhotoPromptFeature(
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

    private func output(from response: SemanticPhotoGeneratedResponse) -> SemanticPhotoSemanticOutput {
        SemanticPhotoSemanticOutput(
            subjects: features(from: response.subjects, kind: .subject),
            materialHints: features(from: response.materialHints, kind: .material),
            conditionHints: features(from: response.conditionHints, kind: .condition),
            placeHints: features(from: response.placeHints, kind: .place),
            textEntities: features(from: response.textEntities, kind: .text),
            styleHints: features(from: response.styleHints, kind: .style)
        )
    }

    private func features(
        from generatedFeatures: [SemanticPhotoGeneratedFeature],
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
                source: .semanticModel
            )
        }
    }
}

private struct SemanticPhotoPromptFeature: Encodable {
    let value: String
    let confidence: Double
}

protocol SemanticPhotoTagFiltering: Sendable {
    func filterTags(_ tags: [SemanticPhotoVisualFeature]) async -> [SemanticPhotoVisualFeature]
}

private struct SemanticPhotoTagFilterPromptItem: Encodable {
    let tag: String
    let confidence: Double
}

struct AppleFoundationModelsSemanticPhotoTagFilter: SemanticPhotoTagFiltering {
    func filterTags(_ tags: [SemanticPhotoVisualFeature]) async -> [SemanticPhotoVisualFeature] {
        guard !tags.isEmpty else {
            return []
        }

        do {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                return tags
            }

            let session = LanguageModelSession(
                model: model,
                instructions: instructions
            )
            let response = try await session.respond(
                generating: SemanticPhotoTagFilterGeneratedResponse.self,
                options: GenerationOptions(sampling: .greedy)
            ) {
                userPrompt(for: tags)
            }
            let acceptedTags = Set(
                response.content.tags
                    .map { Self.normalizedLabel($0.tag) }
            )

            return tags.filter { acceptedTags.contains(Self.normalizedLabel($0.label)) }
        } catch {
            return tags
        }
    }

    private var instructions: String {
        """
        You filter visual recognition tags for semantic photo analysis.
        Remove noisy, overly generic, background, and technical tags.
        Keep only tags useful for describing visible photo content.
        Return only a subset of the provided input tags.
        Do not invent new tags.
        """
    }

    private func userPrompt(for tags: [SemanticPhotoVisualFeature]) -> String {
        let promptItems = tags.map {
            SemanticPhotoTagFilterPromptItem(
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
        {
          "tags": [
            { "tag": "ceramic", "confidence": 0.95 }
          ]
        }
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
    private let semanticExtractor: any SemanticPhotoSemanticExtracting

    init(
        tagFilter: any SemanticPhotoTagFiltering = AppleFoundationModelsSemanticPhotoTagFilter(),
        semanticExtractor: any SemanticPhotoSemanticExtracting = AppleFoundationModelsSemanticPhotoExtractor()
    ) {
        self.tagFilter = tagFilter
        self.semanticExtractor = semanticExtractor
    }

    func extractFeatures(from analysis: PhotoAnalysisResult) async -> SemanticPhotoFeatures {
        let visionFeatures = visionFeatures(from: analysis.main)
        let recognizedText = analysis.main.recognizedText
        let filteredVisionFeatures = await filterVisionFeatures(visionFeatures)
        let ocrFeatures = recognizedText.map {
            SemanticPhotoFeature(
                kind: .recognizedText,
                value: $0.text,
                confidence: $0.confidence,
                source: .ocr
            )
        }
        let semanticOutput = await semanticExtractor.extractFeatures(
            from: SemanticPhotoSemanticInput(
                visualFeatures: semanticVisualFeatures(from: filteredVisionFeatures),
                recognizedText: recognizedText
            )
        )
        let semanticFeatures = features(from: semanticOutput)

        let features =
            filteredVisionFeatures +
            ocrFeatures +
            semanticFeatures

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
        let visualFeatures = semanticVisualFeatures(from: features)
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

    private func semanticVisualFeatures(
        from features: [SemanticPhotoFeature]
    ) -> [SemanticPhotoVisualFeature] {
        features.map {
            SemanticPhotoVisualFeature(
                label: $0.value,
                confidence: $0.confidence
            )
        }
    }

    private func features(from output: SemanticPhotoSemanticOutput) -> [SemanticPhotoFeature] {
        output.subjects +
        output.materialHints +
        output.conditionHints +
        output.placeHints +
        output.textEntities +
        output.styleHints
    }
}
