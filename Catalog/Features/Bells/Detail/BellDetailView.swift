import SwiftUI
import UIKit
import MapKit
import SwiftData

struct BellDetailView: View {
    private enum DetailFeedback: Equatable {
        case success

        var sensoryFeedback: SensoryFeedback {
            switch self {
            case .success:
                return .success
            }
        }
    }

    private struct DetailFeedbackEvent: Equatable {
        let kind: DetailFeedback
        let token: Int
    }

    @Binding var bell: BellRecord
    let repository: any CatalogRepository
    @Query(sort: \CollectionEntity.title) private var collectionEntities: [CollectionEntity]
    @Query(sort: \LocationEntity.name) private var locationEntities: [LocationEntity]
    @State private var draftNotes = ""
    @State private var draftTags: [String] = []
    @State private var tagInput = ""
    @State private var isPresentingEditor = false
    @State private var isPresentingLocationPicker = false
    @State private var isPresentingUnsavedChangesConfirmation = false
    @State private var feedbackEvent: DetailFeedbackEvent?
    @State private var feedbackToken = 0

    init(bell: Binding<BellRecord>, repository: any CatalogRepository) {
        _bell = bell
        self.repository = repository

        let collectionID = bell.wrappedValue.item.collectionID
        _collectionEntities = Query(
            filter: #Predicate<CollectionEntity> { entity in
                entity.id == collectionID
            },
            sort: \.title
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroHeader

                VStack(alignment: .leading, spacing: 18) {
                    detailSection(String(localized: "bell.detail.section.collection_info")) {
                        detailRow(String(localized: "bell.detail.acquisition"), value: bell.acquisitionMethod.displayName)
                        detailRow(String(localized: "bell.detail.condition"), value: bell.condition.displayName)
                    }

                    detailSection(String(localized: "bell.detail.section.location")) {
                        OriginStorageSection(
                            place: bell.originPlace,
                            storagePath: bell.storageDisplayPath,
                            accentColor: detailAccentColor,
                            isStorageAssigned: bell.item.locationID != nil,
                            onEditStorage: {
                                isPresentingLocationPicker = true
                            }
                        )
                    }

                    detailSection(String(localized: "bell.detail.section.media")) {
                        MediaSection(
                            itemID: bell.id,
                            mediaAssets: mediaAssetsBinding,
                            allowsDeletion: false
                        )
                    }

                    detailSection(
                        String(localized: "bell.detail.section.notes"),
                        isHighlighted: isNotesOrTagsDirty,
                        tint: detailAccentColor
                    ) {
                        TextField(String(localized: "editor.note_history"), text: $draftNotes, axis: .vertical)
                            .lineLimit(6, reservesSpace: true)
                            .textFieldStyle(.plain)

                        TagEditorSection(
                            tagInput: $tagInput,
                            tags: $draftTags
                        )
                    }
                }
                .padding(.horizontal, CatalogLayoutInsets.screen)
                .padding(.top, CatalogSpacing.section)
                .padding(.bottom, CatalogSpacing.section)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .systemBackground))
            }
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .background(
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
        )
        .sensoryFeedback(trigger: feedbackEvent) { _, newValue in
            newValue?.kind.sensoryFeedback
        }
        .interactiveDismissDisabled(isNotesOrTagsDirty)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNotesOrTagsDirty {
                ToolbarItem(placement: .topBarLeading) {
                    Button { requestDiscardNotesAndTagsChanges() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(String(localized: "common.cancel"))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { saveNotesAndTagsChanges() } label: { Image(systemName: "checkmark") }
                    .accessibilityLabel(String(localized: "common.save"))
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isPresentingEditor = true } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel(String(localized: "common.edit"))
                }
            }
        }
        .confirmationDialog(
            String(localized: "bell.detail.unsaved_changes.title"),
            isPresented: $isPresentingUnsavedChangesConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.save")) {
                saveNotesAndTagsChanges()
            }

            Button(String(localized: "bell.detail.unsaved_changes.discard"), role: .destructive) {
                discardNotesAndTagsChanges()
            }

            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "bell.detail.unsaved_changes.message"))
        }
        .sheet(isPresented: $isPresentingEditor) {
            if let collection = inferredCollection {
                BellEditorView(
                    collection: collection,
                    repository: repository,
                    bell: bell
                ) { updatedBell in
                    repository.saveBellRecord(updatedBell)
                    bell = updatedBell
                }
            } else {
                ContentUnavailableView(String(localized: "home.not_found.title"), systemImage: "folder.badge.questionmark")
            }
        }
        .sheet(isPresented: $isPresentingLocationPicker) {
            LocationHierarchyPickerView(
                locations: availableLocations,
                selectedLocationID: locationIDBinding
            )
        }
        .onAppear {
            syncDraftsFromBell()
        }
        .onChange(of: bell) { _, _ in
            guard !isNotesOrTagsDirty else { return }
            syncDraftsFromBell()
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        isHighlighted: Bool = false,
        tint: Color = .clear,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CatalogCornerRadii.section, style: .continuous)
                .fill(isHighlighted ? AnyShapeStyle(tint.opacity(0.10)) : AnyShapeStyle(.ultraThinMaterial))
        )
        .catalogShadow(
            isHighlighted
                ? CatalogElevation.highlightedDetailSection(tint: tint)
                : CatalogElevation.detailSection
        )
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var heroHeader: some View {
        BellCardImagePreviewView(bell: bell)
    }

    private var availableLocations: [Location] {
        guard let homeID = inferredCollection?.homeID else { return [] }
        return locationEntities
            .filter { $0.home?.id == homeID }
            .map(\.locationSnapshot)
    }

    private var inferredCollection: CollectionSummary? {
        collectionEntities.first?.summarySnapshot
    }

    private var detailAccentColor: Color {
        inferredCollection?.backgroundStyle.accentColor ?? .accentColor
    }

    private var isNotesOrTagsDirty: Bool {
        draftNotes != bell.notes || draftTags != bell.tags
    }

    private func syncDraftsFromBell() {
        draftNotes = bell.notes
        draftTags = bell.tags
        tagInput = ""
    }

    private var mediaAssetsBinding: Binding<[MediaAsset]> {
        Binding(
            get: { bell.mediaAssets },
            set: { persist(mediaAssets: $0) }
        )
    }

    private var locationIDBinding: Binding<UUID?> {
        Binding(
            get: { bell.item.locationID },
            set: { persist(locationID: $0) }
        )
    }

    private func requestDiscardNotesAndTagsChanges() {
        guard isNotesOrTagsDirty else { return }
        isPresentingUnsavedChangesConfirmation = true
    }

    private func discardNotesAndTagsChanges() {
        syncDraftsFromBell()
    }

    private func saveNotesAndTagsChanges() {
        persist(
            notes: draftNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: draftTags
        )
        syncDraftsFromBell()
        emitFeedback(.success)
    }

    private func emitFeedback(_ kind: DetailFeedback) {
        feedbackToken += 1
        feedbackEvent = DetailFeedbackEvent(kind: kind, token: feedbackToken)
    }

    private func persist(
        notes: String? = nil,
        tags: [String]? = nil,
        mediaAssets: [MediaAsset]? = nil,
        locationID: UUID?? = nil
    ) {
        let resolvedLocationID = locationID ?? bell.item.locationID
        let location = availableLocations.first(where: { $0.id == resolvedLocationID })
        let locationsByID = Dictionary(uniqueKeysWithValues: availableLocations.map { ($0.id, $0) })
        let normalizedMediaAssets = (mediaAssets ?? bell.mediaAssets)
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, asset in
                MediaAsset(
                    id: asset.id,
                    itemID: bell.id,
                    kind: asset.kind,
                    localIdentifier: asset.localIdentifier,
                    displayName: asset.displayName,
                    sortOrder: index
                )
            }

        let updatedBell = BellRecord(
            item: Item(
                id: bell.item.id,
                collectionID: bell.item.collectionID,
                locationID: resolvedLocationID,
                createdAt: bell.item.createdAt,
                title: bell.item.title,
                notes: notes ?? bell.notes,
                acquiredYear: bell.item.acquiredYear,
                condition: bell.item.condition,
                acquisitionMethod: bell.item.acquisitionMethod
            ),
            details: bell.details,
            originPlace: bell.originPlace,
            storageLocation: location,
            storagePath: location.map { locationPath(for: $0, locationsByID: locationsByID) } ?? String(localized: "common.unassigned"),
            mediaAssets: normalizedMediaAssets,
            createdBy: bell.createdBy,
            tags: tags ?? bell.tags
        )

        repository.saveBellRecord(updatedBell)
        bell = updatedBell
    }

    private func locationPath(for location: Location, locationsByID: [UUID: Location]) -> String {
        var parts = [location.name]
        var currentParentID = location.parentLocationID

        while let parentID = currentParentID, let parent = locationsByID[parentID] {
            parts.insert(parent.name, at: 0)
            currentParentID = parent.parentLocationID
        }

        return parts.joined(separator: " / ")
    }
}

private struct BellDetailPreviewHost: View {
    let collectionID: UUID
    let repository: any CatalogRepository
    @Query(sort: \BellEntity.createdAt, order: .reverse) private var bells: [BellEntity]
    @State private var bell: BellRecord?

    var body: some View {
        Group {
            if let binding = bellBinding {
                BellDetailView(
                    bell: binding,
                    repository: repository
                )
            } else {
                ContentUnavailableView(String(localized: "home.not_found.title"), systemImage: "bell.slash")
            }
        }
        .onAppear(perform: syncBellIfNeeded)
    }

    private var bellBinding: Binding<BellRecord>? {
        guard bell != nil else { return nil }
        return Binding(
            get: { bell! },
            set: { bell = $0 }
        )
    }

    private func syncBellIfNeeded() {
        guard bell == nil else { return }
        bell = bells.first(where: { $0.collection?.id == collectionID })?.recordSnapshot
    }
}
