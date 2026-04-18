import Foundation
import UIKit
import Vision

struct SuggestedFieldValue<Value: Sendable>: Sendable {
    let value: Value
    let confidence: Double
}

struct VisionFeature: Sendable {
    let label: String
    let confidence: Double
}

struct RecognizedTextFeature: Hashable, Sendable {
    let text: String
    let confidence: Double
}

struct VisualKeyword: Hashable, Sendable {
    let value: String
    let confidence: Double
}

enum PhotoSemanticTag: String, CaseIterable, Hashable, Sendable {
    case bell
    case metal
    case brass
    case bronze
    case ceramic
    case porcelain
    case glass
    case wood
    case silver
    case stone
    case plastic
    case decorative
    case antique
    case vintage
    case shiny
    case worn
    case damaged
}

struct NormalizedVisionTag: Hashable, Sendable {
    let tag: PhotoSemanticTag
    let confidence: Double
}

struct PhotoAnalysisResult: Sendable {
    let tags: [NormalizedVisionTag]
    let recognizedText: [RecognizedTextFeature]
    let visualKeywords: [VisualKeyword]

    static let empty = PhotoAnalysisResult(tags: [], recognizedText: [], visualKeywords: [])
}

protocol VisionFeatureExtracting: Sendable {
    func extractFeatures(from image: UIImage) async throws -> [VisionFeature]
}

protocol TextFeatureExtracting: Sendable {
    func extractText(from image: UIImage) async throws -> [RecognizedTextFeature]
}

protocol PhotoAnalysisService: Sendable {
    func analyze(image: UIImage) async -> PhotoAnalysisResult
}

struct VisionFeatureExtractor: VisionFeatureExtracting {
    private let maxResults: Int

    init(maxResults: Int = 12) {
        self.maxResults = maxResults
    }

    func extractFeatures(from image: UIImage) async throws -> [VisionFeature] {
        guard let cgImage = image.cgImage else { return [] }

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations: [VNClassificationObservation] = request.results ?? []
        return observations
            .prefix(maxResults)
            .map { VisionFeature(label: $0.identifier.lowercased(), confidence: Double($0.confidence)) }
    }
}

struct VisionTextFeatureExtractor: TextFeatureExtracting {
    private let maxResults: Int
    private let minimumConfidence: Double

    init(maxResults: Int = 8, minimumConfidence: Double = 0.55) {
        self.maxResults = maxResults
        self.minimumConfidence = minimumConfidence
    }

    func extractText(from image: UIImage) async throws -> [RecognizedTextFeature] {
        guard let cgImage = image.cgImage else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.02

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations: [VNRecognizedTextObservation] = request.results ?? []

        let textFeatures: [RecognizedTextFeature] = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let confidence = Double(candidate.confidence)
                guard confidence >= minimumConfidence else { return nil }

                let text = normalizedText(candidate.string)
                guard isUsefulRecognizedText(text) else { return nil }

                return RecognizedTextFeature(text: text, confidence: confidence)
            }

        let bestByNormalizedText = textFeatures.reduce(into: [String: RecognizedTextFeature]()) {
            (partialResult: inout [String: RecognizedTextFeature], feature: RecognizedTextFeature) in
                let normalized = feature.text.lowercased()
                let current = partialResult[normalized]
                if current == nil || current!.confidence < feature.confidence {
                    partialResult[normalized] = feature
                }
            }

        return bestByNormalizedText.values
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.text.localizedCaseInsensitiveCompare(rhs.text) == .orderedAscending
                }
                return lhs.confidence > rhs.confidence
            }
            .prefix(maxResults)
            .map { $0 }
    }

    private func normalizedText(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    private func isUsefulRecognizedText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        guard text.count >= 2, text.count <= 28 else { return false }

        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, words.count <= 4 else { return false }

        let letters = text.unicodeScalars.filter(CharacterSet.letters.contains)
        let digits = text.unicodeScalars.filter(CharacterSet.decimalDigits.contains)
        guard letters.count >= 2 else { return false }
        guard digits.count < text.count else { return false }

        let allowedSymbols = CharacterSet(charactersIn: " -./")
        let allowedCharacters = CharacterSet.letters
            .union(.decimalDigits)
            .union(allowedSymbols)
        guard text.unicodeScalars.allSatisfy(allowedCharacters.contains) else { return false }

        return true
    }
}

struct DefaultPhotoAnalysisService: PhotoAnalysisService {
    private let extractor: any VisionFeatureExtracting
    private let textExtractor: any TextFeatureExtracting

    init(
        extractor: any VisionFeatureExtracting = VisionFeatureExtractor(),
        textExtractor: any TextFeatureExtracting = VisionTextFeatureExtractor()
    ) {
        self.extractor = extractor
        self.textExtractor = textExtractor
    }

