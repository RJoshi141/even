import MapKit
import SwiftUI

struct RouteMapView: View {
    let response: RouteResponse
    let selected: RouteKind
    let origin: Place
    let destination: Place

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            // the route you're not looking at: quiet, dashed, underneath
            ForEach(response.routes.filter { $0.kind != selected }) { route in
                MapPolyline(coordinates: route.allCoordinates)
                    .stroke(Color.gray.opacity(0.7),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [2, 8]))
            }

            if let route = response.routes.first(where: { $0.kind == selected }) {
                // white casing so the slope colors pop on the basemap
                MapPolyline(coordinates: route.allCoordinates)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                ForEach(route.segments.indices, id: \.self) { i in
                    MapPolyline(coordinates: route.segments[i].coords)
                        .stroke(route.segments[i].slope.color,
                                style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }
            }

            // when the route can't reach the destination, show where it stops and the gap left
            if let route = response.routes.first(where: { $0.kind == selected }),
               !route.reachesDestination,
               let end = route.allCoordinates.last {
                MapPolyline(coordinates: [end, destination.point.coordinate])
                    .stroke(Color.evenTeal, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 6]))
                Marker("Closest you can get", systemImage: "figure.roll", coordinate: end)
                    .tint(Color.slopeModerate)
            }

            Marker(origin.name, systemImage: "circle.fill", coordinate: origin.point.coordinate)
                .tint(.black)
            Marker(destination.name, systemImage: "mappin", coordinate: destination.point.coordinate)
                .tint(Color.evenTeal)
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onAppear { position = .rect(fittingRect) }
        .accessibilityHidden(true) // the route cards carry the same info as text
    }

    // everything on screen, with a little breathing room
    private var fittingRect: MKMapRect {
        let points = response.routes.flatMap(\.allCoordinates)
            + [origin.point.coordinate, destination.point.coordinate]
        var rect = MKMapRect.null
        for c in points {
            let p = MKMapPoint(c)
            rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
        }
        return rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.15)
    }
}
