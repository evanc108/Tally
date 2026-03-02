import SwiftUI
import PhotosUI

// MARK: - Circle Model

struct TallyCircle: Identifiable {
    let id = UUID()
    var name: String
    var photo: UIImage?
    var members: [CircleMember]
    var splitMethod: SplitMethod
    var leaderId: UUID?
    var transactions: [CircleTransaction]
    var createdAt: Date
}

struct CircleMember: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var initial: String
    var color: Color
    var splitPercentage: Double = 0

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: CircleMember, rhs: CircleMember) -> Bool { lhs.id == rhs.id }
}

struct CircleTransaction: Identifiable {
    let id = UUID()
    var title: String
    var amount: Double
    var paidBy: String
    var emoji: String
    var status: TransactionStatus
    var date: Date
}

enum TransactionStatus {
    case settled, pending, declined

    var color: Color {
        switch self {
        case .settled: TallyColors.statusSuccess
        case .pending: TallyColors.statusPending
        case .declined: TallyColors.statusAlert
        }
    }

    var label: String {
        switch self {
        case .settled: "Settled"
        case .pending: "Pending"
        case .declined: "Declined"
        }
    }
}

// MARK: - Split Method

enum SplitMethod: String, CaseIterable, Identifiable {
    case equal = "Equal"
    case percentage = "Percentage"
    case custom = "Custom"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .equal: "Everyone pays the same"
        case .percentage: "Set custom %"
        case .custom: "Assign specific shares"
        }
    }
}

// MARK: - Navigation Route

enum CreateCircleRoute: Hashable {
    case addMembers
    case splitMethod
    case chooseLeader
    case cardIssued
    case circleReady
}

// MARK: - Flow State

@Observable
final class CreateCircleState {
    var circleName: String = ""
    var photo: UIImage?
    var photoPickerItem: PhotosPickerItem?
    var members: [CircleMember] = []
    var splitMethod: SplitMethod = .equal
    var leaderId: UUID?
    // "You" percentage is stored separately
    var youPercentage: Double = 0

    var isNameValid: Bool { !circleName.trimmingCharacters(in: .whitespaces).isEmpty }
    var hasMembersValid: Bool { members.count >= 1 }

    var totalPeople: Int { members.count + 1 }

    func initializeEqualPercentages() {
        let share = 100.0 / Double(totalPeople)
        youPercentage = share
        for i in members.indices {
            members[i].splitPercentage = share
        }
    }

    /// When member at `index` changes their percentage to `newValue`,
    /// redistribute the remainder proportionally among the others (including You).
    func updatePercentage(forMemberAt index: Int, to newValue: Double) {
        let old = members[index].splitPercentage
        let clamped = min(max(newValue, 0), 100)
        members[index].splitPercentage = clamped

        let delta = clamped - old
        if delta == 0 { return }

        // Gather all other shares (You + other members)
        var otherShares: [(isYou: Bool, index: Int, value: Double)] = []
        otherShares.append((isYou: true, index: -1, value: youPercentage))
        for (i, m) in members.enumerated() where i != index {
            otherShares.append((isYou: false, index: i, value: m.splitPercentage))
        }

        let othersTotal = otherShares.reduce(0.0) { $0 + $1.value }
        let newOthersTotal = max(othersTotal - delta, 0)

        for (j, share) in otherShares.enumerated() {
            let proportion = othersTotal > 0 ? share.value / othersTotal : 1.0 / Double(otherShares.count)
            let newVal = max(newOthersTotal * proportion, 0)
            if share.isYou {
                youPercentage = newVal
            } else {
                members[otherShares[j].index].splitPercentage = newVal
            }
        }
    }

    /// When "You" percentage changes
    func updateYouPercentage(to newValue: Double) {
        let old = youPercentage
        let clamped = min(max(newValue, 0), 100)
        youPercentage = clamped

        let delta = clamped - old
        if delta == 0 { return }

        let othersTotal = members.reduce(0.0) { $0 + $1.splitPercentage }
        let newOthersTotal = max(othersTotal - delta, 0)

        for i in members.indices {
            let proportion = othersTotal > 0 ? members[i].splitPercentage / othersTotal : 1.0 / Double(members.count)
            members[i].splitPercentage = max(newOthersTotal * proportion, 0)
        }
    }

    func reset() {
        circleName = ""
        photo = nil
        photoPickerItem = nil
        members = []
        splitMethod = .equal
        leaderId = nil
        youPercentage = 0
    }

    static func seeded() -> CreateCircleState {
        let s = CreateCircleState()
        s.members = [
            CircleMember(name: "Sarah Kim", initial: "S", color: .orange),
            CircleMember(name: "Alex Chen", initial: "A", color: .blue),
            CircleMember(name: "Jordan Park", initial: "J", color: .purple),
        ]
        return s
    }
}

// MARK: - Sample Data

extension TallyCircle {
    static let sample = TallyCircle(
        name: "Roommates",
        members: [
            CircleMember(name: "You", initial: "Y", color: TallyColors.accent),
            CircleMember(name: "Sarah", initial: "S", color: .orange),
            CircleMember(name: "Alex", initial: "A", color: .blue),
        ],
        splitMethod: .equal,
        transactions: [
            CircleTransaction(title: "Groceries", amount: 86.40, paidBy: "Sarah", emoji: "🛒", status: .settled, date: .now.addingTimeInterval(-3600)),
            CircleTransaction(title: "Electric bill", amount: 142.00, paidBy: "You", emoji: "⚡", status: .pending, date: .now.addingTimeInterval(-86400)),
            CircleTransaction(title: "Internet", amount: 65.99, paidBy: "Alex", emoji: "📡", status: .settled, date: .now.addingTimeInterval(-172800)),
        ],
        createdAt: .now.addingTimeInterval(-604800)
    )
}
