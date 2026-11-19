import Foundation

/// Display order of storage locations and the rules for moving them by drag and drop.
///
/// Siblings follow the person's own order (`Location.sortOrder`, stored per user) first.
/// Locations that were never reordered come after them, by level and then by name, with
/// numbers compared by value ("Shelf 2" before "Shelf 10").
nonisolated enum LocationOrdering {
    /// `UserSortOrderEntity` scope for the person's order of locations.
    static let userSortScope = "Location"

    /// Orders sibling locations for display.
    static func lessThan(_ lhs: Location, _ rhs: Location) -> Bool {
        switch (lhs.sortOrder, rhs.sortOrder) {
        case let (lhsOrder?, rhsOrder?) where lhsOrder != rhsOrder:
            return lhsOrder < rhsOrder
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            break
        }

        if lhs.kind != rhs.kind {
            return lhs.kind.sortRank < rhs.kind.sortRank
        }

        let nameComparison = lhs.name.localizedStandardCompare(rhs.name)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Where dragged locations land in the visible tree.
    enum DropPosition: Equatable {
        /// Ahead of the visible row with this location ID.
        case before(UUID)
        /// After the last visible row.
        case end
    }

    /// Moves locations to a drop position in the visible tree, changing their parent when needed.
    ///
    /// The drop lands between two visible rows. The moved location becomes a sibling of the row
    /// below the gap when its level allows that. Otherwise it goes to the end of the row above
    /// the gap, or of the closest ancestor of that row, that can hold it. Collapsed locations
    /// don't take new children. Every sibling group that changes gets a full, gap-free order.
    ///
    /// - Parameters:
    ///   - movedIDs: The dragged locations.
    ///   - position: The drop position.
    ///   - visibleIDs: The rows shown in the tree, parents before their children.
    ///   - collapsedIDs: Locations whose children are hidden.
    ///   - locations: All locations of the home.
    /// - Returns: The updated locations, or `nil` when the drop isn't valid.
    static func move(
        _ movedIDs: [UUID],
        to position: DropPosition,
        visibleIDs: [UUID],
        collapsedIDs: Set<UUID>,
        in locations: [Location]
    ) -> [Location]? {
        let locationsByID = Dictionary(locations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let moved = movedIDs.compactMap { locationsByID[$0] }
        guard !moved.isEmpty else { return nil }

        // A moved location carries its subtree, so none of it can be a drop anchor or a parent.
        var excludedIDs = Set(moved.map(\.id))
        for location in moved {
            excludedIDs.formUnion(descendantIDs(of: location.id, in: locations))
        }

        let anchorID: UUID?
        switch position {
        case let .before(id):
            guard !excludedIDs.contains(id), locationsByID[id] != nil else { return nil }
            anchorID = id
        case .end:
            anchorID = nil
        }

        let remainingVisibleIDs = visibleIDs.filter { !excludedIDs.contains($0) }
        let anchorIndex = anchorID.flatMap { remainingVisibleIDs.firstIndex(of: $0) } ?? remainingVisibleIDs.endIndex
        let rowAboveID = anchorIndex > remainingVisibleIDs.startIndex
            ? remainingVisibleIDs[remainingVisibleIDs.index(before: anchorIndex)]
            : nil
        // A dangling parent reference is shown at the top level.
        let anchorParentID = anchorID
            .flatMap { locationsByID[$0]?.parentLocationID }
            .flatMap { locationsByID[$0] != nil ? $0 : nil }

        func canHold(_ parentID: UUID?) -> Bool {
            guard let parentID else {
                return true
            }
            guard let parent = locationsByID[parentID], !excludedIDs.contains(parentID) else {
                return false
            }
            return moved.allSatisfy { $0.kind.canBeChild(of: parent.kind) }
        }

        // Candidate parents, deepest first: the row above the gap and its ancestors, down to the
        // parent of the row below the gap. That parent is the last candidate and places the
        // moved locations right before the anchor; the others take them at the end.
        var candidates: [UUID?] = []
        var currentID = rowAboveID
        while let id = currentID, id != anchorParentID {
            if !(collapsedIDs.contains(id) && hasChildren(id, in: locations)) {
                candidates.append(id)
            }
            currentID = locationsByID[id]?.parentLocationID
        }
        candidates.append(anchorParentID)

        guard let targetParentID = candidates.first(where: canHold) else { return nil }
        let insertsBeforeAnchor = targetParentID == anchorParentID && anchorID != nil

        var result = locations
        let movedSet = Set(moved.map(\.id))
        let oldParentIDs = Set(moved.map(\.parentLocationID))

        for index in result.indices where movedSet.contains(result[index].id) {
            result[index].parentLocationID = targetParentID
        }

        var siblings = sortedChildren(of: targetParentID, in: result).filter { !movedSet.contains($0.id) }
        let insertionIndex = insertsBeforeAnchor
            ? siblings.firstIndex(where: { $0.id == anchorID }) ?? siblings.endIndex
            : siblings.endIndex
        let movedInOrder = movedIDs.compactMap { id in result.first(where: { $0.id == id }) }
        siblings.insert(contentsOf: movedInOrder, at: insertionIndex)
        renumber(siblings.map(\.id), in: &result)

        for parentID in oldParentIDs where parentID != targetParentID {
            renumber(sortedChildren(of: parentID, in: result).map(\.id), in: &result)
        }

        return result
    }

    private static func renumber(_ orderedIDs: [UUID], in locations: inout [Location]) {
        let orderByID = Dictionary(orderedIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        for index in locations.indices {
            if let order = orderByID[locations[index].id] {
                locations[index].sortOrder = order
            }
        }
    }

    private static func sortedChildren(of parentID: UUID?, in locations: [Location]) -> [Location] {
        let ids = Set(locations.map(\.id))
        return locations
            .filter { location in
                // A dangling parent reference is shown at the top level.
                let effectiveParentID = location.parentLocationID.flatMap { ids.contains($0) ? $0 : nil }
                return effectiveParentID == parentID
            }
            .sorted(by: lessThan)
    }

    private static func hasChildren(_ id: UUID, in locations: [Location]) -> Bool {
        locations.contains { $0.parentLocationID == id }
    }

    private static func descendantIDs(of locationID: UUID, in locations: [Location]) -> Set<UUID> {
        var result: Set<UUID> = []
        var pending = [locationID]

        while let parentID = pending.popLast() {
            for location in locations where location.parentLocationID == parentID {
                if result.insert(location.id).inserted {
                    pending.append(location.id)
                }
            }
        }

        return result
    }
}

extension LocationKind {
    /// Level order used when the person hasn't ordered locations: floors first, shelves last.
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
