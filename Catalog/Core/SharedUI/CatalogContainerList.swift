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

private struct CatalogContainerListRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(
                    top: CatalogMetrics.Insets.overlay,
                    leading: CatalogMetrics.Insets.screen,
                    bottom: CatalogMetrics.Insets.overlay,
                    trailing: CatalogMetrics.Insets.screen
                )
            )
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

    var body: some View {
        HStack(alignment: .center, spacing: CatalogMetrics.Spacing.md) {
            leading

            VStack(alignment: .leading, spacing: CatalogMetrics.Spacing.sm) {
                Text(title)
                    .font(CatalogTypography.cardTitle)

                if let subtitle {
                    Text(subtitle)
                        .font(CatalogTypography.cardSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let supportingText {
                    Text(supportingText)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, CatalogMetrics.Spacing.sm)
                }
            }

            Spacer(minLength: CatalogMetrics.Spacing.md)

            trailing
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .catalogSurfaceCard()
    }

    private var leading: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CatalogMetrics.CornerRadius.medium, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 52, height: 52)

            Image(systemName: systemImage)
                .font(CatalogTypography.cardTitle)
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
