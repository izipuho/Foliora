import MapKit

struct SuggestedFieldValue<Value: Sendable>: Sendable {
    let value: Value
    let confidence: Double
}

struct GeoPoint: Sendable {
    let label: String
    let name: String
    let coordinate: CLLocationCoordinate2D?
}