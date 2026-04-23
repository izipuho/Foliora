import Foundation
import Observation

private let unknownTitle = String(localized: "common.unknown")

private struct StorageGroupKey: Hashable {
    let floor: String
    let room: String
}

private extension BellEntity {

    var storageFloor: String {
        storageComponent(.floor)
    }

    var storageRoom: String {
        storageComponent(.room)
    }

    var storageCabinet: String {
        storageComponent(.cabinet)
    }

    var storageShelf: String {
        storageComponent(.shelf)
    }

    var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func storageComponent(_ kind: LocationKind) -> String {
        var current = location

        while let location = current {
            if location.kind == kind {
                return location.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            current = location.parent
        }

        return ""
    }
}

@MainActor
@Observable
final class BellCatalogViewModel {
    var bellRecords: [BellEntity]
    var selectedCondition: ItemCondition?
    var orderMode: BellOrderMode
    var summaryFilter: BellSummaryFilter?
    var searchText: String

    init(
        bellRecords: [BellEntity],
        orderMode: BellOrderMode,
        summaryFilter: BellSummaryFilter?,
        searchText: String,
        selectedCondition: ItemCondition? = nil
    ) {
        self.bellRecords = bellRecords
        self.orderMode = orderMode
        self.summaryFilter = summaryFilter
        self.searchText = searchText
        self.selectedCondition = selectedCondition
    }

    var filteredBells: [BellEntity] {
        bellRecords.filter { bell in
            matches(bell: bell, summaryFilter: summaryFilter)
            && (selectedCondition == nil || bell.condition == selectedCondition)
            && (
                searchText.isEmpty
                || bell.title.localizedCaseInsensitiveContains(searchText)
                || bell.countryName.localizedCaseInsensitiveContains(searchText)
                || bell.cityName.localizedCaseInsensitiveContains(searchText)
                || bell.tagValues.contains { $0.localizedCaseInsensitiveContains(searchText) }
            )
        }
    }

    var countryCount: Int {
        Set(bellRecords.map(\.countryName).filter { !$0.isEmpty }).count
    }

    var materialCount: Int {
        Set(bellRecords.map(\.materialDisplayName)).count
    }

    var cityCount: Int {
        Set(bellRecords.map(\.cityName).filter { !$0.isEmpty }).count
    }

    var bellsWithOriginCount: Int {
        bellRecords.filter { $0.originPlace != nil }.count
    }

    var bellsWithAcquiredYearCount: Int {
        bellRecords.filter { $0.acquiredYear != nil }.count
    }

    var bellsWithStorageCount: Int {
        bellRecords.filter { $0.location != nil }.count
    }

    var bellsWithNotesCount: Int {
        bellRecords.filter(\.hasNotes).count
    }

    var bellsWithTagsCount: Int {
        bellRecords.filter { !$0.tagValues.isEmpty }.count
    }

    private func topValues(
        from values: [String],
        skipEmpty: Bool = false
    ) -> [(String, Int)] {
        Dictionary(grouping: skipEmpty ? values.filter { !$0.isEmpty } : values, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
                }

                return lhs.1 > rhs.1
            }
    }

    var topCountries: [(String, Int)] {
        topValues(from: bellRecords.map(\.countryName), skipEmpty: true)
    }

    var topMaterials: [(String, Int)] {
        topValues(from: bellRecords.map(\.materialDisplayName))
    }

    var topTags: [(String, Int)] {
        topValues(from: bellRecords.flatMap(\.tagValues))
    }

    var usesGroupedSections: Bool {
        [.geography, .acquisitionYear, .storage].contains(orderMode)
    }

    func updateContext(
        orderMode: BellOrderMode,
        summaryFilter: BellSummaryFilter?,
        searchText: String
    ) {
        self.orderMode = orderMode
        self.summaryFilter = summaryFilter
        self.searchText = searchText
    }

