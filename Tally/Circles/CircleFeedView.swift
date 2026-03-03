import SwiftUI

struct CircleFeedView: View {
    let circleID: UUID
    var viewModel: CirclesViewModel
    private let fallback: TallyCircle

    /// Always read the latest version from the viewModel.
    private var circle: TallyCircle {
        viewModel.circles.first(where: { $0.id == circleID }) ?? fallback
    }

    init(circle: TallyCircle, viewModel: CirclesViewModel) {
        self.circleID = circle.id
        self.viewModel = viewModel
        self.fallback = circle
    }

    @Environment(\.dismiss) private var navDismiss
    @State private var showSettings = false
    @State private var showAddMoney = false
    @State private var showSettleUp = false
    @State private var shouldCloseCircle = false
    @State private var isClosing = false
    @State private var closeError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                rule
                membersSection
                rule
                activitySection
            }
            .padding(.bottom, 100)
        }
        .background(TallyColors.bgPrimary)
        .navigationTitle(circle.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TallyColors.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            if shouldCloseCircle {
                shouldCloseCircle = false
                Task {
                    isClosing = true
                    await viewModel.closeCircle(circle)
                    navDismiss()
                }
            }
        }) {
            CircleSettingsSheet(circle: circle, viewModel: viewModel) {
                shouldCloseCircle = true
            }
        }
        .sheet(isPresented: $showAddMoney) { AddMoneySheet() }
        .sheet(isPresented: $showSettleUp) { SettleUpSheet(circle: circle) }
        .overlay {
            if isClosing {
                ZStack {
                    Color.black.opacity(0.3)
                    ProgressView("Closing circle...")
                        .padding(TallySpacing.xl)
                        .background(TallyColors.bgPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
                }
                .ignoresSafeArea()
            }
        }
        .alert("Error", isPresented: .init(
            get: { closeError != nil },
            set: { if !$0 { closeError = nil } }
        )) {
            Button("OK") { closeError = nil }
        } message: {
            Text(closeError ?? "Failed to close circle.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            Text("Total Balance")
                .font(TallyFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(TallyColors.textSecondary)
                .padding(.top, TallySpacing.xl)

            HStack(alignment: .bottom) {
                Text(String(format: "$%.2f", circle.walletBalance))
                    .font(TallyFont.heroAmount)
                    .foregroundStyle(TallyColors.textPrimary)

                Spacer()

                // Circular icon-only action buttons
                HStack(spacing: TallySpacing.sm) {
                    iconCircleButton(systemName: "plus") { showAddMoney = true }
                    iconCircleButton(systemName: "arrow.left.arrow.right") { showSettleUp = true }
                }
                .padding(.bottom, 6)
            }

            CardVisual(
                photo: circle.photo,
                circleName: circle.name,
                last4: "4289",
                isVirtual: true
            )
            .padding(.top, TallySpacing.sm)
            .padding(.bottom, TallySpacing.lg)
        }
        .padding(.horizontal, TallySpacing.screenPadding)
    }

    private func iconCircleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(TallyColors.ink)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var rule: some View {
        Rectangle()
            .fill(TallyColors.divider)
            .frame(height: 1)
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            Text("Members")
                .font(TallyFont.bodySemibold)
                .foregroundStyle(TallyColors.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TallySpacing.lg) {
                    MemberPill(initial: "Y", name: "You",
                               color: TallyColors.accent, isLeader: circle.leaderId == nil)
                    ForEach(circle.members) { member in
                        MemberPill(
                            initial: member.initial,
                            name: member.name.split(separator: " ").first.map(String.init) ?? member.name,
                            color: member.color,
                            isLeader: circle.leaderId == member.id
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.vertical, TallySpacing.lg)
    }

    // MARK: - Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Transactions")
                .font(TallyFont.title)
                .foregroundStyle(TallyColors.textPrimary)
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.top, TallySpacing.lg)
                .padding(.bottom, TallySpacing.sm)

            if circle.transactions.isEmpty {
                VStack(spacing: TallySpacing.sm) {
                    Text("🧾").font(.system(size: 36))
                    Text("No transactions yet")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, TallySpacing.xxxl)
            } else {
                ForEach(groupedTransactions, id: \.label) { group in
                    Text(group.label)
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.top, TallySpacing.md)
                        .padding(.bottom, 2)

                    ForEach(Array(group.transactions.enumerated()), id: \.element.id) { idx, tx in
                        Rectangle().fill(TallyColors.divider).frame(height: 0.5)
                        FeedTransactionRow(tx: tx, colorIndex: idx)
                    }
                }
                Rectangle().fill(TallyColors.divider).frame(height: 0.5)
            }
        }
    }

    // MARK: - Grouping

    private struct DateGroup { let label: String; let transactions: [CircleTransaction] }

    private var groupedTransactions: [DateGroup] {
        let cal = Calendar.current
        var buckets: [(key: Date, txs: [CircleTransaction])] = []
        for tx in circle.transactions.sorted(by: { $0.date > $1.date }) {
            let day = cal.startOfDay(for: tx.date)
            if let i = buckets.firstIndex(where: { cal.isDate($0.key, inSameDayAs: day) }) {
                buckets[i].txs.append(tx)
            } else { buckets.append((day, [tx])) }
        }
        return buckets.map { b in
            let label: String
            if cal.isDateInToday(b.key) { label = "Today" }
            else if cal.isDateInYesterday(b.key) { label = "Yesterday" }
            else { let f = DateFormatter(); f.dateFormat = "MMMM d"; label = f.string(from: b.key) }
            return DateGroup(label: label, transactions: b.txs)
        }
    }
}

