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
	Name        string `json:"name"         binding:"required"`
	Currency    string `json:"currency"`
	DisplayName string `json:"display_name" binding:"required"`
}

type createGroupResponse struct {
	GroupID   string `json:"group_id"`
	Name      string `json:"name"`
	Currency  string `json:"currency"`
	CreatedAt string `json:"created_at"`
	MemberID  string `json:"member_id"`
}

// CreateGroup creates a new tally group and its clearing (liability) ledger account.
//
// @Summary      Create a group
// @Description  Creates a new Tally group and provisions its double-entry liability ledger account.
// @Tags         groups
// @Accept       json
// @Produce      json
// @Param        body body createGroupRequest true "Group details"
// @Success      201  {object} createGroupResponse
// @Failure      400  {object} map[string]string
// @Failure      500  {object} map[string]string
// @Router       /v1/groups [post]
func (h *Handler) CreateGroup(c *gin.Context) {
	clerkUserID, ok := c.Get("clerk_user_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	userID, _ := clerkUserID.(string)

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
	groupAccountID := uuid.New()
	memberID := uuid.New()
	memberAccountID := uuid.New()

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
		groupAccountID, groupID, currency,
	); err != nil {
		slog.ErrorContext(c.Request.Context(), "create group account failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	// Add the creator as the first member and leader.
	if _, err := tx.ExecContext(c.Request.Context(), `
		INSERT INTO members (id, group_id, user_id, display_name, split_weight, is_leader)
		VALUES ($1, $2, $3, $4, 1.0, true)`,
		memberID, groupID, userID, req.DisplayName,
	); err != nil {
		slog.ErrorContext(c.Request.Context(), "create creator member failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	if _, err := tx.ExecContext(c.Request.Context(),
		`INSERT INTO accounts (id, owner_id, owner_type, account_type) VALUES ($1, $2, 'member', 'asset')`,
		memberAccountID, memberID,
	); err != nil {
		slog.ErrorContext(c.Request.Context(), "create creator account failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit failed"})
		return
	}

	slog.InfoContext(c.Request.Context(), "group created", "group_id", groupID, "creator_member_id", memberID)
	c.JSON(http.StatusCreated, createGroupResponse{
		GroupID:   groupID.String(),
		Name:      req.Name,
		Currency:  currency,
		CreatedAt: createdAt.UTC().Format(time.RFC3339),
		MemberID:  memberID.String(),
	})
}

// ── POST /v1/groups/:id/members ───────────────────────────────────────────────

type addMemberRequest struct {
	DisplayName      string  `json:"display_name"        binding:"required"`
	UserID           string  `json:"user_id"`           // optional: defaults to caller's user ID
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
//
// @Summary      Add a member to a group
// @Description  Creates a member record (with optional Plaid tokens) and provisions their asset ledger account.
// @Tags         groups
// @Accept       json
// @Produce      json
// @Param        id   path string          true "Group ID (UUID)"
// @Param        body body addMemberRequest true "Member details"
// @Success      201  {object} addMemberResponse
// @Failure      400  {object} map[string]string
// @Failure      404  {object} map[string]string
// @Failure      500  {object} map[string]string
// @Router       /v1/groups/{id}/members [post]
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

	// Use the provided user_id if given (leader adding someone else), otherwise
	// default to the caller's own identity (self-join).
	userID := req.UserID
	if userID == "" {
		callerID, _ := c.Get("clerk_user_id")
		userID, _ = callerID.(string)
	}
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_user_identity"})
		return
	}

	// Ensure the user exists in the users table (upsert so leaders can add
	// members who haven't called /users/me yet).
	if _, err := h.db.ExecContext(c.Request.Context(),
		`INSERT INTO users (id) VALUES ($1) ON CONFLICT (id) DO NOTHING`, userID,
	); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	memberID := uuid.New()
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

	slog.InfoContext(c.Request.Context(), "member added", "member_id", memberID, "group_id", groupID, "user_id", userID)
	c.JSON(http.StatusCreated, addMemberResponse{
		MemberID:    memberID.String(),
		UserID:      userID,
		DisplayName: req.DisplayName,
		SplitWeight: req.SplitWeight,
	})
}

// ── GET /v1/groups ────────────────────────────────────────────────────────────

type groupSummary struct {
	GroupID   string `json:"group_id"`
	Name      string `json:"name"`
	Currency  string `json:"currency"`
	CreatedAt string `json:"created_at"`
}

// ListGroups returns all groups the authenticated user belongs to.
//
// @Summary      List groups
// @Description  Returns all groups the authenticated user is a member of, newest first.
// @Tags         groups
// @Produce      json
// @Success      200 {object} map[string][]groupSummary
// @Failure      401 {object} map[string]string
// @Failure      500 {object} map[string]string
// @Router       /v1/groups [get]
func (h *Handler) ListGroups(c *gin.Context) {
	clerkUserID, ok := c.Get("clerk_user_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	rows, err := h.db.QueryContext(c.Request.Context(), `
		SELECT g.id, g.name, g.currency, g.created_at
		FROM tally_groups g
		JOIN members m ON m.group_id = g.id
		WHERE m.user_id = $1
		ORDER BY g.created_at DESC`,
		clerkUserID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	result := []groupSummary{}
	for rows.Next() {
		var g groupSummary
		var createdAt time.Time
		if err := rows.Scan(&g.GroupID, &g.Name, &g.Currency, &createdAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		g.CreatedAt = createdAt.UTC().Format(time.RFC3339)
		result = append(result, g)
	}

	c.JSON(http.StatusOK, gin.H{"groups": result})
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
//
// @Summary      Get a group
// @Description  Returns group metadata (name, currency) and a summary of all members including balances.
// @Tags         groups
// @Produce      json
// @Param        id  path string true "Group ID (UUID)"
// @Success      200 {object} getGroupResponse
// @Failure      400 {object} map[string]string
// @Failure      404 {object} map[string]string
// @Failure      500 {object} map[string]string
// @Router       /v1/groups/{id} [get]
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
//
// @Summary      List transactions
// @Description  Returns the 50 most recent transactions for a group, newest first.
// @Tags         groups
// @Produce      json
// @Param        id  path string true "Group ID (UUID)"
// @Success      200 {object} map[string][]transactionSummary
// @Failure      400 {object} map[string]string
// @Failure      500 {object} map[string]string
// @Router       /v1/groups/{id}/transactions [get]
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
