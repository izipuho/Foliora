import SwiftUI

#if DEBUG
#Preview("Mixed Collections") {
    let container = PreviewContainer.make(.collectionsMinimal)
    let repository = CoreDataCatalogRepository(
        context: container.viewContext,
        persistentContainer: nil
    )
    let catalogSnapshot = CatalogSnapshot.load(from: container.viewContext)

    NavigationStack {
        CollectionsView(
            repository: repository,
            catalogSnapshot: catalogSnapshot
        )
    }
}
#endif
