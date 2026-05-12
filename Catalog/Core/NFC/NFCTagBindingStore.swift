import Foundation

struct NFCTagBindingConflict: Identifiable {
    enum Kind {
        case tagBoundToAnotherLocation(Location)
        case locationBoundToAnotherTag(URL)
    }

    let id = UUID()
    let kind: Kind
}

struct NFCTagBindingStore {
    private let locationToURLKey = "nfc.locationToURL"
    private let defaults: UserDefaults
    private let parser: TagPayloadParser

    init(defaults: UserDefaults = .standard, parser: TagPayloadParser = TagPayloadParser()) {
        self.defaults = defaults
        self.parser = parser
    }

    func conflicts(
        currentTagURL: URL?,
        newTagURL: URL,
        location: Location,
        allLocations: [Location]
    ) -> [NFCTagBindingConflict] {
        var conflicts: [NFCTagBindingConflict] = []

        if let currentTagURL,
           case .storageLocation(let existingLocationID) = try? parser.parse(url: currentTagURL),
           existingLocationID != location.id,
           let existingLocation = allLocations.first(where: { $0.id == existingLocationID }) {
            conflicts.append(.init(kind: .tagBoundToAnotherLocation(existingLocation)))
        }

        if let existingURL = boundURL(for: location.id), existingURL != newTagURL {
            conflicts.append(.init(kind: .locationBoundToAnotherTag(existingURL)))
        }

        return conflicts
    }

    func saveBinding(locationID: UUID, url: URL) {
        var bindings = storedBindings
        bindings[locationID.uuidString] = url.absoluteString
        defaults.set(bindings, forKey: locationToURLKey)
    }

    func boundURL(for locationID: UUID) -> URL? {
        storedBindings[locationID.uuidString].flatMap(URL.init(string:))
    }

    private var storedBindings: [String: String] {
        defaults.dictionary(forKey: locationToURLKey) as? [String: String] ?? [:]
    }
}
