import Foundation
import Combine

private let unknownTitle = String(localized: "common.unknown")

enum BellCatalogLayout {
    case empty
    case flat([BellListItem])
    case grouped([BellGroupedSection])

    var isGrouped: Bool {
        if case .grouped = self {
            return true
        }
        return false
    }
}

struct BellCatalogDisplayModel {
    let layout: BellCatalogLayout
    let stats: BellCatalogStats
}

struct CountryCount: Identifiable {
    let country: String
    let countryCode: String
    let count: Int

    var id: String { country }
}

struct BellCatalogStats {
    let totalCount: Int
    let countryCount: Int
    let cityCount: Int
    let materialCount: Int
    let tagCount: Int
    let topCountries: [CountryCount]
    let filledOriginCount: Int
    let filledYearCount: Int
    let filledMaterialCount: Int
    let filledStorageCount: Int
    let filledNotesCount: Int
    let filledTagsCount: Int
}

private struct StorageGroupKey: Hashable {
    let floor: String
    let room: String
}

@MainActor
final class BellCatalogViewModel: ObservableObject {
    var orderMode: BellOrderMode
    var filters: BellFilters
    @Published private(set) var displayModel: BellCatalogDisplayModel
    private var sourceBells: [BellListItem]?

    init(
        orderMode: BellOrderMode,
        filters: BellFilters
    ) {
        self.orderMode = orderMode
        self.filters = filters
        self.displayModel = BellCatalogDisplayModel(
            layout: .empty,
            stats: BellCatalogStats(
                totalCount: 0,
                countryCount: 0,
                cityCount: 0,
                materialCount: 0,
                tagCount: 0,
                topCountries: [],
                filledOriginCount: 0,
                filledYearCount: 0,
                filledMaterialCount: 0,
                filledStorageCount: 0,
                filledNotesCount: 0,
                filledTagsCount: 0
            )
        )
    }

    func updateSource(bells: [BellListItem]) {
        sourceBells = bells
        let filteredBells = filteredBells(from: bells)
        let sortedBells = sorted(filteredBells)
        let groupedSections = groupedSections(fromFilteredBells: sortedBells)
        let layout: BellCatalogLayout

        if sortedBells.isEmpty {
            layout = .empty
        } else if !groupedSections.isEmpty {
            layout = .grouped(groupedSections)
        } else {
            layout = .flat(sortedBells)
        }

        let stats = buildStats(from: filteredBells, sourceBells: bells)

        displayModel = BellCatalogDisplayModel(
            layout: layout,
            stats: stats
        )
    }

    private func buildStats(from bells: [BellListItem], sourceBells: [BellListItem]) -> BellCatalogStats {
        BellCatalogStats(
            totalCount: bells.count,
            countryCount: countryCount(in: sourceBells),
            cityCount: cityCount(in: sourceBells),
            materialCount: materialCount(in: sourceBells),
            tagCount: tagCount(in: sourceBells),
            topCountries: topCountries(in: sourceBells),
            filledOriginCount: bellsWithOriginCount(in: sourceBells),
            filledYearCount: bellsWithAcquiredYearCount(in: sourceBells),
            filledMaterialCount: bellsWithMaterialCount(in: sourceBells),
            filledStorageCount: bellsWithStorageCount(in: sourceBells),
            filledNotesCount: bellsWithNotesCount(in: sourceBells),
            filledTagsCount: bellsWithTagsCount(in: sourceBells)
        )
    }

    func bell(withID id: UUID) -> BellListItem? {
        switch displayModel.layout {
        case .empty:
            return nil
        case .flat(let bells):
            return bells.first { $0.id == id }
        case .grouped(let sections):
            for section in sections {
                if let bell = section.allBells.first(where: { $0.id == id }) {
                    return bell
                }
            }

            return nil
        }
    }

    private func filteredBells(from bells: [BellListItem]) -> [BellListItem] {
        bells.filter { bell in
            matches(bell: bell, filters: filters)
        }
    }

    private func countryCount(in bells: [BellListItem]) -> Int {
        Set(bells.map(\.countryName).filter { !$0.isEmpty }).count
    }

    private func cityCount(in bells: [BellListItem]) -> Int {
        Set(bells.map(\.cityName).filter { !$0.isEmpty }).count
    }

    private func materialCount(in bells: [BellListItem]) -> Int {
        Set(bells.map(\.materialDisplayName).filter { !$0.isEmpty }).count
    }

    private func tagCount(in bells: [BellListItem]) -> Int {
        Set(bells.flatMap(\.tagValues)).count
    }

    private func bellsWithOriginCount(in bells: [BellListItem]) -> Int {
        bells.filter(\.hasOrigin).count
    }

    private func bellsWithAcquiredYearCount(in bells: [BellListItem]) -> Int {
        bells.filter { $0.acquiredYear != nil }.count
    }

    private func bellsWithMaterialCount(in bells: [BellListItem]) -> Int {
        bells.filter { $0.material != .unknown }.count
    }

