// Package paysession implements HTTP handlers for payment session management.
//
// A payment session represents a group bill-splitting event. Members create a
// session, assign splits, confirm their shares, and the leader approves.
// Once approved the session can be "tapped" (simulated or real) to run the
// same JIT authorization + ledger posting flow used by real card swipes.
package paysession

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/tally/backend/internal/ledger"
	"github.com/tally/backend/internal/middleware"
	"github.com/tally/backend/internal/waterfall"
)

// ── Request / Response types ────────────────────────────────────────────────

type createSessionRequest struct {
	TotalCents     int64  `json:"total_cents" binding:"required,gt=0"`
	Currency       string `json:"currency"`
	SplitMethod    string `json:"split_method"`
	MerchantName   string `json:"merchant_name"`
	AssignmentMode string `json:"assignment_mode"`
}

type sessionResponse struct {
	ID             string          `json:"id"`
	GroupID        string          `json:"group_id"`
	TotalCents     int64           `json:"total_cents"`
	Currency       string          `json:"currency"`
	SplitMethod    string          `json:"split_method"`
	AssignmentMode string          `json:"assignment_mode"`
	Status         string          `json:"status"`
	MerchantName   string          `json:"merchant_name,omitempty"`
	ArmedAt        string          `json:"armed_at,omitempty"`
	ExpiresAt      string          `json:"expires_at"`
	TransactionID  string          `json:"transaction_id,omitempty"`
	CreatedAt      string          `json:"created_at"`
	Splits         []splitResponse `json:"splits,omitempty"`
}

type splitResponse struct {
	MemberID      string `json:"member_id"`
	DisplayName   string `json:"display_name"`
	AmountCents   int64  `json:"amount_cents"`
	TipCents      int64  `json:"tip_cents"`
	FundingSource string `json:"funding_source"`
	Confirmed     bool   `json:"confirmed"`
}

type setSplitsRequest struct {
	Splits []splitInput `json:"splits" binding:"required"`
}

type splitInput struct {
	MemberID      string `json:"member_id" binding:"required"`
	AmountCents   int64  `json:"amount_cents" binding:"gte=0"`
	TipCents      int64  `json:"tip_cents"`
	FundingSource string `json:"funding_source"`
}

type updateSessionRequest struct {
	TotalCents     *int64  `json:"total_cents"`
	MerchantName   *string `json:"merchant_name"`
	Status         *string `json:"status"`
	SplitMethod    *string `json:"split_method"`
	AssignmentMode *string `json:"assignment_mode"`
}

type simulateTapResponse struct {
	Decision      string `json:"decision"`
	TransactionID string `json:"transaction_id,omitempty"`
	Reason        string `json:"reason,omitempty"`
}

// ── Handler ─────────────────────────────────────────────────────────────────

// Handler handles payment session routes.
type Handler struct {
	db *sql.DB
}

func NewHandler(db *sql.DB) *Handler {
	return &Handler{db: db}
}

// terminalStatuses are session states from which no further transitions are allowed.
var terminalStatuses = map[string]bool{
	"completed": true,
	"cancelled": true,
	"expired":   true,
}

// validTransitions defines the allowed status transitions for a payment session.
var validTransitions = map[string]map[string]bool{
	"draft": {
		"splitting":  true,
		"cancelled":  true,
	},
	"splitting": {
		"confirming": true,
		"ready":      true,
		"cancelled":  true,
	},
	"confirming": {
		"ready":      true,
		"cancelled":  true,
	},
	"ready": {
		"completed":  true,
		"cancelled":  true,
		"splitting":  true,
	},
}

// ── POST /v1/groups/:id/sessions ────────────────────────────────────────────

