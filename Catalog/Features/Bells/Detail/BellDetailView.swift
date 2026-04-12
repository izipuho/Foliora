import SwiftUI

struct BellDetailView: View {
    let bell: BellRecord

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(bell.title)
                        .font(.title2.bold())
                    Text(bell.placeDisplayName)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Характеристики") {
                detailRow("Материал", value: bell.materialDisplayName)
                detailRow("Состояние", value: bell.condition.rawValue)
                detailRow("Способ появления", value: bell.acquisitionMethod.rawValue)
                detailRow("Добавил", value: bell.createdBy)
                if let year = bell.year {
                    detailRow("Год", value: String(year))
                }
            }

            if !bell.tags.isEmpty {
                Section("Теги") {
                    Text(bell.tags.map { "#\($0)" }.joined(separator: "  "))
                }
            }

            Section("Заметки") {
                Text(bell.notes)
            }
        }
        .navigationTitle("Карточка")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct BellDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            let repository = InMemoryCatalogRepository()
            let collection = repository.fetchCollections().first { $0.kind == .bells }!
            BellDetailView(bell: repository.fetchBellRecords(for: collection.id)[0])
        }
    }
}
