import SwiftUI
import UIKit

private func BL(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum BellSortOption: String, CaseIterable, Hashable {
    case title
    case origin
    case yearNewest
    case yearOldest

    var title: String {
        switch self {
        case .title:
            return BL("bell_catalog.sort.title")
        case .origin:
            return BL("bell_catalog.sort.origin")
        case .yearNewest:
            return BL("bell_catalog.sort.year_newest")
        case .yearOldest:
            return BL("bell_catalog.sort.year_oldest")
        }
    }
}

enum BellCatalogMode {
    case summary
    case items
    case search
}

enum BellGridLayoutMode: Int, CaseIterable {
    case covers
    case mini
    case compact
    case wide
    case showcase

    var columnCount: Int {
        switch self {
        case .covers:
            return 4
        case .mini:
            return 3
        case .compact:
            return 2
        case .wide, .showcase:
            return 1
        }
    }

    var cardHeight: CGFloat {
        switch self {
        case .covers:
            return 92
        case .mini:
            return 144
        case .compact:
            return 220
        case .wide:
            return 170
        case .showcase:
            return 460
        }
    }

    var cardPadding: CGFloat {
        switch self {
        case .covers:
            return 0
        case .mini:
            return 10
        case .compact:
            return 14
        case .wide:
            return 18
        case .showcase:
            return 22
        }
    }

    var spacing: CGFloat {
        switch self {
        case .covers:
            return 8
        case .mini:
            return 10
        case .compact:
            return 12
        case .wide:
            return 14
        case .showcase:
            return 18
        }
    }

    func preferredCardWidth(for availableWidth: CGFloat) -> CGFloat {
        let totalSpacing = spacing * CGFloat(max(columnCount - 1, 0))
        let usableWidth = max(availableWidth - totalSpacing, 0)
        return floor(usableWidth / CGFloat(columnCount))
    }

    var stripHeight: CGFloat {
        cardHeight + spacing
    }
}

struct BellCatalogView: View {
    let repository: any CatalogRepository
    let collaborators: [Collaborator]
    let collection: CollectionSummary
    let mode: BellCatalogMode
    let sortOption: BellSortOption

    @State private var bellRecords: [BellRecord]
    @State private var searchText = ""
    @State private var selectedCondition: ItemCondition?
    @State private var layoutMode: BellGridLayoutMode = .compact
    @State private var presentedBell: BellRecord?

    init(
        collection: CollectionSummary,
        repository: any CatalogRepository,
        collaborators: [Collaborator],
        mode: BellCatalogMode,
        sortOption: BellSortOption = .title
    ) {
        self.repository = repository
        self.collaborators = collaborators
        self.collection = collection
        self.mode = mode
        self.sortOption = sortOption
        _bellRecords = State(initialValue: repository.fetchBellRecords(for: collection.id))
    }

    private var bells: [BellRecord] {
        sorted(bellRecords)
    }

    private var filteredBells: [BellRecord] {
        sorted(
            bellRecords.filter { bell in
            let matchesSearch =
                searchText.isEmpty ||
                bell.title.localizedCaseInsensitiveContains(searchText) ||
                bell.countryName.localizedCaseInsensitiveContains(searchText) ||
                bell.cityName.localizedCaseInsensitiveContains(searchText) ||
                bell.tags.joined(separator: " ").localizedCaseInsensitiveContains(searchText)

            let matchesCondition = selectedCondition == nil || bell.condition == selectedCondition
            return matchesSearch && matchesCondition
        })
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

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: layoutMode.spacing, alignment: .top),
            count: layoutMode.columnCount
        )
    }

    @ViewBuilder
    var body: some View {
        switch mode {
        case .summary:
            summaryContent
        case .items:
            bellGridContent(
                bells: bells,
                showsSearchControls: false,
                emptyTitle: LocalizedStringKey(BL("bell_catalog.empty.title")),
                emptyDescription: LocalizedStringKey(BL("bell_catalog.empty.description"))
            )
        case .search:
            bellGridContent(
                bells: filteredBells,
                showsSearchControls: true,
                emptyTitle: LocalizedStringKey(BL("bell_catalog.search.empty.title")),
                emptyDescription: LocalizedStringKey(BL("bell_catalog.search.empty.description"))
            )
        }
    }

    private var summaryContent: some View {
        List {
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

    private func bellGridContent(
        bells: [BellRecord],
        showsSearchControls: Bool,
        emptyTitle: LocalizedStringKey,
        emptyDescription: LocalizedStringKey
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if showsSearchControls {
                    searchSection
                }

                if bells.isEmpty {
                    emptyBellsGridState(title: emptyTitle, description: emptyDescription)
                } else {
                    LazyVGrid(columns: gridColumns, spacing: layoutMode.spacing) {
                        ForEach(bells) { bell in
                            Button {
                                presentedBell = bell
                            } label: {
                                BellCardView(
                                    bell: bell,
                                    layoutMode: layoutMode
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
            .animation(.snappy(duration: 0.24), value: layoutMode)
        }
        .simultaneousGesture(zoomGesture)
        .background(
            LinearGradient(
                colors: themeColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .sheet(item: $presentedBell, onDismiss: {
            bellRecords = repository.fetchBellRecords(for: collection.id)
        }) { bell in
            BellGridDetailSheetContainer(bell: bell, repository: repository)
                .presentationDragIndicator(.visible)
        }
    }

    private func emptyBellsGridState(title: LocalizedStringKey, description: LocalizedStringKey) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "bell.slash",
            description: Text(description)
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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
                        FilterChip(title: condition.displayName, isSelected: selectedCondition == condition, tint: collection.backgroundStyle.accentColor) {
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

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onEnded { value in
                if value.magnification > 1.12 {
                    zoomIn()
                } else if value.magnification < 0.92 {
                    zoomOut()
                }
            }
    }

    private func zoomIn() {
        guard let nextMode = BellGridLayoutMode(rawValue: layoutMode.rawValue + 1) else { return }
        layoutMode = nextMode
    }

    private func zoomOut() {
        guard let previousMode = BellGridLayoutMode(rawValue: layoutMode.rawValue - 1) else { return }
        layoutMode = previousMode
    }

    private func sorted(_ bells: [BellRecord]) -> [BellRecord] {
        bells.sorted { lhs, rhs in
            switch sortOption {
            case .title:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .origin:
                let leftOrigin = lhs.placeDisplayName
                let rightOrigin = rhs.placeDisplayName

                if leftOrigin.localizedCaseInsensitiveCompare(rightOrigin) == .orderedSame {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }

                return leftOrigin.localizedCaseInsensitiveCompare(rightOrigin) == .orderedAscending
            case .yearNewest:
                switch (lhs.acquiredYear, rhs.acquiredYear) {
                case let (left?, right?) where left != right:
                    return left > right
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            case .yearOldest:
                switch (lhs.acquiredYear, rhs.acquiredYear) {
                case let (left?, right?) where left != right:
                    return left < right
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
        }
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
    @State private var selectedOriginPlace: Place?
    @State private var selectedLocationID: UUID?
    @State private var tagInput = ""
    @State private var tags: [String] = []
    @State private var mediaAssets: [MediaAsset] = []
    @State private var selectedAcquiredYearOption = BL("editor.acquired_year.none")
    private let existingBellID: UUID?
    private let editorItemID: UUID

    private let acquiredYearOptions = [BL("editor.acquired_year.none")] + Array(1900...Calendar.current.component(.year, from: .now)).reversed().map(String.init)

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
        initialMediaAssets: [MediaAsset] = [],
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
        _selectedOriginPlace = State(initialValue: bell?.originPlace)
        _selectedLocationID = State(initialValue: bell?.item.locationID)
        _tags = State(initialValue: bell?.tags ?? [])
        _mediaAssets = State(initialValue: bell?.mediaAssets ?? initialMediaAssets)
        _selectedAcquiredYearOption = State(initialValue: bell?.acquiredYear.map(String.init) ?? BL("editor.acquired_year.none"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(BL("editor.media")) {
                    MediaSection(
                        itemID: editorItemID,
                        mediaAssets: $mediaAssets
                    )
                }

                Section(BL("editor.description")) {
                    TextField(BL("editor.short_description"), text: $title)
                    TextField(BL("editor.note_history"), text: $notes, axis: .vertical)
                        .lineLimit(4, reservesSpace: true)
                }

                Section(BL("editor.acquisition_details")) {
                    YearPickerField(
                        title: BL("editor.acquired_year"),
                        selection: $selectedAcquiredYearOption,
                        options: acquiredYearOptions
                    )

                    EnumSelectionRow(
                        title: BL("editor.acquisition"),
                        selectedLabel: acquisitionMethod.displayName,
                        options: AcquisitionMethod.allCases,
                        selection: $acquisitionMethod,
                        optionTitle: \.displayName
                    )
                }

                Section(BL("editor.attributes")) {
                    EnumSelectionRow(
                        title: BL("editor.condition"),
                        selectedLabel: condition.displayName,
                        options: ItemCondition.allCases,
                        selection: $condition,
                        optionTitle: \.displayName
                    )

                    EnumSelectionRow(
                        title: BL("editor.material"),
                        selectedLabel: material.displayName,
                        options: BellMaterial.allCases,
                        selection: $material,
                        optionTitle: \.displayName
                    )

                    if material == .other {
                        TextField(BL("editor.material.custom"), text: $customMaterialName)
                    }
                }

                Section(BL("editor.storage")) {
                    LocationPickerField(
                        title: BL("editor.location"),
                        selectedLabel: selectedLocationLabel,
                        locations: availableLocations,
                        selectedLocationID: $selectedLocationID
                    )
                }

                Section(BL("editor.additional_details")) {
                    PlacePickerField(
                        title: BL("editor.origin"),
                        selectedLabel: selectedOriginLabel,
                        places: availablePlaces,
                        selectedPlace: $selectedOriginPlace
                    )
                }

                Section(BL("editor.tags")) {
                    TagEditorSection(
                        tagInput: $tagInput,
                        tags: $tags
                    )
                }
            }
            .navigationTitle(existingBellID == nil ? BL("editor.bell.add") : BL("editor.bell.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(BL("common.cancel"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveBell()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(BL("common.save"))
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
        let originPlace = selectedOriginPlace
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
                acquiredYear: selectedAcquiredYearOption == BL("editor.acquired_year.none") ? nil : Int(selectedAcquiredYearOption),
                condition: condition,
                acquisitionMethod: acquisitionMethod
            ),
            details: BellDetails(
                itemID: itemID,
                originPlaceID: selectedOriginPlace?.id,
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
        selectedOriginPlace?.displayName ?? BL("common.unassigned")
    }

    private var selectedLocationLabel: String {
        guard let selectedLocationID, let path = locationPathByID[selectedLocationID] else {
            return BL("common.unassigned")
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

struct BellCardView: View {
    let bell: BellRecord
    let layoutMode: BellGridLayoutMode

    @ViewBuilder
    var body: some View {
        if layoutMode == .wide {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.clear)
                .overlay {
                    cardBackground
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(hasCoverPhoto ? 0.34 : 0),
                            Color.black.opacity(hasCoverPhoto ? 0.10 : 0),
                            Color.black.opacity(hasCoverPhoto ? 0.08 : 0)
                        ],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bell.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(hasCoverPhoto ? .white : .primary)
                            .lineLimit(2)

                        Text(bell.placeDisplayName)
                            .font(.caption)
                            .foregroundStyle(hasCoverPhoto ? .white.opacity(0.86) : .secondary)
                            .lineLimit(2)
                    }
                    .padding(layoutMode.cardPadding)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 8) {
                        CompactMetaChip(
                            label: bell.materialDisplayName,
                            systemImage: "shippingbox.fill",
                            bright: hasCoverPhoto
                        )

                        if let acquiredYear = bell.acquiredYear {
                            CompactMetaChip(
                                label: String(acquiredYear),
                                systemImage: "calendar",
                                bright: hasCoverPhoto
                            )
                        }
                    }
                    .padding(layoutMode.cardPadding)
                }
                .frame(maxWidth: .infinity)
                .frame(height: layoutMode.cardHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
        } else {
            ZStack(alignment: .topLeading) {
                cardBackground

                LinearGradient(
                    colors: [
                        Color.black.opacity(hasCoverPhoto ? 0.34 : 0),
                        Color.black.opacity(hasCoverPhoto ? 0.10 : 0),
                        Color.black.opacity(hasCoverPhoto ? 0.08 : 0)
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                cardContent
                    .padding(layoutMode.cardPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: layoutMode.cardHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch layoutMode {
        case .covers:
            if !hasCoverPhoto {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bell.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(bell.placeDisplayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

        case .mini:
            VStack(alignment: .leading, spacing: 4) {
                Spacer()

                Text(bell.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(2)

                Text(bell.placeDisplayName)
                    .font(.caption2)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)

                if let acquiredYear = bell.acquiredYear {
                    Text(String(acquiredYear))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(hasCoverPhoto ? .white.opacity(0.9) : .secondary)
                }
            }

        case .compact:
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bell.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(2)

                    Text(bell.placeDisplayName)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(2)
                }

                Spacer()

                if let acquiredYear = bell.acquiredYear {
                    CompactMetaChip(
                        label: String(acquiredYear),
                        systemImage: "calendar",
                        bright: hasCoverPhoto
                    )
                }
            }

        case .wide:
            EmptyView()

        case .showcase:
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bell.title)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(3)

                    Text(bell.placeDisplayName)
                        .font(.body)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(2)
                }

                Spacer()

                HStack(spacing: 8) {
                    CompactMetaChip(
                        label: bell.materialDisplayName,
                        systemImage: "shippingbox.fill",
                        bright: hasCoverPhoto
                    )

                    if let acquiredYear = bell.acquiredYear {
                        CompactMetaChip(
                            label: String(acquiredYear),
                            systemImage: "calendar",
                            bright: hasCoverPhoto
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if let coverPhotoAsset {
            BellCardCoverBackground(asset: coverPhotoAsset)
        } else {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.88),
                    Color.white.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var coverPhotoAsset: MediaAsset? {
        bell.mediaAssets
            .filter({ $0.kind == .photo })
            .sorted(by: { $0.sortOrder < $1.sortOrder })
            .first
    }

    private var hasCoverPhoto: Bool {
        coverPhotoAsset != nil
    }

    private var primaryTextColor: Color {
        hasCoverPhoto ? .white : .primary
    }

    private var secondaryTextColor: Color {
        hasCoverPhoto ? .white.opacity(0.86) : .secondary
    }
}

struct BellCardCoverBackground: View {
    let asset: MediaAsset
    private let mediaStore = LocalMediaFileStore.shared
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.88),
                        Color.white.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .task(id: asset.localIdentifier) {
            loadImage()
        }
    }

    private func loadImage() {
        guard image == nil,
              let url = mediaStore.fileURL(for: asset.localIdentifier),
              let loadedImage = UIImage(contentsOfFile: url.path) else {
            return
        }

        image = loadedImage
    }
}

private struct CompactMetaChip: View {
    let label: String
    let systemImage: String
    let bright: Bool

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                bright
                    ? Color.white.opacity(0.16)
                    : Color.black.opacity(0.04),
                in: Capsule()
            )
            .foregroundStyle(bright ? .white : .secondary)
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

private struct BellGridDetailSheetContainer: View {
    @State var bell: BellRecord
    let repository: any CatalogRepository

    var body: some View {
        NavigationStack {
            BellDetailView(bell: $bell, repository: repository)
        }
        .presentationBackground(.clear)
    }
}
