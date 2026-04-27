import Foundation
import Observation

private let unknownTitle = String(localized: "common.unknown")

struct BellCatalogDisplayModel {
    struct TopCountry: Identifiable {
        let country: String
        let countryCode: String
        let count: Int

        var id: String { country }
    }

    let bellRecords: [BellEntity]
    let filteredBells: [BellEntity]
    let groupedSections: [BellGroupedSection]
    let usesGroupedSections: Bool
    let countryCount: Int
    let cityCount: Int
    let topCountries: [TopCountry]
    let bellsWithOriginCount: Int
    let bellsWithAcquiredYearCount: Int
    let bellsWithStorageCount: Int
    let bellsWithNotesCount: Int
    let bellsWithTagsCount: Int
}

private struct StorageGroupKey: Hashable {
    let floor: String
    let room: String
}

private extension BellEntity {

    var storageFloor: String {
        location?.storagePath.floor ?? ""
    }

    var storageRoom: String {
        location?.storagePath.room ?? ""
    }

    var storageCabinet: String {
        location?.storagePath.cabinet ?? ""
    }

    var storageShelf: String {
        location?.storagePath.shelf ?? ""
    }

    var hasNotes: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

@MainActor
@Observable
final class BellCatalogViewModel {
    var bellRecords: [BellEntity]
    var selectedCondition: ItemCondition?
    var orderMode: BellOrderMode
    var filters: BellFilters
    var searchText: String

    init(
        bellRecords: [BellEntity],
        orderMode: BellOrderMode,
        filters: BellFilters,
        searchText: String,
        selectedCondition: ItemCondition? = nil
    ) {
        self.bellRecords = bellRecords
        self.orderMode = orderMode
        self.filters = filters
        self.searchText = searchText
        self.selectedCondition = selectedCondition
    }

    func makeDisplayModel() -> BellCatalogDisplayModel {
        let filteredBells = filteredBells
        let usesGroupedSections = usesGroupedSections

        return BellCatalogDisplayModel(
            bellRecords: bellRecords,
            filteredBells: filteredBells,
            groupedSections: usesGroupedSections ? groupedSections(fromFilteredBells: filteredBells) : [],
            usesGroupedSections: usesGroupedSections,
            countryCount: countryCount,
            cityCount: cityCount,
            topCountries: topCountries,
            bellsWithOriginCount: bellsWithOriginCount,
            bellsWithAcquiredYearCount: bellsWithAcquiredYearCount,
            bellsWithStorageCount: bellsWithStorageCount,
            bellsWithNotesCount: bellsWithNotesCount,
            bellsWithTagsCount: bellsWithTagsCount
        )
    }

    private var filteredBells: [BellEntity] {
        bellRecords.filter { bell in
            matches(bell: bell, filters: filters)
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

    private var countryCount: Int {
        Set(bellRecords.map(\.countryName).filter { !$0.isEmpty }).count
    }

    var materialCount: Int {
        Set(bellRecords.map(\.materialDisplayName)).count
    }

    private var cityCount: Int {
        Set(bellRecords.map(\.cityName).filter { !$0.isEmpty }).count
    }

    private var bellsWithOriginCount: Int {
        bellRecords.filter { $0.originPlace != nil }.count
    }

    private var bellsWithAcquiredYearCount: Int {
        bellRecords.filter { $0.acquiredYear != nil }.count
    }

    private var bellsWithStorageCount: Int {
        bellRecords.filter { $0.location != nil }.count
    }

    private var bellsWithNotesCount: Int {
        bellRecords.filter(\.hasNotes).count
    }

    private var bellsWithTagsCount: Int {
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

    private var topCountries: [BellCatalogDisplayModel.TopCountry] {
        topValues(from: bellRecords.map(\.countryName), skipEmpty: true).map { country, count in
            let countryCode = bellRecords
                .first(where: { $0.countryName.localizedCaseInsensitiveCompare(country) == .orderedSame })?
                .originPlace?
                .countryCode ?? ""

            return BellCatalogDisplayModel.TopCountry(
                country: country,
                countryCode: countryCode,
                count: count
            )
        }
    }

    var topMaterials: [(String, Int)] {
        topValues(from: bellRecords.map(\.materialDisplayName))
    }

    var topTags: [(String, Int)] {
        topValues(from: bellRecords.flatMap(\.tagValues))
    }

    private var usesGroupedSections: Bool {
        [.geography, .acquisitionYear, .storage].contains(orderMode)
    }

    func updateContext(
        orderMode: BellOrderMode,
        filters: BellFilters,
        searchText: String
    ) {
        self.orderMode = orderMode
        self.filters = filters
        self.searchText = searchText
    }

    func matches(bell: BellEntity, filters: BellFilters) -> Bool {
        filters.presence.allSatisfy { filter in
            switch filter {
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
            }
        }
    }

    func sorted(_ bellRecords: [BellEntity]) -> [BellEntity] {
        bellRecords.sorted(using: sortComparators)
    }

    private func groupedSections(fromFilteredBells bellRecords: [BellEntity]) -> [BellGroupedSection] {
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
                let path = bell.location?.storagePath
                return StorageGroupKey(
                    floor: path?.floor ?? unknownTitle,
                    room: path?.room ?? unknownTitle
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
        bell.location?.storagePath.cabinet ?? unknownTitle
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
