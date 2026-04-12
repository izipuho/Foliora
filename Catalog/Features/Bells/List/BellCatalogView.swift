import SwiftUI

struct BellCatalogView: View {
    let collection: CollectionSummary
    let repository: any CatalogRepository
    let collaborators: [Collaborator]

    @State private var bellRecords: [BellRecord]
    @State private var searchText = ""
    @State private var selectedCondition: ItemCondition?
    @State private var isPresentingAddBell = false

    init(collection: CollectionSummary, repository: any CatalogRepository, collaborators: [Collaborator]) {
        self.collection = collection
        self.repository = repository
        self.collaborators = collaborators
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                searchSection
                collaboratorStrip

                if filteredBells.isEmpty {
                    ContentUnavailableView(
                        "Ничего не найдено",
                        systemImage: "bell.slash",
                        description: Text("Попробуйте изменить запрос или сбросить фильтр по состоянию.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(filteredBells) { bell in
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
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.96, blue: 0.90),
                    Color(red: 0.95, green: 0.91, blue: 0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle(collection.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingAddBell = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAddBell) {
            BellEditorView(
                collection: collection,
                repository: repository
            ) { newBell in
                bellRecords.insert(newBell, at: 0)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(collection.name)
                        .font(.largeTitle.bold())

                    Text("Отдельный UI для колокольчиков: происхождение, материал, состояние, заметки и прозрачный доступ участников коллекции.")
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.66))
                        .frame(width: 62, height: 62)

                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.16))
                }
            }

            HStack(spacing: 12) {
                StatChip(title: "Items", value: "\(bells.count)")
                StatChip(title: "Countries", value: "\(countryCount)")
                StatChip(title: "Materials", value: "\(materialCount)")
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Поиск по названию, городу или тегу", text: $searchText)
                .textInputAutocapitalization(.sentences)
                .padding(14)
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    FilterChip(title: "Все", isSelected: selectedCondition == nil) {
                        selectedCondition = nil
                    }

                    ForEach(ItemCondition.allCases) { condition in
                        FilterChip(title: condition.rawValue, isSelected: selectedCondition == condition) {
                            selectedCondition = condition
                        }
                    }
                }
            }
        }
    }

    private var collaboratorStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Доступ к коллекции")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(collaborators) { collaborator in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(collaborator.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(collaborator.role.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(
                            collaborator.isCurrentUser
                                ? Color(red: 0.61, green: 0.35, blue: 0.14).opacity(0.16)
                                : Color.white.opacity(0.78),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func binding(for bellID: UUID) -> Binding<BellRecord>? {
        guard let index = bellRecords.firstIndex(where: { $0.id == bellID }) else { return nil }
        return $bellRecords[index]
    }
}

struct BellEditorView: View {
    let collection: CollectionSummary
    let repository: any CatalogRepository
    let onSave: (BellRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var yearText = ""
    @State private var condition: ItemCondition = .good
    @State private var acquisitionMethod: AcquisitionMethod = .bought
    @State private var material: BellMaterial = .brass
    @State private var customMaterialName = ""
    @State private var selectedLocationID: UUID?
    @State private var tagsText = ""
    private let existingBellID: UUID?

    private var availableLocations: [Location] {
        guard let home = repository.fetchHomes().first else { return [] }
        return repository.fetchLocations(in: home.id)
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
        _title = State(initialValue: bell?.title ?? "")
        _notes = State(initialValue: bell?.notes ?? "")
        _yearText = State(initialValue: bell?.year.map(String.init) ?? "")
        _condition = State(initialValue: bell?.condition ?? .good)
        _acquisitionMethod = State(initialValue: bell?.acquisitionMethod ?? .bought)
        _material = State(initialValue: bell?.details.material ?? .brass)
        _customMaterialName = State(initialValue: bell?.details.customMaterialName ?? "")
        _selectedLocationID = State(initialValue: bell?.item.locationID)
        _tagsText = State(initialValue: bell?.tags.joined(separator: ", ") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Main Info") {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                    TextField("Year", text: $yearText)
                        .keyboardType(.numberPad)
                }

                Section("Attributes") {
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
                    Picker("Location", selection: $selectedLocationID) {
                        Text("Unassigned").tag(Optional<UUID>.none)
                        ForEach(availableLocations) { location in
                            Text(location.name).tag(Optional(location.id))
                        }
                    }
                }

                Section("Tags") {
                    TextField("museum, travel, gift", text: $tagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let itemID = existingBellID ?? UUID()
        let location = availableLocations.first(where: { $0.id == selectedLocationID })

        let newBell = BellRecord(
            item: Item(
                id: itemID,
                collectionID: collection.id,
                locationID: selectedLocationID,
                title: trimmedTitle,
                notes: trimmedNotes,
                year: Int(yearText),
                condition: condition,
                acquisitionMethod: acquisitionMethod
            ),
            details: BellDetails(
                itemID: itemID,
                originPlaceID: nil,
                material: material,
                customMaterialName: material == .other ? trimmedCustomMaterial : nil
            ),
            originPlace: nil,
            storageLocation: location,
            mediaAssets: [],
            createdBy: "You",
            tags: tags
        )

        onSave(newBell)
        dismiss()
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
                MetaChip(label: bell.storageLocationName, systemImage: "shippingbox.circle")
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    isSelected
                        ? Color(red: 0.53, green: 0.31, blue: 0.14)
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
                collaborators: repository.fetchCollaborators(for: collection.id)
            )
        }
    }
}
