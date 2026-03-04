import SwiftUI

// MARK: - Payment Session

struct PaySession: Identifiable {
    /// Stable local ID for SwiftUI identity (always auto-generated).
    let id: UUID
    /// UUID string returned by the server. Nil for locally-created draft sessions.
    var serverId: String?
    var groupId: String
    var totalCents: Int64
    var currency: String
    var splitMethod: PaySplitMethod
    var assignmentMode: AssignmentMode
    var status: PaySessionStatus
    var merchantName: String
    var splits: [PaySplit]
    var expiresAt: Date
    var armedAt: Date?
    var transactionId: String?
    var createdAt: Date

    /// Local-only init used by sample data and previews.
    init(
        groupId: String,
        totalCents: Int64 = 0,
        currency: String = "USD",
        splitMethod: PaySplitMethod = .equal,
        merchantName: String = "",
        splits: [PaySplit] = []
    ) {
        self.id             = UUID()
        self.serverId       = nil
        self.groupId        = groupId
        self.totalCents     = totalCents
        self.currency       = currency
        self.splitMethod    = splitMethod
        self.assignmentMode = .leader
        self.status         = .draft
        self.merchantName   = merchantName
        self.splits         = splits
        self.expiresAt      = Date().addingTimeInterval(7200)
        self.armedAt        = nil
        self.transactionId  = nil
        self.createdAt      = Date()
    }

    /// Server-backed init used after a successful API create/fetch.
    init(
        serverId: String,
        groupId: String,
        totalCents: Int64,
        currency: String,
        splitMethod: PaySplitMethod,
        assignmentMode: AssignmentMode,
        status: PaySessionStatus,
        merchantName: String,
        splits: [PaySplit],
        expiresAt: Date,
        armedAt: Date?,
        transactionId: String?,
        createdAt: Date
    ) {
        self.id             = UUID()
        self.serverId       = serverId
        self.groupId        = groupId
        self.totalCents     = totalCents
        self.currency       = currency
        self.splitMethod    = splitMethod
        self.assignmentMode = assignmentMode
        self.status         = status
        self.merchantName   = merchantName
        self.splits         = splits
        self.expiresAt      = expiresAt
        self.armedAt        = armedAt
        self.transactionId  = transactionId
        self.createdAt      = createdAt
    }
}

// MARK: - Split Method

enum PaySplitMethod: String, CaseIterable, Identifiable {
    case equal, percentage, itemized
    var id: String { rawValue }

    var label: String {
        switch self {
        case .equal:      "Equal"
        case .percentage: "Percentage"
        case .itemized:   "By Items"
        }
    }

    var description: String {
        switch self {
        case .equal:      "Everyone pays the same"
        case .percentage: "Set custom %"
        case .itemized:   "Split by receipt items"
        }
    }

    var icon: String {
        switch self {
        case .equal:      "equal.circle"
        case .percentage: "percent"
        case .itemized:   "list.bullet.rectangle"
        }
    }
}

// MARK: - Assignment Mode

enum AssignmentMode: String {
    case leader, everyone
}

// MARK: - Session Status

enum PaySessionStatus: String {
    case draft, receipt, splitting, confirming, ready, completed, cancelled, expired

    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .expired: true
        default: false
        }
    }
}

// MARK: - Pay Split

struct PaySplit: Identifiable {
    let id: UUID
    var memberId: String
    var memberName: String
    var amountCents: Int64
    var tipCents: Int64
    var fundingSource: FundingSource
    var confirmed: Bool

    init(
        memberId: String,
        memberName: String,
        amountCents: Int64 = 0,
        tipCents: Int64 = 0,
        fundingSource: FundingSource = .card,
        confirmed: Bool = false
    ) {
        self.id            = UUID()
        self.memberId      = memberId
        self.memberName    = memberName
        self.amountCents   = amountCents
        self.tipCents      = tipCents
        self.fundingSource = fundingSource
        self.confirmed     = confirmed
    }
}

// MARK: - Funding Source

enum FundingSource: String, CaseIterable {
    case card, wallet

    var label: String {
        switch self {
        case .card:   "Debit Card"
        case .wallet: "Wallet"
        }
    }

    var icon: String {
        switch self {
        case .card:   "creditcard"
        case .wallet: "wallet.bifold"
        }
    }
}

// MARK: - Receipt

struct PayReceipt: Identifiable {
    let id: UUID
    var serverId: String?
    var items: [PayReceiptItem]
    var subtotalCents: Int64
    var taxCents: Int64
    var tipCents: Int64
    var totalCents: Int64
    var merchantName: String
    var receiptDate: String?
    var confidence: Double
    var warnings: [String]
    var currency: String

    var formattedTotal: String {
        CentsFormatter.format(totalCents, currency: currency)
    }

