import SwiftUI

// MARK: - Auth Header (Logo + Subtitle)

struct AuthHeader: View {
    let subtitle: String

    var body: some View {
        VStack(spacing: TallySpacing.xs) {
            // Logo row
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(TallyColors.accent)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "creditcard.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    )

                Text("tally")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(TallyColors.accent)
                    .tracking(-1.2)
            }

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(TallyColors.textSecondary)
        }
        .padding(.top, TallySpacing.lg)
    }
}

// MARK: - Auth Primary Button Style

struct AuthPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .tracking(-0.2)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? TallyColors.accent : TallyColors.accent.opacity(0.4))
            .clipShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Divider with "or"

struct AuthDivider: View {
    var body: some View {
        HStack(spacing: TallySpacing.md) {
            Rectangle()
                .fill(TallyColors.divider)
                .frame(height: 1)
            Text("or")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TallyColors.textTertiary)
            Rectangle()
                .fill(TallyColors.divider)
                .frame(height: 1)
        }
    }
}

// MARK: - Social Auth Button

enum SocialProvider {
    case google, apple

    var label: String {
        switch self {
        case .google: return "Continue with Google"
        case .apple: return "Continue with Apple"
        }
    }

    var iconName: String {
        switch self {
        case .google: return "g.circle.fill"
        case .apple: return "apple.logo"
        }
    }
}

struct SocialAuthButton: View {
    let provider: SocialProvider
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: TallySpacing.xs) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(provider == .apple ? TallyColors.textPrimary : .red)
                Text(provider.label)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(TallyColors.textPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(TallyColors.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                    .stroke(TallyColors.divider, lineWidth: 1.5)
            )
        }
    }
}

// MARK: - Footer Link ("Don't have an account? Sign up")

struct AuthFooterLink: View {
    let text: String
    let action: String
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(TallyFont.caption)
                .foregroundStyle(TallyColors.textSecondary)
            Button(action) {
                onTap()
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(TallyColors.accent)
        }
    }
}
