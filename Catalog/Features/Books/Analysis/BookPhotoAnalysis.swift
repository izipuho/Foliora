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

    private let service: any PhotoAnalysisService
    private let identifierExtractor: any BookIdentifierExtracting
    private let bibliographicExtractor: any BookBibliographicExtracting

    init() {
        self.service = DefaultPhotoAnalysisService()
        self.identifierExtractor = BookIdentifierExtractor()
        self.bibliographicExtractor = BookBibliographicExtractor()
    }

    init(
        service: any PhotoAnalysisService,
        identifierExtractor: any BookIdentifierExtracting,
        bibliographicExtractor: any BookBibliographicExtracting
    ) {
        self.service = service
        self.identifierExtractor = identifierExtractor
        self.bibliographicExtractor = bibliographicExtractor
    }

    var hasSuggestions: Bool {
        isAnalyzing || suggestions.hasSuggestions
    }

    func analyze(image: UIImage) {
        guard let cgImage = image.cgImage else {
            isAnalyzing = false
            return
        }

        isAnalyzing = true

        Task {
            let analysis = await service.analyze(image: cgImage)
            let identifiers = identifierExtractor.extract(from: analysis)
            let bibliography = await bibliographicExtractor.extract(from: analysis)
            let mappedSuggestions = BookPhotoSuggestions(
                title: bibliography.title,
                authors: bibliography.authors,
                identifiers: identifiers,
                publisher: bibliography.publisher,
                publicationYear: bibliography.publicationYear,
                languageCode: bibliography.languageCode,
                series: bibliography.series,
                volumeNumber: bibliography.volumeNumber
            )

            await MainActor.run {
                self.suggestions = mappedSuggestions
                self.isAnalyzing = false
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
        isAnalyzing = false
    }
}
