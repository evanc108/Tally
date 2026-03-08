import SwiftUI

struct PayWalletConfirmView: View {
    @Bindable var viewModel: PayFlowViewModel
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Wallet icon
                Image(systemName: "wallet.bifold")
                    .font(TallyIcon.splash)
                    .foregroundStyle(TallyColors.ink)

                // Title
                Text("Pay from Wallet")
                    .font(TallyFont.title)
                    .foregroundStyle(TallyColors.textPrimary)
                    .padding(.top, TallySpacing.xl)

                // Merchant name
                if !viewModel.merchantName.isEmpty {
                    Text(viewModel.merchantName)
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(.top, TallySpacing.sm)
                }

                // Hero amount
                Text(CentsFormatter.format(viewModel.totalCents))
                    .font(TallyFont.heroAmount)
                    .foregroundStyle(TallyColors.textPrimary)
                    .padding(.top, TallySpacing.xl)
            }
            .padding(.horizontal, TallySpacing.screenPadding)

            Spacer()

            // Confirm button
            Button("Confirm Payment") {
                viewModel.push(.complete)
            }
            .buttonStyle(TallyDarkButtonStyle())
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PayWalletConfirmView(
            viewModel: {
                let vm = PayFlowViewModel()
                vm.manualAmountCents = 4250
                vm.merchantName = "Sushi Ro"
                return vm
            }(),
            onDone: {}
        )
    }
}
