import Foundation

// MARK: - Receipt DTOs

/// Request body for POST /v1/groups/:groupID/receipts
struct SaveReceiptRequestDTO: Encodable {
    let subtotalCents: Int64
    let taxCents: Int64
    let tipCents: Int64
    let totalCents: Int64
    let currency: String
    let merchantName: String
    let items: [ReceiptItemDTO]

    enum CodingKeys: String, CodingKey {
        case subtotalCents = "subtotal_cents"
        case taxCents      = "tax_cents"
        case tipCents      = "tip_cents"
        case totalCents    = "total_cents"
        case currency
        case merchantName  = "merchant_name"
        case items
    }
}

struct ReceiptItemDTO: Codable {
    let name: String
    let quantity: Int
    let unitCents: Int64
    let totalCents: Int64

    enum CodingKeys: String, CodingKey {
        case name, quantity
        case unitCents  = "unit_cents"
        case totalCents = "total_cents"
    }
}

/// Response from receipt endpoints
struct ReceiptResponseDTO: Decodable {
    let id: String
    let subtotalCents: Int64
    let taxCents: Int64
    let tipCents: Int64
    let totalCents: Int64
    let currency: String
    let merchantName: String?
    let confidence: Double?
    let warnings: [String]?
    let status: String
    let items: [ReceiptItemResponseDTO]
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case subtotalCents = "subtotal_cents"
        case taxCents      = "tax_cents"
        case tipCents      = "tip_cents"
        case totalCents    = "total_cents"
        case currency
        case merchantName  = "merchant_name"
        case confidence, warnings, status, items
        case createdAt     = "created_at"
    }
}

struct ReceiptItemResponseDTO: Decodable {
    let id: String
    let name: String
    let quantity: Int
    let unitCents: Int64
    let totalCents: Int64
    let claimedByMemberId: String?
    let claimedAt: String?
    let claimExpiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, quantity
        case unitCents         = "unit_cents"
        case totalCents        = "total_cents"
        case claimedByMemberId = "claimed_by_member_id"
        case claimedAt         = "claimed_at"
        case claimExpiresAt    = "claim_expires_at"
    }
}

// MARK: - Receipt Parse DTOs (POST /v1/receipts/parse)

/// Wraps the parse endpoint response: `{ data: ParsedReceiptDataDTO, meta: ... }`
struct ParseReceiptResponseDTO: Decodable {
    let data: ParsedReceiptDataDTO?
    let meta: ParseReceiptMetaDTO?
}

struct ParseReceiptMetaDTO: Decodable {
    let requestId: String?
    let timestamp: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case timestamp
    }
}

struct ParsedReceiptDataDTO: Decodable {
    let items: [ParsedReceiptItemDTO]
    let subtotalCents: Int64?
    let taxCents: Int64?
    let tipCents: Int64?
    let totalCents: Int64?
    let merchantName: String?
    let receiptDate: String?
    let confidence: Double
    let warnings: [String]?

    enum CodingKeys: String, CodingKey {
        case items
        case subtotalCents = "subtotal_cents"
        case taxCents      = "tax_cents"
        case tipCents      = "tip_cents"
        case totalCents    = "total_cents"
        case merchantName  = "merchant_name"
        case receiptDate   = "receipt_date"
        case confidence
        case warnings
    }
}

struct ParsedReceiptItemDTO: Decodable {
    let name: String
    let quantity: Int
    let unitCents: Int64
    let totalCents: Int64

    enum CodingKeys: String, CodingKey {
        case name, quantity
        case unitCents  = "unit_cents"
        case totalCents = "total_cents"
    }
}

extension PayReceipt {
    /// Maps the parsed receipt data from the parse endpoint into a PayReceipt domain model.
    /// Computes a fallback total from items + tax + tip if the backend total is nil/zero.
    private static var todayISO: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    init(fromParsed dto: ParsedReceiptDataDTO) {
        self.id            = UUID()
        self.serverId      = nil
        self.tipCents      = dto.tipCents ?? 0
        self.currency      = "USD"
        self.merchantName  = dto.merchantName ?? ""
        self.receiptDate   = (dto.receiptDate?.isEmpty == false) ? dto.receiptDate : Self.todayISO
        self.confidence    = dto.confidence
        self.warnings      = dto.warnings ?? []
        self.items         = dto.items.map { item in
            PayReceiptItem(
                name: item.name,
                quantity: item.quantity,
                unitCents: item.unitCents,
                totalCents: item.totalCents
            )
        }

        // Use explicit subtotal or compute from items
        let itemSum = self.items.reduce(Int64(0)) { $0 + $1.totalCents }
        self.subtotalCents = dto.subtotalCents ?? itemSum

        // Use explicit total or compute from subtotal + tax + tip
        if let total = dto.totalCents, total > 0 {
            self.totalCents = total
            // Derive tax from total when available — more reliable than parser's
            // tax value since parsers often miss multi-line taxes (e.g. TIF + HST).
            let derived = self.totalCents - self.subtotalCents - self.tipCents
            self.taxCents = derived > 0 ? derived : (dto.taxCents ?? 0)
        } else {
            self.taxCents = dto.taxCents ?? 0
            self.totalCents = self.subtotalCents + self.taxCents + self.tipCents
        }
    }
}

