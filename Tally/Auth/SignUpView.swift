import SwiftUI
import ClerkKit

struct SignUpView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(AuthFlowModel.self) private var flowModel
    @Environment(\.dismiss) private var dismiss
    @Binding var path: [AuthRoute]

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
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

                    Text("Create account")
                        .font(TallyFont.title)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.lg)

                    Text("Sign up to get started")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                }
                .padding(.top, TallySpacing.xxxl)
                .padding(.bottom, TallySpacing.xl)

                // Form
                VStack(spacing: TallySpacing.md) {
                    TallyTextField(
                        placeholder: "Full name",
                        text: $fullName,
                        textContentType: .name
                    )

                    TallyTextField(
                        placeholder: "Email",
                        text: $email,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress
                    )

                    TallyTextField(
                        placeholder: "Password",
                        text: $password,
                        isSecure: true,
                        textContentType: .newPassword
                    )
                }
                .padding(.horizontal, TallySpacing.screenPadding)

                // Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.statusAlert)
                        .padding(.top, TallySpacing.sm)
                        .padding(.horizontal, TallySpacing.screenPadding)
                }

                // Create Account button
                Button {
                    createAccount()
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Create Account")
                    }
                }
                .buttonStyle(TallyPrimaryButtonStyle())
                .disabled(fullName.isEmpty || email.isEmpty || password.isEmpty || isLoading)
                .opacity(fullName.isEmpty || email.isEmpty || password.isEmpty ? 0.6 : 1)
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.top, TallySpacing.xl)

                // Divider
                orDivider
                    .padding(.vertical, TallySpacing.xl)

                // Social buttons
                VStack(spacing: TallySpacing.md) {
                    Button {
                        signUpWithApple()
                    } label: {
                        HStack(spacing: TallySpacing.sm) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 18))
                            Text("Continue with Apple")
                        }
                    }
                    .buttonStyle(TallySecondaryButtonStyle(color: TallyColors.textPrimary))
                    .accessibilityLabel("Sign up with Apple")
                    .padding(.horizontal, TallySpacing.screenPadding)

                    Button {
                        signUpWithGoogle()
                    } label: {
                        HStack(spacing: TallySpacing.sm) {
                            Text("G")
                                .font(.system(size: 18, weight: .bold))
                                .accessibilityHidden(true)
                            Text("Continue with Google")
                        }
                    }
                    .buttonStyle(TallySecondaryButtonStyle(color: TallyColors.textPrimary))
                    .accessibilityLabel("Sign up with Google")
                    .padding(.horizontal, TallySpacing.screenPadding)
                }

                // Login link
                HStack(spacing: TallySpacing.xs) {
                    Text("Already have an account?")
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                    Button("Log in") {
                        dismiss()
                    }
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.accent)
                }
                .padding(.top, TallySpacing.xxl)
                .padding(.bottom, TallySpacing.xxxl)
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

    // MARK: - Divider

    private var orDivider: some View {
        HStack(spacing: TallySpacing.lg) {
            Rectangle()
                .fill(TallyColors.divider)
                .frame(height: 1)
            Text("or")
                .font(TallyFont.caption)
                .foregroundStyle(TallyColors.textSecondary)
            Rectangle()
                .fill(TallyColors.divider)
                .frame(height: 1)
        }
        .padding(.horizontal, TallySpacing.screenPadding)
    }

    // MARK: - Actions

    private func createAccount() {
        guard !fullName.isEmpty, !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        let nameParts = fullName.split(separator: " ", maxSplits: 1)
        let firstName = String(nameParts.first ?? "")
        let lastName = nameParts.count > 1 ? String(nameParts[1]) : nil

        Task {
            do {
                let signUp = try await clerk.auth.signUp(
                    emailAddress: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName
                )

                if signUp.unverifiedFields.contains(.emailAddress) {
                    let updated = try await signUp.sendEmailCode()
                    flowModel.currentSignUp = updated
                    path.append(.verifyEmail(email: email, isPasswordReset: false))
                }
                // If no verification needed, session is created automatically
            } catch {
                guard clerk.session == nil else { return }
                errorMessage = ClerkErrorMapper.userMessage(for: error)
            }
            isLoading = false
        }
    }

    private func signUpWithApple() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await clerk.auth.signInWithApple()
            } catch {
                guard clerk.session == nil else { return }
                errorMessage = ClerkErrorMapper.userMessage(for: error)
            }
            isLoading = false
        }
    }

    private func signUpWithGoogle() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await clerk.auth.signInWithOAuth(provider: .google)
            } catch {
                guard clerk.session == nil else { return }
                errorMessage = ClerkErrorMapper.userMessage(for: error)
            }
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        SignUpView(path: .constant([]))
    }
    .environment(Clerk.shared)
    .environment(AuthFlowModel())
}
