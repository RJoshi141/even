import MapKit
import SwiftUI

struct RouteMapView: View {
    let model: RouteViewModel
    let fitTrigger: Int
    let onTap: (CLLocationCoordinate2D) -> Void

    @State private var position: MapCameraPosition = .region(Coverage.region)
    private var style: EvenStyle { StyleStore.shared.current }

    private var otherRoutes: [Route] {
        guard let r = model.response, !r.identical else { return [] }
        return r.routes.filter { $0.kind != model.selected }
    }

    // refit when a new route arrives or the user taps "fit"
    private var fitToken: String { "\(model.response == nil ? "" : model.requestKey)#\(fitTrigger)" }

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                slopeLayer
                routeLayer
                inspectLayer

                Annotation("", coordinate: model.origin.point.coordinate) { LetterPin(letter: "A", fill: .ink) }
                    .annotationTitles(.hidden)
                Annotation("", coordinate: model.destination.point.coordinate) { LetterPin(letter: "B", fill: .brand) }
                    .annotationTitles(.hidden)
            }
            .mapStyle(.standard(elevation: .flat, emphasis: style.mutedMap ? .muted : .automatic,
                                pointsOfInterest: .excludingAll))
            .onTapGesture { screenPoint in
                if let coordinate = proxy.convert(screenPoint, from: .local) { onTap(coordinate) }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                Task { await model.regionChanged(context.region) }
            }
            .onAppear { fit(animated: false) }
            .onChange(of: fitToken) { fit(animated: true) }
            .accessibilityHidden(true) // panels carry the same info as text
        }
    }

    // MARK: layers

    // every path in view, colored for this profile
    @MapContentBuilder private var slopeLayer: some MapContent {
        let lines = model.network?.lines ?? []
        ForEach(lines.indices, id: \.self) { i in
            let cls = PathClass(rawValue: lines[i].cls) ?? .easy
            MapPolyline(coordinates: lines[i].coords)
                .stroke(cls.color.opacity(0.75),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round,
                                           dash: cls == .steps ? [2, 3] : []))
        }
    }

    @MapContentBuilder private var routeLayer: some MapContent {
        ForEach(otherRoutes) { route in
            MapPolyline(coordinates: route.allCoordinates)
                .stroke(Color.ink.opacity(0.35),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [1, 9]))
        }

        if let route = model.selectedRoute {
            MapPolyline(coordinates: route.allCoordinates)
                .stroke(Color.white, style: StrokeStyle(lineWidth: style.routeWidth + 5, lineCap: .round, lineJoin: .round))
            ForEach(route.segments.indices, id: \.self) { i in
                MapPolyline(coordinates: route.segments[i].coords)
                    .stroke(route.segments[i].slope.color,
                            style: StrokeStyle(lineWidth: style.routeWidth, lineCap: .round, lineJoin: .round))
            }
            // over-limit stretches also get white dashes, readable without relying on color
            ForEach(route.segments.indices.filter { route.segments[$0].slope == .over }, id: \.self) { i in
                MapPolyline(coordinates: route.segments[i].coords)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [3, 7]))
            }

            // curb problems marked right on the route
            ForEach(curbIssues(route), id: \.index) { issue in
                Annotation("", coordinate: issue.coordinate) { CurbMarker(kind: issue.kind) }
                    .annotationTitles(.hidden)
            }

            // can't reach it: where the route stops, and the gap left
            if !route.reachesDestination, let end = route.allCoordinates.last {
                MapPolyline(coordinates: [end, model.destination.point.coordinate])
                    .stroke(Color.sun, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 7]))
                Annotation("", coordinate: end) { GapPin() }
                    .annotationTitles(.hidden)
            }
        }
    }

    // the tapped spot and the path it landed on
    @MapContentBuilder private var inspectLayer: some MapContent {
        if let info = model.inspected, info.found {
            MapPolyline(coordinates: info.coords)
                .stroke(Color.ink, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            MapPolyline(coordinates: info.coords)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        if let point = model.tapped {
            Annotation("", coordinate: point.coordinate) { TapPin() }
                .annotationTitles(.hidden)
        }
    }

    // MARK: helpers

    private struct CurbIssue {
        let index: Int
        let coordinate: CLLocationCoordinate2D
        let kind: CurbMarker.Kind
    }

    private func curbIssues(_ route: Route) -> [CurbIssue] {
        route.segments.enumerated().compactMap { pair -> CurbIssue? in
            let (i, s) = pair
            guard s.kind == "crossing", !s.coordinates.isEmpty else { return nil }
            let kind: CurbMarker.Kind
            if s.curb == "barrier" { kind = .barrier }
            else if s.rampIssue == true { kind = .poorRamp }
            else if s.curb == "unknown" { kind = .unknown }
            else { return nil }
            return CurbIssue(index: i, coordinate: s.coords[s.coords.count / 2], kind: kind)
        }
    }

    private func fit(animated: Bool) {
        guard model.response != nil else { return }
        if animated {
            withAnimation(.smooth(duration: 0.6)) { position = .rect(fittingRect) }
        } else {
            position = .rect(fittingRect)
        }
    }

    private var fittingRect: MKMapRect {
        let points = (model.response?.routes.flatMap(\.allCoordinates) ?? [])
            + [model.origin.point.coordinate, model.destination.point.coordinate]
        var rect = MKMapRect.null
        for c in points {
            let p = MKMapPoint(c)
            rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
        }
        return rect.insetBy(dx: -rect.width * 0.12, dy: -rect.height * 0.12)
    }
}

// MARK: - map pins

struct LetterPin: View {
    let letter: String
    let fill: Color

    private var radius: CGFloat { StyleStore.shared.current.pin == .circle ? 15 : 7 }

    var body: some View {
        Text(letter)
            .font(.system(size: 14, weight: .heavy, design: StyleStore.shared.current.fontDesign))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(fill, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}

struct CurbMarker: View {
    enum Kind { case unknown, poorRamp, barrier }
    let kind: Kind

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(kind == .poorRamp ? Color.ink : Color.white)
            .frame(width: 18, height: 18)
            .background(fill, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

    var symbol: String {
        switch kind {
        case .unknown: "questionmark"
        case .poorRamp: "exclamationmark"
        case .barrier: "xmark"
        }
    }

    var fill: Color {
        switch kind {
        case .unknown: Color(hex: 0x6B7280)
        case .poorRamp: .sun
        case .barrier: .slopeOver
        }
    }
}

private struct GapPin: View {
    var body: some View {
        Image(systemName: "figure.roll")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.ink)
            .frame(width: 30, height: 30)
            .background(Color.sun, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}

private struct TapPin: View {
    var body: some View {
        Circle()
            .fill(Color.ink)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}
