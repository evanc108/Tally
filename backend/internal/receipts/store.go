package receipts

import (
	"database/sql"
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// StoreHandler handles receipt persistence and item assignment routes.
type StoreHandler struct {
	db *sql.DB
}

// NewStoreHandler returns a StoreHandler backed by the given database.
func NewStoreHandler(db *sql.DB) *StoreHandler {
	return &StoreHandler{db: db}
}

// ── Request / response types (unexported) ────────────────────────────────────

type saveReceiptItemRequest struct {
	Name       string `json:"name"        binding:"required"`
	Quantity   int    `json:"quantity"`
	UnitCents  int64  `json:"unit_cents"`
	TotalCents int64  `json:"total_cents"`
}

type saveReceiptRequest struct {
	SubtotalCents int64                    `json:"subtotal_cents"`
	TaxCents      int64                    `json:"tax_cents"`
	TipCents      int64                    `json:"tip_cents"`
	TotalCents    int64                    `json:"total_cents"`
	Currency      string                   `json:"currency"`
	MerchantName  string                   `json:"merchant_name"`
	RawText       string                   `json:"raw_text"`
	Items         []saveReceiptItemRequest `json:"items" binding:"required,dive"`
}

type saveReceiptItemResponse struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Quantity   int    `json:"quantity"`
	UnitCents  int64  `json:"unit_cents"`
	TotalCents int64  `json:"total_cents"`
	SortOrder  int    `json:"sort_order"`
}

type saveReceiptResponse struct {
	ID            string                    `json:"id"`
	GroupID       string                    `json:"group_id"`
	SubtotalCents int64                     `json:"subtotal_cents"`
	TaxCents      int64                     `json:"tax_cents"`
	TipCents      int64                     `json:"tip_cents"`
	TotalCents    int64                     `json:"total_cents"`
	Currency      string                    `json:"currency"`
	MerchantName  string                    `json:"merchant_name"`
	Status        string                    `json:"status"`
	Items         []saveReceiptItemResponse `json:"items"`
	CreatedAt     string                    `json:"created_at"`
}

type itemAssignmentResponse struct {
	ID                   string  `json:"id"`
	MemberID             string  `json:"member_id"`
	QuantityNumerator    int     `json:"quantity_numerator"`
	QuantityDenominator  int     `json:"quantity_denominator"`
	AmountCents          int64   `json:"amount_cents"`
}

type getReceiptItemResponse struct {
	ID                 string                   `json:"id"`
	Name               string                   `json:"name"`
	Quantity           int                      `json:"quantity"`
	UnitCents          int64                    `json:"unit_cents"`
	TotalCents         int64                    `json:"total_cents"`
	SortOrder          int                      `json:"sort_order"`
	IsFullyAssigned    bool                     `json:"is_fully_assigned"`
	ClaimedByMemberID  *string                  `json:"claimed_by_member_id"`
	ClaimedAt          *string                  `json:"claimed_at"`
	ClaimExpiresAt     *string                  `json:"claim_expires_at"`
	Assignments        []itemAssignmentResponse `json:"assignments"`
}

type getReceiptResponse struct {
	ID            string                   `json:"id"`
	GroupID       string                   `json:"group_id"`
	SubtotalCents int64                    `json:"subtotal_cents"`
	TaxCents      int64                    `json:"tax_cents"`
	TipCents      int64                    `json:"tip_cents"`
	TotalCents    int64                    `json:"total_cents"`
	Currency      string                   `json:"currency"`
	MerchantName  string                   `json:"merchant_name"`
	Status        string                   `json:"status"`
	RawText       string                   `json:"raw_text"`
	Items         []getReceiptItemResponse `json:"items"`
	CreatedAt     string                   `json:"created_at"`
	UpdatedAt     string                   `json:"updated_at"`
}

type claimItemResponse struct {
	ID                 string  `json:"id"`
	ReceiptID          string  `json:"receipt_id"`
	Name               string  `json:"name"`
	Quantity           int     `json:"quantity"`
	UnitCents          int64   `json:"unit_cents"`
	TotalCents         int64   `json:"total_cents"`
	ClaimedByMemberID  *string `json:"claimed_by_member_id"`
	ClaimedAt          *string `json:"claimed_at"`
	ClaimExpiresAt     *string `json:"claim_expires_at"`
}

