import SwiftUI

struct SettingsView: View {
    let repository: any CatalogRepository
    let navigate: (AppDestination) -> Void

    @State private var exportDocument: CatalogTransferDocument?
    @State private var isExportingDocument = false
    @State private var isImportingDocument = false
    @State private var isImportExportRunning = false
    @State private var importErrorMessage: String?
    @State private var importWarningMessage: String?
    @State private var exportErrorMessage: String?

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
        }
        .listStyle(.insetGrouped)
        .navigationTitle(RootTab.settings.title)
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
}
