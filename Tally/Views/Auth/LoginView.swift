import SwiftUI
import ClerkKit

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(Clerk.self) private var clerk

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            AuthHeader(subtitle: "Welcome back")

            Spacer().frame(height: TallySpacing.xl)

            // Form
            VStack(spacing: TallySpacing.md) {
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
                    placeholder: "Enter password",
                    isSecure: true,
                    textContentType: .password
                )

                // Forgot password
                HStack {
                    Spacer()
                    Button("Forgot password?") {}
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TallyColors.accent)
                }

                // Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.statusAlert)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Log In button
                Button {
                    logIn()
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Log In")
                    }
                }
                .buttonStyle(AuthPrimaryButtonStyle())
                .disabled(email.isEmpty || password.isEmpty || isLoading)

                // Divider
                AuthDivider()

                // Social buttons
                SocialAuthButton(provider: .google) {
                    signInWithGoogle()
                }

                SocialAuthButton(provider: .apple) {
                    signInWithApple()
                }
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .onSubmit {
                logIn()
            }

            Spacer()

            // Footer
            AuthFooterLink(
                text: "Don't have an account?",
                action: "Sign up"
            ) {
                withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                    authManager.authMode = .signUp
                }
            }
            .padding(.bottom, TallySpacing.xl)
        }
        .background(TallyColors.bgPrimary)
        .animation(.spring(duration: 0.3), value: errorMessage)
    }

    // MARK: - Actions

    private func logIn() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let signIn = try await clerk.auth.signInWithPassword(
                    identifier: email,
                    password: password
                )
                if signIn.status == .complete {
                    authManager.completeAuth()
                } else if signIn.status == .needsSecondFactor {
                    authManager.requireTwoFactor(signIn: signIn)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func signInWithGoogle() {
        Task {
            do {
                try await clerk.auth.signInWithOAuth(provider: .google)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func signInWithApple() {
        Task {
            do {
                try await clerk.auth.signInWithApple()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
