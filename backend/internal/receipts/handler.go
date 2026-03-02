package receipts

import (
	"fmt"
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
	parser      ParserConfig
	maxInputLen int
}

// NewHandler returns a Handler configured with default parsing rules.
func NewHandler() *Handler {
	return &Handler{
		parser:      DefaultConfig(),
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

	result := h.parser.Parse(req.RawText)

	c.JSON(http.StatusOK, parseResponse{
		Data: result,
		Meta: responseMeta{
			RequestID: uuid.New().String(),
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		},
	})
}
