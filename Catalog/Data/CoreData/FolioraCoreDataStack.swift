import CloudKit
import CoreData
import Foundation

/// Groups foliora core data stack values and behavior.
enum FolioraCoreDataStack {
    static let modelName = "Foliora"
    static let cloudKitContainerIdentifier = "iCloud.com.izipuho.FolioraBells"

    @concurrent
    static func makeContainer() async throws -> NSPersistentCloudKitContainer {
        let model = try managedObjectModel()
        var usesCloudKit = true
        var container = NSPersistentCloudKitContainer(name: modelName, managedObjectModel: model)

        do {
            try await loadPersistentStores(into: container, inMemory: false, usesCloudKit: usesCloudKit)
        } catch {
            usesCloudKit = false
            container = NSPersistentCloudKitContainer(name: modelName, managedObjectModel: model)
            try await loadPersistentStores(into: container, inMemory: false, usesCloudKit: usesCloudKit)
        }

        try configureLoadedContainer(container, usesCloudKit: usesCloudKit)

        return container
    }

    static func makeInMemoryContainer() throws -> NSPersistentCloudKitContainer {
        let model = try managedObjectModel()
        let container = NSPersistentCloudKitContainer(name: modelName, managedObjectModel: model)
        try loadPersistentStoresSynchronously(into: container, inMemory: true, usesCloudKit: false)
        try configureLoadedContainer(container, usesCloudKit: false)

        return container
    }

