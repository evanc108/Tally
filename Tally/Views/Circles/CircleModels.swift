import SwiftUI
import PhotosUI

// MARK: - Circle Model

struct TallyCircle: Identifiable {
    /// Stable local ID for SwiftUI identity (always auto-generated).
    let id: UUID
    /// UUID string returned by the server. Nil for locally-created draft circles.
    var serverId: String?
    var name: String
    var photo: UIImage?
    var members: [CircleMember]
    /// Server-reported member count (includes "You"). Falls back to local members + 1.
    var serverMemberCount: Int?
    var splitMethod: SplitMethod
    var leaderId: UUID?
    var transactions: [CircleTransaction]
    var walletBalance: Double
    var myCardLastFour: String?
    var myCardType: String?
    var archivedAt: Date?
    var createdAt: Date

    /// Whether this circle has been archived (soft-deleted).
    var isArchived: Bool { archivedAt != nil }

    /// Authoritative member count — prefers server value over local.
    var memberCount: Int {
        serverMemberCount ?? (members.count + 1)
    }

    /// Local-only init used by sample data and previews.
    init(
        name: String,
        members: [CircleMember],
        splitMethod: SplitMethod,
        leaderId: UUID? = nil,
        transactions: [CircleTransaction],
        walletBalance: Double = 0,
        createdAt: Date
    ) {
        self.id                = UUID()
        self.serverId          = nil
        self.name              = name
        self.members           = members
        self.serverMemberCount = nil
        self.splitMethod       = splitMethod
        self.leaderId          = leaderId
        self.transactions      = transactions
        self.walletBalance     = walletBalance
        self.createdAt         = createdAt
    }

    /// Server-backed init used after a successful API create/fetch.
    init(
        serverId: String,
        name: String,
        members: [CircleMember],
        serverMemberCount: Int? = nil,
        splitMethod: SplitMethod,
        leaderId: UUID? = nil,
        transactions: [CircleTransaction],
        walletBalance: Double = 0,
        myCardLastFour: String? = nil,
        myCardType: String? = nil,
        archivedAt: Date? = nil,
        createdAt: Date
    ) {
        self.id                = UUID()
        self.serverId          = serverId
        self.name              = name
        self.members           = members
        self.serverMemberCount = serverMemberCount
        self.splitMethod       = splitMethod
        self.leaderId          = leaderId
        self.transactions      = transactions
        self.walletBalance     = walletBalance
        self.myCardLastFour    = myCardLastFour
        self.myCardType        = myCardType
        self.archivedAt        = archivedAt
        self.createdAt         = createdAt
    }
}

