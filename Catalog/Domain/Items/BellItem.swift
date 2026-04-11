import Foundation

struct BellItem: Identifiable, Hashable {
    let id: UUID
    let collectionID: UUID
    var title: String
    var originCountry: String
    var originCity: String
    var material: String
    var year: Int?
    var condition: BellCondition
    var acquisition: AcquisitionMethod
    var notes: String
    var tags: [String]
    var createdBy: String
}

enum BellCondition: String, CaseIterable, Identifiable {
    case pristine = "Отличное"
    case good = "Хорошее"
    case restoration = "Нужно восстановление"

    var id: String { rawValue }
}

enum AcquisitionMethod: String, CaseIterable, Identifiable {
    case travel = "Привезен из поездки"
    case gift = "Подарок"
    case market = "Покупка"
    case family = "Семейная вещь"

    var id: String { rawValue }
}
