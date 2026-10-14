import MapKit
import SwiftUI

struct RouteMapView: View {
    let model: RouteViewModel
    let fitTrigger: Int
    let onTap: (CLLocationCoordinate2D) -> Void

    @State private var position: MapCameraPosition = .region(Coverage.region)
    private var style: EvenStyle { StyleStore.shared.current }

    // refit when a new route arrives or the user taps "fit"
    private var fitToken: String { "\(model.response == nil ? "" : model.requestKey)#\(fitTrigger)" }

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                UserAnnotation()
                slopeLayer
                routeLayer
                inspectLayer

                Annotation("", coordinate: model.origin.point.coordinate) { LetterPin(letter: "A", filled: false) }
                    .annotationTitles(.hidden)
                Annotation("", coordinate: model.destination.point.coordinate) { LetterPin(letter: "B") }
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
                .mapOverlayLevel(level: .aboveRoads)
        }
    }

    @MapContentBuilder private var routeLayer: some MapContent {
        if let route = model.selectedRoute {
            // ids are tied to this exact route, so a new route redraws every piece in order:
            // all the white casing first, then the colors on top. MapKit puts re-added shapes on top,
            // which is what let the casing cover colored pieces before.
            let pieces = drawn(route)
            ForEach(pieces) { piece in
                MapPolyline(coordinates: piece.coords)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: style.routeWidth + 5, lineCap: .round, lineJoin: .round))
                    .mapOverlayLevel(level: .aboveLabels)
            }
            ForEach(pieces) { piece in
                MapPolyline(coordinates: piece.coords)
                    .stroke(piece.color, style: StrokeStyle(lineWidth: style.routeWidth, lineCap: .round, lineJoin: .round))
                    .mapOverlayLevel(level: .aboveLabels)
            }
            // over-limit stretches also get white dashes, readable without relying on color
            ForEach(pieces.filter(\.over)) { piece in
                MapPolyline(coordinates: piece.coords)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [3, 7]))
                    .mapOverlayLevel(level: .aboveLabels)
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
                    .mapOverlayLevel(level: .aboveLabels)
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
                .mapOverlayLevel(level: .aboveLabels)
            MapPolyline(coordinates: info.coords)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .mapOverlayLevel(level: .aboveLabels)
        }
        if let point = model.tapped {
            Annotation("", coordinate: point.coordinate) { TapPin() }
                .annotationTitles(.hidden)
        }
    }

    // MARK: helpers

    private struct DrawnPiece: Identifiable {
        let id: String
        let coords: [CLLocationCoordinate2D]
        let color: Color
        let over: Bool
    }

    private func drawn(_ route: Route) -> [DrawnPiece] {
        let key = "\(model.requestKey)|\(route.kind.rawValue)"
        return route.segments.enumerated().map { pair -> DrawnPiece in
            let (i, s) = pair
            return DrawnPiece(id: "\(key)#\(i)", coords: s.coords, color: s.slope.color, over: s.slope == .over)
        }
    }

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
        let points = (model.selectedRoute?.allCoordinates ?? [])
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
    var filled = true      // B is solid ink, A is paper with an ink ring
    var size: CGFloat = 30

    var body: some View {
        Text(letter)
            .font(.evenFixed(size * 0.46, .bold))
            .foregroundStyle(filled ? Color.onBrand : Color.ink)
            .frame(width: size, height: size)
            .background(filled ? Color.brand : Color.white, in: Circle())
            .overlay(Circle().stroke(filled ? Color.paper : Color.ink, lineWidth: size > 24 ? 2.5 : 1.5))
            .shadow(color: .black.opacity(size > 24 ? 0.25 : 0), radius: 3, y: 1)
    }
}

struct CurbMarker: View {
    enum Kind { case unknown, poorRamp, barrier }
    let kind: Kind

    var body: some View {
        Image(systemName: symbol)
            .font(.evenFixed(9, .black))
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
            .font(.evenFixed(13, .bold))
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