// CreateSession creates a new payment session for a group.
func (h *Handler) CreateSession(c *gin.Context) {
	clerkUserID, ok := c.Get(middleware.ClerkUserIDKey)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	userID, ok := clerkUserID.(string)
	if !ok || userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
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

	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}

	var req createSessionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	currency := req.Currency
	if currency == "" {
		currency = "USD"
	}
	splitMethod := req.SplitMethod
	if splitMethod == "" {
		splitMethod = "equal"
	}
	assignmentMode := req.AssignmentMode
	if assignmentMode == "" {
		assignmentMode = "auto"
	}

	sessionID := uuid.New()
	now := time.Now().UTC()
	expiresAt := now.Add(24 * time.Hour)

	var createdAt time.Time
	if err := h.db.QueryRowContext(c.Request.Context(), `
		INSERT INTO payment_sessions
			(id, group_id, created_by_user_id, created_by_member_id, total_cents, currency,
			 split_method, assignment_mode, status, merchant_name, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'draft', $9, $10)
		RETURNING created_at`,
		sessionID, groupID, userID, memberID, req.TotalCents, currency,
		splitMethod, assignmentMode, req.MerchantName, expiresAt,
	).Scan(&createdAt); err != nil {
		slog.ErrorContext(c.Request.Context(), "create payment session failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	slog.InfoContext(c.Request.Context(), "payment session created",
		"session_id", sessionID, "group_id", groupID, "member_id", memberID)

	c.JSON(http.StatusCreated, sessionResponse{
		ID:             sessionID.String(),
		GroupID:        groupID.String(),
		TotalCents:     req.TotalCents,
		Currency:       currency,
		SplitMethod:    splitMethod,
		AssignmentMode: assignmentMode,
		Status:         "draft",
		MerchantName:   req.MerchantName,
		ExpiresAt:      expiresAt.Format(time.RFC3339),
		CreatedAt:      createdAt.UTC().Format(time.RFC3339),
	})
}

// ── GET /v1/groups/:id/sessions/active ──────────────────────────────────────

// GetActiveSession finds the first non-terminal session for this group.
func (h *Handler) GetActiveSession(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}

	var s sessionResponse
	var createdAt time.Time
	var expiresAt time.Time
	var armedAt sql.NullTime
	var transactionID sql.NullString
	var merchantName sql.NullString

	err = h.db.QueryRowContext(c.Request.Context(), `
		SELECT id, group_id, total_cents, currency, split_method, assignment_mode,
		       status, merchant_name, armed_at, expires_at, transaction_id, created_at
		FROM payment_sessions
		WHERE group_id = $1 AND status NOT IN ('completed','cancelled','expired')
		ORDER BY created_at DESC
		LIMIT 1`,
		groupID,
	).Scan(&s.ID, &s.GroupID, &s.TotalCents, &s.Currency, &s.SplitMethod,
		&s.AssignmentMode, &s.Status, &merchantName, &armedAt, &expiresAt,
		&transactionID, &createdAt)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "no active session"})
		return
	}
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "query active session failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	if merchantName.Valid {
		s.MerchantName = merchantName.String
	}
	if armedAt.Valid {
		s.ArmedAt = armedAt.Time.UTC().Format(time.RFC3339)
	}
	s.ExpiresAt = expiresAt.UTC().Format(time.RFC3339)
	if transactionID.Valid {
		s.TransactionID = transactionID.String
	}
	s.CreatedAt = createdAt.UTC().Format(time.RFC3339)

	// Load splits for the active session.
	s.Splits, err = h.loadSplits(c, s.ID)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "load splits failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	c.JSON(http.StatusOK, s)
}

// ── GET /v1/groups/:id/sessions/:sessionId ──────────────────────────────────

// GetSession returns session detail with splits.
func (h *Handler) GetSession(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	sessionID, err := uuid.Parse(c.Param("sessionId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session_id"})
		return
	}

	var s sessionResponse
	var createdAt time.Time
	var expiresAt time.Time
	var armedAt sql.NullTime
	var transactionID sql.NullString
	var merchantName sql.NullString

	err = h.db.QueryRowContext(c.Request.Context(), `
		SELECT id, group_id, total_cents, currency, split_method, assignment_mode,
		       status, merchant_name, armed_at, expires_at, transaction_id, created_at
		FROM payment_sessions
		WHERE id = $1 AND group_id = $2`,
		sessionID, groupID,
	).Scan(&s.ID, &s.GroupID, &s.TotalCents, &s.Currency, &s.SplitMethod,
		&s.AssignmentMode, &s.Status, &merchantName, &armedAt, &expiresAt,
		&transactionID, &createdAt)

	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "session not found"})
		return
	}
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "query session failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	if merchantName.Valid {
		s.MerchantName = merchantName.String
	}
	if armedAt.Valid {
		s.ArmedAt = armedAt.Time.UTC().Format(time.RFC3339)
	}
	s.ExpiresAt = expiresAt.UTC().Format(time.RFC3339)
	if transactionID.Valid {
		s.TransactionID = transactionID.String
	}
	s.CreatedAt = createdAt.UTC().Format(time.RFC3339)

	// Load splits with member display names.
	s.Splits, err = h.loadSplits(c, s.ID)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "load splits failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	c.JSON(http.StatusOK, s)
}

