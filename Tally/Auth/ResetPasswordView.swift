import SwiftUI
import ClerkKit

struct ResetPasswordView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(AuthFlowModel.self) private var flowModel
    @Environment(\.dismiss) private var dismiss
    @Binding var path: [AuthRoute]

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var passwordsMatch: Bool {
        !newPassword.isEmpty && newPassword == confirmPassword
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: TallySpacing.xs) {
                    Text("tally")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(TallyColors.textPrimary)
                        .tracking(-1)

                    Text("Set new password")
                        .font(TallyFont.title)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.lg)

                    Text("Enter your new password below")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                }
                .padding(.top, TallySpacing.xxxl)
                .padding(.bottom, TallySpacing.xl)

                // Password fields
                VStack(spacing: TallySpacing.md) {
                    TallyTextField(
                        placeholder: "New password",
                        text: $newPassword,
                        isSecure: true,
                        textContentType: .newPassword
                    )

                    TallyTextField(
                        placeholder: "Confirm password",
                        text: $confirmPassword,
                        isSecure: true,
                        textContentType: .newPassword
                    )

                    // Password strength indicator
                    if !newPassword.isEmpty {
                        passwordStrengthView
                    }

                    // Mismatch warning
                    if !confirmPassword.isEmpty && !passwordsMatch {
                        Text("Passwords do not match")
                            .font(TallyFont.caption)
                            .foregroundStyle(TallyColors.statusAlert)
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

                // Reset Password button
                Button {
                    resetPassword()
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Reset Password")
                    }
                }
                .buttonStyle(TallyPrimaryButtonStyle())
                .disabled(!passwordsMatch || isLoading)
                .opacity(!passwordsMatch ? 0.6 : 1)
                .padding(.horizontal, TallySpacing.screenPadding)
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

    // MARK: - Password Strength

    private var passwordStrength: (text: String, color: Color, progress: Double) {
        let length = newPassword.count
        if length < 6 {
            return ("Weak", TallyColors.statusAlert, 0.25)
        } else if length < 10 {
            let hasUppercase = newPassword.contains(where: \.isUppercase)
            let hasNumber = newPassword.contains(where: \.isNumber)
            if hasUppercase && hasNumber {
                return ("Good", TallyColors.statusPending, 0.65)
            }
            return ("Fair", TallyColors.statusPending, 0.45)
        } else {
            let hasUppercase = newPassword.contains(where: \.isUppercase)
            let hasNumber = newPassword.contains(where: \.isNumber)
            let hasSpecial = newPassword.contains(where: { !$0.isLetter && !$0.isNumber })
            if hasUppercase && hasNumber && hasSpecial {
                return ("Strong", TallyColors.statusSuccess, 1.0)
            }
            return ("Good", TallyColors.statusPending, 0.75)
        }
    }

    private var passwordStrengthView: some View {
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(TallyColors.bgSecondary)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(passwordStrength.color)
                        .frame(width: geometry.size.width * passwordStrength.progress, height: 4)
                        .animation(.easeInOut(duration: 0.3), value: passwordStrength.progress)
                }
            }
            .frame(height: 4)

            Text(passwordStrength.text)
                .font(TallyFont.caption)
                .foregroundStyle(passwordStrength.color)
        }
    }

    // MARK: - Actions

    private func resetPassword() {
        guard passwordsMatch else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                if let signIn = flowModel.currentSignIn {
                    try await signIn.resetPassword(newPassword: newPassword)
                    // After reset, pop back to sign in screen
                    path.removeAll()
                }
            } catch {
                errorMessage = ClerkErrorMapper.userMessage(for: error)
            }
            isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        ResetPasswordView(path: .constant([]))
    }
    .environment(Clerk.shared)
    .environment(AuthFlowModel())
}
