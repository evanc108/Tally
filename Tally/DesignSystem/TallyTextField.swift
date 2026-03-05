import SwiftUI

struct TallyTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences
    var helperText: String? = nil
    var errorText: String? = nil

    @FocusState private var isFocused: Bool

    private var hasError: Bool { errorText != nil }

    private var borderColor: Color {
        if hasError { return TallyColors.statusAlert }
        if isFocused { return TallyColors.accent }
        return TallyColors.border
    }

    private var ringColor: Color {
        if hasError { return Color(hex: 0xFF3B30, opacity: 0.12) }
        if isFocused { return Color(hex: 0x00C805, opacity: 0.12) }
        return .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(TallyFont.inputLabel)
                .foregroundStyle(TallyColors.textPrimary)

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
            .foregroundStyle(TallyColors.textPrimary)
            .padding(.horizontal, TallySpacing.lg)
            .frame(height: TallySpacing.inputHeight)
            .background(TallyColors.white)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(
                color: ringColor,
                radius: 0, x: 0, y: 0
            )
            .overlay(
                RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                    .stroke(ringColor, lineWidth: 3)
            )
            .focused($isFocused)

            if let error = errorText {
                Text(error)
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.statusAlert)
            } else if let helper = helperText {
                Text(helper)
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textTertiary)
            }
        }
    }
}
