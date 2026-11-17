import Foundation
import Testing
@testable import Foliora_Bells

struct CatalogStorageTreeTests {
    private let homeID = UUID()

    @Test
    func countsItemsOnEachLocationAndSumsThemUpTheTree() {
        let room = location(.room, "Room")
        let cabinet = location(.cabinet, "Cabinet", parent: room)
        let upperShelf = location(.shelf, "Upper", parent: cabinet)
        let lowerShelf = location(.shelf, "Lower", parent: cabinet)

        let tree = CatalogStorageTree(
            locations: [lowerShelf, room, upperShelf, cabinet],
            archivedLocationIDs: [],
            itemLocationIDs: [upperShelf.id, upperShelf.id, lowerShelf.id, cabinet.id, room.id]
        )

        #expect(tree.nodes.map(\.location.name) == ["Room", "Cabinet", "Lower", "Upper"])
        #expect(tree.nodes.map(\.depth) == [0, 1, 2, 2])
        #expect(tree.nodes.map(\.ownCount) == [1, 1, 1, 2])
        #expect(tree.nodes.map(\.totalCount) == [5, 4, 1, 2])
        #expect(tree.nodes[1].subtreeLocationIDs == [cabinet.id, upperShelf.id, lowerShelf.id])
        #expect(tree.cabinetCount == 1)
        #expect(tree.shelfCount == 2)
        #expect(tree.unassignedCount == 0)
    }

    @Test
    func countsItemsWithoutAKnownLocationAsUnassigned() {
        let shelf = location(.shelf, "Shelf")

        let tree = CatalogStorageTree(
            locations: [shelf],
            archivedLocationIDs: [],
            itemLocationIDs: [nil, UUID(), shelf.id]
        )

        #expect(tree.nodes.first?.totalCount == 1)
        #expect(tree.unassignedCount == 2)
    }

    @Test
    func keepsArchivedLocationsWithItemsOutOfTheActiveTree() {
        let room = location(.room, "Room")
        let archivedShelf = location(.shelf, "Old Shelf")
        let archivedEmptyShelf = location(.shelf, "Empty Old Shelf")

        let tree = CatalogStorageTree(
            locations: [room, archivedShelf, archivedEmptyShelf],
            archivedLocationIDs: [archivedShelf.id, archivedEmptyShelf.id],
            itemLocationIDs: [archivedShelf.id, room.id]
        )

        #expect(tree.nodes.map(\.id) == [room.id])
        #expect(tree.archivedNodes.map(\.id) == [archivedShelf.id])
        #expect(tree.archivedNodes.first?.totalCount == 1)
        #expect(tree.unassignedCount == 0)
        #expect(!tree.isEmpty)
    }

    @Test
    func isEmptyWithoutLocations() {
        let tree = CatalogStorageTree(
            locations: [],
            archivedLocationIDs: [],
            itemLocationIDs: [nil, nil]
        )

        #expect(tree.isEmpty)
        #expect(tree.unassignedCount == 2)
    }

    private func location(_ kind: LocationKind, _ name: String, parent: Location? = nil) -> Location {
        Location(
            id: UUID(),
            homeID: homeID,
            parentLocationID: parent?.id,
            kind: kind,
            name: name,
            notes: "",
            sortOrder: nil
        )
    }
}
