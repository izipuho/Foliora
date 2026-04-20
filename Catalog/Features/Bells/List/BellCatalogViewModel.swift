import Foundation
import Observation

@MainActor
@Observable
final class BellCatalogViewModel {
    var bellRecords: [BellRecord]
    var selectedCondition: ItemCondition?
    var orderMode: BellOrderMode
    var summaryFilter: BellSummaryFilter?
    var searchText: String
    var locationsByID: [UUID: Location]
    var homeName: String

    init(
        bellRecords: [BellRecord],
        orderMode: BellOrderMode,
        summaryFilter: BellSummaryFilter?,
        searchText: String,
        locationsByID: [UUID: Location],
        homeName: String,
        selectedCondition: ItemCondition? = nil
    ) {
        self.bellRecords = bellRecords
        self.orderMode = orderMode
        self.summaryFilter = summaryFilter
        self.searchText = searchText
        self.locationsByID = locationsByID
        self.homeName = homeName
        self.selectedCondition = selectedCondition
    }

    var bells: [BellRecord] {
        sorted(bellRecords)
    }

    var filteredBells: [BellRecord] {
        sorted(
            bellRecords.filter { bell in
                let matchesSearch =
                    searchText.isEmpty ||
                    bell.title.localizedCaseInsensitiveContains(searchText) ||
                    bell.countryName.localizedCaseInsensitiveContains(searchText) ||
                    bell.cityName.localizedCaseInsensitiveContains(searchText) ||
                    bell.tags.joined(separator: " ").localizedCaseInsensitiveContains(searchText)

                let matchesCondition = selectedCondition == nil || bell.condition == selectedCondition
                let matchesSummaryFilter = matches(bell: bell, summaryFilter: summaryFilter)
                return matchesSearch && matchesCondition && matchesSummaryFilter
            }
        )
    }

    var filteredItemsBells: [BellRecord] {
        sorted(
            bellRecords.filter { bell in
                matches(bell: bell, summaryFilter: summaryFilter)
            }
        )
    }

    var recentBells: [BellRecord] {
        Array(
            bellRecords
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(5)
        )
    }

    var countryCount: Int {
        Set(bells.map(\.countryName).filter { !$0.isEmpty }).count
    }

    var materialCount: Int {
        Set(bells.map(\.materialDisplayName)).count
    }

    var cityCount: Int {
        Set(bells.map(\.cityName).filter { !$0.isEmpty }).count
    }

    var bellsWithOriginCount: Int {
        bells.filter { $0.originPlace != nil }.count
    }

    var bellsWithAcquiredYearCount: Int {
        bells.filter { $0.acquiredYear != nil }.count
    }

    var bellsWithStorageCount: Int {
        bells.filter { $0.item.locationID != nil }.count
    }

    var bellsWithNotesCount: Int {
        bells.filter { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var bellsWithTagsCount: Int {
        bells.filter { !$0.tags.isEmpty }.count
    }

    var topCountries: [(String, Int)] {
        Dictionary(grouping: bells.map(\.countryName).filter { !$0.isEmpty }, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
                }

                return lhs.1 > rhs.1
            }
    }

    var topMaterials: [(String, Int)] {
        Dictionary(grouping: bells.map(\.materialDisplayName), by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
                }

                return lhs.1 > rhs.1
            }
    }

