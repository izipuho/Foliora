import Foundation

enum AppDestination: Hashable {
    case collection(CollectionSummary)
    case home(UUID)
}
