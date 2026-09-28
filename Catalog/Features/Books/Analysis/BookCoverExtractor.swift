import CoreGraphics
import CoreImage
import CryptoKit
import Foundation
import UIKit
import Vision

/// Extracts and perspective-corrects a book cover from a source image.
struct BookCoverExtractor: Sendable {
    func extractCover(from image: UIImage) async -> MediaAsset? {
        guard let sourceImage = normalizedCGImage(from: image),
              let coverImage = extractCover(from: sourceImage) else {
            return nil
        }

        let normalizedCover = UIImage(cgImage: coverImage)
        guard let data = normalizedCover.jpegData(compressionQuality: 0.92) else {
            return nil
        }

        return MediaAsset(
            id: UUID(),
            kind: .photo,
            displayName: nil,
            sortOrder: 0,
            fileName: nil,
            mimeType: "image/jpeg",
            byteSize: data.count,
            checksum: checksum(for: data),
            width: coverImage.width,
            height: coverImage.height,
            originalData: data
        )
    }

    private func extractCover(from image: CGImage) -> CGImage? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 8
        request.minimumConfidence = 0.5
        request.minimumAspectRatio = 0.25
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.25
        request.quadratureTolerance = 35

        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return nil
        }

        guard let rectangle = bestRectangle(in: request.results ?? []) else {
            return nil
        }

        return perspectiveCorrectedImage(image, using: rectangle)
    }

    private func normalizedCGImage(from image: UIImage) -> CGImage? {
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

    private func bestRectangle(in observations: [VNRectangleObservation]) -> VNRectangleObservation? {
        observations.max { lhs, rhs in
            score(lhs) < score(rhs)
        }
    }

    private func score(_ observation: VNRectangleObservation) -> CGFloat {
        let area = observation.boundingBox.width * observation.boundingBox.height
        return area * CGFloat(max(observation.confidence, 0.01))
    }

    private func perspectiveCorrectedImage(
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

    private func vector(for point: CGPoint, imageSize: CGSize) -> CIVector {
        CIVector(
            x: point.x * imageSize.width,
            y: point.y * imageSize.height
        )
    }

    private func checksum(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
