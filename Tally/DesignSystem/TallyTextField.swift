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
                .font(TallyFont.caption)
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
            .background(isFocused ? Color(hex: 0xE8F0FE) : TallyColors.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                    .stroke(
                        isFocused ? TallyColors.accent : TallyColors.divider,
                        lineWidth: 1.5
                    )
            )
            .focused($isFocused)
        }
    }
}
