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
    @State private var localCounts: [LocalCount] = []
    @State private var countsError: String?
    @State private var databaseProbe = CloudKitProbeResult()
    @State private var mirroredRecordsProbe = MirroredRecordsProbeResult()
    @State private var shareProbe = CKShareProbeResult()
    @State private var productionShareProbe = CKShareProbeResult()
    @State private var localSaveProbe = LocalSaveProbeResult()
    @State private var eventHistory: [CloudKitEventSummary] = []

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

            Section("Local Store Counts") {
                Button("Refresh Local Counts") {
                    refreshLocalCounts()
                }

                ForEach(localCounts) { count in
                    diagnosticsRow(count.name, "\(count.value)")
                }

                if let countsError {
                    diagnosticsRow("Error", countsError)
                }
            }

            Section("Private Database Probe") {
                Button("Refresh CloudKit Probe") {
                    refreshCloudKitProbe()
                }

                diagnosticsRow("Status", databaseProbe.status)
                diagnosticsRow("Zone count", databaseProbe.zoneCountText)
                diagnosticsRow("Error code", databaseProbe.errorCode ?? "None")
                diagnosticsRow("Error", databaseProbe.errorDescription ?? "None")
                diagnosticsRow("Last checked", databaseProbe.timestampText)
                //DELETE
                ForEach(databaseProbe.zoneNames, id: \.self) { zoneName in
                    diagnosticsRow("Zone", zoneName)
                }
            }

            Section("Core Data Mirrored Records") {
                Button("Refresh CD_CollectionEntity Records") {
                    refreshMirroredCollectionRecords()
                }
                diagnosticsRow("Status", mirroredRecordsProbe.status)
                diagnosticsRow("CD_CollectionEntity count", mirroredRecordsProbe.countText)
                diagnosticsRow("First recordName", mirroredRecordsProbe.firstRecordName ?? "None")
                diagnosticsRow("First CD_id", mirroredRecordsProbe.firstCDID ?? "None")
                diagnosticsRow("First allKeys", mirroredRecordsProbe.firstAllKeysText)
                diagnosticsRow("Error code", mirroredRecordsProbe.errorCode ?? "None")
                diagnosticsRow("Error", mirroredRecordsProbe.errorDescription ?? "None")
                diagnosticsRow("Last checked", mirroredRecordsProbe.timestampText)
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

                diagnosticsRow("Object name", localSaveProbe.objectName ?? "None")
                diagnosticsRow("Status", localSaveProbe.status)
                diagnosticsRow("Timestamp", localSaveProbe.timestampText)

                if let errorDescription = localSaveProbe.errorDescription {
                    diagnosticsRow("Error", errorDescription)
                }
            }
        }
        .navigationTitle("Cloud Sync Diagnostics")
        .task {
            refreshAccountStatus()
            refreshLocalCounts()
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
            let container = CKContainer.default()

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

    private func refreshLocalCounts() {
        do {
            localCounts = [
                LocalCount(name: "HomeEntity", value: try countCoreDataEntities(named: "HomeEntity")),
                LocalCount(name: "LocationEntity", value: try countCoreDataEntities(named: "LocationEntity")),
                LocalCount(name: "BellEntity", value: try countCoreDataEntities(named: "BellEntity")),
                LocalCount(name: "MediaAssetEntity", value: try countCoreDataEntities(named: "MediaAssetEntity")),
                LocalCount(name: "CollectionEntity", value: try countCoreDataEntities(named: "CollectionEntity")),
                LocalCount(name: "PlaceEntity", value: try countCoreDataEntities(named: "PlaceEntity")),
                LocalCount(name: "TagEntity", value: try countCoreDataEntities(named: "BellTagEntity"))
            ]
            countsError = nil
        } catch {
            countsError = error.localizedDescription
        }
    }

    private func countCoreDataEntities(named entityName: String) throws -> Int {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        return try managedObjectContext.count(for: request)
    }

    private func refreshCloudKitProbe() {
        databaseProbe = CloudKitProbeResult(status: "In progress", timestamp: Date.now)

        CKContainer.default().privateCloudDatabase.fetchAllRecordZones { zones, error in
            DispatchQueue.main.async {
                let zoneNames = zones?
                    .map { $0.zoneID.zoneName }
                    .sorted() ?? []

                if let error {
                    let ckError = error as? CKError
                    databaseProbe = CloudKitProbeResult(
                        status: "Failed",
                        zoneCount: zones?.count,
                        zoneNames: zoneNames,
                        errorCode: ckError.map { "\($0.code.rawValue) (\($0.code))" },
                        errorDescription: error.localizedDescription,
                        timestamp: Date.now
                    )
                } else {
                    databaseProbe = CloudKitProbeResult(
                        status: "Success",
                        zoneCount: zones?.count ?? 0,
                        zoneNames: zoneNames,
                        timestamp: Date.now
                    )
                }
            }
        }
    }

    private func refreshMirroredCollectionRecords() {
        mirroredRecordsProbe = MirroredRecordsProbeResult(status: "In progress", timestamp: Date.now)

        guard let collection = try? fetchFirstCollection() else {
            mirroredRecordsProbe = MirroredRecordsProbeResult(
                status: "Failed",
                errorDescription: "No local CollectionEntity found.",
                timestamp: Date.now
            )
            return
        }

        let collectionID = collection.id.uuidString

        Task {
            let database = CKContainer.default().privateCloudDatabase
            let query = CKQuery(
                recordType: "CD_CollectionEntity",
                predicate: NSPredicate(
                    format: "CD_id == %@",
                    collectionID
                )
            )
            let zoneID = CKRecordZone.ID(
                zoneName: "com.apple.coredata.cloudkit.zone",
                ownerName: CKCurrentUserDefaultName
            )

            do {
                let response = try await database.records(matching: query, inZoneWith: zoneID)
                var matchResults = response.matchResults
                var cursor = response.queryCursor

                while let currentCursor = cursor {
                    let nextResponse = try await database.records(continuingMatchFrom: currentCursor)
                    matchResults.append(contentsOf: nextResponse.matchResults)
                    cursor = nextResponse.queryCursor
                }

                let records = try matchResults.map { _, result in
                    try result.get()
                }
                let firstRecord = records.first

                await MainActor.run {
                    mirroredRecordsProbe = MirroredRecordsProbeResult(
                        status: "Success",
                        count: records.count,
                        firstRecordName: firstRecord?.recordID.recordName,
                        firstCDID: firstRecord?["CD_id"] as? String,
                        firstAllKeys: firstRecord?.allKeys().sorted() ?? [],
                        timestamp: Date.now
                    )
                }
            } catch {
                let ckError = error as? CKError

                await MainActor.run {
                    mirroredRecordsProbe = MirroredRecordsProbeResult(
                        status: "Failed",
                        errorCode: ckError.map { "\($0.code.rawValue) (\($0.code))" },
                        errorDescription: error.localizedDescription,
                        timestamp: Date.now
                    )
                }
            }
        }
    }

    private func createCKShareForCurrentCollection() {
        shareProbe = CKShareProbeResult(status: "In progress", timestamp: Date.now)

        guard let collection = try? fetchFirstCollection() else {
            shareProbe = CKShareProbeResult(
                status: "Failed",
                errorDescription: "No local CollectionEntity found.",
                timestamp: Date.now
            )
            return
        }

        let collectionID = collection.id.uuidString

        Task {
            let database = CKContainer.default().privateCloudDatabase
            let query = CKQuery(
                recordType: "CD_CollectionEntity",
                predicate: NSPredicate(
                    format: "CD_id == %@",
                    collectionID
                )
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

                guard let record = records.first else {
                    await MainActor.run {
                        shareProbe = CKShareProbeResult(
                            status: "Failed",
                            errorDescription: "No CD_CollectionEntity found for \(collectionID).",
                            timestamp: Date.now
                        )
                    }
                    return
                }

                let share = CKShare(rootRecord: record)
                let operation = CKModifyRecordsOperation(recordsToSave: [record, share], recordIDsToDelete: nil)
                operation.savePolicy = .ifServerRecordUnchanged
                operation.modifyRecordsResultBlock = { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            shareProbe = CKShareProbeResult(
                                status: "Success",
                                shareRecordName: share.recordID.recordName,
                                timestamp: Date.now
                            )
                        case .failure(let error):
                            let ckError = error as? CKError
                            shareProbe = CKShareProbeResult(
                                status: "Failed",
                                errorCode: ckError.map { "\($0.code.rawValue) (\($0.code))" },
                                errorDescription: error.localizedDescription,
                                timestamp: Date.now
                            )
                        }
                    }
                }
                database.add(operation)
            } catch {
                let ckError = error as? CKError

                await MainActor.run {
                    shareProbe = CKShareProbeResult(
                        status: "Failed",
                        errorCode: ckError.map { "\($0.code.rawValue) (\($0.code))" },
                        errorDescription: error.localizedDescription,
                        timestamp: Date.now
                    )
                }
            }
        }
    }

    private func createShareUsingProductionService() {
        productionShareProbe = CKShareProbeResult(status: "In progress", timestamp: Date.now)

        guard let collection = try? fetchFirstCollection() else {
            productionShareProbe = CKShareProbeResult(
                status: "Failed",
                errorDescription: "No local CollectionEntity found.",
                timestamp: Date.now
            )
            return
        }

        let collectionID = collection.id
        let service = CloudKitCollectionSharingService(
            container: CKContainer.default()
        )

        Task {
            do {
                let share = try await service.createShare(for: collectionID, title: collection.title)

                await MainActor.run {
                    productionShareProbe = CKShareProbeResult(
                        status: "Success",
                        shareRecordName: share.recordID.recordName,
                        timestamp: Date.now
                    )
                }
            } catch {
                let ckError = error as? CKError

                await MainActor.run {
                    productionShareProbe = CKShareProbeResult(
                        status: "Failed",
                        errorCode: ckError.map { "\($0.code.rawValue) (\($0.code))" },
                        errorDescription: error.localizedDescription,
                        timestamp: Date.now
                    )
                }
            }
        }
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
        let probe = NSEntityDescription.insertNewObject(forEntityName: "HomeEntity", into: managedObjectContext)
        probe.setValue(UUID(), forKey: "id")
        probe.setValue(name, forKey: "name")
        probe.setValue("icloud", forKey: "iconName")
        probe.setValue("Temporary CloudKit sync diagnostics probe.", forKey: "notes")

        do {
            try managedObjectContext.save()
            localSaveProbe = LocalSaveProbeResult(objectName: name, status: "Save success", timestamp: Date.now)
            refreshLocalCounts()
        } catch {
            localSaveProbe = LocalSaveProbeResult(
                objectName: name,
                status: "Save failed",
                errorDescription: error.localizedDescription,
                timestamp: Date.now
            )
        }
    }

    private func fetchFirstCollection() throws -> (id: UUID, title: String)? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CollectionEntity")
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true)]

        guard let entity = try managedObjectContext.fetch(request).first,
              let id = entity.value(forKey: "id") as? UUID else {
            return nil
        }

        return (
            id: id,
            title: entity.value(forKey: "title") as? String ?? ""
        )
    }
}

