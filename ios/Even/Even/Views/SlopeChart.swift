import Charts
import SwiftUI

/// Grade along the route as bars, with dashed lines at the user's limits.
struct SlopeChart: View {
    let route: Route
    let profile: Profile
    var height: CGFloat = 64

    private struct Bar: Identifiable {
        let id: Int
        let start: Double
        let end: Double
        let grade: Double
        let color: Color
    }

    private var bars: [Bar] {
        var out: [Bar] = []
        var x = 0.0
        for (i, s) in route.segments.enumerated() {
            // clamp so one extreme stretch doesn't flatten everything else
            out.append(Bar(id: i, start: x, end: x + max(s.lengthM, 1),
                           grade: min(max(s.grade, -16), 16), color: s.slope.color))
            x += s.lengthM
        }
        return out
    }

    var body: some View {
        Chart {
            RuleMark(y: .value("Flat", 0.0))
                .foregroundStyle(Color.secondary.opacity(0.25))
            ForEach(bars) { b in
                RectangleMark(xStart: .value("Start", b.start), xEnd: .value("End", b.end),
                              yStart: .value("Base", 0.0), yEnd: .value("Grade", b.grade))
                    .foregroundStyle(b.color)
            }
            RuleMark(y: .value("Uphill limit", profile.maxUphill))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary)
            RuleMark(y: .value("Downhill limit", -profile.maxDownhill))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: -bottom...top)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slope along the route")
        .accessibilityValue(spokenSummary)
    }

    // scale to the limits and the route's steepest point, with a little headroom, so the bars fill the chart
    private var top: Double {
        let steepest = route.segments.map(\.grade).max() ?? 0
        return min(16, max(profile.maxUphill, steepest) + 2)
    }

    private var bottom: Double {
        let steepest = -(route.segments.map(\.grade).min() ?? 0)
        return min(16, max(profile.maxDownhill, steepest) + 2)
    }

    private var spokenSummary: String {
        let total = max(route.segments.reduce(0) { $0 + $1.lengthM }, 1)
        let over = route.segments.filter { $0.slope == .over }.reduce(0) { $0 + $1.lengthM }
        if over == 0 { return "Stays within your limits the whole way" }
        return "\(Int((over / total * 100).rounded())) percent of the way is over your limits"
    }
}
