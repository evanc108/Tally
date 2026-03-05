package receipts

import (
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type parseRequest struct {
	RawText  string `json:"raw_text" binding:"required"`
	CircleID string `json:"circle_id"`
}

type parseResponse struct {
	Data *ParsedReceipt `json:"data"`
	Meta responseMeta   `json:"meta"`
}

type responseMeta struct {
	RequestID string `json:"request_id"`
	Timestamp string `json:"timestamp"`
}

// Handler handles receipt parsing routes.
type Handler struct {
	gemini      *GeminiClient
	maxInputLen int
}

// NewHandler returns a Handler that uses Gemini for parsing.
func NewHandler(geminiAPIKey, geminiModel string) *Handler {
	return &Handler{
		gemini:      NewGeminiClient(geminiAPIKey, geminiModel),
		maxInputLen: 10000,
	}
}

// ParseReceipt parses raw OCR text into structured receipt line items.
//
// @Summary      Parse receipt text
// @Description  Accepts raw OCR text from a receipt photo and returns structured line items with subtotal, tax, tip, and total.
// @Tags         receipts
// @Accept       json
// @Produce      json
// @Param        body body parseRequest true "Receipt OCR text"
// @Success      200  {object} parseResponse
// @Failure      400  {object} map[string]string
// @Failure      401  {object} map[string]string
// @Failure      429  {object} map[string]string
// @Failure      503  {object} map[string]string
// @Router       /v1/receipts/parse [post]
func (h *Handler) ParseReceipt(c *gin.Context) {
	var req parseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if len(req.RawText) > h.maxInputLen {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": fmt.Sprintf("raw_text exceeds maximum length of %d characters", h.maxInputLen),
		})
		return
	}

	if req.CircleID != "" {
		if _, err := uuid.Parse(req.CircleID); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid circle_id"})
			return
		}
	}

	if !h.gemini.Available() {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "receipt parsing service not configured"})
		return
	}

	ctx := c.Request.Context()
	slog.InfoContext(ctx, "receipt parse request", "raw_text_len", len(req.RawText))

	result, err := h.gemini.ParseReceipt(ctx, req.RawText)
	if err != nil {
		slog.ErrorContext(ctx, "gemini parse failed", "error", err)
		if errors.Is(err, ErrRateLimited) {
			c.JSON(http.StatusTooManyRequests, gin.H{"error": "receipt parsing rate limited, please try again shortly"})
			return
		}
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "receipt parsing failed, please try again"})
		return
	}

	slog.InfoContext(ctx, "receipt parse result",
		"items", len(result.Items),
		"subtotal", result.SubtotalCents,
		"tax", result.TaxCents,
		"tip", result.TipCents,
		"total", result.TotalCents,
		"receipt_date", result.ReceiptDate,
		"merchant", result.MerchantName,
		"confidence", result.Confidence,
	)

	c.JSON(http.StatusOK, parseResponse{
		Data: result,
		Meta: responseMeta{
			RequestID: uuid.New().String(),
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		},
	})
}