// ── PATCH /v1/groups/:id/sessions/:sessionId ────────────────────────────────

// UpdateSession updates mutable fields on a payment session.
func (h *Handler) UpdateSession(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	sessionID, err := uuid.Parse(c.Param("sessionId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session_id"})
		return
	}

	var req updateSessionRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Fetch current status to validate transitions.
	var currentStatus string
	err = h.db.QueryRowContext(c.Request.Context(),
		`SELECT status FROM payment_sessions WHERE id = $1 AND group_id = $2`,
		sessionID, groupID,
	).Scan(&currentStatus)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "session not found"})
		return
	}
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "query session status failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	if terminalStatuses[currentStatus] {
		c.JSON(http.StatusConflict, gin.H{"error": "session is in terminal state"})
		return
	}

	// Validate status transition if a new status is provided.
	if req.Status != nil {
		allowed, exists := validTransitions[currentStatus]
		if !exists || !allowed[*req.Status] {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": fmt.Sprintf("invalid status transition from '%s' to '%s'", currentStatus, *req.Status),
			})
			return
		}
	}

	// Build the dynamic UPDATE query.
	query := "UPDATE payment_sessions SET updated_at = NOW()"
	args := []interface{}{}
	argIdx := 1

	if req.TotalCents != nil {
		query += fmt.Sprintf(", total_cents = $%d", argIdx)
		args = append(args, *req.TotalCents)
		argIdx++
	}
	if req.MerchantName != nil {
		query += fmt.Sprintf(", merchant_name = $%d", argIdx)
		args = append(args, *req.MerchantName)
		argIdx++
	}
	if req.Status != nil {
		query += fmt.Sprintf(", status = $%d", argIdx)
		args = append(args, *req.Status)
		argIdx++
	}
	if req.SplitMethod != nil {
		query += fmt.Sprintf(", split_method = $%d", argIdx)
		args = append(args, *req.SplitMethod)
		argIdx++
	}
	if req.AssignmentMode != nil {
		query += fmt.Sprintf(", assignment_mode = $%d", argIdx)
		args = append(args, *req.AssignmentMode)
		argIdx++
	}

	query += fmt.Sprintf(" WHERE id = $%d AND group_id = $%d", argIdx, argIdx+1)
	args = append(args, sessionID, groupID)

	if _, err := h.db.ExecContext(c.Request.Context(), query, args...); err != nil {
		slog.ErrorContext(c.Request.Context(), "update session failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	slog.InfoContext(c.Request.Context(), "payment session updated",
		"session_id", sessionID, "group_id", groupID)

	// Return the updated session.
	h.returnSession(c, sessionID, groupID)
}

// ── DELETE /v1/groups/:id/sessions/:sessionId ───────────────────────────────

// CancelSession sets a session's status to 'cancelled'.
func (h *Handler) CancelSession(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	sessionID, err := uuid.Parse(c.Param("sessionId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session_id"})
		return
	}

	var currentStatus string
	err = h.db.QueryRowContext(c.Request.Context(),
		`SELECT status FROM payment_sessions WHERE id = $1 AND group_id = $2`,
		sessionID, groupID,
	).Scan(&currentStatus)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "session not found"})
		return
	}
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "query session status failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	if currentStatus == "completed" {
		c.JSON(http.StatusConflict, gin.H{"error": "cannot cancel a completed session"})
		return
	}
	if currentStatus == "cancelled" {
		c.JSON(http.StatusOK, gin.H{"status": "already cancelled"})
		return
	}

	if _, err := h.db.ExecContext(c.Request.Context(), `
		UPDATE payment_sessions SET status = 'cancelled', updated_at = NOW()
		WHERE id = $1 AND group_id = $2`,
		sessionID, groupID,
	); err != nil {
		slog.ErrorContext(c.Request.Context(), "cancel session failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	slog.InfoContext(c.Request.Context(), "payment session cancelled",
		"session_id", sessionID, "group_id", groupID)

	c.JSON(http.StatusOK, gin.H{"status": "cancelled"})
}

// ── POST /v1/groups/:id/sessions/:sessionId/splits ──────────────────────────

