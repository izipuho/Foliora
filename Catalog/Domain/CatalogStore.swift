import Foundation

struct CatalogStore {
    let bells: [Bell] = [
        Bell(
            name: "Латунный колокольчик из Ярославля",
            country: "Россия",
            city: "Ярославль",
            material: "Латунь",
            year: 2018,
            condition: .pristine,
            acquisition: .travel,
            notes: "Куплен в музейной лавке. Звон высокий и очень чистый.",
            tags: ["путешествие", "музей", "золотое кольцо"]
        ),
        Bell(
            name: "Керамический колокольчик с лавандой",
            country: "Франция",
            city: "Грас",
            material: "Керамика",
            year: 2022,
            condition: .good,
            acquisition: .gift,
            notes: "Подарок от друзей. На ручке нарисована веточка лаванды.",
            tags: ["подарок", "цветочный", "ручная работа"]
        ),
        Bell(
            name: "Старинный бронзовый колокольчик",
            country: "Италия",
            city: "Флоренция",
            material: "Бронза",
            year: 1960,
            condition: .restoration,
            acquisition: .market,
            notes: "Есть небольшая трещина у язычка, но форма хорошо сохранилась.",
            tags: ["винтаж", "блошиный рынок", "редкость"]
        )
    ]

    var uniqueCountryCount: Int {
        Set(bells.map(\.country)).count
    }

    var uniqueMaterialCount: Int {
        Set(bells.map(\.material)).count
    }
}
