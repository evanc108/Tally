//
//  ContentView.swift
//  Tally
//
//  Created by Evan Chang on 3/1/26.
//

import SwiftUI
import ClerkKit

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

    init() {
        // Hide the system tab bar globally
        UITabBar.appearance().isHidden = true

        // Nav bar: opaque with shadow, not floating/translucent
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(TallyColors.bgPrimary)
        navAppearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch selectedTab {
                case .home:
                    HomeTab()
                case .circles:
                    CirclesTab(viewModel: circlesViewModel)
                case .pay:
                    PayTab()
                case .wallet:
                    WalletTab()
                case .profile:
                    ProfileTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar
            TallyTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Custom Tab Bar

private struct TallyTabBar: View {
    @Binding var selectedTab: TallyTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TallyTab.allCases, id: \.rawValue) { tab in
                if tab == .pay {
                    // Raised center button
                    PayButton(isSelected: selectedTab == .pay) {
                        selectedTab = .pay
                    }
                } else {
                    TabBarItem(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(.horizontal, TallySpacing.sm)
        .padding(.top, TallySpacing.sm)
        .padding(.bottom, TallySpacing.xs)
        .background(
            TallyColors.bgPrimary
                .shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2))
        )
    }
}

private struct TabBarItem: View {
    let tab: TallyTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: TallySpacing.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20))
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isSelected ? TallyColors.accent : TallyColors.textSecondary)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct PayButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: TallySpacing.xs) {
                ZStack {
                    Circle()
                        .fill(TallyColors.accent)
                        .frame(width: 44, height: 44)
                    Image(systemName: "dollarsign")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .offset(y: -12)
                Text("Pay")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? TallyColors.accent : TallyColors.textSecondary)
                    .offset(y: -12)
            }
            .frame(maxWidth: .infinity)
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
    @State private var searchText = ""
    @State private var selectedFilter: ActivityFilter = .all

    private let items = ActivityItem.samples

    enum ActivityFilter: String, CaseIterable {
        case all = "All"
        case spending = "Spending"
        case income = "Income"
    }

    private var filteredItems: [ActivityItem] {
        let base: [ActivityItem]
        switch selectedFilter {
        case .all:      base = items
        case .spending: base = items.filter { !$0.isCredit }
        case .income:   base = items.filter { $0.isCredit }
        }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var groupedItems: [(label: String, items: [ActivityItem])] {
        let calendar = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"

        let grouped = Dictionary(grouping: filteredItems) { item -> String in
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    searchBar
                    balanceSection
                    transactionsHeader
                    filterChips
                    transactionsList
                }
                .padding(.bottom, 100)
            }
            .background(TallyColors.bgPrimary)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: TallySpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(TallyColors.textSecondary)
            TextField("Search activity...", text: $searchText)
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
        .padding(.top, TallySpacing.lg)
        .padding(.bottom, TallySpacing.xl)
    }

    // MARK: - Balance

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: TallySpacing.xs) {
            Text("Total Balance")
                .font(TallyFont.caption)
                .fontWeight(.semibold)
                .foregroundStyle(TallyColors.textSecondary)

            HStack(alignment: .bottom) {
                Text("$1,224.00")
                    .font(TallyFont.heroAmount)
                    .tracking(-2)
                    .foregroundStyle(TallyColors.textPrimary)

                Spacer()

                HStack(spacing: TallySpacing.sm) {
                    darkCircleButton(systemName: "plus") {}
                    darkCircleButton(systemName: "arrow.left.arrow.right") {}
                }
                .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.bottom, TallySpacing.xl)
    }

    private func darkCircleButton(systemName: String, action: @escaping () -> Void) -> some View {
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

    // MARK: - Transactions

    private var transactionsHeader: some View {
        Text("Transactions")
            .font(TallyFont.title)
            .foregroundStyle(TallyColors.textPrimary)
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.sm)
    }

    private var filterChips: some View {
        HStack(spacing: TallySpacing.sm) {
            ForEach(ActivityFilter.allCases, id: \.self) { filter in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        selectedFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(TallyFont.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(selectedFilter == filter ? .white : TallyColors.textSecondary)
                        .padding(.horizontal, TallySpacing.lg)
                        .padding(.vertical, TallySpacing.sm)
                        .background(selectedFilter == filter ? TallyColors.ink : TallyColors.bgSecondary)
                        .clipShape(Capsule())
                }
            }
            Spacer()
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
                        .fontWeight(.semibold)
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.top, TallySpacing.lg)
                        .padding(.bottom, TallySpacing.xs)

                    ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                        ActivityRowView(item: item)
                        if index < group.items.count - 1 {
                            Divider()
                                .padding(.leading, TallySpacing.screenPadding + 48 + TallySpacing.md)
                        }
                    }
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

// MARK: - Activity Row

private struct ActivityRowView: View {
    let item: ActivityItem

    var body: some View {
        HStack(spacing: TallySpacing.md) {
            ActivityIconView(icon: item.icon, size: 48)

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
    }
}

// MARK: - Activity Icon

private struct ActivityIconView: View {
    let icon: ActivityIcon
    var size: CGFloat = 48

    var body: some View {
        switch icon {
        case .category(let emoji, let background):
            Text(emoji)
                .font(.system(size: size * 0.46))
                .frame(width: size, height: size)
                .background(background)
                .clipShape(Circle())
        case .person(let initial, let color):
            Text(initial)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(color.opacity(0.15))
                .clipShape(Circle())
        }
    }
}

// MARK: - Circles Tab

private struct CirclesTab: View {
    @Bindable var viewModel: CirclesViewModel
    @State private var showCreateFlow = false
    @State private var navigationPath = NavigationPath()
    @State private var pendingCircle: TallyCircle?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading && viewModel.circles.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.circles.isEmpty {
                    emptyState
                } else {
                    CircleListView(circles: viewModel.circles)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TallyColors.bgPrimary)
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
                await viewModel.fetchCircles()
            }
            .safeAreaInset(edge: .top) {
                circlesHeader
            }
        }
    }

    // MARK: - Pinned Header

    private var circlesHeader: some View {
        HStack {
            Text("Circles")
                .font(TallyFont.largeTitle)
                .foregroundStyle(TallyColors.textPrimary)
            Spacer()
            Button { showCreateFlow = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(TallyColors.ink)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Create circle")
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.top, TallySpacing.sm)
        .padding(.bottom, TallySpacing.sm)
        .background(TallyColors.bgPrimary)
    }

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

// MARK: - Pay Tab

private struct PayTab: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: TallySpacing.lg) {
                Spacer()
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(TallyColors.textSecondary)
                Text("Pay & Request")
                    .font(TallyFont.title)
                    .foregroundStyle(TallyColors.textPrimary)
                Text("Send money or request payments from friends.")
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TallySpacing.xxl)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TallyColors.bgPrimary)
            .navigationTitle("Pay")
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
