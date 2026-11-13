import MapKit
import SwiftUI

/// Displays a reusable origin tile for catalog item details.
struct CatalogOriginTile: View {
    let place: Place?
    let accentColor: Color
    let canEdit: Bool
    let onEdit: () -> Void

    private let coordinate: CLLocationCoordinate2D?
    private let region: MKCoordinateRegion?

    init(
        place: Place?,
        accentColor: Color,
        canEdit: Bool,
        onEdit: @escaping () -> Void
    ) {
        self.place = place
        self.accentColor = accentColor
        self.canEdit = canEdit
        self.onEdit = onEdit

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
            if canEdit {
                Button(action: onEdit) {
                    tileContent
                }
                .buttonStyle(.plain)
            } else {
                tileContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var tileContent: some View {
        if place != nil {
            originContent
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .bottomLeading)
                .catalogSurfaceTile {
                    originMedia
                }
        } else if canEdit {
            CatalogDetailTileCTAContent(
                systemImage: "mappin.slash",
                title: "common.unknown_origin",
                message: "common.ui.tap_to_assign"
            )
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            .catalogSurfaceCTATile(tint: accentColor)
        } else {
            unassignedOriginContent
        }
    }

    private var originContent: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            Label(String(localized: "common.ui.origin"), systemImage: "mappin.and.ellipse")
                .font(CatalogTypography.cardLabel)
                .foregroundStyle(CatalogMediaContrast.onMediaPrimary)

            Spacer(minLength: 0)

            Text(place?.displayName ?? String(localized: "common.unassigned"))
                .font(CatalogTypography.cardSubtitle)
                .foregroundStyle(CatalogMediaContrast.onMediaPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
    }

    private var unassignedOriginContent: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            Label(String(localized: "common.ui.origin"), systemImage: "mappin.slash")
                .font(CatalogTypography.cardLabel)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(String(localized: "common.unassigned"))
                .font(CatalogTypography.cardSubtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .catalogSurfaceTile()
    }

    @ViewBuilder
    private var originMedia: some View {
        if let coordinate, let region {
            Map(initialPosition: .region(region), interactionModes: []) {
                Annotation("", coordinate: coordinate) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title2)
                        .foregroundStyle(accentColor, .red)
                        .shadow(radius: 2, y: 1)
                }
            }
            .mapStyle(.standard(elevation: .flat))
        } else {
            Color.clear
        }
    }
}

/// Displays a reusable storage tile for catalog item details.
struct CatalogStorageTile: View {
    let storagePath: String
    let accentColor: Color
    let isAssigned: Bool
    let canEdit: Bool
    let onEdit: () -> Void

    private var pathParts: [String] {
        storagePath
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        Group {
            if canEdit {
                Button(action: onEdit) {
                    tileContent
                }
                .buttonStyle(.plain)
            } else {
                tileContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var tileContent: some View {
        if isAssigned {
            storageContent
        } else if canEdit {
            CatalogDetailTileCTAContent(
                systemImage: "square.stack.3d.up.slash",
                title: "item.detail.storage.assign.action",
                message: "common.ui.tap_to_assign"
            )
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            .catalogSurfaceCTATile(tint: accentColor)
        } else {
            unassignedStorageContent
        }
    }

    private var storageContent: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            Label(String(localized: "common.storage"), systemImage: "square.stack.3d.up")
                .font(CatalogTypography.cardLabel)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                ForEach(Array(pathParts.enumerated()), id: \.offset) { index, part in
                    Text(part)
                        .font(index == pathParts.count - 1 ? CatalogTypography.cardLabel : CatalogTypography.cardSubtitle)
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

    private var unassignedStorageContent: some View {
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.md) {
            Label(String(localized: "common.storage"), systemImage: "square.stack.3d.up.slash")
                .font(CatalogTypography.cardLabel)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(String(localized: "common.unassigned"))
                .font(CatalogTypography.cardSubtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .catalogSurfaceTile()
    }
}

private struct CatalogDetailTileCTAContent: View {
    let systemImage: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource

    var body: some View {
        VStack(spacing: CatalogMetrics.Spacing.sm) {
            Label(title, systemImage: systemImage)
                .font(CatalogTypography.cardLabel)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Label(message, systemImage: "hand.tap")
                .font(CatalogTypography.cardSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}
