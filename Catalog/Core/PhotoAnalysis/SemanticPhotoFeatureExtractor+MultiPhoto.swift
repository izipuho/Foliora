import Foundation

extension SemanticPhotoFeatureExtracting {
    /// Extracts one semantic result from the main-object evidence of several photos of one item.
    func extractFeatures(from analysis: MultiPhotoAnalysisResult) async -> SemanticPhotoFeatures {
        await extractFeatures(
            from: ItemRecognitionEvidence(analysis: analysis).analysisResult
        )
    }
}
