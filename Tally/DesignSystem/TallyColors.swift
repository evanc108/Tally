import SwiftUI

enum TallyColors {
    // Core text
    static let textPrimary   = Color(hex: 0x111111)
    static let textSecondary = Color(hex: 0x8E8E93)
    static let textTertiary  = Color(hex: 0xC7C7CC)

    // Backgrounds
    static let bgPrimary   = Color(hex: 0xFFFFFF)
    static let bgSecondary = Color(hex: 0xF5F5F7)  // warmer than before
    static let bgSurface   = Color(hex: 0xFAFAFA)  // elevated card surface

    static let divider = Color(hex: 0xE5E5EA)

    // Ink — near-black for dark buttons / heavy elements
    static let ink = Color(hex: 0x111111)

    // Primary accent — green
    static let accent = Color(hex: 0x30D158)

    // Status
    static let statusSuccess = Color(hex: 0x30D158)
    static let statusAlert   = Color(hex: 0xFF453A)
    static let statusPending = Color(hex: 0xFFD60A)
    static let statusSocial  = Color(hex: 0xBF5AF2)

    // Card palette — soft pastels for circle cards, category chips, etc.
    static let cardMint    = Color(hex: 0xD4F5E2)
    static let cardLavender = Color(hex: 0xE5D9F2)
    static let cardPeach   = Color(hex: 0xFFE5D9)
    static let cardCream   = Color(hex: 0xFFF3D9)
    static let cardBlush   = Color(hex: 0xFFD9E5)
    static let cardSky     = Color(hex: 0xD9EEFF)

    /// Cycles through the card palette by index (for deterministic circle colors).
    static let cardPalette: [Color] = [
        cardMint, cardLavender, cardPeach, cardCream, cardBlush, cardSky
    ]

    static func cardColor(for index: Int) -> Color {
        cardPalette[abs(index) % cardPalette.count]
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: opacity
        )
    }
}