    func analyze(image: UIImage) async -> PhotoAnalysisResult {
        async let extractedFeatures = try? extractor.extractFeatures(from: image)
        async let extractedText = try? textExtractor.extractText(from: image)

        let features = await extractedFeatures ?? []
        let recognizedText = await extractedText ?? []

        return PhotoAnalysisResult(
            tags: normalize(features: filteredVisionFeatures(features)),
            recognizedText: recognizedText,
            visualKeywords: extractVisualKeywords(from: features)
        )
    }

    private func normalize(features: [VisionFeature]) -> [NormalizedVisionTag] {
        var bestConfidenceByTag: [PhotoSemanticTag: Double] = [:]

        for feature in features {
            for tag in tags(for: feature.label) {
                bestConfidenceByTag[tag] = max(bestConfidenceByTag[tag] ?? 0, feature.confidence)
            }
        }

        return bestConfidenceByTag
            .map { NormalizedVisionTag(tag: $0.key, confidence: $0.value) }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.tag.rawValue < rhs.tag.rawValue
                }
                return lhs.confidence > rhs.confidence
            }
    }

    private func tags(for label: String) -> Set<PhotoSemanticTag> {
        var result: Set<PhotoSemanticTag> = []
        let normalized = label.lowercased()

        if normalized.contains("bell") || normalized.contains("handbell") || normalized.contains("cowbell") {
            result.insert(.bell)
        }
        if normalized.contains("metal") || normalized.contains("brass") || normalized.contains("bronze") || normalized.contains("copper") {
            result.insert(.metal)
        }
        if normalized.contains("brass") {
            result.insert(.brass)
            result.insert(.shiny)
        }
        if normalized.contains("bronze") || normalized.contains("copper") {
            result.insert(.bronze)
        }
        if normalized.contains("ceramic") || normalized.contains("pottery") {
            result.insert(.ceramic)
        }
        if normalized.contains("porcelain") {
            result.insert(.porcelain)
        }
        if normalized.contains("glass") || normalized.contains("crystal") {
            result.insert(.glass)
            result.insert(.shiny)
        }
        if normalized.contains("wood") || normalized.contains("timber") {
            result.insert(.wood)
        }
        if normalized.contains("silver") || normalized.contains("chrome") || normalized.contains("steel") {
            result.insert(.silver)
            result.insert(.shiny)
        }
        if normalized.contains("stone") || normalized.contains("rock") || normalized.contains("marble") {
            result.insert(.stone)
        }
        if normalized.contains("plastic") || normalized.contains("polymer") || normalized.contains("resin") {
            result.insert(.plastic)
        }
        if normalized.contains("ornament") || normalized.contains("decor") || normalized.contains("decoration") {
            result.insert(.decorative)
        }
        if normalized.contains("antique") || normalized.contains("ancient") {
            result.insert(.antique)
        }
        if normalized.contains("vintage") || normalized.contains("retro") {
            result.insert(.vintage)
        }
        if normalized.contains("rust") || normalized.contains("weathered") || normalized.contains("aged") || normalized.contains("worn") {
            result.insert(.worn)
        }
        if normalized.contains("broken") || normalized.contains("damaged") || normalized.contains("crack") {
            result.insert(.damaged)
        }

        return result
    }

    private func filteredVisionFeatures(_ features: [VisionFeature]) -> [VisionFeature] {
        features.filter { $0.confidence >= 0.18 }
    }

    private func extractVisualKeywords(from features: [VisionFeature]) -> [VisualKeyword] {
        let keywordMap: [(needles: [String], keyword: String)] = [
            (["hedgehog", "porcupine"], "hedgehog"),
            (["owl"], "owl"),
            (["bird"], "bird"),
            (["cat", "kitten", "feline"], "cat"),
            (["dog", "puppy", "canine"], "dog"),
            (["animal", "creature"], "animal"),
            (["figurine", "statuette", "statue", "sculpture"], "figurine"),
            (["ornament", "decor", "decoration"], "decorative"),
            (["toy", "doll"], "toy")
        ]

        var bestByKeyword: [String: Double] = [:]

        for feature in features where feature.confidence >= 0.22 {
            let label = feature.label.lowercased()
            for mapping in keywordMap where mapping.needles.contains(where: label.contains) {
                bestByKeyword[mapping.keyword] = max(bestByKeyword[mapping.keyword] ?? 0, feature.confidence)
            }
        }

        return bestByKeyword
            .map { VisualKeyword(value: $0.key, confidence: $0.value) }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.value < rhs.value
                }
                return lhs.confidence > rhs.confidence
            }
    }
}
