import SwiftUI
import ClerkKit

struct SignUpView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(Clerk.self) private var clerk

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            AuthHeader(subtitle: "Create your account")

            Spacer().frame(height: TallySpacing.xl)

            // Form
            VStack(spacing: TallySpacing.md) {
                TallyTextField(
                    label: "Full name",
                    text: $fullName,
                    placeholder: "Alex Chen",
                    textContentType: .name
                )

                TallyTextField(
                    label: "Email",
                    text: $email,
                    placeholder: "you@email.com",
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress,
                    autocapitalization: .never
                )

                TallyTextField(
                    label: "Password",
                    text: $password,
                    placeholder: "Min 8 characters",
                    isSecure: true,
                    textContentType: .newPassword
                )

                // Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(TallyFont.small)
                        .foregroundStyle(TallyColors.statusAlert)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.move(edge: .top).combined(with: .opacity))
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
                .buttonStyle(AuthPrimaryButtonStyle())
                .disabled(!isFormValid || isLoading)

                // Divider
                AuthDivider()

                // Social
                SocialAuthButton(provider: .google) {
                    signUpWithGoogle()
                }

                SocialAuthButton(provider: .apple) {
                    signUpWithApple()
                }
            }
            .padding(.horizontal, TallySpacing.lg)

            Spacer()

            // Footer
            AuthFooterLink(
                text: "Already have an account?",
                action: "Log in"
            ) {
                withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                    authManager.authMode = .login
                }
            }
            .padding(.bottom, TallySpacing.xl)
        }
        .background(TallyColors.white)
        .animation(.spring(duration: 0.3), value: errorMessage)
    }

    private var isFormValid: Bool {
        !fullName.isEmpty && !email.isEmpty && !password.isEmpty && password.count >= 8
    }

    // MARK: - Actions

    private func createAccount() {
        guard isFormValid else { return }
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
                if signUp.status == .complete {
                    authManager.completeAuth()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func signUpWithGoogle() {
        Task {
            do {
                try await clerk.auth.signInWithOAuth(provider: .google)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func signUpWithApple() {
        Task {
            do {
                try await clerk.auth.signInWithApple()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
