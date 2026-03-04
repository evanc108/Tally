package receipts

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func setupTestRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	h := NewHandler("", "") // no Gemini key
	r := gin.New()
	r.POST("/v1/receipts/parse", h.ParseReceipt)
	return r
}

func TestParseReceiptHandler_NoGeminiKey(t *testing.T) {
	r := setupTestRouter()
	body := `{"raw_text": "1 Burger  12.99\nTax  1.04\nTotal  14.03"}`
	req := httptest.NewRequest("POST", "/v1/receipts/parse", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503 when Gemini not configured, got %d: %s", w.Code, w.Body.String())
	}
}

func TestParseReceiptHandler_MissingRawText(t *testing.T) {
	r := setupTestRouter()
	body := `{}`
	req := httptest.NewRequest("POST", "/v1/receipts/parse", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

func TestParseReceiptHandler_EmptyBody(t *testing.T) {
	r := setupTestRouter()
	req := httptest.NewRequest("POST", "/v1/receipts/parse", bytes.NewBufferString(""))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

func TestParseReceiptHandler_TooLong(t *testing.T) {
	r := setupTestRouter()
	longText := strings.Repeat("a", 10001)
	bodyMap := map[string]string{"raw_text": longText}
	body, _ := json.Marshal(bodyMap)
	req := httptest.NewRequest("POST", "/v1/receipts/parse", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

func TestParseReceiptHandler_InvalidCircleID(t *testing.T) {
	r := setupTestRouter()
	body := `{"raw_text": "test  1.00", "circle_id": "not-a-uuid"}`
	req := httptest.NewRequest("POST", "/v1/receipts/parse", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}
