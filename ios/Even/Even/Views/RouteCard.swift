import SwiftUI

// MARK: - bottom bar: one line by default, full comparison on demand

struct ComparePanel: View {
    let response: RouteResponse
    @Binding var selected: RouteKind
    @Binding var expanded: Bool
    let destinationName: String

    private var current: Route? { response.routes.first { $0.kind == selected } }
    private var other: Route? { response.routes.first { $0.kind != selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if response.identical {
                    Label("Shortest way fits you", systemImage: "checkmark.seal.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.brand)
                } else {
                    RoutePicker(routes: response.routes, selected: $selected)
                }
                Spacer()
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? "Less" : "Details")
                        Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                }
                .accessibilityLabel(expanded ? "Hide route details" : "Show route details")
            }

            if let route = current {
                SummaryLine(route: route, profile: response.profile)

                if !route.reachesDestination, let gap = route.gapM {
                    Label("Ends \(Format.distance(gap)) from \(destinationName), the closest within your limits",
                          systemImage: "figure.roll")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 14) {
                        CompareTable(routes: response.identical ? [route] : response.routes,
                                     profile: response.profile, selected: $selected)
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: "Slope along the way")
                            SlopeChart(route: route, profile: response.profile)
                        }
                        if let note = tradeOff(route) {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    private func tradeOff(_ route: Route) -> String? {
        guard let other, !response.identical else { return nil }
        if route.kind == .fitsProfile, !other.fitsProfile {
            let diff = route.summary.distanceM - other.summary.distanceM
            let shorter = diff > 15 ? "\(Format.distance(diff)) shorter" : "about the same length"
            return "The shortest way is \(shorter) but climbs \(Format.percent(other.summary.maxUphill))."
        }
        if route.kind == .shortest, !route.fitsProfile {
            let extra = other.summary.durationS - route.summary.durationS
            return extra > 60
                ? "The Even route stays within your limits for \(Format.duration(extra)) more."
                : "The Even route stays within your limits in about the same time."
        }
        return nil
    }
}

/// time, distance and the two numbers that matter, on one line
private struct SummaryLine: View {
    let route: Route
    let profile: Profile

    var body: some View {
        let s = route.summary
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Format.duration(s.durationS))
                .font(.title2.weight(.bold))
            Text(Format.distance(s.distanceM))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            metric("↑", s.maxUphill, over: s.maxUphill > profile.maxUphill)
            metric("↓", s.maxDownhill, over: s.maxDownhill > profile.maxDownhill)
            if s.barrierCurbs > 0 {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(Color.slopeOver)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Format.duration(s.durationS)), \(Format.distance(s.distanceM)), steepest uphill \(Format.percent(s.maxUphill)), steepest downhill \(Format.percent(s.maxDownhill))\(route.fitsProfile ? ", fits your profile" : ", breaks your limits")")
    }

    private func metric(_ arrow: String, _ value: Double, over: Bool) -> some View {
        Text("\(arrow) \(Format.percent(value))")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(over ? Color.slopeOver : Color.primary)
    }
}

