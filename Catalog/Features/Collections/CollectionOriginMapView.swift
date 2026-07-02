import SwiftUI
import CoreData
import MapKit

struct CollectionOriginMapView: View {
    let collection: CollectionSummary
    let repository: any CatalogRepository
    @Environment(\.managedObjectContext) private var managedObjectContext
    @State private var catalogSnapshot = BellCatalogSnapshot()

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedGroupID: String?

    init(collection: CollectionSummary, repository: any CatalogRepository) {
        self.collection = collection
        self.repository = repository
    }

    private var mappedGroups: [MapBellGroup] {
        let grouped = Dictionary(grouping: catalogSnapshot.bells.compactMap { listItem -> (String, BellRecord, CLLocationCoordinate2D)? in
            guard let bell = catalogSnapshot.recordsByID[listItem.id],
                  let latitude = bell.originPlace?.latitude,
                  let longitude = bell.originPlace?.longitude else {
                return nil
            }

            let roundedLatitude = (latitude * 100).rounded() / 100
            let roundedLongitude = (longitude * 100).rounded() / 100
            let key = "\(roundedLatitude)|\(roundedLongitude)"
            return (key, bell, CLLocationCoordinate2D(latitude: roundedLatitude, longitude: roundedLongitude))
        }, by: \.0)

        return grouped.compactMap { key, entries in
            guard let coordinate = entries.first?.2 else { return nil }
            let groupedBells = entries.map(\.1)
            return MapBellGroup(
                id: key,
                coordinate: coordinate,
                bells: groupedBells
            )
        }
        .sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private var selectedGroup: MapBellGroup? {
        mappedGroups.first(where: { $0.id == selectedGroupID })
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position, interactionModes: .all) {
                ForEach(mappedGroups) { group in
                    Annotation("", coordinate: group.coordinate, anchor: .bottom) {
                        Button {
                            selectedGroupID = group.id
                        } label: {
                            MapBellAnnotationView(
                                bells: group.bells,
                                isSelected: selectedGroupID == group.id,
                                accentColor: collection.backgroundStyle.accentColor
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .ignoresSafeArea()
            .onAppear {
                reloadCatalogSnapshot()
                updateCameraIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange,
                object: managedObjectContext
            )) { _ in
                reloadCatalogSnapshot()
            }
            .onChange(of: mappedGroups.map(\.id)) { _, _ in
                updateCameraIfNeeded()
            }
            .overlay(alignment: .bottom) {
                if let selectedGroup {
                    MapSelectionPanel(
                        bells: selectedGroup.bells,
                        repository: repository
                    )
                    .padding(.bottom, CatalogMetrics.Spacing.xl)
                }
            }
        }
        .navigationTitle(String(localized: "collection.placeholder.map.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reloadCatalogSnapshot() {
        catalogSnapshot = BellCatalogSnapshot(context: managedObjectContext, collectionID: collection.id)
    }

    private func updateCameraIfNeeded() {
        guard !mappedGroups.isEmpty else {
            position = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
                    span: MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 80)
                )
            )
            selectedGroupID = nil
            return
        }

        if mappedGroups.count == 1, let onlyGroup = mappedGroups.first {
            position = .region(
                MKCoordinateRegion(
                    center: onlyGroup.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8)
                )
            )
            selectedGroupID = selectedGroupID ?? onlyGroup.id
            return
        }

        guard let focusedGroup = mappedGroups.max(by: { $0.bells.count < $1.bells.count }) else {
            return
        }

        position = .region(
            MKCoordinateRegion(
                center: focusedGroup.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)
            )
        )
        selectedGroupID = focusedGroup.id
    }
}

private struct MapBellGroup: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D

    let bells: [BellRecord]

    var title: String {
        bells.first?.title ?? ""
    }
}

private struct MapBellAnnotationView: View {
    let bells: [BellRecord]
    let isSelected: Bool
    let accentColor: Color

    private var annotationSize: CGSize {
        let side = isSelected ? 56.0 : 48.0
        return CGSize(width: side, height: side)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            annotationImage
                .frame(width: annotationSize.width, height: annotationSize.height)
                .clipShape(RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.tile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.tile, style: .continuous)
                        .stroke(isSelected ? accentColor : CatalogMediaContrast.mediaSelectionStroke, lineWidth: isSelected ? 3 : 2)
                )

            if bells.count > 1 {
                Text("\(bells.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CatalogMediaContrast.onMediaPrimary)
                    .catalogPillPadding(.micro)
                    .background(accentColor, in: Capsule())
                    .offset(x: 6, y: -6)
            }
        }
    }

    @ViewBuilder
    private var annotationImage: some View {
        if let bell = bells.first,
           bell.coverPhotoThumbnailData != nil || bell.coverPhotoIdentifier != nil || bell.coverPhotoOriginalData != nil {
            BellCardCoverBackground(
                identifier: bell.coverPhotoIdentifier,
                thumbnailData: bell.coverPhotoThumbnailData,
                originalData: bell.coverPhotoOriginalData,
                size: annotationSize
            )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.tile, style: .continuous)
                    .fill(.regularMaterial)
                Image(systemName: "bell.fill")
                    .foregroundStyle(accentColor)
            }
        }
    }
}

private struct MapSelectionPanel: View {
    let bells: [BellRecord]
    let repository: any CatalogRepository

    @State private var presentedBell: BellRecord?

    var body: some View {
        GeometryReader { proxy in
            Group {
                if bells.count == 1 {
                    BellCardStripView(
                        bells: bells,
                        layoutMode: .wide,
                        screenWidth: proxy.size.width + 32
                    ) { bell in
                        presentedBell = bell
                    }
                } else {
                    BellCardStripView(
                        bells: bells,
                        layoutMode: .mini,
                        screenWidth: proxy.size.width + 32
                    ) { bell in
                        presentedBell = bell
                    }
                }
            }
        }
        .frame(height: bells.count == 1 ? BellGridLayoutMode.wide.cardMetrics.cardHeight : BellGridLayoutMode.mini.cardMetrics.cardHeight)
        .sheet(item: $presentedBell) { bell in
            BellDetailSheetContainer(bell: bell, repository: repository)
                .presentationDragIndicator(.visible)
        }
    }
}

private struct BellDetailSheetContainer: View {
    @State var bell: BellRecord
    let repository: any CatalogRepository

    var body: some View {
        NavigationStack {
            BellDetailView(
                bell: $bell,
                repository: repository,
                canEditCollection: false
            )
        }
        .presentationBackground(.clear)
    }
}
