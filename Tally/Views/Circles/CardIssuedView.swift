import SwiftUI

struct CardIssuedView: View {
    let state: CreateCircleState
    var onContinue: () -> Void

    @State private var cardAppeared = false
    @State private var cardType: CardType = .virtual
    @State private var walletState: WalletState = .idle

    enum CardType: String { case virtual, physical }
    enum WalletState { case idle, adding, added }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Title
                    Text("Your mntly card")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.sm)

                    // Card visual
                    TallyCard(
                        circleName: state.circleName,
                        last4: "4289",
                        photo: state.photo
                    )
                    .aspectRatio(1.586, contentMode: .fit)
                    .scaleEffect(cardAppeared ? 1.0 : 0.85)
                    .opacity(cardAppeared ? 1.0 : 0)
                    .padding(.top, TallySpacing.xxl)

                    // Card type selector
                    HStack(spacing: 0) {
                        cardTypeButton("Virtual (instant)", type: .virtual)
                        cardTypeButton("Physical (3–5 days)", type: .physical)
                    }
                    .frame(height: 40)
                    .background(TallyColors.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: TallySpacing.chipCornerRadius))
                    .padding(.top, TallySpacing.xl)
                }
                .padding(.horizontal, TallySpacing.screenPadding)
            }

            // Bottom button
            Group {
                if walletState == .added {
                    Button("Continue", action: onContinue)
                        .buttonStyle(TallyPrimaryButtonStyle())
                } else {
                    Button { addToWallet() } label: {
                        HStack(spacing: TallySpacing.sm) {
                            if walletState == .adding {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "wallet.bifold")
                                    .font(TallyIcon.lg)
                                Text("Add to Apple Wallet")
                            }
                        }
                    }
                    .buttonStyle(TallyDarkButtonStyle())
                    .disabled(walletState == .adding)
                }
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                cardAppeared = true
            }
        }
    }

    private func cardTypeButton(_ label: String, type: CardType) -> some View {
        Button {
            withAnimation(.spring(response: 0.2)) { cardType = type }
        } label: {
            Text(label)
                .font(TallyFont.smallLabel)
                .fontWeight(.semibold)
                .foregroundStyle(cardType == type ? TallyColors.textPrimary : TallyColors.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cardType == type ? TallyColors.bgPrimary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: TallySpacing.chipCornerRadius - 2))
                .shadow(color: cardType == type ? .black.opacity(0.06) : .clear, radius: 4, y: 1)
                .padding(3)
        }
    }

    private func addToWallet() {
        walletState = .adding
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.5)) { walletState = .added }
        }
    }
}

