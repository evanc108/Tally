import SwiftUI
import ClerkKit

struct TwoFactorView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(Clerk.self) private var clerk

    @State private var code = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var appeared = false
    @State private var isResending = false

    @FocusState private var isCodeFieldFocused: Bool

    private var mfaType: SignIn.MfaType {
        guard let factors = authManager.pendingSignIn?.supportedSecondFactors else { return .totp }
        if factors.contains(where: { $0.strategy == .emailCode }) { return .emailCode }
        if factors.contains(where: { $0.strategy == .phoneCode }) { return .phoneCode }
        return .totp
    }

    private var subtitle: String {
        switch mfaType {
        case .emailCode: return "We sent a 6-digit code to your email"
        case .phoneCode: return "We sent a 6-digit code to your phone"
        case .totp: return "Enter the code from your\nauthenticator app"
        case .backupCode: return "Enter one of your backup codes"
        }
    }

    private var needsPrepare: Bool {
        mfaType == .emailCode || mfaType == .phoneCode
    }

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            HStack {
                Button {
                    authManager.beginAuth(mode: .login)
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
                Image(systemName: "lock.shield")
                    .font(TallyIcon.hero)
                    .foregroundStyle(TallyColors.accent)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)

            Spacer().frame(height: TallySpacing.xxl)

            Text("Two-factor authentication")
                .font(TallyFont.largeTitle)
                .foregroundStyle(TallyColors.textPrimary)

            Text(subtitle)
                .font(TallyFont.body)
                .foregroundStyle(TallyColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, TallySpacing.sm)

            Spacer().frame(height: TallySpacing.xxxl)

            // OTP input
            VStack(spacing: TallySpacing.lg) {
                TwoFactorCodeField(code: $code, isFocused: $isCodeFieldFocused)

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
                        Text("Verify")
                    }
                }
                .buttonStyle(TallyPrimaryButtonStyle())
                .disabled(code.count != 6 || isLoading)
                .opacity(code.count != 6 ? 0.5 : 1)

                if needsPrepare {
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
        .task {
            await sendInitialCode()
        }
    }

    private func sendInitialCode() async {
        guard needsPrepare, var signIn = authManager.pendingSignIn else { return }
        do {
            let updated: SignIn
            switch mfaType {
            case .emailCode:
                updated = try await signIn.sendMfaEmailCode()
            case .phoneCode:
                updated = try await signIn.sendMfaPhoneCode()
            default:
                return
            }
            authManager.pendingSignIn = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resendCode() {
        isResending = true
        errorMessage = nil
        Task {
            await sendInitialCode()
            isResending = false
        }
    }

    private func verifyCode() {
        guard code.count == 6, var signIn = authManager.pendingSignIn else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let result = try await signIn.verifyMfaCode(code, type: mfaType)
                if result.status == .complete {
                    authManager.completeAuth()
                } else {
                    errorMessage = "Verification incomplete. Please try again."
                }
            } catch {
                errorMessage = error.localizedDescription
                code = ""
            }
            isLoading = false
        }
    }
}

// MARK: - Code Field

private struct TwoFactorCodeField: View {
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
