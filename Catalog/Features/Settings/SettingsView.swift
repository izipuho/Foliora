import CloudKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    let repository: any CatalogRepository
    let navigate: (AppDestination) -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var exportDocument: CatalogTransferDocument?
    @State private var isExportingDocument = false
    @State private var isImportingDocument = false
    @State private var isImportExportRunning = false
    @State private var importErrorMessage: String?
    @State private var importWarningMessage: String?
    @State private var exportErrorMessage: String?
    @State private var cloudAccountStatusText = "Not checked"
    @State private var cloudUserRecordIDText = "Not checked"
    @State private var cloudStatusErrorMessage: String?
    @State private var cloudStatusLastRefreshText = "Never"
    @State private var isRefreshingCloudStatus = false
    @State private var isShowingPurgeConfirmation = false
    @State private var isPurgingCloudData = false
    @State private var purgeStatusMessage: String?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    HomeView(
                        repository: repository,
                        embedsNavigation: false,
                        navigate: navigate
                    )
                } label: {
                    Label(String(localized: "root_tab.homes"), systemImage: "house")
                }
            } footer: {
                Text(String(localized: "settings.storage.subtitle"))
            }

            Section {
                Button {
                    exportCurrentBackup()
                } label: {
                    Label(String(localized: "settings.data.export"), systemImage: "square.and.arrow.up")
                }
                .disabled(isImportExportRunning)

                Button {
                    isImportingDocument = true
                } label: {
                    Label(String(localized: "settings.data.import"), systemImage: "square.and.arrow.down")
                }
                .disabled(isImportExportRunning)
            } header: {
                Text(String(localized: "settings.data.section_title"))
            } footer: {
                Text(String(localized: "settings.data.footer"))
            }

            Section {
                SettingsInfoRow(title: "App Version", value: appVersion)
                SettingsInfoRow(title: "Build Number", value: buildNumber)
                SettingsInfoRow(title: "Bundle Identifier", value: bundleIdentifier)
                SettingsInfoRow(title: "CloudKit Container", value: CloudKitConfiguration.containerIdentifier)
                SettingsInfoRow(title: "iCloud Account", value: cloudAccountStatusText)
                SettingsInfoRow(title: "CloudKit User Record ID", value: cloudUserRecordIDText)
                SettingsInfoRow(title: "Last Refresh", value: cloudStatusLastRefreshText)

                if let cloudStatusErrorMessage {
                    Text(cloudStatusErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    refreshCloudStatus()
                } label: {
                    if isRefreshingCloudStatus {
                        Label("Refreshing Cloud Status", systemImage: "icloud")
                    } else {
                        Label("Refresh Cloud Status", systemImage: "arrow.clockwise.icloud")
                    }
                }
                .disabled(isRefreshingCloudStatus)
            } header: {
                Text("Cloud Diagnostics")
            } footer: {
                Text("Apple ID/email is not available to apps. CloudKit exposes only account status and user record ID.")
            }

            Section {
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
        .alert(String(localized: "settings.export.error_title"), isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    exportErrorMessage = nil
                }
            }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
        .alert(String(localized: "settings.import.error_title"), isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    importErrorMessage = nil
                }
            }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
        .alert(String(localized: "settings.import.warning_title"), isPresented: Binding(
            get: { importWarningMessage != nil },
            set: { newValue in
                if !newValue {
                    importWarningMessage = nil
                }
            }
        )) {
            Button(String(localized: "common.ok"), role: .cancel) {}
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
            let container = CKContainer(identifier: CloudKitConfiguration.containerIdentifier)

            do {
                let status = try await container.accountStatus()
                let userRecordID = try await container.userRecordID()

                await MainActor.run {
                    cloudAccountStatusText = status.displayText
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
                let actor = CatalogImportExportActor(modelContainer: repository.modelContainer)
                let data = try await actor.exportArchiveData()
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
                    let actor = CatalogImportExportActor(modelContainer: repository.modelContainer)
                    let importResult = try await actor.importArchive(from: url)

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
        try modelContext.fetch(FetchDescriptor<MediaAssetEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<BellTagEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<MembershipEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<BellEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<LocationEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<HomeEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<CollectionEntity>()).forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<PlaceEntity>()).forEach(modelContext.delete)
        try modelContext.save()
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

private extension CKAccountStatus {
    var displayText: String {
        switch self {
        case .available:
            "Available"
        case .noAccount:
            "No Account"
        case .restricted:
            "Restricted"
        case .couldNotDetermine:
            "Could Not Determine"
        case .temporarilyUnavailable:
            "Temporarily Unavailable"
        @unknown default:
            "Unknown"
        }
    }
}
