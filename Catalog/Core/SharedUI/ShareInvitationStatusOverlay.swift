import SwiftUI

struct ShareInvitationStatusOverlay: View {
    let state: CloudKitShareInvitationAcceptanceState

    var body: some View {
        switch state {
        case .accepting:
            statusCard {
                ProgressView()
                Text("collection.sharing.accepting")
                    .font(CatalogTypography.sectionTitle)
            }
        case .accepted:
            statusCard {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(CatalogSemanticColors.success)
                Text("collection.sharing.access_granted")
                    .font(CatalogTypography.sectionTitle)
            }
        case .idle, .failed:
            EmptyView()
        }
    }

    private func statusCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: CatalogMetrics.Spacing.md) {
            content()
        }
        .catalogSurfaceTile()
    }
}
