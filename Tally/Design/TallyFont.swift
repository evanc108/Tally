import SwiftUI

enum TallyFont {
    // MARK: - Display

    /// 32px / ExtraBold / 1.2 line-height / -0.02em tracking
    static let display: Font = .system(size: 32, weight: .heavy)

    // MARK: - Headings

    /// 24px / Bold / 1.2 / -0.02em
    static let title: Font = .system(size: 24, weight: .bold)

    /// 20px / Bold / 1.2 / -0.01em
    static let heading2: Font = .system(size: 20, weight: .bold)

    /// 17px / SemiBold / 1.3
    static let heading3: Font = .system(size: 17, weight: .semibold)

    // MARK: - Body

    /// 15px / Regular / 1.5
    static let body: Font = .system(size: 15, weight: .regular)

    /// 15px / Medium / 1.5
    static let bodyMedium: Font = .system(size: 15, weight: .medium)

    /// 15px / SemiBold / 1.5
    static let bodySemibold: Font = .system(size: 15, weight: .semibold)

    // MARK: - Small

    /// 13px / Regular / 1.5
    static let small: Font = .system(size: 13, weight: .regular)

    /// 12px / Medium / 1.4 / +0.02em
    static let caption: Font = .system(size: 12, weight: .medium)

    /// 11px / Bold / 1.2 / 0.08em / uppercase
    static let overline: Font = .system(size: 11, weight: .bold)

    // MARK: - Special

    /// Large amount display — same as display heading
    static let heroAmount: Font = .system(size: 32, weight: .heavy)
}

// MARK: - Tracking (Letter Spacing) Modifiers

extension View {
    func tallyTracking(_ style: TallyTrackingStyle) -> some View {
        self.tracking(style.value)
    }
}

enum TallyTrackingStyle {
    case display    // -0.02em → ~-0.64pt at 32px
    case title      // -0.02em → ~-0.48pt at 24px
    case heading2   // -0.01em → ~-0.2pt at 20px
    case caption    // +0.02em → ~+0.24pt at 12px
    case overline   // +0.08em → ~+0.88pt at 11px

    var value: CGFloat {
        switch self {
        case .display: return -0.64
        case .title: return -0.48
        case .heading2: return -0.2
        case .caption: return 0.24
        case .overline: return 0.88
        }
    }
}
