import CoreData

@MainActor
extension PreviewData {
    static func populateMinimalBooks(context: NSManagedObjectContext) {
        populateCoreMinimal(context: context, collectionKind: .books)
    }
}
