import Foundation
import Observation
import UIKit

/// Represents typed suggestions produced from one or more photos of a book.
struct BookPhotoSuggestions: Sendable {
    let title: SuggestedFieldValue<String>?
    let authors: [SuggestedFieldValue<String>]
    let identifiers: [SuggestedFieldValue<BookIdentifier>]
    let publisher: SuggestedFieldValue<String>?
    let publicationYear: SuggestedFieldValue<Int>?
    let languageCode: SuggestedFieldValue<String>?
    let series: SuggestedFieldValue<String>?
    let volumeNumber: SuggestedFieldValue<Int>?

    static let empty = BookPhotoSuggestions(
        title: nil,
        authors: [],
        identifiers: [],
        publisher: nil,
        publicationYear: nil,
        languageCode: nil,
        series: nil,
        volumeNumber: nil
    )

    var hasSuggestions: Bool {
        title != nil
            || !authors.isEmpty
            || !identifiers.isEmpty
            || publisher != nil
            || publicationYear != nil
            || languageCode != nil
            || series != nil
            || volumeNumber != nil
    }
}

/// Defines failures owned by the book photo-analysis orchestration layer.
enum BookPhotoAnalysisError: LocalizedError, Sendable {
    case imageUnavailable
    case bibliographicTimeout

    var errorDescription: String? {
        switch self {
        case .imageUnavailable:
            return "One or more source images cannot be analyzed as CGImages."
        case .bibliographicTimeout:
            return "Foundation Models bibliographic extraction timed out."
        }
    }
}

/// Orchestrates generic item-level photo analysis and book-specific recognition.
@MainActor
@Observable
final class BookPhotoAnalysisController: ItemCreationRecognitionController {
    enum Field {
        case title
        case authors
        case identifiers
        case publisher
        case publicationYear
        case languageCode
        case series
        case volumeNumber
    }

    private struct PendingPhoto {
        let assetID: UUID
        let image: CGImage
    }

    private(set) var isAnalyzing = false
    private(set) var suggestions: BookPhotoSuggestions = .empty
    private(set) var recognizedText: [RecognizedTextFeature] = []
    private(set) var mediaSnapshot: ItemRecognitionMediaSnapshot = .empty
    private(set) var analysisError: (any Error)?
    private(set) var photoAnalysisFailures: [PhotoAnalysisFailure] = []

    private let service: any PhotoAnalysisService
    private let identifierExtractor: any BookIdentifierExtracting
    private let bibliographicExtractor: any BookBibliographicExtracting
    private let bibliographicTimeout: Duration

    private var analysisByAssetID: [UUID: PhotoAnalysisResult] = [:]
    private var analysisOrder: [UUID] = []
    private var pendingBatches: [[PendingPhoto]] = []
    private var isProcessingBatch = false
    private var evidenceRevision = 0
    private var persistenceItemID: UUID?
    private var persistenceRepository: (any CatalogRepository)?
    private var persistedEvidence: ItemRecognitionEvidence?
    private var persistedEvidenceAssetIDs: Set<UUID> = []
    private(set) var isRestoredFromPersistence = false
    private(set) var requiresFullAnalysis = false

    init() {
        self.service = DefaultPhotoAnalysisService()
        self.identifierExtractor = BookIdentifierExtractor()
        self.bibliographicExtractor = BookBibliographicExtractor()
        self.bibliographicTimeout = .seconds(30)
    }

    init(
        service: any PhotoAnalysisService,
        identifierExtractor: any BookIdentifierExtracting,
        bibliographicExtractor: any BookBibliographicExtracting,
        bibliographicTimeout: Duration = .seconds(30)
    ) {
        self.service = service
        self.identifierExtractor = identifierExtractor
        self.bibliographicExtractor = bibliographicExtractor
        self.bibliographicTimeout = bibliographicTimeout
    }

    var hasSuggestions: Bool {
        isAnalyzing || suggestions.hasSuggestions
    }

