import SwiftUI

enum TallySpacing {
    // MARK: - 4px Base Grid

    static let space4: CGFloat = 4
    static let space8: CGFloat = 8
    static let space12: CGFloat = 12
    static let space16: CGFloat = 16
    static let space20: CGFloat = 20
    static let space24: CGFloat = 24
    static let space32: CGFloat = 32
    static let space40: CGFloat = 40
    static let space48: CGFloat = 48
    static let space64: CGFloat = 64

    // MARK: - Semantic Aliases

    static let xxs: CGFloat = space4
    static let xs: CGFloat = space8
    static let sm: CGFloat = space12
    static let md: CGFloat = space16
    static let lg: CGFloat = space24
    static let xl: CGFloat = space32
    static let xxl: CGFloat = space40

    // MARK: - Layout

    static let screenPadding: CGFloat = space20
}

// MARK: - Corner Radii

enum TallyRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let full: CGFloat = 9999
}
