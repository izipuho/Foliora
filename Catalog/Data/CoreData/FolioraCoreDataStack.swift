import CloudKit
import CoreData
import Foundation

/// Groups foliora core data stack values and behavior.
enum FolioraCoreDataStack {
    static let modelName = "Foliora"
    static let appGroupIdentifier = "group.com.izipuho.Foliora"

    @concurrent
    static func makeContainer() async throws -> NSPersistentCloudKitContainer {
        let model = try managedObjectModel()
        var usesCloudKit = true
        var container = NSPersistentCloudKitContainer(name: modelName, managedObjectModel: model)
        guard let cloudKitContainerIdentifier = container
            .persistentStoreDescriptions
            .first?
            .cloudKitContainerOptions?
            .containerIdentifier
        else {
            throw FolioraCoreDataStackError.cloudKitContainerUnavailable
        }

        do {
            try await loadPersistentStores(
                into: container,
                inMemory: false,
                usesCloudKit: usesCloudKit,
                cloudKitContainerIdentifier: cloudKitContainerIdentifier
            )
        } catch {
            usesCloudKit = false
            container = NSPersistentCloudKitContainer(name: modelName, managedObjectModel: model)
            try await loadPersistentStores(
                into: container,
                inMemory: false,
                usesCloudKit: usesCloudKit,
                cloudKitContainerIdentifier: cloudKitContainerIdentifier
            )
        }

        configureLoadedContainer(container)

        return container
    }

    static func makeInMemoryContainer() throws -> NSPersistentCloudKitContainer {
        let model = try managedObjectModel()
        let container = NSPersistentCloudKitContainer(name: modelName, managedObjectModel: model)
        try loadPersistentStoresSynchronously(into: container, inMemory: true, usesCloudKit: false)
        configureLoadedContainer(container)

        return container
    }

    private static func configureLoadedContainer(
        _ container: NSPersistentCloudKitContainer
    ) {
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
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

    private static func loadPersistentStores(
        into container: NSPersistentCloudKitContainer,
        inMemory: Bool,
        usesCloudKit: Bool,
        cloudKitContainerIdentifier: String
    ) async throws {
        container.persistentStoreDescriptions = try storeDescriptions(
            inMemory: inMemory,
            usesCloudKit: usesCloudKit,
            cloudKitContainerIdentifier: cloudKitContainerIdentifier
        )

        try await withCheckedThrowingContinuation { continuation in
            let storeCount = container.persistentStoreDescriptions.count
            guard storeCount > 0 else {
                continuation.resume()
                return
            }

            let lock = NSLock()
            var remainingStores = storeCount
            var loadError: Error?

            container.loadPersistentStores { _, error in
                lock.lock()
                if loadError == nil {
                    loadError = error
                }
                remainingStores -= 1
                let isComplete = remainingStores == 0
                let result = loadError
                lock.unlock()

                guard isComplete else { return }

                if let result {
                    continuation.resume(throwing: result)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func loadPersistentStoresSynchronously(
        into container: NSPersistentCloudKitContainer,
        inMemory: Bool,
        usesCloudKit: Bool
    ) throws {
        container.persistentStoreDescriptions = try storeDescriptions(
            inMemory: inMemory,
            usesCloudKit: usesCloudKit,
            cloudKitContainerIdentifier: nil
        )

        let storeCount = container.persistentStoreDescriptions.count
        guard storeCount > 0 else { return }

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var remainingStores = storeCount
        var loadError: Error?

        container.loadPersistentStores { _, error in
            lock.lock()
            if loadError == nil {
                loadError = error
            }
            remainingStores -= 1
            let isComplete = remainingStores == 0
            lock.unlock()

            if isComplete {
                semaphore.signal()
            }
        }

        semaphore.wait()

        if let loadError {
            throw loadError
        }
    }

    private static func storeDescriptions(
        inMemory: Bool,
        usesCloudKit: Bool,
        cloudKitContainerIdentifier: String?
    ) throws -> [NSPersistentStoreDescription] {
        let privateDescription = NSPersistentStoreDescription(url: try storeURL(named: "Private.sqlite"))
        configure(
            privateDescription,
            inMemory: inMemory,
            usesCloudKit: usesCloudKit,
            cloudKitContainerIdentifier: cloudKitContainerIdentifier,
            databaseScope: .private,
            inMemoryName: "Private"
        )

        let sharedDescription = NSPersistentStoreDescription(url: try storeURL(named: "Shared.sqlite"))
        configure(
            sharedDescription,
            inMemory: inMemory,
            usesCloudKit: usesCloudKit,
            cloudKitContainerIdentifier: cloudKitContainerIdentifier,
            databaseScope: .shared,
            inMemoryName: "Shared"
        )

        return [privateDescription, sharedDescription]
    }

    private static func configure(
        _ description: NSPersistentStoreDescription,
        inMemory: Bool,
        usesCloudKit: Bool,
        cloudKitContainerIdentifier: String?,
        databaseScope: CKDatabase.Scope,
        inMemoryName: String
    ) {
        if inMemory {
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null/\(inMemoryName)")
        } else if usesCloudKit {
            guard let cloudKitContainerIdentifier else {
                return
            }
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
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw FolioraCoreDataStackError.appGroupContainerUnavailable
        }

        let baseURL = containerURL.appendingPathComponent("CoreData", isDirectory: true)
        try FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true
        )

        return baseURL.appendingPathComponent(fileName)
    }
}

/// Defines the supported foliora core data stack error values.
enum FolioraCoreDataStackError: LocalizedError {
    case modelNotFound(String)
    case appGroupContainerUnavailable
    case cloudKitContainerUnavailable

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let modelName):
            "Core Data model \(modelName).momd was not found."
        case .appGroupContainerUnavailable:
            "Foliora App Group container is unavailable."
        case .cloudKitContainerUnavailable:
            "CloudKit container from Core Data store description is unavailable."
        }
    }
}

private final class FolioraCoreDataStackBundleToken {}