    func configurePersistence(
        itemID: UUID,
        repository: any CatalogRepository,
        currentSnapshot: ItemRecognitionMediaSnapshot
    ) {
        persistenceItemID = itemID
        persistenceRepository = repository

        guard !isAnalyzing,
              analysisByAssetID.isEmpty,
              pendingBatches.isEmpty,
              !suggestions.hasSuggestions,
              recognizedText.isEmpty,
              let record = repository.itemRecognition(for: itemID) else {
            return
        }

        guard record.schemaVersion == ItemRecognitionRecord.currentSchemaVersion else {
            repository.deleteItemRecognition(for: itemID)
            return
        }

        guard record.photoAssetIDs == currentSnapshot.photoAssetIDs else {
            // CloudKit can deliver the Item media graph and its recognition record at different times.
            // Keep a valid recognition record until the local media snapshot catches up or a local
            // recognition mutation explicitly invalidates it.
            mediaSnapshot = currentSnapshot
            return
        }

        guard let evidenceData = record.evidenceData,
              let evidence = try? JSONDecoder().decode(
                ItemRecognitionEvidence.self,
                from: evidenceData
              ),
              let resultData = record.resultData,
              let persisted = try? JSONDecoder().decode(
                BookPersistedRecognitionResult.self,
                from: resultData
              ) else {
            repository.deleteItemRecognition(for: itemID)
            return
        }

        mediaSnapshot = currentSnapshot
        persistedEvidence = evidence
        persistedEvidenceAssetIDs = record.photoAssetIDs
        suggestions = persisted.runtimeSuggestions
        recognizedText = persisted.runtimeRecognizedText
        analysisError = nil
        photoAnalysisFailures = []
        isRestoredFromPersistence = true
        requiresFullAnalysis = false
    }

    func flushPersistedResultIfPossible() {
        persistCurrentResultIfPossible()
    }

    func analyze(image: UIImage) {
        analyze(images: [image])
    }

    func analyze(images: [UIImage]) {
        analyze(
            photos: images.map {
                (assetID: UUID(), image: $0)
            }
        )
    }

    func analyze(photos: [(assetID: UUID, image: UIImage)]) {
        deletePersistedResult()
        persistedEvidence = nil
        persistedEvidenceAssetIDs.removeAll()
        isRestoredFromPersistence = false
        requiresFullAnalysis = false
        analysisByAssetID.removeAll()
        analysisOrder.removeAll()
        pendingBatches.removeAll()
        evidenceRevision += 1
        suggestions = .empty
        recognizedText = []
        photoAnalysisFailures = []
        analysisError = nil
        mediaSnapshot = ItemRecognitionMediaSnapshot(
            photoAssetIDs: Set(photos.map(\.assetID))
        )

        let pending = pendingPhotos(from: photos)
        guard pending.count == photos.count else {
            analysisError = BookPhotoAnalysisError.imageUnavailable
            if pending.isEmpty, !isProcessingBatch {
                isAnalyzing = false
            }
            if pending.isEmpty {
                return
            }
            enqueue(pending)
            return
        }

        analysisOrder = pending.map(\.assetID)
        enqueue(pending)
    }

    func analyzeAddedPhoto(assetID: UUID, image: UIImage) {
        guard !requiresFullAnalysis else { return }
        guard let cgImage = image.photoAnalysisCGImage else {
            analysisError = BookPhotoAnalysisError.imageUnavailable
            return
        }

        deletePersistedResult()
        isRestoredFromPersistence = false
        mediaSnapshot = ItemRecognitionMediaSnapshot(
            photoAssetIDs: mediaSnapshot.photoAssetIDs.union([assetID])
        )
        if !analysisOrder.contains(assetID) {
            analysisOrder.append(assetID)
        }
        enqueue([PendingPhoto(assetID: assetID, image: cgImage)])
    }

    func reconcileMediaSnapshot(_ snapshot: ItemRecognitionMediaSnapshot) {
        guard snapshot != mediaSnapshot else { return }

        let removedAssetIDs = mediaSnapshot.photoAssetIDs.subtracting(snapshot.photoAssetIDs)
        let validAssetIDs = snapshot.photoAssetIDs

        let ownsRecognitionState =
            persistedEvidence != nil
            || !analysisByAssetID.isEmpty
            || !pendingBatches.isEmpty
            || isProcessingBatch

        // A media snapshot can change while CloudKit is still converging. If this controller has
        // not restored or produced recognition evidence yet, do not turn that passive sync change
        // into a deletion of a potentially valid remote recognition record.
        guard ownsRecognitionState else {
            mediaSnapshot = snapshot
            return
        }

        deletePersistedResult()
        mediaSnapshot = snapshot

        let removedPersistedAssetIDs = removedAssetIDs.intersection(persistedEvidenceAssetIDs)
        if !removedPersistedAssetIDs.isEmpty {
            persistedEvidence = nil
            persistedEvidenceAssetIDs.removeAll()
            isRestoredFromPersistence = false
            requiresFullAnalysis = true
            analysisByAssetID.removeAll()
            analysisOrder.removeAll()
            pendingBatches.removeAll()
            evidenceRevision += 1
            suggestions = .empty
            recognizedText = []
            photoAnalysisFailures = []
            analysisError = nil
            if !isProcessingBatch {
                isAnalyzing = false
            }
            return
        }

        isRestoredFromPersistence = false
        analysisByAssetID = analysisByAssetID.filter { validAssetIDs.contains($0.key) }
        analysisOrder.removeAll { !validAssetIDs.contains($0) }
        pendingBatches = pendingBatches.compactMap { batch in
            let filtered = batch.filter { validAssetIDs.contains($0.assetID) }
            return filtered.isEmpty ? nil : filtered
        }

        guard !removedAssetIDs.isEmpty else { return }

        evidenceRevision += 1
        let revision = evidenceRevision

        guard !isProcessingBatch else { return }

        isAnalyzing = true
        Task {
            await refreshSuggestions(for: revision)
            guard revision == evidenceRevision else { return }
            isAnalyzing = false
            persistCurrentResultIfPossible()
        }
    }