private struct CKShareProbeResult {
    var status = "Not checked"
    var shareRecordName: String?
    var errorCode: String?
    var errorDescription: String?
    var timestamp: Date?

    var timestampText: String {
        timestamp?.formatted(date: .abbreviated, time: .standard) ?? "Never"
    }
}

private struct MirroredRecordsProbeResult {
    var status = "Not checked"
    var count: Int?
    var firstRecordName: String?
    var firstCDID: String?
    var firstAllKeys: [String] = []
    var errorCode: String?
    var errorDescription: String?
    var timestamp: Date?

    var countText: String {
        count.map(String.init) ?? "Not checked"
    }

    var firstAllKeysText: String {
        firstAllKeys.isEmpty ? "None" : firstAllKeys.joined(separator: ", ")
    }

    var timestampText: String {
        timestamp?.formatted(date: .abbreviated, time: .standard) ?? "Never"
    }
}

private struct LocalCount: Identifiable {
    let id = UUID()
    let name: String
    let value: Int
}

private struct CloudKitProbeResult {
    var status = "Not checked"
    var zoneCount: Int?
    var zoneNames: [String] = []
    var errorCode: String?
    var errorDescription: String?
    var timestamp: Date?

    var zoneCountText: String {
        zoneCount.map(String.init) ?? "Not checked"
    }

    var timestampText: String {
        timestamp?.formatted(date: .abbreviated, time: .standard) ?? "Never"
    }
}

private struct LocalSaveProbeResult {
    var objectName: String?
    var status = "Not created"
    var errorDescription: String?
    var timestamp: Date?

    var timestampText: String {
        timestamp?.formatted(date: .abbreviated, time: .standard) ?? "Never"
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
