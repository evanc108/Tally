import SwiftUI

enum TallyColors {
    // Core text
    static let textPrimary   = Color(hex: 0x1A1D1F)  // "Blue Black"
    static let textSecondary = Color(hex: 0x6F767E)
    static let textTertiary  = Color(hex: 0x9A9FA5)
    static let textPlaceholder = Color(hex: 0xC0C4C8) // "Slate Hint"

    // Backgrounds
    static let bgPrimary   = Color(hex: 0xFFFFFF)  // "White"
    static let bgSecondary = Color(hex: 0xF7F8FA)  // "Background"
    static let bgSurface   = Color(hex: 0xF7F8FA)  // alias for bgSecondary

    static let white  = Color(hex: 0xFFFFFF)
    static let divider = Color(hex: 0xE0E4E8)       // "Border"
    static let border  = Color(hex: 0xE0E4E8)
    static let borderLight = Color(hex: 0xF0F2F4)   // "Border Light"

    // Ink — near-black for dark buttons / heavy elements
    static let ink = Color(hex: 0x1A1D1F)            // "Blue Black"

    // Primary accent — mint green
    static let accent      = Color(hex: 0x52B788)    // "Mint Leaf 2"
    static let accentDark  = Color(hex: 0x40916C)    // "Sea Green" (hover)
    static let accentLight = Color(hex: 0xE8F8E8)    // "Green Light"

    // Extended green palette
    static let mintGreen   = Color(hex: 0x77BFA3)    // "Mint Green"
    static let frostedMint = Color(hex: 0xD8F3DC)    // "Frosted Mint"
    static let celadon     = Color(hex: 0xB7E4C7)    // "Celadon"
    static let celadon2    = Color(hex: 0x95D5B2)    // "Celadon 2"
    static let mintLeaf    = Color(hex: 0x74C69D)    // "Mint Leaf"
    static let seaGreen    = Color(hex: 0x40916C)    // "Sea Green"
    static let hunterGreen = Color(hex: 0x2D6A4F)    // "Hunter Green"
    static let pineTeal    = Color(hex: 0x1B4332)    // "Pine Teal"

    // Glass
    static let glassBorder = Color.white.opacity(0.2)
    static let glassShadow = Color.black.opacity(0.06)

    // Status — each has a background + foreground pair
    static let statusSuccess   = Color(hex: 0x0A7B0A)  // "Active Green" text
    static let statusSuccessBg = Color(hex: 0xE8F8E8)  // "Active Green" bg
    static let statusAlert     = Color(hex: 0xF1574E)  // "Declined Red" text
    static let statusAlertBg   = Color(hex: 0xFFF0EF)  // "Declined Red" bg
    static let statusPending   = Color(hex: 0xA06800)  // "Pending Yellow" text
    static let statusPendingBg = Color(hex: 0xFFF8E0)  // "Pending Yellow" bg
    static let statusInfo      = Color(hex: 0x2F80D6)  // "Processing Blue" text
    static let statusInfoBg    = Color(hex: 0xEFF6FF)  // "Processing Blue" bg
    static let statusSocial    = Color(hex: 0x52B788)  // mapped to accent for social indicators

    // Danger button colors
    static let dangerText = Color(hex: 0xF1574E)
    static let dangerBg   = Color(hex: 0xFFF0EF)
    static let dangerHoverBg = Color(hex: 0xFFD7D4)

    // Inactive / slate
    static let slateHint     = Color(hex: 0xC0C4C8)
    static let slateHintDark = Color(hex: 0x8D9297)

    // Card palette — soft pastels for circle cards, category chips, etc.
    static let cardMint    = Color(hex: 0xD8F3DC)  // Frosted Mint
    static let cardLavender = Color(hex: 0xE5D9F2)
    static let cardPeach   = Color(hex: 0xFFE5D9)
    static let cardCream   = Color(hex: 0xFFF8E0)  // Pending Yellow bg
    static let cardBlush   = Color(hex: 0xFFF0EF)  // Declined Red bg
    static let cardSky     = Color(hex: 0xEFF6FF)  // Processing Blue bg

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
