import SwiftUI

/// Displays the people referenced by books in a single library.
struct PeopleView: View {
    let collection: CollectionSummary
    let catalogSnapshot: CatalogSnapshot?
    let repository: any CatalogRepository
    let canEditCollection: Bool
    let onBookSelected: ((UUID) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var localPeople: [Person]
    @State private var searchText = ""
    @State private var selectedPerson: Person?

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
        _localPeople = State(
            initialValue: Self.libraryPeople(
                collectionID: collection.id,
                snapshot: catalogSnapshot
            )
        )
    }

    private var books: [BookRecord] {
        catalogSnapshot?.bookRecords.filter { $0.collectionID == collection.id } ?? []
    }

    private var allBooks: [BookRecord] {
        catalogSnapshot?.bookRecords ?? []
    }

    private var filteredPeople: [Person] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return localPeople
            .filter { person in
                query.isEmpty
                    || person.name.localizedCaseInsensitiveContains(query)
                    || (person.birthPlace?.displayName.localizedCaseInsensitiveContains(query) ?? false)
                    || (person.deathPlace?.displayName.localizedCaseInsensitiveContains(query) ?? false)
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
            if localPeople.isEmpty {
                emptyState
            } else {
                CatalogContainerList {
                    Section {
                        ForEach(filteredPeople) { person in
                            Button {
                                selectedPerson = person
                            } label: {
                                PersonCard(
                                    person: person,
                                    roleUsages: roleUsagesForPerson(person),
                                    accentColor: collection.backgroundStyle.accentColor
                                )
                            }
                            .buttonStyle(.plain)
                            .catalogContainerListRow()
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search people")
            }
        }
        .background {
            CatalogBackgrounds.collection(
                collection.backgroundStyle.accentColor,
                scheme: colorScheme
            )
            .ignoresSafeArea()
        }
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedPerson) { person in
            PersonDetailView(
                person: person,
                books: booksForPerson(person),
                allBookCount: allBooks.filter { book in
                    book.details.contributors.contains { $0.person.id == person.id }
                }.count,
                places: catalogSnapshot?.places ?? [],
                repository: repository,
                canEditCollection: canEditCollection,
                accentColor: collection.backgroundStyle.accentColor,
                onPersonSaved: upsertLocalPerson,
                onPersonDeleted: removeLocalPerson,
                onBookSelected: onBookSelected
            )
        }
    }

    private var emptyState: some View {
        CatalogEmptyStateView(
            systemImage: "person.2",
            title: "No People",
            message: "No people are referenced by books in this library yet.",
            primaryTint: collection.backgroundStyle.accentColor
        )
    }

    private func booksForPerson(_ person: Person) -> [BookRecord] {
        books.filter { book in
            book.details.contributors.contains { $0.person.id == person.id }
        }
    }

    private func roleUsagesForPerson(_ person: Person) -> [PersonRoleUsage] {
        let matchingBooks = booksForPerson(person)

        return BookContributorRole.allCases.compactMap { role in
            let bookCount = matchingBooks.filter { book in
                book.details.contributors.contains { contributor in
                    contributor.person.id == person.id && contributor.role == role
                }
            }.count

            guard bookCount > 0 else { return nil }
            return PersonRoleUsage(role: role, bookCount: bookCount)
        }
    }

    private func upsertLocalPerson(_ person: Person) {
        if let index = localPeople.firstIndex(where: { $0.id == person.id }) {
            localPeople[index] = person
        }
    }

    private func removeLocalPerson(_ personID: UUID) {
        localPeople.removeAll { $0.id == personID }
        if selectedPerson?.id == personID {
            selectedPerson = nil
        }
    }

    private static func libraryPeople(
        collectionID: UUID,
        snapshot: CatalogSnapshot?
    ) -> [Person] {
        guard let snapshot else { return [] }

        let referencedPeople = snapshot.bookRecords
            .filter { $0.collectionID == collectionID }
            .flatMap { $0.details.contributors.map(\.person) }

        let uniqueByID = Dictionary(
            referencedPeople.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return Array(uniqueByID.values)
    }
}

private struct PersonRoleUsage {
    let role: BookContributorRole
    let bookCount: Int
}

private struct PersonCard: View {
    let person: Person
    let roleUsages: [PersonRoleUsage]
    let accentColor: Color

    var body: some View {
        HStack(alignment: .center, spacing: CatalogMetrics.Spacing.md) {
            mark

            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
                Text(person.name)
                    .font(CatalogTypography.cardTitle)

                if let lifeSpanText {
                    Text(lifeSpanText)
                        .font(CatalogTypography.cardSubtitle)
                        .foregroundStyle(.secondary)
                }

                if !roleUsages.isEmpty {
                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                        ForEach(roleUsages, id: \.role) { usage in
                            Text("\(usage.role.displayName) · \(usage.bookCount) \(usage.bookCount == 1 ? "book" : "books")")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, CatalogMetrics.Spacing.sm)
                }
            }

            Spacer(minLength: CatalogMetrics.Spacing.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .catalogSurfaceCard()
    }

    @ViewBuilder
    private var mark: some View {
        if let photo = person.photos
            .filter({ $0.kind == .photo })
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .first {
            MediaPreviewImage(
                identifier: photo.localIdentifier,
                originalData: photo.originalData,
                size: CGSize(width: 52, height: 52)
            )
            .frame(width: 52, height: 52)
            .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.12))
                    .frame(width: 52, height: 52)

                Image(systemName: "person.fill")
                    .font(CatalogTypography.cardTitle)
                    .foregroundStyle(accentColor)
            }
        }
    }

