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

    // the command bar and strong text
    static let ink = Color(hex: 0x0E1726)
    static let inkSoft = Color(hex: 0x1C2738)

    // brand: follows the active style (see Style.swift)
    static var brand: Color { StyleStore.shared.current.accent }
    static var brandBright: Color { StyleStore.shared.current.accent }
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