    private static func configureLoadedContainer(
        _ container: NSPersistentCloudKitContainer,
        usesCloudKit: Bool
    ) throws {
        try migrateExistingBellsToItems(in: container)

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        #if DEBUG
        if usesCloudKit {
            do {
                try container.initializeCloudKitSchema(options: [])
                print("CloudKit schema initialized successfully.")
            } catch {
                print("CloudKit schema initialization skipped: \(error)")
            }
        }
        #endif
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
        usesCloudKit: Bool
    ) async throws {
        container.persistentStoreDescriptions = try storeDescriptions(
            inMemory: inMemory,
            usesCloudKit: usesCloudKit
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
            usesCloudKit: usesCloudKit
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

    private static func storeDescriptions(inMemory: Bool, usesCloudKit: Bool) throws -> [NSPersistentStoreDescription] {
        let privateDescription = NSPersistentStoreDescription(url: try storeURL(named: "Private.sqlite"))
        configure(
            privateDescription,
            inMemory: inMemory,
            usesCloudKit: usesCloudKit,
            databaseScope: .private,
            inMemoryName: "Private"
        )

        let sharedDescription = NSPersistentStoreDescription(url: try storeURL(named: "Shared.sqlite"))
        configure(
            sharedDescription,
            inMemory: inMemory,
            usesCloudKit: usesCloudKit,
            databaseScope: .shared,
            inMemoryName: "Shared"
        )

        return [privateDescription, sharedDescription]
    }

    private static func configure(
        _ description: NSPersistentStoreDescription,
        inMemory: Bool,
        usesCloudKit: Bool,
        databaseScope: CKDatabase.Scope,
        inMemoryName: String
    ) {
        if inMemory {
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null/\(inMemoryName)")
        } else if usesCloudKit {
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

    private static func migrateExistingBellsToItems(in container: NSPersistentCloudKitContainer) throws {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        try context.performAndWait {
            try migrateExistingBellsToItems(in: context)
        }
    }

    private static func migrateExistingBellsToItems(in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "BellEntity")
        request.predicate = NSPredicate(format: "item == nil")
        let bells = try context.fetch(request)

        for bell in bells {
            let item = try fetchItem(with: uuidValue(bell, "id"), in: context) ?? makeEntity(named: "ItemEntity", in: context)
            copyCommonAttributes(from: bell, to: item)
            fillMissingRelationships(
                ["collection", "collectionLocation", "location", "originPlace", "mediaAssets"],
                from: bell,
                to: item
            )
            try migrateTags(from: bell, to: item, in: context)
            bell.setValue(item, forKey: "item")
            fillInverseRelationship(from: bell, relationshipName: "item", with: item)
        }

        if context.hasChanges {
            try context.save()
        }
    }

    private static func fetchItem(with id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ItemEntity")
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private static func migrateTags(from bell: NSManagedObject, to item: NSManagedObject, in context: NSManagedObjectContext) throws {
        guard item.entity.relationshipsByName["tags"] != nil else { return }

        var existingKeys = Set(relatedObjects(item, "tags").map(tagKey))
        let tags = relatedObjects(bell, "tags")
            .sorted { intValue($0, "sortOrder") < intValue($1, "sortOrder") }

        for tag in tags {
            let key = tagKey(tag)
            guard existingKeys.insert(key).inserted else { continue }

            let itemTag = try fetchItemTag(matching: tag, in: context) ?? makeEntity(named: "ItemTagEntity", in: context)
            if itemTag.value(forKey: "id") == nil {
                itemTag.setValue(UUID(), forKey: "id")
            }
            itemTag.setValue(tag.value(forKey: "value"), forKey: "value")
            itemTag.setValue(tag.value(forKey: "normalizedName"), forKey: "normalizedName")
            itemTag.setValue(tag.value(forKey: "sortOrder"), forKey: "sortOrder")
            itemTag.setValue(tag.value(forKey: "collection"), forKey: "collection")
            item.mutableSetValue(forKey: "tags").add(itemTag)
            fillInverseRelationship(from: item, relationshipName: "tags", with: itemTag)
        }
    }

    private static func fetchItemTag(matching tag: NSManagedObject, in context: NSManagedObjectContext) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ItemTagEntity")
        request.fetchLimit = 1

        if let collection = tag.value(forKey: "collection") as? NSManagedObject {
            request.predicate = NSPredicate(
                format: "normalizedName == %@ AND collection == %@",
                tag.value(forKey: "normalizedName") as? String ?? "",
                collection
            )
        } else {
            request.predicate = NSPredicate(
                format: "normalizedName == %@ AND collection == nil",
                tag.value(forKey: "normalizedName") as? String ?? ""
            )
        }

        return try context.fetch(request).first
    }

    private static func copyCommonAttributes(from source: NSManagedObject, to destination: NSManagedObject) {
        let destinationAttributes = destination.entity.attributesByName

        for attributeName in source.entity.attributesByName.keys where destinationAttributes[attributeName] != nil {
            destination.setValue(source.value(forKey: attributeName), forKey: attributeName)
        }
    }

    private static func fillMissingRelationships(
        _ relationshipNames: [String],
        from source: NSManagedObject,
        to destination: NSManagedObject
    ) {
        let destinationRelationships = destination.entity.relationshipsByName

        for relationshipName in relationshipNames
        where source.entity.relationshipsByName[relationshipName] != nil && destinationRelationships[relationshipName] != nil {
            let relationship = destinationRelationships[relationshipName]
            if relationship?.isToMany == true {
                let sourceObjects = relatedObjects(source, relationshipName)
                let destinationSet = destination.mutableSetValue(forKey: relationshipName)
                for object in sourceObjects where !destinationSet.contains(object) {
                    destinationSet.add(object)
                }
            } else if destination.value(forKey: relationshipName) == nil,
                      let value = source.value(forKey: relationshipName) {
                destination.setValue(value, forKey: relationshipName)
            }
        }
    }

    private static func fillInverseRelationship(
        from source: NSManagedObject,
        relationshipName: String,
        with destination: NSManagedObject
    ) {
        guard
            let inverseName = source.entity.relationshipsByName[relationshipName]?.inverseRelationship?.name,
            let inverseRelationship = destination.entity.relationshipsByName[inverseName]
        else {
            return
        }

        if inverseRelationship.isToMany {
            destination.mutableSetValue(forKey: inverseName).add(source)
        } else {
            destination.setValue(source, forKey: inverseName)
        }
    }

    private static func makeEntity(named entityName: String, in context: NSManagedObjectContext) -> NSManagedObject {
        NSEntityDescription.insertNewObject(forEntityName: entityName, into: context)
    }

    private static func relatedObjects(_ entity: NSManagedObject, _ key: String) -> [NSManagedObject] {
        if let objects = entity.value(forKey: key) as? Set<NSManagedObject> {
            return Array(objects)
        }

        return (entity.value(forKey: key) as? NSSet)?.allObjects.compactMap { $0 as? NSManagedObject } ?? []
    }

    private static func tagKey(_ tag: NSManagedObject) -> String {
        let normalizedName = tag.value(forKey: "normalizedName") as? String ?? ""
        let collectionID = (tag.value(forKey: "collection") as? NSManagedObject)?.objectID.uriRepresentation().absoluteString ?? ""
        return "\(normalizedName)#\(collectionID)"
    }

    private static func uuidValue(_ entity: NSManagedObject, _ key: String) -> UUID {
        entity.value(forKey: key) as? UUID ?? UUID()
    }

    private static func intValue(_ entity: NSManagedObject, _ key: String) -> Int {
        if let value = entity.value(forKey: key) as? Int {
            return value
        }

        return (entity.value(forKey: key) as? NSNumber)?.intValue ?? 0
    }
}

/// Defines the supported foliora core data stack error values.
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
