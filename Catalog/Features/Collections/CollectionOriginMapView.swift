import SwiftUI
import SwiftData
import MapKit

struct CollectionOriginMapView: View {
    let collection: CollectionSummary
    let repository: any CatalogRepository
    @Query private var queriedBells: [BellEntity]

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedGroupID: String?

    init(collection: CollectionSummary, repository: any CatalogRepository) {
        self.collection = collection
        self.repository = repository
        let collectionID = Optional(collection.id)
        _queriedBells = Query(
            filter: #Predicate<BellEntity> { bell in
                bell.collection?.id == collectionID
            },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    private var mappedGroups: [MapBellGroup] {
        let grouped = Dictionary(grouping: queriedBells.compactMap { bell -> (String, BellEntity, CLLocationCoordinate2D)? in
            guard let place = bell.originPlace,
                  let latitude = place.latitude,
                  let longitude = place.longitude else {
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
                updateCameraIfNeeded()
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
                        .padding(.horizontal, CatalogLayoutInsets.overlay)
                        .padding(.bottom, CatalogSpacing.section)
                }
            }
        }
        .navigationTitle(String(localized: "collection.placeholder.map.title"))
        .navigationBarTitleDisplayMode(.inline)
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

        let coordinates = mappedGroups.map(\.coordinate)
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard let minLatitude = latitudes.min(),
              let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(),
              let maxLongitude = longitudes.max() else {
            return
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) * 1.6, 8),
            longitudeDelta: max((maxLongitude - minLongitude) * 1.6, 8)
        )

        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct MapBellGroup: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D

    let bells: [BellEntity]

    var title: String {
        bells.first?.title ?? ""
    }
}

private struct MapBellAnnotationView: View {
    let bells: [BellEntity]
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
                .clipShape(RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous)
                        .stroke(isSelected ? accentColor : CatalogMediaContrast.mediaSelectionStroke, lineWidth: isSelected ? 3 : 2)
                )

            if bells.count > 1 {
                Text("\(bells.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .catalogPillPadding(.micro)
                    .background(accentColor, in: Capsule())
                    .offset(x: 6, y: -6)
            }
        }
    }

    @ViewBuilder
    private var annotationImage: some View {
        if let identifier = bells.first?.coverPhotoIdentifier {
            BellCardCoverBackground(identifier: identifier, size: annotationSize)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous)
                    .fill(.regularMaterial)
                Image(systemName: "bell.fill")
                    .foregroundStyle(accentColor)
            }
        }
    }
}

private struct MapSelectionPanel: View {
    let bells: [BellEntity]
    let repository: any CatalogRepository

    @State private var presentedBell: BellEntity?

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
        .frame(height: bells.count == 1 ? BellGridLayoutMode.wide.cardHeight : BellGridLayoutMode.mini.cardHeight)
        .sheet(item: $presentedBell) { bell in
            BellDetailSheetContainer(bell: bell.recordSnapshot, repository: repository)
                .presentationDragIndicator(.visible)
        }
    }
}

private struct BellDetailSheetContainer: View {
    @State var bell: BellRecord
    let repository: any CatalogRepository

    var body: some View {
        NavigationStack {
            BellDetailView(bell: $bell, repository: repository)
        }
        .presentationBackground(.clear)
    }
}