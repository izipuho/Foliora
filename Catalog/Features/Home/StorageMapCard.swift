import DesignSystem
import SwiftUI

struct StorageMapCard: View {
    let locations: [Location]

    private var rootLocations: [Location] {
        locations
            .filter { $0.parentLocationID == nil }
            .sorted(by: locationSort)
    }

    private var floorCount: Int {
        locations.filter { $0.kind == .floor }.count
    }

    private var roomCount: Int {
        locations.filter { $0.kind == .room }.count
    }

    private var cabinetCount: Int {
        let cabinets = locations.filter { $0.kind == .cabinet }.count
        let standaloneShelves = locations.filter { location in
            location.kind == .shelf && !hasAncestor(ofKind: .cabinet, for: location)
        }.count
        return cabinets + standaloneShelves
    }

    private var flattenedLocations: [StorageMapNode] {
        rootLocations.flatMap { flatten(location: $0, depth: 0) }
    }

    private var storageSummaryText: String {
        var parts: [String] = []

        if floorCount > 0 {
            parts.append(localizedStorageCount("home.storage.count.floors", floorCount))
        }

        parts.append(localizedStorageCount("home.storage.count.rooms", roomCount))
        parts.append(localizedStorageCount("home.storage.count.cabinets", cabinetCount))

        return parts.joined(separator: " · ")
    }

    var body: some View {
        if locations.isEmpty {
            ContentUnavailableView(
                String(localized: "home.location.empty.title"),
                systemImage: "square.stack.3d.up.slash",
                description: Text(String(localized: "home.location.empty.description"))
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, CatalogSpacing.section)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text(storageSummaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(flattenedLocations) { node in
                    locationRow(location: node.location, depth: node.depth)
                }
            }
        }
    }

    private func children(of location: Location) -> [Location] {
        locations
            .filter { $0.parentLocationID == location.id }
            .sorted(by: locationSort)
    }

    private func hasAncestor(ofKind kind: LocationKind, for location: Location) -> Bool {
        var currentParentID = location.parentLocationID

        while let parentID = currentParentID,
              let parent = locations.first(where: { $0.id == parentID }) {
            if parent.kind == kind {
                return true
            }

            currentParentID = parent.parentLocationID
        }

        return false
    }

    private func flatten(location: Location, depth: Int) -> [StorageMapNode] {
        [StorageMapNode(location: location, depth: depth)] +
        visibleChildren(of: location).flatMap { flatten(location: $0, depth: depth + 1) }
    }

    private func visibleChildren(of location: Location) -> [Location] {
        children(of: location).filter { child in
            !(location.kind == .cabinet && child.kind == .shelf)
        }
    }

    private func shelfCount(in cabinet: Location) -> Int {
        guard cabinet.kind == .cabinet else { return 0 }
        return children(of: cabinet).filter { $0.kind == .shelf }.count
    }

    private func localizedStorageCount(_ key: String, _ count: Int) -> String {
        String.localizedStringWithFormat(
            NSLocalizedString(key, comment: "Home storage summary count"),
            count
        )
    }

    private var locationSort: (Location, Location) -> Bool {
        { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind.sortRank < rhs.kind.sortRank
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func locationRow(location: Location, depth: Int) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(kindColor(location.kind))
                .frame(width: 8, height: 8)

            Text(location.name)
                .font(.subheadline.weight(.semibold))

            if let shelfSummary = shelfSummaryText(for: location) {
                Text(shelfSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.leading, CGFloat(depth) * 18)
    }

    private func shelfSummaryText(for location: Location) -> String? {
        guard location.kind == .cabinet else { return nil }
        let shelfCount = shelfCount(in: location)
        guard shelfCount > 0 else { return nil }

        let localizedCount = String.localizedStringWithFormat(
            NSLocalizedString("home.storage.count.shelves", comment: "Shelf count under cabinet"),
            shelfCount
        )
        return "(\(localizedCount))"
    }

    private func kindColor(_ kind: LocationKind) -> Color {
        switch kind {
        case .floor:
            return Color(red: 0.20, green: 0.42, blue: 0.34)
        case .room:
            return Color(red: 0.36, green: 0.52, blue: 0.24)
        case .cabinet:
            return Color(red: 0.58, green: 0.44, blue: 0.18)
        case .shelf:
            return Color(red: 0.51, green: 0.31, blue: 0.14)
        }
    }
}

private struct StorageMapNode: Identifiable {
    let location: Location
    let depth: Int

    var id: UUID { location.id }
}

extension LocationKind {
    var sortRank: Int {
        switch self {
        case .floor:
            return 0
        case .room:
            return 1
        case .cabinet:
            return 2
        case .shelf:
            return 3
        }
    }
}
