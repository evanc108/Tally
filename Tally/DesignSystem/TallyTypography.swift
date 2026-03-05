import SwiftUI

enum TallyFont {
    // ── Display ───────────────────────────────────────────────────────────────
    /// 32pt — hero heading, extrabold, tight tracking
    static let display = Font.custom("Inter", size: 32).weight(.heavy)

    // ── Headings ──────────────────────────────────────────────────────────────
    /// 24pt — screen-level heading (H1)
    static let largeTitle = Font.custom("Inter", size: 24).weight(.bold)
    /// 20pt — section heading (H2)
    static let title      = Font.custom("Inter", size: 20).weight(.bold)
    /// 17pt — card header / sub-section title (H3)
    static let titleSemibold = Font.custom("Inter", size: 17).weight(.semibold)

    // ── Body ─────────────────────────────────────────────────────────────────
    static let body         = Font.custom("Inter", size: 15).weight(.regular)
    static let bodySemibold = Font.custom("Inter", size: 15).weight(.medium)

    // ── Small / Captions ─────────────────────────────────────────────────────
    /// 13pt — small text, labels
    static let small   = Font.custom("Inter", size: 13).weight(.regular)
    static let caption = Font.custom("Inter", size: 12).weight(.medium)
    /// 11pt — overline, tags, badges, tab bar labels
    static let smallLabel = Font.custom("Inter", size: 11).weight(.bold)

    // ── Amounts (monospaced) ────────────────────────────────────────────────
    /// 32pt — hero balance / primary number on a screen
    static let heroAmount = Font.system(size: 32, weight: .heavy, design: .monospaced)
    /// 24pt — large transaction / card amounts
    static let amountsLarge = Font.system(size: 24, weight: .bold, design: .monospaced)
    /// 20pt — standard row amounts
    static let amounts = Font.system(size: 20, weight: .medium, design: .monospaced)

    // ── Button text ──────────────────────────────────────────────────────────
    /// 15pt — primary & secondary buttons
    static let button = Font.custom("Inter", size: 15).weight(.semibold)
    /// 13pt — small buttons
    static let buttonSmall = Font.custom("Inter", size: 13).weight(.semibold)
    /// 13pt — label for input fields
    static let inputLabel = Font.custom("Inter", size: 13).weight(.medium)
}
