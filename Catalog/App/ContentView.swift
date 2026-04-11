import SwiftUI

struct ContentView: View {
    let store: CatalogStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    summaryCard
                    BellCatalogView(store: store)
                }
                .padding(20)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.99, green: 0.97, blue: 0.93),
                        Color(red: 0.96, green: 0.92, blue: 0.83)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Мои коллекции")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Каталог домашних коллекций")
                .font(.largeTitle.bold())
            Text("Начинаем с колокольчиков: учитываем происхождение, материал, состояние и личные заметки.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Колокольчики", systemImage: "bell.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(red: 0.55, green: 0.27, blue: 0.10))

            HStack(spacing: 12) {
                StatChip(title: "Всего", value: "\(store.bells.count)")
                StatChip(title: "Страны", value: "\(store.uniqueCountryCount)")
                StatChip(title: "Материалы", value: "\(store.uniqueMaterialCount)")
            }

            Text("Архитектура уже готова к добавлению новых разделов: монеты, книги, фарфор или любые другие домашние коллекции.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct StatChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(store: CatalogStore())
    }
}
