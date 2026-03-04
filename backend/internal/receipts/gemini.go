package receipts

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"time"
)

// ErrRateLimited is returned when the Gemini API returns 429.
var ErrRateLimited = errors.New("gemini rate limited")

// GeminiClient calls the Gemini API to parse receipt OCR text into structured data.
type GeminiClient struct {
	apiKey     string
	model      string
	httpClient *http.Client
}

// NewGeminiClient creates a client for the Gemini API.
// If model is empty, defaults to gemini-2.5-flash-lite (fastest, cheapest).
func NewGeminiClient(apiKey, model string) *GeminiClient {
	if model == "" {
		model = "gemini-2.5-flash-lite"
	}
	return &GeminiClient{
		apiKey: apiKey,
		model:  model,
		httpClient: &http.Client{
			Timeout: 15 * time.Second,
		},
	}
}

// Available reports whether a Gemini API key is configured.
func (g *GeminiClient) Available() bool {
	return g.apiKey != ""
}

const receiptPrompt = `You are an expert receipt parser. Extract structured data from OCR text of a receipt.

CRITICAL RULES — follow exactly:

ITEMS:
- Only include actual purchased products (food, drinks, goods).
- Each item has: name, quantity (default 1), unit_cents, total_cents.
- unit_cents = total_cents / quantity (integer division).
- NEVER include these as items: subtotal, tax, tip, gratuity, total, amount due, balance due, service charge, payment method, card numbers, change due, transaction lines.
- NEVER include percentage lines (e.g. "18%%", "18%% Grat") as items. Those are gratuity rates.
- If a line shows a percentage with a dollar amount (e.g. "18%% Grat $39.06"), the dollar amount is the tip, NOT an item.

SUMMARY FIELDS:
- subtotal_cents: sum of all purchased items BEFORE tax, tip, and gratuity. This is the food/goods total.
- tax_cents: sales tax, HST, GST, VAT, PST, QST, or any tax line. If multiple tax lines exist (e.g. "TIF 4.75%%" and "HST 13%%"), sum them.
- tip_cents: tip, gratuity, grat, service charge, auto-gratuity — the dollar amount, NOT the percentage.
- total_cents: the final amount due including everything.
- All monetary values in integer cents. $12.99 = 1299, $217.00 = 21700.
- If a field is not found, use 0.

DATE:
- receipt_date MUST be in ISO format: YYYY-MM-DD (e.g. "2015-08-16").
- Parse any date format into YYYY-MM-DD. Examples: "Aug16'15" → "2015-08-16", "03/01/2026" → "2026-03-01".
- If no date is found, use empty string.

MERCHANT:
- merchant_name: the restaurant or store name from the receipt header.
- OCR may fragment the name across lines (e.g. "RCHRIS", "TEAK HOUSE", "JTH'S/"). Reconstruct the full name (e.g. "Ruth's Chris Steak House").
- If unclear, use empty string.

OCR Text:
---
%s
---`

// geminiRequest is the Gemini API request body.
type geminiRequest struct {
	Contents         []geminiContent  `json:"contents"`
	GenerationConfig geminiGenConfig  `json:"generationConfig"`
}

type geminiContent struct {
	Parts []geminiPart `json:"parts"`
}

type geminiPart struct {
	Text string `json:"text"`
}

type geminiGenConfig struct {
	ResponseMimeType string      `json:"responseMimeType"`
	ResponseSchema   interface{} `json:"responseSchema"`
	Temperature      float64     `json:"temperature"`
}

// geminiResponse is the Gemini API response body.
type geminiResponse struct {
	Candidates []struct {
		Content struct {
			Parts []struct {
				Text string `json:"text"`
			} `json:"parts"`
		} `json:"content"`
	} `json:"candidates"`
	Error *struct {
		Message string `json:"message"`
		Code    int    `json:"code"`
	} `json:"error"`
}

// geminiParsedReceipt is the schema we ask Gemini to return.
type geminiParsedReceipt struct {
	MerchantName  string            `json:"merchant_name"`
	ReceiptDate   string            `json:"receipt_date"`
	Items         []geminiItem      `json:"items"`
	SubtotalCents int64             `json:"subtotal_cents"`
	TaxCents      int64             `json:"tax_cents"`
	TipCents      int64             `json:"tip_cents"`
	TotalCents    int64             `json:"total_cents"`
}

