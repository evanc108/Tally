import Foundation

// MARK: - User

/// Response from POST /v1/users/me
struct MeResponseDTO: Decodable {
    let userID: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case userID    = "user_id"
        case createdAt = "created_at"
    }
}

// MARK: - Create Circle

/// A member to create alongside the group.
struct CreateGroupMemberDTO: Encodable {
    let displayName: String
    let splitWeight: Double

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case splitWeight = "split_weight"
    }
}

/// Request body for POST /v1/groups
struct CreateCircleRequestDTO: Encodable {
    /// Slug — lowercase, hyphenated (e.g. "weekend-in-nashville")
    let name: String
    /// Human-readable label shown in the iOS UI
    let displayName: String
    let currency: String
    /// Additional members (beyond the creator) to create in the same transaction.
    let members: [CreateGroupMemberDTO]

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case currency
        case members
    }
}

/// Response from POST /v1/groups
struct CreateCircleResponseDTO: Decodable {
    let groupID: String
    let name: String
    let currency: String
    let createdAt: String
    /// The calling user's member row ID within this group
    let memberID: String

    enum CodingKeys: String, CodingKey {
        case groupID   = "group_id"
        case name
        case currency
        case createdAt = "created_at"
        case memberID  = "member_id"
    }
}

// MARK: - List Circles

/// Response from GET /v1/groups
struct ListCirclesResponseDTO: Decodable {
    let groups: [CircleSummaryDTO]
}

struct CircleSummaryDTO: Decodable {
    let groupID: String
    let name: String
    let displayName: String?
    let currency: String
    let memberCount: Int?
    let myCardLastFour: String?
    let myCardType: String?
    let createdAt: String
    let archivedAt: String?

    enum CodingKeys: String, CodingKey {
        case groupID        = "group_id"
        case name
        case displayName    = "display_name"
        case currency
        case memberCount    = "member_count"
        case myCardLastFour = "my_card_last_four"
        case myCardType     = "my_card_type"
        case createdAt      = "created_at"
        case archivedAt     = "archived_at"
    }
}

// MARK: - Group Detail

/// Response from GET /v1/groups/:id — includes full member list.
struct GroupDetailResponseDTO: Decodable {
    let groupID: String
    let name: String
    let currency: String
    let members: [GroupMemberDTO]

    enum CodingKeys: String, CodingKey {
        case groupID  = "group_id"
        case name
        case currency
        case members
    }
}

struct GroupMemberDTO: Decodable {
    let memberID: String
    let displayName: String
    let splitWeight: Double
    let tallyBalanceCents: Int64
    let isLeader: Bool
    let hasCard: Bool
    let kycStatus: String

    enum CodingKeys: String, CodingKey {
        case memberID          = "member_id"
        case displayName       = "display_name"
        case splitWeight       = "split_weight"
        case tallyBalanceCents = "tally_balance_cents"
        case isLeader          = "is_leader"
        case hasCard           = "has_card"
        case kycStatus         = "kyc_status"
    }
}

// MARK: - Transactions

/// Response from GET /v1/groups/:id/transactions
struct ListTransactionsResponseDTO: Decodable {
    let transactions: [TransactionSummaryDTO]
}

struct TransactionSummaryDTO: Decodable {
    let id: String
    let amountCents: Int64
    let currency: String
    let merchantName: String?
    let merchantCategory: String?
    let status: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case amountCents      = "amount_cents"
        case currency
        case merchantName     = "merchant_name"
        case merchantCategory = "merchant_category"
        case status
        case createdAt        = "created_at"
    }
}

extension CircleTransaction {
    /// Maps a backend transaction summary into a CircleTransaction.
    init(from dto: TransactionSummaryDTO) {
        let isoFormatter = ISO8601DateFormatter()
        self.title = dto.merchantName ?? "Payment"
        self.amount = Double(dto.amountCents) / 100.0
        self.paidBy = "Circle"
        self.emoji = Self.emojiForCategory(dto.merchantCategory)
        self.status = Self.statusFromString(dto.status)
        self.date = isoFormatter.date(from: dto.createdAt) ?? .now
    }

    private static func emojiForCategory(_ category: String?) -> String {
        guard let cat = category?.lowercased() else { return "💳" }
        if cat.contains("food") || cat.contains("restaurant") { return "🍽️" }
        if cat.contains("grocery") { return "🛒" }
        if cat.contains("transport") || cat.contains("uber") || cat.contains("lyft") { return "🚗" }
        if cat.contains("entertainment") { return "🎬" }
        if cat.contains("utility") || cat.contains("electric") { return "⚡" }
        return "💳"
    }

    private static func statusFromString(_ status: String) -> TransactionStatus {
        switch status.uppercased() {
        case "SETTLED":  return .settled
        case "DECLINED": return .declined
        default:         return .pending
        }
    }
}

// MARK: - Update Circle

/// Request body for PATCH /v1/groups/:groupID
struct UpdateCircleRequestDTO: Encodable {
    let displayName: String?
    let splitMode: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case splitMode   = "split_mode"
    }
}

// MARK: - Archive Circle

/// Response from DELETE /v1/groups/:groupID
struct ArchiveCircleResponseDTO: Decodable {
    let groupID: String
    let archivedAt: String

    enum CodingKeys: String, CodingKey {
        case groupID    = "group_id"
        case archivedAt = "archived_at"
    }
}
