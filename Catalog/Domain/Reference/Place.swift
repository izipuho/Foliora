import Foundation

/// Represents place data and behavior.
struct Place: Identifiable, Hashable, Codable {
    let id: UUID
    let canonicalID: UUID
    let collectionID: UUID?
    var displayName: String
    var countryCode: String
    var countryName: String
    var regionName: String?
    var cityName: String?
    var latitude: Double?
    var longitude: Double?

    init(
        id: UUID,
        canonicalID: UUID? = nil,
        collectionID: UUID? = nil,
        displayName: String,
        countryCode: String,
        countryName: String,
        regionName: String? = nil,
        cityName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.canonicalID = canonicalID ?? id
        self.collectionID = collectionID
        self.displayName = displayName
        self.countryCode = countryCode
        self.countryName = countryName
        self.regionName = regionName
        self.cityName = cityName
        self.latitude = latitude
        self.longitude = longitude
    }
}
