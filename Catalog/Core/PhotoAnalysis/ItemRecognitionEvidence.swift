import CoreGraphics
import Foundation

/// Durable item-level recognition evidence used to continue recognition after restoring a persisted result.
struct ItemRecognitionEvidence: Codable, Sendable {
    struct VisualFeature: Codable, Sendable {
        let label: String
        let confidence: Double

        init(_ feature: VisionFeature) {
            label = feature.label
            confidence = feature.confidence
        }

        var runtimeValue: VisionFeature {
            VisionFeature(label: label, confidence: confidence)
        }
    }

    struct TextFeature: Codable, Sendable {
        let text: String
        let confidence: Double
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ feature: RecognizedTextFeature) {
            text = feature.text
            confidence = feature.confidence
            x = feature.boundingBox.origin.x
            y = feature.boundingBox.origin.y
            width = feature.boundingBox.size.width
            height = feature.boundingBox.size.height
        }

        var runtimeValue: RecognizedTextFeature {
            RecognizedTextFeature(
                text: text,
                confidence: confidence,
                boundingBox: CGRect(x: x, y: y, width: width, height: height)
            )
        }
    }

    struct BarcodeFeature: Codable, Sendable {
        let payload: String
        let symbology: String
        let confidence: Double
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ feature: RecognizedBarcodeFeature) {
            payload = feature.payload
            symbology = feature.symbology
            confidence = feature.confidence
            x = feature.boundingBox.origin.x
            y = feature.boundingBox.origin.y
            width = feature.boundingBox.size.width
            height = feature.boundingBox.size.height
        }

        var runtimeValue: RecognizedBarcodeFeature {
            RecognizedBarcodeFeature(
                payload: payload,
                symbology: symbology,
                confidence: confidence,
                boundingBox: CGRect(x: x, y: y, width: width, height: height)
            )
        }
    }

    let visualFeatures: [VisualFeature]
    let recognizedText: [TextFeature]
    let recognizedBarcodes: [BarcodeFeature]

    init(analysis: MultiPhotoAnalysisResult) {
        visualFeatures = Self.deduplicatedByBestConfidence(
            analysis.photos.flatMap { photo in
                photo.main.classifications + photo.main.recognizedObjects.flatMap(\.labels)
            },
            key: { Self.normalizedKey($0.label) },
            confidence: \.confidence
        ).map(VisualFeature.init)

        recognizedText = Self.deduplicatedByBestConfidence(
            analysis.photos.flatMap { $0.main.recognizedText },
            key: { Self.normalizedKey($0.text) },
            confidence: \.confidence
        ).map(TextFeature.init)

        recognizedBarcodes = Self.deduplicatedByBestConfidence(
            analysis.photos.flatMap { $0.main.recognizedBarcodes },
            key: {
                "\(Self.normalizedKey($0.symbology))\u{1F}\(Self.normalizedKey($0.payload))"
            },
            confidence: \.confidence
        ).map(BarcodeFeature.init)
    }

    var analysisResult: PhotoAnalysisResult {
        PhotoAnalysisResult(
            mainObjectImage: nil,
            mainObjectRegion: nil,
            main: PhotoAnalysisFeatureScope(
                classifications: visualFeatures.map(\.runtimeValue),
                recognizedText: recognizedText.map(\.runtimeValue),
                recognizedObjects: [],
                recognizedBarcodes: recognizedBarcodes.map(\.runtimeValue)
            ),
            background: .empty
        )
    }

    private static func deduplicatedByBestConfidence<Value, Confidence: Comparable>(
        _ values: [Value],
        key: (Value) -> String,
        confidence: (Value) -> Confidence
    ) -> [Value] {
        var order: [String] = []
        var bestByKey: [String: Value] = [:]

        for value in values {
            let key = key(value)
            guard !key.isEmpty else { continue }

            if bestByKey[key] == nil {
                order.append(key)
            }

            if let current = bestByKey[key], confidence(current) >= confidence(value) {
                continue
            }

            bestByKey[key] = value
        }

        return order.compactMap { bestByKey[$0] }
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}
