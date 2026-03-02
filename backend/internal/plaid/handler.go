package plaid

import (
	"database/sql"
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"
)

// Handler handles the Plaid bank-linking endpoints.
type Handler struct {
	db          *sql.DB
	plaidClient LinkClient
}

// NewHandler creates a Plaid Handler.
func NewHandler(db *sql.DB, plaidClient LinkClient) *Handler {
	return &Handler{db: db, plaidClient: plaidClient}
}

// ── POST /v1/plaid/link-token ─────────────────────────────────────────────────

type createLinkTokenResponse struct {
	LinkToken string `json:"link_token"`
}

// CreateLinkToken creates a Plaid Link token for the authenticated user.
// The iOS app passes this token directly to the Plaid Link SDK.
func (h *Handler) CreateLinkToken(c *gin.Context) {
	clerkUserID, ok := c.Get("clerk_user_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	userID, _ := clerkUserID.(string)

	token, err := h.plaidClient.CreateLinkToken(c.Request.Context(), userID)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "plaid link token failed", "error", err, "user_id", userID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not create link token"})
		return
	}

	c.JSON(http.StatusOK, createLinkTokenResponse{LinkToken: token})
}

// ── POST /v1/plaid/exchange-token ─────────────────────────────────────────────

type exchangeTokenRequest struct {
	GroupID     string `json:"group_id"     binding:"required"`
	PublicToken string `json:"public_token" binding:"required"`
	AccountID   string `json:"account_id"   binding:"required"`
	IsBackup    bool   `json:"is_backup"`
}

type exchangeTokenResponse struct {
	AccountID string `json:"account_id"`
	Name      string `json:"name"`
	Mask      string `json:"mask"`
	Type      string `json:"type"`
	Subtype   string `json:"subtype"`
}

// ExchangeToken exchanges a Plaid public token for a durable access token and
// stores it on the member record for the given group.
func (h *Handler) ExchangeToken(c *gin.Context) {
	clerkUserID, ok := c.Get("clerk_user_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	userID, _ := clerkUserID.(string)

	var req exchangeTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify the caller is a member of the requested group.
	var memberID string
	err := h.db.QueryRowContext(c.Request.Context(),
		`SELECT id FROM members WHERE group_id = $1 AND user_id = $2`,
		req.GroupID, userID,
	).Scan(&memberID)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	// Exchange the short-lived public token.
	accessToken, itemID, err := h.plaidClient.ExchangePublicToken(c.Request.Context(), req.PublicToken)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "plaid exchange failed", "error", err, "member_id", memberID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "token exchange failed"})
		return
	}

	// Verify the account_id exists in the linked item.
	accounts, err := h.plaidClient.GetAccounts(c.Request.Context(), accessToken)
	if err != nil {
		slog.ErrorContext(c.Request.Context(), "plaid get accounts failed", "error", err, "member_id", memberID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not fetch accounts"})
		return
	}

	var matched *LinkedAccount
	for i := range accounts {
		if accounts[i].AccountID == req.AccountID {
			matched = &accounts[i]
			break
		}
	}
	if matched == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "account_id not found in linked item"})
		return
	}

	// Persist the token to the correct columns based on is_backup.
	var query string
	if req.IsBackup {
		query = `UPDATE members
			SET backup_plaid_access_token = $1,
			    backup_plaid_account_id   = $2,
			    backup_plaid_item_id      = $3
			WHERE id = $4`
	} else {
		query = `UPDATE members
			SET plaid_access_token = $1,
			    plaid_account_id   = $2,
			    plaid_item_id      = $3
			WHERE id = $4`
	}

	if _, err := h.db.ExecContext(c.Request.Context(), query,
		accessToken, matched.AccountID, itemID, memberID,
	); err != nil {
		slog.ErrorContext(c.Request.Context(), "plaid token store failed", "error", err, "member_id", memberID)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not save account"})
		return
	}

	slog.InfoContext(c.Request.Context(), "plaid account linked",
		"member_id", memberID, "account_mask", matched.Mask, "is_backup", req.IsBackup)

	c.JSON(http.StatusOK, exchangeTokenResponse{
		AccountID: matched.AccountID,
		Name:      matched.Name,
		Mask:      matched.Mask,
		Type:      matched.Type,
		Subtype:   matched.Subtype,
	})
}

