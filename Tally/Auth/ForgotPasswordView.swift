import SwiftUI
import ClerkKit

struct ForgotPasswordView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(AuthFlowModel.self) private var flowModel
    @Environment(\.dismiss) private var dismiss
    @Binding var path: [AuthRoute]

    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: TallySpacing.xs) {
                    Text("tally")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(TallyColors.textPrimary)
                        .tracking(-1)

                    Text("Forgot password?")
                        .font(TallyFont.title)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.lg)

                    Text("Enter your email and we'll send you\na reset code")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, TallySpacing.xxxl)
                .padding(.bottom, TallySpacing.xl)

                // Email field
                TallyTextField(
                    placeholder: "Email",
                    text: $email,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress
                )
                .padding(.horizontal, TallySpacing.screenPadding)

                // Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.statusAlert)
                        .padding(.top, TallySpacing.sm)
                        .padding(.horizontal, TallySpacing.screenPadding)
                }

                // Send Reset Code button
                Button {
                    sendResetCode()
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Send Reset Code")
                    }
                }
                .buttonStyle(TallyPrimaryButtonStyle())
                .disabled(email.isEmpty || isLoading)
                .opacity(email.isEmpty ? 0.6 : 1)
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.top, TallySpacing.xl)

                // Back to sign in
                Button("Back to Sign In") {
                    dismiss()
                }
                .font(TallyFont.caption)
                .foregroundStyle(TallyColors.accent)
                .padding(.top, TallySpacing.xl)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(TallyColors.bgPrimary)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(TallyColors.textPrimary)
                }
                .accessibilityLabel("Back")
            }
        }
    }

    // MARK: - Actions

    private func sendResetCode() {
        guard !email.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                // Create a sign-in attempt with the email
                let signIn = try await clerk.auth.signIn(email)
                // Send password reset email code
                let updated = try await signIn.sendResetPasswordEmailCode()
                flowModel.currentSignIn = updated
                path.append(.verifyEmail(email: email, isPasswordReset: true))
            } catch {
                errorMessage = ClerkErrorMapper.userMessage(for: error)
            }
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        ForgotPasswordView(path: .constant([]))
    }
    .environment(Clerk.shared)
    .environment(AuthFlowModel())
}