// SetSplits bulk upserts splits for a payment session.
func (h *Handler) SetSplits(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	sessionID, err := uuid.Parse(c.Param("sessionId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session_id"})
		return
	}

	var req setSplitsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify session exists and is not in a terminal state.
	var totalCents int64
	var currentStatus string
	err = h.db.QueryRowContext(c.Request.Context(),
		`SELECT total_cents, status FROM payment_sessions WHERE id = $1 AND group_id = $2`,
		sessionID, groupID,
	).Scan(&totalCents, &currentStatus)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "session not found"})
		return
	}
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "query session failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if terminalStatuses[currentStatus] {
		c.JSON(http.StatusConflict, gin.H{"error": "session is in terminal state"})
		return
	}

	// Validate that split amounts sum to total_cents.
	var splitSum int64
	for _, s := range req.Splits {
		splitSum += s.AmountCents + s.TipCents
	}
	if splitSum != totalCents {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":       "splits do not sum to total_cents",
			"split_sum":   splitSum,
			"total_cents": totalCents,
		})
		return
	}

	tx, err := h.db.BeginTx(c.Request.Context(), nil)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	defer tx.Rollback()

	for _, s := range req.Splits {
		memberID, err := uuid.Parse(s.MemberID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("invalid member_id: %s", s.MemberID)})
			return
		}

		fundingSource := s.FundingSource
		if fundingSource == "" {
			fundingSource = "card"
		}

		if _, err := tx.ExecContext(c.Request.Context(), `
			INSERT INTO payment_session_splits
				(session_id, member_id, amount_cents, tip_cents, funding_source)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (session_id, member_id) DO UPDATE
			SET amount_cents = EXCLUDED.amount_cents,
			    tip_cents = EXCLUDED.tip_cents,
			    funding_source = EXCLUDED.funding_source,
			    confirmed = false,
			    confirmed_at = NULL,
			    updated_at = NOW()`,
			sessionID, memberID, s.AmountCents, s.TipCents, fundingSource,
		); err != nil {
			slog.ErrorContext(c.Request.Context(), "upsert split failed", "error", err, "member_id", memberID)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
			return
		}
	}

	// Move session to 'splitting' if it was still in 'draft'.
	if _, err := tx.ExecContext(c.Request.Context(), `
		UPDATE payment_sessions SET status = 'splitting', updated_at = NOW()
		WHERE id = $1 AND status = 'draft'`,
		sessionID,
	); err != nil {
		slog.ErrorContext(c.Request.Context(), "update session status failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	if err := tx.Commit(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "commit failed"})
		return
	}

	slog.InfoContext(c.Request.Context(), "splits set",
		"session_id", sessionID, "split_count", len(req.Splits))

	// Return the full updated session (with splits embedded).
	h.returnSession(c, sessionID, groupID)
}

// ── POST /v1/groups/:id/sessions/:sessionId/confirm ─────────────────────────

// ConfirmSplit confirms the current member's split.
func (h *Handler) ConfirmSplit(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	sessionID, err := uuid.Parse(c.Param("sessionId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session_id"})
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

	// Verify session exists and belongs to this group.
	var currentStatus string
	err = h.db.QueryRowContext(c.Request.Context(),
		`SELECT status FROM payment_sessions WHERE id = $1 AND group_id = $2`,
		sessionID, groupID,
	).Scan(&currentStatus)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "session not found"})
		return
	}
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "query session failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	if terminalStatuses[currentStatus] {
		c.JSON(http.StatusConflict, gin.H{"error": "session is in terminal state"})
		return
	}

	result, err := h.db.ExecContext(c.Request.Context(), `
		UPDATE payment_session_splits
		SET confirmed = true, confirmed_at = NOW(), updated_at = NOW()
		WHERE session_id = $1 AND member_id = $2`,
		sessionID, memberID,
	)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "confirm split failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	rowsAffected, _ := result.RowsAffected()
	if rowsAffected == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "split not found for this member"})
		return
	}

	slog.InfoContext(c.Request.Context(), "split confirmed",
		"session_id", sessionID, "member_id", memberID)

	c.JSON(http.StatusOK, gin.H{"confirmed": true})
}

// ── POST /v1/groups/:id/sessions/:sessionId/approve ─────────────────────────

