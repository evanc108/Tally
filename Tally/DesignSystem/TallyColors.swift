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

    // Primary accent — sage green
    static let accent     = Color(hex: 0x52B788)
    static let accentDark = Color(hex: 0x3A8A63)   // gradient dark end

    // Glass
    static let glassBorder = Color.white.opacity(0.2)
    static let glassShadow = Color.black.opacity(0.06)

    // Status
    static let statusSuccess = Color(hex: 0x52B788)
    static let statusAlert   = Color(hex: 0xFF453A)
    static let statusPending = Color(hex: 0xFFD60A)
    static let statusSocial  = Color(hex: 0xBF5AF2)

    // Card palette — saturated mid-tone pastels for circle cards
    static let cardMint    = Color(hex: 0x8BD8AB)
    static let cardLavender = Color(hex: 0xB8A4D8)
    static let cardPeach   = Color(hex: 0xF0A889)
    static let cardCream   = Color(hex: 0xE8C96A)
    static let cardBlush   = Color(hex: 0xE894AB)
    static let cardSky     = Color(hex: 0x7EB8E0)

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