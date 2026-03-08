import SwiftUI
import ClerkKit

struct AuthFlowView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(Clerk.self) private var clerk

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with back button
            HStack {
                Button {
                    authManager.backToWelcome()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(TallyIcon.md)
                        .foregroundStyle(TallyColors.textSecondary)
                        .frame(width: 44, height: 44)
                }
                Spacer()
            }
            .padding(.horizontal, TallySpacing.sm)

            // Content
            Group {
                switch authManager.authMode {
                case .login:
                    LoginView()
                case .signUp:
                    SignUpView()
                }
            }
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
        }
        .background(TallyColors.bgPrimary)
        .onAppear {
            appeared = false
            withAnimation(.easeOut(duration: 0.35).delay(0.05)) {
                appeared = true
            }
        }
    }
}
