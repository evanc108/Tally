import SwiftUI

// MARK: - Typography Tokens

/// Centralized typography system. Every text element in the app should reference
/// a token from this enum — never use inline `.font(.system(...))` for text.
///
/// **Hierarchy**:  Brand → Display → Heading → Body → Caption → Label
/// **Amounts** use system monospaced for tabular alignment.
/// **Icons** use `TallyIcon` size tokens below.
enum TallyFont {

    // ── Private Font Names ──────────────────────────────────────────────────
    // PostScript names for bundled Inter static weight files.
    // Verify at runtime if fonts don't render (see FontDebug below).
    private static let inter        = "Inter-Regular"
    private static let interMedium  = "Inter-Medium"
    private static let interSemi    = "Inter-SemiBold"
    private static let interBold    = "Inter-Bold"
    private static let interXBold   = "Inter-ExtraBold"
    private static let interBlack   = "Inter-Black"

    // ── Brand ───────────────────────────────────────────────────────────────
    /// 56pt — Welcome screen hero "tally" wordmark
    static let brandHero      = Font.custom(interBlack, size: 56)
    /// 36pt — Large circle initial (circle ready screen)
    static let brandInitial   = Font.custom(interBold, size: 36)
    /// 28pt — Auth header "tally" wordmark
    static let brandLarge     = Font.custom(interBlack, size: 28)
    /// 22pt — Card face "tally" brand
    static let brandCard      = Font.custom(interBold, size: 22)
    /// 20pt — Nav bar "Mntly" brand
    static let brandNav       = Font.custom(interBold, size: 20)
    /// 18pt — Mini card "tally" brand
    static let brandMiniCard  = Font.custom(interBold, size: 18)
    /// 17pt — Circle feed card "tally" brand
    static let brandCardSmall = Font.custom(interBold, size: 17)
    /// 11pt — Onboarding mini card "tally" brand
    static let brandTiny      = Font.custom(interXBold, size: 11)

    // ── Display ─────────────────────────────────────────────────────────────
    /// 32pt — hero heading, tight tracking
    static let display     = Font.custom(interXBold, size: 32)
    /// 34pt — large decorative text (camera prompts, placeholders)
    static let displayIcon = Font.custom(interRegular, size: 34)

    // ── Headings ────────────────────────────────────────────────────────────
    /// 24pt — screen-level heading (H1)
    static let largeTitle    = Font.custom(interBold, size: 24)
    /// 20pt — section heading (H2)
    static let title         = Font.custom(interBold, size: 20)
    /// 17pt — card header / sub-section title (H3)
    static let titleSemibold = Font.custom(interSemi, size: 17)

    // ── Body ────────────────────────────────────────────────────────────────
    /// 18pt — tagline / large body text
    static let bodyLarge    = Font.custom(interMedium, size: 18)
    /// 16pt — input field text, large body
    static let bodyInput    = Font.custom(interMedium, size: 16)
    /// 15pt — standard body text
    static let body         = Font.custom(inter, size: 15)
    /// 15pt — emphasized body text
    static let bodySemibold = Font.custom(interMedium, size: 15)
    /// 14pt — secondary descriptions, labels
    static let bodySmall    = Font.custom(inter, size: 14)
    /// 14pt — bold secondary labels ("Total Balance")
    static let bodySmallBold = Font.custom(interBold, size: 14)

    // ── Captions / Labels ───────────────────────────────────────────────────
    /// 13pt — overline section headers ("YOUR CIRCLES", "TRANSACTIONS")
    static let overline    = Font.custom(interBold, size: 13)
    /// 13pt — small text, labels
    static let small       = Font.custom(inter, size: 13)
    /// 13pt — small semibold (links, small buttons)
    static let smallSemibold = Font.custom(interSemi, size: 13)
    /// 13pt — small medium (input labels, "or" divider)
    static let smallMedium = Font.custom(interMedium, size: 13)
    /// 12pt — caption text
    static let caption     = Font.custom(interMedium, size: 12)
    /// 12pt — bold caption (Stripe badge, small labels)
    static let captionBold = Font.custom(interBold, size: 12)
    /// 11pt — overline tags, badges, tab bar labels
    static let smallLabel  = Font.custom(interBold, size: 11)
    /// 11pt — semibold small label ("Settled", status badges)
    static let smallLabelSemibold = Font.custom(interSemi, size: 11)
    /// 10pt — tab bar text, micro labels
    static let micro       = Font.custom(interMedium, size: 10)
    /// 10pt — bold micro ("Selected" badge)
    static let microBold   = Font.custom(interBold, size: 10)
    /// 8pt — decorative mini text (onboarding illustrations)
    static let decorative  = Font.custom(inter, size: 8)
    /// 8pt — decorative mini text bold
    static let decorativeBold = Font.custom(interBold, size: 8)
    /// 7pt — ultra-small decorative text
    static let decorativeTiny = Font.custom(inter, size: 7)

