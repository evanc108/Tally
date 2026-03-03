import SwiftUI

struct AddMembersView: View {
    @Bindable var state: CreateCircleState
    var onContinue: () -> Void

    @State private var searchText = ""

    // Mock Tally users (on the platform)
    private let tallyUsers: [(name: String, username: String)] = [
        ("Alex Kim",     "@alexk"),
        ("Sarah Jones",  "@sarahj"),
        ("Mike Lee",     "@mikelee"),
    ]

    // Mock device contacts (not on Tally)
    private let deviceContacts: [String] = [
        "John Doe",
        "Amy Smith",
        "Rachel Park",
    ]

    private var filteredTallyUsers: [(name: String, username: String)] {
        guard !searchText.isEmpty else { return tallyUsers }
        return tallyUsers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.username.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredDeviceContacts: [String] {
        guard !searchText.isEmpty else { return deviceContacts }
        return deviceContacts.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func isMemberAdded(_ name: String) -> Bool {
        state.members.contains { $0.name == name }
    }

    private func initials(for name: String) -> String {
        name.split(separator: " ").map { String($0.prefix(1)) }.joined()
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Fixed header ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                // Member chips (selected members)
                if !state.members.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TallySpacing.sm) {
                            ForEach(state.members) { member in
                                MemberChipView(
                                    name: member.name,
                                    initial: member.initial,
                                    color: member.color,
                                    removable: true
                                ) {
                                    withAnimation(.spring(response: 0.3)) {
                                        state.members.removeAll { $0.id == member.id }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, TallySpacing.md)
                }

                // Search bar
                HStack(spacing: TallySpacing.md) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TallyColors.textSecondary)
                    TextField("Search contacts...", text: $searchText)
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textPrimary)
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
                .padding(.top, TallySpacing.lg)
            }
            .padding(.horizontal, TallySpacing.screenPadding)

            // ── Scrollable contact sections ─────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ON TALLY section
                    if !filteredTallyUsers.isEmpty {
                        Text("ON TALLY")
                            .font(TallyFont.smallLabel)
                            .foregroundStyle(TallyColors.textSecondary)
                            .padding(.horizontal, TallySpacing.screenPadding)
                            .padding(.top, TallySpacing.xl)
                            .padding(.bottom, TallySpacing.sm)

                        ForEach(Array(filteredTallyUsers.enumerated()), id: \.element.name) { index, user in
                            TallyUserRow(
                                name: user.name,
                                username: user.username,
                                initials: initials(for: user.name),
                                color: tallyUserColor(for: index),
                                isSelected: isMemberAdded(user.name)
                            ) {
                                toggleTallyUser(user, index: index)
                            }

                            if index < filteredTallyUsers.count - 1 {
                                Divider()
                                    .padding(.leading, TallySpacing.screenPadding + 48 + TallySpacing.md)
                            }
                        }
                    }

                    // FROM CONTACTS section
                    if !filteredDeviceContacts.isEmpty {
                        Text("FROM CONTACTS")
                            .font(TallyFont.smallLabel)
                            .foregroundStyle(TallyColors.textSecondary)
                            .padding(.horizontal, TallySpacing.screenPadding)
                            .padding(.top, TallySpacing.xl)
                            .padding(.bottom, TallySpacing.sm)

                        ForEach(Array(filteredDeviceContacts.enumerated()), id: \.element) { index, contact in
                            DeviceContactRow(
                                name: contact,
                                initials: initials(for: contact)
                            )

                            if index < filteredDeviceContacts.count - 1 {
                                Divider()
                                    .padding(.leading, TallySpacing.screenPadding + 48 + TallySpacing.md)
                            }
                        }
                    }

                    // Share invite link
                    Divider()
                        .padding(.top, TallySpacing.lg)

                    Button {} label: {
                        HStack(spacing: TallySpacing.md) {
                            Image(systemName: "link")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(TallyColors.textSecondary)
                                .frame(width: 48, height: 48)
                                .background(TallyColors.bgSecondary)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Share invite link")
                                    .font(TallyFont.bodySemibold)
                                    .foregroundStyle(TallyColors.textPrimary)
                                Text("Or share via QR code")
                                    .font(TallyFont.caption)
                                    .foregroundStyle(TallyColors.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(TallyColors.textTertiary)
                        }
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.vertical, TallySpacing.md)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, TallySpacing.xl)
            }

