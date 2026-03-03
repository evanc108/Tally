import SwiftUI

struct TallyTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            Text(label)
                .font(TallyFont.small)
                .foregroundStyle(TallyColors.textSecondary)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .textInputAutocapitalization(autocapitalization)
                }
            }
            .font(TallyFont.body)
            .padding(.horizontal, TallySpacing.md)
            .frame(height: 52)
            .background(isFocused ? Color(hex: 0xE8F0FE) : TallyColors.white)
            .clipShape(RoundedRectangle(cornerRadius: TallyRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: TallyRadius.lg)
                    .stroke(
                        isFocused ? TallyColors.accent : TallyColors.border,
                        lineWidth: 1.5
                    )
            )
            .focused($isFocused)
        }
    }
}