/// small Even / Shortest toggle
private struct RoutePicker: View {
    let routes: [Route]
    @Binding var selected: RouteKind
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(routes) { route in
                let isOn = selected == route.kind
                Button {
                    withAnimation(.snappy) { selected = route.kind }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(route.fitsProfile ? Color.brandBright : Color.slopeOver)
                            .frame(width: 6, height: 6)
                        Text(route.kind == .fitsProfile ? "Even" : "Shortest")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isOn ? Color.primary : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        if isOn {
                            Capsule()
                                .fill(Color(uiColor: .systemBackground))
                                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(route.kind == .fitsProfile ? "Even route" : "Shortest route"), \(route.fitsProfile ? "fits your profile" : "breaks your limits")")
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        .sensoryFeedback(.selection, trigger: selected)
    }
}

// MARK: - full comparison (inside Details)

private struct CompareTable: View {
    let routes: [Route]
    let profile: Profile
    @Binding var selected: RouteKind

    private let rowHeight: CGFloat = 24

    private enum Metric: CaseIterable {
        case distance, climb, descent, curbs, steps

        var label: String {
            switch self {
            case .distance: "Distance"
            case .climb: "Max climb"
            case .descent: "Max descent"
            case .curbs: "Curbs"
            case .steps: "Steps"
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: rowHeight)
                ForEach(Metric.allCases, id: \.self) { m in
                    SectionLabel(text: m.label).frame(height: rowHeight, alignment: .leading)
                }
            }
            .accessibilityHidden(true)

            ForEach(routes) { route in
                VStack(alignment: .leading, spacing: 0) {
                    Text(route.kind == .fitsProfile ? "Even" : "Shortest")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(selected == route.kind ? Color.primary : Color.secondary)
                        .frame(height: rowHeight, alignment: .leading)
                    ForEach(Metric.allCases, id: \.self) { m in
                        let v = value(m, route)
                        Text(v.text)
                            .font(.footnote.weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(v.bad ? Color.slopeOver : Color.primary)
                            .lineLimit(1)
                            .frame(height: rowHeight, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func value(_ m: Metric, _ r: Route) -> (text: String, bad: Bool) {
        let s = r.summary
        switch m {
        case .distance: return (Format.distance(s.distanceM), false)
        case .climb: return (Format.percent(s.maxUphill), s.maxUphill > profile.maxUphill)
        case .descent: return (Format.percent(s.maxDownhill), s.maxDownhill > profile.maxDownhill)
        case .curbs:
            if s.barrierCurbs > 0 { return ("\(s.barrierCurbs) blocked", true) }
            if s.unknownCurbs > 0 { return ("\(s.unknownCurbs) unverified", false) }
            return ("All ramped", false)
        case .steps: return (s.steps == 0 ? "None" : "\(s.steps)", s.steps > 0 && profile.avoidSteps)
        }
    }
}

// MARK: - tapped spot

struct InspectCard: View {
    let info: InspectResponse?
    let loading: Bool
    let profile: Profile?
    let onRouteFrom: () -> Void
    let onRouteTo: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    if loading {
                        Text("Reading this spot…").font(.subheadline).foregroundStyle(.secondary)
                    } else if let info, info.found {
                        HStack(spacing: 6) {
                            Circle().fill(pathClass(info).color).frame(width: 8, height: 8)
                            Text(info.verdict ?? "").font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No sidewalk data here").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(uiColor: .secondarySystemBackground), in: Circle())
                }
                .accessibilityLabel("Close")
            }

            if !loading, let info, info.found {
                HStack(spacing: 18) {
                    inline("Incline", Format.percent(info.grade ?? 0))
                    inline("Length", Format.distance(info.lengthM ?? 0))
                    if info.kind == "crossing" {
                        inline("Curb", curbText(info))
                    } else if let surface = info.surface {
                        inline("Surface", surface.capitalized)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Start here", action: onRouteFrom)
                    .buttonStyle(.bordered)
                    .tint(Color.primary)
                    .accessibilityHint("Route from this spot")
                Button("Go here", action: onRouteTo)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brand)
                    .accessibilityHint("Route to this spot")
            }
            .font(.subheadline.weight(.semibold))
            .buttonBorderShape(StyleStore.shared.current.buttonShape)
        }
    }

    private func inline(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: label)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        guard let info, info.found else { return loading ? "Checking…" : "Open spot" }
        if let name = info.name { return name }
        switch info.kind {
        case "crossing": return "Crosswalk"
        case "footway": return "Path"
        case "pedestrian": return "Plaza"
        case "steps": return "Steps"
        case "elevator": return "Elevator"
        default: return "Sidewalk"
        }
    }

    private func pathClass(_ info: InspectResponse) -> PathClass {
        if info.kind == "steps" { return .steps }
        if info.access != "both_ways" { return .over }
        return (info.grade ?? 0) < 3 ? .easy : .moderate
    }

    private func curbText(_ info: InspectResponse) -> String {
        if info.rampIssue { return "Steep or worn" }
        switch info.curb {
        case "ramp": return "Ramp"
        case "flush": return "Flush"
        case "barrier": return "No ramp"
        default: return "Unverified"
        }
    }
}

// MARK: - legend

struct LegendPanel: View {
    let profile: Profile?

    private var limit: Int? { profile.map { Int(min($0.maxUphill, $0.maxDownhill)) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            group("Slope") {
                line(.slopeEasy, "Under 3%")
                line(.slopeModerate, limit.map { "3 to \($0)%" } ?? "Moderate")
                line(.slopeOver, limit.map { "Over \($0)%" } ?? "Over your limit", dashed: true)
            }
            group("Curbs") {
                marker(.unknown, "Unverified")
                marker(.poorRamp, "Steep or worn ramp")
                marker(.barrier, "No ramp")
            }
            group("Map") {
                swatch(Capsule().fill(Color.ink.opacity(0.35)).frame(width: 18, height: 3), "Other route")
                swatch(Capsule().fill(Color.sun).frame(width: 18, height: 3), "Gap you can't cross")
                swatch(Capsule().fill(PathClass.steps.color).frame(width: 18, height: 3), "Steps")
            }
        }
        .padding(12)
        .frame(width: 190, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Map legend")
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: title)
            content()
        }
    }

    private func line(_ color: Color, _ name: String, dashed: Bool = false) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Capsule().fill(color).frame(width: 18, height: 5)
                if dashed { Capsule().fill(.white).frame(width: 6, height: 2) }
            }
            Text(name).font(.caption)
        }
    }

    private func marker(_ kind: CurbMarker.Kind, _ name: String) -> some View {
        HStack(spacing: 8) {
            CurbMarker(kind: kind).scaleEffect(0.8).frame(width: 18)
            Text(name).font(.caption)
        }
    }

    private func swatch<S: View>(_ shape: S, _ name: String) -> some View {
        HStack(spacing: 8) {
            shape.frame(width: 18)
            Text(name).font(.caption)
        }
    }
}

// MARK: - shared

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}
