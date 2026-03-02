import SwiftUI
import ClerkKit

struct VerifyEmailView: View {
    let email: String
    let isPasswordReset: Bool

    @Environment(Clerk.self) private var clerk
    @Environment(AuthFlowModel.self) private var flowModel
    @Environment(\.dismiss) private var dismiss
    @Binding var path: [AuthRoute]

    @State private var code = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: TallySpacing.xs) {
                    Text("tally")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(TallyColors.textPrimary)
                        .tracking(-1)

                    Text("Check your email")
                        .font(TallyFont.title)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.lg)

                    Text("We sent a verification code to\n\(email)")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, TallySpacing.xxxl)
                .padding(.bottom, TallySpacing.xxl)

                // Code input
                codeInput
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Verification code, \(code.count) of 6 digits entered")

                // Error
                if let errorMessage {
                    Text(errorMessage)
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.statusAlert)
                        .padding(.top, TallySpacing.sm)
                        .padding(.horizontal, TallySpacing.screenPadding)
                }

                // Verify button
                Button {
                    verifyCode()
                } label: {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Verify")
                    }
                }
                .buttonStyle(TallyPrimaryButtonStyle())
                .disabled(code.count < 6 || isLoading)
                .opacity(code.count < 6 ? 0.6 : 1)
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.top, TallySpacing.xl)

                // Resend
                Button("Didn't receive a code? Resend") {
                    resendCode()
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
                        .accessibilityLabel("Back")
                }
            }
        }
        .task {
            isCodeFocused = true
        }
    }

    // MARK: - Code Input

    private var codeInput: some View {
        ZStack {
            // Hidden text field for keyboard input
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isCodeFocused)
                .opacity(0)
                .frame(width: 0, height: 0)
                .onChange(of: code) { _, newValue in
                    let filtered = String(newValue.prefix(6)).filter(\.isNumber)
                    if filtered != newValue {
                        code = filtered
                        return // Avoid double-fire: the re-set triggers onChange again
                    }
                    if filtered.count == 6, !isLoading {
                        verifyCode()
                    }
                }

            // Visual code boxes
            HStack(spacing: TallySpacing.sm) {
                ForEach(0..<6, id: \.self) { index in
                    let digit = index < code.count
                        ? String(code[code.index(code.startIndex, offsetBy: index)])
                        : ""

                    Text(digit)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundStyle(TallyColors.textPrimary)
                        .frame(width: 48, height: 56)
                        .background(TallyColors.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: TallySpacing.sm)
                                .stroke(
                                    index == code.count ? TallyColors.accent : Color.clear,
                                    lineWidth: 2
                                )
                        )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isCodeFocused = true
            }
        }
    }

    // MARK: - Actions

    private func verifyCode() {
        guard code.count == 6, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                if isPasswordReset {
                    if let signIn = flowModel.currentSignIn {
                        let updated = try await signIn.verifyCode(code)
                        flowModel.currentSignIn = updated
                        path.append(.resetPassword)
                    }
                } else {
                    if let signUp = flowModel.currentSignUp {
                        try await signUp.verifyEmailCode(code)
                        // Session created — onChange in AuthFlowView handles transition
                    }
                }
            } catch {
                guard clerk.session == nil else { return }
                errorMessage = ClerkErrorMapper.userMessage(for: error)
            }
            isLoading = false
        }
    }

    private func resendCode() {
        errorMessage = nil

        Task {
            do {
                if isPasswordReset {
                    if let signIn = flowModel.currentSignIn {
                        flowModel.currentSignIn = try await signIn.sendResetPasswordEmailCode()
                    }
                } else {
                    if let signUp = flowModel.currentSignUp {
                        flowModel.currentSignUp = try await signUp.sendEmailCode()
                    }
                }
            } catch {
                errorMessage = ClerkErrorMapper.userMessage(for: error)
            }
        }
    }
}

#Preview {
    NavigationStack {
        VerifyEmailView(
            email: "user@example.com",
            isPasswordReset: false,
            path: .constant([])
        )
    }
    .environment(Clerk.shared)
    .environment(AuthFlowModel())
}
