import Foundation

enum TallySpacing {
    // ── Base scale ────────────────────────────────────────────────────────────
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let lg:   CGFloat = 16
    static let xl:   CGFloat = 24
    static let xxl:  CGFloat = 32
    static let xxxl: CGFloat = 48

    // ── Layout ────────────────────────────────────────────────────────────────
    static let screenPadding: CGFloat = 20   // was 16
    static let cardPadding:   CGFloat = 20   // was 16
    static let cardGap:       CGFloat = 12

    // ── Corners ───────────────────────────────────────────────────────────────
    static let cardCornerRadius:   CGFloat = 16   // modern rounded
    static let cardInnerRadius:    CGFloat = 12   // nested content
    static let buttonCornerRadius: CGFloat = 16   // soft rounded buttons
    static let chipCornerRadius:   CGFloat = 20   // capsule-like for pills/chips

    // ── Interactive elements ───────────────────────────────────────────────────
    static let buttonHeight:      CGFloat = 56
    static let inputHeight:       CGFloat = 52
    static let listItemMinHeight: CGFloat = 60

    // ── Action grid ──────────────────────────────────────────────────────────
    static let actionIconSize:    CGFloat = 28
    static let actionButtonSize:  CGFloat = 56
}
