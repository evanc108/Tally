import SwiftUI

struct CircleFeedView: View {
    let circle: TallyCircle

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                circleHeader

                Divider()
                    .padding(.horizontal, TallySpacing.screenPadding)

                memberBar
                    .padding(.vertical, TallySpacing.lg)

                Divider()
                    .padding(.horizontal, TallySpacing.screenPadding)

                transactionFeed
            }
        }
        .background(TallyColors.bgPrimary)
        .navigationTitle(circle.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var circleHeader: some View {
        VStack(spacing: TallySpacing.md) {
            // Photo or initial
            if let photo = circle.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
            } else {
                Text(String(circle.name.prefix(1)).uppercased())
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        LinearGradient(
                            colors: [TallyColors.accent, TallyColors.accent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
            }

            Text(totalOwed)
                .font(TallyFont.heroAmount)
                .foregroundStyle(TallyColors.textPrimary)

            Text("total this month")
                .font(TallyFont.caption)
                .foregroundStyle(TallyColors.textSecondary)

            HStack(spacing: TallySpacing.md) {
                Button("Settle Up") {}
                    .buttonStyle(TallyPrimaryButtonStyle())
                Button("Add Expense") {}
                    .buttonStyle(TallySecondaryButtonStyle())
            }
            .padding(.horizontal, TallySpacing.screenPadding)
        }
        .padding(.vertical, TallySpacing.xl)
    }

    // MARK: - Member Bar

    private var memberBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: TallySpacing.lg) {
                ForEach(circle.members) { member in
                    VStack(spacing: TallySpacing.xs) {
                        AvatarCircleView(initial: member.initial, color: member.color, size: 40)
                        Text(member.name.split(separator: " ").first.map(String.init) ?? member.name)
                            .font(TallyFont.caption)
                            .foregroundStyle(TallyColors.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(width: 56)
                }
            }
            .padding(.horizontal, TallySpacing.screenPadding)
        }
    }

    // MARK: - Transaction Feed

    private var transactionFeed: some View {
        LazyVStack(spacing: 0) {
            ForEach(circle.transactions) { tx in
                HStack(spacing: TallySpacing.md) {
                    Circle()
                        .fill(tx.status.color)
                        .frame(width: 8, height: 8)

                    Text(tx.emoji)
                        .font(.system(size: 14))
                        .frame(width: 32, height: 32)
                        .background(TallyColors.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tx.title)
                            .font(TallyFont.body)
                            .foregroundStyle(TallyColors.textPrimary)
                        Text("\(tx.paidBy) · \(tx.status.label)")
                            .font(TallyFont.caption)
                            .foregroundStyle(TallyColors.textSecondary)
                    }

                    Spacer()

                    Text(String(format: "$%.2f", tx.amount))
                        .font(TallyFont.amounts)
                        .foregroundStyle(TallyColors.textPrimary)
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.vertical, TallySpacing.md)

                if tx.id != circle.transactions.last?.id {
                    Divider()
                        .padding(.leading, TallySpacing.screenPadding + 8 + TallySpacing.md + 32 + TallySpacing.md)
                }
            }
        }
    }

    private var totalOwed: String {
        let total = circle.transactions.reduce(0) { $0 + $1.amount }
        return String(format: "$%.2f", total)
    }
}
