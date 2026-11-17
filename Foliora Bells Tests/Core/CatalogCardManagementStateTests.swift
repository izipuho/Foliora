import Foundation
import Testing
@testable import Foliora_Bells

@MainActor
struct CatalogCardManagementStateTests {
    private struct TestItem: Identifiable {
        let id = UUID()
    }

    private let items = [TestItem(), TestItem(), TestItem()]

    @Test
    func enterSelectionWithoutItemStartsEmpty() {
        var state = CatalogCardManagementState<TestItem>()

        state.enterSelection()

        #expect(state.isSelectionModeEnabled)
        #expect(state.selectedIDs.isEmpty)
        #expect(!state.areAllSelected(in: items))
    }

    @Test
    func enterSelectionWithItemSelectsIt() {
        var state = CatalogCardManagementState<TestItem>()

        state.enterSelection(with: items[1])

        #expect(state.isSelectionModeEnabled)
        #expect(state.selectedIDs == [items[1].id])
    }

    @Test
    func toggleSelectionAddsAndRemoves() {
        var state = CatalogCardManagementState<TestItem>()
        state.enterSelection()

        state.toggleSelection(of: items[0])
        #expect(state.selectedIDs == [items[0].id])

        state.toggleSelection(of: items[0])
        #expect(state.selectedIDs.isEmpty)
        #expect(state.isSelectionModeEnabled)
    }

    @Test
    func selectAllSelectsEveryVisibleItem() {
        var state = CatalogCardManagementState<TestItem>()
        state.enterSelection(with: items[0])

        state.selectAll(items)

        #expect(state.selectedIDs == Set(items.map(\.id)))
        #expect(state.areAllSelected(in: items))
        #expect(state.selectedItems(in: items).map(\.id) == items.map(\.id))
    }

    @Test
    func deselectAllKeepsSelectionModeOn() {
        var state = CatalogCardManagementState<TestItem>()
        state.enterSelection()
        state.selectAll(items)

        state.deselectAll(items)

        #expect(state.selectedIDs.isEmpty)
        #expect(state.isSelectionModeEnabled)
        #expect(!state.areAllSelected(in: items))
    }

    @Test
    func selectAllOnlyTouchesGivenItems() {
        let other = TestItem()
        var state = CatalogCardManagementState<TestItem>()
        state.enterSelection(with: other)

        state.selectAll(items)
        state.deselectAll(items)

        #expect(state.selectedIDs == [other.id])
    }

    @Test
    func areAllSelectedIsFalseForNoItems() {
        var state = CatalogCardManagementState<TestItem>()
        state.enterSelection()

        #expect(!state.areAllSelected(in: []))
    }

    @Test
    func pruneSelectionDropsHiddenItemsAndExitsWhenEmpty() {
        var state = CatalogCardManagementState<TestItem>()
        state.enterSelection()
        state.selectAll(items)

        state.pruneSelection(to: [items[0]])
        #expect(state.selectedIDs == [items[0].id])
        #expect(state.isSelectionModeEnabled)

        state.pruneSelection(to: [])
        #expect(state.selectedIDs.isEmpty)
        #expect(!state.isSelectionModeEnabled)
    }

    @Test
    func itemsForActionUsesSelectionOnlyInSelectionMode() {
        var state = CatalogCardManagementState<TestItem>()

        #expect(state.itemsForAction(triggeredBy: items[2], visibleItems: items).map(\.id) == [items[2].id])

        state.enterSelection()
        state.selectAll([items[0], items[1]])

        #expect(state.itemsForAction(triggeredBy: items[2], visibleItems: items).map(\.id) == [items[0].id, items[1].id])
    }

    @Test
    func completeActionExitsSelection() {
        var state = CatalogCardManagementState<TestItem>()
        state.enterSelection()
        state.selectAll(items)
        state.beginBatchEdit()

        state.completeAction()

        #expect(!state.isSelectionModeEnabled)
        #expect(state.selectedIDs.isEmpty)
        #expect(!state.isPresentingBatchEdit)
    }
}