// ApproveSession arms a session for payment (leader only).
func (h *Handler) ApproveSession(c *gin.Context) {
	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	sessionID, err := uuid.Parse(c.Param("sessionId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session_id"})
		return
	}

	isLeaderRaw, ok := c.Get(middleware.IsLeaderKey)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	isLeader, ok := isLeaderRaw.(bool)
	if !ok || !isLeader {
		c.JSON(http.StatusForbidden, gin.H{"error": "leader access required"})
		return
	}

	var currentStatus string
	err = h.db.QueryRowContext(c.Request.Context(),
		`SELECT status FROM payment_sessions WHERE id = $1 AND group_id = $2`,
		sessionID, groupID,
	).Scan(&currentStatus)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "session not found"})
		return
	}
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "query session failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	if terminalStatuses[currentStatus] {
		c.JSON(http.StatusConflict, gin.H{"error": "session is in terminal state"})
		return
	}
	if currentStatus != "splitting" && currentStatus != "confirming" {
		c.JSON(http.StatusBadRequest, gin.H{"error": fmt.Sprintf("cannot approve session in '%s' state", currentStatus)})
		return
	}

	now := time.Now().UTC()
	armedAt := now
	expiresAt := now.Add(2 * time.Hour)

	if _, err := h.db.ExecContext(c.Request.Context(), `
		UPDATE payment_sessions
		SET status = 'ready', armed_at = $1, expires_at = $2, updated_at = NOW()
		WHERE id = $3 AND group_id = $4`,
		armedAt, expiresAt, sessionID, groupID,
	); err != nil {
		slog.ErrorContext(c.Request.Context(), "approve session failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db write failed"})
		return
	}

	slog.InfoContext(c.Request.Context(), "payment session approved",
		"session_id", sessionID, "group_id", groupID, "expires_at", expiresAt)

	h.returnSession(c, sessionID, groupID)
}

// ── POST /v1/groups/:id/sessions/:sessionId/simulate-tap ────────────────────

