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
    enum Accessory {
        case icon(String)
        case label(text: String, systemImage: String)
    }

    let title: String
    var subtitle: String? = nil
    var accessory: Accessory? = nil
    var supportingText: String? = nil
    let systemImage: String

    private enum Metrics {
        static let iconCornerRadius: CGFloat = 18
        static let iconSize: CGFloat = 52
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            leading

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.bold())

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let supportingText {
                    Text(supportingText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 10)
                }
            }

            Spacer(minLength: 12)

            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .catalogSurfaceCard()
    }

    private var leading: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.iconCornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)

            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch accessory {
        case nil:
            EmptyView()
        case .icon(let systemImage):
            Image(systemName: systemImage)
        case .label(let text, let systemImage):
            Label(text, systemImage: systemImage)
        }
    }
}
