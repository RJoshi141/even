import CoreLocation
import MapKit

enum LocationProvider {
    struct Unavailable: LocalizedError {
        var errorDescription: String? { "Couldn't get your location. Check Location access for Even in Settings." }
    }

    /// One fix of the user's current location, asking for permission if needed.
    static func current() async throws -> CLLocation {
        // the session is what triggers the permission prompt; keep it alive until we have a fix
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location { return location }
            if update.authorizationDenied || update.authorizationDeniedGlobally { throw Unavailable() }
        }
        throw Unavailable()
    }
}

enum PinNamer {
    /// Street address for a dropped pin, like "512 Valencia St".
    static func name(for point: GeoPoint) async -> String {
        let location = CLLocation(latitude: point.lat, longitude: point.lon)
        // MapKit's reverse geocoder (iOS 26), replaces CLGeocoder
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first else { return "Dropped pin" }
        return item.address?.shortAddress ?? item.name ?? "Dropped pin"
    }
}
