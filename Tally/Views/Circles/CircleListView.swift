import SwiftUI

struct CircleListView: View {
    let circles: [TallyCircle]
    @Binding var searchText: String
    var onAdd: () -> Void

    private var filteredCircles: [TallyCircle] {
        guard !searchText.isEmpty else { return circles }
        return circles.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.members.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // ── Scrollable cards ─────────────────────────────
            ScrollView {
                LazyVStack(spacing: TallySpacing.xl) {
                    ForEach(Array(filteredCircles.enumerated()), id: \.element.id) { index, circle in
                        NavigationLink(value: circle) {
                            CircleCard(circle: circle, index: index)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.top, 72) // space for floating search bar + gap
                .padding(.bottom, TallySpacing.lg)
            }

            // ── Floating search bar + add button ─────────────
            HStack(spacing: TallySpacing.sm) {
                searchBar
                addButton
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.top, TallySpacing.sm)
            .padding(.bottom, TallySpacing.sm)
        }
        .background {
            TallyColors.bgPrimary
                .ignoresSafeArea()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: TallySpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(TallyColors.textSecondary)

            TextField("Search circles", text: $searchText)
                .font(TallyFont.body)
                .foregroundStyle(TallyColors.textPrimary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(TallyColors.textSecondary)
                }
            }
        }
        .padding(.horizontal, TallySpacing.lg)
        .frame(height: 44)
        .liquidGlass(in: Capsule())
    }

    // MARK: - Add Button

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(TallyColors.ink)
                .frame(width: 44, height: 44)
                .liquidGlass(in: Circle())
        }
    }
}

// MARK: - Circle Card

private struct CircleCard: View {
    let circle: TallyCircle
    let index: Int

    private var cardColor: Color {
        TallyColors.cardColor(for: index)
    }

    private var latestTransaction: CircleTransaction? {
        circle.transactions.sorted { $0.date > $1.date }.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Zone 1: Header ───────────────────────────────
            HStack(alignment: .top, spacing: TallySpacing.md) {
                circleImage

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(circle.name)
                            .font(TallyFont.bodySemibold)
                            .foregroundStyle(TallyColors.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        Text(formattedBalance)
                            .font(TallyFont.title)
                            .foregroundStyle(TallyColors.textPrimary)
                    }

                    // Activity subtitle or placeholder
                    if let tx = latestTransaction {
                        HStack(spacing: 5) {
                            Text(tx.emoji)
                                .font(.system(size: 13))
                            Text(tx.title)
                                .font(TallyFont.caption)
                                .foregroundStyle(TallyColors.textSecondary)
                                .lineLimit(1)
                            Circle()
                                .fill(tx.status.color)
                                .frame(width: 5, height: 5)
                            Text(tx.status.label)
                                .font(TallyFont.smallLabel)
                                .foregroundStyle(tx.status.color)
                        }
                    } else {
                        Text("No activity yet")
                            .font(TallyFont.caption)
                            .foregroundStyle(TallyColors.textTertiary)
                    }
                }
            }
            .padding(.horizontal, TallySpacing.cardPadding)
            .padding(.top, TallySpacing.lg)
            .padding(.bottom, TallySpacing.md)

            // ── Zone 2: Tinted divider ───────────────────────
            cardColor.opacity(0.20)
                .frame(height: 1)
                .padding(.horizontal, TallySpacing.md)

            // ── Zone 3: Footer ───────────────────────────────
            HStack(alignment: .center) {
                // Virtual card number
                if let lastFour = circle.myCardLastFour {
                    HStack(spacing: 4) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 11))
                            .foregroundStyle(TallyColors.textSecondary)
                        Text("•••• \(lastFour)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(TallyColors.textSecondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 11))
                            .foregroundStyle(TallyColors.textTertiary)
                        Text("No card linked")
                            .font(TallyFont.caption)
                            .foregroundStyle(TallyColors.textTertiary)
                    }
                }

                Spacer(minLength: TallySpacing.sm)

                // Member avatars + count
                VStack(alignment: .trailing, spacing: 3) {
                    memberAvatarRow
                    Text("\(circle.memberCount) members")
                        .font(TallyFont.smallLabel)
                        .foregroundStyle(TallyColors.textTertiary)
                }
            }
            .padding(.horizontal, TallySpacing.cardPadding)
            .padding(.top, TallySpacing.md)
            .padding(.bottom, TallySpacing.lg)
        }
        .background(TallyColors.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    // MARK: - Circle Image

    @ViewBuilder
    private var circleImage: some View {
        if let photo = circle.photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardInnerRadius))
        } else {
            Text(String(circle.name.prefix(1)).uppercased())
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(
                        colors: [cardColor, cardColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardInnerRadius))
        }
    }

    // MARK: - Balance

    private var formattedBalance: String {
        String(format: "$%.0f", circle.walletBalance)
    }

    // MARK: - Member Avatars

    @ViewBuilder
    private var memberAvatarRow: some View {
        HStack(spacing: -6) {
            avatarBubble(initial: "Y", color: TallyColors.accent)
            ForEach(Array(circle.members.prefix(3))) { member in
                avatarBubble(initial: member.initial, color: member.color)
            }
            if circle.members.count > 3 {
                Text("+\(circle.members.count - 3)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(TallyColors.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(TallyColors.bgSecondary, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
            }
        }
    }

    private func avatarBubble(initial: String, color: Color) -> some View {
        Text(initial)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(color)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
    }
}
