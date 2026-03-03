// Package groups implements HTTP handlers for group and member management.
package groups

import (
	"database/sql"
	"log/slog"
	"math"
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
	userID, ok := clerkUserID.(string)
	if !ok || userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

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
	DisplayName string  `json:"display_name" binding:"required"`
	UserID      string  `json:"user_id"`   // optional: defaults to caller's user ID
	SplitWeight float64 `json:"split_weight"`
	IsLeader    bool    `json:"is_leader"`
}

type addMemberResponse struct {
	MemberID    string  `json:"member_id"`
	UserID      string  `json:"user_id"`
	DisplayName string  `json:"display_name"`
	SplitWeight float64 `json:"split_weight"`
}

// AddMember adds a member to an existing group and creates their asset ledger
// account. The sum of all split_weight values in the group must not exceed
// 1.000000 after the addition; the caller is responsible for distributing
// weights correctly before the group goes live.
//
// @Summary      Add a member to a group
// @Description  Creates a member record and provisions their asset ledger account. Enforces that the total split weight for the group does not exceed 1.0.
// @Tags         groups
// @Accept       json
// @Produce      json
// @Param        id   path string          true "Group ID (UUID)"
// @Param        body body addMemberRequest true "Member details"
// @Success      201  {object} addMemberResponse
// @Failure      400  {object} map[string]string
// @Failure      404  {object} map[string]string
// @Failure      422  {object} map[string]string
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
	if req.SplitWeight > 1.0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "split_weight must be between 0 and 1"})
		return
	}

	// Use the provided user_id if given (leader adding someone else), otherwise
	// default to the caller's own identity (self-join).
	userID := req.UserID
	if userID == "" {
		callerIDRaw, _ := c.Get("clerk_user_id")
		userID, _ = callerIDRaw.(string)
	}
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing_user_identity"})
		return
	}

	// Ensure the user exists in the users table.
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
			(id, group_id, user_id, display_name, split_weight, is_leader)
		VALUES ($1, $2, $3, $4, $5, $6)`,
		memberID, groupID, userID, req.DisplayName,
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

	// Validate that total split weight does not exceed 1.0 after this insert.
	var totalWeight float64
	if err := tx.QueryRowContext(c.Request.Context(),
		`SELECT COALESCE(SUM(split_weight::float8), 0) FROM members WHERE group_id = $1`,
		groupID,
	).Scan(&totalWeight); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	// Allow a tiny float tolerance.
	if totalWeight > 1.0+1e-6 {
		c.JSON(http.StatusUnprocessableEntity, gin.H{
			"error":        "split_weight_exceeded",
			"total_weight": math.Round(totalWeight*1e6) / 1e6,
		})
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
	clerkUserIDRaw, ok := c.Get("clerk_user_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	clerkUserID, ok := clerkUserIDRaw.(string)
	if !ok || clerkUserID == "" {
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
	KYCStatus         string  `json:"kyc_status"`
}

type getGroupResponse struct {
	GroupID  string          `json:"group_id"`
	Name     string          `json:"name"`
	Currency string          `json:"currency"`
	Members  []memberSummary `json:"members"`
}

// GetGroup returns group metadata and a summary of all members.
//
// @Summary      Get a group
// @Description  Returns group metadata (name, currency) and a summary of all members.
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
		       (card_token IS NOT NULL) AS has_card,
		       kyc_status
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
			&m.TallyBalanceCents, &m.IsLeader, &m.HasCard, &m.KYCStatus); err != nil {
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

// ── GET /v1/groups/:id/transactions/:txnId ────────────────────────────────────

type fundingPullDetail struct {
	MemberID    string `json:"member_id"`
	DisplayName string `json:"display_name"`
	AmountCents int64  `json:"amount_cents"`
	FundingType string `json:"funding_type"`
	Status      string `json:"status"`
}

type iouDetail struct {
	ID               string `json:"id"`
	DebtorMemberID   string `json:"debtor_member_id"`
	CreditorMemberID string `json:"creditor_member_id"`
	AmountCents      int64  `json:"amount_cents"`
	Status           string `json:"status"`
}

type transactionDetail struct {
	ID               string              `json:"id"`
	AmountCents      int64               `json:"amount_cents"`
	Currency         string              `json:"currency"`
	MerchantName     string              `json:"merchant_name,omitempty"`
	MerchantCategory string              `json:"merchant_category,omitempty"`
	Status           string              `json:"status"`
	CreatedAt        string              `json:"created_at"`
	UpdatedAt        string              `json:"updated_at"`
	Splits           []fundingPullDetail `json:"splits"`
	IOUs             []iouDetail         `json:"ious"`
}

// GetTransaction returns full detail for a single transaction.
//
// @Summary      Get transaction detail
// @Description  Returns a transaction with per-member funding results and any IOUs.
// @Tags         groups
// @Produce      json
// @Param        id    path string true "Group ID (UUID)"
// @Param        txnId path string true "Transaction ID (UUID)"
// @Success      200 {object} transactionDetail
// @Failure      400 {object} map[string]string
// @Failure      404 {object} map[string]string
// @Failure      500 {object} map[string]string
// @Router       /v1/groups/{id}/transactions/{txnId} [get]
func (h *Handler) GetTransaction(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	txnID, err := uuid.Parse(c.Param("txnId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid transaction_id"})
		return
	}

	var detail transactionDetail
	var createdAt, updatedAt time.Time
	err = h.db.QueryRowContext(c.Request.Context(), `
		SELECT id, amount_cents, currency,
		       COALESCE(merchant_name,''), COALESCE(merchant_category,''),
		       status, created_at, updated_at
		FROM transactions
		WHERE id = $1 AND group_id = $2`,
		txnID, groupID,
	).Scan(&detail.ID, &detail.AmountCents, &detail.Currency,
		&detail.MerchantName, &detail.MerchantCategory,
		&detail.Status, &createdAt, &updatedAt)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "transaction not found"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	detail.CreatedAt = createdAt.UTC().Format(time.RFC3339)
	detail.UpdatedAt = updatedAt.UTC().Format(time.RFC3339)

	// Load per-member funding pulls.
	splitRows, err := h.db.QueryContext(c.Request.Context(), `
		SELECT fp.member_id, m.display_name, fp.amount_cents, fp.funding_type, fp.status
		FROM funding_pulls fp
		JOIN members m ON m.id = fp.member_id
		WHERE fp.transaction_id = $1
		ORDER BY m.display_name ASC`,
		txnID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer splitRows.Close()

	detail.Splits = []fundingPullDetail{}
	for splitRows.Next() {
		var fp fundingPullDetail
		if err := splitRows.Scan(&fp.MemberID, &fp.DisplayName, &fp.AmountCents, &fp.FundingType, &fp.Status); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		detail.Splits = append(detail.Splits, fp)
	}

	// Load IOUs for this transaction.
	iouRows, err := h.db.QueryContext(c.Request.Context(), `
		SELECT id, debtor_member_id, creditor_member_id, amount_cents, status
		FROM iou_entries
		WHERE transaction_id = $1`,
		txnID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer iouRows.Close()

	detail.IOUs = []iouDetail{}
	for iouRows.Next() {
		var iou iouDetail
		if err := iouRows.Scan(&iou.ID, &iou.DebtorMemberID, &iou.CreditorMemberID, &iou.AmountCents, &iou.Status); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		detail.IOUs = append(detail.IOUs, iou)
	}

	c.JSON(http.StatusOK, detail)
}

// ── POST/DELETE/GET /v1/groups/:id/leader/authorize ───────────────────────────

type leaderAuthResponse struct {
	PreAuthorized bool    `json:"pre_authorized"`
	ExpiresAt     *string `json:"expires_at,omitempty"`
}

// SetLeaderAuthorization sets or clears leader pre-authorization.
//
// @Summary      Set leader pre-authorization
// @Description  Enables the leader cover fail-safe for the next 24 hours. Requires the caller to be the group leader.
// @Tags         groups
// @Produce      json
// @Param        id path string true "Group ID (UUID)"
// @Success      200 {object} leaderAuthResponse
// @Failure      403 {object} map[string]string
// @Router       /v1/groups/{id}/leader/authorize [post]
func (h *Handler) SetLeaderAuthorization(c *gin.Context) {
	memberIDRaw, ok := c.Get("member_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	mid, ok := memberIDRaw.(string)
	if !ok || mid == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	_, err := h.db.ExecContext(c.Request.Context(), `
		UPDATE members
		SET leader_pre_authorized    = true,
		    leader_pre_authorized_at = NOW(),
		    updated_at               = NOW()
		WHERE id = $1`, mid,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	expiresAt := time.Now().UTC().Add(24 * time.Hour).Format(time.RFC3339)
	c.JSON(http.StatusOK, leaderAuthResponse{PreAuthorized: true, ExpiresAt: &expiresAt})
}

// ClearLeaderAuthorization revokes leader pre-authorization.
//
// @Summary      Revoke leader pre-authorization
// @Description  Disables leader cover immediately.
// @Tags         groups
// @Produce      json
// @Param        id path string true "Group ID (UUID)"
// @Success      200 {object} leaderAuthResponse
// @Router       /v1/groups/{id}/leader/authorize [delete]
func (h *Handler) ClearLeaderAuthorization(c *gin.Context) {
	memberIDRaw, ok := c.Get("member_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	mid, ok := memberIDRaw.(string)
	if !ok || mid == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	_, err := h.db.ExecContext(c.Request.Context(), `
		UPDATE members
		SET leader_pre_authorized = false,
		    updated_at            = NOW()
		WHERE id = $1`, mid,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	c.JSON(http.StatusOK, leaderAuthResponse{PreAuthorized: false})
}

// GetLeaderAuthorization returns the current pre-authorization status.
//
// @Summary      Get leader pre-authorization status
// @Description  Returns whether the leader has pre-authorized and when it expires.
// @Tags         groups
// @Produce      json
// @Param        id path string true "Group ID (UUID)"
// @Success      200 {object} leaderAuthResponse
// @Router       /v1/groups/{id}/leader/authorize [get]
func (h *Handler) GetLeaderAuthorization(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}

	var authorized bool
	var authorizedAt sql.NullTime
	err = h.db.QueryRowContext(c.Request.Context(), `
		SELECT leader_pre_authorized, leader_pre_authorized_at
		FROM members
		WHERE group_id = $1 AND is_leader = true
		LIMIT 1`,
		groupID,
	).Scan(&authorized, &authorizedAt)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "leader not found"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	resp := leaderAuthResponse{PreAuthorized: authorized}
	if authorized && authorizedAt.Valid {
		expiresAt := authorizedAt.Time.UTC().Add(24 * time.Hour)
		if time.Now().UTC().Before(expiresAt) {
			s := expiresAt.Format(time.RFC3339)
			resp.ExpiresAt = &s
		} else {
			// Auth window has elapsed — clear the flag in DB so future queries
			// don't load an expired authorization (e.g. in settlement worker).
			h.db.ExecContext(c.Request.Context(), `
				UPDATE members
				SET leader_pre_authorized = false, updated_at = NOW()
				WHERE group_id = $1 AND is_leader = true AND leader_pre_authorized = true`,
				groupID) //nolint:errcheck
			resp.PreAuthorized = false
		}
	}

	c.JSON(http.StatusOK, resp)
}

// ── GET /v1/groups/:id/ious ───────────────────────────────────────────────────

type iouSummary struct {
	ID               string `json:"id"`
	DebtorMemberID   string `json:"debtor_member_id"`
	DebtorName       string `json:"debtor_name"`
	CreditorMemberID string `json:"creditor_member_id"`
	CreditorName     string `json:"creditor_name"`
	TransactionID    string `json:"transaction_id"`
	AmountCents      int64  `json:"amount_cents"`
	Status           string `json:"status"`
	CreatedAt        string `json:"created_at"`
}

// ListIOUs returns outstanding IOUs for the group.
//
// @Summary      List IOUs
// @Description  Returns all outstanding IOUs for the group.
// @Tags         groups
// @Produce      json
// @Param        id path string true "Group ID (UUID)"
// @Success      200 {object} map[string][]iouSummary
// @Router       /v1/groups/{id}/ious [get]
func (h *Handler) ListIOUs(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}

	rows, err := h.db.QueryContext(c.Request.Context(), `
		SELECT i.id, i.debtor_member_id, d.display_name,
		       i.creditor_member_id, cr.display_name,
		       i.transaction_id, i.amount_cents, i.status, i.created_at
		FROM iou_entries i
		JOIN members d  ON d.id  = i.debtor_member_id
		JOIN members cr ON cr.id = i.creditor_member_id
		JOIN transactions t ON t.id = i.transaction_id
		WHERE t.group_id = $1
		ORDER BY i.created_at DESC`,
		groupID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	ious := []iouSummary{}
	for rows.Next() {
		var i iouSummary
		var createdAt time.Time
		if err := rows.Scan(&i.ID, &i.DebtorMemberID, &i.DebtorName,
			&i.CreditorMemberID, &i.CreditorName,
			&i.TransactionID, &i.AmountCents, &i.Status, &createdAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "scan failed"})
			return
		}
		i.CreatedAt = createdAt.UTC().Format(time.RFC3339)
		ious = append(ious, i)
	}

	c.JSON(http.StatusOK, gin.H{"ious": ious})
}

// ── POST /v1/groups/:id/ious/:iouId/settle ────────────────────────────────────

// SettleIOU marks an IOU as settled. Caller must be the debtor or creditor.
//
// @Summary      Settle an IOU
// @Description  Marks an IOU as settled. Requires the caller to be the debtor or creditor of the IOU.
// @Tags         groups
// @Produce      json
// @Param        id    path string true "Group ID (UUID)"
// @Param        iouId path string true "IOU ID (UUID)"
// @Success      200 {object} map[string]string
// @Failure      403 {object} map[string]string
// @Failure      404 {object} map[string]string
// @Router       /v1/groups/{id}/ious/{iouId}/settle [post]
func (h *Handler) SettleIOU(c *gin.Context) {
	iouID, err := uuid.Parse(c.Param("iouId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid iou_id"})
		return
	}

	callerMemberIDRaw, ok := c.Get("member_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	mid, ok := callerMemberIDRaw.(string)
	if !ok || mid == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}

	// Verify the caller is the debtor or creditor.
	var debtorID, creditorID string
	err = h.db.QueryRowContext(c.Request.Context(),
		`SELECT debtor_member_id, creditor_member_id FROM iou_entries WHERE id = $1`,
		iouID,
	).Scan(&debtorID, &creditorID)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "iou not found"})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	if mid != debtorID && mid != creditorID {
		c.JSON(http.StatusForbidden, gin.H{"error": "not authorized to settle this IOU"})
		return
	}

	_, err = h.db.ExecContext(c.Request.Context(), `
		UPDATE iou_entries
		SET status = 'SETTLED', updated_at = NOW()
		WHERE id = $1 AND status = 'OUTSTANDING'`,
		iouID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"status": "settled"})
}
