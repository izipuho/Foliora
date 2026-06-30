import CloudKit
import CoreData
import SwiftUI

struct SettingsView: View {
    let repository: any CatalogRepository
    let navigate: (AppDestination) -> Void

    @Environment(\.managedObjectContext) private var managedObjectContext

    @State private var exportDocument: CatalogTransferDocument?
    @State private var isExportingDocument = false
    @State private var isImportingDocument = false
    @State private var isImportExportRunning = false
    @State private var importErrorMessage: String?
    @State private var importWarningMessage: String?
    @State private var exportErrorMessage: String?
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
                Button {
                    exportCurrentBackup()
                } label: {
                    Label("settings.data.export", systemImage: "square.and.arrow.up")
                }
                .disabled(isImportExportRunning)

                Button {
                    isImportingDocument = true
                } label: {
                    Label("settings.data.import", systemImage: "square.and.arrow.down")
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
        .fileExporter(
            isPresented: $isExportingDocument,
            document: exportDocument,
            contentType: .zip,
            defaultFilename: "catalog-export"
        ) { result in
            if case .failure(let error) = result {
                exportErrorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $isImportingDocument,
            allowedContentTypes: [.zip]
        ) { result in
            handleImport(result)
        }
        .alert("settings.export.error_title", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    exportErrorMessage = nil
                }
            }
        )) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
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
        .alert("settings.import.warning_title", isPresented: Binding(
            get: { importWarningMessage != nil },
            set: { newValue in
                if !newValue {
                    importWarningMessage = nil
                }
            }
        )) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(importWarningMessage ?? "")
        }
        .confirmationDialog(
            "Purge Cloud Data?",
            isPresented: $isShowingPurgeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Purge", role: .destructive) {
                purgeCloudData()
            }
            Button("Cancel", role: .cancel) {}
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

    private func exportCurrentBackup() {
        isImportExportRunning = true
        Task {
            do {
                let data = try await CatalogJSONPort.exportArchiveData(
                    context: managedObjectContext
                )
                await MainActor.run {
                    exportDocument = CatalogTransferDocument(data: data)
                    isExportingDocument = true
                    isImportExportRunning = false
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = error.localizedDescription
                    isImportExportRunning = false
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
                    let importResult = try await CatalogJSONPort.importArchive(
                        from: url,
                        context: managedObjectContext
                    )

                    await MainActor.run {
                        if !importResult.missingMediaIdentifiers.isEmpty {
                            importWarningMessage = String(localized: "settings.import.warning.missing_media")
                        }
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
