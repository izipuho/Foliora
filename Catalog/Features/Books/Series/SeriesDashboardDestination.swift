import CoreData
import SwiftUI

/// Resolves the current catalog dependencies for the Series dashboard destination.
struct SeriesDashboardDestination: View {
    let collection: CollectionSummary
    let canEditCollection: Bool

    @Environment(\.managedObjectContext) private var managedObjectContext

    var body: some View {
        let snapshot = CatalogSnapshot.load(from: managedObjectContext)
        let repository = CoreDataCatalogRepository(
            context: managedObjectContext,
            persistentContainer: FolioraAppDelegate.coreDataContainer
        )

        SeriesView(
            collection: collection,
            catalogSnapshot: snapshot,
            repository: repository,
            canEditCollection: canEditCollection
        )
    }
}
