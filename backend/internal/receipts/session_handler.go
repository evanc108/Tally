package receipts

import (
	"database/sql"
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/tally/backend/internal/middleware"
)

// SessionHandler manages persisted receipt sessions — the bridge between
// stateless OCR parsing (/v1/receipts/parse) and the JIT authorization
// handler. Flow:
//
//  1. iOS parses receipt → POST /v1/receipts/parse (stateless)
//  2. iOS saves result  → POST /v1/groups/:id/receipts  (status: draft)
//  3. Members claim items → PUT /v1/groups/:id/receipts/:id/assignments
//  4. Leader locks it   → POST /v1/groups/:id/receipts/:id/finalize (status: finalized)
//  5. Card swipe        → JIT reads finalized receipt, uses item amounts instead
//     of split_weight, then links receipt to the transaction.
type SessionHandler struct {
	db *sql.DB
}

func NewSessionHandler(db *sql.DB) *SessionHandler {
	return &SessionHandler{db: db}
}

// ── POST /v1/groups/:id/receipts ─────────────────────────────────────────────

type receiptItemIn struct {
	Name       string `json:"name"        binding:"required"`
	Quantity   int    `json:"quantity"`
	UnitCents  int64  `json:"unit_cents"`
	TotalCents int64  `json:"total_cents" binding:"required"`
}

type createReceiptReq struct {
	Items         []receiptItemIn `json:"items"          binding:"required,min=1"`
	SubtotalCents *int64          `json:"subtotal_cents"`
	TaxCents      *int64          `json:"tax_cents"`
	TipCents      *int64          `json:"tip_cents"`
	TotalCents    *int64          `json:"total_cents"`
	MerchantName  string          `json:"merchant_name"`
	RawText       string          `json:"raw_text"`
	Confidence    float64         `json:"confidence"`
}

type itemOut struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Quantity   int    `json:"quantity"`
	UnitCents  int64  `json:"unit_cents"`
	TotalCents int64  `json:"total_cents"`
	SortOrder  int    `json:"sort_order"`
}

type createReceiptResp struct {
	ReceiptID string    `json:"receipt_id"`
	Status    string    `json:"status"`
	Items     []itemOut `json:"items"`
	CreatedAt string    `json:"created_at"`
}

