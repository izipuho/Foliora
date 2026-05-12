import Foundation

enum TagPayloadParseError: Error {
    case unknownTag
}

struct TagURLFormat {
    static let shared = TagURLFormat()

    // Replace this placeholder host with the Universal Links domain when the paid account is available.
    let scheme = "https"
    let host = "catalog.example.com"
    let storageLocationPathPrefix = "/locations"

    func url(for routeKey: ExternalRouteKey) -> URL {
        switch routeKey {
        case .storageLocation(let locationID):
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            components.path = "\(storageLocationPathPrefix)/\(locationID.uuidString)"
            return components.url!
        }
    }
}

struct TagPayloadParser {
    private let format: TagURLFormat

    init(format: TagURLFormat = .shared) {
        self.format = format
    }

    func parse(url: URL) throws -> ExternalRouteKey {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == format.scheme,
              components.host == format.host,
              components.queryItems?.isEmpty != false else {
            throw TagPayloadParseError.unknownTag
        }

        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count == 2,
              "/\(parts[0])" == format.storageLocationPathPrefix,
              let locationID = UUID(uuidString: parts[1]) else {
            throw TagPayloadParseError.unknownTag
        }

        return .storageLocation(locationID)
    }
}
