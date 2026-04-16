import Foundation

@MainActor
final class InMemoryCatalogRepository: CatalogRepository {
    private let homeID = UUID(uuidString: "A1000000-0000-0000-0000-000000000001")!
    private let bellCollectionID = UUID(uuidString: "3BC496BE-693A-4AAB-9D1B-7F6FB49B7A5A")!
    private let floorID = UUID(uuidString: "A2000000-0000-0000-0000-000000000001")!
    private let officeRoomID = UUID(uuidString: "A2000000-0000-0000-0000-000000000002")!
    private let glassCabinetID = UUID(uuidString: "A2000000-0000-0000-0000-000000000003")!
    private let officeShelfID = UUID(uuidString: "0B9A28CC-D8B6-4554-A60F-D95B39E4C1A1")!
    private let russiaPlaceID = UUID(uuidString: "B5000000-0000-0000-0000-000000000001")!
    private let francePlaceID = UUID(uuidString: "B5000000-0000-0000-0000-000000000002")!
    private let italyPlaceID = UUID(uuidString: "B5000000-0000-0000-0000-000000000003")!

    func fetchHomes() -> [Home] {
        [
            Home(
                id: homeID,
                name: "Main Home",
                notes: "Primary living space for household collections."
            )
        ]
    }

    func fetchLocations(in homeID: UUID) -> [Location] {
        guard homeID == self.homeID else {
            return []
        }

        return [
            Location(
                id: floorID,
                homeID: homeID,
                parentLocationID: nil,
                kind: .floor,
                name: "Second Floor",
                notes: "Upper level with office and reading space."
            ),
            Location(
                id: officeRoomID,
                homeID: homeID,
                parentLocationID: floorID,
                kind: .room,
                name: "Office",
                notes: "Main room for display cabinets and work desk."
            ),
            Location(
                id: glassCabinetID,
                homeID: homeID,
                parentLocationID: officeRoomID,
                kind: .cabinet,
                name: "Glass Cabinet",
                notes: "Tall display cabinet for fragile pieces."
            ),
            Location(
                id: officeShelfID,
                homeID: homeID,
                parentLocationID: glassCabinetID,
                kind: .shelf,
                name: "Top Shelf",
                notes: "Top shelf used for the bell collection."
            )
        ]
    }

    func fetchDomainCollections(in homeID: UUID) -> [Collection] {
        guard homeID == self.homeID else {
            return []
        }

        return [
            Collection(
                id: bellCollectionID,
                homeID: homeID,
                kind: .bells,
                title: "Колокольчики семьи",
                notes: "Первая живая коллекция с полным доступом по приглашениям.",
                backgroundStyle: .amber
            )
        ]
    }

    func fetchMemberships(for collectionID: UUID) -> [Membership] {
        switch collectionID {
        case bellCollectionID:
            return [
                Membership(id: UUID(uuidString: "C1000000-0000-0000-0000-000000000001")!, collectionID: bellCollectionID, userID: "me", role: .owner, status: .active),
                Membership(id: UUID(uuidString: "C1000000-0000-0000-0000-000000000002")!, collectionID: bellCollectionID, userID: "marina", role: .editor, status: .active),
                Membership(id: UUID(uuidString: "C1000000-0000-0000-0000-000000000003")!, collectionID: bellCollectionID, userID: "alexey", role: .contributor, status: .active)
            ]
        default:
            return []
        }
    }

    func fetchCollections() -> [CollectionSummary] {
        fetchDomainCollections(in: homeID).map { collection in
            let memberships = fetchMemberships(for: collection.id)
            let activeMemberships = memberships.filter { $0.status == .active }

            return CollectionSummary(
                id: collection.id,
                homeID: collection.homeID,
                kind: collection.kind,
                name: collection.title,
                subtitle: collection.notes,
                backgroundStyle: collection.backgroundStyle,
                itemCount: collection.kind == .bells ? fetchBellRecords(for: collection.id).count : 0,
                collaboratorCount: activeMemberships.count,
                role: activeMemberships.first(where: { $0.userID == "me" })?.role ?? .viewer,
                status: collection.kind == .bells ? .active : .planned,
                sharingSummary: "Invitation-only. Members join with Apple ID and receive a role inside the collection."
            )
        }
    }

