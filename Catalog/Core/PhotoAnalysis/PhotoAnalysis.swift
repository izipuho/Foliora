import CoreGraphics
import Foundation
import ImageIO
import UIKit
import Vision

struct PhotoAnalysisResult: Sendable {
    let recognizedText: [RecognizedTextFeature]
    let mainObjectImage: UIImage?
    let main: PhotoAnalysisFeatureScope
    let background: PhotoAnalysisFeatureScope
    let saliencyRegions: [ImageRegionFeature]
    let detectedRectangles: [DetectedRectangleFeature]
    let imageSize: CGSize
    let imageOrientation: CGImagePropertyOrientation
    let visionFeatures: [VisionFeature]

    static let empty = PhotoAnalysisResult(
        recognizedText: [],
        mainObjectImage: nil,
        main: .empty,
        background: .empty,
        saliencyRegions: [],
        detectedRectangles: [],
        imageSize: .zero,
        imageOrientation: .up,
        visionFeatures: []
    )
}

struct PhotoAnalysisFeatureScope: Sendable {
    let recognizedText: [RecognizedTextFeature]
    let visionFeatures: [VisionFeature]
    let animalHints: [PhotoAnimalHint]
    let allTags: [PhotoTag]

    static let empty = PhotoAnalysisFeatureScope(
        recognizedText: [],
        visionFeatures: [],
        animalHints: [],
        allTags: []
    )
}

struct VisionFeature: Hashable, Sendable {
    let label: String
    let confidence: Double
}

struct PhotoAnimalHint: Hashable, Sendable {
    let label: String
    let confidence: Float
}

struct PhotoTag: Hashable, Sendable {
    let label: String
    let confidence: Double
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

struct DetectedRectangleFeature: Hashable, Sendable {
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

private enum PhotoAnalysisTagBuilder {
    nonisolated static func allTags(
        recognizedText: [RecognizedTextFeature],
        visionFeatures: [VisionFeature],
        animalHints: [PhotoAnimalHint],
        excludedLabels: Set<String>
    ) -> [PhotoTag] {
        let excludedLabels = Set(excludedLabels.map(PhotoAnalysisNormalization.normalizedLabel))
        let tags = recognizedText.map {
            PhotoTag(label: $0.text, confidence: $0.confidence)
        } + visionFeatures.map {
            PhotoTag(label: $0.label, confidence: $0.confidence)
        } + animalHints.map {
            PhotoTag(label: $0.label, confidence: Double($0.confidence))
        }

        return PhotoAnalysisNormalization.deduplicatedByBestConfidence(
            tags.compactMap { tag in
                let label = PhotoAnalysisNormalization.normalizedLabel(tag.label)
                guard !label.isEmpty, !excludedLabels.contains(label) else { return nil }
                return tag
            },
            key: { PhotoAnalysisNormalization.normalizedLabel($0.label) },
            confidence: \.confidence
        )
        .sorted(by: PhotoAnalysisNormalization.confidenceSort(\.confidence, \.label))
    }
}

protocol PhotoAnalysisService: Sendable {
    func analyze(image: UIImage) async -> PhotoAnalysisResult
}

private struct VisionAnalyzer: Sendable {
    func classify(image: UIImage) async throws -> [VisionFeature] {
        let maxResults = 16
        guard let cgImage = image.cgImage else { return [] }

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.cgImagePropertyOrientation,
            options: [:]
        )
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

    func recognizeText(image: UIImage) async throws -> [RecognizedTextFeature] {
        let maxResults = 32
        guard let cgImage = image.cgImage else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.cgImagePropertyOrientation,
            options: [:]
        )
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

    func detectSaliency(image: UIImage) async throws -> [ImageRegionFeature] {
        let maxResults = 8
        guard let cgImage = image.cgImage else { return [] }

        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.cgImagePropertyOrientation,
            options: [:]
        )
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

    func detectRectangles(image: UIImage) async throws -> [DetectedRectangleFeature] {
        let maxResults = 8
        guard let cgImage = image.cgImage else { return [] }

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = maxResults

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.cgImagePropertyOrientation,
            options: [:]
        )
        try handler.perform([request])

        return (request.results ?? [])
            .map {
                DetectedRectangleFeature(
                    boundingBox: $0.boundingBox,
                    confidence: Double($0.confidence)
                )
            }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxResults)
            .map { $0 }
    }

    func recognizeAnimals(image: UIImage) async throws -> [PhotoAnimalHint] {
        let maxResults = 8
        guard let cgImage = image.cgImage else { return [] }

        var requestError: Error?
        var classifications: [VNClassificationObservation] = []
        let request = VNRecognizeAnimalsRequest { request, error in
            requestError = error
            let observations = request.results as? [VNRecognizedObjectObservation] ?? []
            classifications = observations.flatMap(\.labels)
        }

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.cgImagePropertyOrientation,
            options: [:]
        )
        try handler.perform([request])