// ── GET /v1/plaid/accounts ────────────────────────────────────────────────────

type linkedAccountResponse struct {
	AccountID    string `json:"account_id"`
	Name         string `json:"name"`
	Mask         string `json:"mask"`
	Type         string `json:"type"`
	Subtype      string `json:"subtype"`
	BalanceCents int64  `json:"balance_cents"`
	IsBackup     bool   `json:"is_backup"`
}

// ListAccounts returns all bank accounts linked for the caller in a given group.
func (h *Handler) ListAccounts(c *gin.Context) {
	clerkUserID, ok := c.Get("clerk_user_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	userID, _ := clerkUserID.(string)

	groupID := c.Query("group_id")
	if groupID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "group_id query param required"})
		return
	}

	var primaryToken, primaryAccountID, backupToken, backupAccountID sql.NullString
	err := h.db.QueryRowContext(c.Request.Context(), `
		SELECT plaid_access_token, plaid_account_id,
		       backup_plaid_access_token, backup_plaid_account_id
		FROM members
		WHERE group_id = $1 AND user_id = $2`,
		groupID, userID,
	).Scan(&primaryToken, &primaryAccountID, &backupToken, &backupAccountID)
	if err == sql.ErrNoRows {
		c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}

	result := []linkedAccountResponse{}

	// Fetch primary bank accounts.
	if primaryToken.Valid && primaryAccountID.Valid {
		accounts, err := h.plaidClient.GetAccounts(c.Request.Context(), primaryToken.String)
		if err != nil {
			slog.WarnContext(c.Request.Context(), "plaid primary accounts fetch failed", "error", err)
		} else {
			for _, acct := range accounts {
				if acct.AccountID == primaryAccountID.String {
					result = append(result, linkedAccountResponse{
						AccountID:    acct.AccountID,
						Name:         acct.Name,
						Mask:         acct.Mask,
						Type:         acct.Type,
						Subtype:      acct.Subtype,
						BalanceCents: acct.BalanceCents,
						IsBackup:     false,
					})
					break
				}
			}
		}
	}

	// Fetch backup bank accounts.
	if backupToken.Valid && backupAccountID.Valid {
		accounts, err := h.plaidClient.GetAccounts(c.Request.Context(), backupToken.String)
		if err != nil {
			slog.WarnContext(c.Request.Context(), "plaid backup accounts fetch failed", "error", err)
		} else {
			for _, acct := range accounts {
				if acct.AccountID == backupAccountID.String {
					result = append(result, linkedAccountResponse{
						AccountID:    acct.AccountID,
						Name:         acct.Name,
						Mask:         acct.Mask,
						Type:         acct.Type,
						Subtype:      acct.Subtype,
						BalanceCents: acct.BalanceCents,
						IsBackup:     true,
					})
					break
				}
			}
		}
	}

	c.JSON(http.StatusOK, gin.H{"accounts": result})
}

// ── DELETE /v1/plaid/accounts ─────────────────────────────────────────────────

// UnlinkAccount removes a linked bank account from the member record.
// Pass ?group_id=xxx&is_backup=true to remove the backup account.
func (h *Handler) UnlinkAccount(c *gin.Context) {
	clerkUserID, ok := c.Get("clerk_user_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	userID, _ := clerkUserID.(string)

	groupID := c.Query("group_id")
	if groupID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "group_id query param required"})
		return
	}
	isBackup := c.Query("is_backup") == "true"

	var query string
	if isBackup {
		query = `UPDATE members
			SET backup_plaid_access_token = NULL,
			    backup_plaid_account_id   = NULL,
			    backup_plaid_item_id      = NULL
			WHERE group_id = $1 AND user_id = $2`
	} else {
		query = `UPDATE members
			SET plaid_access_token = NULL,
			    plaid_account_id   = NULL,
			    plaid_item_id      = NULL
			WHERE group_id = $1 AND user_id = $2`
	}

	result, err := h.db.ExecContext(c.Request.Context(), query, groupID, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error"})
		return
	}
	rows, _ := result.RowsAffected()
	if rows == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
		return
	}

	slog.InfoContext(c.Request.Context(), "plaid account unlinked",
		"user_id", userID, "group_id", groupID, "is_backup", isBackup)
	c.Status(http.StatusNoContent)
}