// SimulateTap simulates a card tap, mirroring the auth/jit.go Authorize flow.
func (h *Handler) SimulateTap(c *gin.Context) {
	ctx := c.Request.Context()

	groupID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid group_id"})
		return
	}
	sessionID, err := uuid.Parse(c.Param("sessionId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session_id"})
		return
	}

	log := slog.With("session_id", sessionID, "group_id", groupID)

	// ── Step 1: Validate session status ─────────────────────────────────────
	var status string
	var totalCents int64
	var currency string
	var merchantName sql.NullString
	var expiresAt time.Time
	err = h.db.QueryRowContext(ctx, `
		SELECT status, total_cents, currency, merchant_name, expires_at
		FROM payment_sessions
		WHERE id = $1 AND group_id = $2`,
		sessionID, groupID,
	).Scan(&status, &totalCents, &currency, &merchantName, &expiresAt)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, simulateTapResponse{Decision: "DECLINE", Reason: "session_not_found"})
		return
	}
	if err != nil {
		log.ErrorContext(ctx, "query session failed", "error", err)
		c.JSON(http.StatusInternalServerError, simulateTapResponse{Decision: "DECLINE", Reason: "internal_error"})
		return
	}

	if status != "ready" {
		c.JSON(http.StatusBadRequest, simulateTapResponse{
			Decision: "DECLINE",
			Reason:   fmt.Sprintf("session status is '%s', expected 'ready'", status),
		})
		return
	}

	// ── Step 2: Validate not expired ────────────────────────────────────────
	if time.Now().UTC().After(expiresAt) {
		// Mark session as expired.
		_, _ = h.db.ExecContext(ctx, `
			UPDATE payment_sessions SET status = 'expired', updated_at = NOW()
			WHERE id = $1`, sessionID)
		c.JSON(http.StatusBadRequest, simulateTapResponse{Decision: "DECLINE", Reason: "session_expired"})
		return
	}

	// ── Step 3: Look up a card_token for the group ──────────────────────────
	var cardToken string
	err = h.db.QueryRowContext(ctx, `
		SELECT card_token FROM members
		WHERE group_id = $1 AND card_token IS NOT NULL
		LIMIT 1`,
		groupID,
	).Scan(&cardToken)
	if err == sql.ErrNoRows {
		cardToken = fmt.Sprintf("sim_card_%s", groupID)
	} else if err != nil {
		log.ErrorContext(ctx, "query card_token failed", "error", err)
		c.JSON(http.StatusInternalServerError, simulateTapResponse{Decision: "DECLINE", Reason: "internal_error"})
		return
	}

	// ── Step 4: Generate idempotency key ────────────────────────────────────
	idempotencyKey := fmt.Sprintf("sim_tap_%s", sessionID)

	// ── Step 5: Create PENDING transaction ──────────────────────────────────
	txnID := uuid.New()
	merchant := ""
	if merchantName.Valid {
		merchant = merchantName.String
	}

	if _, err := h.db.ExecContext(ctx, `
		INSERT INTO transactions
			(id, group_id, idempotency_key, amount_cents, currency,
			 merchant_name, status, card_token)
		VALUES ($1, $2, $3, $4, $5, $6, 'PENDING', $7)`,
		txnID, groupID, idempotencyKey, totalCents, currency, merchant, cardToken,
	); err != nil {
		log.ErrorContext(ctx, "insert pending transaction failed", "error", err)
		c.JSON(http.StatusInternalServerError, simulateTapResponse{Decision: "DECLINE", Reason: "internal_error"})
		return
	}

	// ── Step 6: Try waterfall.ResolveCard, fall back to manual splits ───────
	var splits []ledger.SplitEntry
	var groupAccountID uuid.UUID

	_, members, gaID, resolveErr := waterfall.ResolveCard(ctx, h.db, cardToken)
	if resolveErr == nil && len(members) > 0 {
		groupAccountID = gaID
		var planErr error
		splits, planErr = waterfall.BuildFundingPlan(members, totalCents)
		if planErr != nil {
			log.ErrorContext(ctx, "funding plan from waterfall failed, falling back to session splits",
				"error", planErr)
			splits = nil // fall through to manual split building
		}
	}

	// ── Step 7: Fall back — build splits from payment_session_splits ────────
	if len(splits) == 0 {
		// Look up the group's clearing account.
		err = h.db.QueryRowContext(ctx, `
			SELECT id FROM accounts
			WHERE owner_id = $1 AND account_type = 'liability'`,
			groupID,
		).Scan(&groupAccountID)
		if err != nil {
			log.ErrorContext(ctx, "query group account failed", "error", err)
			h.declineTransaction(ctx, txnID)
			c.JSON(http.StatusInternalServerError, simulateTapResponse{Decision: "DECLINE", Reason: "no_group_account"})
			return
		}

		rows, err := h.db.QueryContext(ctx, `
			SELECT pss.member_id, pss.amount_cents, a.id AS account_id,
			       COALESCE(m.stripe_payment_method_id, 'pm_mock_sim') AS pm_id
			FROM payment_session_splits pss
			JOIN members m ON m.id = pss.member_id
			JOIN accounts a ON a.owner_id = m.id AND a.account_type = 'asset'
			WHERE pss.session_id = $1`, sessionID)
		if err != nil {
			log.ErrorContext(ctx, "query session splits failed", "error", err)
			h.declineTransaction(ctx, txnID)
			c.JSON(http.StatusInternalServerError, simulateTapResponse{Decision: "DECLINE", Reason: "internal_error"})
			return
		}
		defer rows.Close()

		for rows.Next() {
			var memberID uuid.UUID
			var amountCents int64
			var accountID uuid.UUID
			var pmID string

			if err := rows.Scan(&memberID, &amountCents, &accountID, &pmID); err != nil {
				log.ErrorContext(ctx, "scan split row failed", "error", err)
				h.declineTransaction(ctx, txnID)
				c.JSON(http.StatusInternalServerError, simulateTapResponse{Decision: "DECLINE", Reason: "internal_error"})
				return
			}

			splits = append(splits, ledger.SplitEntry{
				MemberID:    memberID,
				AccountID:   accountID,
				AmountCents: amountCents,
				FundingType: ledger.FundingDirectPull,
			})
		}
		if err := rows.Err(); err != nil {
			log.ErrorContext(ctx, "rows iteration error", "error", err)
			h.declineTransaction(ctx, txnID)
			c.JSON(http.StatusInternalServerError, simulateTapResponse{Decision: "DECLINE", Reason: "internal_error"})
			return
		}

		if len(splits) == 0 {
			log.ErrorContext(ctx, "no splits found for session")
			h.declineTransaction(ctx, txnID)
			c.JSON(http.StatusBadRequest, simulateTapResponse{Decision: "DECLINE", Reason: "no_splits"})
			return
		}
	}

	// ── Step 8: Atomically post PENDING journal entries ─────────────────────
	if err := ledger.PostPendingTransaction(ctx, h.db, txnID, groupAccountID, splits, nil); err != nil {
		log.ErrorContext(ctx, "ledger post failed", "error", err)
		h.declineTransaction(ctx, txnID)
		c.JSON(http.StatusInternalServerError, simulateTapResponse{Decision: "DECLINE", Reason: "ledger_error"})
		return
	}

	// ── Step 9: Update session → completed ──────────────────────────────────
	if _, err := h.db.ExecContext(ctx, `
		UPDATE payment_sessions
		SET status = 'completed', transaction_id = $1, updated_at = NOW()
		WHERE id = $2`,
		txnID, sessionID,
	); err != nil {
		log.ErrorContext(ctx, "update session to completed failed", "error", err)
		// Transaction was already approved in the ledger, so we don't decline it.
		// Just log the error; the session can be reconciled later.
	}

	log.InfoContext(ctx, "simulate-tap approved",
		"transaction_id", txnID,
		"amount_cents", totalCents,
		"split_count", len(splits),
	)

	c.JSON(http.StatusOK, simulateTapResponse{
		Decision:      "APPROVE",
		TransactionID: txnID.String(),
	})
}