// CreateReceipt saves parsed receipt data to the database as a draft session.
// Any existing unlinked draft or finalized session for the group is cancelled
// first so there is never more than one active session per group at a time.
func (h *SessionHandler) CreateReceipt(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}

	userIDRaw, _ := c.Get(middleware.ClerkUserIDKey)
	userID, _ := userIDRaw.(string)

	var req createReceiptReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	tx, err := h.db.BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer tx.Rollback() //nolint:errcheck

	// Fix 6: cancel any existing active session for this group before creating
	// a new one — prevents multiple concurrent sessions from confusing the JIT
	// handler. Atomically done inside the same transaction.
	if _, err := tx.ExecContext(c.Request.Context(), `
		UPDATE receipts
		SET status = 'deleted', updated_at = NOW()
		WHERE group_id       = $1
		  AND status         IN ('draft', 'finalized')
		  AND transaction_id IS NULL`,
		groupID,
	); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	receiptID := uuid.New()
	var createdAt time.Time

	var nullableUserID interface{}
	if userID != "" {
		nullableUserID = userID
	}

	if err := tx.QueryRowContext(c.Request.Context(), `
		INSERT INTO receipts
			(id, group_id, created_by_user_id,
			 subtotal_cents, tax_cents, tip_cents, total_cents,
			 confidence, merchant_name, raw_text, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'draft')
		RETURNING created_at`,
		receiptID, groupID, nullableUserID,
		req.SubtotalCents, req.TaxCents, req.TipCents, req.TotalCents,
		req.Confidence, req.MerchantName, req.RawText,
	).Scan(&createdAt); err != nil {
		slog.ErrorContext(c.Request.Context(), "insert receipt failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	items := make([]itemOut, 0, len(req.Items))
	for i, item := range req.Items {
		qty := item.Quantity
		if qty == 0 {
			qty = 1
		}
		itemID := uuid.New()
		if _, err := tx.ExecContext(c.Request.Context(), `
			INSERT INTO receipt_items
				(id, receipt_id, name, quantity, unit_cents, total_cents, sort_order)
			VALUES ($1, $2, $3, $4, $5, $6, $7)`,
			itemID, receiptID, item.Name, qty, item.UnitCents, item.TotalCents, i,
		); err != nil {
			slog.ErrorContext(c.Request.Context(), "insert receipt item failed", "error", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
			return
		}
		items = append(items, itemOut{
			ID:         itemID.String(),
			Name:       item.Name,
			Quantity:   qty,
			UnitCents:  item.UnitCents,
			TotalCents: item.TotalCents,
			SortOrder:  i,
		})
	}

	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit failed"})
		return
	}

	c.JSON(http.StatusCreated, createReceiptResp{
		ReceiptID: receiptID.String(),
		Status:    "draft",
		Items:     items,
		CreatedAt: createdAt.UTC().Format(time.RFC3339),
	})
}

// ── GET /v1/groups/:id/receipts/active ────────────────────────────────────────

type assignmentOut struct {
	MemberID            string `json:"member_id"`
	AmountCents         int64  `json:"amount_cents"`
	QuantityNumerator   int    `json:"quantity_numerator"`
	QuantityDenominator int    `json:"quantity_denominator"`
}

type itemWithAssignments struct {
	itemOut
	Assignments []assignmentOut `json:"assignments"`
}

type activeReceiptResp struct {
	ReceiptID     string                `json:"receipt_id"`
	Status        string                `json:"status"`
	MerchantName  string                `json:"merchant_name,omitempty"`
	SubtotalCents *int64                `json:"subtotal_cents,omitempty"`
	TaxCents      *int64                `json:"tax_cents,omitempty"`
	TipCents      *int64                `json:"tip_cents,omitempty"`
	TotalCents    *int64                `json:"total_cents,omitempty"`
	Items         []itemWithAssignments `json:"items"`
	CreatedAt     string                `json:"created_at"`
}

// GetActiveReceipt returns the most recent draft or finalized receipt for the
// group that has not yet been linked to a transaction, along with all current
// item assignments. The iOS app polls this to show each member's selections
// in real time.
func (h *SessionHandler) GetActiveReceipt(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}

	var receiptID, status, merchantName string
	var createdAt time.Time
	var subtotal, tax, tip, total sql.NullInt64

	err = h.db.QueryRowContext(c.Request.Context(), `
		SELECT id, status, COALESCE(merchant_name, ''),
		       subtotal_cents, tax_cents, tip_cents, total_cents, created_at
		FROM receipts
		WHERE group_id       = $1
		  AND status         IN ('draft', 'finalized')
		  AND transaction_id IS NULL
		ORDER BY created_at DESC
		LIMIT 1`,
		groupID,
	).Scan(&receiptID, &status, &merchantName,
		&subtotal, &tax, &tip, &total, &createdAt)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "no active receipt"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	resp := activeReceiptResp{
		ReceiptID:    receiptID,
		Status:       status,
		MerchantName: merchantName,
		CreatedAt:    createdAt.UTC().Format(time.RFC3339),
	}
	if subtotal.Valid {
		resp.SubtotalCents = &subtotal.Int64
	}
	if tax.Valid {
		resp.TaxCents = &tax.Int64
	}
	if tip.Valid {
		resp.TipCents = &tip.Int64
	}
	if total.Valid {
		resp.TotalCents = &total.Int64
	}

	// Load items ordered by sort_order.
	itemRows, err := h.db.QueryContext(c.Request.Context(), `
		SELECT id, name, quantity, unit_cents, total_cents, sort_order
		FROM receipt_items
		WHERE receipt_id = $1
		ORDER BY sort_order ASC`,
		receiptID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer itemRows.Close()

	itemMap := map[string]*itemWithAssignments{}
	itemOrder := []string{}
	for itemRows.Next() {
		var it itemWithAssignments
		if err := itemRows.Scan(&it.ID, &it.Name, &it.Quantity,
			&it.UnitCents, &it.TotalCents, &it.SortOrder); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		it.Assignments = []assignmentOut{}
		itemMap[it.ID] = &it
		itemOrder = append(itemOrder, it.ID)
	}

	// Load all current assignments for this receipt in one query.
	assignRows, err := h.db.QueryContext(c.Request.Context(), `
		SELECT ria.receipt_item_id::text, ria.member_id::text,
		       ria.amount_cents, ria.quantity_numerator, ria.quantity_denominator
		FROM receipt_item_assignments ria
		JOIN receipt_items ri ON ri.id = ria.receipt_item_id
		WHERE ri.receipt_id = $1`,
		receiptID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer assignRows.Close()

	for assignRows.Next() {
		var itemID string
		var a assignmentOut
		if err := assignRows.Scan(&itemID, &a.MemberID, &a.AmountCents,
			&a.QuantityNumerator, &a.QuantityDenominator); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		if it, ok := itemMap[itemID]; ok {
			it.Assignments = append(it.Assignments, a)
		}
	}

	resp.Items = make([]itemWithAssignments, 0, len(itemOrder))
	for _, id := range itemOrder {
		resp.Items = append(resp.Items, *itemMap[id])
	}

	c.JSON(http.StatusOK, resp)
}

// ── PUT /v1/groups/:id/receipts/:receiptId/assignments ────────────────────────

type assignmentIn struct {
	ItemID              string `json:"item_id"              binding:"required"`
	QuantityNumerator   int    `json:"quantity_numerator"`
	QuantityDenominator int    `json:"quantity_denominator"`
	AmountCents         int64  `json:"amount_cents"         binding:"required"`
}

type upsertAssignmentsReq struct {
	Assignments []assignmentIn `json:"assignments" binding:"required"`
}

// UpsertAssignments replaces all item assignments for the calling member on a
// draft receipt. Send an empty assignments slice to clear all claims. The iOS
// app calls this each time a member taps or untaps an item.
func (h *SessionHandler) UpsertAssignments(c *gin.Context) {
	// Fix 1: scope all receipt queries to the group in the URL.
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

	memberIDRaw, ok := c.Get(middleware.MemberIDKey)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	memberID, ok := memberIDRaw.(uuid.UUID)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	var req upsertAssignmentsReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Fix 1: verify receipt belongs to this group and is still in draft.
	var status string
	err = h.db.QueryRowContext(c.Request.Context(),
		`SELECT status FROM receipts WHERE id = $1 AND group_id = $2`,
		receiptID, groupID,
	).Scan(&status)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "receipt not found"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if status != "draft" {
		c.JSON(http.StatusConflict, gin.H{"error": "receipt is not in draft status"})
		return
	}

	if len(req.Assignments) > 0 {
		// Parse and deduplicate item IDs.
		itemIDs := make([]uuid.UUID, 0, len(req.Assignments))
		for _, a := range req.Assignments {
			id, err := uuid.Parse(a.ItemID)
			if err != nil {
				c.JSON(http.StatusBadRequest, gin.H{"error": "invalid item_id: " + a.ItemID})
				return
			}
			itemIDs = append(itemIDs, id)
		}

		// Fix 1 + Fix 3: fetch item prices in one query to validate both
		// ownership (item belongs to this receipt) and amount_cents bounds.
		priceRows, err := h.db.QueryContext(c.Request.Context(),
			`SELECT id::text, total_cents FROM receipt_items
			 WHERE receipt_id = $1 AND id = ANY($2)`,
			receiptID, itemIDs,
		)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
			return
		}
		itemPrices := map[string]int64{}
		for priceRows.Next() {
			var id string
			var tc int64
			if err := priceRows.Scan(&id, &tc); err != nil {
				priceRows.Close()
				c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
				return
			}
			itemPrices[id] = tc
		}
		priceRows.Close()

		if len(itemPrices) != len(req.Assignments) {
			c.JSON(http.StatusBadRequest, gin.H{"error": "one or more item_ids do not belong to this receipt"})
			return
		}

		// Fix 3: validate that each amount_cents is consistent with the item
		// price and the claimed fraction. Allow ±1 cent for rounding at the
		// client (floor vs ceil of the fractional division).
		for _, a := range req.Assignments {
			totalCents := itemPrices[a.ItemID]
			num := int64(a.QuantityNumerator)
			den := int64(a.QuantityDenominator)
			if num <= 0 {
				num = 1
			}
			if den <= 0 {
				den = 1
			}
			minAllowed := (totalCents * num) / den
			maxAllowed := (totalCents*num + den - 1) / den
			if a.AmountCents < minAllowed || a.AmountCents > maxAllowed {
				c.JSON(http.StatusBadRequest, gin.H{
					"error":       "amount_cents out of range for item",
					"item_id":     a.ItemID,
					"min_allowed": minAllowed,
					"max_allowed": maxAllowed,
					"got":         a.AmountCents,
				})
				return
			}
		}
	}

	tx, err := h.db.BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer tx.Rollback() //nolint:errcheck

	// Clear all existing assignments for this member on this receipt.
	if _, err := tx.ExecContext(c.Request.Context(), `
		DELETE FROM receipt_item_assignments
		WHERE member_id = $1
		  AND receipt_item_id IN (
		      SELECT id FROM receipt_items WHERE receipt_id = $2
		  )`,
		memberID, receiptID,
	); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	for _, a := range req.Assignments {
		itemID, _ := uuid.Parse(a.ItemID) // already validated above
		num := a.QuantityNumerator
		den := a.QuantityDenominator
		if num <= 0 {
			num = 1
		}
		if den <= 0 {
			den = 1
		}
		if _, err := tx.ExecContext(c.Request.Context(), `
			INSERT INTO receipt_item_assignments
				(receipt_item_id, member_id, quantity_numerator, quantity_denominator, amount_cents)
			VALUES ($1, $2, $3, $4, $5)`,
			itemID, memberID, num, den, a.AmountCents,
		); err != nil {
			slog.ErrorContext(c.Request.Context(), "insert assignment failed", "error", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
			return
		}
	}

	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit failed"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "ok", "assignments_saved": len(req.Assignments)})
}

// ── POST /v1/groups/:id/receipts/:receiptId/finalize ──────────────────────────

// FinalizeReceipt locks the receipt so the JIT handler will use item-based
// amounts on the next card swipe. Requires the caller to be the group leader.
func (h *SessionHandler) FinalizeReceipt(c *gin.Context) {
	// Fix 1: scope to group.
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

	// Fix 2: only the group leader may finalize.
	isLeaderRaw, _ := c.Get(middleware.IsLeaderKey)
	isLeader, _ := isLeaderRaw.(bool)
	if !isLeader {
		c.JSON(http.StatusForbidden, gin.H{"error": "leader access required to finalize receipt"})
		return
	}

	// Fix 1: include group_id in the WHERE so cross-group IDOR is impossible.
	result, err := h.db.ExecContext(c.Request.Context(), `
		UPDATE receipts
		SET status = 'finalized', updated_at = NOW()
		WHERE id = $1 AND group_id = $2 AND status = 'draft'`,
		receiptID, groupID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if n, _ := result.RowsAffected(); n == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "receipt not found, wrong group, or not in draft status"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "finalized"})
}

// ── DELETE /v1/groups/:id/receipts/:receiptId ─────────────────────────────────

// CancelReceipt soft-deletes a draft or finalized receipt before the card is
// swiped. Requires the caller to be the receipt creator or the group leader.
func (h *SessionHandler) CancelReceipt(c *gin.Context) {
	// Fix 1: scope to group.
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

	// Fix 2: allow the creator or the group leader to cancel.
	callerIDRaw, _ := c.Get(middleware.ClerkUserIDKey)
	callerID, _ := callerIDRaw.(string)

	isLeaderRaw, _ := c.Get(middleware.IsLeaderKey)
	isLeader, _ := isLeaderRaw.(bool)

	// Fetch the receipt's creator scoped to this group.
	var createdByUserID sql.NullString
	err = h.db.QueryRowContext(c.Request.Context(),
		`SELECT created_by_user_id FROM receipts WHERE id = $1 AND group_id = $2`,
		receiptID, groupID,
	).Scan(&createdByUserID)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "receipt not found"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	isCreator := createdByUserID.Valid && createdByUserID.String == callerID
	if !isLeader && !isCreator {
		c.JSON(http.StatusForbidden, gin.H{"error": "only the receipt creator or group leader can cancel"})
		return
	}

	// Fix 1: include group_id in the UPDATE to close any remaining IDOR surface.
	result, err := h.db.ExecContext(c.Request.Context(), `
		UPDATE receipts
		SET status = 'deleted', updated_at = NOW()
		WHERE id             = $1
		  AND group_id       = $2
		  AND status         IN ('draft', 'finalized')
		  AND transaction_id IS NULL`,
		receiptID, groupID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if n, _ := result.RowsAffected(); n == 0 {
		c.JSON(http.StatusConflict, gin.H{"error": "receipt cannot be cancelled"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "cancelled"})
}
