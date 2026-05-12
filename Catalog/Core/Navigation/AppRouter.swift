import Foundation
import Combine

enum AppDestination: Hashable {
    case collection(CollectionSummary, BellFilters)
    case home(UUID)
}

final class AppExternalRouteRouter: ObservableObject {
    @Published var pendingRouteKey: ExternalRouteKey?

    func open(_ routeKey: ExternalRouteKey) {
        pendingRouteKey = routeKey
    }
}

enum ExternalRouteKey: Hashable {
    case storageLocation(UUID)
}

struct ResolvedExternalRoute: Hashable {
    let collection: CollectionSummary
    let filters: BellFilters
}

enum ExternalRouteResolutionError: Error {
    case locationNotFound
}

struct AppRouteResolver {
    func resolveStorageLocation(
        _ locationID: UUID,
        locations: [LocationEntity],
        collections: [CollectionEntity]
    ) throws -> ResolvedExternalRoute {
        guard let location = locations.first(where: { $0.id == locationID }),
              let homeID = location.home?.id,
              let collection = collections
                .filter({ $0.home?.id == homeID })
                .sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
                .first else {
            throw ExternalRouteResolutionError.locationNotFound
        }

        return ResolvedExternalRoute(
            collection: collection.summarySnapshot,
            filters: BellFilters(attributes: [.storageLocation(locationID)])
        )
    }
}
