import CoreData
import Foundation

extension CoreDataCatalogRepository {
    func savePerson(_ person: Person) {
        _ = upsertCatalogPerson(person)
        propagatePerson(person)
        saveContext()
    }

    func deletePerson(personID: UUID) {
        let people = fetchEntities(
            named: "PersonEntity",
            predicate: NSPredicate(format: "id == %@", personID as NSUUID)
        )
        guard !people.isEmpty else { return }

        for person in people {
            relatedObjects(person, "bookContributions").forEach(context.delete)
            relatedObjects(person, "photos").forEach(context.delete)
            context.delete(person)
        }

        saveContext()
    }

    @discardableResult
    func upsertCatalogPerson(_ person: Person) -> NSManagedObject {
        let collection = requireCollectionEntity(id: person.collectionID)
        let entity = collectionOwnedEntity(
            named: "PersonEntity",
            id: person.id,
            in: collection
        )

        entity.setValue(person.canonicalID, forKey: "canonicalID")
        entity.setValue(person.givenName, forKey: "givenName")
        entity.setValue(person.familyName, forKey: "familyName")
        entity.setValue(person.middleName, forKey: "middleName")
        entity.setValue(person.birthYear, forKey: "birthYear")
        entity.setValue(person.deathYear, forKey: "deathYear")
        entity.setValue(person.biography, forKey: "biography")
        entity.setValue(person.birthPlace, forKey: "birthPlace")
        entity.setValue(person.deathPlace, forKey: "deathPlace")
        replacePersonPhotos(person.photos, for: entity)
        return entity
    }

    private func propagatePerson(_ person: Person) {
        let copies = canonicalCopies(
            named: "PersonEntity",
            canonicalID: person.canonicalID,
            excluding: person.id
        )

        for copy in copies {
            guard
                let id = copy.value(forKey: "id") as? UUID,
                let collection = copy.value(forKey: "collection") as? NSManagedObject,
                let collectionID = collection.value(forKey: "id") as? UUID
            else {
                continue
            }

            let synchronized = Person(
                id: id,
                canonicalID: person.canonicalID,
                collectionID: collectionID,
                givenName: person.givenName,
                familyName: person.familyName,
                middleName: person.middleName,
                birthYear: person.birthYear,
                deathYear: person.deathYear,
                biography: person.biography,
                birthPlace: person.birthPlace,
                deathPlace: person.deathPlace,
                photos: synchronizedPersonPhotos(person.photos, for: copy)
            )
            _ = upsertCatalogPerson(synchronized)
        }
    }

    private func synchronizedPersonPhotos(
        _ photos: [MediaAsset],
        for person: NSManagedObject
    ) -> [MediaAsset] {
        let existingPhotos = relatedObjects(person, "photos")
            .sorted {
                CoreDataDomainMapper.intValue($0, "sortOrder")
                    < CoreDataDomainMapper.intValue($1, "sortOrder")
            }

        return photos.enumerated().map { index, photo in
            let existing = existingPhotos.indices.contains(index) ? existingPhotos[index] : nil

            return MediaAsset(
                id: existing?.value(forKey: "id") as? UUID ?? UUID(),
                itemID: nil,
                kind: photo.kind,
                displayName: photo.displayName,
                sortOrder: index,
                fileName: photo.fileName,
                mimeType: photo.mimeType,
                byteSize: photo.byteSize,
                checksum: photo.checksum,
                width: photo.width,
                height: photo.height,
                duration: photo.duration,
                metadataJSON: photo.metadataJSON,
                originalData: photo.originalData ?? existing?.value(forKey: "originalData") as? Data
            )
        }
    }

    private func replacePersonPhotos(_ photos: [MediaAsset], for person: NSManagedObject) {
        let existingPhotos = Set(relatedObjects(person, "photos"))
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
            apply(photo.with(sortOrder: index), to: entity)
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
}