extension TallyCircle {
    /// Maps a summary DTO from GET /v1/groups into a TallyCircle.
    init(from dto: CircleSummaryDTO) {
        let isoFormatter = ISO8601DateFormatter()
        self.init(
            serverId: dto.groupID,
            name: dto.displayName ?? dto.name,
            members: [],
            serverMemberCount: dto.memberCount,
            splitMethod: .equal,
            transactions: [],
            myCardLastFour: dto.myCardLastFour,
            myCardType: dto.myCardType,
            archivedAt: dto.archivedAt.flatMap { isoFormatter.date(from: $0) },
            createdAt: isoFormatter.date(from: dto.createdAt) ?? .now
        )
    }
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
        let base = Int(100 / totalPeople)
        let remainder = 100 - base * totalPeople
        // "You" gets the first slot for remainder distribution
        youPercentage = Double(base + (0 < remainder ? 1 : 0))
        for i in members.indices {
            members[i].splitPercentage = Double(base + ((i + 1) < remainder ? 1 : 0))
        }
    }

    /// When member at `index` changes their percentage to `newValue`,
    /// redistribute the remainder proportionally among the others (including You).
    func updatePercentage(forMemberAt index: Int, to newValue: Double) {
        let old = members[index].splitPercentage
        let clamped = min(max(newValue.rounded(), 0), 100)
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

        // Distribute with rounding, then fix remainder on the largest share
        var newValues = otherShares.map { share -> Double in
            let proportion = othersTotal > 0 ? share.value / othersTotal : 1.0 / Double(otherShares.count)
            return max((newOthersTotal * proportion).rounded(), 0)
        }
        let roundedSum = newValues.reduce(0.0, +)
        let diff = newOthersTotal - roundedSum
        if diff != 0, let maxIdx = newValues.indices.max(by: { newValues[$0] < newValues[$1] }) {
            newValues[maxIdx] += diff
        }

        for (j, share) in otherShares.enumerated() {
            if share.isYou {
                youPercentage = newValues[j]
            } else {
                members[otherShares[j].index].splitPercentage = newValues[j]
            }
        }
    }

    /// When "You" percentage changes
    func updateYouPercentage(to newValue: Double) {
        let old = youPercentage
        let clamped = min(max(newValue.rounded(), 0), 100)
        youPercentage = clamped

        let delta = clamped - old
        if delta == 0 { return }

        let othersTotal = members.reduce(0.0) { $0 + $1.splitPercentage }
        let newOthersTotal = max(othersTotal - delta, 0)

        var newValues = members.indices.map { i -> Double in
            let proportion = othersTotal > 0 ? members[i].splitPercentage / othersTotal : 1.0 / Double(members.count)
            return max((newOthersTotal * proportion).rounded(), 0)
        }
        let roundedSum = newValues.reduce(0.0, +)
        let diff = newOthersTotal - roundedSum
        if diff != 0, let maxIdx = newValues.indices.max(by: { newValues[$0] < newValues[$1] }) {
            newValues[maxIdx] += diff
        }

        for i in members.indices {
            members[i].splitPercentage = newValues[i]
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

// MARK: - Hashable

extension TallyCircle: Hashable {
    static func == (lhs: TallyCircle, rhs: TallyCircle) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Sample Data

extension TallyCircle {
    static let sample = TallyCircle(
        name: "Roommates",
        members: [
            CircleMember(name: "Sarah Kim", initial: "S", color: .orange),
            CircleMember(name: "Alex Chen", initial: "A", color: .blue),
        ],
        splitMethod: .equal,
        transactions: [
            CircleTransaction(title: "Groceries", amount: 86.40, paidBy: "Sarah", emoji: "🛒", status: .settled, date: .now.addingTimeInterval(-3600)),
            CircleTransaction(title: "Electric bill", amount: 142.00, paidBy: "You", emoji: "⚡", status: .pending, date: .now.addingTimeInterval(-86400)),
            CircleTransaction(title: "Internet", amount: 65.99, paidBy: "Alex", emoji: "📡", status: .settled, date: .now.addingTimeInterval(-172800)),
        ],
        walletBalance: 320.00,
        createdAt: .now.addingTimeInterval(-604800)
    )

    static let samples: [TallyCircle] = [
        TallyCircle.sample,
        TallyCircle(
            name: "Ski Trip",
            members: [
                CircleMember(name: "Jordan Park", initial: "J", color: .purple),
                CircleMember(name: "Mike Lee", initial: "M", color: .cyan),
                CircleMember(name: "Emily Davis", initial: "E", color: .pink),
            ],
            splitMethod: .equal,
            transactions: [
                CircleTransaction(title: "Lift Tickets", amount: 320.00, paidBy: "You", emoji: "🎿", status: .settled, date: .now.addingTimeInterval(-86400 * 3)),
                CircleTransaction(title: "Lodge", amount: 480.00, paidBy: "Jordan", emoji: "🏔️", status: .pending, date: .now.addingTimeInterval(-86400 * 4)),
            ],
            walletBalance: 800.00,
            createdAt: .now.addingTimeInterval(-86400 * 5)
        ),
        TallyCircle(
            name: "Monthly Bills",
            members: [
                CircleMember(name: "Sarah Kim", initial: "S", color: .orange),
            ],
            splitMethod: .percentage,
            transactions: [
                CircleTransaction(title: "Internet", amount: 65.99, paidBy: "You", emoji: "📡", status: .settled, date: .now.addingTimeInterval(-86400 * 2)),
                CircleTransaction(title: "Electric", amount: 142.00, paidBy: "Sarah", emoji: "⚡", status: .pending, date: .now),
            ],
            walletBalance: 250.00,
            createdAt: .now.addingTimeInterval(-86400 * 30)
        ),
    ]
}
