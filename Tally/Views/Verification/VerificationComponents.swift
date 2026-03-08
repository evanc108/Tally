import SwiftUI

// MARK: - Verification Nav Bar

struct VerificationNavBar: View {
    let title: String?
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button {
                onBack()
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

            if let title {
                Text(title)
                    .font(TallyFont.titleSemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                Spacer()
                // Balance the back button width
                Color.clear.frame(width: 60)
            }
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .frame(height: 48)
    }
}

// MARK: - Powered by Stripe

struct PoweredByStripe: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Powered by")
                .font(TallyFont.caption)
                .foregroundStyle(TallyColors.textTertiary)
            Text("stripe")
                .font(TallyFont.captionBold)
                .foregroundStyle(Color(hex: 0x635BFF))
        }
    }
}
