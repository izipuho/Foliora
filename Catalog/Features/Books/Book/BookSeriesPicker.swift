import Foundation
import SwiftUI

struct BookSeriesPickerField: View {
    @Binding var selection: BookSeries?
    let series: [BookSeries]
    let collectionID: UUID
    let statusSystemImage: String?
    let onCreate: (BookSeries) -> Void

    @State private var isPresentingPicker = false

    var body: some View {
        Button {
            isPresentingPicker = true
        } label: {
            HStack {
                Text("series.title")
                    .foregroundStyle(.primary)

                Spacer()

                Text(selection?.name ?? String(localized: "common.none"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)

                if let statusSystemImage {
                    Image(systemName: statusSystemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(CatalogTypography.chipLabel)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresentingPicker) {
            BookSeriesSelectionView(
                selection: $selection,
                series: series,
                collectionID: collectionID,
                onCreate: onCreate
            )
        }
    }
}

private struct BookSeriesSelectionView: View {
    @Binding var selection: BookSeries?
    let series: [BookSeries]
    let collectionID: UUID
    let onCreate: (BookSeries) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredSeries: [BookSeries] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return series }
        return series.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var newSeriesName: String? {
        let candidate = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        guard !series.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) else {
            return nil
        }
        return candidate
    }

    var body: some View {
        NavigationStack {
            List {
                if let newSeriesName {
                    Button {
                        let newSeries = BookSeries(
                            id: UUID(),
                            collectionID: collectionID,
                            name: newSeriesName,
                            totalBookCount: nil,
                            publisher: nil
                        )
                        onCreate(newSeries)
                        selection = newSeries
                        dismiss()
                    } label: {
                        Label(
                            String.localizedStringWithFormat(String(localized: "common.action.add_value"), newSeriesName),
                            systemImage: "plus.circle.fill"
                        )
                    }
                }

                Button {
                    selection = nil
                    dismiss()
                } label: {
                    HStack {
                        Text(String(localized: "common.none"))
                            .foregroundStyle(.primary)

                        Spacer()

                        if selection == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }

                ForEach(filteredSeries) { item in
                    Button {
                        selection = item
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.xs) {
                                Text(item.name)
                                    .foregroundStyle(.primary)

                                if let totalBookCount = item.totalBookCount {
                                    Text(CollectionKind.bookCountLabel(for: totalBookCount))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if selection?.id == item.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("series.title")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "picker.search_or_add")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "common.cancel"))
                }
            }
        }
    }
}
