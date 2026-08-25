import Foundation

/// Builds and parses collection deep links between Foliora apps.
enum CollectionAppLink {
    static func url(for kind: CollectionKind, collectionID: UUID) -> URL? {
        var components = URLComponents()
        components.scheme = scheme(for: kind)
        components.host = "collection"
        components.path = "/\(collectionID.uuidString)"
        return components.url
    }

    static func collectionID(from url: URL, for kind: CollectionKind) -> UUID? {
        guard url.scheme?.lowercased() == scheme(for: kind),
              url.host?.lowercased() == "collection"
        else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count == 1 else { return nil }
        return UUID(uuidString: pathComponents[0])
    }

    private static func scheme(for kind: CollectionKind) -> String {
        switch kind {
        case .bells:
            return "foliora-bells"
        case .books:
            return "foliora-books"
        }
    }
}
