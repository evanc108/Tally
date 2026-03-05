//
//  ContentView.swift
//  Tally
//
//  Created by Evan Chang on 3/1/26.
//

import SwiftUI
import ClerkKit

// MARK: - Scroll Offset Preference

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Tab Definition

enum TallyTab: Int, CaseIterable {
    case home, circles, pay, wallet, profile

    var title: String {
        switch self {
        case .home: "Home"
        case .circles: "Circles"
        case .pay: "Pay"
        case .wallet: "Wallet"
        case .profile: "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .circles: "person.3"
        case .pay: "dollarsign"
        case .wallet: "wallet.bifold"
        case .profile: "person"
        }
    }

    var activeIcon: String {
        switch self {
        case .home: "house.fill"
        case .circles: "person.3.fill"
        case .pay: "dollarsign"
        case .wallet: "wallet.bifold.fill"
        case .profile: "person.fill"
        }
    }
}

// MARK: - Root View

struct ContentView: View {
    @Environment(Clerk.self) private var clerk
    @State private var selectedTab: TallyTab = .home
    @State private var previousTab: TallyTab = .home
    @State private var circlesViewModel = CirclesViewModel()
    @State private var showPayFlow = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                HomeTab(circles: circlesViewModel.circles)
            }
            Tab("Circles", systemImage: "person.3", value: .circles) {
                CirclesTab(viewModel: circlesViewModel)
            }
            Tab(value: .pay) {
                EmptyView()
            } label: {
                Label("Pay", systemImage: "dollarsign.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, TallyColors.accent)
            }
            Tab("Wallet", systemImage: "wallet.bifold", value: .wallet) {
                WalletTab()
            }
            Tab("Profile", systemImage: "person", value: .profile) {
                ProfileTab()
            }
        }
        .tint(.black)
        .task {
            await circlesViewModel.fetchCircles()
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            if newTab == .pay {
                showPayFlow = true
                selectedTab = oldTab
            } else {
                previousTab = newTab
            }
        }
        .fullScreenCover(isPresented: $showPayFlow, onDismiss: {
            Task { await circlesViewModel.fetchCircles(force: true) }
        }) {
            PayFlowView(availableCircles: circlesViewModel.circles)
        }
    }
}

// MARK: - Activity Models

struct ActivityItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let amount: Double
    let isCredit: Bool
    let date: Date
    let icon: ActivityIcon

    var formattedAmount: String {
        let prefix = isCredit ? "+" : "-"
        return "\(prefix)$\(String(format: "%.2f", amount))"
    }
}

enum ActivityIcon {
    case category(emoji: String, background: Color)
    case person(initial: String, color: Color)
}

extension ActivityItem {
    static let samples: [ActivityItem] = [
        ActivityItem(title: "Starbucks",    subtitle: "Coffee",        amount: 12.50,  isCredit: false, date: .now,                              icon: .category(emoji: "☕️", background: TallyColors.cardPeach)),
        ActivityItem(title: "Sarah Kim",    subtitle: "Roommates",     amount: 43.20,  isCredit: true,  date: .now.addingTimeInterval(-3_600),   icon: .person(initial: "S", color: .orange)),
        ActivityItem(title: "Spotify",      subtitle: "Music",         amount: 14.99,  isCredit: false, date: .now.addingTimeInterval(-86_400),  icon: .category(emoji: "🎵", background: TallyColors.cardMint)),
        ActivityItem(title: "Whole Foods",  subtitle: "Groceries",     amount: 86.40,  isCredit: false, date: .now.addingTimeInterval(-86_400),  icon: .category(emoji: "🛒", background: TallyColors.cardSky)),
        ActivityItem(title: "Alex Chen",    subtitle: "Ski Trip",      amount: 150.00, isCredit: true,  date: .now.addingTimeInterval(-86_400),  icon: .person(initial: "A", color: .blue)),
        ActivityItem(title: "Uber",         subtitle: "Transport",     amount: 28.00,  isCredit: false, date: .now.addingTimeInterval(-172_800), icon: .category(emoji: "🚗", background: TallyColors.cardCream)),
        ActivityItem(title: "Netflix",      subtitle: "Entertainment", amount: 22.99,  isCredit: false, date: .now.addingTimeInterval(-172_800), icon: .category(emoji: "🎬", background: TallyColors.cardBlush)),
        ActivityItem(title: "Jordan Park",  subtitle: "Date Night",    amount: 65.00,  isCredit: true,  date: .now.addingTimeInterval(-259_200), icon: .person(initial: "J", color: .purple)),
        ActivityItem(title: "Trader Joe's", subtitle: "Groceries",     amount: 54.30,  isCredit: false, date: .now.addingTimeInterval(-259_200), icon: .category(emoji: "🛍️", background: TallyColors.cardSky)),
        ActivityItem(title: "Electric Bill",subtitle: "Utilities",     amount: 142.00, isCredit: false, date: .now.addingTimeInterval(-345_600), icon: .category(emoji: "⚡️", background: TallyColors.cardCream)),
    ]
}

