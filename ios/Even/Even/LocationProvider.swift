import CoreLocation

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
