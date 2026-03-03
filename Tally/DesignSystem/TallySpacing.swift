import Foundation

enum TallySpacing {
    // ── Base scale (4px grid) ────────────────────────────────────────────────
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let lg:   CGFloat = 16
    static let xl:   CGFloat = 20
    static let xxl:  CGFloat = 24
    static let xxxl: CGFloat = 32
    static let xxxxl: CGFloat = 40
    static let jumbo: CGFloat = 48
    static let mega:  CGFloat = 64

    // ── Layout ────────────────────────────────────────────────────────────────
    static let screenPadding: CGFloat = 28
    static let cardPadding:   CGFloat = 24
    static let cardGap:       CGFloat = 16

    // ── Corners ───────────────────────────────────────────────────────────────
    static let cardCornerRadius:   CGFloat = 8
    static let cardInnerRadius:    CGFloat = 8
    static let buttonCornerRadius: CGFloat = 8
    static let chipCornerRadius:   CGFloat = 20   // capsule-like for pills/chips

    // ── Interactive elements ─────────────────────────────────────────────────
    static let buttonHeightPrimary:   CGFloat = 52
    static let buttonHeightSecondary: CGFloat = 44
    static let buttonHeightSmall:     CGFloat = 36
    static let buttonHeight:          CGFloat = 52  // default (primary)
    static let inputHeight:           CGFloat = 52
    static let listItemMinHeight:     CGFloat = 60
}

// MARK: - Corner Radii

enum TallyRadius {
    static let sm:   CGFloat = 4
    static let md:   CGFloat = 8
    static let lg:   CGFloat = 12
    static let xl:   CGFloat = 16
    static let full: CGFloat = 9999
}
