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
    @State private var circlesViewModel = CirclesViewModel()
    @State private var showPayFlow = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch selectedTab {
                case .home:
                    NavigationStack {
                        HomeTab(circles: circlesViewModel.circles)
                            .toolbar(.hidden, for: .navigationBar)
                    }
                case .circles:
                    CirclesTab(viewModel: circlesViewModel)
                case .pay:
                    EmptyView()
                case .wallet:
                    WalletTab()
                case .profile:
                    ProfileTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom liquid glass tab bar
            TallyTabBar(selectedTab: $selectedTab, onPayTap: {
                showPayFlow = true
            })
        }
        .ignoresSafeArea(.keyboard)
        .task {
            await circlesViewModel.fetchCircles()
        }
        .fullScreenCover(isPresented: $showPayFlow, onDismiss: {
            Task { await circlesViewModel.fetchCircles(force: true) }
        }) {
            PayFlowView(availableCircles: circlesViewModel.circles)
        }
    }

}

// MARK: - Custom Liquid Glass Tab Bar

private struct TallyTabBar: View {
    @Binding var selectedTab: TallyTab
    @Environment(Clerk.self) private var clerk
    var onPayTap: () -> Void

    private var userInitials: String {
        let first = clerk.user?.firstName?.prefix(1) ?? ""
        let last = clerk.user?.lastName?.prefix(1) ?? ""
        let result = "\(first)\(last)"
        return result.isEmpty ? "T" : result.uppercased()
    }

    var body: some View {
        HStack(spacing: 0) {
            // Home
            tabButton(for: .home)
            // Circles
            tabButton(for: .circles)
            // Pay — green circle, no label
            Button {
                onPayTap()
            } label: {
                Image(systemName: "dollarsign")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(TallyColors.accent)
                    .clipShape(Circle())
            }
            .frame(maxWidth: .infinity)
            // Wallet
            tabButton(for: .wallet)
            // Profile — user initials or image
            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    selectedTab = .profile
                }
            } label: {
                VStack(spacing: 4) {
                    Text(userInitials)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(selectedTab == .profile ? .white : TallyColors.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(selectedTab == .profile ? TallyColors.accent : TallyColors.textSecondary.opacity(0.2))
                        .clipShape(Circle())
                    Text("Profile")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(selectedTab == .profile ? TallyColors.textPrimary : TallyColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, TallySpacing.xs)
                .padding(.horizontal, 4)
                .background {
                    if selectedTab == .profile {
                        Capsule()
                            .fill(.regularMaterial)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .padding(.horizontal, TallySpacing.sm)
        .padding(.vertical, TallySpacing.xs)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.bottom, TallySpacing.xs)
    }

    private func tabButton(for tab: TallyTab) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selectedTab == tab ? tab.activeIcon : tab.icon)
                    .font(.system(size: 20, weight: .medium))
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(selectedTab == tab ? TallyColors.textPrimary : TallyColors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, TallySpacing.xs)
            .padding(.horizontal, 4)
            .background {
                if selectedTab == tab {
                    Capsule()
                        .fill(.regularMaterial)
                        .transition(.scale.combined(with: .opacity))
                }
            }
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

    /// Header opacity: starts fading at 40pt, gone by 120pt
    private var headerOpacity: Double {
        let fadeStart: CGFloat = 40
        let fadeEnd: CGFloat = 120
        if scrollOffset <= fadeStart { return 1 }
        if scrollOffset >= fadeEnd { return 0 }
        return Double(1 - (scrollOffset - fadeStart) / (fadeEnd - fadeStart))
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 56)
                    balanceRow
                    if !circles.isEmpty { circleCarousel }
                    transactionsHeader
                    transactionsList
                }
            }
            .contentMargins(.bottom, 100, for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, newValue in
                scrollOffset = newValue
            }

            // Floating header overlay
            topBar
                .allowsHitTesting(headerOpacity > 0.1)
        }
        .background(
            ZStack {
                Color.white
                VStack {
                    Spacer()
                    LinearGradient(
                        stops: [
                            .init(color: TallyColors.accent.opacity(0), location: 0),
                            .init(color: TallyColors.accent.opacity(0.02), location: 0.25),
                            .init(color: TallyColors.accent.opacity(0.06), location: 0.5),
                            .init(color: TallyColors.accent.opacity(0.12), location: 0.75),
                            .init(color: TallyColors.accent.opacity(0.18), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .containerRelativeFrame(.vertical) { h, _ in h * 0.9 }
                }
            }
            .ignoresSafeArea()
        )
    }

    // MARK: - Top Bar (floating, fades on deep scroll)

    private var topBar: some View {
        ZStack {
            Text("Mntly")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(TallyColors.textPrimary)

            HStack {
                Spacer()
                Button {} label: {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(TallyColors.textPrimary)
                        .frame(width: 44, height: 44)
                        .liquidGlass(in: Circle())
                }
            }
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.top, TallySpacing.sm)
        .padding(.bottom, TallySpacing.sm)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.9), location: 0),
                    .init(color: Color.white.opacity(0.6), location: 0.35),
                    .init(color: Color.white.opacity(0.2), location: 0.7),
                    .init(color: Color.white.opacity(0), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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

            // Right: circular liquid glass black buttons
            HStack(spacing: TallySpacing.md) {
                quickActionCircle(icon: "plus")
                quickActionCircle(icon: "arrow.up.right")
            }
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.top, TallySpacing.lg)
        .padding(.bottom, TallySpacing.xxxl)
    }

    private func quickActionCircle(icon: String) -> some View {
        Button {} label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.black)
                .clipShape(Circle())
                .glassEffect(.regular.interactive(), in: Circle())
        }
    }

    // MARK: - Circle Carousel

    private var circleCarousel: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            HStack {
                Text("YOUR CIRCLES")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TallyColors.textSecondary)
                    .tracking(0.5)
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
            Text("TRANSACTIONS")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(TallyColors.textSecondary)
                .tracking(0.5)
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
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TallyColors.textSecondary)
                        .tracking(0.3)
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.top, TallySpacing.lg)
                        .padding(.bottom, TallySpacing.sm)

                    // Elevated card container for the group
                    VStack(spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            ActivityRowView(item: item)
                            if index < group.items.count - 1 {
                                Divider()
                                    .foregroundStyle(TallyColors.borderLight)
                                    .padding(.leading, 72) // align with text after icon
                            }
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
        .shadow(color: TallyColors.hunterGreen.opacity(0.15), radius: 6, y: 3)
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
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(item.isCredit ? TallyColors.statusSuccess : TallyColors.textPrimary)
        }
        .padding(.horizontal, TallySpacing.lg)
        .padding(.vertical, TallySpacing.md)
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
