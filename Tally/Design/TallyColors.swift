import SwiftUI

enum TallyColors {
    // MARK: - Neutrals

    static let white = Color(hex: 0xFFFFFF)
    static let bgPrimary = Color(hex: 0xF7F8FA)
    static let border = Color(hex: 0xE0E4E8)
    static let borderLight = Color(hex: 0xF0F2F4)

    // MARK: - Text

    static let textPrimary = Color(hex: 0x1A1D1F)
    static let textSecondary = Color(hex: 0x6F767E)
    static let textTertiary = Color(hex: 0x9A9FA5)
    static let textHint = Color(hex: 0xC0C4C8)

    // MARK: - Brand / Accent

    static let accent = Color(hex: 0x00C805)
    static let accentLight = Color(hex: 0xE8F8E8)
    static let accentDark = Color(hex: 0x00A504)

    // MARK: - Status

    static let statusAlert = Color(hex: 0xFF3B30)
    static let statusAlertLight = Color(hex: 0xFFF0EF)
    static let statusWarning = Color(hex: 0xF5A623)
    static let statusWarningLight = Color(hex: 0xFFF8E0)
    static let statusInfo = Color(hex: 0x2563EB)
    static let statusInfoLight = Color(hex: 0xEFF6FF)
}

// MARK: - Hex Initializer

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
