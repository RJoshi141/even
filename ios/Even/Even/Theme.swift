import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    // same palette as the mockup
    static let evenTeal = Color(hex: 0x0B5D52)
    static let slopeEasy = Color(hex: 0x1F9A83)
    static let slopeModerate = Color(hex: 0xE0A23A)
    static let slopeOver = Color(hex: 0xB42318)
}

extension SlopeClass {
    var color: Color {
        switch self {
        case .easy: .slopeEasy
        case .moderate: .slopeModerate
        case .over: .slopeOver
        }
    }
}
