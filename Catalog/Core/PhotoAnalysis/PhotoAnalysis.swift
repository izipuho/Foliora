import CoreGraphics
import Foundation
import Vision

struct PhotoAnalysisResult: Sendable {
    let mainObjectImage: CGImage?
    let mainObjectRegion: ImageRegionFeature?
    let main: PhotoAnalysisFeatureScope
    let background: PhotoAnalysisFeatureScope

    static let empty = PhotoAnalysisResult(
        mainObjectImage: nil,
        mainObjectRegion: nil,
        main: .empty,
        background: .empty
    )
}

struct PhotoAnalysisFeatureScope: Sendable {
    let classifications: [VisionFeature]
    let recognizedText: [RecognizedTextFeature]
    let recognizedObjects: [RecognizedObjectFeature]

    static let empty = PhotoAnalysisFeatureScope(
        classifications: [],
        recognizedText: [],
        recognizedObjects: []
    )
}

struct VisionFeature: Hashable, Sendable {
    let label: String
    let confidence: Double
}

enum RecognizedObjectKind: Hashable, Sendable {
    case animal
}

struct RecognizedObjectFeature: Hashable, Sendable {
    let kind: RecognizedObjectKind
    let labels: [VisionFeature]
    let confidence: Double
    let boundingBox: CGRect
}

struct RecognizedTextFeature: Hashable, Sendable {
    let text: String
    let confidence: Double
    let boundingBox: CGRect
}

struct ImageRegionFeature: Hashable, Sendable {
    let boundingBox: CGRect
    let confidence: Double
}

private enum PhotoAnalysisNormalization {
    nonisolated static func normalizedText(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    nonisolated static func normalizedLabel(_ raw: String) -> String {
        normalizedText(raw).lowercased()
    }

    nonisolated static func normalizedConfidence(_ confidence: Double) -> Double {
        min(max(confidence, 0), 1)
    }

    nonisolated static func deduplicatedByBestConfidence<T, Confidence: Comparable>(
        _ values: [T],
        key: (T) -> String,
        confidence: (T) -> Confidence
    ) -> [T] {
        var order: [String] = []
        var deduplicated: [String: T] = [:]

        for value in values {
            let key = key(value)
            if deduplicated[key] == nil {
                order.append(key)
            }
            if let current = deduplicated[key], confidence(current) >= confidence(value) {
                continue
            }
            deduplicated[key] = value
        }

        return order.compactMap { deduplicated[$0] }
    }

    nonisolated static func confidenceSort<T, Confidence: Comparable>(
        _ confidence: @escaping (T) -> Confidence,
        _ tieBreaker: @escaping (T) -> String
    ) -> (T, T) -> Bool {
        { lhs, rhs in
            let lhsConfidence = confidence(lhs)
            let rhsConfidence = confidence(rhs)
            if lhsConfidence != rhsConfidence {
                return lhsConfidence > rhsConfidence
            }
            return tieBreaker(lhs).localizedCaseInsensitiveCompare(tieBreaker(rhs)) == .orderedAscending
        }
    }
}

protocol PhotoAnalysisService: Sendable {
    func analyze(image: CGImage) async -> PhotoAnalysisResult
}

private struct VisionAnalyzer: Sendable {
    private func makeHandler(for image: CGImage) -> VNImageRequestHandler {
        // Orientation is intentionally not part of this contract; CGImage pixels are analyzed as-is.
        VNImageRequestHandler(cgImage: image, options: [:])
    }

    func classify(image: CGImage) async throws -> [VisionFeature] {
        let maxResults = 16

        let request = VNClassifyImageRequest()
        let handler = makeHandler(for: image)
        try handler.perform([request])

        let features = (request.results ?? []).compactMap { observation -> VisionFeature? in
            let label = PhotoAnalysisNormalization.normalizedLabel(observation.identifier)
            let confidence = Double(observation.confidence)
            guard !label.isEmpty else { return nil }

            return VisionFeature(label: label, confidence: confidence)
        }

        return PhotoAnalysisNormalization
            .deduplicatedByBestConfidence(
                features,
                key: \.label,
                confidence: \.confidence
            )
            .sorted(by: PhotoAnalysisNormalization.confidenceSort(\.confidence, \.label))
            .prefix(maxResults)
            .map { $0 }
    }

