import CoreLocation
import MapKit

enum LocationProvider {
    enum LocationError: LocalizedError, Equatable {
        case denied, timedOut

        var errorDescription: String? {
            switch self {
            case .denied: "Location access is off for Even. Turn it on in Settings to start from where you are."
            case .timedOut: "Couldn't find your location. Try again in a moment."
            }
        }
    }

    /// One fix of the user's location, asking for permission if needed. Gives up after `timeout`.
    static func current(timeout: Duration = .seconds(12)) async throws -> CLLocation {
        try await withThrowingTaskGroup(of: CLLocation.self) { group in
            group.addTask { try await firstFix() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LocationError.timedOut
            }
            defer { group.cancelAll() }
            guard let location = try await group.next() else { throw LocationError.timedOut }
            return location
        }
    }

    private static func firstFix() async throws -> CLLocation {
        // the session is what triggers the permission prompt; keep it alive until we have a fix
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location { return location }
            if update.authorizationDenied || update.authorizationDeniedGlobally { throw LocationError.denied }
        }
        throw LocationError.timedOut
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
