import CloudKit
import Combine
import CoreData
import SwiftUI

// Temporary diagnostics screen. Remove after CloudKit sync investigation.
struct CloudSyncDiagnosticsView: View {

    @Environment(\.managedObjectContext) private var managedObjectContext

    @State private var accountStatus = "Not checked"
    @State private var userRecordID = "Not checked"
    @State private var accountError: String?
    @State private var localSaveProbe = LocalSaveProbeResult()
    @State private var eventHistory: [CloudKitEventSummary] = []
    @State private var persistentStores: [PersistentStoreDiagnostics] = []

    private var diagnosticsCloudKitContainer: CKContainer {
        CKContainer.default()
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cloud Sync Diagnostics")
                        .font(.title2.weight(.semibold))
                    Text("Temporary diagnostics screen for Core Data / CloudKit sync.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("CloudKit Account") {
                diagnosticsRow("Account status", accountStatus)
                diagnosticsRow("User record ID", userRecordID)

                if let accountError {
                    diagnosticsRow("Error", accountError)
                }
            }

            Section("Container") {
                diagnosticsRow(
                    "Diagnostics identifier",
                    diagnosticsCloudKitContainer.containerIdentifier ?? "Unavailable"
                )
            }

            Section("Persistent Stores") {
                Button("Refresh Persistent Stores") {
                    refreshPersistentStores()
                }

                if persistentStores.isEmpty {
                    Text("No persistent stores loaded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(persistentStores) { store in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.title)
                                .font(.headline)
                            diagnosticsRow("URL", store.url)
                            diagnosticsRow("Configuration", store.configurationName)
                            diagnosticsRow("Database scope", store.databaseScope)
                            diagnosticsRow("Read-only", store.isReadOnlyText)
                            diagnosticsRow("CloudKit enabled", store.isCloudKitEnabledText)
                            diagnosticsRow("Container identifier", store.containerIdentifier ?? "Unavailable")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Core Data / CloudKit Event History") {
                if eventHistory.isEmpty {
                    Text("No events observed in this app session.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(eventHistory) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.type)
                                .font(.headline)
                            diagnosticsRow("Timestamp", event.timestampText)
                            diagnosticsRow("Type", event.type)
                            diagnosticsRow("Identifier", event.identifier)
                            diagnosticsRow("Status", event.status)
                            if let errorDescription = event.errorDescription {
                                diagnosticsRow("Error", errorDescription)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Last CloudKit Error") {
                if let lastError = eventHistory.first(where: { $0.errorDescription != nil }) {
                    diagnosticsRow("Timestamp", lastError.timestampText)
                    diagnosticsRow("Type", lastError.type)
                    diagnosticsRow("Error", lastError.errorDescription ?? "")
                } else {
                    Text("No CloudKit errors observed in this app session.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Manual Local Save Probe") {
                Button("Create Local Sync Probe") {
                    createLocalSyncProbe()
                }
                Button("Check Probe Export") {
                    checkLocalSyncProbeExport()
                }
                .disabled(localSaveProbe.objectID == nil)

                diagnosticsRow("Object name", localSaveProbe.objectName ?? "None")
                diagnosticsRow("Object ID", localSaveProbe.objectID?.uuidString ?? "None")
                diagnosticsRow("Status", localSaveProbe.status)
                diagnosticsRow("Export status", localSaveProbe.exportStatus)
                diagnosticsRow("Exported recordName", localSaveProbe.exportedRecordName ?? "None")
                diagnosticsRow("Timestamp", localSaveProbe.timestampText)

                if let errorDescription = localSaveProbe.errorDescription {
                    diagnosticsRow("Error", errorDescription)
                }
            }
        }
        .navigationTitle("Cloud Sync Diagnostics")
        .task {
            refreshAccountStatus()
            refreshPersistentStores()
        }
        .onReceive(
            NotificationCenter.default
                .publisher(for: NSPersistentCloudKitContainer.eventChangedNotification)
                .receive(on: DispatchQueue.main)
        ) { notification in
            appendCloudKitEvent(from: notification)
        }
    }

    private func diagnosticsRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func refreshAccountStatus() {
        Task {
            let container = diagnosticsCloudKitContainer

            do {
                let status = try await container.accountStatus()
                let recordID = try await container.userRecordID()

                await MainActor.run {
                    accountStatus = status.diagnosticsText
                    userRecordID = recordID.recordName
                    accountError = nil
                }
            } catch {
                await MainActor.run {
                    accountStatus = "Failed"
                    userRecordID = "Unavailable"
                    accountError = error.localizedDescription
                }
            }
        }
    }

    private func refreshPersistentStores() {
        let stores = managedObjectContext.persistentStoreCoordinator?.persistentStores ?? []
        persistentStores = stores.map(PersistentStoreDiagnostics.init(store:))
    }

    private func appendCloudKitEvent(from notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            return
        }

        eventHistory.insert(CloudKitEventSummary(event: event), at: 0)

        if eventHistory.count > 20 {
            eventHistory = Array(eventHistory.prefix(20))
        }
    }

    private func createLocalSyncProbe() {
        let timestamp = Date.now.timeIntervalSince1970
        let name = "__sync_probe_\(Int(timestamp))"
        let id = UUID()
        let probe = NSEntityDescription.insertNewObject(forEntityName: "HomeEntity", into: managedObjectContext)
        probe.setValue(id, forKey: "id")
        probe.setValue(name, forKey: "name")
        probe.setValue("icloud", forKey: "iconName")
        probe.setValue("Temporary CloudKit sync diagnostics probe.", forKey: "notes")

        do {
            try managedObjectContext.save()
            localSaveProbe = LocalSaveProbeResult(objectID: id, objectName: name, status: "Save success", timestamp: Date.now)
        } catch {
            localSaveProbe = LocalSaveProbeResult(
                objectID: id,
                objectName: name,
                status: "Save failed",
                errorDescription: error.localizedDescription,
                timestamp: Date.now
            )
        }
    }

    private func checkLocalSyncProbeExport() {
        guard let objectID = localSaveProbe.objectID else {
            localSaveProbe.exportStatus = "No probe object"
            localSaveProbe.timestamp = Date.now
            return
        }

        localSaveProbe.exportStatus = "In progress"
        localSaveProbe.exportedRecordName = nil
        localSaveProbe.errorDescription = nil
        localSaveProbe.timestamp = Date.now

        Task {
            let database = diagnosticsCloudKitContainer.privateCloudDatabase
            let query = CKQuery(
                recordType: "CD_HomeEntity",
                predicate: NSPredicate(format: "CD_id == %@", objectID.uuidString)
            )
            let zoneID = CKRecordZone.ID(
                zoneName: "com.apple.coredata.cloudkit.zone",
                ownerName: CKCurrentUserDefaultName
            )

            do {
                let response = try await database.records(matching: query, inZoneWith: zoneID)
                let records = try response.matchResults.map { _, result in
                    try result.get()
                }
                let firstRecord = records.first

                await MainActor.run {
                    localSaveProbe.exportStatus = firstRecord == nil ? "Not found" : "Found"
                    localSaveProbe.exportedRecordName = firstRecord?.recordID.recordName
                    localSaveProbe.timestamp = Date.now
                }
            } catch {
                await MainActor.run {
                    localSaveProbe.exportStatus = "Check failed"
                    localSaveProbe.errorDescription = error.localizedDescription
                    localSaveProbe.timestamp = Date.now
                }
            }
        }
    }
}

private struct LocalSaveProbeResult {
    var objectID: UUID?
    var objectName: String?
    var status = "Not created"
    var exportStatus = "Not checked"
    var exportedRecordName: String?
    var errorDescription: String?
    var timestamp: Date?

    var timestampText: String {
        timestamp?.formatted(date: .abbreviated, time: .standard) ?? "Never"
    }
}

private struct PersistentStoreDiagnostics: Identifiable {
    let id: String
    let title: String
    let url: String
    let configurationName: String
    let databaseScope: String
    let isReadOnly: Bool
    let isCloudKitEnabled: Bool
    let containerIdentifier: String?

    init(store: NSPersistentStore) {
        let fileName = store.url?.lastPathComponent ?? store.identifier ?? "Unknown store"
        let inferredCloudKitConfiguration = Self.cloudKitConfiguration(for: store.url)

        id = store.identifier ?? fileName
        title = fileName
        url = store.url?.path ?? "Unavailable"
        configurationName = store.configurationName
        databaseScope = inferredCloudKitConfiguration?.databaseScope ?? "Unavailable"
        isReadOnly = store.isReadOnly
        isCloudKitEnabled = inferredCloudKitConfiguration != nil || Self.hasCloudKitOptions(store.options)
        containerIdentifier = inferredCloudKitConfiguration?.containerIdentifier
    }

    var isReadOnlyText: String {
        isReadOnly ? "Yes" : "No"
    }

    var isCloudKitEnabledText: String {
        isCloudKitEnabled ? "Yes" : "No"
    }

    private static func cloudKitConfiguration(for url: URL?) -> (databaseScope: String, containerIdentifier: String?)? {
        switch url?.lastPathComponent {
        case "Private.sqlite":
            return ("Private", nil)
        case "Shared.sqlite":
            return ("Shared", nil)
        default:
            return nil
        }
    }

    private static func hasCloudKitOptions(_ options: [AnyHashable: Any]?) -> Bool {
        guard let options else {
            return false
        }

        return options.keys.contains { key in
            String(describing: key).localizedCaseInsensitiveContains("CloudKit")
        }
    }
}

private struct CloudKitEventSummary: Identifiable {
    let id: UUID
    let timestamp: Date
    let type: String
    let identifier: String
    let status: String
    let errorDescription: String?

    init(event: NSPersistentCloudKitContainer.Event) {
        id = event.identifier
        timestamp = Date.now
        type = event.type.diagnosticsText
        identifier = event.identifier.uuidString
        errorDescription = event.error?.localizedDescription

        if event.endDate == nil {
            status = "In progress"
        } else if event.succeeded {
            status = "Succeeded"
        } else {
            status = "Failed"
        }
    }

    var timestampText: String {
        timestamp.formatted(date: .abbreviated, time: .standard)
    }
}

extension CKAccountStatus {
    var diagnosticsText: String {
        switch self {
        case .available:
            return "Available"
        case .couldNotDetermine:
            return "Could not determine"
        case .noAccount:
            return "No account"
        case .restricted:
            return "Restricted"
        case .temporarilyUnavailable:
            return "Temporarily unavailable"
        @unknown default:
            return "Unknown"
        }
    }
}

private extension NSPersistentCloudKitContainer.EventType {
    var diagnosticsText: String {
        switch self {
        case .setup:
            return "Setup"
        case .import:
            return "Import"
        case .export:
            return "Export"
        @unknown default:
            return "Unknown"
        }
    }
}
