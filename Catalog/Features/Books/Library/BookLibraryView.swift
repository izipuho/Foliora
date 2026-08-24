import CoreData
import SwiftUI

/// Displays the book library list interface.
struct BookLibraryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var collections: [NSManagedObject] = []

    var body: some View {
        NavigationStack {
            List(collections, id: \.objectID) { collection in
                NavigationLink {
                    BookCollectionDraftView(collection: collection)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(collectionTitle(collection))
                            .font(.headline)

                        Text(collectionSubtitle(collection))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if collections.isEmpty {
                    ContentUnavailableView {
                        Label("No Book Libraries", systemImage: "books.vertical")
                    } description: {
                        Text("Create a first books collection backed by the shared Foliora catalog model.")
                    } actions: {
                        Button("Create Library", action: createBookCollection)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Foliora Books")
            .toolbar {
                ToolbarItem {
                    Button(action: createBookCollection) {
                        Label("Add Library", systemImage: "plus")
                    }
                }
            }
            .onAppear(perform: reloadCollections)
            .onReceive(NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange,
                object: viewContext
            )) { _ in
                reloadCollections()
            }
        }
    }

    private func createBookCollection() {
        let home = existingHome() ?? createDefaultHome()
        let collection = NSEntityDescription.insertNewObject(forEntityName: "CollectionEntity", into: viewContext)
        collection.setValue(UUID(), forKey: "id")
        collection.setValue(home.value(forKey: "id"), forKey: "homeID")
        collection.setValue(home.value(forKey: "name"), forKey: "homeName")
        collection.setValue(CollectionKind.books.rawValue, forKey: "kind")
        collection.setValue("Books", forKey: "title")
        collection.setValue("", forKey: "notes")
        collection.setValue(CollectionBackgroundStyle.mint.rawValue, forKey: "backgroundStyle")
        collection.setValue(home, forKey: "home")

        do {
            try viewContext.save()
            reloadCollections()
        } catch {
            viewContext.rollback()
        }
    }

    private func reloadCollections() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CollectionEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]
        request.predicate = NSPredicate(format: "kind == %@", CollectionKind.books.rawValue)
        collections = (try? viewContext.fetch(request)) ?? []
    }

    private func existingHome() -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "HomeEntity")
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try? viewContext.fetch(request).first
    }

    private func createDefaultHome() -> NSManagedObject {
        let home = NSEntityDescription.insertNewObject(forEntityName: "HomeEntity", into: viewContext)
        home.setValue(UUID(), forKey: "id")
        home.setValue("My Library", forKey: "name")
        home.setValue("books.vertical.fill", forKey: "iconName")
        home.setValue("", forKey: "notes")
        return home
    }

    private func collectionTitle(_ collection: NSManagedObject) -> String {
        let title = collection.value(forKey: "title") as? String
        return title?.isEmpty == false ? title! : "Books"
    }

    private func collectionSubtitle(_ collection: NSManagedObject) -> String {
        let homeName = collection.value(forKey: "homeName") as? String
        return homeName?.isEmpty == false ? homeName! : "Shared Foliora catalog"
    }
}

#Preview {
    let container = try! FolioraCoreDataStack.makeInMemoryContainer()
    BookLibraryView()
        .environment(\.managedObjectContext, container.viewContext)
}
