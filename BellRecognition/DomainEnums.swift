enum BellMaterial: String, CaseIterable, Hashable, Identifiable, Codable {
    case unknown
    case metall
    case brass
    case bronze
    case silver
    case gold
    case ceramic
    case porcelain
    case glass
    case wood
    case other

    var id: String {
        rawValue
    }
}

enum ItemCondition: String, CaseIterable, Identifiable, Codable {
    case mint = "Mint"
    case good = "Good"
    case worn = "Worn"
    case damaged = "Damaged"
    case needsRestoration = "Needs Restoration"

    var id: String {
        rawValue
    }
}