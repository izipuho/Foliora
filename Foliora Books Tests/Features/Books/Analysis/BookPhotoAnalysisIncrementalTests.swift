import CoreGraphics
import Testing
import UIKit
@testable import Foliora_Books

@MainActor
struct BookPhotoAnalysisIncrementalTests {
    @Test
    func addedPhotoIsAnalyzedWithoutReprocessingInitialPhotos() async {
        let service = BookIncrementalRecordingPhotoAnalysisService()
        let controller = BookPhotoAnalysisController(
            service: service,
            identifierExtractor: BookIncrementalEmptyIdentifierExtractor(),
            bibliographicExtractor: BookIncrementalBibliographicExtractor()
        )

        controller.analyze(images: [makeImage(), makeImage()])
        await waitUntilAnalysisFinishes(controller)

        #expect(controller.suggestions.title?.value == "evidence-1 | evidence-2")

        controller.analyzeAddedPhoto(
            assetID: UUID(),
            image: makeImage()
        )
        await waitUntilAnalysisFinishes(controller)

        let batchSizes = await service.recordedBatchSizes()
        #expect(batchSizes == [2, 1])
        #expect(controller.suggestions.title?.value == "evidence-1 | evidence-2 | evidence-3")
    }

    @Test
    func restoredEvidenceKeepsAddedPhotoIncremental() async throws {
        let itemID = UUID()
        let oldPhotoID = UUID()
        let newPhotoID = UUID()
        let evidence = ItemRecognitionEvidence(
            analysis: MultiPhotoAnalysisResult(
                photos: [
                    PhotoAnalysisResult(
                        mainObjectImage: nil,
                        mainObjectRegion: nil,
                        main: PhotoAnalysisFeatureScope(
                            classifications: [],
                            recognizedText: [
                                RecognizedTextFeature(
                                    text: "evidence-0",
                                    confidence: 1,
                                    boundingBox: .zero
                                )
                            ],
                            recognizedObjects: [],
                            recognizedBarcodes: []
                        ),
                        background: .empty
                    )
                ]
            )
        )
        let repository = BookIncrementalRecognitionRepository(
            record: ItemRecognitionRecord(
                itemID: itemID,
                photoAssetIDs: [oldPhotoID],
                evidenceData: try JSONEncoder().encode(evidence),
                resultData: try JSONEncoder().encode(
                    BookPersistedRecognitionResult(
                        suggestions: .empty,
                        recognizedText: []
                    )
                )
            )
        )
        let service = BookIncrementalRecordingPhotoAnalysisService()
        let controller = BookPhotoAnalysisController(
            service: service,
            identifierExtractor: BookIncrementalEmptyIdentifierExtractor(),
            bibliographicExtractor: BookIncrementalBibliographicExtractor()
        )

        controller.configurePersistence(
            itemID: itemID,
            repository: repository,
            currentSnapshot: ItemRecognitionMediaSnapshot(
                photoAssetIDs: [oldPhotoID]
            )
        )
        controller.reconcileMediaSnapshot(
            ItemRecognitionMediaSnapshot(
                photoAssetIDs: [oldPhotoID, newPhotoID]
            )
        )
        controller.analyzeAddedPhoto(
            assetID: newPhotoID,
            image: makeImage()
        )
        await waitUntilAnalysisFinishes(controller)

        #expect(await service.recordedBatchSizes() == [1])
        #expect(controller.suggestions.title?.value == "evidence-0 | evidence-1")
    }

    private func waitUntilAnalysisFinishes(_ controller: BookPhotoAnalysisController) async {
        for _ in 0..<500 {
            if !controller.isAnalyzing {
                return
            }
            await Task.yield()
        }

        Issue.record("Book photo analysis did not finish.")
    }

    private func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }
}

private actor BookIncrementalRecordingPhotoAnalysisService: PhotoAnalysisService {
    private var batchSizes: [Int] = []
    private var evidenceIndex = 0

    func analyze(image: CGImage) async -> PhotoAnalysisResult {
        evidenceIndex += 1
        return result(index: evidenceIndex)
    }

    func analyze(images: [CGImage]) async -> MultiPhotoAnalysisResult {
        batchSizes.append(images.count)

        let results = images.map { _ -> PhotoAnalysisResult in
            evidenceIndex += 1
            return result(index: evidenceIndex)
        }

        return MultiPhotoAnalysisResult(photos: results)
    }

    func recordedBatchSizes() -> [Int] {
        batchSizes
    }

    private func result(index: Int) -> PhotoAnalysisResult {
        PhotoAnalysisResult(
            mainObjectImage: nil,
            mainObjectRegion: nil,
            main: PhotoAnalysisFeatureScope(
                classifications: [],
                recognizedText: [
                    RecognizedTextFeature(
                        text: "evidence-\(index)",
                        confidence: 1,
                        boundingBox: .zero
                    )
                ],
                recognizedObjects: [],
                recognizedBarcodes: []
            ),
            background: .empty
        )
    }
}

private struct BookIncrementalEmptyIdentifierExtractor: BookIdentifierExtracting {
    nonisolated func extract(
        from analysis: MultiPhotoAnalysisResult
    ) -> [SuggestedFieldValue<BookIdentifier>] {
        []
    }
}

private struct BookIncrementalBibliographicExtractor: BookBibliographicExtracting {
    func extract(
        from analysis: MultiPhotoAnalysisResult
    ) async throws -> BookBibliographicExtraction {
        let title = analysis.photos
            .flatMap { $0.main.recognizedText }
            .map(\.text)
            .joined(separator: " | ")

        return BookBibliographicExtraction(
            title: title.isEmpty
                ? nil
                : SuggestedFieldValue(value: title, confidence: 1),
            authors: [],
            publisher: nil,
            publicationYear: nil,
            languageCode: nil,
            series: nil,
            volumeNumber: nil
        )
    }
}


@MainActor
private final class BookIncrementalRecognitionRepository: CatalogRepository {
    private var record: ItemRecognitionRecord?

    init(record: ItemRecognitionRecord?) {
        self.record = record
    }

    func saveHome(_ home: Home) {}
    func saveLocations(_ locations: [Location], in homeID: UUID) {}
    func deleteHome(homeID: UUID) {}
    func saveCollection(_ collection: Collection) {}
    func deleteResolution(for collectionID: UUID) -> CollectionDeleteResolution {
        .deletePrivateCollection
    }
    func deleteCollection(collectionID: UUID) {}
    func saveUserSortOrder(itemIDs: [UUID], scope: String) {}
    func saveItemRecord(_ item: ItemRecord) {}
    func setFavorite(_ isFavorite: Bool, for itemID: UUID) {}

    func itemRecognition(for itemID: UUID) -> ItemRecognitionRecord? {
        guard record?.itemID == itemID else { return nil }
        return record
    }

    @discardableResult
    func saveItemRecognition(_ record: ItemRecognitionRecord) -> Bool {
        self.record = record
        return true
    }

    func deleteItemRecognition(for itemID: UUID) {
        if record?.itemID == itemID {
            record = nil
        }
    }
}
