import CoreGraphics
import CoreImage
import CryptoKit
import Foundation
import UIKit
import Vision

/// Extracts and perspective-corrects a book cover from a source image.
struct BookCoverExtractor: Sendable {
    /// Rendered cover pixels produced off the main actor.
    private struct RenderedCover: Sendable {
        let jpegData: Data
        let width: Int
        let height: Int
    }

    func extractCover(from imageData: Data) async -> MediaAsset? {
        guard let cover = await Self.renderCover(from: imageData) else {
            return nil
        }

        return MediaAsset(
            id: UUID(),
            kind: .photo,
            displayName: nil,
            sortOrder: 0,
            fileName: nil,
            mimeType: "image/jpeg",
            byteSize: cover.jpegData.count,
            checksum: checksum(for: cover.jpegData),
            width: cover.width,
            height: cover.height,
            originalData: cover.jpegData
        )
    }

    /// Decodes, orients, detects and corrects the cover away from the main actor.
    ///
    /// Every step works on the full-resolution photo and takes noticeable time, so running it
    /// inline on the main actor froze the UI once per created book.
    @concurrent
    private nonisolated static func renderCover(from imageData: Data) async -> RenderedCover? {
        guard let image = UIImage(data: imageData),
              let sourceImage = normalizedCGImage(from: image),
              let coverImage = extractCover(from: sourceImage),
              let jpegData = UIImage(cgImage: coverImage).jpegData(compressionQuality: 0.92) else {
            return nil
        }

        return RenderedCover(
            jpegData: jpegData,
            width: coverImage.width,
            height: coverImage.height
        )
    }

    /// Finds the cover and returns it perspective-corrected.
    ///
    /// Document segmentation runs first: unlike contour detection it still finds a cover whose
    /// outline blends into the background or is crossed by stronger lines, such as floor seams or
    /// the cover artwork itself. Contour-based rectangle detection stays as the fallback.
    private nonisolated static func extractCover(from image: CGImage) -> CGImage? {
        let minimumConfidence: VNConfidence = 0.5
        // Shortest cover side as a proportion of the shortest image side.
        let minimumSize: Float = 0.25
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        let documentRequest = VNDetectDocumentSegmentationRequest()
        // A failed segmentation is not fatal: rectangle detection below still gets its turn.
        try? handler.perform([documentRequest])

        let shortestImageSide = CGFloat(min(image.width, image.height))
        let document = documentRequest.results?.first { observation in
            let box = observation.boundingBox
            let shortestSide = min(box.width * CGFloat(image.width), box.height * CGFloat(image.height))

            return observation.confidence >= minimumConfidence
                && shortestSide >= CGFloat(minimumSize) * shortestImageSide
        }

        if let document {
            return perspectiveCorrectedImage(image, using: document)
        }

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 8
        request.minimumConfidence = minimumConfidence
        request.minimumAspectRatio = 0.25
        request.maximumAspectRatio = 1.0
        request.minimumSize = minimumSize
        request.quadratureTolerance = 35

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let rectangle = bestRectangle(in: request.results ?? []) else {
            return nil
        }

        return perspectiveCorrectedImage(image, using: rectangle)
    }

    private nonisolated static func normalizedCGImage(from image: UIImage) -> CGImage? {
        guard image.imageOrientation != .up else {
            return image.cgImage
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false

        let normalizedImage = UIGraphicsImageRenderer(
            size: image.size,
            format: format
        ).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }

        return normalizedImage.cgImage
    }

    private nonisolated static func bestRectangle(in observations: [VNRectangleObservation]) -> VNRectangleObservation? {
        observations.max { lhs, rhs in
            score(lhs) < score(rhs)
        }
    }

    private nonisolated static func score(_ observation: VNRectangleObservation) -> CGFloat {
        let area = observation.boundingBox.width * observation.boundingBox.height
        return area * CGFloat(max(observation.confidence, 0.01))
    }

    private nonisolated static func perspectiveCorrectedImage(
        _ image: CGImage,
        using rectangle: VNRectangleObservation
    ) -> CGImage? {
        let inputImage = CIImage(cgImage: image)
        let imageSize = inputImage.extent.size

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            return nil
        }

        filter.setValue(inputImage, forKey: kCIInputImageKey)
        filter.setValue(vector(for: rectangle.topLeft, imageSize: imageSize), forKey: "inputTopLeft")
        filter.setValue(vector(for: rectangle.topRight, imageSize: imageSize), forKey: "inputTopRight")
        filter.setValue(vector(for: rectangle.bottomLeft, imageSize: imageSize), forKey: "inputBottomLeft")
        filter.setValue(vector(for: rectangle.bottomRight, imageSize: imageSize), forKey: "inputBottomRight")

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let extent = outputImage.extent.integral
        guard extent.width > 0, extent.height > 0 else {
            return nil
        }

        return CIContext().createCGImage(outputImage, from: extent)
    }

    private nonisolated static func vector(for point: CGPoint, imageSize: CGSize) -> CIVector {
        CIVector(
            x: point.x * imageSize.width,
            y: point.y * imageSize.height
        )
    }

    private func checksum(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
