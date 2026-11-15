import CoreGraphics

extension DefaultPhotoAnalysisService {
    /// Avoids running several already-parallel Vision pipelines at the same time.
    func analyze(images: [CGImage]) async -> MultiPhotoAnalysisResult {
        guard !images.isEmpty else {
            return .empty
        }

#if DEBUG
        await RecognitionDebugSettings.waitBeforeAnalysisIfNeeded()
#endif

        var results: [PhotoAnalysisResult] = []
        results.reserveCapacity(images.count)

        for image in images {
            results.append(await analyze(image: image))
        }

        return MultiPhotoAnalysisResult(photos: results)
    }
}
