import SwiftUI

// MARK: - the trip card floating over the map

struct TripCard: View {
    let route: Route
    let profile: Profile
    let destinationName: String
    let onOpen: (TripPanel) -> Void

    var body: some View {
        let s = route.summary
        let style = StyleStore.shared.current
        VStack(alignment: .leading, spacing: 10) {
            // one line: verdict, time, distance, the two slopes that matter
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !route.fitsProfile {
                    Label(verdict(route), systemImage: "exclamationmark.triangle.fill")
                        .font(.even(.caption, .bold))
                        .foregroundStyle(Color.warning)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.warning.opacity(0.12), in: Capsule())
                }
                Text(Format.duration(s.durationS)).font(.even(.title3, .bold))
                Text(Format.distance(s.distanceM)).font(.even(.subheadline)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("↑\(Format.percent(s.maxUphill))  ↓\(Format.percent(s.maxDownhill))")
                    .font(.even(.caption, .medium))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(route.fitsProfile ? "" : verdict(route) + ". ")\(Format.duration(s.durationS)), \(Format.distance(s.distanceM)). Steepest uphill \(Format.percent(s.maxUphill)), steepest downhill \(Format.percent(s.maxDownhill))\(route.reachesDestination ? "" : ". Ends short of your destination")")

            HStack(spacing: 8) {
                Button { onOpen(.info) } label: {
                    Label("Trip info", systemImage: "info.circle")
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(Color.primary)
                        .overlay(RoundedRectangle(cornerRadius: style.corner).stroke(Color.hairline, lineWidth: 1))
                }
                Button { onOpen(.directions) } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(Color.onBrand)
                        .background(Color.brand, in: .rect(cornerRadius: style.corner))
                }
            }
            .font(.even(.footnote, .semibold))
            .buttonStyle(PressableStyle())
        }
        .padding(12)
        .background(Color.paper, in: .rect(cornerRadius: style.corner + 4))
        .overlay(RoundedRectangle(cornerRadius: style.corner + 4).stroke(Color.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
        .padding(.horizontal, 12)
    }
}

func verdict(_ route: Route) -> String {
    if route.fitsProfile { return "Fits you" }
    guard route.breaks.count == 1 else { return "Breaks \(route.breaks.count) of your limits" }
    switch route.breaks[0] {
    case "uphill": return "Too steep uphill"
    case "downhill": return "Too steep downhill"
    case "steps": return "Has steps"
    case "curb": return "A curb has no ramp"
    default: return "Breaks a limit"
    }
}

// MARK: - trip info and directions

enum TripPanel: String, Identifiable {
    case info, directions
    var id: String { rawValue }
    var title: String { self == .info ? "Trip info" : "Directions" }
}

/// Content for one pop-up: trip info or directions.
struct TripDetails: View {
    let panel: TripPanel
    let response: RouteResponse
    let originName: String
    let destinationName: String

    private var route: Route? { response.routes.first { $0.kind == .fitsProfile } }
    private var shortest: Route? { response.routes.first { $0.kind == .shortest } }
    private var corner: CGFloat { StyleStore.shared.current.corner }

    var body: some View {
        if let route {
            switch panel {
            case .info: info(route)
            case .directions: directions(route)
            }
        }
    }

    // MARK: trip info

    private func info(_ route: Route) -> some View {
        let s = route.summary
        let p = response.profile
        return VStack(alignment: .leading, spacing: 26) {
            // header: the trip in one glance
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Trip info")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Format.duration(s.durationS))
                        .font(.even(.largeTitle, .bold))
                        .tracking(-1)
                    Text(Format.distance(s.distanceM))
                        .font(.even(.title3))
                        .foregroundStyle(.secondary)
                }
                if !route.fitsProfile {
                    Label(verdict(route), systemImage: "exclamationmark.triangle.fill")
                        .font(.even(.subheadline, .bold))
                        .foregroundStyle(Color.warning)
                }
                fromTo
                if !route.reachesDestination, let gap = route.gapM {
                    Text("Ends \(Format.distance(gap)) from \(destinationName), the closest point within your limits.")
                        .font(.even(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, 40) // room for the close button

            // slope profile in an inset
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: "Slope profile")
                    Spacer()
                    HStack(spacing: 5) {
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: 14, height: 1)
                        Text("Your limits")
                    }
                    .font(.even(.caption2))
                    .foregroundStyle(.secondary)
                }
                SlopeChart(route: route, profile: p, height: 110)
                HStack {
                    LetterPin(letter: "A", filled: false, size: 18)
                    Spacer()
                    Text("\(Int(p.maxUphill))% up · \(Int(p.maxDownhill))% down")
                        .font(.even(.caption2))
                        .foregroundStyle(.secondary)
                    Spacer()
                    LetterPin(letter: "B", size: 18)
                }
            }
            .padding(14)
            .background(Color.paperDeep, in: .rect(cornerRadius: corner + 4))

