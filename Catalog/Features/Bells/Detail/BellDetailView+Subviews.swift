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
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
            ZStack(alignment: .bottomLeading) {
                if let coordinate, let region {
                    Map(initialPosition: .region(region), interactionModes: []) {
                        Marker("", coordinate: coordinate)
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .clipShape(RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.tile, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.tile, style: .continuous)
                            .fill(CatalogSemanticColors.groupedSurfaceElevated)
                        Image(systemName: "mappin.slash")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                LinearGradient(
                    colors: [
                        CatalogMediaContrast.mapScrimTop,
                        CatalogMediaContrast.mapScrimMiddle,
                        CatalogMediaContrast.mapScrimBottom
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.tile, style: .continuous))

                VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                    Label(String(localized: "common.field.origin"), systemImage: "mappin.and.ellipse")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(place?.displayName ?? String(localized: "common.unassigned"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(CatalogMetrics.Spacing.md)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .bottomLeading)
            .overlay(
                RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.tile, style: .continuous)
                    .stroke(accentColor.opacity(0.22), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
                ForEach(Array(pathParts.enumerated()), id: \.offset) { index, part in
                    HStack(spacing: CatalogMetrics.Spacing.sm) {
                        Circle()
                            .fill(index == pathParts.count - 1 ? accentColor.opacity(0.80) : CatalogSemanticColors.tertiaryLabel)
                            .frame(width: 7, height: 7)

                        Text(part)
                            .font(index == pathParts.count - 1 ? .subheadline.weight(.semibold) : .subheadline)
                            .foregroundStyle(index == pathParts.count - 1 ? .primary : .secondary)

                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(CatalogMetrics.Spacing.md)
            .background(CatalogSemanticColors.groupedSurfaceElevated, in: RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.tile, style: .continuous)
                    .stroke(accentColor.opacity(0.22), lineWidth: 1)
            )
        }
    }

    private var placeholderTileContent: some View {
        VStack(spacing: CatalogMetrics.Spacing.sm) {
            Spacer(minLength: 0)

            Image(systemName: "square.stack.3d.up.slash")
                .font(.title2.weight(.semibold))
                .foregroundStyle(accentColor)

            Text(String(localized: "bell.detail.storage.assign.action"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(accentColor)
                .multilineTextAlignment(.center)

            Text(String(localized: "bell.detail.storage.placeholder"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
        .padding(CatalogMetrics.Spacing.md)
        .background(accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.tile, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                .foregroundStyle(accentColor.opacity(0.38))
        )
    }
}
