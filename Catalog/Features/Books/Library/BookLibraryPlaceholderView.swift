import SwiftUI

struct BookLibraryPlaceholderView: View {
    let collection: CollectionSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(collection.name)
                        .font(.largeTitle.bold())

                    Text("Для книг будет отдельный интерфейс: полки, авторы, издания, статусы прочтения и поиск по библиотеке. Этот модуль пока только обозначен архитектурно.")
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

                ContentUnavailableView(
                    "Модуль книг следующий в очереди",
                    systemImage: "books.vertical",
                    description: Text("Каркас приложения уже разделяет коллекции по типам и позволяет каждой из них иметь собственный UI, repository и набор сценариев.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
            }
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.96, blue: 0.92),
                    Color(red: 0.86, green: 0.93, blue: 0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle(collection.kind.title)
    }
}

struct BookLibraryPlaceholderView_Previews: PreviewProvider {
    static var previews: some View {
        let repository = InMemoryCatalogRepository()
        BookLibraryPlaceholderView(collection: repository.fetchCollections().first { $0.kind == .books }!)
    }
}