    // ── Amounts (system monospaced for tabular alignment) ───────────────────
    /// 48pt — hero balance on card detail
    static let heroAmount    = Font.system(size: 48, weight: .bold, design: .monospaced)
    /// 48pt — large display amount (light weight, receipt totals)
    static let heroAmountLight = Font.system(size: 48, weight: .light, design: .default)
    /// 38pt — main balance on home screen
    static let balanceAmount = Font.system(size: 38, weight: .bold, design: .rounded)
    /// 28pt — card balance amounts
    static let amountsXL     = Font.system(size: 28, weight: .bold, design: .monospaced)
    /// 24pt — verification code input
    static let codeDisplay   = Font.system(size: 24, weight: .bold, design: .monospaced)
    /// 20pt — standard row amounts
    static let amounts       = Font.system(size: 20, weight: .medium, design: .monospaced)
    /// 18pt — card number display
    static let cardNumber    = Font.system(size: 18, weight: .medium, design: .monospaced)
    /// 17pt — transaction row amounts
    static let amountsSmall  = Font.system(size: 17, weight: .bold, design: .rounded)
    /// 14pt — small card numbers, monospaced details
    static let cardNumberSmall = Font.system(size: 14, weight: .medium, design: .monospaced)
    /// 13pt — mini card number
    static let cardNumberMini = Font.system(size: 13, weight: .medium, design: .monospaced)

    // ── Buttons ─────────────────────────────────────────────────────────────
    /// 16pt — large/primary button text
    static let buttonLarge = Font.custom(interBold, size: 16)
    /// 15pt — standard button text
    static let button      = Font.custom(interSemi, size: 15)
    /// 15pt — bold button text (auth buttons)
    static let buttonBold  = Font.custom(interBold, size: 15)
    /// 13pt — small button text
    static let buttonSmall = Font.custom(interSemi, size: 13)
    /// 13pt — label for input fields
    static let inputLabel  = Font.custom(interMedium, size: 13)

    // ── Profile ─────────────────────────────────────────────────────────────
    /// 22pt — profile avatar initials
    static let avatarInitials = Font.custom(interSemi, size: 22)
    /// 20pt — member pill initials
    static let memberInitial  = Font.custom(interBold, size: 20)
    /// 14pt — small avatar initials (card face)
    static let avatarSmall    = Font.custom(interBold, size: 14)
    /// 12pt — tiny avatar/member initials
    static let avatarTiny     = Font.custom(interSemi, size: 12)

    // ── Private alias for Font.custom ───────────────────────────────────────
    private static let interRegular = inter
}

// MARK: - Icon Size Tokens

/// Standardized SF Symbol icon sizes. Use these instead of inline `.font(.system(size:))`.
enum TallyIcon {
    /// 9pt — tiny decorative icons (dollar badges)
    static let xxxs = Font.system(size: 9)
    /// 11pt — small card icons (contactless, wave)
    static let xxs  = Font.system(size: 11)
    /// 12pt — chevrons, small action icons
    static let xs   = Font.system(size: 12)
    /// 14pt — small icons
    static let sm   = Font.system(size: 14)
    /// 16pt — standard action icons (nav chevrons, toolbar)
    static let md   = Font.system(size: 16)
    /// 18pt — medium icons (bell, social icons, toolbar)
    static let lg   = Font.system(size: 18)
    /// 20pt — tab bar icons, member avatars
    static let xl   = Font.system(size: 20)
    /// 22pt — large icons (checkmarks, close buttons)
    static let xxl  = Font.system(size: 22)
    /// 24pt — feature icons
    static let xxxl = Font.system(size: 24)
    /// 30pt — extra large icons
    static let hero = Font.system(size: 30)
    /// 36pt — hero decorative icons (empty states)
    static let heroLg = Font.system(size: 36)
    /// 48pt — splash/loading icons
    static let splash = Font.system(size: 48)
    /// 56pt — full-screen decorative icons
    static let full = Font.system(size: 56)
    /// 64pt — sheet hero icons
    static let mega = Font.system(size: 64)
}
