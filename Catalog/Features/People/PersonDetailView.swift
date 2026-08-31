import SwiftUI

private enum PersonBookOrderMode: String, CaseIterable, Hashable {
    case title
    case publicationYearNewest
    case newestFirst

    var title: String {
        switch self {
        case .title:
            return String(localized: "common.field_title")
        case .publicationYearNewest:
            return String(localized: "book.field.publication_year")
        case .newestFirst:
            return String(localized: "sort.newest_first")
        }
    }
}

/// Displays a person and the books from the current library that reference them.
struct PersonDetailView: View {
    @State private var person: Person
    let books: [BookRecord]
    let allBookCount: Int
    let places: [Place]
    let repository: any CatalogRepository
    let canEditCollection: Bool
    let accentColor: Color
    let onPersonSaved: (Person) -> Void
    let onPersonDeleted: (UUID) -> Void
    let onBookSelected: ((UUID) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bookPerson.orderMode") private var selectedOrderRawValue = PersonBookOrderMode.title.rawValue
    @AppStorage("bellCatalog.layoutMode") private var layoutModeRawValue = CatalogCardLayoutMode.mini.rawValue
    @State private var isPresentingEditor = false

    init(
        person: Person,
        books: [BookRecord],
        allBookCount: Int,
        places: [Place],
        repository: any CatalogRepository,
        canEditCollection: Bool,
        accentColor: Color,
        onPersonSaved: @escaping (Person) -> Void,
        onPersonDeleted: @escaping (UUID) -> Void,
        onBookSelected: ((UUID) -> Void)? = nil
    ) {
        _person = State(initialValue: person)
        self.books = books
        self.allBookCount = allBookCount
        self.places = places
        self.repository = repository
        self.canEditCollection = canEditCollection
        self.accentColor = accentColor
        self.onPersonSaved = onPersonSaved
        self.onPersonDeleted = onPersonDeleted
        self.onBookSelected = onBookSelected
    }

    private var selectedOrder: PersonBookOrderMode {
        get { PersonBookOrderMode(rawValue: selectedOrderRawValue) ?? .title }
        nonmutating set { selectedOrderRawValue = newValue.rawValue }
    }

    private var selectedOrderBinding: Binding<PersonBookOrderMode> {
        Binding(
            get: { selectedOrder },
            set: { selectedOrder = $0 }
        )
    }

    private var layoutMode: CatalogCardLayoutMode {
        get { CatalogCardLayoutMode(rawValue: layoutModeRawValue) ?? .mini }
        nonmutating set { layoutModeRawValue = newValue.rawValue }
    }

    private var layoutModeBinding: Binding<CatalogCardLayoutMode> {
        Binding(
            get: { layoutMode },
            set: { layoutMode = $0 }
        )
    }

    private var sortedBooks: [BookRecord] {
        switch selectedOrder {
        case .title:
            return books.sorted(by: titleLessThan)
        case .publicationYearNewest:
            return books.sorted(by: publicationYearLessThan)
        case .newestFirst:
            return books.sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt > $1.createdAt
                }
                return titleLessThan($0, $1)
            }
        }
    }

    var body: some View {
        CatalogCardGrid(
            layoutMode: layoutMode,
            usesGridLayout: false
        ) { cardSize, gridMetrics, cardMetrics in
            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.lg) {
                summaryCard

                if sortedBooks.isEmpty {
                    CatalogEmptyStateView(
                        systemImage: "book.closed",
                        title: "library.empty.books.title",
                        message: "person.detail.empty_books.message",
                        primaryTint: accentColor
                    )
                    .frame(minHeight: 260)
                } else {
                    VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
                        Text("common.books")
                            .font(CatalogTypography.sectionTitle)

                        BookGridView(
                            books: sortedBooks,
                            layoutMode: layoutMode,
                            layoutMetrics: (cardSize, gridMetrics, cardMetrics),
                            accessories: roleAccessories,
                            onBookSelected: onBookSelected
                        )
                    }
                }
            }
            .padding(.horizontal, CatalogMetrics.Insets.screen)
            .padding(.vertical, CatalogMetrics.Spacing.lg)
        }
        .background {
            CatalogBackgrounds.collection(accentColor, scheme: colorScheme)
                .ignoresSafeArea()
        }
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            CatalogSortLayoutToolbar(
                selectedSort: selectedOrderBinding,
                selectedLayoutMode: layoutModeBinding,
                sortOptions: PersonBookOrderMode.allCases,
                sortSectionTitle: String(localized: "common.sort"),
                sortTitle: { $0.title }
            )

            if canEditCollection {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingEditor = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("person.action.edit")
                }
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            PersonEditorView(
                person: person,
                places: places,
                bookCount: allBookCount,
                onDelete: {
                    (repository as! any BookCatalogRepository).deletePerson(personID: person.id)
                    onPersonDeleted(person.id)
                    isPresentingEditor = false
                    dismiss()
                }
            ) { updatedPerson in
                (repository as! any BookCatalogRepository).savePerson(updatedPerson)
                person = updatedPerson
                onPersonSaved(updatedPerson)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.lg) {
            HStack(alignment: .center, spacing: CatalogMetrics.Spacing.md) {
                personMark

                VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                    Text(person.name)
                        .font(CatalogTypography.cardTitle)

                    if let lifeSpanText {
                        Text(lifeSpanText)
                            .font(CatalogTypography.cardSubtitle)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let biography = person.biography?.trimmingCharacters(in: .whitespacesAndNewlines),
               !biography.isEmpty {
                Divider()

                Text(biography)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            if person.birthPlace != nil || person.deathPlace != nil {
                Divider()

                VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
                    if let birthPlace = person.birthPlace {
                        metadataField(
                            title: String(localized: "person.field.birth_place"),
                            value: birthPlace.displayName,
                            systemImage: "mappin.and.ellipse"
                        )
                    }

                    if let deathPlace = person.deathPlace {
                        metadataField(
                            title: String(localized: "person.field.death_place"),
                            value: deathPlace.displayName,
                            systemImage: "mappin.and.ellipse"
                        )
                    }
                }
            }

            Divider()

            HStack(alignment: .top, spacing: CatalogMetrics.Spacing.lg) {
                metadataField(
                    title: String(localized: "common.books"),
                    value: String(books.count),
                    systemImage: "book.closed"
                )

                metadataField(
                    title: String(localized: "person.section.roles"),
                    value: rolesText,
                    systemImage: "person.text.rectangle"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CatalogMetrics.Spacing.lg)
        .background {
            CatalogShapes.section
                .fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private var personMark: some View {
        if let photo = person.photos
            .filter({ $0.kind == .photo })
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .first {
            MediaPreviewImage(
                identifier: photo.localIdentifier,
                originalData: photo.originalData,
                size: CGSize(width: 72, height: 72)
            )
            .frame(width: 72, height: 72)
            .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.14))
                    .frame(width: 72, height: 72)

                Image(systemName: "person.fill")
                    .font(.title.weight(.semibold))
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

    private var rolesText: String {
        let usages = BookContributorRole.allCases.compactMap { role -> String? in
            let bookCount = books.filter { book in
                book.details.contributors.contains { contributor in
                    contributor.person.id == person.id && contributor.role == role
                }
            }.count

            guard bookCount > 0 else { return nil }
            return "\(role.displayName) · \(bookCount)"
        }

        return usages.isEmpty ? "—" : usages.joined(separator: "\n")
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
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func roleAccessories(for book: BookRecord) -> [CatalogCardAccessory] {
        book.details.contributors
            .filter { $0.person.id == person.id }
            .map(\.role)
            .reduce(into: [BookContributorRole]()) { roles, role in
                if !roles.contains(role) {
                    roles.append(role)
                }
            }
            .map { role in
                .label(
                    text: role.displayName,
                    systemImage: "person.fill"
                )
            }
    }

    private func titleLessThan(_ lhs: BookRecord, _ rhs: BookRecord) -> Bool {
        lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func publicationYearLessThan(_ lhs: BookRecord, _ rhs: BookRecord) -> Bool {
        switch (lhs.details.publicationYear, rhs.details.publicationYear) {
        case let (.some(lhsYear), .some(rhsYear)) where lhsYear != rhsYear:
            return lhsYear > rhsYear
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return titleLessThan(lhs, rhs)
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

    if let collection = snapshot.collections
        .compactMap({ snapshot.collectionSummary(id: $0.id) })
        .first(where: { $0.kind == .books }),
       let person = snapshot.bookRecords
        .filter({ $0.collectionID == collection.id })
        .flatMap({ $0.details.contributors.map(\.person) })
        .first {
        NavigationStack {
            PersonDetailView(
                person: person,
                books: snapshot.bookRecords.filter { book in
                    book.collectionID == collection.id
                        && book.details.contributors.contains { $0.person.id == person.id }
                },
                allBookCount: snapshot.bookRecords.filter { book in
                    book.details.contributors.contains { $0.person.id == person.id }
                }.count,
                places: snapshot.places,
                repository: repository,
                canEditCollection: true,
                accentColor: collection.backgroundStyle.accentColor,
                onPersonSaved: { _ in },
                onPersonDeleted: { _ in }
            )
        }
        .environment(\.managedObjectContext, container.viewContext)
    }
}
#endif