    /// Formats ISO date string (YYYY-MM-DD) into a readable display like "August 16, 2015".
    var formattedDate: String? {
        guard let raw = receiptDate, !raw.isEmpty else { return nil }
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = isoFormatter.date(from: raw) else { return raw }
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .long
        displayFormatter.timeStyle = .none
        return displayFormatter.string(from: date)
    }
}

struct PayReceiptItem: Identifiable {
    let id: UUID
    var name: String
    var quantity: Int
    var unitCents: Int64
    var totalCents: Int64
    var claimedByMemberId: String?
    var assignments: [ItemAssignment]

    init(
        name: String,
        quantity: Int = 1,
        unitCents: Int64,
        totalCents: Int64? = nil,
        claimedByMemberId: String? = nil,
        assignments: [ItemAssignment] = []
    ) {
        self.id                = UUID()
        self.name              = name
        self.quantity          = quantity
        self.unitCents         = unitCents
        self.totalCents        = totalCents ?? (Int64(quantity) * unitCents)
        self.claimedByMemberId = claimedByMemberId
        self.assignments       = assignments
    }
}

struct ItemAssignment: Identifiable {
    let id: UUID
    var memberId: String
    var memberName: String
    var numerator: Int
    var denominator: Int
    var amountCents: Int64

    init(
        memberId: String,
        memberName: String = "",
        numerator: Int = 1,
        denominator: Int = 1,
        amountCents: Int64
    ) {
        self.id          = UUID()
        self.memberId    = memberId
        self.memberName  = memberName
        self.numerator   = numerator
        self.denominator = denominator
        self.amountCents = amountCents
    }
}

// MARK: - Navigation Route

enum PayFlowRoute: Hashable {
    case receiptReview
    case splitConfig
    case leaderAssign
    case memberSelect
    case waiting
    case tipConfig
    case leaderApprove
    case cardReady
    case complete
    case walletConfirm
    case percentageSplit
}

// MARK: - Payment Method

struct PaymentMethod: Identifiable, Hashable {
    let id: String
    let kind: PaymentMethodKind
    let circleName: String?
    let groupId: String?
    let lastFour: String?

    var displayLabel: String {
        switch kind {
        case .circleCard:
            let name = circleName ?? "Circle"
            let card = lastFour.map { "•••• \($0)" } ?? "Card"
            return "\(name) \(card)"
        case .wallet:
            return "Wallet"
        }
    }

    var icon: String {
        switch kind {
        case .circleCard: "creditcard"
        case .wallet:     "wallet.bifold"
        }
    }
}

enum PaymentMethodKind: String, Hashable {
    case circleCard, wallet
}

// MARK: - Cents Formatter

enum CentsFormatter {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f
    }()

    static func format(_ cents: Int64, currency: String = "USD") -> String {
        let f = formatter
        f.currencyCode = currency
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "$0.00"
    }

    static func spoken(_ cents: Int64, currency: String = "USD") -> String {
        let dollars = cents / 100
        let remainingCents = cents % 100
        if remainingCents == 0 {
            return "\(dollars) dollars"
        }
        return "\(dollars) dollars and \(remainingCents) cents"
    }
}

// MARK: - Hashable

extension PaySession: Hashable {
    static func == (lhs: PaySession, rhs: PaySession) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension PaySplit: Hashable {
    static func == (lhs: PaySplit, rhs: PaySplit) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Sample Data

extension PaySession {
    static let sample = PaySession(
        groupId: "sample-group-id",
        totalCents: 8640,
        currency: "USD",
        splitMethod: .equal,
        merchantName: "Sushi Ro",
        splits: PaySplit.samples
    )
}

extension PaySplit {
    static let samples: [PaySplit] = [
        PaySplit(memberId: "m1", memberName: "Sarah Kim", amountCents: 2880),
        PaySplit(memberId: "m2", memberName: "Alex Chen", amountCents: 2880),
        PaySplit(memberId: "m3", memberName: "You", amountCents: 2880),
    ]
}

extension PayReceipt {
    static let sample = PayReceipt(
        id: UUID(),
        items: PayReceiptItem.samples,
        subtotalCents: 7200,
        taxCents: 540,
        tipCents: 900,
        totalCents: 8640,
        merchantName: "Sushi Ro",
        receiptDate: "2026-03-01",
        confidence: 0.92,
        warnings: [],
        currency: "USD"
    )
}

extension PayReceiptItem {
    static let samples: [PayReceiptItem] = [
        PayReceiptItem(name: "California Roll", quantity: 2, unitCents: 1200, totalCents: 2400),
        PayReceiptItem(name: "Miso Soup", quantity: 1, unitCents: 400),
        PayReceiptItem(name: "Salmon Sashimi", quantity: 1, unitCents: 1800),
        PayReceiptItem(name: "Edamame", quantity: 1, unitCents: 600),
        PayReceiptItem(name: "Green Tea", quantity: 2, unitCents: 300, totalCents: 600),
        PayReceiptItem(name: "Gyoza", quantity: 1, unitCents: 800),
    ]
}
