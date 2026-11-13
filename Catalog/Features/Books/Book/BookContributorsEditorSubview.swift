import SwiftUI

@ViewBuilder
func BookContributorsEditorSubview<RowContent: View, AddContent: View>(
    rowCount: Int,
    onDelete: @escaping (IndexSet) -> Void,
    @ViewBuilder rowContent: @escaping (Int) -> RowContent,
    @ViewBuilder addContent: @escaping () -> AddContent
) -> some View {
    Section("book.section.contributors") {
        ForEach(0..<rowCount, id: \.self, content: rowContent)
            .onDelete(perform: onDelete)
        addContent()
    }
}

@ViewBuilder
@MainActor
func BookContributorEditorRow(
    role: BookContributorRole,
    person: Person?,
    statusSystemImage: String? = nil,
    onTap: @escaping () -> Void
) -> some View {
    Button(action: onTap) {
        HStack {
            Text(role.displayName)
                .foregroundStyle(.secondary)

            Spacer()

            if let person {
                Text(person.displayName)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(String(localized: "common.clear"))
                    .foregroundStyle(.red)
            }

            if let statusSystemImage {
                Image(systemName: statusSystemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(CatalogTypography.chipLabel)
                .foregroundStyle(.tertiary)
        }
    }
    .buttonStyle(.plain)
}

/// Shared editor for one contributor. Callers keep ownership of validation and persistence semantics.
struct BookContributorEditorView: View {
    let title: String
    let people: [Person]
    let collectionID: UUID
    let availableRoles: [BookContributorRole]
    let onCreatePerson: ((Person) -> Void)?
    let onClear: ((BookContributorRole) -> Void)?
    let validationMessage: (BookContributorRole, Person?) -> String?
    let onSave: (BookContributorRole, Person) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var role: BookContributorRole
    @State private var selectedPerson: Person?
    @State private var isPresentingPersonPicker = false

    init(
        title: String,
        role: BookContributorRole,
        person: Person?,
        people: [Person],
        collectionID: UUID,
        availableRoles: [BookContributorRole] = BookContributorRole.allCases,
        onCreatePerson: ((Person) -> Void)? = nil,
        onClear: ((BookContributorRole) -> Void)? = nil,
        validationMessage: @escaping (BookContributorRole, Person?) -> String? = { _, _ in nil },
        onSave: @escaping (BookContributorRole, Person) -> Void
    ) {
        self.title = title
        self.people = people
        self.collectionID = collectionID
        self.availableRoles = availableRoles
        self.onCreatePerson = onCreatePerson
        self.onClear = onClear
        self.validationMessage = validationMessage
        self.onSave = onSave
        _role = State(initialValue: role)
        _selectedPerson = State(initialValue: person)
    }

    private var validation: String? {
        validationMessage(role, selectedPerson)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("book_contributor.section.contribution") {
                    Picker("book_contributor.field.role", selection: $role) {
                        ForEach(availableRoles) { role in
                            Text(role.displayName).tag(role)
                        }
                    }

                    Button {
                        isPresentingPersonPicker = true
                    } label: {
                        LabeledContent("person.title") {
                            HStack(spacing: CatalogMetrics.Spacing.xs) {
                                Text(selectedPerson?.displayName ?? String(localized: "common.none"))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                                Image(systemName: "chevron.right")
                                    .font(CatalogTypography.chipLabel)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if let validation {
                        Label(validation, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(CatalogSemanticColors.destructive)
                    }
                }

                if let onClear {
                    Section {
                        Button(role: .destructive) {
                            onClear(role)
                            dismiss()
                        } label: {
                            Label("common.clear", systemImage: "xmark.circle.fill")
                        }
                    }
                }
            }
            .navigationTitle(title)
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
                        guard let selectedPerson else { return }
                        onSave(role, selectedPerson)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(selectedPerson == nil || validation != nil)
                    .accessibilityLabel(String(localized: "common.save"))
                }
            }
            .sheet(isPresented: $isPresentingPersonPicker) {
                BookPersonSelectionView(
                    selection: $selectedPerson,
                    people: people,
                    collectionID: collectionID,
                    onCreate: onCreatePerson
                )
            }
        }
    }
}

private struct BookPersonSelectionView: View {
    @Binding var selection: Person?
    let people: [Person]
    let collectionID: UUID
    let onCreate: ((Person) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredPeople: [Person] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty
            ? people
            : people.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    private var newPersonName: String? {
        guard onCreate != nil else { return nil }
        let name = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !people.contains(where: { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }) else {
            return nil
        }
        return name
    }

    var body: some View {
        NavigationStack {
            List {
                if let name = newPersonName, let onCreate {
                    Button {
                        let person = Person(
                            id: UUID(),
                            collectionID: collectionID,
                            givenName: name,
                            birthYear: nil,
                            deathYear: nil,
                            biography: nil,
                            birthPlace: nil,
                            deathPlace: nil,
                            photos: []
                        )
                        onCreate(person)
                        selection = person
                        dismiss()
                    } label: {
                        Label(
                            String.localizedStringWithFormat(String(localized: "common.action.add_value"), name),
                            systemImage: "plus.circle.fill"
                        )
                    }
                }

                selectionRow(
                    title: String(localized: "common.none"),
                    isSelected: selection == nil
                ) {
                    selection = nil
                    dismiss()
                }

                ForEach(filteredPeople) { person in
                    selectionRow(
                        title: person.displayName,
                        isSelected: selection?.id == person.id
                    ) {
                        selection = person
                        dismiss()
                    }
                }
            }
            .navigationTitle("person.title")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                prompt: Text(onCreate == nil ? String(localized: "person.title") : String(localized: "picker.search_or_add"))
            )
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

    private func selectionRow(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}