extension PayReceipt {
    /// Maps on-device Apple Intelligence output into a PayReceipt domain model.
    init(fromOnDevice output: ParsedReceiptOutput) {
        self.id            = UUID()
        self.serverId      = nil
        self.tipCents      = Int64(output.tipCents ?? 0)
        self.currency      = "USD"
        self.merchantName  = output.merchantName ?? ""
        self.receiptDate   = (output.receiptDate?.isEmpty == false) ? output.receiptDate : Self.todayISO
        self.confidence    = 1.0
        self.warnings      = []
        self.items         = output.items.map { item in
            PayReceiptItem(
                name: item.name,
                quantity: item.quantity,
                unitCents: Int64(item.unitCents),
                totalCents: Int64(item.totalCents)
            )
        }

        let itemSum = self.items.reduce(Int64(0)) { $0 + $1.totalCents }
        self.subtotalCents = Int64(output.subtotalCents ?? 0)
        if self.subtotalCents == 0 { self.subtotalCents = itemSum }

        if let total = output.totalCents, total > 0 {
            self.totalCents = Int64(total)
            // Derive tax from total when available — more reliable than parser's
            // tax value since parsers often miss multi-line taxes (e.g. TIF + HST).
            let derived = self.totalCents - self.subtotalCents - self.tipCents
            self.taxCents = derived > 0 ? derived : Int64(output.taxCents ?? 0)
        } else {
            self.taxCents = Int64(output.taxCents ?? 0)
            self.totalCents = self.subtotalCents + self.taxCents + self.tipCents
        }
    }
}

// MARK: - Session DTOs

/// Request body for POST /v1/groups/:groupID/sessions
struct CreateSessionRequestDTO: Encodable {
    let totalCents: Int64
    let currency: String
    let splitMethod: String
    let merchantName: String
    let assignmentMode: String?

    enum CodingKeys: String, CodingKey {
        case totalCents     = "total_cents"
        case currency
        case splitMethod    = "split_method"
        case merchantName   = "merchant_name"
        case assignmentMode = "assignment_mode"
    }
}

/// Response from session endpoints
struct SessionResponseDTO: Decodable {
    let id: String
    let groupId: String
    let totalCents: Int64
    let currency: String
    let splitMethod: String
    let assignmentMode: String
    let status: String
    let merchantName: String?
    let armedAt: String?
    let expiresAt: String
    let transactionId: String?
    let createdAt: String
    let splits: [SplitResponseDTO]?

    enum CodingKeys: String, CodingKey {
        case id
        case groupId        = "group_id"
        case totalCents     = "total_cents"
        case currency
        case splitMethod    = "split_method"
        case assignmentMode = "assignment_mode"
        case status
        case merchantName   = "merchant_name"
        case armedAt        = "armed_at"
        case expiresAt      = "expires_at"
        case transactionId  = "transaction_id"
        case createdAt      = "created_at"
        case splits
    }
}

struct SplitResponseDTO: Decodable {
    let memberId: String
    let displayName: String
    let amountCents: Int64
    let tipCents: Int64
    let fundingSource: String
    let confirmed: Bool

    enum CodingKeys: String, CodingKey {
        case memberId      = "member_id"
        case displayName   = "display_name"
        case amountCents   = "amount_cents"
        case tipCents      = "tip_cents"
        case fundingSource = "funding_source"
        case confirmed
    }
}

/// Request body for PUT /v1/groups/:groupID/sessions/:sessionID/splits
struct SetSplitsRequestDTO: Encodable {
    let splits: [SplitInputDTO]
}

struct SplitInputDTO: Encodable {
    let memberId: String
    let amountCents: Int64
    let tipCents: Int64
    let fundingSource: String

