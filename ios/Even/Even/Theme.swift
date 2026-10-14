import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }

    /// separate values for light and dark mode, so text colors keep their contrast
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    // ink and paper
    static let ink = Color(hex: 0x111111)
    static let inkSoft = Color(hex: 0x2A2A2A)
    static let paper = Color(light: 0xFBFAF7, dark: 0x17181B)       // panels
    static let paperDeep = Color(light: 0xF1EEE7, dark: 0x222429)   // tiles, wells
    static let hairline = Color(light: 0xDDD9CF, dark: 0x34363C)    // 1pt rules and borders
    static let onBrand = Color.white                                   // text on a blue button
    static var highlight: Color { brand }                              // blue: selection, active controls
    static let onHighlight = Color.white                               // text and icons on blue
    static let safe = Color(light: 0x15803D, dark: 0x4ADE80)           // "fits you"
    static let warning = Color(light: 0xC62828, dark: 0xF87171)        // over-limit numbers and errors

    // brand: follows the active style (see Style.swift)
    static var brand: Color { StyleStore.shared.current.accent }
    static let brandSoft = Color(light: 0xDCE6FF, dark: 0x1E2A4A)    // light blue: selected rows
    static var brandBright: Color { StyleStore.shared.current.accent }  // kept for older call sites
    static let coral = Color(hex: 0xFF6B4A)                     // the dot in the wordmark, small accents
    static let sun = Color(hex: 0xF5A524)
    static let berry = Color(light: 0xD92D4B, dark: 0xFF6B81)   // over a limit, errors
    static let evenViolet = Color(hex: 0x7C5CFF)
    static let evenSky = Color(hex: 0x0EA5E9)

    // slope scale on the map and chart, also from the active style
    static var slopeEasy: Color { StyleStore.shared.current.easy }
    static var slopeModerate: Color { StyleStore.shared.current.moderate }
    static var slopeOver: Color { StyleStore.shared.current.over }

    // older name, still used in a couple of places
    static var evenTeal: Color { brand }
}