            // ── Pinned footer ───────────────────────────────────────────────
            VStack(spacing: 0) {
                Button("Continue", action: onContinue)
                    .buttonStyle(TallyPrimaryButtonStyle())
                    .disabled(state.members.count < 1)
                    .opacity(state.members.count >= 1 ? 1 : 0.5)
                    .padding(.top, TallySpacing.md)
                    .padding(.bottom, TallySpacing.xxxl)
            }
            .padding(.horizontal, TallySpacing.screenPadding)
        }
        .background(TallyColors.bgPrimary)
    }

    // MARK: - Actions

    private func toggleTallyUser(_ user: (name: String, username: String), index: Int) {
        withAnimation(.spring(response: 0.3)) {
            if let existingIndex = state.members.firstIndex(where: { $0.name == user.name }) {
                state.members.remove(at: existingIndex)
            } else {
                let initial = initials(for: user.name)
                let color = tallyUserColor(for: index)
                let member = CircleMember(name: user.name, initial: initial, color: color)
                state.members.append(member)
            }
        }
    }

    private func tallyUserColor(for index: Int) -> Color {
        let colors: [Color] = [.red, .purple, .green, .blue, .orange, .pink, .cyan]
        return colors[index % colors.count]
    }
}

// MARK: - Tally User Row (on platform)

private struct TallyUserRow: View {
    let name: String
    let username: String
    let initials: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TallySpacing.md) {
                // Avatar
                Text(initials)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(color)
                    .clipShape(Circle())

                // Name + username
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(TallyColors.textPrimary)
                    Text(username)
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                }

                Spacer(minLength: 0)

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(TallyColors.statusSuccess)
                } else {
                    Circle()
                        .strokeBorder(TallyColors.textTertiary, lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.vertical, TallySpacing.md)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Device Contact Row (not on Tally)

private struct DeviceContactRow: View {
    let name: String
    let initials: String

    var body: some View {
        HStack(spacing: TallySpacing.md) {
            // Avatar (muted)
            Text(initials)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TallyColors.textSecondary)
                .frame(width: 48, height: 48)
                .background(TallyColors.bgSecondary)
                .clipShape(Circle())

            Text(name)
                .font(TallyFont.bodySemibold)
                .foregroundStyle(TallyColors.textPrimary)

            Spacer(minLength: 0)

            Button {} label: {
                Text("Invite")
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.vertical, TallySpacing.md)
    }
}

// MARK: - Member Chip

private struct MemberChipView: View {
    let name: String
    let initial: String
    let color: Color
    let removable: Bool
    let onRemove: () -> Void

    private var shortName: String {
        let parts = name.split(separator: " ")
        guard let first = parts.first else { return name }
        if let last = parts.last, parts.count > 1 {
            return "\(first) \(last.prefix(1))."
        }
        return String(first)
    }

    var body: some View {
        HStack(spacing: TallySpacing.xs) {
            Text(initial)
                .font(TallyFont.smallLabel)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(color)
                .clipShape(Circle())
            Text(shortName)
                .font(TallyFont.caption)
                .fontWeight(.medium)
                .foregroundStyle(TallyColors.textPrimary)
            if removable {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TallyColors.textSecondary)
                }
            }
        }
        .padding(.leading, TallySpacing.xs)
        .padding(.trailing, TallySpacing.md)
        .padding(.vertical, TallySpacing.xs)
        .background(TallyColors.bgSecondary)
        .clipShape(Capsule())
    }
}