type geminiItem struct {
	Name       string `json:"name"`
	Quantity   int    `json:"quantity"`
	UnitCents  int64  `json:"unit_cents"`
	TotalCents int64  `json:"total_cents"`
}

// responseSchema is the JSON schema passed to Gemini for structured output.
var responseSchema = map[string]interface{}{
	"type": "object",
	"properties": map[string]interface{}{
		"merchant_name": map[string]interface{}{"type": "string"},
		"receipt_date":  map[string]interface{}{"type": "string"},
		"items": map[string]interface{}{
			"type": "array",
			"items": map[string]interface{}{
				"type": "object",
				"properties": map[string]interface{}{
					"name":        map[string]interface{}{"type": "string"},
					"quantity":    map[string]interface{}{"type": "integer"},
					"unit_cents":  map[string]interface{}{"type": "integer"},
					"total_cents": map[string]interface{}{"type": "integer"},
				},
				"required": []string{"name", "quantity", "unit_cents", "total_cents"},
			},
		},
		"subtotal_cents": map[string]interface{}{"type": "integer"},
		"tax_cents":      map[string]interface{}{"type": "integer"},
		"tip_cents":      map[string]interface{}{"type": "integer"},
		"total_cents":    map[string]interface{}{"type": "integer"},
	},
	"required": []string{"items", "subtotal_cents", "tax_cents", "tip_cents", "total_cents"},
}

// ParseReceipt sends OCR text to Gemini and returns a ParsedReceipt.
// Retries up to 3 times on transient errors (429, 5xx) with exponential backoff + jitter.
func (g *GeminiClient) ParseReceipt(ctx context.Context, rawText string) (*ParsedReceipt, error) {
	if g.apiKey == "" {
		return nil, fmt.Errorf("gemini API key not configured")
	}

	reqBody := geminiRequest{
		Contents: []geminiContent{
			{
				Parts: []geminiPart{
					{Text: fmt.Sprintf(receiptPrompt, rawText)},
				},
			},
		},
		GenerationConfig: geminiGenConfig{
			ResponseMimeType: "application/json",
			ResponseSchema:   responseSchema,
			Temperature:      0.1,
		},
	}

	bodyBytes, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	const maxRetries = 3
	var lastErr error
	for attempt := range maxRetries {
		if attempt > 0 {
			backoff := time.Duration(1<<uint(attempt-1)) * time.Second
			jitter := time.Duration(rand.Int64N(int64(backoff / 2)))
			select {
			case <-ctx.Done():
				return nil, fmt.Errorf("context cancelled during retry: %w", ctx.Err())
			case <-time.After(backoff + jitter):
			}
			slog.WarnContext(ctx, "retrying gemini request", "attempt", attempt+1, "prev_error", lastErr)
		}

		result, err := g.doGeminiRequest(ctx, bodyBytes)
		if err == nil {
			return result, nil
		}
		if !errors.Is(err, ErrRateLimited) && !isTransient(err) {
			return nil, err
		}
		lastErr = err
	}

	return nil, fmt.Errorf("gemini request failed after %d attempts: %w", maxRetries, lastErr)
}

// isTransient reports whether an error indicates a retryable server-side failure.
func isTransient(err error) bool {
	var se *statusError
	return errors.As(err, &se) && se.code >= 500
}

// statusError wraps an HTTP status code for error classification.
type statusError struct {
	code int
	msg  string
}

func (e *statusError) Error() string { return e.msg }