// ── Helpers ─────────────────────────────────────────────────────────────────

// loadSplits fetches splits for a session with member display names.
func (h *Handler) loadSplits(c *gin.Context, sessionID string) ([]splitResponse, error) {
	rows, err := h.db.QueryContext(c.Request.Context(), `
		SELECT pss.member_id, COALESCE(m.display_name, '') AS display_name,
		       pss.amount_cents, pss.tip_cents,
		       COALESCE(pss.funding_source, 'card') AS funding_source,
		       pss.confirmed
		FROM payment_session_splits pss
		JOIN members m ON m.id = pss.member_id
		WHERE pss.session_id = $1
		ORDER BY m.display_name ASC`, sessionID)
	if err != nil {
		return nil, fmt.Errorf("query splits: %w", err)
	}
	defer rows.Close()

	splits := []splitResponse{}
	for rows.Next() {
		var s splitResponse
		if err := rows.Scan(&s.MemberID, &s.DisplayName, &s.AmountCents,
			&s.TipCents, &s.FundingSource, &s.Confirmed); err != nil {
			return nil, fmt.Errorf("scan split: %w", err)
		}
		splits = append(splits, s)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows error: %w", err)
	}

	return splits, nil
}

// returnSession fetches and returns a full session response. Used by endpoints
// that modify a session and want to return its updated state.
func (h *Handler) returnSession(c *gin.Context, sessionID, groupID uuid.UUID) {
	var s sessionResponse
	var createdAt time.Time
	var expiresAt time.Time
	var armedAt sql.NullTime
	var transactionID sql.NullString
	var merchantName sql.NullString

	err := h.db.QueryRowContext(c.Request.Context(), `
		SELECT id, group_id, total_cents, currency, split_method, assignment_mode,
		       status, merchant_name, armed_at, expires_at, transaction_id, created_at
		FROM payment_sessions
		WHERE id = $1 AND group_id = $2`,
		sessionID, groupID,
	).Scan(&s.ID, &s.GroupID, &s.TotalCents, &s.Currency, &s.SplitMethod,
		&s.AssignmentMode, &s.Status, &merchantName, &armedAt, &expiresAt,
		&transactionID, &createdAt)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "return session query failed", "error", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	if merchantName.Valid {
		s.MerchantName = merchantName.String
	}
	if armedAt.Valid {
		s.ArmedAt = armedAt.Time.UTC().Format(time.RFC3339)
	}
	s.ExpiresAt = expiresAt.UTC().Format(time.RFC3339)
	if transactionID.Valid {
		s.TransactionID = transactionID.String
	}
	s.CreatedAt = createdAt.UTC().Format(time.RFC3339)

	var splitErr error
	s.Splits, splitErr = h.loadSplits(c, s.ID)
	if splitErr != nil {
		slog.ErrorContext(c.Request.Context(), "load splits failed", "error", splitErr)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	c.JSON(http.StatusOK, s)
}

// declineTransaction marks a transaction as DECLINED in the database.
func (h *Handler) declineTransaction(ctx context.Context, txnID uuid.UUID) {
	_, err := h.db.ExecContext(ctx,
		`UPDATE transactions SET status = 'DECLINED', updated_at = NOW() WHERE id = $1`, txnID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to decline transaction", "transaction_id", txnID, "error", err)
	}
}
