import SwiftUI

struct HomeEditorView: View {
    @Binding var home: Home
    @Binding var locations: [Location]
    let onSave: () -> Void
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingDeleteConfirmation = false
    @State private var isPresentingAddLocationSheet = false
    @State private var editingLocationID: UUID?
    @State private var addingChildContext: AddChildContext?
    @State private var collapsedLocationIDs: Set<UUID> = []

    private var flattenedLocations: [EditableLocationNode] {
        let roots = locations
            .filter { $0.parentLocationID == nil }
            .sorted(by: locationSort)
        return roots.flatMap { flatten(location: $0, depth: 0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "home.editor.section_home")) {
                    TextField(
                        String(localized: "common.name"),
                        text: $home.name
                    )

                    Picker(String(localized: "home.icon"), selection: $home.iconName) {
                        ForEach(HomeIconOption.allCases) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option.systemImage)
                        }
                    }

                    TextField(
                        String(localized: "common.notes"),
                        text: $home.notes,
                        axis: .vertical
                    )
                    .lineLimit(3, reservesSpace: true)
                }

                Section(String(localized: "home.editor.section_locations")) {
                    if locations.isEmpty {
                        ContentUnavailableView(
                            String(localized: "home.location.empty.title"),
                            systemImage: "square.stack.3d.up.slash",
                            description: Text(String(localized: "home.location.empty.description"))
                        )
                    } else {
                        ForEach(flattenedLocations) { node in
                            Button {
                                editingLocationID = node.location.id
                            } label: {
                                EditableLocationRow(
                                    location: node.location,
                                    depth: node.depth,
                                    hasChildren: !children(of: node.location).isEmpty,
                                    isCollapsed: collapsedLocationIDs.contains(node.location.id),
                                    showsAddChildAction: defaultChildKind(for: node.location) != nil,
                                    onToggleCollapsed: {
                                        toggleCollapsed(node.location.id)
                                    },
                                    onAddChild: {
                                        if let childKind = defaultChildKind(for: node.location) {
                                            addingChildContext = AddChildContext(
                                                parentID: node.location.id,
                                                childKind: childKind
                                            )
                                        }
                                    }
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(String(localized: "common.delete"), role: .destructive) {
                                    deleteLocation(node.location.id)
                                }
                            }
                        }
                    }

                    Button {
                        isPresentingAddLocationSheet = true
                    } label: {
                        Label(String(localized: "home.location.add"), systemImage: "plus.circle.fill")
                    }
                }

                if onDelete != nil {
                    Section {
                        Button(role: .destructive) {
                            isPresentingDeleteConfirmation = true
                        } label: {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "home.common.field.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        locations = normalizedLocations()
                        onSave()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .confirmationDialog(
                String(localized: "home.delete.title"),
                isPresented: $isPresentingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "home.delete.confirm"), role: .destructive) {
                    onDelete?()
                    dismiss()
                }

                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "home.delete.message"))
            }
            .sheet(isPresented: $isPresentingAddLocationSheet) {
                AddLocationSheet(
                    homeID: home.id,
                    existingLocations: locations,
                    initialKind: .room,
                    initialParentLocationID: nil,
                    onAdd: { newLocations in
                        locations.append(contentsOf: newLocations)
                    }
                )
            }
            .sheet(
                isPresented: Binding(
                    get: { addingChildContext != nil },
                    set: { newValue in
                        if !newValue {
                            addingChildContext = nil
                        }
                    }
                )
            ) {
                if let addingChildContext {
                    AddLocationSheet(
                        homeID: home.id,
                        existingLocations: locations,
                        initialKind: addingChildContext.childKind,
                        initialParentLocationID: addingChildContext.parentID,
                        onAdd: { newLocations in
                            locations.append(contentsOf: newLocations)
                            self.addingChildContext = nil
                        }
                    )
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { editingLocationID != nil },
                    set: { newValue in
                        if !newValue {
                            editingLocationID = nil
                        }
                    }
                )
            ) {
                if let location = editingLocationBinding {
                    EditLocationSheet(
                        location: location,
                        allLocations: locations,
                        onDelete: { deletedID in
                            deleteLocation(deletedID)
                            editingLocationID = nil
                        }
                    )
                }
            }
        }
    }

    private var editingLocationBinding: Binding<Location>? {
        guard let editingLocationID,
              let index = locations.firstIndex(where: { $0.id == editingLocationID }) else {
            return nil
        }

        return $locations[index]
    }

    private func deleteLocation(_ locationID: UUID) {
        let removedIDs = Set([locationID])
        collapsedLocationIDs.subtract(removedIDs)
        locations.removeAll { removedIDs.contains($0.id) }
        locations = locations.map { location in
            guard removedIDs.contains(location.parentLocationID ?? UUID()) else {
                return location
            }

            var copy = location
            copy.parentLocationID = nil
            return copy
        }
    }

    private func parentCandidates(for location: Location) -> [Location] {
        locations
            .filter { candidate in
                isValidParent(candidate, for: location)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func normalizedLocations() -> [Location] {
        locations.map { location in
            guard hasValidParent(location) else {
                var copy = location
                copy.parentLocationID = nil
                return copy
            }

            return location
        }
    }

    private func hasValidParent(_ location: Location) -> Bool {
        guard let parentID = location.parentLocationID else { return true }
        guard let parent = locations.first(where: { $0.id == parentID }) else { return false }
        return isValidParent(parent, for: location)
    }

    private func isValidParent(_ candidate: Location, for location: Location) -> Bool {
        guard candidate.id != location.id else { return false }
        guard candidate.homeID == location.homeID else { return false }
        guard location.kind.canBeChild(of: candidate.kind) else { return false }
        guard !isDescendant(candidateID: candidate.id, of: location.id) else { return false }
        return true
    }

    private func isDescendant(candidateID: UUID, of locationID: UUID) -> Bool {
        var currentParentID = locations.first(where: { $0.id == candidateID })?.parentLocationID

        while let parentID = currentParentID {
            if parentID == locationID {
                return true
            }

            currentParentID = locations.first(where: { $0.id == parentID })?.parentLocationID
        }

        return false
    }

    private func flatten(location: Location, depth: Int) -> [EditableLocationNode] {
        //[EditableLocationNode(location: location, depth: depth)] +
        //children(of: location).flatMap { flatten(location: $0, depth: depth + 1) }
        let node = EditableLocationNode(location: location, depth: depth)

        guard !collapsedLocationIDs.contains(location.id) else {
            return [node]
        }

        return [node] + children(of: location).flatMap { flatten(location: $0, depth: depth + 1) }
    }

    private func toggleCollapsed(_ locationID: UUID) {
        if collapsedLocationIDs.contains(locationID) {
            collapsedLocationIDs.remove(locationID)
        } else {
            collapsedLocationIDs.insert(locationID)
        }
    }

    private func children(of location: Location) -> [Location] {
        locations
            .filter { $0.parentLocationID == location.id }
            .sorted(by: locationSort)
    }

    private var locationSort: (Location, Location) -> Bool {
        { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.sortRank < rhs.kind.sortRank
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func defaultChildKind(for location: Location) -> LocationKind? {
        switch location.kind {
        case .floor:
            return .room
        case .room:
            return .cabinet
        case .cabinet:
            return .shelf
        case .shelf:
            return nil
        }
    }
}

struct AddLocationSheet: View {
    let homeID: UUID
    let existingLocations: [Location]
    let initialKind: LocationKind
    let initialParentLocationID: UUID?
    let onAdd: ([Location]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: LocationKind
    @State private var name: String = ""
    @State private var parentLocationID: UUID?
    @State private var notes: String = ""
    @State private var shelfCount: Int = 0

    init(
        homeID: UUID,
        existingLocations: [Location],
        initialKind: LocationKind = .room,
        initialParentLocationID: UUID? = nil,
        onAdd: @escaping ([Location]) -> Void
    ) {
        self.homeID = homeID
        self.existingLocations = existingLocations
        self.initialKind = initialKind
        self.initialParentLocationID = initialParentLocationID
        self.onAdd = onAdd
        _kind = State(initialValue: initialKind)
        _parentLocationID = State(initialValue: initialParentLocationID)
    }

    private var draftLocation: Location {
        Location(
            id: UUID(),
            homeID: homeID,
            parentLocationID: parentLocationID,
            kind: kind,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultName(for: kind) : name,
            notes: notes
        )
    }

    private var parentCandidates: [Location] {
        existingLocations
            .filter { candidate in
                kind.canBeChild(of: candidate.kind)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var lockedParent: Location? {
        guard let initialParentLocationID else { return nil }
        return existingLocations.first(where: { $0.id == initialParentLocationID })
    }

    private var availableKinds: [LocationKind] {
        if let lockedParent {
            return LocationKind.allCases.filter { $0.canBeChild(of: lockedParent.kind) }
        }

        return LocationKind.allCases
    }

    private var canSave: Bool {
        !draftLocation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "home.location.add")) {
                    Picker(String(localized: "home.location.kind"), selection: $kind) {
                        ForEach(availableKinds) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    .onChange(of: kind) { _, newKind in
                        if !newKind.canBeChild(of: parentLocationID.flatMap { id in
                            existingLocations.first(where: { $0.id == id })?.kind
                        }) {
                            parentLocationID = nil
                        }

                        if newKind != .cabinet {
                            shelfCount = 0
                        }
                    }

                    TextField(String(localized: "home.location.name"), text: $name, prompt: Text(defaultName(for: kind)))

                    if let lockedParent {
                        LabeledContent(String(localized: "home.location.parent")) {
                            Text(lockedParent.name)
                        }
                    } else {
                        Picker(String(localized: "home.location.parent"), selection: $parentLocationID) {
                            Text(String(localized: "common.none")).tag(Optional<UUID>.none)
                            ForEach(parentCandidates) { candidate in
                                Text(candidate.name).tag(Optional(candidate.id))
                            }
                        }
                    }

                    if kind == .cabinet {
                        Stepper(value: $shelfCount, in: 0...24) {
                            Text(
                                String.localizedStringWithFormat(
                                    NSLocalizedString("home.location.shelf_count", comment: "Shelf count when creating cabinet"),
                                    shelfCount
                                )
                            )
                        }
                    }

                    TextField(String(localized: "common.notes"), text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
            }
            .navigationTitle(String(localized: "home.location.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { save() } label: { Image(systemName: "checkmark") }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if !availableKinds.contains(kind), let firstAvailableKind = availableKinds.first {
                    kind = firstAvailableKind
                }
            }
        }
    }

    private func save() {
        let baseLocation = draftLocation
        var createdLocations: [Location] = [baseLocation]

        if kind == .cabinet, shelfCount > 0 {
            createdLocations.append(contentsOf: (1...shelfCount).map { index in
                Location(
                    id: UUID(),
                    homeID: homeID,
                    parentLocationID: baseLocation.id,
                    kind: .shelf,
                    name: String.localizedStringWithFormat(
                        NSLocalizedString("home.location.shelf_default_name", comment: "Default generated shelf name"),
                        index
                    ),
                    notes: ""
                )
            })
        }

        onAdd(createdLocations)
        dismiss()
    }

    private func defaultName(for kind: LocationKind) -> String {
        switch kind {
        case .floor:
            return String(localized: "enum.location_kind.floor")
        case .room:
            return String(localized: "enum.location_kind.room")
        case .cabinet:
            return String(localized: "enum.location_kind.cabinet")
        case .shelf:
            return String(localized: "enum.location_kind.shelf")
        }
    }
}

private struct EditableLocationNode: Identifiable {
    let location: Location
    let depth: Int

    var id: UUID { location.id }
}

private struct AddChildContext: Identifiable {
    let parentID: UUID
    let childKind: LocationKind

    var id: UUID { parentID }
}

private struct EditableLocationRow: View {
    let location: Location
    let depth: Int
    let hasChildren: Bool
    let isCollapsed: Bool
    let showsAddChildAction: Bool
    let onToggleCollapsed: () -> Void
    let onAddChild: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if hasChildren {
                Button(action: onToggleCollapsed) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 20, height: 20)
            }
            Circle()
                .fill(kindColor(location.kind))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.body.weight(.medium))

                HStack(spacing: 6) {
                    Text(location.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !location.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Text(location.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if showsAddChildAction {
                Button(action: onAddChild) {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundStyle(.tint)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.leading, CGFloat(depth) * 18)
        .padding(.vertical, 4)
    }

    private func kindColor(_ kind: LocationKind) -> Color {
        switch kind {
        case .floor:
            return Color(red: 0.20, green: 0.42, blue: 0.34)
        case .room:
            return Color(red: 0.36, green: 0.52, blue: 0.24)
        case .cabinet:
            return Color(red: 0.58, green: 0.44, blue: 0.18)
        case .shelf:
            return Color(red: 0.51, green: 0.31, blue: 0.14)
        }
    }
}

private struct EditLocationSheet: View {
    @Binding var location: Location
    let allLocations: [Location]
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingDeleteConfirmation = false

    private var parentCandidates: [Location] {
        allLocations
            .filter { candidate in
                isValidParent(candidate, for: location)
            }
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "home.editor.section_locations")) {
                    LabeledContent(String(localized: "home.location.kind")) {
                        Text(location.kind.displayName)
                    }

                    TextField(String(localized: "home.location.name"), text: $location.name)

                    Picker(String(localized: "home.location.parent"), selection: $location.parentLocationID) {
                        Text(String(localized: "common.none")).tag(Optional<UUID>.none)
                        ForEach(parentCandidates) { candidate in
                            Text(candidate.name).tag(Optional(candidate.id))
                        }
                    }

                    TextField(String(localized: "common.notes"), text: $location.notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }

                Section {
                    Button(role: .destructive) {
                        isPresentingDeleteConfirmation = true
                    } label: {
                        Label(String(localized: "common.delete"), systemImage: "trash")
                    }
                }
            }
            .navigationTitle(location.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }
                }
            }
            .confirmationDialog(
                String(localized: "home.delete.title"),
                isPresented: $isPresentingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "common.delete"), role: .destructive) {
                    onDelete(location.id)
                    dismiss()
                }

                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "home.location.delete.message"))
            }
        }
    }

    private func isValidParent(_ candidate: Location, for location: Location) -> Bool {
        guard candidate.id != location.id else { return false }
        guard candidate.homeID == location.homeID else { return false }
        guard location.kind.canBeChild(of: candidate.kind) else { return false }
        guard !isDescendant(candidateID: candidate.id, of: location.id) else { return false }
        return true
    }

    private func isDescendant(candidateID: UUID, of locationID: UUID) -> Bool {
        var currentParentID = allLocations.first(where: { $0.id == candidateID })?.parentLocationID

        while let parentID = currentParentID {
            if parentID == locationID {
                return true
            }

            currentParentID = allLocations.first(where: { $0.id == parentID })?.parentLocationID
        }

        return false
    }
}

private enum HomeIconOption: String, CaseIterable, Identifiable {
    case house = "house.fill"
    case building = "building.2.fill"
    case cottage = "mountain.2.fill"
    case treehouse = "tree.fill"
    case city = "building.columns.fill"
    case warehouse = "shippingbox.fill"

    var id: String { rawValue }
    var systemImage: String { rawValue }

    var title: String {
        switch self {
        case .house:
            return String(localized: "home.icon.house")
        case .building:
            return String(localized: "home.icon.building")
        case .cottage:
            return String(localized: "home.icon.cottage")
        case .treehouse:
            return String(localized: "home.icon.treehouse")
        case .city:
            return String(localized: "home.icon.city")
        case .warehouse:
            return String(localized: "home.icon.warehouse")
        }
    }
}