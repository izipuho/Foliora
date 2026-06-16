import SwiftUI
import UIKit
import MapKit
import CoreData

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
    @Environment(\.managedObjectContext) private var managedObjectContext
    @State private var lookupSnapshot = BellLookupSnapshot()
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
    }

    var body: some View {
        ScrollView {
            ZStack(alignment: .top) {
                heroHeader
                detailContent
            }
        }
        .ignoresSafeArea(edges: .top)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .sensoryFeedback(trigger: feedbackEvent) { _, newValue in
            newValue?.kind.sensoryFeedback
        }
        .interactiveDismissDisabled(isNotesOrTagsDirty)
        .navigationTitle(bell.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
        .task {
            reloadLookupSnapshot()
        }
        .onAppear {
            syncDraftsFromBell()
        }
        .onChange(of: bell) { _, _ in
            guard !isNotesOrTagsDirty else { return }
            syncDraftsFromBell()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: managedObjectContext)) { _ in
            reloadLookupSnapshot()
        }
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            detailSection(String(localized: "bell.detail.section.collection_info")) {
                if let acquiredYear = bell.acquiredYear {
                    detailRow(String(localized: "common.field.acquired_year"), value: String(acquiredYear))
                }

                detailRow(String(localized: "bell.detail.acquisition"), value: bell.acquisitionMethod.displayName)
                detailRow(String(localized: "common.field.condition"), value: bell.condition.displayName)
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
                String(localized: "common.field.notes"),
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
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color(uiColor: .systemBackground).opacity(0.88), location: 0.08),
                    .init(color: Color(uiColor: .systemBackground), location: 0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .padding(.top, 240)
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
        GeometryReader { proxy in
            ZStack {
                if bell.coverPhotoThumbnailData != nil || bell.coverPhotoIdentifier != nil || bell.coverPhotoOriginalData != nil {
                    BellCardCoverBackground(
                        identifier: bell.coverPhotoIdentifier,
                        thumbnailData: bell.coverPhotoThumbnailData,
                        originalData: bell.coverPhotoOriginalData,
                        size: CGSize(width: proxy.size.width, height: 320)
                    )
                } else {
                    LinearGradient(
                        colors: [
                            CatalogMediaContrast.previewGradientStart,
                            CatalogMediaContrast.previewGradientEnd
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: proxy.size.width, height: 320)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color(uiColor: .systemBackground).opacity(0.22), location: 0.72),
                        .init(color: Color(uiColor: .systemBackground).opacity(0.55), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
            }
        }
        .frame(height: 320)
        .ignoresSafeArea(edges: .top)
    }

    private var availableLocations: [Location] {
        guard let homeID = inferredCollection?.homeID else { return [] }
        return lookupSnapshot.locations.filter { $0.homeID == homeID }
    }

    private var inferredCollection: CollectionSummary? {
        lookupSnapshot.collections.first(where: { $0.id == bell.item.collectionID })?.summarySnapshot
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

    private func reloadLookupSnapshot() {
        lookupSnapshot = CoreDataBellLookupSnapshotLoader(context: managedObjectContext)
            .loadSnapshot(collectionID: bell.item.collectionID, homeID: nil)
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
                asset.with(itemID: bell.id, sortOrder: index)
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
        reloadLookupSnapshot()
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
    @Environment(\.managedObjectContext) private var managedObjectContext
    @State private var lookupSnapshot = BellLookupSnapshot()
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
        .task {
            reloadLookupSnapshot()
            syncBellIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: managedObjectContext)) { _ in
            reloadLookupSnapshot()
            syncBellIfNeeded()
        }
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
        bell = lookupSnapshot.bells.first(where: { $0.item.collectionID == collectionID })
    }

    private func reloadLookupSnapshot() {
        lookupSnapshot = CoreDataBellLookupSnapshotLoader(context: managedObjectContext)
            .loadSnapshot(collectionID: collectionID, homeID: nil)
    }
}

private extension Collection {
    var summarySnapshot: CollectionSummary {
        CollectionSummary(
            id: id,
            homeID: homeID,
            kind: kind,
            name: title,
            subtitle: notes,
            backgroundStyle: backgroundStyle,
            itemCount: 0,
            status: kind == .bells ? .active : .planned,
            sharingSummary: "Invitation-only. Members join with Apple ID and receive a role inside the collection."
        )
    }
}