// MARK: - Home Tab

private struct HomeTab: View {
    let circles: [TallyCircle]

    // Track scroll offset for header fade
    @State private var scrollOffset: CGFloat = 0

    private var groupedItems: [(label: String, items: [ActivityItem])] {
        let items = ActivityItem.samples
        let calendar = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"

        let grouped = Dictionary(grouping: items) { item -> String in
            if calendar.isDateInToday(item.date)     { return "Today" }
            if calendar.isDateInYesterday(item.date)  { return "Yesterday" }
            return fmt.string(from: item.date)
        }

        let pinned = ["Today", "Yesterday"]
        return grouped
            .map { (label: $0.key, items: $0.value) }
            .sorted { a, b in
                let ai = pinned.firstIndex(of: a.label) ?? 99
                let bi = pinned.firstIndex(of: b.label) ?? 99
                if ai != bi { return ai < bi }
                let ad = a.items.first?.date ?? .distantPast
                let bd = b.items.first?.date ?? .distantPast
                return ad > bd
            }
    }

    /// Hardcoded total balance for UI testing.
    private var totalBalance: String { "$1,000.00" }

    /// Header opacity: fully visible until 60pt scroll, fades out by 140pt
    private var headerOpacity: Double {
        let fadeStart: CGFloat = 60
        let fadeEnd: CGFloat = 140
        if scrollOffset <= fadeStart { return 1 }
        if scrollOffset >= fadeEnd { return 0 }
        return Double(1 - (scrollOffset - fadeStart) / (fadeEnd - fadeStart))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                balanceRow
                if !circles.isEmpty { circleCarousel }
                transactionsHeader
                transactionsList
            }
            .padding(.bottom, TallySpacing.lg)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: -geo.frame(in: .named("homeScroll")).minY
                    )
                }
            )
        }
        .coordinateSpace(name: "homeScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
        .background(TallyColors.bgPrimary)
    }

    // MARK: - Top Bar (scrolls with content, fades on deep scroll)

    private var topBar: some View {
        ZStack {
            Text("Mntly")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(TallyColors.textPrimary)

            HStack {
                Spacer()
                Button {} label: {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(TallyColors.textPrimary)
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle())
                }
            }
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.top, TallySpacing.sm)
        .opacity(headerOpacity)
    }

    // MARK: - Balance Row (left-aligned balance + right-aligned pills)

    private var balanceRow: some View {
        HStack(alignment: .bottom) {
            // Left: balance stack
            VStack(alignment: .leading, spacing: 2) {
                Text("Total Balance")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TallyColors.textPrimary)
                Text(totalBalance)
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(TallyColors.textPrimary)
            }

            Spacer()

            // Right: compact pill buttons
            HStack(spacing: TallySpacing.sm) {
                quickActionPill(icon: "plus", label: "Add")
                quickActionPill(icon: "arrow.up.right", label: "Send")
            }
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.top, TallySpacing.lg)
        .padding(.bottom, TallySpacing.xxxl)
    }

    private func quickActionPill(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(label)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(TallyColors.accent)
        .clipShape(Capsule())
    }

    // MARK: - Circle Carousel

    private var circleCarousel: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            HStack {
                Text("Your Circles")
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textSecondary)
                Spacer()
                Button {} label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add")
                            .font(TallyFont.body)
                    }
                    .foregroundStyle(TallyColors.accent)
                }
            }
            .padding(.horizontal, TallySpacing.screenPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TallySpacing.md) {
                    ForEach(circles) { circle in
                        MiniTallyCard(circle: circle)
                    }
                }
                .padding(.horizontal, TallySpacing.screenPadding)
            }
        }
        .padding(.bottom, TallySpacing.xl)
    }

    // MARK: - Transactions

    private var transactionsHeader: some View {
        HStack {
            Text("Transactions")
                .font(TallyFont.bodySemibold)
                .foregroundStyle(TallyColors.textSecondary)
            Spacer()
            Button {} label: {
                HStack(spacing: TallySpacing.xs) {
                    Text("See all")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TallyColors.accent)
                }
            }
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.bottom, TallySpacing.md)
    }

    private var transactionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if groupedItems.isEmpty {
                emptyState
            } else {
                ForEach(groupedItems, id: \.label) { group in
                    Text(group.label)
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.top, TallySpacing.lg)
                        .padding(.bottom, TallySpacing.sm)

                    VStack(spacing: TallySpacing.sm) {
                        ForEach(group.items) { item in
                            ActivityRowView(item: item)
                        }
                    }
                    .padding(.horizontal, TallySpacing.screenPadding)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: TallySpacing.md) {
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(TallyColors.textTertiary)
            Text("No activity found")
                .font(TallyFont.bodySemibold)
                .foregroundStyle(TallyColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TallySpacing.xxxl)
    }
}

