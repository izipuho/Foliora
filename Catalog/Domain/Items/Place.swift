import Foundation

struct Place: Identifiable, Hashable, Codable {
    let id: UUID
    var displayName: String
    var countryCode: String
    var countryName: String
    var regionName: String?
    var cityName: String?
    var latitude: Double?
    var longitude: Double?
}