            // the numbers, big
            HStack(alignment: .top, spacing: 12) {
                bigStat("Max climb", "↑ " + Format.percent(s.maxUphill), bad: s.maxUphill > p.maxUphill)
                bigStat("Max descent", "↓ " + Format.percent(s.maxDownhill), bad: s.maxDownhill > p.maxDownhill)
                bigStat("Steps", s.steps == 0 ? "None" : "\(s.steps)", bad: s.steps > 0 && p.avoidSteps)
            }

            // watch for
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Watch for")
                let items = watchFor(route)
                if items.isEmpty {
                    watchRow("checkmark", .safe, "Nothing on this route. Every curb is ramped.")
                } else {
                    ForEach(items, id: \.text) { watchRow($0.icon, $0.color, $0.text) }
                }
            }

            // why not the obvious way: a pull quote
            if let line = avoided(route) {
                HStack(alignment: .top, spacing: 12) {
                    Rectangle().fill(Color.ink).frame(width: 2)
                    Text(line).font(.even(.subheadline, .medium))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
    }

    private var fromTo: some View {
        HStack(spacing: 6) {
            LetterPin(letter: "A", filled: false, size: 16)
            Text(originName).lineLimit(1)
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            LetterPin(letter: "B", size: 16)
            Text(destinationName).lineLimit(1)
        }
        .font(.even(.footnote, .medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("From \(originName) to \(destinationName)")
    }

    private func bigStat(_ label: String, _ value: String, bad: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.even(.title2, .bold))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(bad ? Color.warning : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            SectionLabel(text: label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private struct Item { let icon: String; let color: Color; let text: String }

    private func watchFor(_ r: Route) -> [Item] {
        let s = r.summary
        var out: [Item] = []
        if s.barrierCurbs > 0 { out.append(.init(icon: "xmark", color: .warning, text: plural(s.barrierCurbs, "crossing has", "crossings have") + " no curb ramp")) }
        if s.steps > 0 { out.append(.init(icon: "stairs", color: .warning, text: plural(s.steps, "set of steps", "sets of steps"))) }
        if s.steepRamps > 0 { out.append(.init(icon: "exclamationmark", color: .slopeModerate, text: plural(s.steepRamps, "curb ramp is", "curb ramps are") + " steeper than the ADA limit")) }
        if s.poorRamps > 0 { out.append(.init(icon: "exclamationmark", color: .slopeModerate, text: plural(s.poorRamps, "curb ramp is", "curb ramps are") + " worn or damaged")) }
        if s.unknownCurbs > 0 { out.append(.init(icon: "questionmark", color: .secondary, text: plural(s.unknownCurbs, "crossing hasn't", "crossings haven't") + " been surveyed yet")) }
        return out
    }

    private func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

    private func watchRow(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.14), in: Circle())
            Text(text).font(.even(.subheadline))
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func avoided(_ route: Route) -> String? {
        if response.identical { return "This is also the shortest way." }
        guard let shortest, !shortest.fitsProfile else { return nil }
        let diff = route.summary.distanceM - shortest.summary.distanceM
        let shorter = diff > 15 ? "\(Format.distance(diff)) shorter" : "about the same length"
        return "The shortest way is \(shorter) but climbs \(Format.percent(shortest.summary.maxUphill)), so Even avoids it."
    }

    // MARK: directions, as a timeline from A to B

    private func directions(_ route: Route) -> some View {
        let steps = route.steps ?? []
        let turns = steps.filter { $0.maneuver != "arrive" }.count
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Directions")
                Text("\(turns) \(turns == 1 ? "step" : "steps") · \(Format.distance(route.summary.distanceM)) · \(Format.duration(route.summary.durationS))")
                    .font(.even(.title2, .bold))
                    .tracking(-0.5)
                fromTo
            }
            .padding(.trailing, 40)

            if steps.isEmpty {
                Text("Directions aren't available for this route yet.")
                    .font(.even(.subheadline))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(steps.indices, id: \.self) { i in
                        TimelineStep(step: steps[i], isFirst: i == 0, isLast: i == steps.count - 1,
                                     number: i + 1, total: steps.count)
                    }
                }
            }
        }
        .padding(22)
    }
}

