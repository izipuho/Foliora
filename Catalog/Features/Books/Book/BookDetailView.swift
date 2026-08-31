import Foundation
import SwiftUI

#if DEBUG
import CoreData
#endif

private enum BookReferenceDestination: Hashable {
    case person(Person)
    case publisher(Publisher)
    case series(BookSeries)
}

/// Displays the catalog details for a single book.
struct BookDetailView: View {
    @Binding var book: BookRecord
    let repository: any CatalogRepository
    let catalogSnapshot: CatalogSnapshot?
    let canEditCollection: Bool
    let canChangeFavorite: Bool
    let onClose: (() -> Void)?

    @State private var draftNotes = ""
    @State private var draftTags: [String] = []
    @State private var tagInput = ""
    @State private var isPresentingEditor = false
    @State private var isPresentingLocationPicker = false
    @State private var isPresentingHomeEditor = false
    @State private var draftHome = Home(id: UUID(), name: "", iconName: "house.fill", notes: "")
    @State private var draftHomeLocations: [Location] = []
    @State private var shouldPresentLocationPickerAfterHomeEditor = false
    @State private var isPresentingUnsavedChangesConfirmation = false

    init(
        book: Binding<BookRecord>,
        repository: any CatalogRepository,
        catalogSnapshot: CatalogSnapshot?,
        canEditCollection: Bool,
        canChangeFavorite: Bool = false,
        onClose: (() -> Void)? = nil
    ) {
        _book = book
        self.repository = repository
        self.catalogSnapshot = catalogSnapshot
        self.canEditCollection = canEditCollection
        self.canChangeFavorite = canChangeFavorite
        self.onClose = onClose
    }

