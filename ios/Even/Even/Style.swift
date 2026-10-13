import Observation
import SwiftUI

/// One complete look for the app. Switch between them from the palette button on the map.
struct EvenStyle: Identifiable {
    enum PinShape { case circle, square }

    struct Icons {
        let legend: String
        let layers: String
        let fit: String
        let swap: String
    }

    let id: String
    let name: String
    let blurb: String

    // type
    let fontDesign: Font.Design
    let fontWidth: Font.Width

    // color
    let accent: Color
    let easy: Color
    let moderate: Color
    let over: Color
    let mutedMap: Bool

    // shape
    let routeWidth: CGFloat
    let corner: CGFloat          // controls and the places card
    let sheetCorner: CGFloat     // bottom panel
    let pin: PinShape
    let buttonShape: ButtonBorderShape

    // icons
    let icons: Icons
    let filledIcons: Bool
    let hierarchicalIcons: Bool

    static let all: [EvenStyle] = [
        EvenStyle(
            id: "lagoon", name: "Lagoon", blurb: "Calm teal, quiet map",
            fontDesign: .default, fontWidth: .standard,
            accent: Color(hex: 0x0B7A70), easy: Color(hex: 0x14B8A6), moderate: Color(hex: 0xF5A524),
            over: Color(hex: 0xE5484D), mutedMap: true,
            routeWidth: 8, corner: 12, sheetCorner: 22, pin: .circle, buttonShape: .capsule,
            icons: .init(legend: "list.bullet.rectangle", layers: "square.3.layers.3d.down.right",
                         fit: "scope", swap: "arrow.up.arrow.down"),
            filledIcons: false, hierarchicalIcons: false),

        EvenStyle(
            id: "transit", name: "Transit", blurb: "Wayfinding signage, condensed and square",
            fontDesign: .default, fontWidth: .condensed,
            accent: Color(hex: 0x1D4ED8), easy: Color(hex: 0x2563EB), moderate: Color(hex: 0xF59E0B),
            over: Color(hex: 0xDC2626), mutedMap: true,
            routeWidth: 9, corner: 6, sheetCorner: 10, pin: .square, buttonShape: .roundedRectangle(radius: 6),
            icons: .init(legend: "info.square", layers: "map", fit: "viewfinder", swap: "arrow.up.arrow.down.square"),
            filledIcons: true, hierarchicalIcons: false),

        EvenStyle(
            id: "pop", name: "Pop", blurb: "Rounded, bright and playful",
            fontDesign: .rounded, fontWidth: .standard,
            accent: Color(hex: 0x7C3AED), easy: Color(hex: 0x22C55E), moderate: Color(hex: 0xFACC15),
            over: Color(hex: 0xF43F5E), mutedMap: false,
            routeWidth: 10, corner: 20, sheetCorner: 32, pin: .circle, buttonShape: .capsule,
            icons: .init(legend: "questionmark.bubble", layers: "paintbrush.pointed",
                         fit: "location.viewfinder", swap: "arrow.triangle.swap"),
            filledIcons: true, hierarchicalIcons: true),

        EvenStyle(
            id: "editorial", name: "Editorial", blurb: "Serif type, ink lines, restrained",
            fontDesign: .serif, fontWidth: .standard,
            accent: Color(hex: 0x111827), easy: Color(hex: 0x1F2937), moderate: Color(hex: 0xD97706),
            over: Color(hex: 0xB91C1C), mutedMap: true,
            routeWidth: 6, corner: 8, sheetCorner: 16, pin: .circle, buttonShape: .roundedRectangle(radius: 8),
            icons: .init(legend: "text.book.closed", layers: "square.stack.3d.up",
                         fit: "arrow.up.left.and.arrow.down.right", swap: "arrow.up.arrow.down"),
            filledIcons: false, hierarchicalIcons: false),

        // Okabe-Ito palette: distinguishable with the common types of color blindness
        EvenStyle(
            id: "clearsight", name: "Clear Sight", blurb: "Color-blind safe palette, bold lines",
            fontDesign: .default, fontWidth: .standard,
            accent: Color(hex: 0x0072B2), easy: Color(hex: 0x0072B2), moderate: Color(hex: 0xE69F00),
            over: Color(hex: 0xD55E00), mutedMap: true,
            routeWidth: 10, corner: 12, sheetCorner: 22, pin: .square, buttonShape: .roundedRectangle(radius: 10),
            icons: .init(legend: "eye", layers: "square.3.layers.3d", fit: "scope", swap: "arrow.up.arrow.down"),
            filledIcons: true, hierarchicalIcons: false),
    ]
}

/// The active style. Views read it while rendering, so switching restyles everything live.
@Observable
final class StyleStore {
    static let shared = StyleStore()

    var current: EvenStyle {
        didSet { UserDefaults.standard.set(current.id, forKey: "evenStyle") }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "evenStyle")
        current = EvenStyle.all.first { $0.id == saved } ?? EvenStyle.all[0]
    }
}
