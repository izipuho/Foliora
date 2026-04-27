import SwiftUI

enum SummaryCountKind: String {
    case bells
    case materials
    case countries
    case cities
    case members

    var resource: LocalizedStringResource {
        switch self {
            case .bells: "collection.count.bells"
            case .materials: "collection.count.materials"
            case .countries: "collection.count.countries"
            case .cities: "collection.count.cities"
            case .members: "collection.count.members"
        }
    }
}

enum BellOrderMode: String, CaseIterable, Hashable {
    case title
    case newestFirst
    case oldestFirst
    case geography
    case acquisitionYear
    case storage

    var title: LocalizedStringResource {
        switch self {
            case .title: "bell_catalog.sort.title"
            case .newestFirst: "bell_catalog.sort.newest_first"
            case .oldestFirst: "bell_catalog.sort.oldest_first"
            case .geography: "bell_catalog.sort.geography"
            case .acquisitionYear: "bell_catalog.sort.acquisition_year"
            case .storage: "bell_catalog.sort.storage"
        }
    }
}

enum BellPresenceFilter: Hashable {
    case withOrigin
    case missingOrigin
    case withYear
    case missingYear
    case withCity
    case withStorage
    case missingStorage
    case withNotes
    case missingNotes
    case withTags
    case missingTags
    case withMaterial
}

enum BellAttributeFilter: Hashable {
    case country(String)
    case material(String)
    case tag(String)
    case condition(ItemCondition)
    case acquisitionMethod(AcquisitionMethod)
}

struct BellFilters: Hashable {
    var presence: Set<BellPresenceFilter> = []
    var attributes: Set<BellAttributeFilter> = []

    var isEmpty: Bool {
        presence.isEmpty && attributes.isEmpty
    }
}
