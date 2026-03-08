import SwiftUI

struct VerifyIdentityIntroView: View {
    let onBegin: () -> Void
    let onBack: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Nav bar
            VerificationNavBar(title: nil, onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: TallySpacing.xxl)

                    // Shield icon
                    ZStack {
                        Circle()
                            .fill(TallyColors.accentLight)
                            .frame(width: 72, height: 72)
                        Image(systemName: "checkmark.shield.fill")
                            .font(TallyIcon.hero)
                            .foregroundStyle(TallyColors.accent)
                    }
                    .scaleEffect(appeared ? 1 : 0.5)
                    .opacity(appeared ? 1 : 0)

                    Spacer().frame(height: TallySpacing.xxl)

                    // Title
                    Text("Verify your identity")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)

                    Text("To keep your account secure and comply with\nregulations, we need to verify your identity. This\nonly takes a few minutes.")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, TallySpacing.sm)

                    // Secured badge
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(TallyIcon.xs)
                            .foregroundStyle(TallyColors.accent)
                        Text("Secured by Stripe Identity")
                            .font(TallyFont.caption)
                            .foregroundStyle(TallyColors.accent)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(TallyColors.accentLight)
                    .clipShape(Capsule())
                    .padding(.top, TallySpacing.lg)

                    Spacer().frame(height: TallySpacing.xxxl)

                    // Requirements
                    VStack(spacing: TallySpacing.md) {
                        RequirementRow(
                            icon: "creditcard.fill",
                            iconColor: TallyColors.statusAlert,
                            iconBg: TallyColors.statusAlertBg,
                            title: "Government-issued ID",
                            subtitle: "Driver's license, passport, or ID card"
                        )

                        RequirementRow(
                            icon: "person.crop.circle.fill",
                            iconColor: TallyColors.statusInfo,
                            iconBg: TallyColors.statusInfoBg,
                            title: "Selfie photo",
                            subtitle: "We'll match your face to your ID"
                        )

                        RequirementRow(
                            icon: "lock.fill",
                            iconColor: TallyColors.accent,
                            iconBg: TallyColors.accentLight,
                            title: "Data encrypted",
                            subtitle: "Your data is securely processed"
                        )
                    }
                    .padding(.horizontal, TallySpacing.screenPadding)
                }
            }

            // Bottom
            VStack(spacing: TallySpacing.md) {
                Button("Begin Verification") {
                    onBegin()
                }
                .buttonStyle(TallyPrimaryButtonStyle())

                PoweredByStripe()
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxl)
        }
        .background(TallyColors.white)
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.3).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// MARK: - Requirement Row

private struct RequirementRow: View {
    let icon: String
    let iconColor: Color
    let iconBg: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: TallySpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: TallyRadius.md)
                    .fill(iconBg)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(TallyIcon.lg)
                    .foregroundStyle(iconColor)
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
        .padding(TallySpacing.lg)
        .background(TallyColors.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
    }
}
