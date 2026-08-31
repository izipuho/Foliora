import SwiftUI

/// Displays the publishers used in a single book library.
struct PublishersView: View {
    let collection: CollectionSummary
    let catalogSnapshot: CatalogSnapshot?
    let repository: any CatalogRepository
    let canEditCollection: Bool
    let onBookSelected: ((UUID) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var localPublishers: [Publisher]
    @State private var searchText = ""
    @State private var selectedPublisher: Publisher?

    init(
        collection: CollectionSummary,
        catalogSnapshot: CatalogSnapshot?,
        repository: any CatalogRepository,
        canEditCollection: Bool,
        onBookSelected: ((UUID) -> Void)? = nil
    ) {
        self.collection = collection
        self.catalogSnapshot = catalogSnapshot
        self.repository = repository
        self.canEditCollection = canEditCollection
        self.onBookSelected = onBookSelected
        _localPublishers = State(
            initialValue: Self.libraryPublishers(
                collectionID: collection.id,
                snapshot: catalogSnapshot
            )
        )
    }

    private var books: [BookRecord] {
        catalogSnapshot?.bookRecords.filter { $0.collectionID == collection.id } ?? []
    }

    private var series: [BookSeries] {
        catalogSnapshot?.bookSeries.filter { $0.collectionID == collection.id } ?? []
    }

    private var allBooks: [BookRecord] {
        catalogSnapshot?.bookRecords ?? []
    }

    private var allSeries: [BookSeries] {
        catalogSnapshot?.bookSeries ?? []
    }

    private var filteredPublishers: [Publisher] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return localPublishers
            .filter { publisher in
                query.isEmpty
                    || publisher.name.localizedCaseInsensitiveContains(query)
                    || (publisher.location?.displayName.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { lhs, rhs in
                let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    var body: some View {
        Group {
            if localPublishers.isEmpty {
                emptyState
            } else {
                CatalogContainerList {
                    Section {
                        ForEach(filteredPublishers) { publisher in
                            Button {
                                selectedPublisher = publisher
                            } label: {
                                PublisherCard(
                                    publisher: publisher,
                                    supportingText: usageText(for: publisher),
                                    accentColor: collection.backgroundStyle.accentColor
                                )
                            }
                            .buttonStyle(.plain)
                            .catalogContainerListRow()
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "publisher.search.prompt")
            }
        }
        .background {
            CatalogBackgrounds.collection(
                collection.backgroundStyle.accentColor,
                scheme: colorScheme
            )
            .ignoresSafeArea()
        }
        .navigationTitle("publisher.title.plural")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedPublisher) { publisher in
            PublisherDetailView(
                publisher: publisher,
                books: booksForPublisher(publisher),
                series: seriesForPublisher(publisher),
                allBookCount: allBooks.filter { $0.details.publisher?.id == publisher.id }.count,
                allSeriesCount: allSeries.filter { $0.publisher?.id == publisher.id }.count,
                places: catalogSnapshot?.places ?? [],
                repository: repository,
                canEditCollection: canEditCollection,
                accentColor: collection.backgroundStyle.accentColor,
                onPublisherSaved: upsertLocalPublisher,
                onPublisherDeleted: removeLocalPublisher,
                onBookSelected: onBookSelected
            )
        }
    }

    private var emptyState: some View {
        CatalogEmptyStateView(
            systemImage: "building.2",
            title: "publisher.empty.title",
            message: "publisher.empty.message",
            primaryTint: collection.backgroundStyle.accentColor
        )
    }

    private func booksForPublisher(_ publisher: Publisher) -> [BookRecord] {
        books.filter { $0.details.publisher?.id == publisher.id }
    }

    private func seriesForPublisher(_ publisher: Publisher) -> [BookSeries] {
        series
            .filter { $0.publisher?.id == publisher.id }
            .sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private func usageText(for publisher: Publisher) -> String {
        let bookCount = booksForPublisher(publisher).count
        let seriesCount = seriesForPublisher(publisher).count

        var parts: [String] = []
        if bookCount > 0 {
            parts.append(CollectionKind.bookCountLabel(for: bookCount))
        }
        if seriesCount > 0 {
            parts.append(String(localized: "\(seriesCount) series"))
        }
        return parts.joined(separator: " · ")
    }

    private func upsertLocalPublisher(_ publisher: Publisher) {
        if let index = localPublishers.firstIndex(where: { $0.id == publisher.id }) {
            localPublishers[index] = publisher
        }
    }

    private func removeLocalPublisher(_ publisherID: UUID) {
        localPublishers.removeAll { $0.id == publisherID }
        if selectedPublisher?.id == publisherID {
            selectedPublisher = nil
        }
    }

    private static func libraryPublishers(
        collectionID: UUID,
        snapshot: CatalogSnapshot?
    ) -> [Publisher] {
        guard let snapshot else { return [] }

        let books = snapshot.bookRecords.filter { $0.collectionID == collectionID }
        let series = snapshot.bookSeries.filter { $0.collectionID == collectionID }
        let referencedPublishers = books.compactMap(\.details.publisher) + series.compactMap(\.publisher)
        let referencedIDs = Set(referencedPublishers.map(\.id))

        var publishersByID = Dictionary(
            referencedPublishers.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for publisher in snapshot.publishers where referencedIDs.contains(publisher.id) {
            publishersByID[publisher.id] = publisher
        }

        return Array(publishersByID.values)
    }
}

private struct PublisherCard: View {
    let publisher: Publisher
    let supportingText: String
    let accentColor: Color

    var body: some View {
        HStack(alignment: .center, spacing: CatalogMetrics.Spacing.md) {
            mark

            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
                Text(publisher.name)
                    .font(CatalogTypography.cardTitle)

                if let location = publisher.location {
                    Text(location.displayName)
                        .font(CatalogTypography.cardSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Text(supportingText)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, CatalogMetrics.Spacing.sm)
            }

            Spacer(minLength: CatalogMetrics.Spacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .catalogSurfaceCard()
    }

    @ViewBuilder
    private var mark: some View {
        if let logo = publisher.logo, logo.kind == .photo {
            MediaPreviewImage(
                identifier: logo.localIdentifier,
                originalData: logo.originalData,
                size: CGSize(width: 52, height: 52)
            )
            .frame(width: 52, height: 52)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: CatalogMetrics.CornerRadius.medium,
                    style: .continuous
                )
            )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.medium, style: .continuous)
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 52, height: 52)

                Image(systemName: "building.2.fill")
                    .font(CatalogTypography.cardTitle)
                    .foregroundStyle(accentColor)
            }
        }
    }
}

/// Displays the editor used to create or update a publisher.
struct PublisherEditorView: View {
    private let existingPublisher: Publisher?
    private let places: [Place]
    private let bookCount: Int
    private let seriesCount: Int
    private let onDelete: (() -> Void)?
    private let onSave: (Publisher) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name: String
    @State private var selectedLocation: Place?
    @State private var logoAssets: [MediaAsset]
    @State private var isConfirmingDelete = false

    private let editorPublisherID: UUID

    init(
        publisher: Publisher?,
        places: [Place],
        bookCount: Int = 0,
        seriesCount: Int = 0,
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (Publisher) -> Void
    ) {
        self.existingPublisher = publisher
        self.places = places
        self.bookCount = bookCount
        self.seriesCount = seriesCount
        self.onDelete = onDelete
        self.onSave = onSave
        self.editorPublisherID = publisher?.id ?? UUID()
        _name = State(initialValue: publisher?.name ?? "")
        _selectedLocation = State(initialValue: publisher?.location)
        _logoAssets = State(initialValue: publisher?.logo.map { [$0] } ?? [])
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedLocationLabel: String {
        selectedLocation?.displayName ?? String(localized: "common.none")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("publisher.field.logo") {
                    MediaSection(
                        itemID: editorPublisherID,
                        mediaAssets: $logoAssets,
                        maxMediaCount: 1
                    )
                    .safeAreaPadding(.horizontal, CatalogMetrics.Insets.screen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, CatalogMetrics.Spacing.md)
                    .background(
                        CatalogShapes.section
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .listRowInsets(.init())
                }

                Section {
                    TextField("common.name", text: $name)
                        .focused($isNameFocused)

                    PlacePickerField(
                        title: String(localized: "common.location"),
                        selectedLabel: selectedLocationLabel,
                        places: places,
                        selectedPlace: $selectedLocation
                    )
                }

                if existingPublisher != nil, onDelete != nil {
                    Section {
                        Button("publisher.action.delete", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .navigationTitle(existingPublisher == nil ? String(localized: "publisher.action.add") : String(localized: "publisher.action.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "common.cancel"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        savePublisher()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(String(localized: "common.save"))
                }
            }
            .confirmationDialog(
                "publisher.delete.title",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("publisher.action.delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
            .onAppear {
                if existingPublisher == nil {
                    isNameFocused = true
                }
            }
        }
    }

    private var deleteMessage: String {
        var parts: [String] = []
        if bookCount > 0 {
            parts.append(CollectionKind.bookCountLabel(for: bookCount))
        }
        if seriesCount > 0 {
            parts.append(String(localized: "\(seriesCount) series"))
        }

        guard !parts.isEmpty else {
            return String(localized: "publisher.delete.message")
        }

        return String(localized: "This publisher will be removed from \(parts.joined(separator: " and ")) across the catalog. The books and series will be kept.")
    }

    private func savePublisher() {
        guard canSave else { return }

        let publisher = Publisher(
            id: existingPublisher?.id ?? editorPublisherID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            location: selectedLocation,
            logo: logoAssets.first?.with(sortOrder: 0)
        )

        onSave(publisher)
        dismiss()
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

    if let collection = snapshot.collections
        .compactMap({ snapshot.collectionSummary(id: $0.id) })
        .first(where: { $0.kind == .books }) {
        NavigationStack {
            PublishersView(
                collection: collection,
                catalogSnapshot: snapshot,
                repository: repository,
                canEditCollection: true
            )
        }
        .environment(\.managedObjectContext, container.viewContext)
    }
}
#endif
