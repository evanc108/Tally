import SwiftUI

enum TallyColors {
    // Core
    static let textPrimary = Color(hex: 0x1C1C1E)
    static let textSecondary = Color(hex: 0x8E8E93)
    static let bgPrimary = Color(hex: 0xFFFFFF)
    static let bgSecondary = Color(hex: 0xF2F2F7)
    static let divider = Color(hex: 0xE5E5EA)

    // Primary accent — green throughout
    static let accent = Color(hex: 0x30D158)

    // Status
    static let statusSuccess = Color(hex: 0x30D158)
    static let statusAlert = Color(hex: 0xFF453A)
    static let statusPending = Color(hex: 0xFFD60A)
    static let statusSocial = Color(hex: 0xBF5AF2)
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
