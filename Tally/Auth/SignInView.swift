import SwiftUI
import ClerkKit

struct SignInView: View {
    @Environment(Clerk.self) private var clerk
    @Binding var path: [AuthRoute]

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

                    Text("Welcome back")
                        .font(TallyFont.title)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.lg)

                    Text("Sign in to your account")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                }
                .padding(.top, TallySpacing.xxxl)
                .padding(.bottom, TallySpacing.xl)

                // Form
                VStack(spacing: TallySpacing.md) {
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
                        textContentType: .password
                    )

                    // Forgot password
                    HStack {
                        Spacer()
                        Button("Forgot password?") {
                            path.append(.forgotPassword)
                        }
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.accent)
                    }
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

                // Sign In button
                Button {
                    signIn()
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign In")
                    }
                }
                .buttonStyle(TallyPrimaryButtonStyle())
                .disabled(email.isEmpty || password.isEmpty || isLoading)
                .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1)
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.top, TallySpacing.xl)

                // Divider
                orDivider
                    .padding(.vertical, TallySpacing.xl)

                // Social buttons
                VStack(spacing: TallySpacing.md) {
                    Button {
                        signInWithApple()
                    } label: {
                        HStack(spacing: TallySpacing.sm) {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 18))
                            Text("Continue with Apple")
                        }
                    }
                    .buttonStyle(TallySecondaryButtonStyle(color: TallyColors.textPrimary))
                    .accessibilityLabel("Sign in with Apple")
                    .padding(.horizontal, TallySpacing.screenPadding)

                    Button {
                        signInWithGoogle()
                    } label: {
                        HStack(spacing: TallySpacing.sm) {
                            Text("G")
                                .font(.system(size: 18, weight: .bold))
                                .accessibilityHidden(true)
                            Text("Continue with Google")
                        }
                    }
                    .buttonStyle(TallySecondaryButtonStyle(color: TallyColors.textPrimary))
                    .accessibilityLabel("Sign in with Google")
                    .padding(.horizontal, TallySpacing.screenPadding)
                }

                // Sign up link
                HStack(spacing: TallySpacing.xs) {
                    Text("Don't have an account?")
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                    Button("Sign up") {
                        path.append(.signUp)
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

    private func signIn() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await clerk.auth.signInWithPassword(identifier: email, password: password)
            } catch {
                // Session may have been created despite the error
                guard clerk.session == nil else { return }
                errorMessage = ClerkErrorMapper.userMessage(for: error)
            }
            isLoading = false
        }
    }

    private func signInWithApple() {
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

    private func signInWithGoogle() {
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
        SignInView(path: .constant([]))
    }
    .environment(Clerk.shared)
}
