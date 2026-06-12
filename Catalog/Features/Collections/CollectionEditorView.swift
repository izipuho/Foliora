import SwiftUI

struct CollectionEditorView: View {
    let homes: [Home]
    let onSave: (String, String, UUID, CollectionBackgroundStyle) -> Void
    let onDelete: (() -> Void)?
    let sharingDestination: AnyView?

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var selectedHomeID: UUID?
    @State private var pendingHomeID: UUID?
    @State private var backgroundStyle: CollectionBackgroundStyle = .amber
    @State private var isPresentingDeleteConfirmation = false
    @State private var isPresentingHomeChangeConfirmation = false
    private let screenTitle: String
    private let hasPlacedItems: Bool
    private let allowsDeletion: Bool

    init(
        homes: [Home],
        screenTitle: String = "",
        initialTitle: String = "",
        initialNotes: String = "",
        initialHomeID: UUID? = nil,
        initialBackgroundStyle: CollectionBackgroundStyle = .amber,
        hasPlacedItems: Bool = false,
        allowsDeletion: Bool = false,
        sharingDestination: AnyView? = nil,
        onSave: @escaping (String, String, UUID, CollectionBackgroundStyle) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.homes = homes
        self.screenTitle = screenTitle
        self.hasPlacedItems = hasPlacedItems
        self.allowsDeletion = allowsDeletion
        self.sharingDestination = sharingDestination
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: initialTitle)
        _notes = State(initialValue: initialNotes)
        _selectedHomeID = State(initialValue: initialHomeID ?? homes.first?.id)
        _backgroundStyle = State(initialValue: initialBackgroundStyle)
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && selectedHomeID != nil
    }

    private var shouldShowHomePicker: Bool {
        homes.count > 1
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNotes: String {
        notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var backgroundColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 74, maximum: 110), spacing: 12)]
    }

    private var homeSelection: Binding<UUID?> {
        Binding {
            selectedHomeID
        } set: { newHomeID in
            guard newHomeID != selectedHomeID else { return }

            if hasPlacedItems {
                pendingHomeID = newHomeID
                isPresentingHomeChangeConfirmation = true
            } else {
                selectedHomeID = newHomeID
            }
        }
    }

    private var collectionSection: some View {
        Section(String(localized: "collection.editor.section_collection")) {
            TextField(String(localized: "common.name"), text: $title)
            TextField(String(localized: "common.notes"), text: $notes, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
            if shouldShowHomePicker {
                Picker(String(localized: "home.screen.single_title"), selection: homeSelection) {
                    ForEach(homes) { home in
                        Text(home.name).tag(Optional(home.id))
                    }
                }
            }
        }
    }

    private var backgroundSection: some View {
        Section(String(localized: "collection.editor.section_background")) {
            LazyVGrid(columns: backgroundColumns, spacing: 12) {
                ForEach(CollectionBackgroundStyle.allCases) { style in
                    CollectionBackgroundStyleButton(
                        style: style,
                        isSelected: backgroundStyle == style
                    ) {
                        backgroundStyle = style
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sharingSection: some View {
        if let sharingDestination {
            Section {
                NavigationLink {
                    sharingDestination
                } label: {
                    Label(String(localized: "collection.sharing.entry_title"), systemImage: "person.2")
                }
            }
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        if allowsDeletion {
            Section {
                Button(role: .destructive) {
                    isPresentingDeleteConfirmation = true
                } label: {
                    Label(String(localized: "common.delete"), systemImage: "trash")
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                collectionSection
                backgroundSection
                sharingSection
                deleteSection
            }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard let selectedHomeID else { return }
                        onSave(trimmedTitle, trimmedNotes, selectedHomeID, backgroundStyle)
                        dismiss()
                    } label: { Image(systemName: "checkmark") }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog(
                String(localized: "collection.home_change.title"),
                isPresented: $isPresentingHomeChangeConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "collection.home_change.confirm"), role: .destructive) {
                    selectedHomeID = pendingHomeID
                    pendingHomeID = nil
                }

                Button(String(localized: "common.cancel"), role: .cancel) {
                    pendingHomeID = nil
                }
            } message: {
                Text(String(localized: "collection.home_change.message"))
            }
            .confirmationDialog(
                String(localized: "collection.delete.title"),
                isPresented: $isPresentingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "collection.delete.confirm"), role: .destructive) {
                    onDelete?()
                    dismiss()
                }

                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "collection.delete.message"))
            }
        }
    }
}

private struct CollectionBackgroundStyleButton: View {
    let style: CollectionBackgroundStyle
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: style.colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 64)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, CatalogMediaContrast.iconPaletteShadowSoft)
                                .padding(CatalogSpacing.compact)
                        }
                    }

                Text(style.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
