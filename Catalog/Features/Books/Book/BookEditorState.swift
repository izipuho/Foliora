import Foundation

/// Holds the editable book draft and book-specific validation needed to persist it.
struct BookEditorState {
    var itemState: ItemEditorState
    var subtitle: String
    var coverImage: MediaAsset?

    var languageCode: String
    var genre: String
    var pageCount: String
    var selectedPublicationYearOption: String
    var selectedSeries: BookSeries?
    var volumeNumber: String
    var selectedPublisher: Publisher?
    var contributors: [BookContributor]
    var identifiers: [BookIdentifier]

    private let existingPublicationYear: Int?

    init(
        book: BookRecord?,
        initialMediaAssets: [MediaAsset]
    ) {
        itemState = ItemEditorState(
            item: book?.item,
            initialMediaAssets: initialMediaAssets
        )
        subtitle = book?.details.subtitle ?? ""
        coverImage = book?.details.coverImage?.with(
            displayName: String(localized: "editor.media.cover")
        )

        languageCode = book?.details.languageCode ?? ""
        genre = book?.details.genre ?? ""
        pageCount = book?.details.pageCount.map(String.init) ?? ""
        selectedPublicationYearOption = book?.details.publicationYear.map(String.init) ?? String(localized: "common.none")
        selectedSeries = book?.details.series
        volumeNumber = book?.details.volumeNumber.map(String.init) ?? ""
        selectedPublisher = book?.details.publisher
        contributors = (book?.details.contributors ?? []).sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.person.sortName.localizedCaseInsensitiveCompare($1.person.sortName) == .orderedAscending
        }
        identifiers = book?.details.identifiers ?? []
        existingPublicationYear = book?.details.publicationYear
    }

    var title: String {
        get { itemState.title }
        set { itemState.title = newValue }
    }

    var notes: String {
        get { itemState.notes }
        set { itemState.notes = newValue }
    }

    var selectedAcquiredYearOption: String {
        get { itemState.selectedAcquiredYearOption }
        set { itemState.selectedAcquiredYearOption = newValue }
    }

    var condition: ItemCondition {
        get { itemState.condition }
        set { itemState.condition = newValue }
    }

    var acquisitionMethod: AcquisitionMethod {
        get { itemState.acquisitionMethod }
        set { itemState.acquisitionMethod = newValue }
    }

    var selectedLocationID: UUID? {
        get { itemState.selectedLocationID }
        set { itemState.selectedLocationID = newValue }
    }

    var tags: [String] {
        get { itemState.tags }
        set { itemState.tags = newValue }
    }

    var mediaAssets: [MediaAsset] {
        get { itemState.mediaAssets }
        set { itemState.mediaAssets = newValue }
    }

    var publicationYearOptions: [String] {
        let none = String(localized: "common.none")
        let currentYear = Calendar.current.component(.year, from: .now)
        var years = Array(1900...currentYear).map(String.init)

        if let existingPublicationYear {
            let value = String(existingPublicationYear)
            if !years.contains(value) {
                years.append(value)
            }
        }

        if Int(selectedPublicationYearOption) != nil,
           !years.contains(selectedPublicationYearOption) {
            years.append(selectedPublicationYearOption)
        }

        years.sort { (Int($0) ?? 0) > (Int($1) ?? 0) }
        return [none] + years
    }

    var isTitleValid: Bool {
        itemState.isTitleValid
    }

    var isVolumeValid: Bool {
        guard let selectedSeries else { return true }

        let trimmed = volumeNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let number = Int(trimmed), number > 0 else { return false }

        if let totalBookCount = selectedSeries.totalBookCount {
            return number <= totalBookCount
        }

        return true
    }

    var volumeValidationMessage: String {
        if let totalBookCount = selectedSeries?.totalBookCount {
            return String.localizedStringWithFormat(
                String(localized: "common.validation.whole_number_range_1_to_max"),
                totalBookCount
            )
        }

        return String(localized: "book.validation.positive_whole_number")
    }

    func isOptionalPositiveIntegerValid(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let number = Int(trimmed) else { return false }
        return number > 0
    }

    func canSave(isGeneratingCoverImage: Bool) -> Bool {
        isTitleValid
            && isOptionalPositiveIntegerValid(pageCount)
            && isVolumeValid
            && !isGeneratingCoverImage
    }

    func makeBook(
        itemID: UUID,
        collectionID: UUID,
        existingBook: BookRecord?
    ) -> BookRecord {
        let normalizedContributors = contributors.enumerated().map { index, contributor in
            var normalized = contributor
            normalized.order = index
            return normalized
        }
        let existingItem = existingBook?.item

        return BookRecord(
            item: itemState.makeItemRecord(
                itemID: itemID,
                collectionID: existingItem?.collectionID ?? collectionID,
                kind: .books,
                createdAt: existingItem?.createdAt ?? .now,
                createdBy: existingItem?.createdBy ?? "me",
                isFavorite: existingItem?.isFavorite ?? false,
                originPlaceID: existingItem?.originPlaceID,
                originPlace: existingItem?.originPlace,
                storageLocation: existingItem?.storageLocation,
                storagePath: existingItem?.storagePath
            ),
            details: BookDetails(
                itemID: itemID,
                subtitle: Self.optionalString(subtitle),
                languageCode: Self.optionalString(languageCode)?.lowercased(),
                genre: Self.optionalString(genre),
                pageCount: Self.optionalPositiveInt(pageCount),
                publicationYear: Int(selectedPublicationYearOption),
                volumeNumber: selectedSeries == nil ? nil : Self.optionalPositiveInt(volumeNumber),
                coverImage: coverImage,
                publisher: selectedPublisher,
                contributors: normalizedContributors,
                series: selectedSeries,
                identifiers: identifiers
            )
        )
    }

    private static func optionalString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func optionalPositiveInt(_ value: String) -> Int? {
        guard let number = optionalString(value).flatMap(Int.init), number > 0 else { return nil }
        return number
    }
}
