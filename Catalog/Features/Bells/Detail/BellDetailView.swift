import SwiftUI

struct BellDetailView: View {
    @Binding var bell: BellRecord
    let repository: any CatalogRepository
    @State private var isPresentingEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(bell.title)
                        .font(.largeTitle.bold())
                    Text(bell.placeDisplayName)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        DetailBadge(label: bell.materialDisplayName, systemImage: "shippingbox.fill")
                        DetailBadge(label: bell.condition.rawValue, systemImage: "checkmark.seal")
                        if let year = bell.year {
                            DetailBadge(label: String(year), systemImage: "calendar")
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color.white.opacity(0.94), Color.white.opacity(0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )

                detailSection("Характеристики") {
                    detailRow("Материал", value: bell.materialDisplayName)
                    detailRow("Состояние", value: bell.condition.rawValue)
                    detailRow("Способ появления", value: bell.acquisitionMethod.rawValue)
                    detailRow("Хранится", value: bell.storageDisplayPath)
                    detailRow("Добавил", value: bell.createdBy)
                    if let year = bell.year {
                        detailRow("Год", value: String(year))
                    }
                }

                detailSection("Медиа") {
                    detailRow("Фото", value: String(bell.photoCount))
                    detailRow("3D models", value: String(bell.model3DCount))
                    detailRow("Documents", value: String(bell.documentCount))
                }

                if !bell.tags.isEmpty {
                    detailSection("Теги") {
                        Text(bell.tags.map { "#\($0)" }.joined(separator: "  "))
                            .font(.subheadline)
                            .foregroundStyle(Color(red: 0.43, green: 0.29, blue: 0.10))
                    }
                }

                detailSection("Заметки") {
                    Text(bell.notes)
                        .font(.body)
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.96, blue: 0.90),
                    Color(red: 0.95, green: 0.91, blue: 0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Карточка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            BellEditorView(
                collection: inferredCollection,
                repository: repository,
                bell: bell
            ) { updatedBell in
                bell = updatedBell
            }
        }
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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

    private var inferredCollection: CollectionSummary {
        repository.fetchCollections().first(where: { $0.id == bell.item.collectionID }) ??
            CollectionSummary(
                id: bell.item.collectionID,
                kind: .bells,
                name: "Колокольчики",
                subtitle: "",
                itemCount: 0,
                collaboratorCount: 0,
                role: .owner,
                status: .active,
                sharingSummary: ""
            )
    }
}

private struct DetailBadge: View {
    let label: String
    let systemImage: String

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color.black.opacity(0.05), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

struct BellDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            let repository = InMemoryCatalogRepository()
            let collection = repository.fetchCollections().first { $0.kind == .bells }!
            BellDetailPreviewHost(collectionID: collection.id, repository: repository)
        }
    }
}

private struct BellDetailPreviewHost: View {
    let collectionID: UUID
    let repository: any CatalogRepository
    @State private var bell: BellRecord

    init(collectionID: UUID, repository: any CatalogRepository) {
        self.collectionID = collectionID
        self.repository = repository
        _bell = State(initialValue: repository.fetchBellRecords(for: collectionID)[0])
    }

    var body: some View {
        BellDetailView(
            bell: $bell,
            repository: repository
        )
    }
}
