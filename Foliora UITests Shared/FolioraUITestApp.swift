import XCTest

/// Drives either app in its `-ui-testing` launch mode.
///
/// The app starts on an in-memory store with one collection, which it opens directly:
/// "Top <Noun> A" (tag "souvenir"), "Top <Noun> B" and "Top <Noun> C" on Top Shelf,
/// "Bottom <Noun>" on Bottom Shelf and "Loose <Noun>" without a location.
/// See `PreviewData.saveUITestingCore` in the app.
@MainActor
struct FolioraUITestApp {
    let app: XCUIApplication
    /// "Bell" or "Book", as used in the fixed item titles.
    let noun: String

    static func launch(noun: String) -> FolioraUITestApp {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ui-testing",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        return FolioraUITestApp(app: app, noun: noun)
    }

    // MARK: - Fixed data

    var topShelfTitles: [String] { ["Top \(noun) A", "Top \(noun) B", "Top \(noun) C"] }
    var bottomShelfTitle: String { "Bottom \(noun)" }

    // MARK: - Elements

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    func card(_ title: String) -> XCUIElement {
        element("card.\(title)")
    }

    /// The context-menu Move item, present only on manageable cards.
    /// Not "Select": the storage screen also has a Select toolbar button.
    var contextMenuMoveItem: XCUIElement {
        app.buttons["Move to..."].firstMatch
    }

    // MARK: - Navigation

    /// Opens the dashboard Storage card, then the named location in the storage tree.
    func openStorageLocation(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let storageCard = element("dashboard.storage")
        XCTAssertTrue(storageCard.waitForExistence(timeout: 15), "Storage card not found", file: file, line: line)
        scrollStripUntilHittable(storageCard)
        storageCard.tap()

        let row = app.staticTexts[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Location \(name) not found", file: file, line: line)
        row.tap()
    }

    /// Switches to the Search tab and types `query` into its field.
    func search(_ query: String, file: StaticString = #filePath, line: UInt = #line) {
        let searchTab = app.tabBars.buttons["Search"].firstMatch
        if searchTab.waitForExistence(timeout: 3) {
            searchTab.tap()
        } else {
            app.buttons["Search"].firstMatch.tap()
        }

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Search field not found", file: file, line: line)
        field.tap()
        if !query.isEmpty {
            field.typeText(query)
        }
    }

    /// Replaces the text in the Search field.
    func replaceSearchText(_ oldQuery: String, with query: String) {
        let field = app.searchFields.firstMatch
        let delete = String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldQuery.count)
        field.typeText(delete + query)
    }

    // MARK: - Actions

    func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "\(identifier) not found", file: file, line: line)
        target.tap()
    }

    /// Long-presses a card and reports whether its context menu appeared.
    func longPressShowsContextMenu(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let target = card(title)
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Card \(title) not found", file: file, line: line)
        target.press(forDuration: 1.2)
        return contextMenuMoveItem.waitForExistence(timeout: 2)
    }

    /// Selects every item on the current storage screen and adds `tag` through batch edit.
    func addTagToAllItemsOnScreen(_ tag: String, file: StaticString = #filePath, line: UInt = #line) {
        tap("selection.select", file: file, line: line)
        tap("selection.selectAll", file: file, line: line)
        tap("selection.batchEdit", file: file, line: line)

        let input = element("tags.input")
        // The tag section is last in the batch-edit form and may start below the fold.
        for _ in 0..<3 where !input.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(input.exists, "Tag field not found", file: file, line: line)
        input.tap()
        input.typeText(tag)
        tap("tags.add", file: file, line: line)
        tap("batchEdit.save", file: file, line: line)
    }

    // MARK: - Helpers

    /// The dashboard card strip scrolls horizontally; swipe it at the element's height.
    private func scrollStripUntilHittable(_ element: XCUIElement) {
        for _ in 0..<6 where !element.isHittable {
            let y = element.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0))
                .withOffset(CGVector(dx: 0, dy: y))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0))
                .withOffset(CGVector(dx: 0, dy: y))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }
}
