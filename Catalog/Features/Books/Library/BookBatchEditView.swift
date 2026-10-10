import SwiftUI

/// Edits shared and book-specific fields for multiple selected books.
struct BookBatchEditView: View {
    let collectionID: UUID
    let people: [Person]
    let series: [BookSeries]
    let publishers: [Publisher]
    let onSave: (ItemBatchEdit, BookBatchEdit) -> Void

    @State private var contributorEdits: [BookContributorBatchEdit] = []
    @State private var editingContributorIndex: Int?
    @State private var isPresentingContributorEditor = false
    @State private var selectedSeries: BookSeries?
    @State private var seriesShouldClear = false
    @State private var selectedPublisher: Publisher?
    @State private var publisherShouldClear = false
    @State private var languageCode: String?
    @State private var languageShouldClear = false
    @State private var genre = ""
    @State private var genreShouldClear = false
    @State private var publicationYearText = ""
    @State private var publicationYearShouldClear = false

    init(
        collectionID: UUID,
        people: [Person] = [],
        series: [BookSeries] = [],
        publishers: [Publisher] = [],
        onSave: @escaping (ItemBatchEdit, BookBatchEdit) -> Void
    ) {
        self.collectionID = collectionID
        self.people = people
        self.series = series
        self.publishers = publishers
        self.onSave = onSave
    }

    private struct LanguageOption: Identifiable {
        let code: String
        let name: String

        var id: String { code }
    }

