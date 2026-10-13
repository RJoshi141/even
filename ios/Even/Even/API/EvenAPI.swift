import Foundation
import MapKit

struct EvenAPI {
    // The simulator shares the Mac's network, so localhost reaches uvicorn.
    // On a real iPhone: use the Mac's LAN IP and run uvicorn with --host 0.0.0.0
    var baseURL = URL(string: "http://localhost:8000")!

    enum APIError: LocalizedError {
        case server(String)
        var errorDescription: String? {
            switch self { case .server(let message): message }
        }
    }

    private struct ErrorBody: Decodable { let detail: String }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    func route(from origin: GeoPoint, to destination: GeoPoint, preset: Preset) async throws -> RouteResponse {
        var request = URLRequest(url: baseURL.appending(path: "route"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RouteRequest(origin: origin, destination: destination, preset: preset))
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        return try decoder.decode(RouteResponse.self, from: data)
    }

    func inspect(_ point: GeoPoint, preset: Preset) async throws -> InspectResponse {
        try await get("inspect", ["lat": "\(point.lat)", "lon": "\(point.lon)", "preset": preset.rawValue])
    }

    func network(in region: MKCoordinateRegion, preset: Preset) async throws -> NetworkResponse {
        let c = region.center, s = region.span
        return try await get("network", [
            "min_lat": "\(c.latitude - s.latitudeDelta / 2)", "max_lat": "\(c.latitude + s.latitudeDelta / 2)",
            "min_lon": "\(c.longitude - s.longitudeDelta / 2)", "max_lon": "\(c.longitude + s.longitudeDelta / 2)",
            "preset": preset.rawValue,
        ])
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try check(response, data)
        return try decoder.decode(T.self, from: data)
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.server("No response from server") }
        guard http.statusCode == 200 else {
            // FastAPI errors look like {"detail": "..."}
            let detail = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.detail
            throw APIError.server(detail ?? "Server error \(http.statusCode)")
        }
    }
}
