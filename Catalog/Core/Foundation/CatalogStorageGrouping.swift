import Foundation

/// Represents a storage section shared by catalog presentation models.
struct CatalogStorageSection<Element> {
    let floor: String?
    let room: String?
    let elements: [Element]
    let subgroups: [CatalogStorageSubgroup<Element>]

    var pathComponents: [String] {
        [floor, room].compactMap { $0 }
    }
}

/// Represents a cabinet or shelf subgroup inside a catalog storage section.
struct CatalogStorageSubgroup<Element> {
    let kind: LocationKind
    let title: String
    let elements: [Element]
}

/// Provides shared storage sorting and grouping behavior for catalog items.
enum CatalogStorageGrouping {
    static func sorted<Element>(
        _ elements: [Element],
        storagePath: (Element) -> StoragePath?,
        title: (Element) -> String
    ) -> [Element] {
        elements.sorted { lhs, rhs in
            lessThan(
                lhs,
                rhs,
                storagePath: storagePath,
                title: title
            )
        }
    }

    static func sections<Element>(
        fromSorted elements: [Element],
        storagePath: (Element) -> StoragePath?
    ) -> [CatalogStorageSection<Element>] {
        let grouped = Dictionary(grouping: elements) { element in
            let path = storagePath(element)
            return SectionKey(
                floor: normalized(path?.floor),
                room: normalized(path?.room)
            )
        }
        let orderedKeys = grouped.keys.sorted { lhs, rhs in
            let floorComparison = compare(lhs.floor, rhs.floor)
            if floorComparison != .orderedSame {
                return floorComparison == .orderedAscending
            }

            return compare(lhs.room, rhs.room) == .orderedAscending
        }

        return orderedKeys.map { key in
            let sectionElements = grouped[key, default: []]
            let directElements = sectionElements.filter {
                subgroupKey(for: $0, storagePath: storagePath) == nil
            }
            let groupedSubgroups = Dictionary(
                grouping: sectionElements.compactMap { element in
                    subgroupKey(for: element, storagePath: storagePath).map { ($0, element) }
                },
                by: { $0.0 }
            )
            let subgroups = groupedSubgroups
                .map { subgroupKey, values in
                    CatalogStorageSubgroup(
                        kind: subgroupKey.kind,
                        title: subgroupKey.title,
                        elements: values.map { $0.1 }
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.kind != rhs.kind {
                        return lhs.kind == .cabinet
                    }

                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }

            return CatalogStorageSection(
                floor: key.floor,
                room: key.room,
                elements: directElements,
                subgroups: subgroups
            )
        }
    }

    private struct SectionKey: Hashable {
        let floor: String?
        let room: String?
    }

    private struct SubgroupKey: Hashable {
        let kind: LocationKind
        let title: String
    }

    private static func subgroupKey<Element>(
        for element: Element,
        storagePath: (Element) -> StoragePath?
    ) -> SubgroupKey? {
        let path = storagePath(element)

        if let cabinet = normalized(path?.cabinet) {
            return SubgroupKey(kind: .cabinet, title: cabinet)
        }

        if let shelf = normalized(path?.shelf) {
            return SubgroupKey(kind: .shelf, title: shelf)
        }

        return nil
    }

    private static func lessThan<Element>(
        _ lhs: Element,
        _ rhs: Element,
        storagePath: (Element) -> StoragePath?,
        title: (Element) -> String
    ) -> Bool {
        let lhsPath = storagePath(lhs)
        let rhsPath = storagePath(rhs)
        let comparisons = [
            compare(normalized(lhsPath?.floor), normalized(rhsPath?.floor)),
            compare(normalized(lhsPath?.room), normalized(rhsPath?.room)),
            compare(normalized(lhsPath?.cabinet), normalized(rhsPath?.cabinet)),
            compare(normalized(lhsPath?.shelf), normalized(rhsPath?.shelf)),
            title(lhs).localizedCaseInsensitiveCompare(title(rhs))
        ]

        return comparisons.first { $0 != .orderedSame } == .orderedAscending
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func compare(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs.localizedCaseInsensitiveCompare(rhs)
        case (.some, .none):
            return .orderedAscending
        case (.none, .some):
            return .orderedDescending
        case (.none, .none):
            return .orderedSame
        }
    }
}