    func matches(bell: BellEntity, summaryFilter: BellSummaryFilter?) -> Bool {
        switch summaryFilter {
        case nil, .all:
            return true
        case .withOrigin:
            return bell.originPlace != nil
        case .missingOrigin:
            return bell.originPlace == nil
        case .withYear:
            return bell.acquiredYear != nil
        case .missingYear:
            return bell.acquiredYear == nil
        case .withCity:
            return !bell.cityName.isEmpty
        case .withStorage:
            return bell.location != nil
        case .missingStorage:
            return bell.location == nil
        case .withNotes:
            return bell.hasNotes
        case .missingNotes:
            return !bell.hasNotes
        case .withTags:
            return !bell.tagValues.isEmpty
        case .missingTags:
            return bell.tagValues.isEmpty
        case .withMaterial:
            return !bell.materialDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .country(let country):
            return bell.countryName.localizedCaseInsensitiveCompare(country) == .orderedSame
        case .material(let material):
            return bell.materialDisplayName.localizedCaseInsensitiveCompare(material) == .orderedSame
        case .tag(let tag):
            return bell.tagValues.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame })
        }
    }

    func sorted(_ bellRecords: [BellEntity]) -> [BellEntity] {
        bellRecords.sorted(using: sortComparators)
    }

    func groupedSections(from bellRecords: [BellEntity]) -> [BellGroupedSection] {
        switch orderMode {
        case .title, .newestFirst, .oldestFirst:
            return []
        case .geography:
            let grouped = Dictionary(grouping: bellRecords, by: { geographyDisplayValue($0.countryName, unknown: unknownTitle) })
            let orderedCountries = grouped.keys.sorted {
                compareDisplayValues($0, $1, unknown: unknownTitle) == .orderedAscending
            }

            return orderedCountries.map { country in
                BellGroupedSection(
                    id: "geography-\(country)",
                    title: country,
                    jumpTitle: country,
                    indexTitle: String(country.prefix(1)).uppercased(),
                    bells: grouped[country, default: []].sorted(using: geographyComparators),
                    cabinetGroups: []
                )
            }
        case .acquisitionYear:
            let grouped = Dictionary(grouping: bellRecords, by: { acquisitionYearGroupTitle(for: $0) })
            let orderedTitles = grouped.keys.sorted { lhs, rhs in
                switch (Int(lhs), Int(rhs)) {
                case let (left?, right?):
                    return left > right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return compareDisplayValues(lhs, rhs, unknown: unknownTitle) == .orderedAscending
                }
            }

            return orderedTitles.map { title in
                BellGroupedSection(
                    id: "year-\(title)",
                    title: title,
                    jumpTitle: title,
                    indexTitle: nil,
                    bells: grouped[title, default: []].sorted(using: titleComparators),
                    cabinetGroups: []
                )
            }
        case .storage:
            let grouped = Dictionary(grouping: bellRecords) { bell in
                let components = storageComponents(for: bell)
                return StorageGroupKey(floor: components.floor, room: components.room)
            }
            let orderedKeys = grouped.keys.sorted { lhs, rhs in
                let floorComparison = compareDisplayValues(lhs.floor, rhs.floor, unknown: unknownTitle)
                if floorComparison != .orderedSame {
                    return floorComparison == .orderedAscending
                }

                return compareDisplayValues(lhs.room, rhs.room, unknown: unknownTitle) == .orderedAscending
            }

            return orderedKeys.map { key in
                let header = storageHeaderTitle(for: key)
                let cabinetGroups = Dictionary(grouping: grouped[key, default: []], by: storageCabinetTitle(for:))
                    .map { key, value in
                        BellStorageCabinetGroup(
                            id: "\(header)-\(key)",
                            title: key,
                            bells: value.sorted(using: titleComparators)
                        )
                    }
                    .sorted {
                        compareDisplayValues($0.title, $1.title, unknown: unknownTitle) == .orderedAscending
                    }

                return BellGroupedSection(
                    id: "storage-\(header)",
                    title: header,
                    jumpTitle: header,
                    indexTitle: nil,
                    bells: [],
                    cabinetGroups: cabinetGroups
                )
            }
        }
    }

    private func acquisitionYearGroupTitle(for bell: BellEntity) -> String {
        bell.acquiredYear.map(String.init) ?? unknownTitle
    }

    private func storageHeaderTitle(for key: StorageGroupKey) -> String {
        "\(key.floor) · \(key.room)"
    }

    private func storageCabinetTitle(for bell: BellEntity) -> String {
        storageComponents(for: bell).cabinet
    }

    private func storageComponents(for bell: BellEntity) -> (floor: String, room: String, cabinet: String) {
        guard let location = bell.location else {
            return (unknownTitle, unknownTitle, unknownTitle)
        }

        var floor = unknownTitle
        var room = unknownTitle
        var cabinet = unknownTitle
        var current: LocationEntity? = location

        while let location = current {
            switch location.kind {
            case .floor:
                floor = location.name
            case .room:
                room = location.name
            case .cabinet:
                cabinet = location.name
            case .shelf:
                break
            }

            current = location.parent
        }

        return (floor, room, cabinet)
    }

    private func compareDisplayValues(_ lhs: String, _ rhs: String, unknown: String) -> ComparisonResult {
        let leftIsUnknown = lhs == unknown
        let rightIsUnknown = rhs == unknown

        if leftIsUnknown != rightIsUnknown {
            return leftIsUnknown ? .orderedDescending : .orderedAscending
        }

        return lhs.localizedCaseInsensitiveCompare(rhs)
    }

    private func geographyDisplayValue(_ value: String, unknown: String) -> String {
        value.isEmpty ? unknown : value
    }

    private var sortComparators: [KeyPathComparator<BellEntity>] {
        switch orderMode {
        case .title:
            return titleComparators
        case .newestFirst:
            return [
                KeyPathComparator(\.createdAt, order: .reverse),
                titleComparator
            ]
        case .oldestFirst:
            return [
                KeyPathComparator(\.createdAt),
                titleComparator
            ]
        case .geography:
            return geographyComparators
        case .acquisitionYear:
            return [
                KeyPathComparator(\.acquiredYear, order: .reverse),
                titleComparator
            ]
        case .storage:
            return [
                KeyPathComparator(\.storageFloor, comparator: .localizedStandard),
                KeyPathComparator(\.storageRoom, comparator: .localizedStandard),
                KeyPathComparator(\.storageCabinet, comparator: .localizedStandard),
                KeyPathComparator(\.storageShelf, comparator: .localizedStandard),
                titleComparator
            ]
        }
    }

    private var geographyComparators: [KeyPathComparator<BellEntity>] {
        [
            KeyPathComparator(\.countryName, comparator: .localizedStandard),
            KeyPathComparator(\.originPlace?.regionName, comparator: .localizedStandard),
            KeyPathComparator(\.cityName, comparator: .localizedStandard),
            titleComparator
        ]
    }

    private var titleComparators: [KeyPathComparator<BellEntity>] {
        [titleComparator]
    }

    private var titleComparator: KeyPathComparator<BellEntity> {
        KeyPathComparator(\.title, comparator: .localizedStandard)
    }
}

struct BellGroupedSection: Identifiable {
    let id: String
    let title: String
    let jumpTitle: String
    let indexTitle: String?
    let bells: [BellEntity]
    let cabinetGroups: [BellStorageCabinetGroup]
}

struct BellStorageCabinetGroup: Identifiable {
    let id: String
    let title: String
    let bells: [BellEntity]
}

struct BellGeographyIndexEntry: Identifiable {
    let id: String
    let title: String
    let targetSectionID: String
}
