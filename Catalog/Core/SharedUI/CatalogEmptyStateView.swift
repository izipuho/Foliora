import SwiftUI

struct CatalogEmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let primaryActionTitle: LocalizedStringKey
    let primaryActionSystemImage: String?
    let primaryTint: Color
    let primaryAction: () -> Void
    let secondaryActionTitle: LocalizedStringKey?
    let secondaryAction: (() -> Void)?

    init(
        systemImage: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        primaryActionTitle: LocalizedStringKey,
        primaryActionSystemImage: String? = nil,
        primaryTint: Color,
        primaryAction: @escaping () -> Void,
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
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(message)
            )
            .frame(maxWidth: .infinity)

            VStack(spacing: CatalogMetrics.Spacing.md) {
                Button(action: primaryAction) {
                    primaryActionLabel
                        .font(CatalogTypography.sectionTitle)
                        .frame(maxWidth: 420)
                        .frame(height: 56)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .buttonStyle(.borderedProminent)
                .tint(primaryTint)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal)
        .padding(.bottom, 80)
    }

    @ViewBuilder
    private var primaryActionLabel: some View {
        if let primaryActionSystemImage {
            Label(primaryActionTitle, systemImage: primaryActionSystemImage)
        } else {
            Text(primaryActionTitle)
        }
    }
}
