import CoreData
import Foundation

extension CoreDataCatalogRepository {
    func savePerson(_ person: Person) {
        _ = upsertCatalogPerson(person)
        saveContext()
    }

    func deletePerson(personID: UUID) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PersonEntity")
        request.predicate = NSPredicate(format: "id == %@", personID as NSUUID)
        let people = (try? context.fetch(request)) ?? []
        guard !people.isEmpty else { return }

        for person in people {
            personRelatedObjects(person, "bookContributions").forEach(context.delete)
            personRelatedObjects(person, "photos").forEach(context.delete)
            context.delete(person)
        }

        saveContext()
    }

    @discardableResult
    func upsertCatalogPerson(_ person: Person) -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PersonEntity")
        request.predicate = NSPredicate(format: "id == %@", person.id as NSUUID)
        request.fetchLimit = 1

        let entity = (try? context.fetch(request))?.first ?? makeEntity(named: "PersonEntity")
        entity.setValue(person.id, forKey: "id")
        entity.setValue(person.givenName, forKey: "givenName")
        entity.setValue(person.familyName, forKey: "familyName")
        entity.setValue(person.middleName, forKey: "middleName")
        entity.setValue(person.birthYear, forKey: "birthYear")
        entity.setValue(person.deathYear, forKey: "deathYear")
        entity.setValue(person.biography, forKey: "biography")
        entity.setValue(person.birthPlace.map(upsertCatalogPlace), forKey: "birthPlace")
        entity.setValue(person.deathPlace.map(upsertCatalogPlace), forKey: "deathPlace")
        replacePersonPhotos(person.photos, for: entity)
        return entity
    }

    private func upsertCatalogPlace(_ place: Place) -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "PlaceEntity")
        request.predicate = NSPredicate(format: "id == %@", place.id as NSUUID)
        request.fetchLimit = 1

        let entity = (try? context.fetch(request))?.first ?? makeEntity(named: "PlaceEntity")
        entity.setValue(place.id, forKey: "id")
        entity.setValue(place.displayName, forKey: "displayName")
        entity.setValue(place.countryCode, forKey: "countryCode")
        entity.setValue(place.countryName, forKey: "countryName")
        entity.setValue(place.regionName, forKey: "regionName")
        entity.setValue(place.cityName, forKey: "cityName")
        entity.setValue(place.latitude, forKey: "latitude")
        entity.setValue(place.longitude, forKey: "longitude")
        return entity
    }

    private func replacePersonPhotos(_ photos: [MediaAsset], for person: NSManagedObject) {
        let existingPhotos = Set(personRelatedObjects(person, "photos"))
        let incomingIDs = Set(photos.map(\.id))
        var existingByID: [UUID: NSManagedObject] = [:]

        for entity in existingPhotos {
            guard let id = entity.value(forKey: "id") as? UUID else { continue }
            existingByID[id] = entity
        }

        let updatedPhotos = photos.enumerated().map { index, photo -> NSManagedObject in
            let entity = existingByID[photo.id] ?? makeEntity(named: "MediaAssetEntity")
            if entity.objectID.persistentStore == nil,
               let store = person.objectID.persistentStore {
                context.assign(entity, to: store)
            }
            applyReferencePhoto(photo.with(sortOrder: index), to: entity)
            entity.setValue(person, forKey: "person")
            return entity
        }

        for entity in existingPhotos {
            guard
                let id = entity.value(forKey: "id") as? UUID,
                !incomingIDs.contains(id)
            else {
                continue
            }
            context.delete(entity)
        }

        person.setValue(Set(updatedPhotos), forKey: "photos")
    }

    private func applyReferencePhoto(_ asset: MediaAsset, to entity: NSManagedObject) {
        let isNewEntity = entity.value(forKey: "id") == nil
        let existingChecksum = entity.value(forKey: "checksum") as? String
        let shouldUpdateOriginalData = isNewEntity || existingChecksum != asset.checksum

        entity.setValue(asset.id, forKey: "id")
        entity.setValue(asset.kind.rawValue, forKey: "kind")
        entity.setValue(asset.localIdentifier, forKey: "localIdentifier")
        entity.setValue(asset.displayName, forKey: "displayName")
        entity.setValue(asset.sortOrder, forKey: "sortOrder")
        entity.setValue(asset.fileName, forKey: "fileName")
        entity.setValue(asset.mimeType, forKey: "mimeType")
        entity.setValue(asset.byteSize, forKey: "byteSize")
        entity.setValue(asset.checksum, forKey: "checksum")
        entity.setValue(asset.width, forKey: "width")
        entity.setValue(asset.height, forKey: "height")
        entity.setValue(asset.duration, forKey: "duration")
        entity.setValue(asset.metadataJSON, forKey: "metadataJSON")
        if shouldUpdateOriginalData {
            entity.setValue(asset.originalData, forKey: "originalData")
        }
    }

    private func personRelatedObjects(_ entity: NSManagedObject, _ key: String) -> [NSManagedObject] {
        if let objects = entity.value(forKey: key) as? Set<NSManagedObject> {
            return Array(objects)
        }

        return (entity.value(forKey: key) as? NSSet)?.allObjects.compactMap { $0 as? NSManagedObject } ?? []
    }
}
