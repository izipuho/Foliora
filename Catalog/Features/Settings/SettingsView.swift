import CloudKit
import CoreData
import SwiftUI

/// Displays the settings view interface.
struct SettingsView: View {
    let repository: any CatalogRepository
    let navigate: (AppDestination) -> Void
    @Binding var displayName: String?

    @Environment(\.managedObjectContext) private var managedObjectContext

    @State private var editedDisplayName = ""
    @State private var isImportingDocument = false
    @State private var importPresentation: CatalogImportPresentation?
    @State private var isImportExportRunning = false
    @State private var importErrorMessage: String?
    @State private var importResultMessage: String?
    @State private var exportResultMessage: String?
    @State private var isDeveloperMenuPresented = false
    @FocusState private var isDisplayNameFocused: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("common.name", text: $editedDisplayName)
                        .textContentType(.name)
                        .focused($isDisplayNameFocused)
                    
                    if hasUnsavedDisplayNameChanges {
                        Button {
                            saveDisplayName()
                            isDisplayNameFocused = false
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("onboarding.introduce.save_name")
                    } else if displayName != nil {
                        Button(role: .destructive) {
                            deleteDisplayName()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("settings.profile.display_name.delete")
                    }
                }
            } header: {
                Text("settings.profile.section_title")
            }

            Section {
                NavigationLink {
                    CatalogExportView { exportedCollectionCount in
                        exportResultMessage = String.localizedStringWithFormat(
                            String(localized: "settings.export.result.message"),
                            exportedCollectionCount
                        )
                    }
                } label: {
                    Label("catalog.export.title", systemImage: "square.and.arrow.up")
                }
                .disabled(isImportExportRunning)

                Button {
                    isImportingDocument = true
                } label: {
                    Label("catalog.import.title", systemImage: "square.and.arrow.down")
                }
                .disabled(isImportExportRunning)
            } header: {
                Text("settings.data.section_title")
            } footer: {
                Text("settings.data.footer")
            }

