import Foundation

struct InMemoryCatalogRepository: CatalogRepository {
    private let bellCollectionID = UUID(uuidString: "3BC496BE-693A-4AAB-9D1B-7F6FB49B7A5A")!
    private let bookCollectionID = UUID(uuidString: "566FBB01-5EE6-4DCC-A5A1-7D7774866D5B")!
    private let officeShelfID = UUID(uuidString: "0B9A28CC-D8B6-4554-A60F-D95B39E4C1A1")!
    private let russiaPlaceID = UUID(uuidString: "B5000000-0000-0000-0000-000000000001")!
    private let francePlaceID = UUID(uuidString: "B5000000-0000-0000-0000-000000000002")!
    private let italyPlaceID = UUID(uuidString: "B5000000-0000-0000-0000-000000000003")!

    func fetchCollections() -> [CollectionSummary] {
        [
            CollectionSummary(
                id: bellCollectionID,
                kind: .bells,
                name: "Колокольчики семьи",
                subtitle: "Первая живая коллекция с полным доступом по приглашениям.",
                itemCount: fetchBellRecords(for: bellCollectionID).count,
                collaboratorCount: fetchCollaborators(for: bellCollectionID).count,
                role: .owner,
                status: .active,
                sharingSummary: "Только по приглашению. Участники входят через Apple ID и получают роль внутри коллекции."
            ),
            CollectionSummary(
                id: bookCollectionID,
                kind: .books,
                name: "Домашняя библиотека",
                subtitle: "Следующий модуль. Будет отдельный UI для книг и собственные сценарии поиска.",
                itemCount: 0,
                collaboratorCount: 2,
                role: .owner,
                status: .planned,
                sharingSummary: "Архитектурно уже учтена как отдельная фиксированная коллекция с собственным интерфейсом."
            )
        ]
    }

    func fetchBellRecords(for collectionID: UUID) -> [BellRecord] {
        guard collectionID == bellCollectionID else {
            return []
        }

        let places = bellPlaces()
        let placesByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })

        return [
            BellRecord(
                item: Item(
                    id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                    collectionID: bellCollectionID,
                    locationID: officeShelfID,
                    title: "Латунный колокольчик из Ярославля",
                    notes: "Куплен в музейной лавке. Звон высокий и очень чистый.",
                    year: 2018,
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
                    year: 2022,
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
                    year: 1960,
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

    func fetchCollaborators(for collectionID: UUID) -> [Collaborator] {
        switch collectionID {
        case bellCollectionID:
            return [
                Collaborator(id: UUID(uuidString: "AAAAAAA1-AAAA-AAAA-AAAA-AAAAAAAAAAA1")!, displayName: "Вы", role: .owner, isCurrentUser: true),
                Collaborator(id: UUID(uuidString: "AAAAAAA2-AAAA-AAAA-AAAA-AAAAAAAAAAA2")!, displayName: "Марина", role: .editor, isCurrentUser: false),
                Collaborator(id: UUID(uuidString: "AAAAAAA3-AAAA-AAAA-AAAA-AAAAAAAAAAA3")!, displayName: "Алексей", role: .contributor, isCurrentUser: false)
            ]
        case bookCollectionID:
            return [
                Collaborator(id: UUID(uuidString: "BBBBBBB1-BBBB-BBBB-BBBB-BBBBBBBBBB11")!, displayName: "Вы", role: .owner, isCurrentUser: true),
                Collaborator(id: UUID(uuidString: "BBBBBBB2-BBBB-BBBB-BBBB-BBBBBBBBBB22")!, displayName: "Нина", role: .editor, isCurrentUser: false)
            ]
        default:
            return []
        }
    }
}
