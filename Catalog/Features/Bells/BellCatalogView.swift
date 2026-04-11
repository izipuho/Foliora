import SwiftUI

struct BellCatalogView: View {
    let store: CatalogStore
    @State private var searchText = ""
    @State private var selectedCondition: BellCondition?

    private var filteredBells: [Bell] {
        store.bells.filter { bell in
            let matchesSearch =
                searchText.isEmpty ||
                bell.name.localizedCaseInsensitiveContains(searchText) ||
                bell.country.localizedCaseInsensitiveContains(searchText) ||
                bell.city.localizedCaseInsensitiveContains(searchText) ||
                bell.tags.joined(separator: " ").localizedCaseInsensitiveContains(searchText)

            let matchesCondition = selectedCondition == nil || bell.condition == selectedCondition
            return matchesSearch && matchesCondition
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Каталог колокольчиков")
                .font(.title2.bold())

            searchSection

            if filteredBells.isEmpty {
                ContentUnavailableView(
                    "Ничего не найдено",
                    systemImage: "bell.slash",
                    description: Text("Попробуйте изменить запрос или сбросить фильтр по состоянию.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
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
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Поиск по названию, городу или тегу", text: $searchText)
                .textInputAutocapitalization(.sentences)
                .padding(14)
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    FilterChip(
                        title: "Все",
                        isSelected: selectedCondition == nil
                    ) {
                        selectedCondition = nil
                    }

                    ForEach(BellCondition.allCases) { condition in
                        FilterChip(
                            title: condition.rawValue,
                            isSelected: selectedCondition == condition
                        ) {
                            selectedCondition = condition
                        }
                    }
                }
            }
        }
    }
}

private struct BellCardView: View {
    let bell: Bell

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(bell.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(bell.city), \(bell.country)")
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

struct BellCatalogView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BellCatalogView(store: CatalogStore())
                .padding()
                .background(Color(red: 0.99, green: 0.97, blue: 0.93))
        }
    }
}
