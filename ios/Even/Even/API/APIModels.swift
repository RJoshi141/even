import CoreLocation
import Foundation

// Mirrors api/models.py. Keys arrive snake_case and are converted on decode.

struct GeoPoint: Codable, Hashable {
    var lat: Double
    var lon: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

enum Preset: String, Codable, CaseIterable, Identifiable {
    case manualWheelchair = "manual_wheelchair"
    case powerWheelchair = "power_wheelchair"
    case walker
    case stroller

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manualWheelchair: "Manual wheelchair"
        case .powerWheelchair: "Power wheelchair"
        case .walker: "Walker or cane"
        case .stroller: "Stroller or cart"
        }
    }
}

struct RouteRequest: Encodable {
    let origin: GeoPoint
    let destination: GeoPoint
    let preset: Preset
}

struct Profile: Codable, Hashable {
    var maxUphill: Double
    var maxDownhill: Double
    var avoidSteps: Bool
    var requireRamps: Bool
    var speedMps: Double
}

struct RouteResponse: Decodable {
    let profile: Profile
    let originSnapM: Double
    let destinationSnapM: Double
    let identical: Bool          // both routes are the same path
    let routes: [Route]
}

enum RouteKind: String, Decodable, Hashable {
    case fitsProfile = "fits_profile"
    case shortest
}

struct Route: Decodable, Identifiable {
    let kind: RouteKind
    let reachesDestination: Bool
    let gapM: Double?            // how far short it stops when it can't reach
    let fitsProfile: Bool
    let breaks: [String]         // uphill | downhill | steps | curb
    let summary: RouteSummary
    let segments: [Segment]

    var id: RouteKind { kind }
    var allCoordinates: [CLLocationCoordinate2D] { segments.flatMap(\.coords) }
}

struct RouteSummary: Decodable {
    let distanceM: Double
    let durationS: Double
    let maxUphill: Double
    let maxDownhill: Double
    let steps: Int
    let barrierCurbs: Int
    let unknownCurbs: Int
    let steepRamps: Int
    let poorRamps: Int
}

enum SlopeClass: String, Decodable {
    case easy, moderate, over
}

struct Segment: Decodable {
    let kind: String
    let slope: SlopeClass
    let grade: Double            // steepest grade in the run, signed in travel direction
    let lengthM: Double
    let curb: String?
    let coordinates: [[Double]]  // [lon, lat]

    var coords: [CLLocationCoordinate2D] {
        coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
    }
}
