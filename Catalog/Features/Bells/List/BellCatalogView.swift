import SwiftUI

struct BellCatalogView: View {
    let collection: CollectionSummary
    let repository: any CatalogRepository
    let collaborators: [Collaborator]

    @State private var searchText = ""
    @State private var selectedCondition: BellCondition?

    private var bells: [BellItem] {
        repository.fetchBellItems(for: collection.id)
    }

    private var filteredBells: [BellItem] {
        bells.filter { bell in
            let matchesSearch =
                searchText.isEmpty ||
                bell.title.localizedCaseInsensitiveContains(searchText) ||
                bell.originCountry.localizedCaseInsensitiveContains(searchText) ||
                bell.originCity.localizedCaseInsensitiveContains(searchText) ||
                bell.tags.joined(separator: " ").localizedCaseInsensitiveContains(searchText)

            let matchesCondition = selectedCondition == nil || bell.condition == selectedCondition
            return matchesSearch && matchesCondition
        }
    }

    private var countryCount: Int {
        Set(bells.map(\.originCountry)).count
    }

    private var materialCount: Int {
        Set(bells.map(\.material)).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                searchSection
                collaboratorStrip

                if filteredBells.isEmpty {
                    ContentUnavailableView(
                        "Ничего не найдено",
                        systemImage: "bell.slash",
                        description: Text("Попробуйте изменить запрос или сбросить фильтр по состоянию.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(filteredBells) { bell in
                            NavigationLink {
                                BellDetailView(bell: bell)
                            } label: {
                                BellCardView(bell: bell)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
        }
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
        .navigationTitle(collection.kind.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(collection.name)
                .font(.largeTitle.bold())

            Text("Отдельный UI для колокольчиков: происхождение, материал, состояние, заметки и прозрачный доступ участников коллекции.")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                StatChip(title: "Всего", value: "\(bells.count)")
                StatChip(title: "Страны", value: "\(countryCount)")
                StatChip(title: "Материалы", value: "\(materialCount)")
            }
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Поиск по названию, городу или тегу", text: $searchText)
                .textInputAutocapitalization(.sentences)
                .padding(14)
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    FilterChip(title: "Все", isSelected: selectedCondition == nil) {
                        selectedCondition = nil
                    }

                    ForEach(BellCondition.allCases) { condition in
                        FilterChip(title: condition.rawValue, isSelected: selectedCondition == condition) {
                            selectedCondition = condition
                        }
                    }
                }
            }
        }
    }

    private var collaboratorStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Доступ к коллекции")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(collaborators) { collaborator in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(collaborator.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(collaborator.role.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(
                            collaborator.isCurrentUser
                                ? Color(red: 0.61, green: 0.35, blue: 0.14).opacity(0.16)
                                : Color.white.opacity(0.78),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                }
            }
        }
    }
}

private struct BellCardView: View {
    let bell: BellItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bell.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(bell.originCity), \(bell.originCountry)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "bell.badge.fill")
                    .font(.title3)
                    .foregroundStyle(Color(red: 0.72, green: 0.45, blue: 0.16))
            }

            HStack {
                Label(bell.material, systemImage: "shippingbox.fill")
                Spacer()
                Label(bell.condition.rawValue, systemImage: "checkmark.seal")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)

            Text("Добавил: \(bell.createdBy)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !bell.tags.isEmpty {
                Text(bell.tags.map { "#\($0)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.43, green: 0.29, blue: 0.10))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    isSelected
                        ? Color(red: 0.53, green: 0.31, blue: 0.14)
                        : Color.white.opacity(0.72),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
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

struct BellCatalogView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            let repository = InMemoryCatalogRepository()
            let collection = repository.fetchCollections().first { $0.kind == .bells }!
            BellCatalogView(
                collection: collection,
                repository: repository,
                collaborators: repository.fetchCollaborators(for: collection.id)
            )
        }
    }
}
