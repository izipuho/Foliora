import XCTest

final class BookStorageUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBatchAddTagToShelf() {
        StorageSelectionUITestCases.batchAddTagToShelf(noun: "Book")
    }

    @MainActor
    func testStorageCardsHaveContextMenu() {
        StorageSelectionUITestCases.storageCardsHaveContextMenu(noun: "Book")
    }

    @MainActor
    func testSearchCardsHaveNoContextMenu() {
        StorageSelectionUITestCases.searchCardsHaveNoContextMenu(noun: "Book")
    }
}
