import Foundation

/// Represents a group of catalog values sharing the same optional year.
struct CatalogYearGroup<Element> {
    let year: Int?
    let elements: [Element]
}

/// Provides shared grouping behavior for optional catalog year values.
enum CatalogYearGrouping {
    static func descending<Element>(
        _ elements: [Element],
        year: (Element) -> Int?,
        sortedBy areInIncreasingOrder: (Element, Element) -> Bool
    ) -> [CatalogYearGroup<Element>] {
        let grouped = Dictionary(grouping: elements, by: year)
        let orderedYears = grouped.keys.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case let (lhs?, rhs?):
                return lhs > rhs
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return false
            }
        }

        return orderedYears.map { year in
            CatalogYearGroup(
                year: year,
                elements: grouped[year, default: []].sorted(by: areInIncreasingOrder)
            )
        }
    }
}
