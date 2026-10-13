import Foundation

struct Place: Identifiable, Hashable {
    let name: String
    let point: GeoPoint
    var id: String { name }
}

// Hardcoded for now, search comes later. All inside the area the pipeline covers.
enum Places {
    static let civicCenter = Place(name: "Civic Center Station", point: .init(lat: 37.7796, lon: -122.4138))

    static let destinations = [
        Place(name: "Mission Dolores Park", point: .init(lat: 37.7596, lon: -122.4269)),
        Place(name: "24th St Mission Station", point: .init(lat: 37.7522, lon: -122.4184)),
        Place(name: "Union Square", point: .init(lat: 37.7880, lon: -122.4075)),
    ]
}