    func recognizeText(image: CGImage) async throws -> [RecognizedTextFeature] {
        let maxResults = 32

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = makeHandler(for: image)
        try handler.perform([request])

        let observations = request.results ?? []
        let features = observations.compactMap { observation -> RecognizedTextFeature? in
            guard let candidate = observation.topCandidates(1).first else { return nil }

            let text = PhotoAnalysisNormalization.normalizedText(candidate.string)
            guard !text.isEmpty else { return nil }

            return RecognizedTextFeature(
                text: text,
                confidence: Double(candidate.confidence),
                boundingBox: observation.boundingBox
            )
        }

        return PhotoAnalysisNormalization
            .deduplicatedByBestConfidence(
                features,
                key: { $0.text.lowercased() },
                confidence: \.confidence
            )
            .sorted(by: PhotoAnalysisNormalization.confidenceSort(\.confidence, \.text))
            .prefix(maxResults)
            .map { $0 }
    }

    func detectSaliency(image: CGImage) async throws -> [ImageRegionFeature] {
        let maxResults = 8

        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = makeHandler(for: image)
        try handler.perform([request])

        return (request.results ?? [])
            .flatMap { observation in
                observation.salientObjects?.map {
                    ImageRegionFeature(
                        boundingBox: $0.boundingBox,
                        confidence: Double($0.confidence)
                    )
                } ?? []
            }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxResults)
            .map { $0 }
    }

    func recognizeAnimals(image: CGImage) async throws -> [RecognizedObjectFeature] {
        let maxResults = 8

        var requestError: Error?
        var observations: [VNRecognizedObjectObservation] = []
        let request = VNRecognizeAnimalsRequest { request, error in
            requestError = error
            observations = request.results as? [VNRecognizedObjectObservation] ?? []
        }

        let handler = makeHandler(for: image)
        try handler.perform([request])

        if let requestError {
            throw requestError
        }

        let objects = observations.compactMap { observation -> RecognizedObjectFeature? in
            let labels = observation.labels.compactMap { labelObservation -> VisionFeature? in
                let label = PhotoAnalysisNormalization.normalizedLabel(labelObservation.identifier)
                guard !label.isEmpty else { return nil }

                return VisionFeature(
                    label: label,
                    confidence: PhotoAnalysisNormalization.normalizedConfidence(Double(labelObservation.confidence))
                )
            }
            guard !labels.isEmpty else { return nil }

            return RecognizedObjectFeature(
                kind: .animal,
                labels: labels,
                confidence: labels.map(\.confidence).max() ?? 0,
                boundingBox: observation.boundingBox
            )
        }

        return objects
            .sorted {
                if $0.confidence != $1.confidence {
                    return $0.confidence > $1.confidence
                }
                return ($0.labels.first?.label ?? "")
                    .localizedCaseInsensitiveCompare($1.labels.first?.label ?? "") == .orderedAscending
            }
            .prefix(maxResults)
            .map { $0 }
    }
}

struct DefaultPhotoAnalysisService: PhotoAnalysisService {
    private let vision = VisionAnalyzer()

    func analyze(image: CGImage) async -> PhotoAnalysisResult {
        async let extractedFeatures = try? vision.classify(image: image)
        async let extractedText = try? vision.recognizeText(image: image)
        async let extractedSaliencyRegions = try? vision.detectSaliency(image: image)
        async let extractedRecognizedObjects = try? vision.recognizeAnimals(image: image)

        let textFeatures = await extractedText ?? []
        let saliencyRegions = await extractedSaliencyRegions ?? []
        let backgroundVisionFeatures = await extractedFeatures ?? []
        let backgroundRecognizedObjects = await extractedRecognizedObjects ?? []

        let mainObjectRegion = detectMainObject(
            saliencyRegions: saliencyRegions
        )
        let mainObjectImage = mainObjectRegion.flatMap {
            crop(image: image, to: $0.boundingBox.insetBy(dx: -0.04, dy: -0.04))
        }
        let splitRecognizedText = splitText(textFeatures, mainObject: mainObjectRegion?.boundingBox)
        let mainVisionFeatures: [VisionFeature]
        let mainRecognizedObjects: [RecognizedObjectFeature]
        if let mainObjectImage {
            mainVisionFeatures = (try? await vision.classify(image: mainObjectImage)) ?? []
            mainRecognizedObjects = (try? await vision.recognizeAnimals(image: mainObjectImage)) ?? []
        } else {
            mainVisionFeatures = []
            mainRecognizedObjects = []
        }
        let mainScope = makeScope(
            visionFeatures: mainVisionFeatures,
            textFeatures: splitRecognizedText.main,
            recognizedObjects: mainRecognizedObjects,
            excludedLabels: []
        )
        let backgroundScope = makeScope(
            visionFeatures: backgroundVisionFeatures,
            textFeatures: splitRecognizedText.background,
            recognizedObjects: backgroundRecognizedObjects,
            excludedLabels: Set(mainVisionFeatures.map(\.label))
        )

        return PhotoAnalysisResult(
            mainObjectImage: mainObjectImage,
            mainObjectRegion: mainObjectRegion,
            main: mainScope,
            background: backgroundScope
        )
    }