    func dismiss(_ field: Field) {
        suggestions = BookPhotoSuggestions(
            title: field == .title ? nil : suggestions.title,
            authors: field == .authors ? [] : suggestions.authors,
            identifiers: field == .identifiers ? [] : suggestions.identifiers,
            publisher: field == .publisher ? nil : suggestions.publisher,
            publicationYear: field == .publicationYear ? nil : suggestions.publicationYear,
            languageCode: field == .languageCode ? nil : suggestions.languageCode,
            series: field == .series ? nil : suggestions.series,
            volumeNumber: field == .volumeNumber ? nil : suggestions.volumeNumber
        )
        persistCurrentResultIfPossible()
    }

    func clear() {
        deletePersistedResult()
        persistedEvidence = nil
        persistedEvidenceAssetIDs.removeAll()
        isRestoredFromPersistence = false
        requiresFullAnalysis = false
        analysisByAssetID.removeAll()
        analysisOrder.removeAll()
        pendingBatches.removeAll()
        evidenceRevision += 1
        suggestions = .empty
        recognizedText = []
        photoAnalysisFailures = []
        analysisError = nil
        mediaSnapshot = .empty
        if !isProcessingBatch {
            isAnalyzing = false
        }
    }

    private func pendingPhotos(
        from photos: [(assetID: UUID, image: UIImage)]
    ) -> [PendingPhoto] {
        photos.compactMap { photo in
            guard let cgImage = photo.image.photoAnalysisCGImage else { return nil }
            return PendingPhoto(assetID: photo.assetID, image: cgImage)
        }
    }

    private func enqueue(_ photos: [PendingPhoto]) {
        guard !photos.isEmpty else { return }
        for photo in photos where !analysisOrder.contains(photo.assetID) {
            analysisOrder.append(photo.assetID)
        }
        pendingBatches.append(photos)
        processNextBatchIfNeeded()
    }

    private func processNextBatchIfNeeded() {
        guard !isProcessingBatch else { return }
        guard !pendingBatches.isEmpty else {
            isAnalyzing = false
            persistCurrentResultIfPossible()
            return
        }

        let batch = pendingBatches.removeFirst()
        isProcessingBatch = true
        isAnalyzing = true

        Task {
            let analysis = await service.analyze(images: batch.map(\.image))

            for (photo, result) in zip(batch, analysis.photos) where analysisOrder.contains(photo.assetID) {
                analysisByAssetID[photo.assetID] = result
            }

            evidenceRevision += 1
            await refreshSuggestions(for: evidenceRevision)

            isProcessingBatch = false
            processNextBatchIfNeeded()
        }
    }

    private func refreshSuggestions(for revision: Int) async {
        let analysis = currentAnalysis
        guard !analysis.photos.isEmpty else {
            guard revision == evidenceRevision else { return }
            suggestions = .empty
            recognizedText = []
            photoAnalysisFailures = []
            analysisError = nil
            return
        }

        let nextRecognizedText = analysis.photos.flatMap {
            Self.readingOrderedText($0.main.recognizedText)
        }
        let nextFailures = analysis.photos.flatMap(\.failures)
        let identifiers = identifierExtractor.extract(from: analysis)

        guard revision == evidenceRevision else { return }
        recognizedText = nextRecognizedText
        photoAnalysisFailures = nextFailures
        analysisError = nil
        suggestions = suggestions(
            bibliography: .empty,
            identifiers: identifiers
        )

        do {
            let bibliography = try await extractBibliography(from: analysis)
            guard revision == evidenceRevision else { return }
            suggestions = suggestions(
                bibliography: bibliography,
                identifiers: identifiers
            )
        } catch {
            guard revision == evidenceRevision else { return }
            analysisError = error
        }
    }