    func fetchBellRecords(for collectionID: UUID) -> [BellRecord] {
        guard collectionID == bellCollectionID else {
            return []
        }

        let places = bellPlaces()
        let placesByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        let locations = fetchLocations(in: homeID)
        let locationsByID = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
        let mediaAssetsByItemID = Dictionary(grouping: bellMediaAssets(), by: \.itemID)

        return [
            BellRecord(
                item: Item(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    collectionID: bellCollectionID,
                    locationID: officeShelfID,
                    title: "Латунный колокольчик из Ярославля",
                    notes: "Куплен в музейной лавке. Звон высокий и очень чистый.",
                    acquiredYear: 2018,
                    condition: .mint,
                    acquisitionMethod: .bought
                ),
                details: BellDetails(
                    itemID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    originPlaceID: russiaPlaceID,
                    material: .brass,
                    customMaterialName: nil
                ),
                originPlace: placesByID[russiaPlaceID],
                storageLocation: locationsByID[officeShelfID],
                storagePath: locationPath(for: officeShelfID, locationsByID: locationsByID),
                mediaAssets: mediaAssetsByItemID[UUID(uuidString: "11111111-1111-1111-1111-111111111111")!] ?? [],
                createdBy: "Вы",
                tags: ["путешествие", "музей", "золотое кольцо"]
            ),
            BellRecord(
                item: Item(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    collectionID: bellCollectionID,
                    locationID: officeShelfID,
                    title: "Керамический колокольчик с лавандой",
                    notes: "Подарок от друзей. На ручке нарисована веточка лаванды.",
                    acquiredYear: 2022,
                    condition: .good,
                    acquisitionMethod: .gifted
                ),
                details: BellDetails(
                    itemID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    originPlaceID: francePlaceID,
                    material: .ceramic,
                    customMaterialName: nil
                ),
                originPlace: placesByID[francePlaceID],
                storageLocation: locationsByID[officeShelfID],
                storagePath: locationPath(for: officeShelfID, locationsByID: locationsByID),
                mediaAssets: mediaAssetsByItemID[UUID(uuidString: "22222222-2222-2222-2222-222222222222")!] ?? [],
                createdBy: "Марина",
                tags: ["подарок", "цветочный", "ручная работа"]
            ),
            BellRecord(
                item: Item(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    collectionID: bellCollectionID,
                    locationID: officeShelfID,
                    title: "Старинный бронзовый колокольчик",
                    notes: "Есть небольшая трещина у язычка, но форма хорошо сохранилась.",
                    acquiredYear: 1960,
                    condition: .needsRestoration,
                    acquisitionMethod: .bought
                ),
                details: BellDetails(
                    itemID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    originPlaceID: italyPlaceID,
                    material: .bronze,
                    customMaterialName: nil
                ),
                originPlace: placesByID[italyPlaceID],
                storageLocation: locationsByID[officeShelfID],
                storagePath: locationPath(for: officeShelfID, locationsByID: locationsByID),
                mediaAssets: mediaAssetsByItemID[UUID(uuidString: "33333333-3333-3333-3333-333333333333")!] ?? [],
                createdBy: "Алексей",
                tags: ["винтаж", "блошиный рынок", "редкость"]
            )
        ]
    }

    private func bellPlaces() -> [Place] {
        [
            Place(
                id: russiaPlaceID,
                displayName: "Yaroslavl, Russia",
                countryCode: "RU",
                countryName: "Russia",
                regionName: "Yaroslavl Oblast",
                cityName: "Yaroslavl",
                latitude: 57.6261,
                longitude: 39.8845
            ),
            Place(
                id: francePlaceID,
                displayName: "Grasse, France",
                countryCode: "FR",
                countryName: "France",
                regionName: "Provence-Alpes-Cote d'Azur",
                cityName: "Grasse",
                latitude: 43.6599,
                longitude: 6.9246
            ),
            Place(
                id: italyPlaceID,
                displayName: "Florence, Italy",
                countryCode: "IT",
                countryName: "Italy",
                regionName: "Tuscany",
                cityName: "Florence",
                latitude: 43.7696,
                longitude: 11.2558
            )
        ]
    }

    private func bellMediaAssets() -> [MediaAsset] {
        [
            MediaAsset(
                id: UUID(uuidString: "D1000000-0000-0000-0000-000000000001")!,
                itemID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                kind: .photo,
                localIdentifier: "bell-photo-1",
                displayName: "Bell Photo",
                sortOrder: 0
            ),
            MediaAsset(
                id: UUID(uuidString: "D1000000-0000-0000-0000-000000000002")!,
                itemID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                kind: .model3D,
                localIdentifier: "bell-model-1",
                displayName: "Bell Model",
                sortOrder: 1
            ),
            MediaAsset(
                id: UUID(uuidString: "D2000000-0000-0000-0000-000000000001")!,
                itemID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                kind: .photo,
                localIdentifier: "bell-photo-2",
                displayName: "Lavender Bell Photo",
                sortOrder: 0
            ),
            MediaAsset(
                id: UUID(uuidString: "D3000000-0000-0000-0000-000000000001")!,
                itemID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                kind: .document,
                localIdentifier: "bell-note-1",
                displayName: "Condition Notes",
                sortOrder: 0
            )
        ]
    }

    private func locationPath(for locationID: UUID?, locationsByID: [UUID: Location]) -> String {
        guard let locationID, let location = locationsByID[locationID] else {
            return "Unassigned"
        }

        var parts = [location.name]
        var currentParentID = location.parentLocationID

        while let parentID = currentParentID, let parent = locationsByID[parentID] {
            parts.insert(parent.name, at: 0)
            currentParentID = parent.parentLocationID
        }

        return parts.joined(separator: " / ")
    }

    func fetchCollaborators(for collectionID: UUID) -> [Collaborator] {
        let users = userDirectory()

        return fetchMemberships(for: collectionID)
            .filter { $0.status == .active }
            .map { membership in
                Collaborator(
                    id: membership.id,
                    displayName: users[membership.userID] ?? membership.userID,
                    role: membership.role,
                    isCurrentUser: membership.userID == "me"
                )
            }
    }

    private func userDirectory() -> [String: String] {
        [
            "me": "Вы",
            "marina": "Марина",
            "alexey": "Алексей",
            "nina": "Нина"
        ]
    }

    func saveHome(_ home: Home) {}

    func saveLocations(_ locations: [Location], in homeID: UUID) {}

    func deleteHome(homeID: UUID) {}

    func saveCollection(_ collection: Collection) {}

    func deleteCollection(collectionID: UUID) {}

    func saveBellRecord(_ bell: BellRecord) {}

    func deleteBellRecord(bellID: UUID) {}
}
