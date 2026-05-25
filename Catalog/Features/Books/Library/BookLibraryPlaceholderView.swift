import DesignSystem
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
                .padding(CatalogLayoutInsets.screen)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.hero, style: .continuous))

                CatalogEmptyState(
                    "Модуль книг следующий в очереди",
                    systemImage: "books.vertical",
                    description: "Каркас приложения уже разделяет коллекции по типам и позволяет каждой из них иметь собственный UI, repository и набор сценариев.",
                    topPadding: 30
                )
            }
        }
        .contentMargins(.horizontal, nil, for: .scrollContent)
        .contentMargins(.top, nil, for: .scrollContent)
        .contentMargins(.bottom, 120, for: .scrollContent)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                } label: {
                    Image(systemName: "books.vertical.circle")
                }
            }
        }
    }
}