// doGeminiRequest performs a single Gemini API call.
func (g *GeminiClient) doGeminiRequest(ctx context.Context, bodyBytes []byte) (*ParsedReceipt, error) {
	url := fmt.Sprintf(
		"https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s",
		g.model, g.apiKey,
	)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(bodyBytes))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	start := time.Now()
	resp, err := g.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("gemini request failed: %w", err)
	}
	defer resp.Body.Close()

	respBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response: %w", err)
	}
	latency := time.Since(start)

	if resp.StatusCode == http.StatusTooManyRequests {
		return nil, fmt.Errorf("gemini API rate limited: %w", ErrRateLimited)
	}
	if resp.StatusCode != http.StatusOK {
		slog.ErrorContext(ctx, "gemini API error", "status", resp.StatusCode, "latency_ms", latency.Milliseconds())
		return nil, &statusError{code: resp.StatusCode, msg: fmt.Sprintf("gemini API returned status %d", resp.StatusCode)}
	}

	var gemResp geminiResponse
	if err := json.Unmarshal(respBytes, &gemResp); err != nil {
		return nil, fmt.Errorf("unmarshal response: %w", err)
	}

	if gemResp.Error != nil {
		return nil, fmt.Errorf("gemini error: %s (code %d)", gemResp.Error.Message, gemResp.Error.Code)
	}

	if len(gemResp.Candidates) == 0 || len(gemResp.Candidates[0].Content.Parts) == 0 {
		return nil, fmt.Errorf("gemini returned no candidates")
	}

	jsonText := gemResp.Candidates[0].Content.Parts[0].Text
	slog.InfoContext(ctx, "gemini response", "model", g.model, "latency_ms", latency.Milliseconds())
	slog.DebugContext(ctx, "gemini raw response", "json", jsonText)

	var parsed geminiParsedReceipt
	if err := json.Unmarshal([]byte(jsonText), &parsed); err != nil {
		return nil, fmt.Errorf("unmarshal receipt JSON: %w", err)
	}

	return g.toReceipt(&parsed), nil
}

// toReceipt converts a Gemini response to our internal ParsedReceipt type.
func (g *GeminiClient) toReceipt(parsed *geminiParsedReceipt) *ParsedReceipt {
	result := &ParsedReceipt{
		MerchantName: parsed.MerchantName,
		ReceiptDate:  parsed.ReceiptDate,
		Items:        make([]ReceiptItem, 0, len(parsed.Items)),
		Warnings:     []string{},
		Confidence:   0.9, // LLM extraction is generally reliable
	}

	// Map items (keep $0 items for display — split logic skips them)
	for _, item := range parsed.Items {
		qty := item.Quantity
		if qty <= 0 {
			qty = 1
		}
		result.Items = append(result.Items, ReceiptItem{
			Name:       item.Name,
			Quantity:   qty,
			UnitCents:  item.UnitCents,
			TotalCents: item.TotalCents,
		})
	}

	// Set summary fields
	if parsed.SubtotalCents > 0 {
		v := parsed.SubtotalCents
		result.SubtotalCents = &v
	}
	if parsed.TaxCents > 0 {
		v := parsed.TaxCents
		result.TaxCents = &v
	}
	if parsed.TipCents > 0 {
		v := parsed.TipCents
		result.TipCents = &v
	}
	if parsed.TotalCents > 0 {
		v := parsed.TotalCents
		result.TotalCents = &v
	}

	// Cross-validate: do items sum to subtotal?
	if result.SubtotalCents != nil && len(result.Items) > 0 {
		var itemSum int64
		for _, item := range result.Items {
			itemSum += item.TotalCents
		}
		if abs64(itemSum-*result.SubtotalCents) > 50 { // 50 cent tolerance for LLM rounding
			result.Warnings = append(result.Warnings, fmt.Sprintf(
				"Item total ($%s) differs from subtotal ($%s)",
				formatCents(itemSum), formatCents(*result.SubtotalCents),
			))
			result.Confidence = 0.7
		}
	}

	// Fallback: compute subtotal from items if not provided
	if result.SubtotalCents == nil && len(result.Items) > 0 {
		var sum int64
		for _, item := range result.Items {
			sum += item.TotalCents
		}
		result.SubtotalCents = &sum
	}

	// Fallback: compute total from subtotal + tax + tip if not provided
	if result.TotalCents == nil && result.SubtotalCents != nil {
		total := *result.SubtotalCents
		if result.TaxCents != nil {
			total += *result.TaxCents
		}
		if result.TipCents != nil {
			total += *result.TipCents
		}
		result.TotalCents = &total
	}

	return result
}

func abs64(n int64) int64 {
	if n < 0 {
		return -n
	}
	return n
}

func formatCents(c int64) string {
	if c < 0 {
		return fmt.Sprintf("-%d.%02d", -c/100, -c%100)
	}
	return fmt.Sprintf("%d.%02d", c/100, c%100)
}
