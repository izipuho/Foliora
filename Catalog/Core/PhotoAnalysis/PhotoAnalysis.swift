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

    static let empty = PhotoAnalysisFeatureScope(
        recognizedText: [],
        visionFeatures: []
    )
}

struct VisionFeature: Hashable, Sendable {
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

        let classifications = request.results ?? []
        let features = classifications.map {
            VisionFeature(label: $0.identifier, confidence: Double($0.confidence))
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

    private func deduplicate(_ features: [VisionFeature]) -> [VisionFeature] {
        features.reduce(into: [String: VisionFeature]()) { result, feature in
            let key = feature.label.lowercased()
            if result[key] == nil || result[key]!.confidence < feature.confidence {
                result[key] = feature
            }
        }
        .values
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

            let confidence = Double(candidate.confidence)
            guard confidence >= minimumConfidence else { return nil }

            let text = normalizedText(candidate.string)
            guard !text.isEmpty else { return nil }

            return RecognizedTextFeature(
                text: text,
                confidence: confidence,
                boundingBox: observation.boundingBox
            )
        }

        return deduplicate(features)
            .sorted { lhs, rhs in
                if lhs.confidence == rhs.confidence {
                    return lhs.text.localizedCaseInsensitiveCompare(rhs.text) == .orderedAscending
                }
                return lhs.confidence > rhs.confidence
            }
            .prefix(maxResults)
            .map { $0 }
    }

    private func deduplicate(_ features: [RecognizedTextFeature]) -> [RecognizedTextFeature] {
        features.reduce(into: [String: RecognizedTextFeature]()) { result, feature in
            let key = feature.text.lowercased()
            if result[key] == nil || result[key]!.confidence < feature.confidence {
                result[key] = feature
            }
        }
        .values
        .map { $0 }
    }

    private func normalizedText(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
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

        let observations = request.results ?? []
        return observations
            .flatMap { observation in
                observation.salientObjects?.map {
                    ImageRegionFeature(
                        boundingBox: $0.boundingBox,
                        confidence: Double($0.confidence)
                    )
                } ?? []
            }
            .sorted { lhs, rhs in lhs.confidence > rhs.confidence }
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

        let observations = request.results ?? []
        return observations
            .map {
                DetectedRectangleFeature(
                    boundingBox: $0.boundingBox,
                    confidence: Double($0.confidence)
                )
            }
            .filter { $0.confidence >= minimumConfidence }
            .sorted { lhs, rhs in lhs.confidence > rhs.confidence }
            .prefix(maxResults)
            .map { $0 }
    }
}

struct DefaultPhotoAnalysisService: PhotoAnalysisService {
    private let featureExtractor: any VisionFeatureExtracting
    private let textExtractor: any TextFeatureExtracting
    private let saliencyExtractor: any SaliencyRegionExtracting
    private let rectangleExtractor: any RectangleFeatureExtracting

    init(
        featureExtractor: any VisionFeatureExtracting = VisionFeatureExtractor(),
        textExtractor: any TextFeatureExtracting = VisionTextFeatureExtractor(),
        saliencyExtractor: any SaliencyRegionExtracting = VisionSaliencyRegionExtractor(),
        rectangleExtractor: any RectangleFeatureExtracting = VisionRectangleFeatureExtractor()
    ) {
        self.featureExtractor = featureExtractor
        self.textExtractor = textExtractor
        self.saliencyExtractor = saliencyExtractor
        self.rectangleExtractor = rectangleExtractor
    }

    func analyze(image: UIImage) async -> PhotoAnalysisResult {
        async let extractedFeatures = try? featureExtractor.extractFeatures(from: image)
        async let extractedText = try? textExtractor.extractText(from: image)
        async let extractedSaliencyRegions = try? saliencyExtractor.extractSaliencyRegions(from: image)
        async let extractedRectangles = try? rectangleExtractor.extractRectangles(from: image)

        let imageSize = image.cgImage.map {
            CGSize(width: $0.width, height: $0.height)
        } ?? .zero

        let recognizedText = await extractedText ?? []
        let saliencyRegions = await extractedSaliencyRegions ?? []
        let detectedRectangles = await extractedRectangles ?? []
        let visionFeatures = await extractedFeatures ?? []

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

        return await PhotoAnalysisResult(
            recognizedText: recognizedText,
            mainObjectImage: mainObjectImage,
            main: PhotoAnalysisFeatureScope(
                recognizedText: mainRecognizedText,
                visionFeatures: mainVisionFeatures
            ),
            background: PhotoAnalysisFeatureScope(
                recognizedText: backgroundRecognizedText,
                visionFeatures: backgroundVisionFeatures
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
