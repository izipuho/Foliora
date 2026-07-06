import SwiftUI
import MapKit

struct OriginStorageSection: View {
    let place: Place?
    let storagePath: String
    let accentColor: Color
    let isStorageAssigned: Bool
    let canEditStorage: Bool
    let onEditStorage: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: CatalogMetrics.Spacing.md) {
            OriginTile(place: place, accentColor: accentColor)

            StorageTile(
                storagePath: storagePath,
                accentColor: accentColor,
                isAssigned: isStorageAssigned,
                canEditStorage: canEditStorage,
                onEditStorage: onEditStorage
            )
        }
    }
}

private struct OriginTile: View {
    let place: Place?
    let accentColor: Color
    private let coordinate: CLLocationCoordinate2D?
    private let region: MKCoordinateRegion?

    init(place: Place?, accentColor: Color) {
        self.place = place
        self.accentColor = accentColor

        guard let latitude = place?.latitude, let longitude = place?.longitude else {
            coordinate = nil
            region = nil
            return
        }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.coordinate = coordinate
        region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 4.8, longitudeDelta: 4.8)
        )
    }

    var body: some View {
        Group {
            if place == nil {
                DetailTileCTAContent(
                    systemImage: "mappin.slash",
                    title: "common.unknown_origin",
                    message: "common.unassigned",
                    accentColor: accentColor
                )
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                .catalogSurfaceTile()
            } else {
                originContent
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .bottomLeading)
                    .catalogSurfaceTile {
                        originMedia
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var originContent: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
            Label(String(localized: "common.field.origin"), systemImage: "mappin.and.ellipse")
                .font(CatalogTypography.chipLabel)
                .foregroundStyle(CatalogMediaContrast.onMediaPrimary)

            Text(place?.displayName ?? String(localized: "common.unassigned"))
                .font(CatalogTypography.cardSubtitle)
                .foregroundStyle(CatalogMediaContrast.onMediaPrimary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var originMedia: some View {
        if let coordinate, let region {
            Map(initialPosition: .region(region), interactionModes: []) {
                Marker("", coordinate: coordinate)
            }
            .mapStyle(.standard(elevation: .flat))
        } else {
            Color.clear
        }
    }
}

private struct StorageTile: View {
    let storagePath: String
    let accentColor: Color
    let isAssigned: Bool
    let canEditStorage: Bool
    let onEditStorage: () -> Void

    private var pathParts: [String] {
        storagePath
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        Group {
            if canEditStorage {
                Button(action: onEditStorage) {
                    tileContent
                }
                .buttonStyle(.plain)
            } else {
                tileContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tileContent: some View {
        Group {
            if isAssigned {
                assignedTileContent
            } else {
                placeholderTileContent
            }
        }
    }

    private var assignedTileContent: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            Label(String(localized: "common.field.storage"), systemImage: "square.stack.3d.up")
                .font(CatalogTypography.chipLabel)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                ForEach(Array(pathParts.enumerated()), id: \.offset) { index, part in
                    Text(part)
                        .font(index == pathParts.count - 1 ? CatalogTypography.cardTitle : CatalogTypography.cardSubtitle)
                        .foregroundStyle(index == pathParts.count - 1 ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .catalogSurfaceTile()
    }

    private var placeholderTileContent: some View {
        DetailTileCTAContent(
            systemImage: "square.stack.3d.up.slash",
            title: "bell.detail.storage.assign.action",
            message: "bell.detail.storage.placeholder",
            accentColor: accentColor
        )
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        .catalogSurfaceTile()
    }
}

private struct DetailTileCTAContent: View {
    let systemImage: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let accentColor: Color

    var body: some View {
        VStack(spacing: CatalogMetrics.Spacing.sm) {
            Spacer(minLength: 0)

            Label(title, systemImage: systemImage)
                .font(CatalogTypography.cardLabel)
                .foregroundStyle(accentColor)
                .multilineTextAlignment(.center)

            Text(message)
                .font(CatalogTypography.cardSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}
