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

    // Editorial: printed transit map. Paper panels, Helvetica, blue for actions, green for safe.
    static let editorial = EvenStyle(
        id: "editorial", name: "Editorial", blurb: "Paper, ink and Helvetica",
        fontDesign: .default, fontWidth: .standard,
        accent: Color(light: 0x1D4ED8, dark: 0x3B82F6),   // reliable blue: actions, B pin
        easy: Color(hex: 0x15803D),                         // safe green
        moderate: Color(hex: 0xD98E04),                     // amber
        over: Color(light: 0x1A1A1A, dark: 0xEDEDED),       // ink + white dashes: reads as blocked, never as a button
        mutedMap: true,
        routeWidth: 7, corner: 8, sheetCorner: 14, pin: .circle, buttonShape: .roundedRectangle(radius: 8),
        icons: .init(legend: "list.bullet", layers: "square.3.layers.3d",
                     fit: "viewfinder", swap: "arrow.up.arrow.down"),
        filledIcons: false, hierarchicalIcons: false)

    static let all: [EvenStyle] = [editorial]
}

/// The active style. Views read it while rendering, so switching restyles everything live.
@Observable
final class StyleStore {
    static let shared = StyleStore()

    var current: EvenStyle

    private init() {
        current = .editorial
    }
}
