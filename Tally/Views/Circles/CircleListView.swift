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
                LazyVStack(spacing: TallySpacing.md) {
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
        HStack(spacing: 0) {
            // Accent strip
            cardColor
                .frame(width: 15)

            // Card content
            VStack(alignment: .leading, spacing: 0) {
                // Header: name + circle icon
                HStack(alignment: .top, spacing: TallySpacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(circle.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(TallyColors.textPrimary)
                            .lineLimit(1)

                        // Card number or member info
                        if let lastFour = circle.myCardLastFour {
                            HStack(spacing: 5) {
                                Image(systemName: "creditcard")
                                    .font(.system(size: 11))
                                Text("•••• \(lastFour)")
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                            }
                            .foregroundStyle(TallyColors.textSecondary)
                        } else {
                            Text("\(circle.memberCount) members")
                                .font(TallyFont.caption)
                                .foregroundStyle(TallyColors.textSecondary)
                        }
                    }

                    Spacer()

                    circleImage
                }
                .padding(.bottom, TallySpacing.lg)

                // Balance row
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Balance")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(TallyColors.textSecondary)
                        Text(formattedBalance)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(TallyColors.textPrimary)
                    }

                    Spacer()

                    // Activity + members
                    VStack(alignment: .trailing, spacing: 6) {
                        memberAvatarRow

                        if let tx = latestTransaction {
                            HStack(spacing: 4) {
                                Text(tx.emoji)
                                    .font(.system(size: 11))
                                Circle()
                                    .fill(tx.status.color)
                                    .frame(width: 5, height: 5)
                                Text(tx.status.label)
                                    .font(TallyFont.smallLabel)
                                    .foregroundStyle(tx.status.color)
                            }
                        } else {
                            Text("No activity")
                                .font(TallyFont.smallLabel)
                                .foregroundStyle(TallyColors.textTertiary)
                        }
                    }
                }
            }
            .padding(TallySpacing.lg)
        }
        .background(TallyColors.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    // MARK: - Circle Image

    @ViewBuilder
    private var circleImage: some View {
        if let photo = circle.photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Text(String(circle.name.prefix(1)).uppercased())
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(
                        colors: [cardColor, cardColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Balance

    private var formattedBalance: String {
        String(format: "$%.2f", circle.walletBalance)
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
