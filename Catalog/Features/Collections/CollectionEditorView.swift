import SwiftUI

struct CollectionEditorView: View {
    let homes: [Home]
    let allowsHomeSelection: Bool
    let onSave: (String, String, UUID, CollectionBackgroundStyle) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var selectedHomeID: UUID?
    @State private var backgroundStyle: CollectionBackgroundStyle = .amber
    @State private var isPresentingDeleteConfirmation = false
    private let screenTitle: String
    private let allowsDeletion: Bool

    init(
        homes: [Home],
        screenTitle: String = "",
        initialTitle: String = "",
        initialNotes: String = "",
        initialHomeID: UUID? = nil,
        initialBackgroundStyle: CollectionBackgroundStyle = .amber,
        allowsHomeSelection: Bool = true,
        allowsDeletion: Bool = false,
        onSave: @escaping (String, String, UUID, CollectionBackgroundStyle) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.homes = homes
        self.allowsHomeSelection = allowsHomeSelection
        self.screenTitle = screenTitle
        self.allowsDeletion = allowsDeletion
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: initialTitle)
        _notes = State(initialValue: initialNotes)
        _selectedHomeID = State(initialValue: initialHomeID ?? homes.first?.id)
        _backgroundStyle = State(initialValue: initialBackgroundStyle)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedHomeID != nil
    }

    private var backgroundColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 74, maximum: 110), spacing: 12)]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "collection.editor.section_type")) {
                    HStack {
                        Label(String(localized: "collection.editor.type_name_localized"), systemImage: "bell.fill")
                        Spacer()
                        Text(String(localized: "collection.editor.type_name_english"))
                            .foregroundStyle(.secondary)
                    }
                }

                Section(String(localized: "collection.editor.section_collection")) {
                    TextField(String(localized: "common.name"), text: $title)
                    TextField(String(localized: "common.notes"), text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section(String(localized: "collection.editor.section_home")) {
                    if homes.isEmpty {
                        Text(String(localized: "collection.editor.no_home"))
                            .foregroundStyle(.secondary)
                    } else if allowsHomeSelection {
                        Picker(String(localized: "home.screen.title"), selection: $selectedHomeID) {
                            ForEach(homes) { home in
                                Text(home.name).tag(Optional(home.id))
                            }
                        }
                    } else {
                        HStack {
                            Text(String(localized: "home.screen.title"))
                            Spacer()
                            Text(homes.first(where: { $0.id == selectedHomeID })?.name ?? String(localized: "common.unknown"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(String(localized: "collection.editor.section_background")) {
                    LazyVGrid(columns: backgroundColumns, spacing: 12) {
                        ForEach(CollectionBackgroundStyle.allCases) { style in
                            CollectionBackgroundButton(
                                style: style,
                                isSelected: backgroundStyle == style
                            ) {
                                backgroundStyle = style
                            }
                        }
                    }
                }

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
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard let selectedHomeID else { return }
                        onSave(title, notes, selectedHomeID, backgroundStyle)
                        dismiss()
                    } label: { Image(systemName: "checkmark") }
                    .disabled(!canSave)
                }
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

private struct CollectionBackgroundButton: View {
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