private struct TimelineStep: View {
    let step: Step
    let isFirst: Bool
    let isLast: Bool
    let number: Int
    let total: Int

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Color.clear.frame(width: 32, height: 1) // the rail is drawn in the overlay
            VStack(alignment: .leading, spacing: 4) {
                Text(step.instruction).font(.even(.body, .semibold))
                if let line = detailLine {
                    HStack(spacing: 6) {
                        if step.lengthM > 0 { Circle().fill(step.slope.color).frame(width: 7, height: 7) }
                        Text(line).font(.even(.footnote)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 5)
            Spacer(minLength: 0)
        }
        .padding(.top, isFirst ? 0 : 10)
        .padding(.bottom, isLast ? 0 : 10)
        .overlay(alignment: .topLeading) {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : Color.hairline).frame(width: 2, height: isFirst ? 0 : 10)
                node
                Rectangle().fill(isLast ? Color.clear : Color.hairline).frame(width: 2)
            }
            .frame(width: 32)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(number) of \(total). \(step.instruction). \(detailLine ?? "")")
    }

    @ViewBuilder private var node: some View {
        switch step.maneuver {
        case "start":
            LetterPin(letter: "A", filled: false, size: 32)
        case "arrive":
            LetterPin(letter: "B", size: 32)
        default:
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 32, height: 32)
                .background(Color.paper, in: Circle())
                .overlay(Circle().stroke(Color.hairline, lineWidth: 1.5))
        }
    }

    private var detailLine: String? {
        var bits: [String] = []
        if step.lengthM > 0 { bits.append(Format.distance(step.lengthM)) }
        if let d = step.detail { bits.append(d) }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    private var icon: String {
        switch step.maneuver {
        case "slight_left": "arrow.up.left"
        case "slight_right": "arrow.up.right"
        case "left": "arrow.turn.up.left"
        case "right": "arrow.turn.up.right"
        case "sharp_left": "arrow.uturn.left"
        case "sharp_right": "arrow.uturn.right"
        case "cross": "arrow.left.and.right"
        default: "arrow.up"
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
    var originName: String = ""
    var destinationName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.even(.headline))
                    if loading {
                        Text("Reading this spot…").font(.even(.subheadline)).foregroundStyle(.secondary)
                    } else if let info, info.found {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(info.access == "both_ways" ? pathClass(info).color : Color.warning)
                                .frame(width: 8, height: 8)
                            Text(info.verdict ?? "").font(.even(.subheadline)).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No sidewalk data here").font(.even(.subheadline)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.even(.caption, .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.paperDeep, in: Circle())
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

            HStack(spacing: 10) {
                PinActionButton(letter: "A", title: "Start here",
                                subtitle: originName.isEmpty ? "Set as start" : "Instead of \(originName)",
                                prominent: false, action: onRouteFrom)
                PinActionButton(letter: "B", title: "Go here",
                                subtitle: destinationName.isEmpty ? "Set as destination" : "Instead of \(destinationName)",
                                prominent: true, action: onRouteTo)
            }
        }
    }

    private func inline(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: label)
            Text(value).font(.even(.subheadline, .semibold)).monospacedDigit()
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
        let style = StyleStore.shared.current
        VStack(alignment: .leading, spacing: 2) {
            header("Slope", first: true)
            row(line(.slopeEasy), "Easy", "Under 3%")
            row(line(.slopeModerate), "Moderate", limit.map { "3 to \($0)%" } ?? "Within your limits")
            row(line(.slopeOver, dashed: true), "Over your limit", limit.map { "Over \($0)%, avoided" } ?? "Avoided")

            header("Curbs")
            row(CurbMarker(kind: .unknown), "Not surveyed", "Curb status unknown")
            row(CurbMarker(kind: .poorRamp), "Steep or worn ramp", "Usable with care")
            row(CurbMarker(kind: .barrier), "No curb ramp", "Not passable")

            header("Map")
            row(LetterPin(letter: "A", filled: false, size: 20), "Start", "Where you begin")
            row(LetterPin(letter: "B", size: 20), "Destination", "Where you're going")
            row(Capsule().fill(Color.sun).frame(width: 22, height: 4), "Gap", "Distance your limits can't cover")
        }
        .padding(8)
        .frame(width: 250, alignment: .leading)
        .background(Color.paper, in: .rect(cornerRadius: style.corner))
        .overlay(RoundedRectangle(cornerRadius: style.corner).stroke(Color.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map legend")
    }

    private func header(_ text: String, first: Bool = false) -> some View {
        SectionLabel(text: text)
            .padding(.horizontal, 8)
            .padding(.top, first ? 2 : 10)
            .padding(.bottom, 4)
    }

    private func row<Icon: View>(_ icon: Icon, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            icon.frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.even(.subheadline, .semibold))
                Text(detail).font(.even(.caption)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
    }

    private func line(_ color: Color, dashed: Bool = false) -> some View {
        ZStack {
            Capsule().fill(color).frame(width: 22, height: 6)
            if dashed { Capsule().fill(.white).frame(width: 7, height: 2) }
        }
    }
}

// MARK: - profile picker, opens beside the controls like the legend

struct ProfilePanel: View {
    @Binding var selection: Preset
    let onPicked: () -> Void
    let onSetUpAgain: () -> Void

    var body: some View {
        let style = StyleStore.shared.current
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: "How you get around")
                .padding(.horizontal, 8)
                .padding(.top, 2)
                .padding(.bottom, 6)

            ForEach(Preset.allCases) { preset in
                let isOn = selection == preset
                Button {
                    selection = preset
                    onPicked()
                } label: {
                    HStack(spacing: 10) {
                        PresetIcon(preset: preset, size: 20)
                            .foregroundStyle(isOn ? Color.onHighlight : Color.primary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(preset.label).font(.even(.subheadline, .semibold))
                            Text(preset.blurb)
                                .font(.even(.caption))
                                .foregroundStyle(isOn ? Color.onHighlight.opacity(0.8) : Color.secondary)
                                .lineLimit(2)
                        }
                        .foregroundStyle(isOn ? Color.onHighlight : Color.primary)
                        Spacer(minLength: 0)
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.even(.caption, .bold))
                                .foregroundStyle(Color.onHighlight)
                        }
                    }
                    .padding(8)
                    .background(isOn ? Color.highlight : .clear, in: .rect(cornerRadius: style.corner))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(preset.label). \(preset.limits)")
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }

            Rectangle().fill(Color.hairline).frame(height: 1).padding(.vertical, 6)

            Button(action: onSetUpAgain) {
                Label("Set up again", systemImage: "arrow.counterclockwise")
                    .font(.even(.footnote, .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(width: 250, alignment: .leading)
        .background(Color.paper, in: .rect(cornerRadius: style.corner))
        .overlay(RoundedRectangle(cornerRadius: style.corner).stroke(Color.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }
}

// MARK: - shared

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.even(.caption2, .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

// MARK: - big A / B action tiles

struct PinActionButton: View {
    let letter: String
    let title: String
    let subtitle: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        let style = StyleStore.shared.current
        Button(action: action) {
            HStack(spacing: 10) {
                // same badge as the pin it will move on the map
                LetterPin(letter: letter, filled: !prominent, size: 24)
                    .overlay(Circle().stroke(prominent ? Color.onBrand : .clear, lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.even(.subheadline, .bold))
                    Text(subtitle)
                        .font(.even(.caption))
                        .lineLimit(1)
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(prominent ? Color.onBrand : Color.primary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(prominent ? Color.brand : Color.paper, in: .rect(cornerRadius: style.corner + 2))
            .overlay(RoundedRectangle(cornerRadius: style.corner + 2)
                .stroke(prominent ? Color.clear : Color.ink.opacity(0.85), lineWidth: 1.25))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(.isButton)
    }
}

/// a small press-down so taps feel physical
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - pop-up shell

/// A centered card over a dimmed map. Hugs short content, scrolls long content.
struct TripPopup: View {
    let panel: TripPanel
    let response: RouteResponse
    let originName: String
    let destinationName: String
    let maxHeight: CGFloat
    let onClose: () -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            TripDetails(panel: panel, response: response,
                        originName: originName, destinationName: destinationName)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .frame(height: min(contentHeight, maxHeight))
        .overlay(alignment: .bottom) {
            // a soft fade says "there's more", instead of slicing through a row
            if contentHeight > maxHeight {
                LinearGradient(colors: [Color.paper.opacity(0), Color.paper], startPoint: .top, endPoint: .bottom)
                    .frame(height: 44)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: 520)
        .background(Color.paper, in: .rect(cornerRadius: 24))
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 32, height: 32)
                    .background(Color.paperDeep, in: Circle())
            }
            .padding(16)
            .accessibilityLabel("Close")
        }
        .clipShape(.rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.22), radius: 30, y: 14)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }
}
