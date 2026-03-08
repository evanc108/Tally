import SwiftUI

struct VerificationResultView: View {
    let succeeded: Bool
    let onContinue: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            if succeeded {
                successContent
            } else {
                failureContent
            }

            Spacer()

            // Buttons
            VStack(spacing: TallySpacing.md) {
                if succeeded {
                    Button("Continue to Tally") {
                        onContinue()
                    }
                    .buttonStyle(TallyPrimaryButtonStyle())
                } else {
                    Button("Try Again") {
                        onRetry()
                    }
                    .buttonStyle(TallyPrimaryButtonStyle())

                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(TallySecondaryButtonStyle())
                }

                PoweredByStripe()
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxl)
        }
        .background(TallyColors.white)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.35).delay(0.1)) {
                appeared = true
            }
        }
    }

    // MARK: - Success

    private var successContent: some View {
        VStack(spacing: 0) {
            // Checkmark icon
            ZStack {
                Circle()
                    .fill(TallyColors.accentLight)
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark")
                    .font(TallyIcon.heroLg)
                    .foregroundStyle(TallyColors.accent)
            }
            .scaleEffect(appeared ? 1 : 0.3)
            .opacity(appeared ? 1 : 0)

            Spacer().frame(height: TallySpacing.xxl)

            Text("Identity verified")
                .font(TallyFont.largeTitle)
                .foregroundStyle(TallyColors.textPrimary)

            Text("Your identity has been confirmed. You're all set\nto start using Tally with full access.")
                .font(TallyFont.body)
                .foregroundStyle(TallyColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, TallySpacing.sm)

            Spacer().frame(height: TallySpacing.xxxl)

            // Feature list
            VStack(spacing: TallySpacing.lg) {
                FeatureUnlockRow(
                    icon: "arrow.left.arrow.right",
                    title: "Send & receive money",
                    subtitle: "Instant transfers enabled"
                )
                FeatureUnlockRow(
                    icon: "creditcard.fill",
                    title: "Shared cards",
                    subtitle: "Create and manage group cards"
                )
                FeatureUnlockRow(
                    icon: "arrow.up.right",
                    title: "Higher limits",
                    subtitle: "Increased transaction limits"
                )
            }
            .padding(.horizontal, TallySpacing.screenPadding)
        }
    }

    // MARK: - Failure

    private var failureContent: some View {
        VStack(spacing: 0) {
            // X icon
            ZStack {
                Circle()
                    .fill(TallyColors.statusAlertBg)
                    .frame(width: 88, height: 88)
                Image(systemName: "xmark")
                    .font(TallyIcon.heroLg)
                    .foregroundStyle(TallyColors.statusAlert)
            }
            .scaleEffect(appeared ? 1 : 0.3)
            .opacity(appeared ? 1 : 0)

            Spacer().frame(height: TallySpacing.xxl)

            Text("Verification failed")
                .font(TallyFont.largeTitle)
                .foregroundStyle(TallyColors.textPrimary)

            Text("We couldn't verify your identity. This may be\ndue to unclear photos or mismatched\ninformation.")
                .font(TallyFont.body)
                .foregroundStyle(TallyColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, TallySpacing.sm)

            Spacer().frame(height: TallySpacing.xxl)

            // Error reason
            HStack(spacing: TallySpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(TallyIcon.lg)
                    .foregroundStyle(TallyColors.statusAlert)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Photo quality issue")
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(TallyColors.statusAlert)
                    Text("Image was too blurry or poorly lit")
                        .font(TallyFont.small)
                        .foregroundStyle(TallyColors.textSecondary)
                }
                Spacer()
            }
            .padding(TallySpacing.lg)
            .background(TallyColors.statusAlertBg)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
            .padding(.horizontal, TallySpacing.screenPadding)

            Spacer().frame(height: TallySpacing.lg)

            // Retry hint
            HStack(spacing: TallySpacing.sm) {
                Image(systemName: "info.circle")
                    .font(TallyIcon.sm)
                    .foregroundStyle(TallyColors.textTertiary)
                Text("Try again with better lighting and make sure\nyour ID is flat and all text is readable. You\nhave 3 attempts remaining.")
                    .font(TallyFont.small)
                    .foregroundStyle(TallyColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, TallySpacing.screenPadding)

            Spacer().frame(height: TallySpacing.lg)

            // Contact support link
            Button("Contact Support") {}
                .font(TallyFont.buttonSmall)
                .foregroundStyle(TallyColors.accent)
        }
    }
}

// MARK: - Feature Unlock Row

private struct FeatureUnlockRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: TallySpacing.md) {
            ZStack {
                Circle()
                    .fill(TallyColors.accentLight)
                    .frame(width: 40, height: 40)
                Image(systemName: "checkmark")
                    .font(TallyIcon.sm)
                    .foregroundStyle(TallyColors.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                Text(subtitle)
                    .font(TallyFont.small)
                    .foregroundStyle(TallyColors.textSecondary)
            }

            Spacer()
        }
        .padding(.vertical, TallySpacing.sm)
        .padding(.horizontal, TallySpacing.lg)
        .background(TallyColors.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
    }
}