    enum CodingKeys: String, CodingKey {
        case memberId      = "member_id"
        case amountCents   = "amount_cents"
        case tipCents      = "tip_cents"
        case fundingSource = "funding_source"
    }
}

/// Request body for PATCH /v1/groups/:groupID/sessions/:sessionID
struct UpdateSessionRequestDTO: Encodable {
    let totalCents: Int64?
    let merchantName: String?
    let status: String?
    let splitMethod: String?
    let assignmentMode: String?

    enum CodingKeys: String, CodingKey {
        case totalCents     = "total_cents"
        case merchantName   = "merchant_name"
        case status
        case splitMethod    = "split_method"
        case assignmentMode = "assignment_mode"
    }
}

/// Response from POST /v1/groups/:groupID/sessions/:sessionID/simulate-tap
struct SimulateTapResponseDTO: Decodable {
    let decision: String
    let transactionId: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case decision
        case transactionId = "transaction_id"
        case reason
    }
}

// MARK: - Assignment DTOs

/// Request body for PUT /v1/groups/:groupID/sessions/:sessionID/assignments
struct AssignItemsRequestDTO: Encodable {
    let assignments: [AssignmentInputDTO]
}

struct AssignmentInputDTO: Encodable {
    let itemId: String
    let memberId: String
    let quantityNumerator: Int
    let quantityDenominator: Int
    let amountCents: Int64

    enum CodingKeys: String, CodingKey {
        case itemId              = "item_id"
        case memberId            = "member_id"
        case quantityNumerator   = "quantity_numerator"
        case quantityDenominator = "quantity_denominator"
        case amountCents         = "amount_cents"
    }
}

/// Response from confirmation endpoints
struct ConfirmationDTO: Decodable {
    let memberId: String
    let displayName: String
    let confirmed: Bool
    let confirmedAt: String?

    enum CodingKeys: String, CodingKey {
        case memberId    = "member_id"
        case displayName = "display_name"
        case confirmed
        case confirmedAt = "confirmed_at"
    }
}

// MARK: - DTO Mapping

extension PaySession {
    /// Maps a session response DTO into a PaySession domain model.
    init(from dto: SessionResponseDTO) {
        let isoFormatter = ISO8601DateFormatter()
        self.init(
            serverId: dto.id,
            groupId: dto.groupId,
            totalCents: dto.totalCents,
            currency: dto.currency,
            splitMethod: PaySplitMethod(rawValue: dto.splitMethod) ?? .equal,
            assignmentMode: AssignmentMode(rawValue: dto.assignmentMode) ?? .leader,
            status: PaySessionStatus(rawValue: dto.status) ?? .draft,
            merchantName: dto.merchantName ?? "",
            splits: dto.splits?.map { PaySplit(from: $0) } ?? [],
            expiresAt: isoFormatter.date(from: dto.expiresAt) ?? Date().addingTimeInterval(7200),
            armedAt: dto.armedAt.flatMap { isoFormatter.date(from: $0) },
            transactionId: dto.transactionId,
            createdAt: isoFormatter.date(from: dto.createdAt) ?? .now
        )
    }
}

extension PaySplit {
    /// Maps a split response DTO into a PaySplit domain model.
    init(from dto: SplitResponseDTO) {
        self.init(
            memberId: dto.memberId,
            memberName: dto.displayName,
            amountCents: dto.amountCents,
            tipCents: dto.tipCents,
            fundingSource: FundingSource(rawValue: dto.fundingSource) ?? .card,
            confirmed: dto.confirmed
        )
    }
}

extension PayReceipt {
    /// Maps a receipt response DTO into a PayReceipt domain model.
    init(from dto: ReceiptResponseDTO) {
        self.id            = UUID()
        self.serverId      = dto.id
        self.subtotalCents = dto.subtotalCents
        self.taxCents      = dto.taxCents
        self.tipCents      = dto.tipCents
        self.totalCents    = dto.totalCents
        self.currency      = dto.currency
        self.merchantName  = dto.merchantName ?? ""
        self.receiptDate   = nil
        self.confidence    = dto.confidence ?? 1.0
        self.warnings      = dto.warnings ?? []
        self.items         = dto.items.map { item in
            PayReceiptItem(
                name: item.name,
                quantity: item.quantity,
                unitCents: item.unitCents,
                totalCents: item.totalCents,
                claimedByMemberId: item.claimedByMemberId
            )
        }
    }
}
