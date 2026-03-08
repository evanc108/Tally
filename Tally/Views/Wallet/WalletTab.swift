import SwiftUI

// MARK: - Wallet Tab

struct WalletTab: View {
    let circles: [TallyCircle]

    // Card expansion — same pattern as CircleListView
    @State private var selectedCircle: TallyCircle? = nil
    @State private var selectedIndex: Int? = nil
    @State private var showExpandedDetail = false
    @Namespace private var cardNamespace

    private var totalBalance: Double {
        circles.reduce(0.0) { $0 + $1.walletBalance }
    }

    private let topPadding: CGFloat = 52

    var body: some View {
        ZStack(alignment: .top) {
            TallyColors.bgSecondary.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: topPadding)

                    balanceBanner
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.top, TallySpacing.sm)
                        .padding(.bottom, 0)
                        .opacity(selectedCircle != nil ? 0 : 1)
                        .offset(y: selectedCircle != nil ? -80 : 0)
                        .animation(.spring(response: 0.85, dampingFraction: 0.84), value: selectedCircle == nil)

                    if circles.isEmpty {
                        emptyState.padding(.top, TallySpacing.xxxl)
                    } else {
                        cardStack
                            .padding(.top, TallySpacing.sm)
                    }
                }
                .contentMargins(.bottom, 100, for: .scrollContent)
            }
            .scrollDisabled(selectedCircle != nil)

            // Expanded card + detail overlay
            if let circle = selectedCircle, let si = selectedIndex {
                expandedView(circle: circle, index: si)
                    .transition(.opacity)
                    .zIndex(1)
            }

            // Floating header (always on top)
            walletHeader
                .zIndex(2)
        }
    }

    // MARK: - Floating Header

    private var walletHeader: some View {
        HStack(alignment: .center) {
            if selectedCircle != nil {
                GlassNavButton(icon: "chevron.left") {
                    withAnimation(.spring(response: 0.85, dampingFraction: 0.84)) {
                        showExpandedDetail = false
                        selectedCircle = nil
                        selectedIndex = nil
                    }
                }
                Text(selectedCircle?.name ?? "")
                    .font(TallyFont.largeTitle)
                    .foregroundStyle(TallyColors.textPrimary)
                    .frame(maxWidth: .infinity)
                GlassNavButton(icon: "xmark") {
                    withAnimation(.spring(response: 0.85, dampingFraction: 0.84)) {
                        showExpandedDetail = false
                        selectedCircle = nil
                        selectedIndex = nil
                    }
                }
            } else {
                Text("Wallet")
                    .font(TallyFont.largeTitle)
                    .foregroundStyle(TallyColors.textPrimary)
                Spacer()
                HStack(spacing: 0) {
                    GlassNavButton(icon: "magnifyingglass") {}
                    GlassNavButton(icon: "plus") {}
                    GlassNavButton(icon: "ellipsis") {}
                }
            }
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.top, TallySpacing.sm)
        .padding(.bottom, TallySpacing.sm)
        .background(
            LinearGradient(
                stops: [
                    .init(color: TallyColors.bgSecondary.opacity(0.9), location: 0),
                    .init(color: TallyColors.bgSecondary.opacity(0.6), location: 0.35),
                    .init(color: TallyColors.bgSecondary.opacity(0.2), location: 0.7),
                    .init(color: TallyColors.bgSecondary.opacity(0), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Balance Banner

    private var balanceBanner: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            Text("Total Balance")
                .font(TallyFont.bodySmallBold)
                .foregroundStyle(TallyColors.textSecondary)

            Text(String(format: "$%.2f", totalBalance))
                .font(TallyFont.balanceAmount)
                .foregroundStyle(TallyColors.textPrimary)

            HStack(spacing: TallySpacing.md) {
                quickActionButton(icon: "plus", label: "Add Money")
                quickActionButton(icon: "paperplane", label: "Send")
                quickActionButton(icon: "arrow.down", label: "Request")
            }
            .padding(.top, TallySpacing.xs)
        }
        .padding(.horizontal, TallySpacing.xl)
        .padding(.top, TallySpacing.xl)
        .padding(.bottom, TallySpacing.md)
        .background(TallyColors.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    private func quickActionButton(icon: String, label: String) -> some View {
        Button {} label: {
            VStack(spacing: TallySpacing.xs) {
                Image(systemName: icon)
                    .font(TallyIcon.md)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(TallyColors.ink)
                    .clipShape(Circle())
                Text(label)
                    .font(TallyFont.micro)
                    .foregroundStyle(TallyColors.ink)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        let cardH: CGFloat = 190
        let peek: CGFloat = 46
        let count = circles.count

        return ZStack(alignment: .top) {
            ForEach(Array(circles.enumerated()).reversed(), id: \.element.id) { index, circle in
                let isSelected = selectedCircle?.id == circle.id
                let hasSelection = selectedCircle != nil
                let si = selectedIndex ?? 0

                TallyCard(
                    circleName: circle.name,
                    last4: circle.myCardLastFour ?? "0000",
                    balance: circle.walletBalance,
                    colorIndex: index,
                    photo: circle.photo,
                    walletLayout: true
                )
                .frame(maxWidth: .infinity)
                .frame(height: cardH)
                .matchedGeometryEffect(id: circle.id, in: cardNamespace, isSource: !isSelected)
                    .opacity(isSelected && hasSelection ? 0 : 1)
                    .offset(y: hasSelection
                        ? (isSelected ? 0 : (index > si ? -420 : 520))
                        : CGFloat(count - 1 - index) * peek)
                    .animation(.spring(response: 0.85, dampingFraction: 0.82), value: selectedCircle?.id)
                    .onTapGesture {
                        guard !hasSelection else { return }
                        withAnimation(.spring(response: 0.85, dampingFraction: 0.82)) {
                            selectedCircle = circle
                            selectedIndex = index
                        }
                    }
            }
        }
        .frame(height: cardH + peek * CGFloat(max(count - 1, 0)))
        .padding(.horizontal, TallySpacing.screenPadding)
    }

    // MARK: - Expanded View

    private func expandedView(circle: TallyCircle, index: Int) -> some View {
        VStack(spacing: 0) {
            // Space behind floating header
            Color.clear.frame(height: topPadding)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Card morphs from stack position to here via matchedGeometryEffect
                    TallyCard(
                        circleName: circle.name,
                        last4: circle.myCardLastFour ?? "0000",
                        balance: circle.walletBalance,
                        colorIndex: index,
                        photo: circle.photo,
                        walletLayout: true
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .matchedGeometryEffect(id: circle.id, in: cardNamespace, isSource: true)
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .allowsHitTesting(false)

                    // Detail content: appears after card settles at top
                    if showExpandedDetail {
                        expandedDetail(circle: circle)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .contentMargins(.bottom, 120, for: .scrollContent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TallyColors.bgSecondary.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(0.28)) {
                showExpandedDetail = true
            }
        }
        .onDisappear {
            showExpandedDetail = false
        }
    }

    // MARK: - Expanded Detail

    private func expandedDetail(circle: TallyCircle) -> some View {
        let sorted = circle.transactions.sorted { $0.date > $1.date }

        return VStack(alignment: .leading, spacing: 0) {
            // Balance row
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: TallySpacing.xs) {
                    Text("BALANCE")
                        .font(TallyFont.overline)
                        .foregroundStyle(TallyColors.textSecondary)
                        .tracking(0.5)
                    Text(String(format: "$%.2f", circle.walletBalance))
                        .font(TallyFont.balanceAmount)
                        .foregroundStyle(TallyColors.textPrimary)
                }
                Spacer()
                Button("Add Money") {}
                    .buttonStyle(TallySmallPrimaryButtonStyle())
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.top, TallySpacing.xl)
            .padding(.bottom, TallySpacing.lg)

            // Quick actions
            HStack(spacing: TallySpacing.md) {
                detailQuickAction(icon: "paperplane", label: "Send")
                detailQuickAction(icon: "arrow.down", label: "Request")
                detailQuickAction(icon: "arrow.left.arrow.right", label: "Transfer")
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xl)

            // Transactions
            Text("LATEST TRANSACTIONS")
                .font(TallyFont.overline)
                .foregroundStyle(TallyColors.textSecondary)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.sm)

            if sorted.isEmpty {
                VStack(spacing: TallySpacing.md) {
                    Image(systemName: "tray")
                        .font(TallyIcon.heroLg)
                        .foregroundStyle(TallyColors.textTertiary)
                    Text("No transactions yet")
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(TallyColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, TallySpacing.xxxl)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sorted.prefix(20).enumerated()), id: \.element.id) { idx, tx in
                        transactionRow(tx: tx, isLast: idx == min(sorted.count, 20) - 1)
                    }
                }
                .background(TallyColors.bgPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                .padding(.horizontal, TallySpacing.screenPadding)
            }
        }
    }

    private func detailQuickAction(icon: String, label: String) -> some View {
        Button {} label: {
            VStack(spacing: TallySpacing.xs) {
                Image(systemName: icon)
                    .font(TallyIcon.md)
                    .fontWeight(.semibold)
                    .foregroundStyle(TallyColors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(TallyColors.bgPrimary)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                Text(label)
                    .font(TallyFont.micro)
                    .foregroundStyle(TallyColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func transactionRow(tx: CircleTransaction, isLast: Bool) -> some View {
        HStack(spacing: TallySpacing.md) {
            Text(tx.emoji)
                .font(.system(size: 20))
                .frame(width: 44, height: 44)
                .background(TallyColors.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(tx.title)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                Text(tx.paidBy == "You" ? "You paid" : "Paid by \(tx.paidBy)")
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "$%.2f", tx.amount))
                    .font(TallyFont.amountsSmall)
                    .foregroundStyle(TallyColors.textPrimary)
                Text(tx.status.label)
                    .font(TallyFont.micro)
                    .foregroundStyle(tx.status.color)
            }
        }
        .padding(.horizontal, TallySpacing.lg)
        .padding(.vertical, TallySpacing.md)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(TallyColors.divider)
                    .frame(height: 0.5)
                    .padding(.leading, 72)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TallySpacing.lg) {
            Image(systemName: "wallet.bifold")
                .font(TallyIcon.splash)
                .foregroundStyle(TallyColors.textTertiary)
            Text("No circles yet")
                .font(TallyFont.bodySemibold)
                .foregroundStyle(TallyColors.textSecondary)
            Text("Create a circle to see your cards here.")
                .font(TallyFont.body)
                .foregroundStyle(TallyColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TallySpacing.xxxl)
    }
}

// MARK: - Card Detail View (kept for preview)

struct WalletCardDetailView: View {
    let circle: TallyCircle
    let circleIndex: Int
    @Environment(\.dismiss) private var dismiss

    private var sortedTransactions: [CircleTransaction] {
        circle.transactions.sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack(alignment: .top) {
            TallyColors.bgSecondary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 68)

                    TallyCard(
                        circleName: circle.name,
                        last4: circle.myCardLastFour ?? "0000",
                        balance: circle.walletBalance,
                        colorIndex: circleIndex,
                        photo: circle.photo,
                        walletLayout: true
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .padding(.horizontal, TallySpacing.screenPadding)

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: TallySpacing.xs) {
                            Text("BALANCE")
                                .font(TallyFont.overline)
                                .foregroundStyle(TallyColors.textSecondary)
                                .tracking(0.5)
                            Text(String(format: "$%.2f", circle.walletBalance))
                                .font(TallyFont.balanceAmount)
                                .foregroundStyle(TallyColors.textPrimary)
                        }
                        Spacer()
                        Button("Add Money") {}
                            .buttonStyle(TallySmallPrimaryButtonStyle())
                    }
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.top, TallySpacing.xl)
                    .padding(.bottom, TallySpacing.lg)

                    HStack(spacing: TallySpacing.md) {
                        detailQuickAction(icon: "paperplane", label: "Send")
                        detailQuickAction(icon: "arrow.down", label: "Request")
                        detailQuickAction(icon: "arrow.left.arrow.right", label: "Transfer")
                    }
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.bottom, TallySpacing.xl)

                    Text("LATEST TRANSACTIONS")
                        .font(TallyFont.overline)
                        .foregroundStyle(TallyColors.textSecondary)
                        .tracking(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.bottom, TallySpacing.sm)

                    if sortedTransactions.isEmpty {
                        VStack(spacing: TallySpacing.md) {
                            Image(systemName: "tray")
                                .font(TallyIcon.heroLg)
                                .foregroundStyle(TallyColors.textTertiary)
                            Text("No transactions yet")
                                .font(TallyFont.bodySemibold)
                                .foregroundStyle(TallyColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, TallySpacing.xxxl)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(sortedTransactions.prefix(20).enumerated()), id: \.element.id) { idx, tx in
                                transactionRow(tx: tx, isLast: idx == min(sortedTransactions.count, 20) - 1)
                            }
                        }
                        .background(TallyColors.bgPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                        .padding(.horizontal, TallySpacing.screenPadding)
                    }
                }
                .contentMargins(.bottom, 60, for: .scrollContent)
            }

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TallyColors.ink)
                        .frame(width: 32, height: 32)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }
                Spacer()
                Text(circle.name)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                Spacer()
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.top, TallySpacing.sm)
            .padding(.bottom, TallySpacing.xl)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: TallyColors.bgSecondary, location: 0),
                        .init(color: TallyColors.bgSecondary, location: 0.6),
                        .init(color: TallyColors.bgSecondary.opacity(0), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private func detailQuickAction(icon: String, label: String) -> some View {
        Button {} label: {
            VStack(spacing: TallySpacing.xs) {
                Image(systemName: icon)
                    .font(TallyIcon.md)
                    .fontWeight(.semibold)
                    .foregroundStyle(TallyColors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(TallyColors.bgPrimary)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                Text(label)
                    .font(TallyFont.micro)
                    .foregroundStyle(TallyColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func transactionRow(tx: CircleTransaction, isLast: Bool) -> some View {
        HStack(spacing: TallySpacing.md) {
            Text(tx.emoji)
                .font(.system(size: 20))
                .frame(width: 44, height: 44)
                .background(TallyColors.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(tx.title)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                Text(tx.paidBy == "You" ? "You paid" : "Paid by \(tx.paidBy)")
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "$%.2f", tx.amount))
                    .font(TallyFont.amountsSmall)
                    .foregroundStyle(TallyColors.textPrimary)
                Text(tx.status.label)
                    .font(TallyFont.micro)
                    .foregroundStyle(tx.status.color)
            }
        }
        .padding(.horizontal, TallySpacing.lg)
        .padding(.vertical, TallySpacing.md)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(TallyColors.divider)
                    .frame(height: 0.5)
                    .padding(.leading, 72)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    WalletTab(circles: TallyCircle.samples)
}

#Preview("Expanded") {
    WalletCardDetailView(circle: TallyCircle.sample, circleIndex: 0)
}
