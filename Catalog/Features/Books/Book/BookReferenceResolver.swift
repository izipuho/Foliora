import Foundation

enum BookReferenceResolutionStatus {
    case existing
    case new

    var systemImage: String {
        switch self {
        case .existing: "checkmark.circle.fill"
        case .new: "plus.circle"
        }
    }
}

/// Resolves book references against the current catalog without owning editor state.
struct BookReferenceResolver {
    let collectionID: UUID
    let catalogSeries: [BookSeries]
    let catalogPublishers: [Publisher]
    let catalogPeople: [Person]
    let contributors: [BookContributor]
    let selectedSeries: BookSeries?
    let selectedPublisher: Publisher?

    var availableSeries: [BookSeries] {
        var uniqueByID = Dictionary(catalogSeries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let selectedSeries {
            uniqueByID[selectedSeries.id] = selectedSeries
        }

        return uniqueByID.values.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var availablePublishers: [Publisher] {
        var uniqueByID = Dictionary(
            catalogPublishers
                .filter { $0.collectionID == collectionID }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        if let selectedPublisher, selectedPublisher.collectionID == collectionID {
            uniqueByID[selectedPublisher.id] = selectedPublisher
        }

        return uniqueByID.values.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var availablePeople: [Person] {
        var uniqueByID = Dictionary(
            catalogPeople
                .filter { $0.collectionID == collectionID }
                .map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for contributor in contributors where contributor.person.collectionID == collectionID {
            uniqueByID[contributor.person.id] = contributor.person
        }

        return uniqueByID.values.sorted {
            let comparison = $0.sortName.localizedCaseInsensitiveCompare($1.sortName)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func resolvePerson(named rawName: String) -> Person? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        if let existing = uniqueMatchingPerson(named: name, in: availablePeople) {
            return existing
        }

        if let canonical = uniqueMatchingPerson(named: name, in: canonicalPeople) {
            return materializePerson(canonical)
        }

        return Person(
            id: UUID(),
            collectionID: collectionID,
            givenName: name,
            birthYear: nil,
            deathYear: nil,
            biography: nil,
            birthPlace: nil,
            deathPlace: nil,
            photos: []
        )
    }

    func existingCatalogPerson(named rawName: String) -> Person? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        if let existing = uniqueMatchingPerson(named: name, in: availablePeople) {
            return existing
        }

        guard let canonical = uniqueMatchingPerson(named: name, in: canonicalPeople) else {
            return nil
        }
        return materializePerson(canonical)
    }

    func resolvePublisher(named rawName: String) -> Publisher? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let key = normalizedKey(name)
        if let existing = availablePublishers.first(where: { normalizedKey($0.name) == key }) {
            return existing
        }

        let canonicalMatches = canonicalPublishers.filter { normalizedKey($0.name) == key }
        if canonicalMatches.count == 1, let canonical = canonicalMatches.first {
            return materializePublisher(canonical)
        }

        return Publisher(
            id: UUID(),
            collectionID: collectionID,
            name: name
        )
    }

    func resolveSeries(named rawName: String) -> BookSeries? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let key = normalizedKey(name)
        if let existing = catalogSeries.first(where: { normalizedKey($0.name) == key }) {
            return existing
        }

        return BookSeries(
            id: UUID(),
            collectionID: collectionID,
            name: name,
            totalBookCount: nil,
            publisher: nil
        )
    }

    func status(for target: BookTextTarget) -> BookReferenceResolutionStatus? {
        switch target {
        case .field(.publisher):
            guard let selectedPublisher else { return nil }
            return catalogPublishers.contains(where: {
                $0.canonicalID == selectedPublisher.canonicalID
            }) ? .existing : .new
        case .field(.series):
            guard let selectedSeries else { return nil }
            return catalogSeries.contains(where: { $0.id == selectedSeries.id }) ? .existing : .new
        case let .author(index):
            guard contributors.indices.contains(index), contributors[index].role == .author else { return nil }
            let person = contributors[index].person
            return catalogPeople.contains(where: {
                $0.canonicalID == person.canonicalID
            }) ? .existing : .new
        default:
            return nil
        }
    }

    func normalizedKey(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private var canonicalPeople: [Person] {
        var uniqueByCanonicalID: [UUID: Person] = [:]

        for person in catalogPeople {
            if let existing = uniqueByCanonicalID[person.canonicalID] {
                if existing.collectionID != collectionID, person.collectionID == collectionID {
                    uniqueByCanonicalID[person.canonicalID] = person
                }
            } else {
                uniqueByCanonicalID[person.canonicalID] = person
            }
        }

        return Array(uniqueByCanonicalID.values)
    }

    private var canonicalPublishers: [Publisher] {
        var uniqueByCanonicalID: [UUID: Publisher] = [:]

        for publisher in catalogPublishers {
            if let existing = uniqueByCanonicalID[publisher.canonicalID] {
                if existing.collectionID != collectionID, publisher.collectionID == collectionID {
                    uniqueByCanonicalID[publisher.canonicalID] = publisher
                }
            } else {
                uniqueByCanonicalID[publisher.canonicalID] = publisher
            }
        }

        return Array(uniqueByCanonicalID.values)
    }

    private func materializePerson(_ source: Person) -> Person {
        if source.collectionID == collectionID {
            return source
        }

        if let existing = catalogPeople.first(where: {
            $0.collectionID == collectionID && $0.canonicalID == source.canonicalID
        }) {
            return existing
        }

        return Person(
            id: UUID(),
            canonicalID: source.canonicalID,
            collectionID: collectionID,
            givenName: source.givenName,
            familyName: source.familyName,
            middleName: source.middleName,
            birthYear: source.birthYear,
            deathYear: source.deathYear,
            biography: source.biography,
            birthPlace: source.birthPlace,
            deathPlace: source.deathPlace,
            photos: source.photos.map(materializeMediaAsset)
        )
    }

    private func materializePublisher(_ source: Publisher) -> Publisher {
        if source.collectionID == collectionID {
            return source
        }

        if let existing = catalogPublishers.first(where: {
            $0.collectionID == collectionID && $0.canonicalID == source.canonicalID
        }) {
            return existing
        }

        return Publisher(
            id: UUID(),
            canonicalID: source.canonicalID,
            collectionID: collectionID,
            name: source.name,
            logo: source.logo.map(materializeMediaAsset)
        )
    }

    private func materializeMediaAsset(_ source: MediaAsset) -> MediaAsset {
        MediaAsset(
            id: UUID(),
            itemID: nil,
            kind: source.kind,
            localIdentifier: "",
            displayName: source.displayName,
            sortOrder: source.sortOrder,
            fileName: source.fileName,
            mimeType: source.mimeType,
            byteSize: source.byteSize,
            checksum: source.checksum,
            width: source.width,
            height: source.height,
            duration: source.duration,
            metadataJSON: source.metadataJSON,
            originalData: source.originalData
        )
    }

    private func uniqueMatchingPerson(named rawName: String, in people: [Person]) -> Person? {
        let matches = people.compactMap { person -> (person: Person, score: Int)? in
            guard let score = personReferenceMatchScore(for: rawName, person: person) else { return nil }
            return (person, score)
        }

        guard let bestScore = matches.map({ $0.score }).max() else { return nil }
        let bestMatches = matches.filter { $0.score == bestScore }
        guard bestMatches.count == 1 else { return nil }
        return bestMatches[0].person
    }

    private func personReferenceMatchScore(for rawName: String, person: Person) -> Int? {
        let rawKey = normalizedKey(rawName)
        guard !rawKey.isEmpty else { return nil }

        if normalizedKey(person.displayName) == rawKey {
            return 300
        }

        let queryTokens = normalizedPersonNameTokens(rawName)
        let personNameParts: [String?] = [person.givenName, person.middleName, person.familyName]
        let personTokens = personNameParts
            .compactMap { $0 }
            .flatMap(normalizedPersonNameTokens)

        guard queryTokens.count >= 2,
              queryTokens.count <= personTokens.count else { return nil }

        if queryTokens.count == personTokens.count,
           queryTokens.sorted() == personTokens.sorted() {
            return 200
        }

        guard let fullTokenMatchCount = personNameFullTokenMatchCount(
            queryTokens,
            against: personTokens
        ), fullTokenMatchCount > 0 else {
            return nil
        }

        return 100 + fullTokenMatchCount
    }

    private func normalizedPersonNameTokens(_ value: String) -> [String] {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private func personNameFullTokenMatchCount(
        _ queryTokens: [String],
        against personTokens: [String]
    ) -> Int? {
        var remainingTokens = personTokens
        var fullTokenMatchCount = 0

        let orderedQueryTokens = queryTokens.sorted { lhs, rhs in
            let lhsIsInitial = lhs.count == 1
            let rhsIsInitial = rhs.count == 1
            if lhsIsInitial != rhsIsInitial {
                return !lhsIsInitial
            }
            return lhs.count > rhs.count
        }

        for queryToken in orderedQueryTokens {
            if let index = remainingTokens.firstIndex(of: queryToken) {
                if queryToken.count > 1 {
                    fullTokenMatchCount += 1
                }
                remainingTokens.remove(at: index)
                continue
            }

            guard queryToken.count == 1,
                  let initial = queryToken.first,
                  let index = remainingTokens.firstIndex(where: { $0.first == initial }) else {
                return nil
            }
            remainingTokens.remove(at: index)
        }

        return fullTokenMatchCount
    }
}
