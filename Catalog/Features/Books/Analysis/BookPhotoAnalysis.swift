import Foundation
import Observation
import UIKit

/// Represents typed suggestions produced from one book photo.
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
            return "The source image cannot be analyzed as a CGImage."
        case .bibliographicTimeout:
            return "Foundation Models bibliographic extraction timed out."
        }
    }
}

/// Orchestrates generic photo analysis and book-specific recognition for one image.
@MainActor
@Observable
final class BookPhotoAnalysisController {
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

    private(set) var isAnalyzing = false
    private(set) var suggestions: BookPhotoSuggestions = .empty
    private(set) var analysisError: (any Error)?

    private let service: any PhotoAnalysisService
    private let identifierExtractor: any BookIdentifierExtracting
    private let bibliographicExtractor: any BookBibliographicExtracting
    private let bibliographicTimeout: Duration

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

    func analyze(image: UIImage) {
        guard let cgImage = image.cgImage else {
            analysisError = BookPhotoAnalysisError.imageUnavailable
            isAnalyzing = false
            return
        }

        suggestions = .empty
        analysisError = nil
        isAnalyzing = true

        Task {
            defer {
                isAnalyzing = false
            }

            let analysis = await service.analyze(image: cgImage)
            let identifiers = identifierExtractor.extract(from: analysis)

            // Deterministic identifiers remain useful even if Foundation Models is unavailable or fails.
            suggestions = suggestions(
                bibliography: .empty,
                identifiers: identifiers
            )

            do {
                let bibliography = try await extractBibliography(from: analysis)
                suggestions = suggestions(
                    bibliography: bibliography,
                    identifiers: identifiers
                )
            } catch {
                // Convert the failure into explicit controller state without discarding partial results.
                analysisError = error
            }
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
    }

    func clear() {
        suggestions = .empty
        analysisError = nil
        isAnalyzing = false
    }

    private func extractBibliography(
        from analysis: PhotoAnalysisResult
    ) async throws -> BookBibliographicExtraction {
        let extractor = bibliographicExtractor
        let timeout = bibliographicTimeout

        return try await withThrowingTaskGroup(of: BookBibliographicExtraction.self) { group in
            group.addTask {
                try await extractor.extract(from: analysis)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BookPhotoAnalysisError.bibliographicTimeout
            }

            guard let result = try await group.next() else {
                throw CancellationError()
            }

            group.cancelAll()
            return result
        }
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
}
