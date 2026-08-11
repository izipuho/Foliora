import MapKit

/// Represents suggested field value data and behavior.
struct SuggestedFieldValue<Value: Sendable>: Sendable {
    let value: Value
    let confidence: Double
}

/// Represents geo point data and behavior.
struct GeoPoint: Sendable {
    let label: String
    let name: String
    let coordinate: CLLocationCoordinate2D?
}
