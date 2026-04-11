import Foundation

struct InMemoryCatalogRepository: CatalogRepository {
    private let bellCollectionID = UUID(uuidString: "3BC496BE-693A-4AAB-9D1B-7F6FB49B7A5A")!
    private let bookCollectionID = UUID(uuidString: "566FBB01-5EE6-4DCC-A5A1-7D7774866D5B")!

    func fetchCollections() -> [CollectionSummary] {
        [
            CollectionSummary(
                id: bellCollectionID,
                kind: .bells,
                name: "Колокольчики семьи",
                subtitle: "Первая живая коллекция с полным доступом по приглашениям.",
                itemCount: fetchBellItems(for: bellCollectionID).count,
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

    func fetchBellItems(for collectionID: UUID) -> [BellItem] {
        guard collectionID == bellCollectionID else {
            return []
        }

        return [
            BellItem(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                collectionID: bellCollectionID,
                title: "Латунный колокольчик из Ярославля",
                originCountry: "Россия",
                originCity: "Ярославль",
                material: "Латунь",
                year: 2018,
                condition: .pristine,
                acquisition: .travel,
                notes: "Куплен в музейной лавке. Звон высокий и очень чистый.",
                tags: ["путешествие", "музей", "золотое кольцо"],
                createdBy: "Вы"
            ),
            BellItem(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                collectionID: bellCollectionID,
                title: "Керамический колокольчик с лавандой",
                originCountry: "Франция",
                originCity: "Грас",
                material: "Керамика",
                year: 2022,
                condition: .good,
                acquisition: .gift,
                notes: "Подарок от друзей. На ручке нарисована веточка лаванды.",
                tags: ["подарок", "цветочный", "ручная работа"],
                createdBy: "Марина"
            ),
            BellItem(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                collectionID: bellCollectionID,
                title: "Старинный бронзовый колокольчик",
                originCountry: "Италия",
                originCity: "Флоренция",
                material: "Бронза",
                year: 1960,
                condition: .restoration,
                acquisition: .market,
                notes: "Есть небольшая трещина у язычка, но форма хорошо сохранилась.",
                tags: ["винтаж", "блошиный рынок", "редкость"],
                createdBy: "Алексей"
            )
        ]
    }

    func fetchCollaborators(for collectionID: UUID) -> [Collaborator] {
        switch collectionID {
        case bellCollectionID:
            return [
                Collaborator(id: UUID(uuidString: "AAAAAAA1-AAAA-AAAA-AAAA-AAAAAAAAAAA1")!, displayName: "Вы", role: .owner, isCurrentUser: true),
                Collaborator(id: UUID(uuidString: "AAAAAAA2-AAAA-AAAA-AAAA-AAAAAAAAAAA2")!, displayName: "Марина", role: .editor, isCurrentUser: false),
                Collaborator(id: UUID(uuidString: "AAAAAAA3-AAAA-AAAA-AAAA-AAAAAAAAAAA3")!, displayName: "Алексей", role: .viewer, isCurrentUser: false)
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
