import CoreData
import SwiftUI

/// Displays the draft book collection interface.
struct BookCollectionDraftView: View {
    let collection: NSManagedObject

    var body: some View {
        ContentUnavailableView(
            collectionTitle,
            systemImage: "books.vertical",
            description: Text("Books, editions, authors, reading status and search will live here. This draft is already backed by the shared Foliora catalog model.")
        )
        .navigationTitle(collectionTitle)
    }

    private var collectionTitle: String {
        let title = collection.value(forKey: "title") as? String
        return title?.isEmpty == false ? title! : "Books"
    }
}
