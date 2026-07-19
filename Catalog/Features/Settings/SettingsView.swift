import CloudKit
import CoreData
import SwiftUI

struct SettingsView: View {
    let repository: any CatalogRepository
    let navigate: (AppDestination) -> Void

    @Environment(\.managedObjectContext) private var managedObjectContext

    @State private var isImportingDocument = false
    @State private var importPresentation: CatalogImportPresentation?
    @State private var isImportExportRunning = false
    @State private var importErrorMessage: String?
    @State private var importResultMessage: String?
    @State private var exportResultMessage: String?
    @State private var isShowingPurgeConfirmation = false
    @State private var isPurgingCloudData = false
    @State private var purgeStatusMessage: String?
    @State private var isRefreshingCloudStatus = false
    @State private var cloudAccountStatusText = "Not checked"
    @State private var cloudUserRecordIDText = "Not checked"
    @State private var cloudStatusLastRefreshText = "Never"
    @State private var cloudStatusErrorMessage: String?

    var body: some View {
        List {
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

            #if DEBUG
            Section {
                NavigationLink {
                    CloudSyncDiagnosticsView()
                } label: {
                    Label("Cloud Sync Diagnostics", systemImage: "icloud")
                }

                Button(role: .destructive) {
                    isShowingPurgeConfirmation = true
                } label: {
                    if isPurgingCloudData {
                        Label("Purging…", systemImage: "trash")
                    } else {
                        Label("Purge Cloud Data", systemImage: "trash")
                    }
                }
                .disabled(isPurgingCloudData)

                if let purgeStatusMessage {
                    Text(purgeStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(purgeStatusMessage.hasPrefix("Purge failed") ? .red : .secondary)
                }
            } header: {
                Text("Developer Tools")
            }
            #endif

            Text("common.version \(appVersion) (\(buildNumber))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(RootTab.settings.title)
        .task {
            refreshCloudStatus()
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
        .confirmationDialog(
            "Purge Cloud Data?",
            isPresented: $isShowingPurgeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Purge", role: .destructive) {
                purgeCloudData()
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("This will delete all Foliora Bells data from this device and sync deletions to iCloud for this Apple ID.")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    private func refreshCloudStatus() {
        guard !isRefreshingCloudStatus else {
            return
        }

        isRefreshingCloudStatus = true
        cloudStatusErrorMessage = nil

        Task {
            let container = CKContainer.default()

            do {
                let status = try await container.accountStatus()
                let userRecordID = try await container.userRecordID()

                await MainActor.run {
                    cloudAccountStatusText = status.diagnosticsText
                    cloudUserRecordIDText = userRecordID.recordName
                    cloudStatusLastRefreshText = Date.now.formatted(date: .abbreviated, time: .standard)
                    isRefreshingCloudStatus = false
                }
            } catch {
                await MainActor.run {
                    cloudStatusErrorMessage = error.localizedDescription
                    cloudStatusLastRefreshText = Date.now.formatted(date: .abbreviated, time: .standard)
                    isRefreshingCloudStatus = false
                }
            }
        }
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

    private func purgeCloudData() {
        guard !isPurgingCloudData else {
            return
        }

        isPurgingCloudData = true
        purgeStatusMessage = "Purging…"

        Task { @MainActor in
            await Task.yield()

            do {
                try deleteAllCatalogEntities()
                purgeStatusMessage = "Purge completed"
            } catch {
                purgeStatusMessage = "Purge failed: \(error.localizedDescription)"
            }

            isPurgingCloudData = false
        }
    }

    private func deleteAllCatalogEntities() throws {
        try deleteCoreDataEntities(named: "MediaAssetEntity")
        try deleteCoreDataEntities(named: "BellTagEntity")
        try deleteCoreDataEntities(named: "BellEntity")
        try deleteCoreDataEntities(named: "CollectionLocationEntity")
        try deleteCoreDataEntities(named: "CollectionEntity")
        try deleteCoreDataEntities(named: "LocationEntity")
        try deleteCoreDataEntities(named: "PlaceEntity")
        try deleteCoreDataEntities(named: "HomeEntity")
        try managedObjectContext.save()
    }

    private func deleteCoreDataEntities(named entityName: String) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        try managedObjectContext.fetch(request).forEach(managedObjectContext.delete)
    }
}

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