// MARK: - Member Pill

private struct MemberPill: View {
    let initial: String
    let name: String
    let color: Color
    let isLeader: Bool

    var body: some View {
        VStack(spacing: TallySpacing.xs) {
            ZStack(alignment: .bottomTrailing) {
                Text(initial)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(color)
                    .clipShape(Circle())

                if isLeader {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(TallyColors.accent)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(TallyColors.bgPrimary, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }
            }
            Text(name)
                .font(TallyFont.smallLabel)
                .foregroundStyle(TallyColors.textSecondary)
                .lineLimit(1)
                .frame(width: 56)
        }
    }
}

// MARK: - Flat Transaction Row

private struct FeedTransactionRow: View {
    let tx: CircleTransaction
    let colorIndex: Int

    var body: some View {
        HStack(spacing: TallySpacing.md) {
            Text(tx.emoji)
                .font(.system(size: 20))
                .frame(width: 44, height: 44)
                .background(TallyColors.cardColor(for: colorIndex))
                .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardInnerRadius))

            VStack(alignment: .leading, spacing: 3) {
                Text(tx.title)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                HStack(spacing: 4) {
                    Text("paid by \(tx.paidBy)")
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                    Circle().fill(tx.status.color).frame(width: 5, height: 5)
                    Text(tx.status.label)
                        .font(TallyFont.caption)
                        .foregroundStyle(tx.status.color)
                }
            }

            Spacer(minLength: 0)

            Text(String(format: "$%.2f", tx.amount))
                .font(TallyFont.amounts)
                .foregroundStyle(TallyColors.textPrimary)
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.vertical, TallySpacing.md)
        .background(TallyColors.bgPrimary)
    }
}

// MARK: - Circle Settings Sheet

