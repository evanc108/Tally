import SwiftUI

struct WelcomeView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logotype
            VStack(spacing: TallySpacing.sm) {
                Text("tally")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(TallyColors.textPrimary)
                    .tracking(-1)

                Text("Group spending, split instantly.")
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textSecondary)
            }

            Spacer()
            Spacer()

            // Actions
            VStack(spacing: TallySpacing.lg) {
                Button("Get Started") {
                    authManager.startAuth()
                }
                .buttonStyle(TallyPrimaryButtonStyle())

                Button("Sign In") {
                    authManager.startAuth()
                }
                .buttonStyle(TallyGhostButtonStyle())
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
    }
}

#Preview {
    WelcomeView()
        .environment(AuthManager())
}