    var body: some View {
        MediaQuickLookPresenter(mediaAssets: book.mediaAssets) { preview in
            ScrollView {
                VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.lg) {
                    header(preview: preview)

                    if hasBookInformation {
                        bookInformationSection
                            .padding(.horizontal, CatalogMetrics.Insets.screen)
                    }

                    collectionInformationSection
                        .padding(.horizontal, CatalogMetrics.Insets.screen)

                    locationSection
                        .padding(.horizontal, CatalogMetrics.Insets.screen)

                    notesAndTagsSection

                    if !detailMediaAssets.isEmpty || canEditCollection {
                        mediaSection
                            .padding(.horizontal, CatalogMetrics.Insets.screen)
                    }

                    if !book.details.identifiers.isEmpty {
                        identifiersSection
                            .padding(.horizontal, CatalogMetrics.Insets.screen)
                    }
                }
                .padding(.top, CatalogMetrics.Spacing.md)
                .padding(.bottom, CatalogMetrics.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
            .interactiveDismissDisabled(canEditCollection && isNotesOrTagsDirty)
            .navigationTitle(book.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                CatalogItemDetailToolbar(
                    onClose: onClose,
                    favorite: favoriteToolbarAction,
                    contentState: detailToolbarState
                )
            }
            .navigationDestination(for: BookReferenceDestination.self) { destination in
                referenceDestination(destination)
            }
            .confirmationDialog(
                String(localized: "item.detail.unsaved_changes.title"),
                isPresented: $isPresentingUnsavedChangesConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "common.save")) {
                    saveNotesAndTagsChanges()
                }

                Button(String(localized: "item.detail.unsaved_changes.discard"), role: .destructive) {
                    discardNotesAndTagsChanges()
                }

                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "item.detail.unsaved_changes.message"))
            }
            .sheet(isPresented: $isPresentingEditor) {
                if canEditCollection, let collection = inferredCollection {
                    BookEditorView(
                        collection: collection,
                        book: book
                    ) { updatedBook in
                        save(updatedBook)
                        syncDraftsFromBook()
                    }
                }
            }
            .sheet(isPresented: $isPresentingLocationPicker) {
                LocationHierarchyPickerView(
                    locations: availableLocations,
                    selectedLocationID: locationIDBinding
                )
            }
            .sheet(isPresented: $isPresentingHomeEditor) {
                HomeEditorView(
                    home: $draftHome,
                    locations: $draftHomeLocations,
                    onSave: {
                        repository.saveHome(draftHome)
                        repository.saveLocations(draftHomeLocations, in: draftHome.id)
                        continueLocationSelectionIfNeeded()
                    },
                    onDelete: nil
                )
            }
            .onAppear {
                syncDraftsFromBook()
            }
            .onChange(of: book) { _, _ in
                guard !isNotesOrTagsDirty else { return }
                syncDraftsFromBook()
            }
        }
    }

    private var detailToolbarState: CatalogItemDetailToolbar.ContentState {
        guard canEditCollection else { return .readOnly }

        if isNotesOrTagsDirty {
            return .pendingChanges(
                onCancel: requestDiscardNotesAndTagsChanges,
                onSave: saveNotesAndTagsChanges
            )
        }

        return .viewing {
            isPresentingEditor = true
        }
    }

    private var favoriteToolbarAction: CatalogItemDetailToolbar.FavoriteAction? {
        guard canChangeFavorite else { return nil }

        return CatalogItemDetailToolbar.FavoriteAction(
            isFavorite: book.isFavorite,
            action: toggleFavorite
        )
    }

    private func header(preview: @escaping (MediaAsset) -> Void) -> some View {
        HStack(alignment: .top, spacing: CatalogMetrics.Spacing.lg) {
            cover(preview: preview)

            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
                if !authorContributors.isEmpty {
                    TagFlowLayout(spacing: CatalogMetrics.Spacing.xs) {
                        ForEach(Array(authorContributors.enumerated()), id: \.offset) { _, contributor in
                            NavigationLink(value: BookReferenceDestination.person(contributor.person)) {
                                HStack(spacing: CatalogMetrics.Spacing.xs) {
                                    Text(contributor.person.name)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                }
                                .font(CatalogTypography.cardLabel)
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text(book.title)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if let series = book.details.series,
                   let headerSeriesDisplayName {
                    NavigationLink(value: BookReferenceDestination.series(series)) {
                        HStack(spacing: CatalogMetrics.Spacing.xs) {
                            Text(headerSeriesDisplayName)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(CatalogTypography.cardSubtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CatalogMetrics.Insets.screen)
    }

    @ViewBuilder
    private func cover(preview: @escaping (MediaAsset) -> Void) -> some View {
        if let coverPhoto {
            MediaPreviewImage(
                identifier: coverPhoto.localIdentifier.isEmpty ? nil : coverPhoto.localIdentifier,
                originalData: coverPhoto.originalData,
                size: CGSize(width: 112, height: 158)
            )
            .frame(width: 112, height: 158)
            .clipShape(RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.thumbnail, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                preview(coverPhoto)
            }
        } else {
            RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.thumbnail, style: .continuous)
                .fill(.secondary.opacity(0.12))
                .frame(width: 112, height: 158)
                .overlay {
                    Image(systemName: "book.closed")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var bookInformationSection: some View {
        detailSection(String(localized: "common.book")) {
            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
                if hasBookMetadataCardContent {
                    bookMetadataCard
                }

                if !otherContributors.isEmpty {
                    Text("book.section.contributors")
                        .font(CatalogTypography.sectionTitle)

                    contributorsCard
                }
            }
        }
    }

    private var bookMetadataCard: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.lg) {
            if let publisher = book.details.publisher {
                NavigationLink(value: BookReferenceDestination.publisher(publisher)) {
                    HStack(alignment: .center, spacing: CatalogMetrics.Spacing.sm) {
                        metadataField(
                            title: String(localized: "publisher.title"),
                            value: publisher.name,
                            systemImage: "building.2"
                        )

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: CatalogMetrics.Spacing.lg, alignment: .top),
                    GridItem(.flexible(), alignment: .top)
                ],
                alignment: .leading,
                spacing: CatalogMetrics.Spacing.lg
            ) {
                if let publicationYear = book.details.publicationYear {
                    metadataField(
                        title: String(localized: "book.field.publication_year"),
                        value: String(publicationYear),
                        systemImage: "calendar"
                    )
                }

                if let pageCount = book.details.pageCount {
                    metadataField(
                        title: String(localized: "book.field.pages"),
                        value: String(pageCount),
                        systemImage: "doc.text"
                    )
                }

                if let languageCode = book.details.languageCode, !languageCode.isEmpty {
                    metadataField(
                        title: String(localized: "book.field.language"),
                        value: bookLanguageDisplayName(for: languageCode),
                        systemImage: "globe"
                    )
                }

                if let genre = book.details.genre, !genre.isEmpty {
                    metadataField(
                        title: String(localized: "book.field.genre"),
                        value: genre,
                        systemImage: "tag"
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CatalogMetrics.Spacing.lg)
        .background {
            CatalogShapes.section
                .fill(.ultraThinMaterial)
        }
    }

    private var contributorsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(otherContributors.enumerated()), id: \.offset) { index, contributor in
                NavigationLink(value: BookReferenceDestination.person(contributor.person)) {
                    HStack(alignment: .firstTextBaseline, spacing: CatalogMetrics.Spacing.md) {
                        Label(contributor.role.title, systemImage: "person.crop.circle")
                            .font(CatalogTypography.cardSubtitle)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: CatalogMetrics.Spacing.md)

                        Text(contributor.person.name)
                            .font(CatalogTypography.cardLabel)
                            .multilineTextAlignment(.trailing)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if index < otherContributors.count - 1 {
                    Divider()
                        .padding(.vertical, CatalogMetrics.Spacing.md)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CatalogMetrics.Spacing.lg)
        .background {
            CatalogShapes.section
                .fill(.ultraThinMaterial)
        }
    }

    private var collectionInformationSection: some View {
        detailSection(String(localized: "item.detail.section.collection_info")) {
            HStack(alignment: .top, spacing: CatalogMetrics.Spacing.lg) {
                if let acquiredYear = book.acquiredYear {
                    metadataField(
                        title: String(localized: "item.detail.acquisition_year"),
                        value: String(acquiredYear),
                        systemImage: "calendar.badge.plus"
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                metadataField(
                    title: String(localized: "item.detail.acquisition"),
                    value: book.acquisitionMethod.displayName,
                    systemImage: "bag"
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)

                metadataField(
                    title: String(localized: "common.field.condition"),
                    value: book.condition.displayName,
                    systemImage: "checkmark.seal"
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(CatalogMetrics.Spacing.lg)
            .background {
                CatalogShapes.section
                    .fill(.ultraThinMaterial)
            }
        }
    }

    private var locationSection: some View {
        detailSection(String(localized: "item.detail.section.location")) {
            CatalogStorageTile(
                storagePath: storageDisplayPath,
                accentColor: detailAccentColor,
                isAssigned: book.item.locationID != nil,
                canEdit: canEditCollection,
                onEdit: {
                    if availableLocations.isEmpty, let inferredCollection {
                        presentHomeEditor(for: inferredCollection.homeID)
                    } else {
                        isPresentingLocationPicker = true
                    }
                }
            )
        }
    }

    private var notesAndTagsSection: some View {
        detailSection(String(localized: "common.field.notes")) {
            if canEditCollection {
                TextField(String(localized: "editor.note_history"), text: $draftNotes, axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.plain)

                TagEditorSection(
                    tagInput: $tagInput,
                    tags: $draftTags
                )
            } else {
                Text(book.notes.isEmpty ? String(localized: "editor.note_history") : book.notes)
                    .foregroundStyle(book.notes.isEmpty ? .secondary : .primary)

                if book.tags.isEmpty {
                    Text(String(localized: "editor.tags.empty"))
                        .font(CatalogTypography.cardSubtitle)
                        .foregroundStyle(.secondary)
                } else {
                    TagFlowLayout(spacing: CatalogMetrics.Spacing.sm) {
                        ForEach(book.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(CatalogTypography.cardSubtitle)
                                .catalogSurfaceCapsule()
                        }
                    }
                }
            }
        }
        .padding(CatalogMetrics.Spacing.lg)
        .background(
            CatalogShapes.section
                .fill(isNotesOrTagsDirty ? AnyShapeStyle(detailAccentColor.opacity(0.10)) : AnyShapeStyle(.ultraThinMaterial))
        )
        .padding(.horizontal, CatalogMetrics.Insets.screen)
    }

    private var mediaSection: some View {
        detailSection(String(localized: "editor.docs_and_media")) {
            MediaSection(
                itemID: book.id,
                mediaAssets: detailMediaAssetsBinding,
                allowsAdding: canEditCollection,
                allowsDeletion: false
            )
        }
    }

    private var identifiersSection: some View {
        detailSection("book.section.identifiers") {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: CatalogMetrics.Spacing.lg, alignment: .top),
                    GridItem(.flexible(), alignment: .top)
                ],
                alignment: .leading,
                spacing: CatalogMetrics.Spacing.lg
            ) {
                ForEach(Array(book.details.identifiers.enumerated()), id: \.offset) { _, identifier in
                    identifierField(identifier)
                }
            }
            .padding(CatalogMetrics.Spacing.lg)
            .background {
                CatalogShapes.section
                    .fill(.ultraThinMaterial)
            }
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            Text(title)
                .font(CatalogTypography.sectionTitle)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataField(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
            Label(title, systemImage: systemImage)
                .font(CatalogTypography.cardSubtitle)
                .foregroundStyle(.secondary)

            Text(value)
                .font(CatalogTypography.cardLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func identifierField(_ identifier: BookIdentifier) -> some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
            Text(identifier.type.title)
                .font(CatalogTypography.cardSubtitle)
                .foregroundStyle(.secondary)

            Text(identifier.value)
                .monospaced()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var coverPhoto: MediaAsset? {
        book.mediaAssets
            .filter { $0.kind == .photo }
            .sorted { $0.sortOrder < $1.sortOrder }
            .first
    }

    private var detailMediaAssets: [MediaAsset] {
        guard let coverPhoto else { return book.mediaAssets }
        return book.mediaAssets.filter { $0.id != coverPhoto.id }
    }

    private var detailMediaAssetsBinding: Binding<[MediaAsset]> {
        Binding(
            get: { detailMediaAssets },
            set: { updatedDetailAssets in
                guard canEditCollection else { return }
                let updatedAssets = coverPhoto.map { [$0] + updatedDetailAssets } ?? updatedDetailAssets
                persist(mediaAssets: updatedAssets)
            }
        )
    }

    private var authorContributors: [BookContributor] {
        book.details.contributors
            .filter { $0.role == .author }
            .sorted { $0.order < $1.order }
    }

    private var otherContributors: [BookContributor] {
        book.details.contributors
            .filter { $0.role != .author }
            .sorted { $0.order < $1.order }
    }

    private var headerSeriesDisplayName: String? {
        guard let series = book.details.series else { return nil }

        if let volumeNumber = book.details.volumeNumber {
            return "\(series.name) · \(String(localized: "book.field.volume")) \(volumeDisplayName(volumeNumber))"
        }

        return series.name
    }

    private var hasBookMetadataCardContent: Bool {
        book.details.publisher != nil
            || book.details.publicationYear != nil
            || book.details.pageCount != nil
            || !(book.details.languageCode?.isEmpty ?? true)
            || !(book.details.genre?.isEmpty ?? true)
    }

    private var hasBookInformation: Bool {
        hasBookMetadataCardContent || !otherContributors.isEmpty
    }

    private func volumeDisplayName(_ volumeNumber: Int) -> String {
        if let totalBookCount = book.details.series?.totalBookCount {
            return String.localizedStringWithFormat(
                String(localized: "common.progress.count_of_total"),
                volumeNumber,
                totalBookCount
            )
        }

        return String(volumeNumber)
    }

    private func bookLanguageDisplayName(for code: String) -> String {
        BookLanguageFormatter.displayName(for: code)
    }

    private var storageDisplayPath: String {
        guard let storagePath = book.storagePath, !storagePath.isEmpty else {
            return book.storageLocation?.name ?? String(localized: "common.unassigned")
        }

        return storagePath.displayPath
    }

    private var availableLocations: [Location] {
        guard let snapshot = catalogSnapshot,
              let collection = inferredCollection else { return [] }

        let collectionLocations = snapshot.collectionLocationsByCollectionID[collection.id] ?? []
        if !collectionLocations.isEmpty {
            return collectionLocations
        }

        return snapshot.locationsByHomeID[collection.homeID] ?? []
    }

    private var inferredCollection: CollectionSummary? {
        catalogSnapshot?.collectionSummary(id: book.collectionID)
    }

    private var detailAccentColor: Color {
        inferredCollection?.backgroundStyle.accentColor ?? Color.accentColor
    }

    private var libraryBooks: [BookRecord] {
        catalogSnapshot?.bookRecords.filter { $0.collectionID == book.collectionID } ?? []
    }

    private var allBooks: [BookRecord] {
        catalogSnapshot?.bookRecords ?? []
    }

    private var librarySeries: [BookSeries] {
        catalogSnapshot?.bookSeries.filter { $0.collectionID == book.collectionID } ?? []
    }

    private var allSeries: [BookSeries] {
        catalogSnapshot?.bookSeries ?? []
    }

    private var availablePublishersForSeries: [Publisher] {
        var publishersByID: [UUID: Publisher] = [:]

        for publisher in libraryBooks.compactMap(\.details.publisher) + librarySeries.compactMap(\.publisher) {
            publishersByID[publisher.id] = publisher
        }

        for publisher in catalogSnapshot?.publishers ?? [] where publishersByID[publisher.id] != nil {
            publishersByID[publisher.id] = publisher
        }

        return publishersByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @ViewBuilder
    private func referenceDestination(_ destination: BookReferenceDestination) -> some View {
        switch destination {
        case .person(let person):
            let resolvedPerson = catalogSnapshot?.people.first(where: { $0.id == person.id }) ?? person
            PersonDetailView(
                person: resolvedPerson,
                books: libraryBooks.filter { candidate in
                    candidate.details.contributors.contains { $0.person.id == person.id }
                },
                allBookCount: allBooks.filter { candidate in
                    candidate.details.contributors.contains { $0.person.id == person.id }
                }.count,
                places: catalogSnapshot?.places ?? [],
                repository: repository,
                canEditCollection: canEditCollection,
                accentColor: detailAccentColor,
                onPersonSaved: updatePersonReference,
                onPersonDeleted: { _ in }
            )

        case .publisher(let publisher):
            let resolvedPublisher = catalogSnapshot?.publishers.first(where: { $0.id == publisher.id }) ?? publisher
            PublisherDetailView(
                publisher: resolvedPublisher,
                books: libraryBooks.filter { $0.details.publisher?.id == publisher.id },
                series: librarySeries.filter { $0.publisher?.id == publisher.id },
                allBookCount: allBooks.filter { $0.details.publisher?.id == publisher.id }.count,
                allSeriesCount: allSeries.filter { $0.publisher?.id == publisher.id }.count,
                places: catalogSnapshot?.places ?? [],
                repository: repository,
                canEditCollection: canEditCollection,
                accentColor: detailAccentColor,
                onPublisherSaved: updatePublisherReference,
                onPublisherDeleted: { _ in }
            )

        case .series(let series):
            let resolvedSeries = catalogSnapshot?.bookSeries.first(where: { $0.id == series.id }) ?? series
            SeriesDetailView(
                series: resolvedSeries,
                books: libraryBooks.filter { $0.details.series?.id == series.id },
                publishers: availablePublishersForSeries,
                repository: repository,
                canEditCollection: canEditCollection,
                accentColor: detailAccentColor,
                onSeriesSaved: updateSeriesReference,
                onSeriesDeleted: { _ in }
            )
        }
    }

    private func updatePersonReference(_ person: Person) {
        var details = book.details
        details.contributors = details.contributors.map { contributor in
            guard contributor.person.id == person.id else { return contributor }
            var updatedContributor = contributor
            updatedContributor.person = person
            return updatedContributor
        }
        book = BookRecord(item: book.item, details: details)
    }

    private func updatePublisherReference(_ publisher: Publisher) {
        var details = book.details

        if details.publisher?.id == publisher.id {
            details.publisher = publisher
        }

        if var series = details.series, series.publisher?.id == publisher.id {
            series.publisher = publisher
            details.series = series
        }

        book = BookRecord(item: book.item, details: details)
    }

    private func updateSeriesReference(_ series: BookSeries) {
        guard book.details.series?.id == series.id else { return }
        var details = book.details
        details.series = series
        book = BookRecord(item: book.item, details: details)
    }

    private var isNotesOrTagsDirty: Bool {
        draftNotes != book.notes || draftTags != book.tags
    }

    private func syncDraftsFromBook() {
        draftNotes = book.notes
        draftTags = book.tags
        tagInput = ""
    }

    private func presentHomeEditor(for homeID: UUID) {
        guard let snapshot = catalogSnapshot,
              let home = snapshot.homes.first(where: { $0.id == homeID }) else { return }
        draftHome = home
        draftHomeLocations = snapshot.locationsByHomeID[homeID] ?? []
        shouldPresentLocationPickerAfterHomeEditor = true
        isPresentingHomeEditor = true
    }

    private func continueLocationSelectionIfNeeded() {
        guard shouldPresentLocationPickerAfterHomeEditor else { return }
        shouldPresentLocationPickerAfterHomeEditor = false
        isPresentingHomeEditor = false
        DispatchQueue.main.async {
            isPresentingLocationPicker = true
        }
    }

    private var locationIDBinding: Binding<UUID?> {
        Binding(
            get: { book.item.locationID },
            set: {
                guard canEditCollection else { return }
                persistStorage(locationID: $0)
            }
        )
    }

    private func requestDiscardNotesAndTagsChanges() {
        guard canEditCollection, isNotesOrTagsDirty else { return }
        isPresentingUnsavedChangesConfirmation = true
    }

    private func discardNotesAndTagsChanges() {
        syncDraftsFromBook()
    }

    private func saveNotesAndTagsChanges() {
        guard canEditCollection else { return }
        persist(
            notes: draftNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: draftTags
        )
        syncDraftsFromBook()
    }

    private func toggleFavorite() {
        guard canChangeFavorite else { return }
        var updatedItem = book.item
        updatedItem.isFavorite.toggle()
        book = BookRecord(item: updatedItem, details: book.details)
        repository.setFavorite(updatedItem.isFavorite, for: updatedItem.id)
    }

    private func persist(
        notes: String? = nil,
        tags: [String]? = nil,
        mediaAssets: [MediaAsset]? = nil
    ) {
        guard canEditCollection else { return }
        var updatedItem = book.item

        if let notes {
            updatedItem.notes = notes
        }

        if let tags {
            updatedItem.tags = tags
        }

        if let mediaAssets {
            updatedItem.mediaAssets = mediaAssets
                .enumerated()
                .map { index, asset in
                    asset.with(itemID: book.id, sortOrder: index)
                }
        }

        save(updatedItem)
    }

    private func persistStorage(locationID: UUID?) {
        guard canEditCollection else { return }
        var updatedItem = book.item
        let location = locationID.flatMap { id in
            availableLocations.first { $0.id == id }
        }
        let locationsByID = Dictionary(uniqueKeysWithValues: availableLocations.map { ($0.id, $0) })
        let path = location.map { storagePath(for: $0, locationsByID: locationsByID) }
        updatedItem.setStorageLocation(location, path: path)
        save(updatedItem)
    }

    private func save(_ item: ItemRecord) {
        let updatedBook = BookRecord(item: item, details: book.details)
        save(updatedBook)
    }

    private func save(_ updatedBook: BookRecord) {
        book = updatedBook
        (repository as! any BookCatalogRepository).saveBookRecord(updatedBook)
    }

    private func storagePath(for location: Location, locationsByID: [UUID: Location]) -> StoragePath {
        var components = [
            StoragePath.Component(
                kind: location.kind,
                name: location.name
            )
        ]
        var currentParentID = location.parentLocationID

        while let parentID = currentParentID, let parent = locationsByID[parentID] {
            components.insert(
                StoragePath.Component(
                    kind: parent.kind,
                    name: parent.name
                ),
                at: 0
            )
            currentParentID = parent.parentLocationID
        }

        return StoragePath(components: components)
    }
}

/// Resolves a book by identifier and keeps the presented detail synchronized with the catalog snapshot.
struct BookDetailContainer: View {
    let bookID: UUID
    let repository: any CatalogRepository
    let catalogSnapshot: CatalogSnapshot?
    let onClose: (() -> Void)?

    @State private var book: BookRecord?
    @State private var collectionSharingState: CollectionSharingState?
    @State private var collectionSharingLoadError: Error?

    init(
        bookID: UUID,
        repository: any CatalogRepository,
        catalogSnapshot: CatalogSnapshot?,
        onClose: (() -> Void)? = nil
    ) {
        self.bookID = bookID
        self.repository = repository
        self.catalogSnapshot = catalogSnapshot
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            if let bookBinding {
                BookDetailView(
                    book: bookBinding,
                    repository: repository,
                    catalogSnapshot: catalogSnapshot,
                    canEditCollection: canEditCollection,
                    canChangeFavorite: canChangeFavorite,
                    onClose: onClose
                )
            } else {
                CatalogEmptyStateView(
                    systemImage: "book.closed",
                    title: "book.not_found.title",
                    message: "book.not_found.message"
                )
            }
        }
        .task(id: bookID) {
            syncBookFromCatalogSnapshot()
        }
        .task(id: currentCollectionID) {
            await loadCollectionSharingState()
        }
        .onChange(of: catalogSnapshot?.recordsByID[bookID]) { _, _ in
            syncBookFromCatalogSnapshot()
        }
    }

    private var canEditCollection: Bool {
        guard collectionSharingLoadError == nil else { return false }

        switch collectionSharingState?.currentUserRole {
        case .owner, .contributor:
            return true
        case .viewer, nil:
            return false
        }
    }

    private var canChangeFavorite: Bool {
        guard collectionSharingLoadError == nil else { return false }

        switch collectionSharingState?.currentUserRole {
        case .owner:
            return true
        case .contributor, .viewer, nil:
            return false
        }
    }

    private var bookBinding: Binding<BookRecord>? {
        guard let currentBook = book else { return nil }

        return Binding(
            get: {
                book ?? currentBook
            },
            set: {
                book = $0
            }
        )
    }

    private var currentCollectionID: UUID? {
        book?.collectionID ?? catalogSnapshot?.recordsByID[bookID]?.collectionID
    }

    private func syncBookFromCatalogSnapshot() {
        book = catalogSnapshot?.recordsByID[bookID]
    }

    @MainActor
    private func loadCollectionSharingState() async {
        collectionSharingState = nil
        collectionSharingLoadError = nil

        guard let collectionID = currentCollectionID,
              let persistentContainer = FolioraAppDelegate.coreDataContainer else {
            return
        }

        do {
            collectionSharingState = try await CloudKitCollectionSharingService(
                persistentContainer: persistentContainer
            ).sharingState(for: collectionID)
        } catch {
            collectionSharingLoadError = error
        }
    }
}

private extension BookContributorRole {
    var title: String {
        switch self {
        case .author: return String(localized: "book_contributor.role.author")
        case .translator: return String(localized: "book_contributor.role.translator")
        case .editor: return String(localized: "book_contributor.role.editor")
        case .illustrator: return String(localized: "book_contributor.role.illustrator")
        }
    }
}

private extension BookIdentifierType {
    var title: String {
        switch self {
        case .isbn10: return "ISBN-10"
        case .isbn13: return "ISBN-13"
        case .asin: return "ASIN"
        case .inventory: return String(localized: "book.field.inventory")
        case .other: return String(localized: "common.other")
        }
    }
}

#if DEBUG
#Preview {
    let container = PreviewContainer.makeBooksMinimal()
    let repository = CoreDataCatalogRepository(
        context: container.viewContext,
        persistentContainer: nil
    )
    let snapshot = CatalogSnapshot.load(from: container.viewContext)

    if let book = snapshot.bookRecords.first {
        BookDetailContainer(
            bookID: book.id,
            repository: repository,
            catalogSnapshot: snapshot
        )
        .environment(\.managedObjectContext, container.viewContext)
    }
}
#endif
