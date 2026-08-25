import Foundation
import UIKit

/// Builds, opens, and parses collection deep links between Foliora apps.
enum CollectionAppLink {
    static var currentAppKind: CollectionKind {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "FolioraCollectionKind") as? String,
              let kind = CollectionKind(rawValue: rawValue)
        else {
            preconditionFailure("FolioraCollectionKind is missing or invalid in Info.plist.")
        }

        return kind
    }

    static func url(for kind: CollectionKind, collectionID: UUID) -> URL? {
        var components = URLComponents()
        components.scheme = scheme(for: kind)
        components.host = "collection"
        components.path = "/\(collectionID.uuidString)"
        return components.url
    }

    @MainActor
    static func open(kind: CollectionKind, collectionID: UUID) {
        guard let url = url(for: kind, collectionID: collectionID) else { return }
        UIApplication.shared.open(url)
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

@MainActor
final class CollectionAppLinkRouter: ObservableObject {
    static let shared = CollectionAppLinkRouter()

    @Published private(set) var pendingCollectionID: UUID?

    private init() {}

    func handle(_ url: URL) {
        pendingCollectionID = CollectionAppLink.collectionID(
            from: url,
            for: CollectionAppLink.currentAppKind
        )
    }

    func consume(_ collectionID: UUID) {
        guard pendingCollectionID == collectionID else { return }
        pendingCollectionID = nil
    }
}
