import Foundation

/// Counts the items of a collection across its storage locations.
///
/// Locations are the collection's own copies (`CollectionLocationEntity`), which is what
/// `locationID` on an item points to. Each node counts the items stored directly in it and,
/// as `totalCount`, everything stored in its subtree.
struct CatalogStorageTree {
    struct Node: Identifiable, Hashable {
        let location: Location
        let depth: Int
        let ownCount: Int
        let totalCount: Int
        /// The node itself and all its descendants, for listing the items stored there.
        let subtreeLocationIDs: Set<UUID>

        var id: UUID { location.id }
    }

    /// Active locations in display order, parents before their children.
    let nodes: [Node]
    /// Locations removed from the home that still hold items.
    let archivedNodes: [Node]
    /// Items without a location, or pointing to a location the collection no longer has.
    let unassignedCount: Int

    var isEmpty: Bool {
        nodes.isEmpty && archivedNodes.isEmpty
    }

    var cabinetCount: Int {
        nodes.filter { $0.location.kind == .cabinet }.count
    }

    var shelfCount: Int {
        nodes.filter { $0.location.kind == .shelf }.count
    }

    init(
        locations: [Location],
        archivedLocationIDs: Set<UUID>,
        itemLocationIDs: [UUID?]
    ) {
        let locationsByID = Dictionary(locations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var ownCounts: [UUID: Int] = [:]
        var unassignedCount = 0

        for locationID in itemLocationIDs {
            if let locationID, locationsByID[locationID] != nil {
                ownCounts[locationID, default: 0] += 1
            } else {
                unassignedCount += 1
            }
        }

        let activeLocations = locations.filter { !archivedLocationIDs.contains($0.id) }
        let activeIDs = Set(activeLocations.map(\.id))
        let childrenByParentID = Dictionary(grouping: activeLocations) { location in
            location.parentLocationID.flatMap { activeIDs.contains($0) ? $0 : nil }
        }

        func sortedChildren(of parentID: UUID?) -> [Location] {
            (childrenByParentID[parentID] ?? []).sorted(by: Self.locationLessThan)
        }

        func build(_ location: Location, depth: Int) -> [Node] {
            let descendants = sortedChildren(of: location.id).flatMap { build($0, depth: depth + 1) }
            let directChildIDs = Set(childrenByParentID[location.id, default: []].map(\.id))
            let ownCount = ownCounts[location.id, default: 0]
            let childTotal = descendants
                .filter { directChildIDs.contains($0.id) }
                .reduce(0) { $0 + $1.totalCount }
            let node = Node(
                location: location,
                depth: depth,
                ownCount: ownCount,
                totalCount: ownCount + childTotal,
                subtreeLocationIDs: Set([location.id] + descendants.map(\.id))
            )
            return [node] + descendants
        }

        nodes = sortedChildren(of: nil).flatMap { build($0, depth: 0) }
        archivedNodes = locations
            .filter { archivedLocationIDs.contains($0.id) }
            .sorted(by: Self.locationLessThan)
            .compactMap { location in
                let count = ownCounts[location.id, default: 0]
                guard count > 0 else { return nil }
                return Node(
                    location: location,
                    depth: 0,
                    ownCount: count,
                    totalCount: count,
                    subtreeLocationIDs: [location.id]
                )
            }
        self.unassignedCount = unassignedCount
    }

    /// Orders locations the same way as the home storage map: by level, then by name.
    static func locationLessThan(_ lhs: Location, _ rhs: Location) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind.sortRank < rhs.kind.sortRank
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

extension CatalogSnapshot {
    /// Builds the storage tree of a collection from its own locations and the given items' locations.
    func storageTree(for collectionID: UUID, itemLocationIDs: [UUID?]) -> CatalogStorageTree {
        CatalogStorageTree(
            locations: collectionLocationsByCollectionID[collectionID] ?? [],
            archivedLocationIDs: archivedCollectionLocationIDs,
            itemLocationIDs: itemLocationIDs
        )
    }
}
