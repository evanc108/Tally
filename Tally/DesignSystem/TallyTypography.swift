import SwiftUI

enum TallyFont {
    // ── Display ───────────────────────────────────────────────────────────────
    /// 56pt — hero balance / primary number on a screen
    static let heroAmount = Font.system(size: 56, weight: .bold, design: .monospaced)
    /// 40pt — large feature number (e.g. total spend, card balance)
    static let display    = Font.system(size: 40, weight: .heavy, design: .monospaced)

    // ── Titles ────────────────────────────────────────────────────────────────
    /// 34pt — screen-level heading
    static let largeTitle = Font.system(size: 34, weight: .bold)
    /// 22pt — section heading
    static let title      = Font.system(size: 22, weight: .bold)
    /// 20pt — card header / sub-section title
    static let titleSemibold = Font.system(size: 20, weight: .semibold)

    // ── Body ─────────────────────────────────────────────────────────────────
    static let bodySemibold = Font.system(size: 17, weight: .semibold)
    static let body         = Font.system(size: 17, weight: .regular)

    // ── Captions / Labels ─────────────────────────────────────────────────────
    static let caption    = Font.system(size: 13, weight: .regular)
    /// 11pt — tags, badges, tab bar labels, chips
    static let smallLabel = Font.system(size: 11, weight: .medium)

    // ── Amounts (monospaced) ──────────────────────────────────────────────────
    /// 28pt — large transaction / card amounts
    static let amountsLarge = Font.system(size: 28, weight: .semibold, design: .monospaced)
    /// 20pt — standard row amounts
    static let amounts      = Font.system(size: 20, weight: .medium,   design: .monospaced)
}
