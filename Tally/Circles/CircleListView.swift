import SwiftUI

struct CircleListView: View {
    let circles: [TallyCircle]
    @State private var searchText = ""

    private var filteredCircles: [TallyCircle] {
        guard !searchText.isEmpty else { return circles }
        return circles.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.members.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pinned search bar
            HStack(spacing: TallySpacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(TallyColors.textSecondary)
                TextField("Search circles...", text: $searchText)
                    .font(TallyFont.body)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(TallyColors.textTertiary)
                    }
                }
            }
            .padding(.horizontal, TallySpacing.lg)
            .frame(height: TallySpacing.inputHeight)
            .background(TallyColors.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.md)

            // Scrollable list
            ScrollView {
                VStack(spacing: TallySpacing.xl) {
                    ForEach(Array(filteredCircles.enumerated()), id: \.element.id) { index, circle in
                        NavigationLink(value: circle) {
                            CircleCard(circle: circle, index: index)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.top, TallySpacing.sm)
                .padding(.bottom, 100)
            }
        }
        .background(TallyColors.bgPrimary)
    }
}

// MARK: - Circle Card

private struct CircleCard: View {
    let circle: TallyCircle
    let index: Int

    private var accentColor: Color { TallyColors.cardColor(for: index) }
    private var memberCount: Int { circle.members.count + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            // ── Photo area ──────────────────────────────────────────────────
            photoArea
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))

            // ── Info: name + members label ───────────────────────────────────
            HStack(alignment: .firstTextBaseline) {
                Text(circle.name)
                    .font(TallyFont.titleSemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text("\(memberCount) members")
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
            }

            // ── Balance + avatars ────────────────────────────────────────────
            HStack(alignment: .center) {
                Text(String(format: "$%.2f", circle.walletBalance))
                    .font(TallyFont.amounts)
                    .foregroundStyle(TallyColors.textPrimary)

                Spacer()

                memberAvatarRow
            }
        }
    }

    // MARK: - Photo Area

    @ViewBuilder
    private var photoArea: some View {
        if let photo = circle.photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                LinearGradient(
                    colors: [accentColor, accentColor.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(String(circle.name.prefix(1)).uppercased())
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
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
                    .background(.black.opacity(0.08))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(TallyColors.bgPrimary, lineWidth: 2))
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
            .overlay(Circle().stroke(TallyColors.bgPrimary, lineWidth: 2))
    }
}
