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

enum BellSummaryFilter: Hashable {
    case all
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
    case country(String)
    case material(String)
    case tag(String)

    var title: String {
        switch self {
        case .all:
            return String(localized: "bell_catalog.filter_summary.all")
        case .withOrigin:
            return String(localized: "bell_catalog.summary.with_origin")
        case .missingOrigin:
            return String(localized: "bell_catalog.filter_summary.missing_origin")
        case .withYear:
            return String(localized: "bell_catalog.summary.with_year")
        case .missingYear:
            return String(localized: "bell_catalog.filter_summary.missing_year")
        case .withCity:
            return String(localized: "bell_catalog.filter_summary.with_city")
        case .withStorage:
            return String(localized: "bell_catalog.summary.with_storage")
        case .missingStorage:
            return String(localized: "bell_catalog.filter_summary.missing_storage")
        case .withNotes:
            return String(localized: "bell_catalog.summary.with_notes")
        case .missingNotes:
            return String(localized: "bell_catalog.filter_summary.missing_notes")
        case .withTags:
            return String(localized: "bell_catalog.summary.with_tags")
        case .missingTags:
            return String(localized: "bell_catalog.filter_summary.missing_tags")
        case .withMaterial:
            return String(localized: "bell_catalog.filter_summary.with_material")
        case .country(let value), .material(let value), .tag(let value):
            return value
        }
    }
}