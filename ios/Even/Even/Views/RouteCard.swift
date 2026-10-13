import SwiftUI

struct RouteCard: View {
    let route: Route
    let profile: Profile
    let isSelected: Bool
    let onSelect: () -> Void

    private var s: RouteSummary { route.summary }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    badge
                }

                Text("\(duration) · \(distance(s.distanceM))")
                    .font(.title3.bold())

                if !route.reachesDestination, let gap = route.gapM {
                    Label("Ends \(distance(gap)) from your destination, the closest you can get",
                          systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 12) {
                    stat("Steepest up", percent(s.maxUphill), over: s.maxUphill > profile.maxUphill)
                    stat("Steepest down", percent(s.maxDownhill), over: s.maxDownhill > profile.maxDownhill)
                    stat("Crossings", crossings, over: s.barrierCurbs > 0)
                }

                if s.steepRamps + s.poorRamps > 0 {
                    Label("\(s.steepRamps + s.poorRamps) ramps on the way are steep or worn",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.evenTeal.opacity(0.06) : Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.evenTeal : Color(uiColor: .separator), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        // VoiceOver reads one clear sentence instead of a dozen fragments
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: pieces

    private var title: String {
        route.kind == .fitsProfile ? "Even route" : "Shortest route"
    }

    @ViewBuilder private var badge: some View {
        let fits = route.fitsProfile
        Text(fits ? "Fits your profile" : "Breaks \(route.breaks.count) \(route.breaks.count == 1 ? "limit" : "limits")")
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(fits ? Color.evenTeal : Color.slopeOver)
            .background((fits ? Color.evenTeal : Color.slopeOver).opacity(0.12), in: Capsule())
    }

    private func stat(_ label: String, _ value: String, over: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).foregroundStyle(over ? Color.slopeOver : .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var crossings: String {
        if s.barrierCurbs > 0 { return "\(s.barrierCurbs) blocked" }
        if s.unknownCurbs > 0 { return "\(s.unknownCurbs) unverified" }
        return "All ramped"
    }

    private var duration: String {
        Duration.seconds(s.durationS).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    private func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func percent(_ v: Double) -> String { String(format: "%.1f%%", v) }

    private var spokenSummary: String {
        var parts = [title, "\(duration), \(distance(s.distanceM))",
                     "Steepest uphill \(percent(s.maxUphill)), steepest downhill \(percent(s.maxDownhill))",
                     "Crossings: \(crossings)"]
        if let gap = route.gapM, !route.reachesDestination {
            parts.append("Ends \(distance(gap)) from your destination")
        }
        parts.append(route.fitsProfile ? "Fits your profile"
                                       : "Breaks your limits for \(route.breaks.joined(separator: ", "))")
        return parts.joined(separator: ". ")
    }
}