        if let requestError {
            throw requestError
        }

        let hints = classifications.compactMap { observation -> PhotoAnimalHint? in
            let label = PhotoAnalysisNormalization.normalizedLabel(observation.identifier)
            guard !label.isEmpty else { return nil }

            return PhotoAnimalHint(label: label, confidence: observation.confidence)
        }

        return PhotoAnalysisNormalization
            .deduplicatedByBestConfidence(hints, key: \.label, confidence: \.confidence)
            .sorted(by: PhotoAnalysisNormalization.confidenceSort(\.confidence, \.label))
            .prefix(maxResults)
            .map { $0 }
    }
}

struct DefaultPhotoAnalysisService: PhotoAnalysisService {
    private let vision = VisionAnalyzer()

    func analyze(image: UIImage) async -> PhotoAnalysisResult {
        async let extractedFeatures = try? vision.classify(image: image)
        async let extractedText = try? vision.recognizeText(image: image)
        async let extractedSaliencyRegions = try? vision.detectSaliency(image: image)
        async let extractedRectangles = try? vision.detectRectangles(image: image)
        async let extractedAnimalHints = try? vision.recognizeAnimals(image: image)

        let imageSize = image.cgImage.map {
            CGSize(width: $0.width, height: $0.height)
        } ?? .zero

        let recognizedText = await extractedText ?? []
        let saliencyRegions = await extractedSaliencyRegions ?? []
        let detectedRectangles = await extractedRectangles ?? []
        let visionFeatures = await extractedFeatures ?? []
        let animalHints = await extractedAnimalHints ?? []

        let mainObject = detectMainObject(
            saliencyRegions: saliencyRegions
        )
        let mainObjectImage = mainObject.flatMap {
            crop(image: image, to: $0.insetBy(dx: -0.04, dy: -0.04))
        }
        let splitRecognizedText = splitText(recognizedText, mainObject: mainObject)
        let mainVisionFeatures: [VisionFeature]
        if let mainObjectImage {
            mainVisionFeatures = (try? await vision.classify(image: mainObjectImage)) ?? []
        } else {
            mainVisionFeatures = []
        }
        let mainScope = makeScope(
            visionFeatures: mainVisionFeatures,
            textFeatures: splitRecognizedText.main,
            animalHints: animalHints,
            excludedLabels: []
        )
        let backgroundScope = makeScope(
            visionFeatures: visionFeatures,
            textFeatures: splitRecognizedText.background,
            animalHints: [],
            excludedLabels: Set(mainScope.visionFeatures.map(\.label))
        )

        return PhotoAnalysisResult(
            recognizedText: recognizedText,
            mainObjectImage: mainObjectImage,
            main: mainScope,
            background: backgroundScope,
            saliencyRegions: saliencyRegions,
            detectedRectangles: detectedRectangles,
            imageSize: imageSize,
            imageOrientation: image.cgImagePropertyOrientation,
            visionFeatures: visionFeatures
        )
    }

    private func detectMainObject(
        saliencyRegions: [ImageRegionFeature]
    ) -> CGRect? {
        saliencyRegions.first?.boundingBox
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
        animalHints: [PhotoAnimalHint],
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
        let animalLabels = animalHints.compactMap { hint -> PhotoAnimalHint? in
            let label = PhotoAnalysisNormalization.normalizedLabel(hint.label)
            guard !label.isEmpty, !excludedLabels.contains(label) else { return nil }

            return PhotoAnimalHint(
                label: label,
                confidence: Float(PhotoAnalysisNormalization.normalizedConfidence(Double(hint.confidence)))
            )
        }
        let allTags = PhotoAnalysisTagBuilder.allTags(
            recognizedText: textLines,
            visionFeatures: labels,
            animalHints: animalLabels,
            excludedLabels: excludedLabels
        )

        return PhotoAnalysisFeatureScope(
            recognizedText: textLines,
            visionFeatures: labels,
            animalHints: animalLabels,
            allTags: allTags
        )
    }

    private func crop(image: UIImage, to normalizedRect: CGRect) -> UIImage? {
        let targetRect = imageRect(from: normalizedRect, in: image.size)
        guard targetRect.width > 0, targetRect.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: targetRect.size, format: format)

        return renderer.image { _ in
            image.draw(
                in: CGRect(
                    x: -targetRect.minX,
                    y: -targetRect.minY,
                    width: image.size.width,
                    height: image.size.height
                )
            )
        }
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

private extension UIImage {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up:
            return .up
        case .upMirrored:
            return .upMirrored
        case .down:
            return .down
        case .downMirrored:
            return .downMirrored
        case .left:
            return .left
        case .leftMirrored:
            return .leftMirrored
        case .right:
            return .right
        case .rightMirrored:
            return .rightMirrored
        @unknown default:
            return .up
        }
    }
}
