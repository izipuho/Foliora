import SwiftUI

private func BL(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum BellCatalogMode {
    case summary
    case items
    case search
}

struct BellCatalogView: View {
    let repository: any CatalogRepository
    let collaborators: [Collaborator]
    let collection: CollectionSummary
    let mode: BellCatalogMode

    @State private var bellRecords: [BellRecord]
    @State private var searchText = ""
    @State private var selectedCondition: ItemCondition?

    init(
        collection: CollectionSummary,
        repository: any CatalogRepository,
        collaborators: [Collaborator],
        mode: BellCatalogMode
    ) {
        self.repository = repository
        self.collaborators = collaborators
        self.collection = collection
        self.mode = mode
        _bellRecords = State(initialValue: repository.fetchBellRecords(for: collection.id))
    }

    private var bells: [BellRecord] {
        bellRecords
    }

    private var filteredBells: [BellRecord] {
        bells.filter { bell in
            let matchesSearch =
                searchText.isEmpty ||
                bell.title.localizedCaseInsensitiveContains(searchText) ||
                bell.countryName.localizedCaseInsensitiveContains(searchText) ||
                bell.cityName.localizedCaseInsensitiveContains(searchText) ||
                bell.tags.joined(separator: " ").localizedCaseInsensitiveContains(searchText)

            let matchesCondition = selectedCondition == nil || bell.condition == selectedCondition
            return matchesSearch && matchesCondition
        }
    }

    private var countryCount: Int {
        Set(bells.map(\.countryName).filter { !$0.isEmpty }).count
    }

    private var materialCount: Int {
        Set(bells.map(\.materialDisplayName)).count
    }

    private var themeColors: [Color] {
        collection.backgroundStyle.screenColors
    }

    var body: some View {
        List {
            switch mode {
            case .summary:
                if !collection.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    summaryDescription
                        .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 0, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                summaryInsights
                    .listRowInsets(
                        EdgeInsets(
                            top: collection.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 20 : 12,
                            leading: 20,
                            bottom: 0,
                            trailing: 20
                        )
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                summaryRecentBells
                    .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 120, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

            case .items:
                if bells.isEmpty {
                    emptyBellsState(
                        title: LocalizedStringKey(BL("bell_catalog.empty.title")),
                        description: LocalizedStringKey(BL("bell_catalog.empty.description"))
                    )
                } else {
                    bellListRows(bells)
                }

            case .search:
                searchSection
                    .listRowInsets(EdgeInsets(top: 20, leading: 20, bottom: 0, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if filteredBells.isEmpty {
                    emptyBellsState(
                        title: LocalizedStringKey(BL("bell_catalog.search.empty.title")),
                        description: LocalizedStringKey(BL("bell_catalog.search.empty.description"))
                    )
                } else {
                    bellListRows(filteredBells)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                colors: themeColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    @ViewBuilder
    private func bellListRows(_ bells: [BellRecord]) -> some View {
        ForEach(bells) { bell in
            if let bellBinding = binding(for: bell.id) {
                NavigationLink {
                    BellDetailView(
                        bell: bellBinding,
                        repository: repository
                    )
                } label: {
                    BellCardView(bell: bell)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 6, trailing: 20))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", role: .destructive) {
                        deleteBell(bell.id)
                    }
                }
            }
        }

        Color.clear
            .frame(height: 100)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func emptyBellsState(title: LocalizedStringKey, description: LocalizedStringKey) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "bell.slash",
            description: Text(description)
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 120, trailing: 20))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var summaryInsights: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatChip(title: BL("bell_catalog.summary.items"), value: "\(bells.count)")
                StatChip(title: BL("bell_catalog.summary.countries"), value: "\(countryCount)")
                StatChip(title: BL("bell_catalog.summary.materials"), value: "\(materialCount)")
                StatChip(title: BL("bell_catalog.summary.with_location"), value: "\(bells.filter { $0.item.locationID != nil }.count)")
                StatChip(title: BL("bell_catalog.summary.with_photos"), value: "\(bells.filter { $0.photoCount > 0 }.count)")
                StatChip(title: BL("bell_catalog.summary.without_media"), value: "\(bells.filter { $0.mediaAssets.isEmpty }.count)")
            }
        }
    }

    private var summaryDescription: some View {
        Text(collection.subtitle)
            .font(.body)
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var summaryRecentBells: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(BL("bell_catalog.summary.recent"))
                .font(.headline)

            if bells.isEmpty {
                Text(BL("bell_catalog.summary.none"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(bells.prefix(5))) { bell in
                    HStack(spacing: 12) {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(collection.backgroundStyle.accentColor)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(bell.title)
                                .font(.subheadline.weight(.semibold))
                            Text(bell.placeDisplayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(BL("bell_catalog.search.placeholder"), text: $searchText)
                .textInputAutocapitalization(.sentences)
                .padding(14)
                .background(Color.white.opacity(0.84), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    FilterChip(title: BL("bell_catalog.filter.all"), isSelected: selectedCondition == nil, tint: collection.backgroundStyle.accentColor) {
                        selectedCondition = nil
                    }

                    ForEach(ItemCondition.allCases) { condition in
                        FilterChip(title: condition.rawValue, isSelected: selectedCondition == condition, tint: collection.backgroundStyle.accentColor) {
                            selectedCondition = condition
                        }
                    }
                }
            }
        }
    }

    private func binding(for bellID: UUID) -> Binding<BellRecord>? {
        guard let index = bellRecords.firstIndex(where: { $0.id == bellID }) else { return nil }
        return $bellRecords[index]
    }

    private func deleteBell(_ bellID: UUID) {
        repository.deleteBellRecord(bellID: bellID)
        bellRecords.removeAll { $0.id == bellID }
    }
}

struct BellEditorView: View {
    let collection: CollectionSummary
    let repository: any CatalogRepository
    let onSave: (BellRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var condition: ItemCondition = .good
    @State private var acquisitionMethod: AcquisitionMethod = .bought
    @State private var material: BellMaterial = .brass
    @State private var customMaterialName = ""
    @State private var selectedOriginPlaceID: UUID?
    @State private var selectedLocationID: UUID?
    @State private var tagInput = ""
    @State private var tags: [String] = []
    @State private var mediaAssets: [MediaAsset] = []
    @State private var selectedYearOption = "None"
    private let existingBellID: UUID?
    private let editorItemID: UUID

    private let yearOptions = ["None"] + Array(1900...Calendar.current.component(.year, from: .now)).reversed().map(String.init)

    private var availableLocations: [Location] {
        repository.fetchLocations(in: collection.homeID)
    }

    private var availablePlaces: [Place] {
        let places = repository
            .fetchBellRecords(for: collection.id)
            .compactMap(\.originPlace)

        return Array(Set(places)).sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private var locationPathByID: [UUID: String] {
        Dictionary(
            uniqueKeysWithValues: availableLocations.map { location in
                (location.id, locationPath(for: location))
            }
        )
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        collection: CollectionSummary,
        repository: any CatalogRepository,
        bell: BellRecord? = nil,
        onSave: @escaping (BellRecord) -> Void
    ) {
        self.collection = collection
        self.repository = repository
        self.onSave = onSave
        self.existingBellID = bell?.id
        self.editorItemID = bell?.id ?? UUID()
        _title = State(initialValue: bell?.title ?? "")
        _notes = State(initialValue: bell?.notes ?? "")
        _condition = State(initialValue: bell?.condition ?? .good)
        _acquisitionMethod = State(initialValue: bell?.acquisitionMethod ?? .bought)
        _material = State(initialValue: bell?.details.material ?? .brass)
        _customMaterialName = State(initialValue: bell?.details.customMaterialName ?? "")
        _selectedOriginPlaceID = State(initialValue: bell?.details.originPlaceID)
        _selectedLocationID = State(initialValue: bell?.item.locationID)
        _tags = State(initialValue: bell?.tags ?? [])
        _mediaAssets = State(initialValue: bell?.mediaAssets ?? [])
        _selectedYearOption = State(initialValue: bell?.year.map(String.init) ?? "None")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Main Info") {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)

                    YearPickerField(
                        title: "Year",
                        selection: $selectedYearOption,
                        options: yearOptions
                    )
                }

                Section("Attributes") {
                    PlacePickerField(
                        title: "Origin",
                        selectedLabel: selectedOriginLabel,
                        places: availablePlaces,
                        selectedPlaceID: $selectedOriginPlaceID
                    )

                    Picker("Condition", selection: $condition) {
                        ForEach(ItemCondition.allCases) { condition in
                            Text(condition.rawValue).tag(condition)
                        }
                    }

                    Picker("Acquisition", selection: $acquisitionMethod) {
                        ForEach(AcquisitionMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }

                    Picker("Material", selection: $material) {
                        ForEach(BellMaterial.allCases) { material in
                            Text(material.displayName).tag(material)
                        }
                    }

                    if material == .other {
                        TextField("Custom material", text: $customMaterialName)
                    }
                }

                Section("Storage") {
                    LocationPickerField(
                        title: "Location",
                        selectedLabel: selectedLocationLabel,
                        locations: availableLocations,
                        selectedLocationID: $selectedLocationID
                    )
                }

                Section("Tags") {
                    TagEditorSection(
                        tagInput: $tagInput,
                        tags: $tags
                    )
                }

                Section("Media") {
                    MediaSection(
                        itemID: editorItemID,
                        mediaAssets: $mediaAssets
                    )
                }
            }
            .navigationTitle("Add Bell")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveBell()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func saveBell() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCustomMaterial = customMaterialName.trimmingCharacters(in: .whitespacesAndNewlines)

        let itemID = editorItemID
        let location = availableLocations.first(where: { $0.id == selectedLocationID })
        let originPlace = availablePlaces.first(where: { $0.id == selectedOriginPlaceID })
        let normalizedMediaAssets = mediaAssets.enumerated().map { index, asset in
            MediaAsset(
                id: asset.id,
                itemID: itemID,
                kind: asset.kind,
                localIdentifier: asset.localIdentifier,
                displayName: asset.displayName,
                sortOrder: index
            )
        }

        let newBell = BellRecord(
            item: Item(
                id: itemID,
                collectionID: collection.id,
                locationID: selectedLocationID,
                title: trimmedTitle,
                notes: trimmedNotes,
                year: selectedYearOption == "None" ? nil : Int(selectedYearOption),
                condition: condition,
                acquisitionMethod: acquisitionMethod
            ),
            details: BellDetails(
                itemID: itemID,
                originPlaceID: selectedOriginPlaceID,
                material: material,
                customMaterialName: material == .other ? trimmedCustomMaterial : nil
            ),
            originPlace: originPlace,
            storageLocation: location,
            storagePath: location.map(locationPath(for:)) ?? "Unassigned",
            mediaAssets: normalizedMediaAssets,
            createdBy: "You",
            tags: tags
        )

        onSave(newBell)
        dismiss()
    }

    private var selectedOriginLabel: String {
        guard let selectedOriginPlaceID,
              let place = availablePlaces.first(where: { $0.id == selectedOriginPlaceID })
        else {
            return "Unassigned"
        }

        return place.displayName
    }

    private var selectedLocationLabel: String {
        guard let selectedLocationID, let path = locationPathByID[selectedLocationID] else {
            return "Unassigned"
        }

        return path
    }

    private func locationPath(for location: Location) -> String {
        let locationsByID = Dictionary(uniqueKeysWithValues: availableLocations.map { ($0.id, $0) })
        var parts = [location.name]
        var currentParentID = location.parentLocationID

        while let parentID = currentParentID, let parent = locationsByID[parentID] {
            parts.insert(parent.name, at: 0)
            currentParentID = parent.parentLocationID
        }

        return parts.joined(separator: " / ")
    }
}

private struct BellCardView: View {
    let bell: BellRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bell.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(bell.placeDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "bell.badge.fill")
                    .font(.title3)
                    .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.16))
            }

            HStack {
                Label(bell.materialDisplayName, systemImage: "shippingbox.fill")
                Spacer()
                Label(bell.condition.rawValue, systemImage: "checkmark.seal")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                MetaChip(label: bell.storageDisplayPath, systemImage: "shippingbox.circle")
                MetaChip(label: "\(bell.photoCount) photo", systemImage: "photo")
                if bell.model3DCount > 0 {
                    MetaChip(label: "\(bell.model3DCount) 3D", systemImage: "cube.transparent")
                }
                if bell.documentCount > 0 {
                    MetaChip(label: "\(bell.documentCount) doc", systemImage: "doc.text")
                }
            }

            Text("Добавил: \(bell.createdBy)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !bell.tags.isEmpty {
                Text(bell.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.43, green: 0.29, blue: 0.10))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
    }
}

private struct MetaChip: View {
    let label: String
    let systemImage: String

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color.black.opacity(0.04), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    var tint: Color = Color(red: 0.53, green: 0.31, blue: 0.14)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    isSelected
                        ? tint
                        : Color.white.opacity(0.72),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
    }
}

private struct StatChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct BellCatalogView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            let repository = InMemoryCatalogRepository()
            let collection = repository.fetchCollections().first { $0.kind == .bells }!
            BellCatalogView(
                collection: collection,
                repository: repository,
                collaborators: repository.fetchCollaborators(for: collection.id),
                mode: .summary
            )
        }
    }
}
