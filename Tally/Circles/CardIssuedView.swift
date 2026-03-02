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
                    Text("Your Tally card")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.sm)

                    // Card visual
                    CardVisual(
                        photo: state.photo,
                        circleName: state.circleName,
                        last4: "4289",
                        isVirtual: cardType == .virtual
                    )
                    .scaleEffect(cardAppeared ? 1.0 : 0.85)
                    .opacity(cardAppeared ? 1.0 : 0)
                    .padding(.top, TallySpacing.xxl)

                    // Card type selector
                    HStack(spacing: 0) {
                        cardTypeButton("Virtual (instant)", type: .virtual)
                        cardTypeButton("Physical (3–5 days)", type: .physical)
                    }
                    .frame(height: 36)
                    .background(TallyColors.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
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
                    Button {
                        addToWallet()
                    } label: {
                        HStack(spacing: TallySpacing.sm) {
                            if walletState == .adding {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "wallet.bifold")
                                    .font(.system(size: 18))
                                Text("Add to Apple Wallet")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: TallySpacing.buttonHeight)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.buttonCornerRadius))
                    }
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(cardType == type ? TallyColors.textPrimary : TallyColors.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cardType == type ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: cardType == type ? .black.opacity(0.08) : .clear, radius: 3, y: 1)
                .padding(2)
        }
    }

    private func addToWallet() {
        walletState = .adding
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.5)) {
                walletState = .added
            }
        }
    }
}

// MARK: - Card Visual

private struct CardVisual: View {
    let photo: UIImage?
    let circleName: String
    let last4: String
    let isVirtual: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [TallyColors.accent, TallyColors.accent.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .aspectRatio(1.586, contentMode: .fit)
                .shadow(color: TallyColors.accent.opacity(0.3), radius: 20, y: 10)

            VStack(alignment: .leading) {
                HStack {
                    // Circle photo or initial
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    } else {
                        Text(String(circleName.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(TallyColors.accent)
                            .frame(width: 32, height: 32)
                            .background(.white.opacity(0.3))
                            .clipShape(Circle())
                    }

                    Spacer()

                    Text(isVirtual ? "VIRTUAL" : "PHYSICAL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.2))
                        .clipShape(Capsule())
                }

                Spacer()

                Text("•••• •••• •••• \(last4)")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)

                Spacer().frame(height: TallySpacing.md)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(circleName.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Text("tally")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .padding(20)
        }
    }
}
