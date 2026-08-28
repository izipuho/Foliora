import Foundation
import Combine

private let unknownTitle = String(localized: "common.unknown")

/// Groups bell catalog layout values and behavior.
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

/// Represents bell catalog display model data and behavior.
struct BellCatalogDisplayModel {
    let layout: BellCatalogLayout
    let stats: BellCatalogStats
}

/// Represents country count data and behavior.
struct CountryCount: Identifiable {
    let country: String
    let countryCode: String
    let count: Int

    var id: String { country }
}

/// Represents bell catalog stats data and behavior.
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

/// Represents bell catalog view model data and behavior.
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
        if orderMode == .storage {
            return CatalogStorageGrouping.sorted(
                bellRecords,
                storagePath: { $0.storagePath },
                title: { $0.title }
            )
        }

        return bellRecords.sorted(using: sortComparators)
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
                    storageGroups: []
                )
            }
        case .acquisitionYear:
            return CatalogYearGrouping.descending(
                bellRecords,
                year: { $0.acquiredYear },
                sortedBy: { lhs, rhs in
                    lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            ).map { group in
                let title = group.year.map(String.init) ?? unknownTitle
                return BellGroupedSection(
                    id: "year-\(title)",
                    title: title,
                    jumpTitle: title,
                    indexTitle: nil,
                    bells: group.elements,
                    storageGroups: []
                )
            }
        case .storage:
            return CatalogStorageGrouping.sections(
                fromSorted: bellRecords,
                storagePath: { $0.storagePath }
            ).map { section in
                let header = section.pathComponents.isEmpty
                    ? unknownTitle
                    : section.pathComponents.joined(separator: " · ")
                let sectionID = storageSectionID(
                    floor: section.floor,
                    room: section.room
                )
                let storageGroups = section.subgroups.map { subgroup in
                    BellStorageGroup(
                        id: "\(sectionID)-\(subgroup.kind.rawValue):\(storageIDComponent(subgroup.title))",
                        kind: subgroup.kind,
                        title: subgroup.title,
                        bells: subgroup.elements
                    )
                }

                return BellGroupedSection(
                    id: sectionID,
                    title: header,
                    jumpTitle: header,
                    indexTitle: nil,
                    bells: section.elements,
                    storageGroups: storageGroups
                )
            }
        }
    }

    private func storageSectionID(floor: String?, room: String?) -> String {
        "storage-floor:\(storageIDComponent(floor))-room:\(storageIDComponent(room))"
    }

    private func storageIDComponent(_ value: String?) -> String {
        value.map { "value:\($0)" } ?? "nil"
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
            return titleComparators
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

/// Represents bell grouped section data and behavior.
struct BellGroupedSection: Identifiable {
    let id: String
    let title: String
    let jumpTitle: String
    let indexTitle: String?
    let bells: [BellListItem]
    let storageGroups: [BellStorageGroup]

    var allBells: [BellListItem] {
        bells + storageGroups.flatMap(\.bells)
    }
}

/// Represents bell storage group data and behavior.
struct BellStorageGroup: Identifiable {
    let id: String
    let kind: LocationKind
    let title: String
    let bells: [BellListItem]
}

/// Represents bell geography index entry data and behavior.
struct BellGeographyIndexEntry: Identifiable {
    let id: String
    let title: String
    let targetSectionID: String
}
