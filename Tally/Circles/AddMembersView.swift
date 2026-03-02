import SwiftUI

struct AddMembersView: View {
    @Bindable var state: CreateCircleState
    var onContinue: () -> Void

    @State private var searchText = ""

    private let contacts: [(name: String, phone: String)] = [
        ("Alex Chen", "(555) 111-2222"),
        ("Sarah Kim", "(555) 333-4444"),
        ("Mike Johnson", "(555) 555-6666"),
        ("Emily Davis", "(555) 777-8888"),
        ("Chris Lee", "(555) 999-0000"),
        ("Jordan Park", "(555) 222-3333"),
    ]

    private var filteredContacts: [(name: String, phone: String)] {
        let addedNames = Set(state.members.map(\.name))
        return contacts.filter { contact in
            !addedNames.contains(contact.name) &&
            (searchText.isEmpty ||
             contact.name.localizedCaseInsensitiveContains(searchText) ||
             contact.phone.contains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Title
                    Text("Who's in?")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.sm)

                    // Search
                    HStack(spacing: TallySpacing.md) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18))
                            .foregroundStyle(TallyColors.textSecondary)
                        TextField("Search by name or phone", text: $searchText)
                            .font(.system(size: 16))
                            .foregroundStyle(TallyColors.textPrimary)
                    }
                    .padding(.horizontal, TallySpacing.lg)
                    .frame(height: 48)
                    .background(TallyColors.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.top, TallySpacing.xl)

                    // Member chips
                    FlowLayout(spacing: 8) {
                        MemberChipView(name: "You", initial: "Y", color: TallyColors.accent, removable: false, onRemove: {})
                        ForEach(state.members) { member in
                            MemberChipView(name: member.name, initial: member.initial, color: member.color, removable: true) {
                                withAnimation(.spring(response: 0.3)) {
                                    state.members.removeAll { $0.id == member.id }
                                }
                            }
                        }
                    }
                    .padding(.top, TallySpacing.lg)

                    // People count
                    Text("\(state.members.count + 1) \(state.members.count + 1 == 1 ? "person" : "people")")
                        .font(.system(size: 14))
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(.top, TallySpacing.md)

                    // Contacts list — bigger cards
                    VStack(spacing: TallySpacing.sm) {
                        ForEach(filteredContacts, id: \.name) { contact in
                            Button {
                                addContact(contact)
                            } label: {
                                ContactCard(contact: contact)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, TallySpacing.xl)

                    // Share invite link
                    Button {} label: {
                        HStack(spacing: TallySpacing.sm) {
                            Image(systemName: "link")
                                .font(.system(size: 16))
                            Text("Share invite link")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundStyle(TallyColors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, TallySpacing.lg)
                    }
                    .padding(.top, TallySpacing.sm)
                }
                .padding(.horizontal, TallySpacing.screenPadding)
            }

            // Continue button
            Button("Continue", action: onContinue)
                .buttonStyle(TallyPrimaryButtonStyle())
                .disabled(state.members.count < 1)
                .opacity(state.members.count >= 1 ? 1 : 0.5)
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
    }

    private func addContact(_ contact: (name: String, phone: String)) {
        let initial = String(contact.name.prefix(1)).uppercased()
        let colors: [Color] = [.orange, .blue, .pink, .purple, .cyan, .mint, .indigo, .brown]
        let color = colors[state.members.count % colors.count]
        let member = CircleMember(name: contact.name, initial: initial, color: color)
        withAnimation(.spring(response: 0.3)) {
            state.members.append(member)
        }
    }
}

// MARK: - Contact Card (bigger)

private struct ContactCard: View {
    let contact: (name: String, phone: String)

    private var initials: String {
        contact.name.split(separator: " ").map { String($0.prefix(1)) }.joined()
    }

    var body: some View {
        HStack(spacing: TallySpacing.lg) {
            // Large gradient avatar
            Text(initials)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: [TallyColors.accent, TallyColors.statusSocial],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(TallyColors.textPrimary)
                Text(contact.phone)
                    .font(.system(size: 14))
                    .foregroundStyle(TallyColors.textSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, TallySpacing.lg)
        .padding(.vertical, TallySpacing.md)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TallyColors.divider).frame(height: 0.5)
        }
    }
}

// MARK: - Member Chip

private struct MemberChipView: View {
    let name: String
    let initial: String
    let color: Color
    let removable: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(initial)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(color)
                .clipShape(Circle())
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(TallyColors.textPrimary)
            if removable {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TallyColors.textSecondary)
                }
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .background(TallyColors.bgSecondary)
        .clipShape(Capsule())
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }
        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
