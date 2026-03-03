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

/// Request body for POST /v1/groups
struct CreateCircleRequestDTO: Encodable {
    /// Slug — lowercase, hyphenated (e.g. "weekend-in-nashville")
    let name: String
    /// Human-readable label shown in the iOS UI
    let displayName: String
    let currency: String

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case currency
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
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case groupID     = "group_id"
        case name
        case displayName = "display_name"
        case currency
        case createdAt   = "created_at"
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