    private func detectMainObject(
        saliencyRegions: [ImageRegionFeature]
    ) -> ImageRegionFeature? {
        saliencyRegions.first
    }

    private func splitText(
        _ recognizedText: [RecognizedTextFeature],
        mainObject: CGRect?
    ) -> (main: [RecognizedTextFeature], background: [RecognizedTextFeature]) {
        guard let mainObject else {
            return (main: [], background: recognizedText)
        }

        var main: [RecognizedTextFeature] = []
        var background: [RecognizedTextFeature] = []

        for text in recognizedText {
            if intersectionRatio(text.boundingBox, mainObject) >= 0.15 {
                main.append(text)
            } else {
                background.append(text)
            }
        }

        return (main: main, background: background)
    }

    private func makeScope(
        visionFeatures: [VisionFeature],
        textFeatures: [RecognizedTextFeature],
        recognizedObjects: [RecognizedObjectFeature],
        excludedLabels: Set<String>
    ) -> PhotoAnalysisFeatureScope {
        let excludedLabels = Set(excludedLabels.map(PhotoAnalysisNormalization.normalizedLabel))
        let labels = visionFeatures.compactMap { feature -> VisionFeature? in
            let label = PhotoAnalysisNormalization.normalizedLabel(feature.label)
            guard !label.isEmpty, !excludedLabels.contains(label) else { return nil }

            return VisionFeature(
                label: label,
                confidence: PhotoAnalysisNormalization.normalizedConfidence(feature.confidence)
            )
        }
        let textLines = textFeatures.compactMap { feature -> RecognizedTextFeature? in
            let text = PhotoAnalysisNormalization.normalizedText(feature.text)
            guard !text.isEmpty else { return nil }

            return RecognizedTextFeature(
                text: text,
                confidence: PhotoAnalysisNormalization.normalizedConfidence(feature.confidence),
                boundingBox: feature.boundingBox
            )
        }
        let objects = recognizedObjects.compactMap { object -> RecognizedObjectFeature? in
            let labels = object.labels.compactMap { feature -> VisionFeature? in
                let label = PhotoAnalysisNormalization.normalizedLabel(feature.label)
                guard !label.isEmpty, !excludedLabels.contains(label) else { return nil }

                return VisionFeature(
                    label: label,
                    confidence: PhotoAnalysisNormalization.normalizedConfidence(feature.confidence)
                )
            }
            guard !labels.isEmpty else { return nil }

            return RecognizedObjectFeature(
                kind: object.kind,
                labels: labels,
                confidence: PhotoAnalysisNormalization.normalizedConfidence(object.confidence),
                boundingBox: object.boundingBox
            )
        }

        return PhotoAnalysisFeatureScope(
            classifications: labels,
            recognizedText: textLines,
            recognizedObjects: objects
        )
    }

    private func crop(image: CGImage, to normalizedRect: CGRect) -> CGImage? {
        let targetRect = imageRect(
            from: normalizedRect,
            in: CGSize(width: image.width, height: image.height)
        )
        guard targetRect.width > 0, targetRect.height > 0 else { return nil }

        return image.cropping(to: targetRect)
    }

    private func imageRect(from normalizedRect: CGRect, in imageSize: CGSize) -> CGRect {
        let clamped = normalizedRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

        return CGRect(
            x: clamped.minX * imageSize.width,
            y: (1 - clamped.maxY) * imageSize.height,
            width: clamped.width * imageSize.width,
            height: clamped.height * imageSize.height
        ).integral
    }

    private func intersectionRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, lhs.width > 0, lhs.height > 0 else { return 0 }

        return (intersection.width * intersection.height) / (lhs.width * lhs.height)
    }
}
