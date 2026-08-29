import SwiftUI

/// Displays the series in a single book library.
struct SeriesView: View {
    let collection: CollectionSummary
    let catalogSnapshot: CatalogSnapshot?
    let repository: any CatalogRepository
    let canEditCollection: Bool
    let onBookSelected: ((UUID) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var localSeries: [BookSeries]
    @State private var searchText = ""
    @State private var isPresentingNewSeries = false

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
        _localSeries = State(
            initialValue: catalogSnapshot?.bookSeries.filter { $0.collectionID == collection.id } ?? []
        )
    }

    private var snapshotSeries: [BookSeries] {
        catalogSnapshot?.bookSeries.filter { $0.collectionID == collection.id } ?? []
    }

    private var books: [BookRecord] {
        catalogSnapshot?.bookRecords.filter { $0.collectionID == collection.id } ?? []
    }

    private var filteredSeries: [BookSeries] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return localSeries
            .filter { series in
                query.isEmpty
                    || series.name.localizedCaseInsensitiveContains(query)
                    || (series.publisher?.name.localizedCaseInsensitiveContains(query) ?? false)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var availablePublishers: [Publisher] {
        var publishersByID: [UUID: Publisher] = [:]

        for publisher in books.compactMap(\.details.publisher) + localSeries.compactMap(\.publisher) {
            publishersByID[publisher.id] = publisher
        }

        return publishersByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if localSeries.isEmpty {
                emptyState
            } else {
                CatalogContainerList {
                    Section {
                        ForEach(filteredSeries) { series in
                            NavigationLink {
                                SeriesDetailView(
                                    series: series,
                                    books: booksForSeries(series),
                                    publishers: availablePublishers,
                                    repository: repository,
                                    canEditCollection: canEditCollection,
                                    accentColor: collection.backgroundStyle.accentColor,
                                    onSeriesSaved: upsertLocalSeries,
                                    onBookSelected: onBookSelected
                                )
                            } label: {
                                CatalogContainerCard(
                                    title: series.name,
                                    subtitle: series.publisher?.name,
                                    accessory: .icon("chevron.right"),
                                    supportingText: completionText(for: series),
                                    systemImage: "books.vertical.fill"
                                )
                            }
                            .buttonStyle(.plain)
                            .catalogContainerListRow()
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search series")
            }
        }
        .background {
            CatalogBackgrounds.collection(
                collection.backgroundStyle.accentColor,
                scheme: colorScheme
            )
            .ignoresSafeArea()
        }
        .navigationTitle("Series")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if canEditCollection {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingNewSeries = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Series")
                }
            }
        }
        .sheet(isPresented: $isPresentingNewSeries) {
            SeriesEditorView(
                collectionID: collection.id,
                series: nil,
                publishers: availablePublishers
            ) { series in
                (repository as! any BookCatalogRepository).saveBookSeries(series)
                upsertLocalSeries(series)
            }
        }
        .onChange(of: snapshotSeries) { _, newSeries in
            localSeries = newSeries
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if canEditCollection {
            CatalogEmptyStateView(
                systemImage: "books.vertical",
                title: "No Series",
                message: "This library does not contain any series yet.",
                primaryActionTitle: "Add Series",
                primaryActionSystemImage: "plus.circle.fill",
                primaryTint: collection.backgroundStyle.accentColor,
                primaryAction: { isPresentingNewSeries = true }
            )
        } else {
            CatalogEmptyStateView(
                systemImage: "books.vertical",
                title: "No Series",
                message: "This library does not contain any series yet.",
                primaryTint: collection.backgroundStyle.accentColor
            )
        }
    }

    private func booksForSeries(_ series: BookSeries) -> [BookRecord] {
        books
            .filter { $0.details.series?.id == series.id }
            .sorted { lhs, rhs in
                switch (lhs.details.volumeNumber, rhs.details.volumeNumber) {
                case let (lhsVolume?, rhsVolume?) where lhsVolume != rhsVolume:
                    return lhsVolume < rhsVolume
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
    }

    private func completionText(for series: BookSeries) -> String {
        let collectedCount = booksForSeries(series).count

        guard let totalBookCount = series.totalBookCount else {
            return "\(collectedCount) collected · total unknown"
        }

        if collectedCount >= totalBookCount {
            return "\(collectedCount) of \(totalBookCount) collected · complete"
        }

        return "\(collectedCount) of \(totalBookCount) collected"
    }

    private func upsertLocalSeries(_ series: BookSeries) {
        if let index = localSeries.firstIndex(where: { $0.id == series.id }) {
            localSeries[index] = series
        } else {
            localSeries.append(series)
        }
    }
}

/// Displays the editor used to create or update a book series.
struct SeriesEditorView: View {
    let collectionID: UUID
    private let existingSeries: BookSeries?
    private let publishers: [Publisher]
    private let onSave: (BookSeries) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name: String
    @State private var totalBookCount: String
    @State private var selectedPublisher: Publisher?
    @State private var localPublishers: [Publisher]
    @State private var isPresentingPublisherPicker = false

    init(
        collectionID: UUID,
        series: BookSeries?,
        publishers: [Publisher],
        onSave: @escaping (BookSeries) -> Void
    ) {
        self.collectionID = collectionID
        self.existingSeries = series
        self.publishers = publishers
        self.onSave = onSave
        _name = State(initialValue: series?.name ?? "")
        _totalBookCount = State(initialValue: series?.totalBookCount.map(String.init) ?? "")
        _selectedPublisher = State(initialValue: series?.publisher)
        _localPublishers = State(initialValue: publishers)
    }

    private var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isTotalBookCountValid: Bool {
        let trimmed = totalBookCount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let value = Int(trimmed) else { return false }
        return value > 0
    }

    private var canSave: Bool {
        isNameValid && isTotalBookCountValid
    }

    private var availablePublishers: [Publisher] {
        var publishersByID = Dictionary(
            localPublishers.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        if let selectedPublisher {
            publishersByID[selectedPublisher.id] = selectedPublisher
        }

        return publishersByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Series") {
                    TextField("Name", text: $name)
                        .focused($isNameFocused)

                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                        LabeledContent("Total books") {
#if os(iOS)
                            TextField("—", text: $totalBookCount)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
#else
                            TextField("—", text: $totalBookCount)
                                .multilineTextAlignment(.trailing)
#endif
                        }

                        if !isTotalBookCountValid {
                            Label(
                                "Enter a positive whole number.",
                                systemImage: "exclamationmark.circle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(CatalogSemanticColors.destructive)
                        }
                    }

                    Button {
                        isPresentingPublisherPicker = true
                    } label: {
                        HStack {
                            Text("Publisher")
                                .foregroundStyle(.primary)

                            Spacer()

                            Text(selectedPublisher?.name ?? String(localized: "common.none"))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)

                            Image(systemName: "chevron.right")
                                .font(CatalogTypography.chipLabel)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(existingSeries == nil ? "Add Series" : "Edit Series")
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
                        saveSeries()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(String(localized: "common.save"))
                }
            }
            .sheet(isPresented: $isPresentingPublisherPicker) {
                SeriesPublisherSelectionView(
                    selection: $selectedPublisher,
                    publishers: availablePublishers,
                    onCreate: { publisher in
                        localPublishers.append(publisher)
                        selectedPublisher = publisher
                    }
                )
            }
            .onAppear {
                if existingSeries == nil {
                    isNameFocused = true
                }
            }
        }
    }

    private func saveSeries() {
        guard canSave else { return }

        let trimmedTotal = totalBookCount.trimmingCharacters(in: .whitespacesAndNewlines)
        let series = BookSeries(
            id: existingSeries?.id ?? UUID(),
            collectionID: collectionID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            totalBookCount: trimmedTotal.isEmpty ? nil : Int(trimmedTotal),
            publisher: selectedPublisher
        )

        onSave(series)
        dismiss()
    }
}

private struct SeriesPublisherSelectionView: View {
    @Binding var selection: Publisher?
    let publishers: [Publisher]
    let onCreate: (Publisher) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredPublishers: [Publisher] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return publishers }
        return publishers.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var newPublisherName: String? {
        let candidate = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        guard !publishers.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) else {
            return nil
        }
        return candidate
    }

    var body: some View {
        NavigationStack {
            List {
                if let newPublisherName {
                    Button {
                        let publisher = Publisher(
                            id: UUID(),
                            name: newPublisherName,
                            location: nil,
                            logos: []
                        )
                        onCreate(publisher)
                        selection = publisher
                        dismiss()
                    } label: {
                        Label("Add “\(newPublisherName)”", systemImage: "plus.circle.fill")
                    }
                }

                Button {
                    selection = nil
                    dismiss()
                } label: {
                    HStack {
                        Text(String(localized: "common.none"))
                            .foregroundStyle(.primary)

                        Spacer()

                        if selection == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }

                ForEach(filteredPublishers) { publisher in
                    Button {
                        selection = publisher
                        dismiss()
                    } label: {
                        HStack {
                            Text(publisher.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            if selection?.id == publisher.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Publisher")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search or add")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "common.cancel"))
                }
            }
        }
    }
}
