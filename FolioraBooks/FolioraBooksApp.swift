import CollectionDomain
import Core
import DesignSystem
import SwiftUI

@main
struct FolioraBooksApp: App {
    var body: some Scene {
        WindowGroup {
            BooksShellView()
        }
    }
}

private struct BooksShellView: View {
    private let sampleMedia = MediaAsset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
        itemID: UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID(),
        kind: .document,
        localIdentifier: FileNameSanitizer.safeBaseName("Books Architecture Proof"),
        displayName: "Architecture proof",
        sortOrder: 0
    )

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Foliora Books")
                    .font(.title.bold())

                Text("App-family shell")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(sampleMedia.displayName ?? "Media")
                        .font(.headline)
                    Text(sampleMedia.kind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .catalogShadow(CatalogElevation.card)
            }
            .padding()
            .navigationTitle("Books")
        }
    }
}