            Text("common.version \(appVersion) (\(buildNumber))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .onTapGesture(count: 5) {
                    isDeveloperMenuPresented = true
                }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(RootTab.settings.title)
        .onAppear {
            editedDisplayName = displayName ?? ""
        }
        .fileImporter(
            isPresented: $isImportingDocument,
            allowedContentTypes: [.zip]
        ) { result in
            handleImport(result)
        }
        .sheet(item: $importPresentation) { presentation in
            NavigationStack {
                CatalogImportView(bundle: presentation.bundle) { selectedCollectionIDs in
                    handleImportSelection(
                        selectedCollectionIDs,
                        from: presentation.archiveURL,
                        bundle: presentation.bundle
                    )
                }
            }
        }
        .alert("settings.import.completed", isPresented: Binding(
            get: { importResultMessage != nil },
            set: { newValue in
                if !newValue {
                    importResultMessage = nil
                }
            }
        )) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(importResultMessage ?? "")
        }
        .alert("settings.export.completed", isPresented: Binding(
            get: { exportResultMessage != nil },
            set: { newValue in
                if !newValue {
                    exportResultMessage = nil
                }
            }
        )) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(exportResultMessage ?? "")
        }
        .alert("settings.import.error_title", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    importErrorMessage = nil
                }
            }
        )) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
        .sheet(isPresented: $isDeveloperMenuPresented) {
            NavigationStack {
                PhotoAnalysisSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                isDeveloperMenuPresented = false
                            } label: {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
            }
        }
    }

    private var hasUnsavedDisplayNameChanges: Bool {
        editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            != (displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        let number = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        #if DEBUG
        return "\(number) dev"
        #else
        return number
        #endif
    }

    private func saveDisplayName() {
        let trimmedDisplayName = editedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let store = NSUbiquitousKeyValueStore.default

        if trimmedDisplayName.isEmpty {
            displayName = nil
            store.removeObject(forKey: "foliora.profile.displayName")
        } else {
            displayName = trimmedDisplayName
            store.set(trimmedDisplayName, forKey: "foliora.profile.displayName")
            store.removeObject(forKey: "foliora.profile.didSkipIntroduction")
        }
    }

    private func deleteDisplayName() {
        displayName = nil
        editedDisplayName = ""
        NSUbiquitousKeyValueStore.default.removeObject(forKey: "foliora.profile.displayName")
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            isImportExportRunning = true
            Task {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    let bundle = try readCatalogTransferBundle(from: url)

                    await MainActor.run {
                        importPresentation = CatalogImportPresentation(
                            archiveURL: url,
                            bundle: bundle
                        )
                        isImportExportRunning = false
                    }
                } catch {
                    await MainActor.run {
                        importErrorMessage = error.localizedDescription
                        isImportExportRunning = false
                    }
                }
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func readCatalogTransferBundle(from archiveURL: URL) throws -> CatalogTransferBundle {
        let fileManager = FileManager.default
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("catalog-import-preview-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: workDirectory) }

        try CatalogArchiveService().extractArchive(at: archiveURL, to: workDirectory)

        let catalogURL = workDirectory.appendingPathComponent("catalog.json")
        guard fileManager.fileExists(atPath: catalogURL.path) else {
            throw CatalogArchiveService.ArchiveError.missingCatalogJSON
        }

        let data = try Data(contentsOf: catalogURL)
        return try JSONDecoder().decode(CatalogTransferBundle.self, from: data)
    }

    private func handleImportSelection(
        _ selectedCollectionIDs: Set<CollectionID>,
        from archiveURL: URL,
        bundle: CatalogTransferBundle
    ) {
        isImportExportRunning = true
        importErrorMessage = nil
        importResultMessage = nil
        let importSummary = importSummary(
            in: bundle,
            selectedCollectionIDs: selectedCollectionIDs
        )

        Task {
            let accessed = archiveURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    archiveURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let result = try await CatalogJSONPort.importArchive(
                    from: archiveURL,
                    selectedCollectionIDs: selectedCollectionIDs,
                    context: managedObjectContext
                )

                await MainActor.run {
                    var message = String(
                        format: String(localized: "settings.import.result.message"),
                        importSummary
                    )
                    if !result.missingMediaIdentifiers.isEmpty {
                        message += "\n\n"
                        message += String.localizedStringWithFormat(
                            String(localized: "settings.import.result.missing_media"),
                            result.missingMediaIdentifiers.count
                        )
                    }
                    importResultMessage = message
                    isImportExportRunning = false
                }
            } catch {
                await MainActor.run {
                    importErrorMessage = error.localizedDescription
                    isImportExportRunning = false
                }
            }
        }
    }

    private func importSummary(
        in bundle: CatalogTransferBundle,
        selectedCollectionIDs: Set<CollectionID>
    ) -> String {
        let collections = bundle.collections.filter {
            selectedCollectionIDs.contains($0.id)
        }
        let collectionIDs = Set(collections.map(\.id))
        let homeIDs = Set(collections.map(\.homeID))
        let homes = bundle.homes.filter { homeIDs.contains($0.id) }
        let bellItems = bundle.bellItems.filter {
            collectionIDs.contains($0.item.collectionID)
        }
        let parts = [
            importSummaryPart(count: homes.count, key: "settings.import.result.homes"),
            importSummaryPart(count: collections.count, key: "settings.import.result.collections"),
            importSummaryPart(count: bellItems.count, key: "settings.import.result.bells")
        ].compactMap { $0 }

        return parts.joined(separator: ", ")
    }

    private func importSummaryPart(
        count: Int,
        key: String.LocalizationValue
    ) -> String? {
        guard count > 0 else {
            return nil
        }

        return String.localizedStringWithFormat(String(localized: key), count)
    }

}

#if DEBUG
#Preview {
    let container = PreviewContainer.make(.minimal)
    let repository = CoreDataCatalogRepository(
        context: container.viewContext,
        persistentContainer: nil
    )

    NavigationStack {
        SettingsView(
            repository: repository,
            navigate: { _ in },
            displayName: .constant("Alex")
        )
        .environment(\.managedObjectContext, container.viewContext)
    }
}
#endif

private struct SettingsInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

private struct CatalogImportPresentation: Identifiable {
    let id = UUID()
    let archiveURL: URL
    let bundle: CatalogTransferBundle
}