struct CircleSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var circle: TallyCircle
    var viewModel: CirclesViewModel
    var onCloseCircle: () -> Void = {}

    @State private var circleName: String
    @State private var selectedSplit: SplitMethod
    @State private var autoSettle = true
    @State private var transactionNotifications = true
    @State private var showCloseConfirm = false

    init(circle: TallyCircle, viewModel: CirclesViewModel, onCloseCircle: @escaping () -> Void = {}) {
        self.circle = circle
        self.viewModel = viewModel
        self._circleName = State(initialValue: circle.name)
        self._selectedSplit = State(initialValue: circle.splitMethod)
        self.onCloseCircle = onCloseCircle
    }

    private var hasChanges: Bool {
        circleName.trimmingCharacters(in: .whitespaces) != circle.name ||
        selectedSplit != circle.splitMethod
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Circle name ─────────────────────────────────────────
                    HStack {
                        TextField("Circle name", text: $circleName)
                            .font(TallyFont.titleSemibold)
                            .foregroundStyle(TallyColors.textPrimary)
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(TallyColors.textSecondary)
                    }
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.top, TallySpacing.lg)
                    .padding(.bottom, TallySpacing.xl)

                    Divider()

                    // ── Split Mode ───────────────────────────────────────────
                    Text("SPLIT MODE")
                        .font(TallyFont.smallLabel)
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.top, TallySpacing.xl)
                        .padding(.bottom, TallySpacing.sm)

                    VStack(spacing: TallySpacing.sm) {
                        splitModeCard(
                            method: .equal,
                            icon: "equal.circle.fill",
                            title: "Equal",
                            subtitle: "Split evenly among all members"
                        )
                        splitModeCard(
                            method: .custom,
                            icon: "slider.horizontal.3",
                            title: "Custom",
                            subtitle: "Set specific amounts per member"
                        )
                        splitModeCard(
                            method: .percentage,
                            icon: "percent",
                            title: "Percentage",
                            subtitle: "Split by percentage"
                        )
                    }
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.bottom, TallySpacing.xl)

                    Divider()

                    // ── Toggles ──────────────────────────────────────────────
                    toggleRow(
                        title: "Auto-settle",
                        subtitle: "Automatically split after grace period",
                        isOn: $autoSettle
                    )

                    Divider()

                    toggleRow(
                        title: "Transaction notifications",
                        subtitle: "Get notified for every transaction",
                        isOn: $transactionNotifications
                    )

                    Divider()

                    // ── Grace period ─────────────────────────────────────────
                    Button {} label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Grace period")
                                    .font(TallyFont.bodySemibold)
                                    .foregroundStyle(TallyColors.textPrimary)
                                Text("Time for members to review charges")
                                    .font(TallyFont.caption)
                                    .foregroundStyle(TallyColors.textSecondary)
                            }
                            Spacer()
                            HStack(spacing: TallySpacing.xs) {
                                Text("24 hours")
                                    .font(TallyFont.body)
                                    .foregroundStyle(TallyColors.textSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(TallyColors.textTertiary)
                            }
                        }
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.vertical, TallySpacing.lg)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    // ── Actions ──────────────────────────────────────────────
                    settingsActionRow(icon: "person.badge.plus", label: "Invite member") {}
                    Divider().padding(.leading, TallySpacing.screenPadding + 32 + TallySpacing.md)
                    settingsActionRow(icon: "shield.lefthalf.filled", label: "Reassign backup leader") {}
                    Divider().padding(.leading, TallySpacing.screenPadding + 32 + TallySpacing.md)
                    settingsActionRow(icon: "snowflake", label: "Freeze card") {}

                    Divider()
                        .padding(.top, TallySpacing.sm)

                    // ── Close Circle ─────────────────────────────────────────
                    Button { showCloseConfirm = true } label: {
                        HStack(spacing: TallySpacing.md) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(TallyColors.statusAlert)
                            Text("Close Circle")
                                .font(TallyFont.bodySemibold)
                                .foregroundStyle(TallyColors.statusAlert)
                            Spacer()
                        }
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.vertical, TallySpacing.lg)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, TallySpacing.xxxl)
            }
            .background(TallyColors.bgPrimary)
            .navigationTitle("Circle Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if hasChanges {
                            let newName = circleName.trimmingCharacters(in: .whitespaces)
                            let nameChange = newName != circle.name ? newName : nil
                            let splitChange = selectedSplit != circle.splitMethod ? selectedSplit : nil
                            Task {
                                await viewModel.updateCircle(circle, name: nameChange, splitMethod: splitChange)
                            }
                        }
                        dismiss()
                    }
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.accent)
                }
            }
            .confirmationDialog("Close \(circle.name)?", isPresented: $showCloseConfirm,
                                titleVisibility: .visible) {
                Button("Close Circle", role: .destructive) {
                    onCloseCircle()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will settle all remaining balances and permanently close the circle.")
            }
        }
    }

    // MARK: - Split Mode Card

    private func splitModeCard(method: SplitMethod, icon: String, title: String, subtitle: String) -> some View {
        let isSelected = selectedSplit == method
        return Button {
            withAnimation(.spring(response: 0.25)) {
                selectedSplit = method
            }
        } label: {
            HStack(spacing: TallySpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? TallyColors.accent : TallyColors.textSecondary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(TallyColors.textPrimary)
                    Text(subtitle)
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, TallySpacing.lg)
            .padding(.vertical, TallySpacing.md)
            .background(
                RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                    .fill(isSelected ? TallyColors.accent.opacity(0.08) : TallyColors.bgPrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                    .stroke(isSelected ? TallyColors.accent : TallyColors.divider, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toggle Row

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                Text(subtitle)
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .tint(TallyColors.accent)
                .labelsHidden()
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.vertical, TallySpacing.lg)
    }

    // MARK: - Action Row

    private func settingsActionRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: TallySpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(TallyColors.textSecondary)
                    .frame(width: 32, height: 32)
                Text(label)
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TallyColors.textTertiary)
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.vertical, TallySpacing.lg)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Money Sheet

private struct AddMoneySheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: TallySpacing.xl) {
                Spacer()
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 64)).foregroundStyle(TallyColors.accent)
                VStack(spacing: TallySpacing.sm) {
                    Text("Add Money").font(TallyFont.title).foregroundStyle(TallyColors.textPrimary)
                    Text("Connect your bank to fund\nthe circle wallet.")
                        .font(TallyFont.body).foregroundStyle(TallyColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Button("Connect Bank") {}
                    .buttonStyle(TallyPrimaryButtonStyle())
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.bottom, TallySpacing.xxxl)
            }
            .navigationTitle("Add Money").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Cancel") { dismiss() }.foregroundStyle(TallyColors.accent)
            }}
        }
    }
}

// MARK: - Settle Up Sheet

private struct SettleUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    var circle: TallyCircle
    var body: some View {
        NavigationStack {
            VStack(spacing: TallySpacing.xl) {
                Spacer()
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 64)).foregroundStyle(TallyColors.statusSocial)
                VStack(spacing: TallySpacing.sm) {
                    Text("Settle Up").font(TallyFont.title).foregroundStyle(TallyColors.textPrimary)
                    Text("Clear pending balances with\nyour group members.")
                        .font(TallyFont.body).foregroundStyle(TallyColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Button("Settle All Balances") {}
                    .buttonStyle(TallyPrimaryButtonStyle())
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.bottom, TallySpacing.xxxl)
            }
            .navigationTitle("Settle Up").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Cancel") { dismiss() }.foregroundStyle(TallyColors.accent)
            }}
        }
    }
}
