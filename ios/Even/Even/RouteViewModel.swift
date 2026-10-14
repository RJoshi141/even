import Foundation
import MapKit
import Observation

@Observable
final class RouteViewModel {
    enum State {
        case loading
        case loaded(RouteResponse)
        case failed(String)
    }

    // route
    var state: State = .loading
    var origin = Places.civicCenter
    var destination = Places.suggestions[1]
    var preset: Preset = Preset(rawValue: UserDefaults.standard.string(forKey: "preset") ?? "") ?? .manualWheelchair {
        didSet { UserDefaults.standard.set(preset.rawValue, forKey: "preset") }
    }
    var selected: RouteKind = .fitsProfile

    // tap to inspect
    var tapped: GeoPoint?
    var inspected: InspectResponse?
    var inspecting = false

    // map layers
    var showLegend = false
    var slopeLayerOn = false
    var network: NetworkResponse?
    private var lastRegion: MKCoordinateRegion?

    private let api = EvenAPI()
    private var didPrepareStart = false

    // changes whenever the request does, so views reload and refit
    var requestKey: String { "\(origin.id)|\(destination.id)|\(preset.rawValue)" }

    var response: RouteResponse? {
        if case .loaded(let r) = state { return r }
        return nil
    }

    var selectedRoute: Route? { response?.routes.first { $0.kind == selected } }

    func load() async {
        state = .loading
        do {
            let response = try await api.route(from: origin.point, to: destination.point, preset: preset)
            selected = .fitsProfile
            state = .loaded(response)
        } catch {
            state = .failed(error.localizedDescription)
        }
        if slopeLayerOn { await loadNetwork() } // profile may have changed the colors
    }

    /// If the user opted in on the start page, begin from where they are (when it's inside coverage).
    func prepareStart() async {
        guard !didPrepareStart else { return }
        didPrepareStart = true
        guard UserDefaults.standard.bool(forKey: "useLocationStart"),
              let location = try? await LocationProvider.current(timeout: .seconds(6)),
              Coverage.contains(location.coordinate) else { return }
        origin = Place(name: "Current location",
                       point: GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude))
    }

    func swap() {
        (origin, destination) = (destination, origin)
    }

    // MARK: inspect

    func inspect(at coordinate: CLLocationCoordinate2D) async {
        let point = GeoPoint(lat: coordinate.latitude, lon: coordinate.longitude)
        tapped = point
        inspected = nil
        inspecting = true
        let result = try? await api.inspect(point, preset: preset)
        guard tapped == point else { return } // a newer tap won
        inspected = result
        inspecting = false
    }

    func closeInspect() {
        tapped = nil
        inspected = nil
        inspecting = false
    }

    func useTapped(asOrigin: Bool) async {
        guard let point = tapped else { return }
        let place = Place(name: await PinNamer.name(for: point), point: point)
        if asOrigin { origin = place } else { destination = place }
        closeInspect()
    }

    // MARK: slope layer

    func regionChanged(_ region: MKCoordinateRegion) async {
        lastRegion = region
        if slopeLayerOn { await loadNetwork() }
    }

    func toggleSlopeLayer() async {
        slopeLayerOn.toggle()
        if slopeLayerOn { await loadNetwork() } else { network = nil }
    }

    private func loadNetwork() async {
        guard let region = lastRegion else { return }
        network = try? await api.network(in: region, preset: preset)
    }
}