extension LinearGradient {
    static let brand = LinearGradient(colors: [Color(hex: 0x0B7A70), Color(hex: 0x14B8A6)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension SlopeClass {
    var color: Color {
        switch self {
        case .easy: .slopeEasy
        case .moderate: .slopeModerate
        case .over: .slopeOver
        }
    }

    var label: String {
        switch self {
        case .easy: "Easy"
        case .moderate: "Moderate"
        case .over: "Over limit"
        }
    }
}

/// classes used by the slope layer and inspect card
enum PathClass: String {
    case easy, moderate, over, steps, barrier

    var color: Color {
        switch self {
        case .easy: .slopeEasy
        case .moderate: .slopeModerate
        case .over: .slopeOver
        case .steps: Color(hex: 0x6B7280)
        case .barrier: .slopeOver
        }
    }
}

extension RouteKind {
    var title: String { self == .fitsProfile ? "Even route" : "Shortest" }
}

extension Preset {
    var shortLabel: String {
        switch self {
        case .manualWheelchair: "Manual chair"
        case .powerWheelchair: "Power chair"
        case .walker: "Walker"
        case .stroller: "Stroller"
        }
    }

    // mirrors PRESETS in api/models.py
    var blurb: String {
        switch self {
        case .manualWheelchair: "Gentle hills, a ramp at every curb"
        case .powerWheelchair: "Moderate hills, a ramp at every curb"
        case .walker: "Easy descents matter most"
        case .stroller: "No steps, hills are fine"
        }
    }

    var limits: String {
        switch self {
        case .manualWheelchair: "Up to 5% uphill and 8% downhill. Avoids steps and curbs without ramps."
        case .powerWheelchair: "Up to 8% uphill and downhill. Avoids steps and curbs without ramps."
        case .walker: "Up to 8% uphill and 5% downhill. Avoids steps and curbs without ramps."
        case .stroller: "Up to 12% uphill and 8% downhill. Avoids steps."
        }
    }

    /// icon for menus and lists; the walker uses our own cane glyph (Assets: CaneUser)
    var icon: Image {
        self == .walker ? Image("CaneUser") : Image(systemName: symbol)
    }

    var symbol: String {
        switch self {
        case .manualWheelchair: "figure.roll"
        case .powerWheelchair: "figure.roll.runningpace"
        case .walker: "figure.walk"
        case .stroller: "stroller.fill"
        }
    }
}

enum Format {
    static func duration(_ seconds: Double) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    static func distance(_ meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    static func percent(_ value: Double) -> String { String(format: "%.1f%%", value) }
}

// MARK: - Helvetica Neue, scaling with Dynamic Type

extension Font {
    private static func helvetica(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "HelveticaNeue-Bold"
        case .semibold, .medium: "HelveticaNeue-Medium"
        case .light, .thin, .ultraLight: "HelveticaNeue-Light"
        default: "HelveticaNeue"
        }
    }

    /// the app's type: a text style's size, in Helvetica Neue, scaling with the user's text size setting
    static func even(_ style: Font.TextStyle, _ weight: Font.Weight? = nil) -> Font {
        let size: CGFloat
        var w = weight ?? .regular
        switch style {
        case .largeTitle: size = 34
        case .title: size = 28
        case .title2: size = 22
        case .title3: size = 20
        case .headline: size = 17; if weight == nil { w = .bold }
        case .body: size = 17
        case .callout: size = 16
        case .subheadline: size = 15
        case .footnote: size = 13
        case .caption: size = 12
        case .caption2: size = 11
        default: size = 17
        }
        return .custom(helvetica(w), size: size, relativeTo: style)
    }

    /// fixed size, for map pins and badges that must not grow
    static func evenFixed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(helvetica(weight), fixedSize: size)
    }
}

/// Profile icon at a given size. SF Symbols size by font, the cane asset by frame.
struct PresetIcon: View {
    let preset: Preset
    var size: CGFloat = 20

    var body: some View {
        if preset == .walker {
            Image("CaneUser")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: preset.symbol)
                .font(.system(size: size * 0.85, weight: .medium))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Brutal: thick ink outlines, hard offset shadows, square corners

extension Color {
    /// outline and hard-shadow ink; flips to off-white in dark mode so edges stay visible
    static let line = Color(light: 0x111111, dark: 0xF2F0EB)
}

struct Brutal: ViewModifier {
    var fill: Color = .paper
    var shadow: CGFloat = 4
    var border: CGFloat = 2

    func body(content: Content) -> some View {
        content
            .background(fill, ignoresSafeAreaEdges: [])
            .overlay(Rectangle().stroke(Color.line, lineWidth: border))
            .background(Rectangle().fill(Color.line).offset(x: shadow, y: shadow))
    }
}

extension View {
    func brutal(fill: Color = .paper, shadow: CGFloat = 4, border: CGFloat = 2) -> some View {
        modifier(Brutal(fill: fill, shadow: shadow, border: border))
    }
}

/// Buttons that drop into their shadow when pressed.
struct BrutalButtonStyle: ButtonStyle {
    var fill: Color = .paper
    var shadow: CGFloat = 4

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .background(fill, ignoresSafeAreaEdges: [])
            .overlay(Rectangle().stroke(Color.line, lineWidth: 2))
            .background(Rectangle().fill(Color.line)
                .offset(x: pressed ? 0 : shadow, y: pressed ? 0 : shadow))
            .offset(x: pressed ? shadow : 0, y: pressed ? shadow : 0)
            .animation(.snappy(duration: 0.12), value: pressed)
    }
}

/// Big uppercase label text with a little tracking, like the button and chip labels.
extension Text {
    func shout(_ style: Font.TextStyle = .subheadline) -> some View {
        self.font(.even(style, .bold)).tracking(1.2).textCase(.uppercase)
    }
}

/// Outlined display type: the word drawn as an ink outline on paper.
struct OutlineText: View {
    let text: String
    let font: Font
    var tracking: CGFloat = 0
    var stroke: Color = .line
    var fill: Color = .paper
    var width: CGFloat = 1.6

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) * .pi / 4
                Text(text).font(font).tracking(tracking)
                    .foregroundStyle(stroke)
                    .offset(x: cos(a) * width, y: sin(a) * width)
            }
            Text(text).font(font).tracking(tracking).foregroundStyle(fill)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Faint graph-paper background.
struct GridPaper: View {
    var spacing: CGFloat = 28

    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            var x: CGFloat = 0
            while x <= size.width { p.move(to: .init(x: x, y: 0)); p.addLine(to: .init(x: x, y: size.height)); x += spacing }
            var y: CGFloat = 0
            while y <= size.height { p.move(to: .init(x: 0, y: y)); p.addLine(to: .init(x: size.width, y: y)); y += spacing }
            ctx.stroke(p, with: .color(Color.hairline.opacity(0.7)), lineWidth: 0.6)
        }
        .background(Color.paper)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
