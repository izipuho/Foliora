import Foundation

extension SemanticPhotoFeatureExtracting {
    /// Extracts one semantic result from the main-object evidence of several photos of one item.
    func extractFeatures(from analysis: MultiPhotoAnalysisResult) async -> SemanticPhotoFeatures {
        let combinedAnalysis = PhotoAnalysisResult(
            mainObjectImage: nil,
            mainObjectRegion: nil,
            main: PhotoAnalysisFeatureScope(
                classifications: analysis.photos.flatMap { $0.main.classifications },
                recognizedText: analysis.photos.flatMap { $0.main.recognizedText },
                recognizedObjects: analysis.photos.flatMap { $0.main.recognizedObjects },
                recognizedBarcodes: analysis.photos.flatMap { $0.main.recognizedBarcodes }
            ),
            background: .empty,
            failures: analysis.photos.flatMap { $0.failures }
        )

        return await extractFeatures(from: combinedAnalysis)
    }
}
