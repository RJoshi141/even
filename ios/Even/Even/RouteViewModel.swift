import Foundation
import Observation

@Observable
final class RouteViewModel {
    enum State {
        case loading
        case loaded(RouteResponse)
        case failed(String)
    }

    var state: State = .loading
    var origin = Places.civicCenter
    var destination = Places.suggestions[1]
    var preset: Preset = .manualWheelchair
    var selected: RouteKind = .fitsProfile

    private let api = EvenAPI()

    // changes whenever the request does, so views can reload and reset the map
    var requestKey: String { "\(origin.id)|\(destination.id)|\(preset.rawValue)" }

    func swap() {
        (origin, destination) = (destination, origin)
    }

    func load() async {
        state = .loading
        do {
            let response = try await api.route(from: origin.point, to: destination.point, preset: preset)
            selected = .fitsProfile
            state = .loaded(response)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