    var topTags: [(String, Int)] {
        Dictionary(grouping: bells.flatMap(\.tags), by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.localizedCaseInsensitiveCompare(rhs.0) == .orderedAscending
                }

                return lhs.1 > rhs.1
            }
    }

    var usesGroupedSections: Bool {
        [.geography, .acquisitionYear, .storage].contains(orderMode)
    }

    var groupedFilteredItemSections: [BellGroupedSection] {
        groupedSections(from: filteredItemsBells)
    }

    var geographyIndexEntries: [BellGeographyIndexEntry] {
        Dictionary(grouping: groupedFilteredItemSections, by: \.indexTitle)
            .compactMap { key, value -> BellGeographyIndexEntry? in
                guard let key, let section = value.first else { return nil }
                return BellGeographyIndexEntry(id: key, title: key, targetSectionID: section.id)
            }
            .sorted { $0.title < $1.title }
    }

    func refreshBellRecords(from repository: any CatalogRepository, collectionID: UUID) {
        bellRecords = repository.fetchBellRecords(for: collectionID)
    }

    func updateContext(
        orderMode: BellOrderMode,
        summaryFilter: BellSummaryFilter?,
        searchText: String,
        locationsByID: [UUID: Location],
        homeName: String
    ) {
        self.orderMode = orderMode
        self.summaryFilter = summaryFilter
        self.searchText = searchText
        self.locationsByID = locationsByID
        self.homeName = homeName
    }

    func matches(bell: BellRecord, summaryFilter: BellSummaryFilter?) -> Bool {
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
            return bell.item.locationID != nil
        case .missingStorage:
            return bell.item.locationID == nil
        case .withNotes:
            return !bell.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .missingNotes:
            return bell.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .withTags:
            return !bell.tags.isEmpty
        case .missingTags:
            return bell.tags.isEmpty
        case .withMaterial:
            return !bell.materialDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .country(let country):
            return bell.countryName.localizedCaseInsensitiveCompare(country) == .orderedSame
        case .material(let material):
            return bell.materialDisplayName.localizedCaseInsensitiveCompare(material) == .orderedSame
        case .tag(let tag):
            return bell.tags.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame })
        }
    }

    func sorted(_ bells: [BellRecord]) -> [BellRecord] {
        bells.sorted { lhs, rhs in
            switch orderMode {
            case .title:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .newestFirst:
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .oldestFirst:
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .geography:
                return geographySort(lhs, rhs)
            case .acquisitionYear:
                if lhs.acquiredYear != rhs.acquiredYear {
                    switch (lhs.acquiredYear, rhs.acquiredYear) {
                    case let (left?, right?):
                        return left > right
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    default:
                        break
                    }
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .storage:
                let left = storageComponents(for: lhs)
                let right = storageComponents(for: rhs)

                if left.floor != right.floor {
                    return compareDisplayValues(left.floor, right.floor, unknown: String(localized: "common.unknown")) == .orderedAscending
                }

                if left.room != right.room {
                    return compareDisplayValues(left.room, right.room, unknown: String(localized: "common.unknown")) == .orderedAscending
                }

                if left.cabinet != right.cabinet {
                    return compareDisplayValues(left.cabinet, right.cabinet, unknown: String(localized: "common.unknown")) == .orderedAscending
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }

    func groupedSections(from bells: [BellRecord]) -> [BellGroupedSection] {
        switch orderMode {
        case .title, .newestFirst, .oldestFirst:
            return []
        case .geography:
            let unknown = String(localized: "common.unknown")
            let grouped = Dictionary(grouping: bells, by: { normalizedCountry(for: $0) })
            let orderedCountries = grouped.keys.sorted {
                compareDisplayValues($0, $1, unknown: unknown) == .orderedAscending
            }

            return orderedCountries.map { country in
                BellGroupedSection(
                    id: "geography-\(country)",
                    title: country,
                    jumpTitle: country,
                    indexTitle: String(country.prefix(1)).uppercased(),
                    bells: grouped[country, default: []].sorted(by: geographySort),
                    cabinetGroups: []
                )
            }
        case .acquisitionYear:
            let unknown = String(localized: "common.unknown")
            let grouped = Dictionary(grouping: bells, by: { acquisitionYearGroupTitle(for: $0) })
            let orderedTitles = grouped.keys.sorted { lhs, rhs in
                switch (Int(lhs), Int(rhs)) {
                case let (left?, right?):
                    return left > right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return compareDisplayValues(lhs, rhs, unknown: unknown) == .orderedAscending
                }
            }

            return orderedTitles.map { title in
                BellGroupedSection(
                    id: "year-\(title)",
                    title: title,
                    jumpTitle: title,
                    indexTitle: nil,
                    bells: grouped[title, default: []].sorted {
                        $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    },
                    cabinetGroups: []
                )
            }
        case .storage:
            let grouped = Dictionary(grouping: bells, by: storageHeaderTitle(for:))
            let orderedHeaders = grouped.keys.sorted { lhs, rhs in
                let left = storageSortComponents(from: lhs)
                let right = storageSortComponents(from: rhs)

                if left.floor != right.floor {
                    return compareDisplayValues(left.floor, right.floor, unknown: String(localized: "common.unknown")) == .orderedAscending
                }

                return compareDisplayValues(left.room, right.room, unknown: String(localized: "common.unknown")) == .orderedAscending
            }

            return orderedHeaders.map { header in
                let cabinetGroups = Dictionary(grouping: grouped[header, default: []], by: storageCabinetTitle(for:))
                    .map { key, value in
                        BellStorageCabinetGroup(
                            id: "\(header)-\(key)",
                            title: key,
                            bells: value.sorted {
                                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                            }
                        )
                    }
                    .sorted {
                        compareDisplayValues($0.title, $1.title, unknown: String(localized: "common.unknown")) == .orderedAscending
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

    private func normalizedCountry(for bell: BellRecord) -> String {
        let country = bell.countryName.trimmingCharacters(in: .whitespacesAndNewlines)
        return country.isEmpty ? String(localized: "common.unknown") : country
    }

    private func normalizedRegion(for bell: BellRecord) -> String {
        let region = (bell.originPlace?.regionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return region.isEmpty ? String(localized: "common.unknown") : region
    }

    private func normalizedCity(for bell: BellRecord) -> String {
        let city = bell.cityName.trimmingCharacters(in: .whitespacesAndNewlines)
        return city.isEmpty ? String(localized: "common.unknown") : city
    }

    private func acquisitionYearGroupTitle(for bell: BellRecord) -> String {
        bell.acquiredYear.map(String.init) ?? String(localized: "common.unknown")
    }

    private func storageHeaderTitle(for bell: BellRecord) -> String {
        let components = storageComponents(for: bell)
        if components.floor == String(localized: "common.unknown"), components.room == String(localized: "common.unknown") {
            return String(localized: "common.unknown")
        }

        return "\(components.floor) · \(components.room)"
    }

    private func storageCabinetTitle(for bell: BellRecord) -> String {
        storageComponents(for: bell).cabinet
    }

    private func storageComponents(for bell: BellRecord) -> (floor: String, room: String, cabinet: String) {
        guard let locationID = bell.item.locationID else {
            let unknown = String(localized: "common.unknown")
            return (unknown, unknown, unknown)
        }

        var floor = String(localized: "common.unknown")
        var room = String(localized: "common.unknown")
        var cabinet = String(localized: "common.unknown")
        var currentID: UUID? = locationID

        while let id = currentID, let location = locationsByID[id] {
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

            currentID = location.parentLocationID
        }

        return (floor, room, cabinet)
    }

    private func storageSortComponents(from header: String) -> (floor: String, room: String) {
        let parts = header.components(separatedBy: " · ")
        if parts.count == 2 {
            return (parts[0], parts[1])
        }

        return (header, header)
    }

    private func compareDisplayValues(_ lhs: String, _ rhs: String, unknown: String) -> ComparisonResult {
        let leftIsUnknown = lhs == unknown
        let rightIsUnknown = rhs == unknown

        if leftIsUnknown != rightIsUnknown {
            return leftIsUnknown ? .orderedDescending : .orderedAscending
        }

        return lhs.localizedCaseInsensitiveCompare(rhs)
    }

    private func geographySort(_ lhs: BellRecord, _ rhs: BellRecord) -> Bool {
        let countryComparison = compareDisplayValues(normalizedCountry(for: lhs), normalizedCountry(for: rhs), unknown: String(localized: "common.unknown"))
        if countryComparison != .orderedSame {
            return countryComparison == .orderedAscending
        }

        let regionComparison = compareDisplayValues(normalizedRegion(for: lhs), normalizedRegion(for: rhs), unknown: String(localized: "common.unknown"))
        if regionComparison != .orderedSame {
            return regionComparison == .orderedAscending
        }

        let cityComparison = compareDisplayValues(normalizedCity(for: lhs), normalizedCity(for: rhs), unknown: String(localized: "common.unknown"))
        if cityComparison != .orderedSame {
            return cityComparison == .orderedAscending
        }

        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

struct BellGroupedSection: Identifiable {
    let id: String
    let title: String
    let jumpTitle: String
    let indexTitle: String?
    let bells: [BellRecord]
    let cabinetGroups: [BellStorageCabinetGroup]
}

struct BellStorageCabinetGroup: Identifiable {
    let id: String
    let title: String
    let bells: [BellRecord]
}

struct BellGeographyIndexEntry: Identifiable {
    let id: String
    let title: String
    let targetSectionID: String
}
