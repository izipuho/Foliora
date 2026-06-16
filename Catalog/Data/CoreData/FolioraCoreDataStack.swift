import CloudKit
import CoreData
import Foundation

enum FolioraCoreDataStack {
    static let modelName = "Foliora"
    static let cloudKitContainerIdentifier = "iCloud.com.izipuho.FolioraBells"
    nonisolated(unsafe) private static var cloudKitEventObserver: NSObjectProtocol?

    static func makeContainer(inMemory: Bool = false) throws -> NSPersistentCloudKitContainer {
        let model = try managedObjectModel()
        let container = NSPersistentCloudKitContainer(name: modelName, managedObjectModel: model)

        container.persistentStoreDescriptions = try storeDescriptions(inMemory: inMemory)
        var loadError: Error?

        container.loadPersistentStores { _, error in
            if let error {
                loadError = error
            }
        }

        if let loadError {
            throw loadError
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        installCloudKitEventObserver(for: container)

        return container
    }

    private static func managedObjectModel() throws -> NSManagedObjectModel {
        let bundle = Bundle(for: FolioraCoreDataStackBundleToken.self)
        let modelURL = bundle.url(forResource: modelName, withExtension: "momd")
            ?? Bundle.main.url(forResource: modelName, withExtension: "momd")

        guard let modelURL, let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw FolioraCoreDataStackError.modelNotFound(modelName)
        }

        return model
    }

    private static func storeDescriptions(inMemory: Bool) throws -> [NSPersistentStoreDescription] {
        let privateDescription = NSPersistentStoreDescription(url: try storeURL(named: "Private.sqlite"))
        configure(
            privateDescription,
            inMemory: inMemory,
            databaseScope: .private,
            inMemoryName: "Private"
        )

        let sharedDescription = NSPersistentStoreDescription(url: try storeURL(named: "Shared.sqlite"))
        configure(
            sharedDescription,
            inMemory: inMemory,
            databaseScope: .shared,
            inMemoryName: "Shared"
        )

        return [privateDescription, sharedDescription]
    }

    private static func configure(
        _ description: NSPersistentStoreDescription,
        inMemory: Bool,
        databaseScope: CKDatabase.Scope,
        inMemoryName: String
    ) {
        if inMemory {
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null/\(inMemoryName)")
        } else {
            let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerIdentifier)
            options.databaseScope = databaseScope
            description.cloudKitContainerOptions = options
        }

        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    }

    private static func storeURL(named fileName: String) throws -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FolioraBells/CoreData", isDirectory: true)
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
        return baseURL.appendingPathComponent(fileName)
    }

    private static func installCloudKitEventObserver(for container: NSPersistentCloudKitContainer) {
        if let cloudKitEventObserver {
            NotificationCenter.default.removeObserver(cloudKitEventObserver)
        }

        cloudKitEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: nil
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else {
                return
            }
            let deviceName = ProcessInfo.processInfo.hostName
            print(
                "CORE_DATA_CLOUDKIT_EVENT:",
                "device=\(deviceName)",
                "type=\(cloudKitEventTypeDescription(event.type))",
                "storeIdentifier=\(event.storeIdentifier)",
                "startDate=\(event.startDate)",
                "endDate=\(String(describing: event.endDate))",
                "succeeded=\(event.succeeded)",
                "error=\(String(describing: event.error))"
            )
        }
    }

    private static func cloudKitEventTypeDescription(_ type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup:
            return "setup"
        case .import:
            return "import"
        case .export:
            return "export"
        @unknown default:
            return "unknown(\(type.rawValue))"
        }
    }
}

enum FolioraCoreDataStackError: LocalizedError {
    case modelNotFound(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let modelName):
            "Core Data model \(modelName).momd was not found."
        }
    }
}

private final class FolioraCoreDataStackBundleToken {}