// MARK: - Mini Tally Card

private struct MiniTallyCard: View {
    let circle: TallyCircle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: circle name label
            Text(circle.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)

            // Hero balance
            Text(String(format: "$%.0f", circle.walletBalance))
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.top, 2)

            Spacer()

            // Bottom: card number + contactless + brand
            HStack(alignment: .bottom) {
                HStack(spacing: 6) {
                    Image(systemName: "wave.3.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("•• \(circle.myCardLastFour ?? "4289")")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Text("tally")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .padding(TallySpacing.lg)
        .frame(width: 220, height: 140)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        TallyColors.accent,
                        TallyColors.mintLeaf,
                        TallyColors.hunterGreen,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // Subtle noise/texture feel with overlapping gradient
                RadialGradient(
                    colors: [Color.white.opacity(0.12), .clear],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 160
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: TallyColors.hunterGreen.opacity(0.3), radius: 16, y: 8)
    }
}

// MARK: - Activity Row

private struct ActivityRowView: View {
    let item: ActivityItem

    var body: some View {
        HStack(spacing: TallySpacing.md) {
            ActivityIconView(icon: item.icon, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                Text(item.subtitle)
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
            }

            Spacer()

            Text(item.formattedAmount)
                .font(TallyFont.amounts)
                .foregroundStyle(item.isCredit ? TallyColors.statusSuccess : TallyColors.textPrimary)
        }
        .padding(.horizontal, TallySpacing.lg)
        .padding(.vertical, TallySpacing.md)
        .liquidGlass(in: RoundedRectangle(cornerRadius: TallySpacing.cardInnerRadius))
    }
}

// MARK: - Activity Icon

private struct ActivityIconView: View {
    let icon: ActivityIcon
    var size: CGFloat = 44

    var body: some View {
        switch icon {
        case .category(let emoji, let background):
            Text(emoji)
                .font(.system(size: size * 0.46))
                .frame(width: size, height: size)
                .background(background.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        case .person(let initial, let color):
            Text(initial)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Circles Tab

private struct CirclesTab: View {
    @Bindable var viewModel: CirclesViewModel
    @State private var showCreateFlow = false
    @State private var navigationPath = NavigationPath()
    @State private var pendingCircle: TallyCircle?
    @State private var searchText = ""

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading && viewModel.circles.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.circles.isEmpty {
                    emptyState
                } else {
                    CircleListView(
                        circles: viewModel.circles,
                        searchText: $searchText,
                        onAdd: { showCreateFlow = true }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TallyColors.bgSecondary)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TallyCircle.self) { circle in
                CircleFeedView(circle: circle, viewModel: viewModel)
            }
            .fullScreenCover(isPresented: $showCreateFlow, onDismiss: {
                if let circle = pendingCircle {
                    pendingCircle = nil
                    navigationPath.append(circle)
                }
            }) {
                CreateCircleFlowView(viewModel: viewModel) { createdCircle in
                    pendingCircle = createdCircle
                }
            }
            .task(id: "circles") {
                await viewModel.fetchCircles()
            }
            .refreshable {
                await viewModel.fetchCircles(force: true)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TallySpacing.lg) {
            Spacer()
            Image(systemName: "person.3")
                .font(.system(size: 48))
                .foregroundStyle(TallyColors.textSecondary)
            Text("No circles yet")
                .font(TallyFont.title)
                .foregroundStyle(TallyColors.textPrimary)
            Text("Create a circle to start splitting expenses with friends.")
                .font(TallyFont.body)
                .foregroundStyle(TallyColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TallySpacing.xxl)
            Button("Create Circle") { showCreateFlow = true }
                .buttonStyle(TallyPrimaryButtonStyle())
                .padding(.horizontal, TallySpacing.screenPadding)
            Spacer()
        }
    }
}

// MARK: - Wallet Tab

private struct WalletTab: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: TallySpacing.lg) {
                Spacer()
                Text("$0.00")
                    .font(TallyFont.heroAmount)
                    .foregroundStyle(TallyColors.textPrimary)
                Text("Load your wallet to get started")
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textSecondary)
                HStack(spacing: TallySpacing.md) {
                    Button("Load Wallet") {}
                        .buttonStyle(TallyPrimaryButtonStyle())
                    Button("Transfer") {}
                        .buttonStyle(TallySecondaryButtonStyle())
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TallyColors.bgPrimary)
            .navigationTitle("Wallet")
        }
    }
}

