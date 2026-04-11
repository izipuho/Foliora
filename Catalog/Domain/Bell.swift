import Foundation

struct Bell: Identifiable, Hashable {
    let id: UUID
    var name: String
    var country: String
    var city: String
    var material: String
    var year: Int?
    var condition: BellCondition
    var acquisition: AcquisitionMethod
    var notes: String
    var tags: [String]

    init(
        id: UUID = UUID(),
        name: String,
        country: String,
        city: String,
        material: String,
        year: Int? = nil,
        condition: BellCondition,
        acquisition: AcquisitionMethod,
        notes: String,
        tags: [String]
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.city = city
        self.material = material
        self.year = year
        self.condition = condition
        self.acquisition = acquisition
        self.notes = notes
        self.tags = tags
    }
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
