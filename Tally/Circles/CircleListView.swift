import SwiftUI

struct CircleListView: View {
    let circles: [TallyCircle]
    let onSelect: (TallyCircle) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: TallySpacing.cardGap) {
                ForEach(circles) { circle in
                    CircleRowView(circle: circle)
                        .onTapGesture { onSelect(circle) }
                }
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.top, TallySpacing.sm)
        }
    }
}

// MARK: - Circle Row

private struct CircleRowView: View {
    let circle: TallyCircle

    private var totalSpent: String {
        let total = circle.transactions.reduce(0) { $0 + $1.amount }
        return String(format: "$%.2f", total)
    }

    private var lastTransaction: String {
        guard let last = circle.transactions.first else { return "No activity yet" }
        return "\(last.paidBy) paid \(last.title)"
    }

    var body: some View {
        HStack(spacing: TallySpacing.md) {
            // Photo or initial
            if let photo = circle.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Text(String(circle.name.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        LinearGradient(
                            colors: [TallyColors.accent, TallyColors.accent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(circle.name)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                Text(lastTransaction)
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(totalSpent)
                    .font(TallyFont.amounts)
                    .foregroundStyle(TallyColors.textPrimary)
                Text("\(circle.members.count) members")
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
            }
        }
        .padding(TallySpacing.cardPadding)
        .background(TallyColors.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}
