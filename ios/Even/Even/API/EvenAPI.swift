import Foundation

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

    func route(from origin: GeoPoint, to destination: GeoPoint, preset: Preset) async throws -> RouteResponse {
        var request = URLRequest(url: baseURL.appending(path: "route"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RouteRequest(origin: origin, destination: destination, preset: preset))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.server("No response from server") }
        guard http.statusCode == 200 else {
            // FastAPI errors look like {"detail": "..."}
            let detail = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.detail
            throw APIError.server(detail ?? "Server error \(http.statusCode)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RouteResponse.self, from: data)
    }
}