    private var languageOptions: [LanguageOption] {
        Locale.LanguageCode.isoLanguageCodes
            .map(\.identifier)
            .map { code in
                LanguageOption(
                    code: code,
                    name: BookLanguageFormatter.displayName(for: code)
                )
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var availablePeople: [Person] {
        Dictionary(
            people
                .filter { $0.collectionID == collectionID }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        .values
        .sorted {
            let comparison = $0.sortName.localizedCaseInsensitiveCompare($1.sortName)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var availableSeries: [BookSeries] {
        Dictionary(
            series
                .filter { $0.collectionID == collectionID }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        .values
        .sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var availablePublishers: [Publisher] {
        Dictionary(
            publishers
                .filter { $0.collectionID == collectionID }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        .values
        .sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var body: some View {
        CatalogBatchEditView(
            isDomainEditEmpty: bookEdit.isEmpty,
            isDomainEditValid: isDomainEditValid,
            onSave: { itemEdit in
                onSave(itemEdit, bookEdit)
            }
        ) {
            Section(String(localized: "common.book")) {
                HStack(spacing: 8) {
                    Picker(String(localized: "series.title"), selection: seriesBinding) {
                        Text(String(localized: "catalog.batch_edit.keep_unchanged"))
                            .tag(nil as BookSeries?)
                        ForEach(availableSeries) { value in
                            Text(value.name)
                                .tag(Optional(value))
                        }
                    }

                    clearButton(isActive: seriesShouldClear) {
                        selectedSeries = nil
                        seriesShouldClear = true
                    }
                }

                HStack(spacing: 8) {
                    Picker(String(localized: "publisher.title"), selection: publisherBinding) {
                        Text(String(localized: "catalog.batch_edit.keep_unchanged"))
                            .tag(nil as Publisher?)
                        ForEach(availablePublishers) { value in
                            Text(value.name)
                                .tag(Optional(value))
                        }
                    }

                    clearButton(isActive: publisherShouldClear) {
                        selectedPublisher = nil
                        publisherShouldClear = true
                    }
                }

                HStack(spacing: 8) {
                    Picker(String(localized: "book.field.language"), selection: languageBinding) {
                        Text(String(localized: "catalog.batch_edit.keep_unchanged"))
                            .tag(nil as String?)
                        ForEach(languageOptions) { option in
                            Text("\(option.name) (\(option.code.uppercased()))")
                                .tag(Optional(option.code))
                        }
                    }

                    clearButton(isActive: languageShouldClear) {
                        languageCode = nil
                        languageShouldClear = true
                    }
                }

                LabeledContent(String(localized: "book.field.genre")) {
                    HStack(spacing: 8) {
                        TextField("", text: genreBinding)
                            .multilineTextAlignment(.trailing)

                        clearButton(isActive: genreShouldClear) {
                            genre = ""
                            genreShouldClear = true
                        }
                    }
                }

                LabeledContent(String(localized: "book.field.publication_year")) {
                    HStack(spacing: 8) {
                        TextField("", text: publicationYearBinding)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)

                        clearButton(isActive: publicationYearShouldClear) {
                            publicationYearText = ""
                            publicationYearShouldClear = true
                        }
                    }
                }
            }
            
            BookContributorsEditorSubview(
                rowCount: contributorEdits.count,
                onDelete: deleteContributorEdits
            ) { index in
                let edit = contributorEdits[index]
                BookContributorEditorRow(
                    role: edit.role,
                    person: edit.person
                ) {
                    editingContributorIndex = index
                    isPresentingContributorEditor = true
                }
            } addContent: {
                Button {
                    editingContributorIndex = nil
                    isPresentingContributorEditor = true
                } label: {
                    Label("book_contributor.action.add", systemImage: "plus")
                }
                .disabled(contributorEdits.count >= BookContributorRole.allCases.count)
            }

        }
        .sheet(isPresented: $isPresentingContributorEditor) {
            BookContributorEditorView(
                title: editingContributorEdit == nil
                    ? String(localized: "book_contributor.action.add")
                    : String(localized: "book_contributor.action.edit"),
                role: editingContributorEdit?.role
                    ?? availableContributorRoles.first
                    ?? .author,
                person: editingContributorEdit?.person,
                people: availablePeople,
                collectionID: collectionID,
                availableRoles: availableContributorRoles,
                onClear: { role in
                    clearContributorRole(role)
                },
                onSave: { role, person in
                    saveContributorEdit(
                        BookContributorBatchEdit(
                            role: role,
                            person: person
                        )
                    )
                }
            )
        }
    }

    private var editingContributorEdit: BookContributorBatchEdit? {
        guard let editingContributorIndex,
              contributorEdits.indices.contains(editingContributorIndex) else {
            return nil
        }
        return contributorEdits[editingContributorIndex]
    }

    private var availableContributorRoles: [BookContributorRole] {
        BookContributorRole.allCases.filter { role in
            role == editingContributorEdit?.role
                || !contributorEdits.contains(where: { $0.role == role })
        }
    }

    private var bookEdit: BookBatchEdit {
        BookBatchEdit(
            languageCode: languageChange,
            genre: stringChange(value: genre, shouldClear: genreShouldClear),
            pageCount: .unchanged,
            publicationYear: integerChange(
                value: publicationYearText,
                shouldClear: publicationYearShouldClear
            ),
            contributors: contributorEdits,
            series: referenceChange(value: selectedSeries, shouldClear: seriesShouldClear),
            publisher: referenceChange(value: selectedPublisher, shouldClear: publisherShouldClear)
        )
    }

    private var isDomainEditValid: Bool {
        isPublicationYearValid
    }

    private var seriesBinding: Binding<BookSeries?> {
        Binding(
            get: { selectedSeries },
            set: { value in
                selectedSeries = value
                seriesShouldClear = false
            }
        )
    }

    private var publisherBinding: Binding<Publisher?> {
        Binding(
            get: { selectedPublisher },
            set: { value in
                selectedPublisher = value
                publisherShouldClear = false
            }
        )
    }

    private var languageBinding: Binding<String?> {
        Binding(
            get: { languageCode },
            set: { value in
                languageCode = value
                languageShouldClear = false
            }
        )
    }

    private var genreBinding: Binding<String> {
        Binding(
            get: { genre },
            set: { value in
                genre = value
                genreShouldClear = false
            }
        )
    }

    private var publicationYearBinding: Binding<String> {
        Binding(
            get: { publicationYearText },
            set: { value in
                publicationYearText = value
                publicationYearShouldClear = false
            }
        )
    }

    private var languageChange: BatchEditValue<String> {
        if languageShouldClear {
            return .set(nil)
        }
        guard let languageCode else { return .unchanged }
        return .set(languageCode)
    }

    private var isPublicationYearValid: Bool {
        guard !publicationYearShouldClear else { return true }

        let trimmed = publicationYearText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let year = Int(trimmed) else { return false }

        let maximumYear = Calendar.current.component(.year, from: Date()) + 1
        return (1...maximumYear).contains(year)
    }

    private func saveContributorEdit(_ edit: BookContributorBatchEdit) {
        if let editingContributorIndex,
           contributorEdits.indices.contains(editingContributorIndex) {
            contributorEdits[editingContributorIndex] = edit
        } else {
            contributorEdits.append(edit)
        }
    }

    private func clearContributorRole(_ role: BookContributorRole) {
        let edit = BookContributorBatchEdit(role: role, person: nil)
        saveContributorEdit(edit)
    }

    private func deleteContributorEdits(at offsets: IndexSet) {
        contributorEdits.remove(atOffsets: offsets)
    }

    private func referenceChange<Value>(
        value: Value?,
        shouldClear: Bool
    ) -> BatchEditValue<Value> {
        if shouldClear {
            return .set(nil)
        }
        guard let value else { return .unchanged }
        return .set(value)
    }

    private func stringChange(
        value: String,
        shouldClear: Bool
    ) -> BatchEditValue<String> {
        if shouldClear {
            return .set(nil)
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unchanged }
        return .set(trimmed)
    }

    private func integerChange(
        value: String,
        shouldClear: Bool
    ) -> BatchEditValue<Int> {
        if shouldClear {
            return .set(nil)
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unchanged }
        return .set(Int(trimmed))
    }

    private func clearButton(
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .opacity(isActive ? 1 : 0.35)
        .accessibilityLabel(String(localized: "common.clear"))
    }
}

#if DEBUG
#Preview {
    BookBatchEditView(collectionID: UUID()) { _, _ in }
}
#endif

extension CatalogCardManagementModifier where Item == BookRecord {
    init(
        state: Binding<CatalogCardManagementState<BookRecord>>,
        visibleItems: [BookRecord],
        snapshot: CatalogSnapshot?,
        collection: CollectionSummary?,
        currentLocationID: @escaping (BookRecord) -> UUID?,
        moveTitle: String,
        deleteTitle: String,
        deleteMessage: String,
        selectedTitle: @escaping (Int) -> String,
        canEdit: Bool,
        tint: Color,
        onSaveHome: @escaping (Home, [Location]) -> Void,
        onMove: @escaping ([BookRecord], UUID?) -> Void,
        onDelete: @escaping ([BookRecord]) -> Void,
        onBatchEdit: @escaping ([BookRecord], ItemBatchEdit, BookBatchEdit) -> Void
    ) {
        guard let collectionID = collection?.id else {
            preconditionFailure("Book batch editing requires a collection.")
        }

        let availableSeries = snapshot?.bookSeries.filter { $0.collectionID == collectionID } ?? []
        let availablePeople = snapshot?.people.filter { $0.collectionID == collectionID } ?? []
        let availablePublishers = snapshot?.publishers.filter { $0.collectionID == collectionID } ?? []

        self.init(
            state: state,
            visibleItems: visibleItems,
            snapshot: snapshot,
            collection: collection,
            currentLocationID: currentLocationID,
            moveTitle: moveTitle,
            deleteTitle: deleteTitle,
            deleteMessage: deleteMessage,
            selectedTitle: selectedTitle,
            canEdit: canEdit,
            tint: tint,
            onSaveHome: onSaveHome,
            onMove: onMove,
            onDelete: onDelete,
            batchEditContent: {
                AnyView(
                    BookBatchEditView(
                        collectionID: collectionID,
                        people: availablePeople,
                        series: availableSeries,
                        publishers: availablePublishers
                    ) { itemEdit, bookEdit in
                        onBatchEdit(
                            state.wrappedValue.selectedItems(in: visibleItems),
                            itemEdit,
                            bookEdit
                        )
                        state.wrappedValue.completeAction()
                    }
                )
            }
        )
    }
}

extension LibraryView {
    func batchEditBooks(
        _ books: [BookRecord],
        itemEdit: ItemBatchEdit,
        bookEdit: BookBatchEdit
    ) {
        let updatedBooks = books.map { book in
            BookRecord(
                item: itemEdit.applying(to: book.item),
                details: bookEdit.applying(to: book.details)
            )
        }
        repository.saveBookRecords(updatedBooks)
    }
}
