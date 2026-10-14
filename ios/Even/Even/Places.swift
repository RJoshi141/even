import MapKit

struct Place: Identifiable, Hashable {
    let name: String
    let point: GeoPoint
    var subtitle: String? = nil

    // names repeat (two cafes with the same name), coordinates don't
    var id: String { "\(name)|\(point.lat),\(point.lon)" }
}

enum Places {
    static let civicCenter = Place(name: "Civic Center Station", point: .init(lat: 37.7796, lon: -122.4138))

    // shown before the user types anything
    static let suggestions = [
        civicCenter,
        Place(name: "Mission Dolores Park", point: .init(lat: 37.7596, lon: -122.4269)),
        Place(name: "24th St Mission Station", point: .init(lat: 37.7522, lon: -122.4184)),
        Place(name: "Union Square", point: .init(lat: 37.7880, lon: -122.4075)),
    ]
}

// the area the pipeline has data for (pipeline/areas.py "sf-core")
enum Coverage {
    static let region = MKCoordinateRegion(
        center: .init(latitude: 37.7715, longitude: -122.4100),
        span: .init(latitudeDelta: 0.047, longitudeDelta: 0.040))
    static let description = "Downtown, SoMa and the Mission"

    static func contains(_ c: CLLocationCoordinate2D) -> Bool {
        abs(c.latitude - region.center.latitude) <= region.span.latitudeDelta / 2
            && abs(c.longitude - region.center.longitude) <= region.span.longitudeDelta / 2
    }
}