type assignmentEntry struct {
	ItemID              string `json:"item_id"              binding:"required"`
	MemberID            string `json:"member_id"            binding:"required"`
	QuantityNumerator   int    `json:"quantity_numerator"   binding:"required"`
	QuantityDenominator int    `json:"quantity_denominator" binding:"required"`
	AmountCents         int64  `json:"amount_cents"`
}

type assignItemsRequest struct {
	Assignments []assignmentEntry `json:"assignments" binding:"required,dive"`
}

type assignItemsResponse struct {
	Assigned int `json:"assigned"`
}

type confirmationMember struct {
	MemberID    string `json:"member_id"`
	DisplayName string `json:"display_name"`
	Confirmed   bool   `json:"confirmed"`
}

type confirmationsResponse struct {
	Confirmations []confirmationMember `json:"confirmations"`
}

// ── POST /v1/groups/:id/receipts ─────────────────────────────────────────────

// SaveReceipt persists a parsed receipt and its items to the database.
func (h *StoreHandler) SaveReceipt(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}

	memberID, ok := c.Get("member_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	mid, ok := memberID.(uuid.UUID)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req saveReceiptRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	currency := req.Currency
	if currency == "" {
		currency = "USD"
	}

	receiptID := uuid.New()

	tx, err := h.db.BeginTx(c.Request.Context(), nil)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "begin tx failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer tx.Rollback()

	// Look up the user_id for this member so we can populate created_by_user_id.
	var createdByUserID string
	if err := tx.QueryRowContext(c.Request.Context(),
		`SELECT user_id FROM members WHERE id = $1`, mid,
	).Scan(&createdByUserID); err != nil {
		slog.ErrorContext(c.Request.Context(), "lookup member user_id failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	var createdAt time.Time
	if err := tx.QueryRowContext(c.Request.Context(), `
		INSERT INTO receipts (id, group_id, created_by_user_id, subtotal_cents, tax_cents, tip_cents, total_cents, currency, merchant_name, status, raw_text)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'draft', $10)
		RETURNING created_at`,
		receiptID, groupID, createdByUserID,
		req.SubtotalCents, req.TaxCents, req.TipCents, req.TotalCents,
		currency, req.MerchantName, req.RawText,
	).Scan(&createdAt); err != nil {
		slog.ErrorContext(c.Request.Context(), "insert receipt failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	items := make([]saveReceiptItemResponse, 0, len(req.Items))
	for i, item := range req.Items {
		itemID := uuid.New()
		quantity := item.Quantity
		if quantity <= 0 {
			quantity = 1
		}
		if _, err := tx.ExecContext(c.Request.Context(), `
			INSERT INTO receipt_items (id, receipt_id, name, quantity, unit_cents, total_cents, sort_order)
			VALUES ($1, $2, $3, $4, $5, $6, $7)`,
			itemID, receiptID, item.Name, quantity, item.UnitCents, item.TotalCents, i,
		); err != nil {
			slog.ErrorContext(c.Request.Context(), "insert receipt item failed", "error", err, "sort_order", i)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
			return
		}
		items = append(items, saveReceiptItemResponse{
			ID:         itemID.String(),
			Name:       item.Name,
			Quantity:   quantity,
			UnitCents:  item.UnitCents,
			TotalCents: item.TotalCents,
			SortOrder:  i,
		})
	}

	if err := tx.Commit(); err != nil {
		slog.ErrorContext(c.Request.Context(), "commit failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit failed"})
		return
	}

	slog.InfoContext(c.Request.Context(), "receipt saved", "receipt_id", receiptID, "group_id", groupID, "items", len(items))
	c.JSON(http.StatusCreated, saveReceiptResponse{
		ID:            receiptID.String(),
		GroupID:       groupID.String(),
		SubtotalCents: req.SubtotalCents,
		TaxCents:      req.TaxCents,
		TipCents:      req.TipCents,
		TotalCents:    req.TotalCents,
		Currency:      currency,
		MerchantName:  req.MerchantName,
		Status:        "draft",
		Items:         items,
		CreatedAt:     createdAt.UTC().Format(time.RFC3339),
	})
}

// ── GET /v1/groups/:id/receipts/:receiptId ───────────────────────────────────

// GetReceipt returns a receipt with all items, claim state, and assignments.
func (h *StoreHandler) GetReceipt(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	receiptID, err := uuid.Parse(c.Param("receiptId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid receipt_id"})
		return
	}

	var resp getReceiptResponse
	var merchantName, rawText sql.NullString
	var createdAt, updatedAt time.Time
	err = h.db.QueryRowContext(c.Request.Context(), `
		SELECT id, group_id, COALESCE(subtotal_cents, 0), COALESCE(tax_cents, 0),
		       COALESCE(tip_cents, 0), COALESCE(total_cents, 0), currency,
		       merchant_name, status, raw_text, created_at, updated_at
		FROM receipts
		WHERE id = $1 AND group_id = $2 AND status != 'deleted'`,
		receiptID, groupID,
	).Scan(&resp.ID, &resp.GroupID, &resp.SubtotalCents, &resp.TaxCents,
		&resp.TipCents, &resp.TotalCents, &resp.Currency,
		&merchantName, &resp.Status, &rawText, &createdAt, &updatedAt)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "receipt not found"})
		return
	} else if err != nil {
		slog.ErrorContext(c.Request.Context(), "get receipt failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	if merchantName.Valid {
		resp.MerchantName = merchantName.String
	}
	if rawText.Valid {
		resp.RawText = rawText.String
	}
	resp.CreatedAt = createdAt.UTC().Format(time.RFC3339)
	resp.UpdatedAt = updatedAt.UTC().Format(time.RFC3339)

	// Load items with claim columns.
	itemRows, err := h.db.QueryContext(c.Request.Context(), `
		SELECT id, name, quantity, unit_cents, total_cents, sort_order, is_fully_assigned,
		       claimed_by_member_id, claimed_at, claim_expires_at
		FROM receipt_items
		WHERE receipt_id = $1
		ORDER BY sort_order ASC`,
		receiptID,
	)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "get receipt items failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer itemRows.Close()

	resp.Items = []getReceiptItemResponse{}
	var itemIDs []uuid.UUID
	for itemRows.Next() {
		var item getReceiptItemResponse
		var claimedByMemberID sql.NullString
		var claimedAt, claimExpiresAt sql.NullTime
		if err := itemRows.Scan(&item.ID, &item.Name, &item.Quantity,
			&item.UnitCents, &item.TotalCents, &item.SortOrder, &item.IsFullyAssigned,
			&claimedByMemberID, &claimedAt, &claimExpiresAt); err != nil {
			slog.ErrorContext(c.Request.Context(), "scan receipt item failed", "error", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		if claimedByMemberID.Valid {
			item.ClaimedByMemberID = &claimedByMemberID.String
		}
		if claimedAt.Valid {
			s := claimedAt.Time.UTC().Format(time.RFC3339)
			item.ClaimedAt = &s
		}
		if claimExpiresAt.Valid {
			s := claimExpiresAt.Time.UTC().Format(time.RFC3339)
			item.ClaimExpiresAt = &s
		}
		item.Assignments = []itemAssignmentResponse{}
		itemIDs = append(itemIDs, uuid.MustParse(item.ID))
		resp.Items = append(resp.Items, item)
	}

	// Load assignments for all items in this receipt.
	if len(itemIDs) > 0 {
		assignRows, err := h.db.QueryContext(c.Request.Context(), `
			SELECT ria.id, ria.receipt_item_id, ria.member_id,
			       ria.quantity_numerator, ria.quantity_denominator, ria.amount_cents
			FROM receipt_item_assignments ria
			JOIN receipt_items ri ON ri.id = ria.receipt_item_id
			WHERE ri.receipt_id = $1
			ORDER BY ria.created_at ASC`,
			receiptID,
		)
		if err != nil {
			slog.ErrorContext(c.Request.Context(), "get assignments failed", "error", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
			return
		}
		defer assignRows.Close()

		// Build a lookup from item ID to index in resp.Items.
		itemIndex := make(map[string]int, len(resp.Items))
		for i, item := range resp.Items {
			itemIndex[item.ID] = i
		}

		for assignRows.Next() {
			var a itemAssignmentResponse
			var receiptItemID string
			if err := assignRows.Scan(&a.ID, &receiptItemID, &a.MemberID,
				&a.QuantityNumerator, &a.QuantityDenominator, &a.AmountCents); err != nil {
				slog.ErrorContext(c.Request.Context(), "scan assignment failed", "error", err)
				c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
				return
			}
			if idx, ok := itemIndex[receiptItemID]; ok {
				resp.Items[idx].Assignments = append(resp.Items[idx].Assignments, a)
			}
		}
	}

	c.JSON(http.StatusOK, resp)
}

// ── PUT /v1/groups/:id/receipts/:receiptId/items/:itemId/claim ───────────────

// ClaimItem atomically claims a receipt item for the current member with a
// 60-second expiry. Returns 409 if another member already holds an active claim.
func (h *StoreHandler) ClaimItem(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	receiptID, err := uuid.Parse(c.Param("receiptId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid receipt_id"})
		return
	}
	itemID, err := uuid.Parse(c.Param("itemId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid item_id"})
		return
	}

	memberIDRaw, ok := c.Get("member_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	memberID, ok := memberIDRaw.(uuid.UUID)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	// Verify the item belongs to a receipt in this group.
	var exists bool
	if err := h.db.QueryRowContext(c.Request.Context(), `
		SELECT EXISTS(
			SELECT 1 FROM receipt_items ri
			JOIN receipts r ON r.id = ri.receipt_id
			WHERE ri.id = $1 AND ri.receipt_id = $2 AND r.group_id = $3
		)`, itemID, receiptID, groupID,
	).Scan(&exists); err != nil {
		slog.ErrorContext(c.Request.Context(), "verify item failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "item not found"})
		return
	}

	// Atomically claim: only succeeds if unclaimed, expired, or already ours.
	res, err := h.db.ExecContext(c.Request.Context(), `
		UPDATE receipt_items
		SET claimed_by_member_id = $1, claimed_at = NOW(), claim_expires_at = NOW() + INTERVAL '60 seconds',
		    updated_at = NOW()
		WHERE id = $2 AND receipt_id = $3
		  AND (claimed_by_member_id IS NULL OR claim_expires_at < NOW() OR claimed_by_member_id = $1)`,
		memberID, itemID, receiptID,
	)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "claim item failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	rows, err := res.RowsAffected()
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "rows affected failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if rows == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "item already claimed"})
		return
	}

	// Return the updated item.
	var item claimItemResponse
	var claimedByMemberID sql.NullString
	var claimedAt, claimExpiresAt sql.NullTime
	if err := h.db.QueryRowContext(c.Request.Context(), `
		SELECT id, receipt_id, name, quantity, unit_cents, total_cents,
		       claimed_by_member_id, claimed_at, claim_expires_at
		FROM receipt_items
		WHERE id = $1`,
		itemID,
	).Scan(&item.ID, &item.ReceiptID, &item.Name, &item.Quantity,
		&item.UnitCents, &item.TotalCents,
		&claimedByMemberID, &claimedAt, &claimExpiresAt); err != nil {
		slog.ErrorContext(c.Request.Context(), "read claimed item failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if claimedByMemberID.Valid {
		item.ClaimedByMemberID = &claimedByMemberID.String
	}
	if claimedAt.Valid {
		s := claimedAt.Time.UTC().Format(time.RFC3339)
		item.ClaimedAt = &s
	}
	if claimExpiresAt.Valid {
		s := claimExpiresAt.Time.UTC().Format(time.RFC3339)
		item.ClaimExpiresAt = &s
	}

	c.JSON(http.StatusOK, item)
}

// ── DELETE /v1/groups/:id/receipts/:receiptId/items/:itemId/claim ────────────

// ReleaseClaim releases a claim on a receipt item. Only the claiming member can
// release their own claim.
func (h *StoreHandler) ReleaseClaim(c *gin.Context) {
	_, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	receiptID, err := uuid.Parse(c.Param("receiptId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid receipt_id"})
		return
	}
	itemID, err := uuid.Parse(c.Param("itemId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid item_id"})
		return
	}

	memberIDRaw, ok := c.Get("member_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	memberID, ok := memberIDRaw.(uuid.UUID)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	res, err := h.db.ExecContext(c.Request.Context(), `
		UPDATE receipt_items
		SET claimed_by_member_id = NULL, claimed_at = NULL, claim_expires_at = NULL,
		    updated_at = NOW()
		WHERE id = $1 AND receipt_id = $2 AND claimed_by_member_id = $3`,
		itemID, receiptID, memberID,
	)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "release claim failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	rows, err := res.RowsAffected()
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "rows affected failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if rows == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "claim not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"released": true})
}

// ── POST /v1/groups/:id/receipts/:receiptId/items/assign ─────────────────────

// AssignItems allows the group leader to bulk-assign receipt items to members.
func (h *StoreHandler) AssignItems(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	receiptID, err := uuid.Parse(c.Param("receiptId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid receipt_id"})
		return
	}

	isLeaderRaw, ok := c.Get("is_leader")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	isLeader, ok := isLeaderRaw.(bool)
	if !ok || !isLeader {
		c.JSON(http.StatusForbidden, gin.H{"error": "leader access required"})
		return
	}

	var req assignItemsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify the receipt belongs to this group.
	var receiptExists bool
	if err := h.db.QueryRowContext(c.Request.Context(),
		`SELECT EXISTS(SELECT 1 FROM receipts WHERE id = $1 AND group_id = $2 AND status != 'deleted')`,
		receiptID, groupID,
	).Scan(&receiptExists); err != nil {
		slog.ErrorContext(c.Request.Context(), "verify receipt failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if !receiptExists {
		c.JSON(http.StatusNotFound, gin.H{"error": "receipt not found"})
		return
	}

	tx, err := h.db.BeginTx(c.Request.Context(), nil)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "begin tx failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer tx.Rollback()

	assigned := 0
	for _, a := range req.Assignments {
		itemID, err := uuid.Parse(a.ItemID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid item_id: " + a.ItemID})
			return
		}
		memberID, err := uuid.Parse(a.MemberID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid member_id: " + a.MemberID})
			return
		}

		// Verify item belongs to this receipt.
		var itemExists bool
		if err := tx.QueryRowContext(c.Request.Context(),
			`SELECT EXISTS(SELECT 1 FROM receipt_items WHERE id = $1 AND receipt_id = $2)`,
			itemID, receiptID,
		).Scan(&itemExists); err != nil {
			slog.ErrorContext(c.Request.Context(), "verify item failed", "error", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
			return
		}
		if !itemExists {
			c.JSON(http.StatusBadRequest, gin.H{"error": "item not found in receipt: " + a.ItemID})
			return
		}

		assignmentID := uuid.New()
		if _, err := tx.ExecContext(c.Request.Context(), `
			INSERT INTO receipt_item_assignments (id, receipt_item_id, member_id, quantity_numerator, quantity_denominator, amount_cents)
			VALUES ($1, $2, $3, $4, $5, $6)
			ON CONFLICT (receipt_item_id, member_id) DO UPDATE
			SET quantity_numerator = EXCLUDED.quantity_numerator,
			    quantity_denominator = EXCLUDED.quantity_denominator,
			    amount_cents = EXCLUDED.amount_cents,
			    updated_at = NOW()`,
			assignmentID, itemID, memberID,
			a.QuantityNumerator, a.QuantityDenominator, a.AmountCents,
		); err != nil {
			slog.ErrorContext(c.Request.Context(), "upsert assignment failed", "error", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
			return
		}
		assigned++
	}

	if err := tx.Commit(); err != nil {
		slog.ErrorContext(c.Request.Context(), "commit failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit failed"})
		return
	}

	slog.InfoContext(c.Request.Context(), "items assigned", "receipt_id", receiptID, "group_id", groupID, "count", assigned)
	c.JSON(http.StatusOK, assignItemsResponse{Assigned: assigned})
}

// ── POST /v1/groups/:id/receipts/:receiptId/confirm ──────────────────────────

// ConfirmSelections converts the current member's claimed items into permanent
// assignments. For each item claimed by this member, a full-quantity assignment
// is created (or updated if one already exists).
func (h *StoreHandler) ConfirmSelections(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	receiptID, err := uuid.Parse(c.Param("receiptId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid receipt_id"})
		return
	}

	memberIDRaw, ok := c.Get("member_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	memberID, ok := memberIDRaw.(uuid.UUID)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	// Verify the receipt belongs to this group.
	var receiptExists bool
	if err := h.db.QueryRowContext(c.Request.Context(),
		`SELECT EXISTS(SELECT 1 FROM receipts WHERE id = $1 AND group_id = $2 AND status != 'deleted')`,
		receiptID, groupID,
	).Scan(&receiptExists); err != nil {
		slog.ErrorContext(c.Request.Context(), "verify receipt failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if !receiptExists {
		c.JSON(http.StatusNotFound, gin.H{"error": "receipt not found"})
		return
	}

	// Find all items claimed by this member on this receipt.
	rows, err := h.db.QueryContext(c.Request.Context(), `
		SELECT id, total_cents
		FROM receipt_items
		WHERE receipt_id = $1 AND claimed_by_member_id = $2`,
		receiptID, memberID,
	)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "get claimed items failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	type claimedItem struct {
		id         uuid.UUID
		totalCents int64
	}
	var claimed []claimedItem
	for rows.Next() {
		var ci claimedItem
		if err := rows.Scan(&ci.id, &ci.totalCents); err != nil {
			slog.ErrorContext(c.Request.Context(), "scan claimed item failed", "error", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		claimed = append(claimed, ci)
	}

	if len(claimed) == 0 {
		c.JSON(http.StatusOK, gin.H{"confirmed": 0})
		return
	}

	tx, err := h.db.BeginTx(c.Request.Context(), nil)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "begin tx failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer tx.Rollback()

	for _, ci := range claimed {
		assignmentID := uuid.New()
		if _, err := tx.ExecContext(c.Request.Context(), `
			INSERT INTO receipt_item_assignments (id, receipt_item_id, member_id, quantity_numerator, quantity_denominator, amount_cents)
			VALUES ($1, $2, $3, 1, 1, $4)
			ON CONFLICT (receipt_item_id, member_id) DO UPDATE
			SET quantity_numerator = 1,
			    quantity_denominator = 1,
			    amount_cents = EXCLUDED.amount_cents,
			    updated_at = NOW()`,
			assignmentID, ci.id, memberID, ci.totalCents,
		); err != nil {
			slog.ErrorContext(c.Request.Context(), "upsert confirmation assignment failed", "error", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
			return
		}
	}

	if err := tx.Commit(); err != nil {
		slog.ErrorContext(c.Request.Context(), "commit failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit failed"})
		return
	}

	slog.InfoContext(c.Request.Context(), "selections confirmed", "receipt_id", receiptID, "member_id", memberID, "items", len(claimed))
	c.JSON(http.StatusOK, gin.H{"confirmed": len(claimed)})
}

// ── GET /v1/groups/:id/receipts/:receiptId/confirmations ─────────────────────

// GetConfirmations returns all group members and whether each has confirmed
// their item selections (i.e., has at least one assignment on this receipt).
func (h *StoreHandler) GetConfirmations(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	receiptID, err := uuid.Parse(c.Param("receiptId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid receipt_id"})
		return
	}

	// Verify the receipt belongs to this group.
	var receiptExists bool
	if err := h.db.QueryRowContext(c.Request.Context(),
		`SELECT EXISTS(SELECT 1 FROM receipts WHERE id = $1 AND group_id = $2 AND status != 'deleted')`,
		receiptID, groupID,
	).Scan(&receiptExists); err != nil {
		slog.ErrorContext(c.Request.Context(), "verify receipt failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if !receiptExists {
		c.JSON(http.StatusNotFound, gin.H{"error": "receipt not found"})
		return
	}

	rows, err := h.db.QueryContext(c.Request.Context(), `
		SELECT m.id, m.display_name,
		       EXISTS(
		           SELECT 1 FROM receipt_item_assignments ria
		           JOIN receipt_items ri ON ri.id = ria.receipt_item_id
		           WHERE ri.receipt_id = $1 AND ria.member_id = m.id
		       ) AS confirmed
		FROM members m
		WHERE m.group_id = $2
		ORDER BY m.display_name ASC`,
		receiptID, groupID,
	)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "get confirmations failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	confirmations := []confirmationMember{}
	for rows.Next() {
		var cm confirmationMember
		if err := rows.Scan(&cm.MemberID, &cm.DisplayName, &cm.Confirmed); err != nil {
			slog.ErrorContext(c.Request.Context(), "scan confirmation failed", "error", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		confirmations = append(confirmations, cm)
	}

	c.JSON(http.StatusOK, confirmationsResponse{Confirmations: confirmations})
}