// MARK: - Profile Tab

private struct ProfileTab: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(Clerk.self) private var clerk

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: TallySpacing.md) {
                        Circle()
                            .fill(TallyColors.accent)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Text(initials)
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                        VStack(alignment: .leading, spacing: TallySpacing.xs) {
                            Text(displayName)
                                .font(TallyFont.bodySemibold)
                                .foregroundStyle(TallyColors.textPrimary)
                            if let email = clerk.user?.primaryEmailAddress?.emailAddress {
                                Text(email)
                                    .font(TallyFont.caption)
                                    .foregroundStyle(TallyColors.textSecondary)
                            }
                        }
                    }
                    .padding(.vertical, TallySpacing.sm)
                }

                Section("Linked Accounts") {
                    Label("Add bank account", systemImage: "building.columns")
                        .foregroundStyle(TallyColors.textSecondary)
                }

                Section("Security") {
                    Label("Face ID", systemImage: "faceid")
                    Label("Change email", systemImage: "envelope")
                }

                Section("Preferences") {
                    Label("Notifications", systemImage: "bell")
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }

                Section("Legal") {
                    Label("Terms of Service", systemImage: "doc.text")
                    Label("Privacy Policy", systemImage: "hand.raised")
                }

                Section {
                    Button("Sign Out") {
                        signOut()
                    }
                    .foregroundStyle(TallyColors.statusAlert)
                    .frame(maxWidth: .infinity)
                }

                Section {
                    Button("Delete Account") {}
                        .foregroundStyle(TallyColors.statusAlert)
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Profile")
        }
    }

    private var displayName: String {
        let first = clerk.user?.firstName ?? ""
        let last = clerk.user?.lastName ?? ""
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? "Tally User" : full
    }

    private var initials: String {
        let first = clerk.user?.firstName?.prefix(1) ?? ""
        let last = clerk.user?.lastName?.prefix(1) ?? ""
        let result = "\(first)\(last)"
        return result.isEmpty ? "T" : result.uppercased()
    }

    private func signOut() {
        Task {
            try? await clerk.auth.signOut()
            authManager.signOut()
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
        .environment(Clerk.shared)
}
