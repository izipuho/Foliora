import SwiftUI

struct CatalogEmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey?
    let primaryActionTitle: LocalizedStringKey?
    let primaryActionSystemImage: String?
    let primaryTint: Color
    let primaryAction: (() -> Void)?
    let secondaryActionTitle: LocalizedStringKey?
    let secondaryAction: (() -> Void)?

    init(
        systemImage: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        primaryActionTitle: LocalizedStringKey? = nil,
        primaryActionSystemImage: String? = nil,
        primaryTint: Color = .accentColor,
        primaryAction: (() -> Void)? = nil,
        secondaryActionTitle: LocalizedStringKey? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.primaryActionTitle = primaryActionTitle
        self.primaryActionSystemImage = primaryActionSystemImage
        self.primaryTint = primaryTint
        self.primaryAction = primaryAction
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
    }

    var body: some View {
        VStack(spacing: CatalogMetrics.Spacing.xl) {
            VStack(spacing: CatalogMetrics.Spacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: CatalogEmptyStateMetrics.iconSize, weight: .semibold))
                    .foregroundStyle(primaryTint)
                    .accessibilityHidden(true)

                VStack(spacing: CatalogMetrics.Spacing.sm) {
                    Text(title)
                        .font(CatalogTypography.cardTitle)
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)

                    if let message {
                        Text(message)
                            .font(CatalogTypography.cardSubtitle)
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            if hasActions {
                VStack(spacing: CatalogMetrics.Spacing.md) {
                    if let primaryActionTitle, let primaryAction {
                        Button(action: primaryAction) {
                            primaryActionLabel(primaryActionTitle)
                                .font(CatalogTypography.sectionTitle)
                                .padding(.horizontal, CatalogMetrics.Spacing.md)
                                .frame(height: CatalogEmptyStateMetrics.primaryActionHeight)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(.glassProminent)
                        .tint(primaryTint)
                    }

                    if let secondaryActionTitle, let secondaryAction {
                        Button(action: secondaryAction) {
                            Text(secondaryActionTitle)
                                .font(CatalogTypography.sectionTitle)
                        }
                        .buttonStyle(.borderless)
                        .tint(primaryTint)
                    }
                }
                .padding(.horizontal, CatalogMetrics.Spacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var hasActions: Bool {
        (primaryActionTitle != nil && primaryAction != nil)
            || (secondaryActionTitle != nil && secondaryAction != nil)
    }

    @ViewBuilder
    private func primaryActionLabel(_ title: LocalizedStringKey) -> some View {
        if let primaryActionSystemImage {
            Label(title, systemImage: primaryActionSystemImage)
        } else {
            Text(title)
        }
    }
}

private enum CatalogEmptyStateMetrics {
    static let iconSize: CGFloat = 56
    static let primaryActionHeight: CGFloat = 56
}
