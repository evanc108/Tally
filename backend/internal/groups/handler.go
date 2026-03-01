// Package groups implements HTTP handlers for group and member management.
package groups

import (
	"database/sql"
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// Handler handles group and member routes.
type Handler struct {
	db *sql.DB
}

func NewHandler(db *sql.DB) *Handler {
	return &Handler{db: db}
}

// ── POST /v1/groups ───────────────────────────────────────────────────────────

type createGroupRequest struct {
	Name     string `json:"name"     binding:"required"`
	Currency string `json:"currency"`
}

type createGroupResponse struct {
	GroupID   string `json:"group_id"`
	Name      string `json:"name"`
	Currency  string `json:"currency"`
	CreatedAt string `json:"created_at"`
}

// CreateGroup creates a new tally group and its clearing (liability) ledger account.
func (h *Handler) CreateGroup(c *gin.Context) {
	var req createGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	currency := req.Currency
	if currency == "" {
		currency = "USD"
	}

	groupID := uuid.New()
	accountID := uuid.New()

	tx, err := h.db.BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer tx.Rollback()

	var createdAt time.Time
	if err := tx.QueryRowContext(c.Request.Context(),
		`INSERT INTO tally_groups (id, name, currency) VALUES ($1, $2, $3) RETURNING created_at`,
		groupID, req.Name, currency,
	).Scan(&createdAt); err != nil {
		slog.ErrorContext(c.Request.Context(), "create group failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	if _, err := tx.ExecContext(c.Request.Context(),
		`INSERT INTO accounts (id, owner_id, owner_type, account_type, currency) VALUES ($1, $2, 'group', 'liability', $3)`,
		accountID, groupID, currency,
	); err != nil {
		slog.ErrorContext(c.Request.Context(), "create group account failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit failed"})
		return
	}

	slog.InfoContext(c.Request.Context(), "group created", "group_id", groupID)
	c.JSON(http.StatusCreated, createGroupResponse{
		GroupID:   groupID.String(),
		Name:      req.Name,
		Currency:  currency,
		CreatedAt: createdAt.UTC().Format(time.RFC3339),
	})
}

// ── POST /v1/groups/:id/members ───────────────────────────────────────────────

type addMemberRequest struct {
	DisplayName      string  `json:"display_name"        binding:"required"`
	PlaidAccessToken string  `json:"plaid_access_token"`
	PlaidAccountID   string  `json:"plaid_account_id"`
	SplitWeight      float64 `json:"split_weight"`
	IsLeader         bool    `json:"is_leader"`
}

type addMemberResponse struct {
	MemberID    string  `json:"member_id"`
	UserID      string  `json:"user_id"`
	DisplayName string  `json:"display_name"`
	SplitWeight float64 `json:"split_weight"`
}

// AddMember adds a member to an existing group and creates their asset ledger account.
// SplitWeight defaults to 0.25 if not provided; callers are responsible for
// ensuring all members' weights sum to 1.0.
func (h *Handler) AddMember(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}

	var req addMemberRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.SplitWeight <= 0 {
		req.SplitWeight = 0.25
	}

	// Verify group exists.
	var exists bool
	if err := h.db.QueryRowContext(c.Request.Context(),
		`SELECT EXISTS(SELECT 1 FROM tally_groups WHERE id = $1)`, groupID,
	).Scan(&exists); err != nil || !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
		return
	}

	memberID := uuid.New()
	userID := uuid.New() // no auth system yet — generate a stable user_id
	accountID := uuid.New()

	tx, err := h.db.BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer tx.Rollback()

	if _, err := tx.ExecContext(c.Request.Context(), `
		INSERT INTO members
			(id, group_id, user_id, display_name,
			 plaid_access_token, plaid_account_id,
			 split_weight, is_leader)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		memberID, groupID, userID, req.DisplayName,
		nullStr(req.PlaidAccessToken), nullStr(req.PlaidAccountID),
		req.SplitWeight, req.IsLeader,
	); err != nil {
		slog.ErrorContext(c.Request.Context(), "create member failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	if _, err := tx.ExecContext(c.Request.Context(),
		`INSERT INTO accounts (id, owner_id, owner_type, account_type) VALUES ($1, $2, 'member', 'asset')`,
		accountID, memberID,
	); err != nil {
		slog.ErrorContext(c.Request.Context(), "create member account failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit failed"})
		return
	}

	slog.InfoContext(c.Request.Context(), "member added", "member_id", memberID, "group_id", groupID)
	c.JSON(http.StatusCreated, addMemberResponse{
		MemberID:    memberID.String(),
		UserID:      userID.String(),
		DisplayName: req.DisplayName,
		SplitWeight: req.SplitWeight,
	})
}

// ── GET /v1/groups/:id ────────────────────────────────────────────────────────

type memberSummary struct {
	MemberID          string  `json:"member_id"`
	DisplayName       string  `json:"display_name"`
	SplitWeight       float64 `json:"split_weight"`
	TallyBalanceCents int64   `json:"tally_balance_cents"`
	IsLeader          bool    `json:"is_leader"`
	HasCard           bool    `json:"has_card"`
}

type getGroupResponse struct {
	GroupID   string          `json:"group_id"`
	Name      string          `json:"name"`
	Currency  string          `json:"currency"`
	Members   []memberSummary `json:"members"`
}

// GetGroup returns group metadata and a summary of all members.
func (h *Handler) GetGroup(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}

	var name, currency string
	if err := h.db.QueryRowContext(c.Request.Context(),
		`SELECT name, currency FROM tally_groups WHERE id = $1`, groupID,
	).Scan(&name, &currency); err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	rows, err := h.db.QueryContext(c.Request.Context(), `
		SELECT id, display_name, split_weight::float8, tally_balance_cents, is_leader,
		       (card_token IS NOT NULL) AS has_card
		FROM members
		WHERE group_id = $1
		ORDER BY is_leader DESC, display_name ASC`,
		groupID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	members := []memberSummary{}
	for rows.Next() {
		var m memberSummary
		if err := rows.Scan(&m.MemberID, &m.DisplayName, &m.SplitWeight,
			&m.TallyBalanceCents, &m.IsLeader, &m.HasCard); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		members = append(members, m)
	}

	c.JSON(http.StatusOK, getGroupResponse{
		GroupID:  groupID.String(),
		Name:     name,
		Currency: currency,
		Members:  members,
	})
}

// ── GET /v1/groups/:id/transactions ──────────────────────────────────────────

type transactionSummary struct {
	ID               string `json:"id"`
	AmountCents      int64  `json:"amount_cents"`
	Currency         string `json:"currency"`
	MerchantName     string `json:"merchant_name,omitempty"`
	MerchantCategory string `json:"merchant_category,omitempty"`
	Status           string `json:"status"`
	CreatedAt        string `json:"created_at"`
}

// ListTransactions returns the 50 most recent transactions for a group.
func (h *Handler) ListTransactions(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}

	rows, err := h.db.QueryContext(c.Request.Context(), `
		SELECT id, amount_cents, currency,
		       COALESCE(merchant_name, ''), COALESCE(merchant_category, ''),
		       status, created_at
		FROM transactions
		WHERE group_id = $1
		ORDER BY created_at DESC
		LIMIT 50`,
		groupID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	txns := []transactionSummary{}
	for rows.Next() {
		var t transactionSummary
		var createdAt time.Time
		if err := rows.Scan(&t.ID, &t.AmountCents, &t.Currency,
			&t.MerchantName, &t.MerchantCategory, &t.Status, &createdAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		t.CreatedAt = createdAt.UTC().Format(time.RFC3339)
		txns = append(txns, t)
	}

	c.JSON(http.StatusOK, gin.H{"transactions": txns})
}

// nullStr converts an empty string to nil for nullable TEXT columns.
func nullStr(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}
