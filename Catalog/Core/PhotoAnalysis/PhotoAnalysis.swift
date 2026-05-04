import Foundation
import UIKit
import Vision

struct VisionFeature: Sendable {
    let label: String
    let confidence: Double
}

struct RecognizedTextFeature: Hashable, Sendable {
    let text: String
    let confidence: Double
}

struct PhotoAnalysisResult: Sendable {
    let visionFeatures: [VisionFeature]
    let recognizedText: [RecognizedTextFeature]

    static let empty = PhotoAnalysisResult(
        visionFeatures: [],
        recognizedText: []
    )
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
    private let minimumConfidence: Double

    init(maxResults: Int = 16, minimumConfidence: Double = 0.18) {
        self.maxResults = maxResults
        self.minimumConfidence = minimumConfidence
    }

    func extractFeatures(from image: UIImage) async throws -> [VisionFeature] {
        guard let cgImage = image.cgImage else { return [] }

        var features: [VisionFeature] = []
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        let classifyRequest = VNClassifyImageRequest()
        try handler.perform([classifyRequest])

        let classifications: [VNClassificationObservation] = classifyRequest.results ?? []
        features += classifications.map {
            VisionFeature(
                label: normalizedLabel($0.identifier),
                confidence: Double($0.confidence)
            )
        }

        if #available(iOS 26.0, *), let objectRequest = makeRecognizeObjectsRequest() {
            try handler.perform([objectRequest])
            let objects = (objectRequest as NSObject).value(forKey: "results") as? [VNRecognizedObjectObservation] ?? []
            features += objects.flatMap { observation in
                observation.labels.map { label in
                    VisionFeature(
                        label: normalizedLabel(label.identifier),
                        confidence: Double(label.confidence)
                    )
                }
            }
        }

        return deduplicate(features)
            .filter { $0.confidence >= minimumConfidence }
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
                return lhs.confidence > rhs.confidence
            }
            .prefix(maxResults)
            .map { $0 }
    }

    private func normalizedLabel(_ raw: String) -> String {
        raw
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func deduplicate(_ features: [VisionFeature]) -> [VisionFeature] {
        features.reduce(into: [String: VisionFeature]()) { partialResult, feature in
            let key = feature.label.lowercased()
            if partialResult[key] == nil || partialResult[key]!.confidence < feature.confidence {
                partialResult[key] = feature
            }
        }
        .values
        .map { $0 }
    }

    private func makeRecognizeObjectsRequest() -> VNRequest? {
        guard let requestClass = NSClassFromString("VNRecognizeObjectsRequest") as? NSObject.Type else {
            return nil
        }
        return requestClass.init() as? VNRequest
    }
}

struct VisionTextFeatureExtractor: TextFeatureExtracting {
    private let maxResults: Int
    private let minimumConfidence: Double

    init(maxResults: Int = 24, minimumConfidence: Double = 0.0) {
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
            guard !text.isEmpty else { return nil }

            return RecognizedTextFeature(text: text, confidence: confidence)
        }

        return deduplicate(textFeatures)
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
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func deduplicate(_ features: [RecognizedTextFeature]) -> [RecognizedTextFeature] {
        features.reduce(into: [String: RecognizedTextFeature]()) { partialResult, feature in
            let key = feature.text.lowercased()
            if partialResult[key] == nil || partialResult[key]!.confidence < feature.confidence {
                partialResult[key] = feature
            }
        }
        .values
        .map { $0 }
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

        return await PhotoAnalysisResult(
            visionFeatures: extractedFeatures ?? [],
            recognizedText: extractedText ?? []
        )
    }
}
