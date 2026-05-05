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

private enum PhotoAnalysisFeatureHelpers {
    static func normalizedText(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    static func normalizedLabel(_ raw: String) -> String {
        normalizedText(raw).lowercased()
    }

    static func deduplicatedByBestConfidence<T, Confidence: Comparable>(
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

    static func confidenceSort<T, Confidence: Comparable>(
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

    static func allTags(
        recognizedText: [RecognizedTextFeature],
        visionFeatures: [VisionFeature],
        animalHints: [PhotoAnimalHint]
    ) -> [PhotoTag] {
        let tags = recognizedText.map {
            PhotoTag(label: $0.text, confidence: $0.confidence)
        } + visionFeatures.map {
            PhotoTag(label: $0.label, confidence: $0.confidence)
        } + animalHints.map {
            PhotoTag(label: $0.label, confidence: Double($0.confidence))
        }

        return deduplicatedByBestConfidence(
            tags.compactMap { tag in
                guard !tag.label.isEmpty else { return nil }
                return tag
            },
            key: \.label,
            confidence: \.confidence
        )
        .sorted(by: confidenceSort(\.confidence, \.label))
    }
}

protocol VisionFeatureExtracting: Sendable {
    func extractFeatures(from image: UIImage) async throws -> [VisionFeature]
}

protocol TextFeatureExtracting: Sendable {
    func extractText(from image: UIImage) async throws -> [RecognizedTextFeature]
}

protocol SaliencyRegionExtracting: Sendable {
    func extractSaliencyRegions(from image: UIImage) async throws -> [ImageRegionFeature]
}

protocol RectangleFeatureExtracting: Sendable {
    func extractRectangles(from image: UIImage) async throws -> [DetectedRectangleFeature]
}

protocol AnimalHintExtracting: Sendable {
    func extractAnimalHints(from image: UIImage) async throws -> [PhotoAnimalHint]
}

protocol PhotoAnalysisService: Sendable {
    func analyze(image: UIImage) async -> PhotoAnalysisResult
}

struct VisionFeatureExtractor: VisionFeatureExtracting {
    private let maxResults: Int
    private let minimumConfidence: Double

    init(maxResults: Int = 16, minimumConfidence: Double = 0.0) {
        self.maxResults = maxResults
        self.minimumConfidence = minimumConfidence
    }

    func extractFeatures(from image: UIImage) async throws -> [VisionFeature] {
        guard let cgImage = image.cgImage else { return [] }

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: image.cgImagePropertyOrientation,
            options: [:]
        )
        try handler.perform([request])

        let features = (request.results ?? []).compactMap { observation -> VisionFeature? in
            let label = PhotoAnalysisFeatureHelpers.normalizedLabel(observation.identifier)
            let confidence = Double(observation.confidence)
            guard !label.isEmpty, confidence >= minimumConfidence else { return nil }

            return VisionFeature(label: label, confidence: confidence)
        }

        return PhotoAnalysisFeatureHelpers
            .deduplicatedByBestConfidence(
                features,
                key: \.label,
                confidence: \.confidence
            )
            .prefix(maxResults)
            .map { $0 }
    }
}

struct VisionTextFeatureExtractor: TextFeatureExtracting {
    private let maxResults: Int
    private let minimumConfidence: Double

    init(maxResults: Int = 32, minimumConfidence: Double = 0.0) {
        self.maxResults = maxResults
        self.minimumConfidence = minimumConfidence
    }

    func extractText(from image: UIImage) async throws -> [RecognizedTextFeature] {
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

            let text = PhotoAnalysisFeatureHelpers.normalizedText(candidate.string)
            guard !text.isEmpty else { return nil }

            return RecognizedTextFeature(
                text: text,
                confidence: Double(candidate.confidence),
                boundingBox: observation.boundingBox
            )
        }

        return PhotoAnalysisFeatureHelpers
            .deduplicatedByBestConfidence(
                features,
                key: { $0.text.lowercased() },
                confidence: \.confidence
            )
            .filter { $0.confidence >= minimumConfidence }
            .sorted(by: PhotoAnalysisFeatureHelpers.confidenceSort(\.confidence, \.text))
            .prefix(maxResults)
            .map { $0 }
    }
}

struct VisionSaliencyRegionExtractor: SaliencyRegionExtracting {
    private let maxResults: Int

    init(maxResults: Int = 8) {
        self.maxResults = maxResults
    }

    func extractSaliencyRegions(from image: UIImage) async throws -> [ImageRegionFeature] {
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
}

struct VisionRectangleFeatureExtractor: RectangleFeatureExtracting {
    private let maxResults: Int
    private let minimumConfidence: Double

    init(maxResults: Int = 8, minimumConfidence: Double = 0.0) {
        self.maxResults = maxResults
        self.minimumConfidence = minimumConfidence
    }

    func extractRectangles(from image: UIImage) async throws -> [DetectedRectangleFeature] {
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
            .filter { $0.confidence >= minimumConfidence }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxResults)
            .map { $0 }
    }
}

struct VisionAnimalHintExtractor: AnimalHintExtracting {
    private let maxResults: Int
    private let minimumConfidence: Float

    init(maxResults: Int = 8, minimumConfidence: Float = 0.0) {
        self.maxResults = maxResults
        self.minimumConfidence = minimumConfidence
    }

    func extractAnimalHints(from image: UIImage) async throws -> [PhotoAnimalHint] {
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
            let label = PhotoAnalysisFeatureHelpers.normalizedLabel(observation.identifier)
            guard !label.isEmpty, observation.confidence >= minimumConfidence else { return nil }

            return PhotoAnimalHint(label: label, confidence: observation.confidence)
        }

