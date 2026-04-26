import SwiftUI

struct DashboardDataHealthCard: View {
    let progress: Double
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(CatalogSemanticColors.separator, lineWidth: 8)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.subheadline.weight(.bold))
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "bell_catalog.dashboard.health"))
                        .font(.headline)
                    Text(String(localized: "bell_catalog.dashboard.health.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .frame(width: 240, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.section, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8)
        }
        .buttonStyle(.plain)
    }
}

struct DashboardTopGeographyCard: View {
    let countryName: String
    let flag: String
    let countText: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(flag)
                    .font(.system(size: 34))

                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "bell_catalog.dashboard.top_geography"))
                        .font(.headline)
                    Text(countryName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(countText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.turn.down.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .padding()
            .frame(width: 240, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CatalogCornerRadii.section, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8)
        }
        .buttonStyle(.plain)
    }
}

struct TopGeographyEntry: Identifiable {
    let country: String
    let flag: String
    let countText: String

    var id: String { country }
}

struct TopGeographyPopover: View {
    let entries: [TopGeographyEntry]
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Button {
                    onSelect(entry.country)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.country)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(entry.countText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(String(localized: "bell_catalog.dashboard.top_geography"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

struct DataHealthEntry: Identifiable {
    let title: String
    let countText: String
    let filter: BellPresenceFilter

    var id: String { title }
}

struct DataHealthPopover: View {
    let entries: [DataHealthEntry]
    let onSelect: (BellPresenceFilter) -> Void

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Button {
                    onSelect(entry.filter)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(entry.countText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(String(localized: "bell_catalog.dashboard.health"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

struct SummaryCoverageRow: View {
    let title: String
    let value: Int
    let total: Int
    let tint: Color
    let action: () -> Void

    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(value) / CGFloat(total)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text("\(value)/\(total)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(CatalogSemanticColors.separator)

                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 8)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SummaryBreakdownRow: View {
    let title: String
    let value: Int
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()

                Text("\(value)")
                    .font(.subheadline.weight(.bold))
                    .catalogPillPadding(.compact)
                    .background(tint.opacity(0.14), in: Capsule())
            }
        }
        .buttonStyle(.plain)
    }
}

struct StatChip: View {
    let value: String
    let title: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: CatalogSpacing.micro) {
            Text(value)
                .font(.title2.weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, CatalogSpacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: CatalogCornerRadii.tile, style: .continuous))
    }
}
