import Foundation
import Testing
@testable import Foliora_Bells

struct LocationOrderingTests {
    private let homeID = UUID()

    @Test
    func putsOrderedLocationsFirstAndComparesNumbersInNamesByValue() {
        let shelf10 = location(.shelf, "Shelf 10")
        let shelf2 = location(.shelf, "Shelf 2")
        let ordered = location(.shelf, "Zeta", sortOrder: 0)

        let sorted = [shelf10, shelf2, ordered].sorted(by: LocationOrdering.lessThan)

        #expect(sorted.map(\.name) == ["Zeta", "Shelf 2", "Shelf 10"])
    }

    @Test
    func reordersSiblings() throws {
        let tree = Tree()

        let result = try #require(LocationOrdering.move(
            [tree.lowerShelf.id],
            to: .before(tree.upperShelf.id),
            visibleIDs: tree.visibleIDs,
            collapsedIDs: [],
            in: tree.locations
        ))

        #expect(children(of: tree.cabinet.id, in: result) == ["Lower", "Upper"])
    }

    @Test
    func movesShelfIntoEmptyCabinetAboveTheGap() throws {
        let tree = Tree()

        let result = try #require(LocationOrdering.move(
            [tree.upperShelf.id],
            to: .end,
            visibleIDs: tree.visibleIDs,
            collapsedIDs: [],
            in: tree.locations
        ))

        #expect(children(of: tree.emptyCabinet.id, in: result) == ["Upper"])
        #expect(children(of: tree.cabinet.id, in: result) == ["Lower"])
        #expect(result.first { $0.id == tree.lowerShelf.id }?.sortOrder == 0)
    }

    @Test
    func movesCabinetToTheClosestAncestorThatCanHoldIt() throws {
        let tree = Tree()

        // Dropped between the last shelf of the first room and the second room.
        let result = try #require(LocationOrdering.move(
            [tree.emptyCabinet.id],
            to: .before(tree.secondRoom.id),
            visibleIDs: tree.visibleIDs,
            collapsedIDs: [],
            in: tree.locations
        ))

        #expect(children(of: tree.firstRoom.id, in: result) == ["Cabinet", "Empty"])
        #expect(children(of: tree.secondRoom.id, in: result).isEmpty)
    }

    @Test
    func skipsCollapsedLocationsAsNewParents() throws {
        let tree = Tree()
        let visibleIDs = [tree.firstRoom.id, tree.secondRoom.id, tree.emptyCabinet.id]

        let result = try #require(LocationOrdering.move(
            [tree.emptyCabinet.id],
            to: .before(tree.secondRoom.id),
            visibleIDs: visibleIDs,
            collapsedIDs: [tree.firstRoom.id],
            in: tree.locations
        ))

        #expect(children(of: nil, in: result) == ["First", "Empty", "Second"])
    }

    @Test
    func rejectsDropsTheLevelsDoNotAllow() {
        let tree = Tree()

        let roomUnderCabinet = LocationOrdering.move(
            [tree.secondRoom.id],
            to: .before(tree.upperShelf.id),
            visibleIDs: tree.visibleIDs,
            collapsedIDs: [],
            in: tree.locations
        )
        let cabinetIntoItsOwnShelves = LocationOrdering.move(
            [tree.cabinet.id],
            to: .before(tree.lowerShelf.id),
            visibleIDs: tree.visibleIDs,
            collapsedIDs: [],
            in: tree.locations
        )

        #expect(roomUnderCabinet == nil)
        #expect(cabinetIntoItsOwnShelves == nil)
    }

    /// First room > Cabinet > Upper, Lower; Second room > Empty cabinet.
    private struct Tree {
        let firstRoom: Location
        let cabinet: Location
        let upperShelf: Location
        let lowerShelf: Location
        let secondRoom: Location
        let emptyCabinet: Location

        init() {
            let homeID = UUID()
            func make(_ kind: LocationKind, _ name: String, _ parent: Location?, _ order: Int) -> Location {
                Location(id: UUID(), homeID: homeID, parentLocationID: parent?.id, kind: kind, name: name, notes: "", sortOrder: order)
            }
            firstRoom = make(.room, "First", nil, 0)
            cabinet = make(.cabinet, "Cabinet", firstRoom, 0)
            upperShelf = make(.shelf, "Upper", cabinet, 0)
            lowerShelf = make(.shelf, "Lower", cabinet, 1)
            secondRoom = make(.room, "Second", nil, 1)
            emptyCabinet = make(.cabinet, "Empty", secondRoom, 0)
        }

        var locations: [Location] {
            [firstRoom, cabinet, upperShelf, lowerShelf, secondRoom, emptyCabinet]
        }

        var visibleIDs: [UUID] {
            locations.map(\.id)
        }
    }

    private func children(of parentID: UUID?, in locations: [Location]) -> [String] {
        locations
            .filter { $0.parentLocationID == parentID }
            .sorted(by: LocationOrdering.lessThan)
            .map(\.name)
    }

    private func location(_ kind: LocationKind, _ name: String, sortOrder: Int? = nil) -> Location {
        Location(id: UUID(), homeID: homeID, parentLocationID: nil, kind: kind, name: name, notes: "", sortOrder: sortOrder)
    }
}
