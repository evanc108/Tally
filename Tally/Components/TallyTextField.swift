import SwiftUI

struct TallyTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?

    @State private var showPassword = false

    var body: some View {
        HStack(spacing: TallySpacing.sm) {
            if isSecure && !showPassword {
                SecureField(placeholder, text: $text)
                    .textContentType(textContentType)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                    .autocorrectionDisabled(keyboardType == .emailAddress)
            }

            if isSecure {
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(TallyColors.textSecondary)
                        .font(.system(size: 16))
                }
                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
            }
        }
        .font(TallyFont.body)
        .padding(.horizontal, TallySpacing.lg)
        .frame(height: TallySpacing.buttonHeight)
        .background(TallyColors.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.buttonCornerRadius))
    }
}
