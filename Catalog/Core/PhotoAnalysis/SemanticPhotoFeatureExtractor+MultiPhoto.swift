import Foundation

extension SemanticPhotoFeatureExtracting {
    /// Extracts one semantic result from the main-object evidence of several photos of one item.
    func extractFeatures(from analysis: MultiPhotoAnalysisResult) async -> SemanticPhotoFeatures {
        let combinedAnalysis = PhotoAnalysisResult(
            mainObjectImage: nil,
            mainObjectRegion: nil,
            main: PhotoAnalysisFeatureScope(
                classifications: MultiPhotoSemanticEvidence.visualFeatures(from: analysis.photos),
                recognizedText: MultiPhotoSemanticEvidence.recognizedText(from: analysis.photos),
                recognizedObjects: [],
                recognizedBarcodes: MultiPhotoSemanticEvidence.barcodes(from: analysis.photos)
            ),
            background: .empty,
            failures: analysis.photos.flatMap { $0.failures }
        )

        return await extractFeatures(from: combinedAnalysis)
    }
}

private enum MultiPhotoSemanticEvidence {
    static func visualFeatures(from photos: [PhotoAnalysisResult]) -> [VisionFeature] {
        let features = photos.flatMap { photo in
            photo.main.classifications
                + photo.main.recognizedObjects.flatMap(\.labels)
        }

        return deduplicatedByBestConfidence(
            features,
            key: { normalizedKey($0.label) },
            confidence: \.confidence
        )
    }

    static func recognizedText(from photos: [PhotoAnalysisResult]) -> [RecognizedTextFeature] {
        deduplicatedByBestConfidence(
            photos.flatMap { $0.main.recognizedText },
            key: { normalizedKey($0.text) },
            confidence: \.confidence
        )
    }

    static func barcodes(from photos: [PhotoAnalysisResult]) -> [RecognizedBarcodeFeature] {
        deduplicatedByBestConfidence(
            photos.flatMap { $0.main.recognizedBarcodes },
            key: {
                "\(normalizedKey($0.symbology))\u{1F}\(normalizedKey($0.payload))"
            },
            confidence: \.confidence
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