    private var lifeSpanText: String? {
        switch (person.birthYear, person.deathYear) {
        case let (birth?, death?):
            return "\(birth)–\(death)"
        case let (birth?, nil):
            return String(localized: "Born \(birth)")
        case let (nil, death?):
            return String(localized: "Died \(death)")
        case (nil, nil):
            return nil
        }
    }
}

/// Displays the editor used to update a person.
struct PersonEditorView: View {
    private let existingPerson: Person
    private let places: [Place]
    private let bookCount: Int
    private let onDelete: (() -> Void)?
    private let onSave: (Person) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var name: String
    @State private var birthYear: String
    @State private var deathYear: String
    @State private var biography: String
    @State private var birthPlace: Place?
    @State private var deathPlace: Place?
    @State private var photos: [MediaAsset]
    @State private var isConfirmingDelete = false

    init(
        person: Person,
        places: [Place],
        bookCount: Int,
        onDelete: (() -> Void)? = nil,
        onSave: @escaping (Person) -> Void
    ) {
        self.existingPerson = person
        self.places = places
        self.bookCount = bookCount
        self.onDelete = onDelete
        self.onSave = onSave
        _name = State(initialValue: person.name)
        _birthYear = State(initialValue: person.birthYear.map(String.init) ?? "")
        _deathYear = State(initialValue: person.deathYear.map(String.init) ?? "")
        _biography = State(initialValue: person.biography ?? "")
        _birthPlace = State(initialValue: person.birthPlace)
        _deathPlace = State(initialValue: person.deathPlace)
        _photos = State(initialValue: person.photos)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validYear(birthYear)
            && validYear(deathYear)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photos") {
                    MediaSection(
                        itemID: existingPerson.id,
                        mediaAssets: $photos
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

                Section("Person") {
                    TextField("Name", text: $name)
                        .focused($isNameFocused)

                    LabeledContent("Birth year") {
                        yearField($birthYear)
                    }

                    LabeledContent("Death year") {
                        yearField($deathYear)
                    }

                    TextField("Biography", text: $biography, axis: .vertical)
                        .lineLimit(4...10)
                }

                Section("Places") {
                    PlacePickerField(
                        title: String(localized: "Birth place"),
                        selectedLabel: birthPlace?.displayName ?? String(localized: "common.none"),
                        places: places,
                        selectedPlace: $birthPlace
                    )

                    PlacePickerField(
                        title: String(localized: "Death place"),
                        selectedLabel: deathPlace?.displayName ?? String(localized: "common.none"),
                        places: places,
                        selectedPlace: $deathPlace
                    )
                }

                if onDelete != nil {
                    Section {
                        Button("Delete Person", role: .destructive) {
                            isConfirmingDelete = true
                        }
                    }
                }
            }
            .navigationTitle("Edit Person")
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
                        savePerson()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(String(localized: "common.save"))
                }
            }
            .confirmationDialog(
                "Delete Person?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Person", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                if bookCount == 0 {
                    Text("This person will be deleted from the catalog.")
                } else {
                    Text("This person will be removed from \(bookCount) \(bookCount == 1 ? "book" : "books") across the catalog. The books will be kept.")
                }
            }
            .onAppear {
                isNameFocused = false
            }
        }
    }

    @ViewBuilder
    private func yearField(_ text: Binding<String>) -> some View {
#if os(iOS)
        TextField("—", text: text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
#else
        TextField("—", text: text)
            .multilineTextAlignment(.trailing)
#endif
    }

    private func validYear(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let year = Int(trimmed) else { return false }
        return (1...9999).contains(year)
    }

    private func optionalYear(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    private func savePerson() {
        guard canSave else { return }

        let person = Person(
            id: existingPerson.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            birthYear: optionalYear(birthYear),
            deathYear: optionalYear(deathYear),
            biography: biography.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            birthPlace: birthPlace,
            deathPlace: deathPlace,
            photos: photos.enumerated().map { index, asset in
                asset.with(sortOrder: index)
            }
        )

        onSave(person)
        dismiss()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
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
            PeopleView(
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
