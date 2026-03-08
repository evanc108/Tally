import SwiftUI
import ClerkKit

struct EmailVerificationView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(Clerk.self) private var clerk

    @State private var code = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isResending = false
    @State private var appeared = false

    @FocusState private var isCodeFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            HStack {
                Button {
                    authManager.beginAuth(mode: .signUp)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(TallyIcon.md)
                        Text("Back")
                            .font(TallyFont.bodySemibold)
                    }
                    .foregroundStyle(TallyColors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.top, TallySpacing.md)

            Spacer().frame(height: TallySpacing.jumbo)

            // Icon
            ZStack {
                Circle()
                    .fill(TallyColors.accentLight)
                    .frame(width: 80, height: 80)
                Image(systemName: "envelope.badge.shield.half.filled")
                    .font(TallyIcon.hero)
                    .foregroundStyle(TallyColors.accent)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)

            Spacer().frame(height: TallySpacing.xxl)

            Text("Check your email")
                .font(TallyFont.largeTitle)
                .foregroundStyle(TallyColors.textPrimary)

            if let email = authManager.pendingEmail {
                Text("We sent a 6-digit code to\n**\(email)**")
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, TallySpacing.sm)
            }

            Spacer().frame(height: TallySpacing.xxxl)

            // OTP input
            VStack(spacing: TallySpacing.lg) {
                OTPFieldView(code: $code, isFocused: $isCodeFieldFocused)

                if let errorMessage {
                    Text(errorMessage)
                        .font(TallyFont.small)
                        .foregroundStyle(TallyColors.statusAlert)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Button {
                    verifyCode()
                } label: {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Verify Email")
                    }
                }
                .buttonStyle(TallyPrimaryButtonStyle())
                .disabled(code.count != 6 || isLoading)
                .opacity(code.count != 6 ? 0.5 : 1)

                Button {
                    resendCode()
                } label: {
                    if isResending {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(TallyColors.accent)
                            Text("Sending...")
                        }
                    } else {
                        Text("Resend code")
                    }
                }
                .buttonStyle(TallyGhostButtonStyle())
                .disabled(isResending)
            }
            .padding(.horizontal, TallySpacing.screenPadding)

            Spacer()
        }
        .background(TallyColors.white)
        .animation(.spring(duration: 0.3), value: errorMessage)
        .onAppear {
            isCodeFieldFocused = true
            withAnimation(.spring(duration: 0.5, bounce: 0.3).delay(0.1)) {
                appeared = true
            }
        }
    }

    private func verifyCode() {
        guard code.count == 6 else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                guard let signUp = clerk.auth.currentSignUp else {
                    errorMessage = "No sign-up in progress"
                    isLoading = false
                    return
                }
                let result = try await signUp.verifyEmailCode(code)
                if result.status == .complete {
                    authManager.requireIdentityVerification()
                }
            } catch {
                errorMessage = error.localizedDescription
                code = ""
            }
            isLoading = false
        }
    }

    private func resendCode() {
        isResending = true
        errorMessage = nil

        Task {
            do {
                guard let signUp = clerk.auth.currentSignUp else {
                    errorMessage = "No sign-up in progress"
                    isResending = false
                    return
                }
                try await signUp.sendEmailCode()
            } catch {
                errorMessage = error.localizedDescription
            }
            isResending = false
        }
    }
}

// MARK: - OTP Field

private struct OTPFieldView: View {
    @Binding var code: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                let char = characterAt(index)
                let isActive = index == code.count

                Text(char)
                    .font(TallyFont.codeDisplay)
                    .foregroundStyle(TallyColors.textPrimary)
                    .frame(width: 48, height: 56)
                    .background(TallyColors.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                            .stroke(
                                isActive ? TallyColors.accent : TallyColors.border,
                                lineWidth: isActive ? 2 : 1
                            )
                    )
            }
        }
        .overlay(
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused(isFocused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .onChange(of: code) { _, newValue in
                    code = String(newValue.prefix(6).filter { $0.isNumber })
                }
        )
        .onTapGesture {
            isFocused.wrappedValue = true
        }
    }

    private func characterAt(_ index: Int) -> String {
        guard index < code.count else { return "" }
        return String(code[code.index(code.startIndex, offsetBy: index)])
    }
}