    private func bellsWithStorageCount(in bells: [BellListItem]) -> Int {
        bells.filter(\.hasStorage).count
    }

    private func bellsWithNotesCount(in bells: [BellListItem]) -> Int {
        bells.filter(\.hasNotes).count
    }

    private func bellsWithTagsCount(in bells: [BellListItem]) -> Int {
        bells.filter { !$0.tagValues.isEmpty }.count
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

    private func topCountries(in bells: [BellListItem]) -> [CountryCount] {
        topValues(from: bells.map(\.countryName), skipEmpty: true).map { country, count in
            let countryCode = bells
                .first(where: { $0.countryName.localizedCaseInsensitiveCompare(country) == .orderedSame })?
                .countryCode ?? ""

            return CountryCount(
                country: country,
                countryCode: countryCode,
                count: count
            )
        }
    }

    func updateContext(orderMode: BellOrderMode) {
        guard self.orderMode != orderMode else { return }
        self.orderMode = orderMode
        refreshSource()
    }

    func updateContext(filters: BellFilters) {
        guard self.filters != filters else { return }
        self.filters = filters
        refreshSource()
    }

    private func refreshSource() {
        guard let sourceBells else { return }
        updateSource(bells: sourceBells)
    }

    func matches(bell: BellListItem, filters: BellFilters) -> Bool {
        filters.presence.allSatisfy { filter in
            switch filter {
            case .withOrigin:
                return bell.hasOrigin
            case .missingOrigin:
                return !bell.hasOrigin
            case .withYear:
                return bell.acquiredYear != nil
            case .missingYear:
                return bell.acquiredYear == nil
            case .withCity:
                return !bell.cityName.isEmpty
            case .withStorage:
                return bell.hasStorage
            case .missingStorage:
                return !bell.hasStorage
            case .withNotes:
                return bell.hasNotes
            case .missingNotes:
                return !bell.hasNotes
            case .withTags:
                return !bell.tagValues.isEmpty
            case .missingTags:
                return bell.tagValues.isEmpty
            case .withMaterial:
                return bell.material != .unknown
            case .missingMaterial:
                return bell.material == .unknown
            }
        }
        && filters.attributes.allSatisfy { filter in
            switch filter {
            case .country(let country):
                return bell.countryName.localizedCaseInsensitiveCompare(country) == .orderedSame
            case .material(let material):
                return bell.materialDisplayName.localizedCaseInsensitiveCompare(material) == .orderedSame
            case .tag(let tag):
                return bell.tagValues.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame })
            case .condition(let condition):
                return bell.condition == condition
            case .acquisitionMethod(let method):
                return bell.acquisitionMethod == method
            }
        }
    }

    func sorted(_ bellRecords: [BellListItem]) -> [BellListItem] {
        bellRecords.sorted(using: sortComparators)
    }

    private func groupedSections(fromFilteredBells bellRecords: [BellListItem]) -> [BellGroupedSection] {
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
                    bells: grouped[country, default: []],
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
                    bells: grouped[title, default: []],
                    cabinetGroups: []
                )
            }
        case .storage:
            let grouped = Dictionary(grouping: bellRecords) { bell in
                return StorageGroupKey(
                    floor: bell.storageFloor.isEmpty ? unknownTitle : bell.storageFloor,
                    room: bell.storageRoom.isEmpty ? unknownTitle : bell.storageRoom
                )
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
                            bells: value
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

    private func acquisitionYearGroupTitle(for bell: BellListItem) -> String {
        bell.acquiredYear.map(String.init) ?? unknownTitle
    }

    private func storageHeaderTitle(for key: StorageGroupKey) -> String {
        "\(key.floor) · \(key.room)"
    }

    private func storageCabinetTitle(for bell: BellListItem) -> String {
        bell.storageCabinet.isEmpty ? unknownTitle : bell.storageCabinet
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

    private var sortComparators: [KeyPathComparator<BellListItem>] {
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

    private var geographyComparators: [KeyPathComparator<BellListItem>] {
        [
            KeyPathComparator(\.countryName, comparator: .localizedStandard),
            KeyPathComparator(\.regionName, comparator: .localizedStandard),
            KeyPathComparator(\.cityName, comparator: .localizedStandard),
            titleComparator
        ]
    }

    private var titleComparators: [KeyPathComparator<BellListItem>] {
        [titleComparator]
    }

    private var titleComparator: KeyPathComparator<BellListItem> {
        KeyPathComparator(\.title, comparator: .localizedStandard)
    }
}

struct BellGroupedSection: Identifiable {
    let id: String
    let title: String
    let jumpTitle: String
    let indexTitle: String?
    let bells: [BellListItem]
    let cabinetGroups: [BellStorageCabinetGroup]

    var allBells: [BellListItem] {
        bells + cabinetGroups.flatMap(\.bells)
    }
}

struct BellStorageCabinetGroup: Identifiable {
    let id: String
    let title: String
    let bells: [BellListItem]
}

struct BellGeographyIndexEntry: Identifiable {
    let id: String
    let title: String
    let targetSectionID: String
}
