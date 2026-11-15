import MapKit

/// Represents geo point data and behavior.
struct GeoPoint: Sendable {
    let label: String
    let name: String
    let coordinate: CLLocationCoordinate2D?
}
