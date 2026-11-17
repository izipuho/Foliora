import XCTest

/// Storage-screen scenarios shared by both apps; each app's test class calls them with its noun.
@MainActor
enum StorageSelectionUITestCases {
    /// Shelf → Select → Select All → Edit → add tag: every item on the shelf gets the tag,
    /// existing tags stay, items elsewhere are untouched.
    static func batchAddTagToShelf(noun: String) {
        let ui = FolioraUITestApp.launch(noun: noun)
        let tag = "shelftag"

        ui.openStorageLocation("Top Shelf")
        for title in ui.topShelfTitles {
            XCTAssertTrue(ui.card(title).waitForExistence(timeout: 5), "\(title) is not on Top Shelf")
        }
        XCTAssertFalse(ui.card(ui.bottomShelfTitle).exists, "Top Shelf shows an item from another shelf")

        ui.addTagToAllItemsOnScreen(tag)

        ui.search(tag)
        for title in ui.topShelfTitles {
            XCTAssertTrue(ui.card(title).waitForExistence(timeout: 5), "\(title) did not get the tag")
        }
        XCTAssertFalse(ui.card(ui.bottomShelfTitle).exists, "An item from another shelf got the tag")

        ui.replaceSearchText(tag, with: "souvenir")
        XCTAssertTrue(ui.card(ui.topShelfTitles[0]).waitForExistence(timeout: 5), "The existing tag was lost")
    }

    /// Cards on the storage screen offer the management context menu.
    static func storageCardsHaveContextMenu(noun: String) {
        let ui = FolioraUITestApp.launch(noun: noun)

        ui.openStorageLocation("Top Shelf")

        XCTAssertTrue(ui.longPressShowsContextMenu(ui.topShelfTitles[0]), "No context menu on the storage screen")
    }

    /// Search results stay read-only: no context menu, no Select button.
    static func searchCardsHaveNoContextMenu(noun: String) {
        let ui = FolioraUITestApp.launch(noun: noun)

        ui.search(ui.topShelfTitles[0])

        XCTAssertFalse(ui.longPressShowsContextMenu(ui.topShelfTitles[0]), "Search results show a context menu")
        XCTAssertFalse(ui.element("selection.select").exists, "Search shows a Select button")
    }
}
