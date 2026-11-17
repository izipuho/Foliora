import XCTest

final class BellStorageUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBatchAddTagToShelf() {
        StorageSelectionUITestCases.batchAddTagToShelf(noun: "Bell")
    }

    @MainActor
    func testStorageCardsHaveContextMenu() {
        StorageSelectionUITestCases.storageCardsHaveContextMenu(noun: "Bell")
    }

    @MainActor
    func testSearchCardsHaveNoContextMenu() {
        StorageSelectionUITestCases.searchCardsHaveNoContextMenu(noun: "Bell")
    }
}