    private var currentAnalysis: MultiPhotoAnalysisResult {
        var photos = analysisOrder.compactMap { analysisByAssetID[$0] }
        if let persistedEvidence {
            photos.insert(persistedEvidence.analysisResult, at: 0)
        }
        return MultiPhotoAnalysisResult(photos: photos)
    }

    private static func readingOrderedText(
        _ features: [RecognizedTextFeature]
    ) -> [RecognizedTextFeature] {
        features.sorted { lhs, rhs in
            // Vision coordinates start at the lower-left. Quantizing Y keeps fragments on the same visual row ordered by X.
            let lhsRow = Int((lhs.boundingBox.midY * 50).rounded())
            let rhsRow = Int((rhs.boundingBox.midY * 50).rounded())
            if lhsRow != rhsRow {
                return lhsRow > rhsRow
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
    }

    private func extractBibliography(
        from analysis: MultiPhotoAnalysisResult
    ) async throws -> BookBibliographicExtraction {
        try await BookBibliographicExtractionRace().run(
            extractor: bibliographicExtractor,
            analysis: analysis,
            timeout: bibliographicTimeout
        )
    }

    private func suggestions(
        bibliography: BookBibliographicExtraction,
        identifiers: [SuggestedFieldValue<BookIdentifier>]
    ) -> BookPhotoSuggestions {
        BookPhotoSuggestions(
            title: bibliography.title,
            authors: bibliography.authors,
            identifiers: identifiers,
            publisher: bibliography.publisher,
            publicationYear: bibliography.publicationYear,
            languageCode: bibliography.languageCode,
            series: bibliography.series,
            volumeNumber: bibliography.volumeNumber
        )
    }

    private func persistCurrentResultIfPossible() {
        let analysis = currentAnalysis
        guard !requiresFullAnalysis,
              !analysis.photos.isEmpty,
              let itemID = persistenceItemID,
              let repository = persistenceRepository,
              let evidenceData = try? JSONEncoder().encode(
                ItemRecognitionEvidence(analysis: analysis)
              ),
              let resultData = try? JSONEncoder().encode(
                BookPersistedRecognitionResult(
                    suggestions: suggestions,
                    recognizedText: recognizedText
                )
              ) else {
            return
        }

        _ = repository.saveItemRecognition(
            ItemRecognitionRecord(
                itemID: itemID,
                photoAssetIDs: mediaSnapshot.photoAssetIDs,
                evidenceData: evidenceData,
                resultData: resultData
            )
        )
    }

    private func deletePersistedResult() {
        guard let itemID = persistenceItemID,
              let repository = persistenceRepository else {
            return
        }
        repository.deleteItemRecognition(for: itemID)
    }
}


@MainActor
private final class BookBibliographicExtractionRace {
    private var continuation: CheckedContinuation<BookBibliographicExtraction, Error>?
    private var extractionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func run(
        extractor: any BookBibliographicExtracting,
        analysis: MultiPhotoAnalysisResult,
        timeout: Duration
    ) async throws -> BookBibliographicExtraction {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation

                extractionTask = Task { @MainActor [weak self] in
                    do {
                        let result = try await extractor.extract(from: analysis)
                        self?.finish(.success(result))
                    } catch {
                        self?.finish(.failure(error))
                    }
                }

                timeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }

                    guard !Task.isCancelled else { return }
                    self?.finish(.failure(BookPhotoAnalysisError.bibliographicTimeout))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(.failure(CancellationError()))
            }
        }
    }

    private func finish(_ result: Result<BookBibliographicExtraction, Error>) {
        guard let continuation else { return }

        self.continuation = nil
        extractionTask?.cancel()
        timeoutTask?.cancel()
        extractionTask = nil
        timeoutTask = nil
        continuation.resume(with: result)
    }
}

private extension UIImage {
    /// Bakes UIImage orientation metadata into pixels before passing the image to Vision.
    var photoAnalysisCGImage: CGImage? {
        guard imageOrientation != .up else {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let normalizedImage = UIGraphicsImageRenderer(
            size: size,
            format: format
        ).image { _ in
            // UIImage drawing respects imageOrientation; the rendered bitmap is therefore orientation-normalized.
            draw(in: CGRect(origin: .zero, size: size))
        }

        return normalizedImage.cgImage
    }
}