        return PhotoAnalysisFeatureHelpers
            .deduplicatedByBestConfidence(hints, key: \.label, confidence: \.confidence)
            .prefix(maxResults)
            .map { $0 }
    }
}

struct DefaultPhotoAnalysisService: PhotoAnalysisService {
    private let featureExtractor: any VisionFeatureExtracting
    private let textExtractor: any TextFeatureExtracting
    private let saliencyExtractor: any SaliencyRegionExtracting
    private let rectangleExtractor: any RectangleFeatureExtracting
    private let animalHintExtractor: any AnimalHintExtracting

    init(
        featureExtractor: any VisionFeatureExtracting = VisionFeatureExtractor(),
        textExtractor: any TextFeatureExtracting = VisionTextFeatureExtractor(),
        saliencyExtractor: any SaliencyRegionExtracting = VisionSaliencyRegionExtractor(),
        rectangleExtractor: any RectangleFeatureExtracting = VisionRectangleFeatureExtractor(),
        animalHintExtractor: any AnimalHintExtracting = VisionAnimalHintExtractor()
    ) {
        self.featureExtractor = featureExtractor
        self.textExtractor = textExtractor
        self.saliencyExtractor = saliencyExtractor
        self.rectangleExtractor = rectangleExtractor
        self.animalHintExtractor = animalHintExtractor
    }

    func analyze(image: UIImage) async -> PhotoAnalysisResult {
        async let extractedFeatures = try? featureExtractor.extractFeatures(from: image)
        async let extractedText = try? textExtractor.extractText(from: image)
        async let extractedSaliencyRegions = try? saliencyExtractor.extractSaliencyRegions(from: image)
        async let extractedRectangles = try? rectangleExtractor.extractRectangles(from: image)
        async let extractedAnimalHints = try? animalHintExtractor.extractAnimalHints(from: image)

        let imageSize = image.cgImage.map {
            CGSize(width: $0.width, height: $0.height)
        } ?? .zero

        let recognizedText = await extractedText ?? []
        let saliencyRegions = await extractedSaliencyRegions ?? []
        let detectedRectangles = await extractedRectangles ?? []
        let visionFeatures = await extractedFeatures ?? []
        let animalHints = await extractedAnimalHints ?? []

        let mainObjectBoundingBox = saliencyRegions.first?.boundingBox
            ?? detectedRectangles.first?.boundingBox
        let mainObjectImage = mainObjectBoundingBox.flatMap {
            crop(image: image, to: $0.insetBy(dx: -0.04, dy: -0.04))
        }
        let backgroundImage = mainObjectBoundingBox.flatMap {
            mask(image: image, normalizedRect: $0)
        }

        let mainVisionFeatures: [VisionFeature]
        if let mainObjectImage {
            mainVisionFeatures = (try? await featureExtractor.extractFeatures(from: mainObjectImage)) ?? []
        } else {
            mainVisionFeatures = []
        }

        let backgroundVisionFeatures: [VisionFeature]
        if let backgroundImage {
            backgroundVisionFeatures = (try? await featureExtractor.extractFeatures(from: backgroundImage)) ?? []
        } else {
            backgroundVisionFeatures = visionFeatures
        }

        let mainRecognizedText: [RecognizedTextFeature]
        let backgroundRecognizedText: [RecognizedTextFeature]
        if let mainObjectBoundingBox {
            mainRecognizedText = recognizedText.filter {
                intersectionRatio($0.boundingBox, mainObjectBoundingBox) >= 0.15
            }
            backgroundRecognizedText = recognizedText.filter {
                intersectionRatio($0.boundingBox, mainObjectBoundingBox) < 0.15
            }
        } else {
            mainRecognizedText = []
            backgroundRecognizedText = recognizedText
        }

        let mainAnimalHints = animalHints
        let backgroundAnimalHints = animalHints
        let mainAllTags = PhotoAnalysisFeatureHelpers.allTags(
            recognizedText: mainRecognizedText,
            visionFeatures: mainVisionFeatures,
            animalHints: mainAnimalHints
        )
        let backgroundAllTags = PhotoAnalysisFeatureHelpers.allTags(
            recognizedText: backgroundRecognizedText,
            visionFeatures: backgroundVisionFeatures,
            animalHints: backgroundAnimalHints
        )

        return await PhotoAnalysisResult(
            recognizedText: recognizedText,
            mainObjectImage: mainObjectImage,
            main: PhotoAnalysisFeatureScope(
                recognizedText: mainRecognizedText,
                visionFeatures: mainVisionFeatures,
                animalHints: mainAnimalHints,
                allTags: mainAllTags
            ),
            background: PhotoAnalysisFeatureScope(
                recognizedText: backgroundRecognizedText,
                visionFeatures: backgroundVisionFeatures,
                animalHints: backgroundAnimalHints,
                allTags: backgroundAllTags
            ),
            saliencyRegions: saliencyRegions,
            detectedRectangles: detectedRectangles,
            imageSize: imageSize,
            imageOrientation: image.cgImagePropertyOrientation,
            visionFeatures: visionFeatures
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

    private func mask(image: UIImage, normalizedRect: CGRect) -> UIImage? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }

        let targetRect = imageRect(from: normalizedRect, in: image.size)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)

        return renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            UIColor.white.setFill()
            context.fill(targetRect)
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
