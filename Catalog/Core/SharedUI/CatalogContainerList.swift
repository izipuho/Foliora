import SwiftUI

struct CatalogContainerList<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        List {
            content
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private enum Metrics {
    static let rowVerticalInset: CGFloat = 8
    static let rowHorizontalInset: CGFloat = 24

    static let rowInsets = EdgeInsets(
        top: rowVerticalInset,
        leading: rowHorizontalInset,
        bottom: rowVerticalInset,
        trailing: rowHorizontalInset
    )
}

private struct CatalogContainerListRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(Metrics.rowInsets)
    }
}

extension View {
    func catalogContainerListRow() -> some View {
        modifier(CatalogContainerListRowModifier())
    }
}

struct CatalogContainerCard: View {
    let title: String
    var subtitle: String? = nil
    var subtitleTrailing: String? = nil
    var subtitleTrailingIcon: String? = nil
    var footnote: [String] = []
    let systemImage: String
    var accessorySystemImage: String? = nil

    private enum Metrics {
        static let iconCornerRadius: CGFloat = 18
        static let iconSize: CGFloat = 52
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: Metrics.iconCornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: Metrics.iconSize, height: Metrics.iconSize)

                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tint)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.title3.bold())

                    HStack(alignment: .firstTextBaseline) {
                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }


                        Spacer(minLength: 8)

                        switch (subtitleTrailing, subtitleTrailingIcon) {
                        case let (.some(subtitleTrailing), .some(subtitleTrailingIcon)):
                            Label(subtitleTrailing, systemImage: subtitleTrailingIcon)
                        case let (.some(subtitleTrailing), .none):
                            Text(subtitleTrailing)
                        case let (.none, .some(subtitleTrailingIcon)):
                            Image(systemName: subtitleTrailingIcon)
                        case (.none, .none):
                            EmptyView()
                        }
                    }
                }

                Spacer(minLength: 12)

                if let accessorySystemImage {
                    Image(systemName: accessorySystemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }

            if !footnote.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(footnote, id: \.self) { detailLine in
                        Text(detailLine)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .catalogSurfaceCard()
    }
}
