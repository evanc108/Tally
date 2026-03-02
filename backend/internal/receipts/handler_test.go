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
	h := NewHandler()
	r := gin.New()
	r.POST("/v1/receipts/parse", h.ParseReceipt)
	return r
}

func TestParseReceiptHandler_OK(t *testing.T) {
	r := setupTestRouter()
	body := `{"raw_text": "1 Burger  12.99\nTax  1.04\nTotal  14.03"}`
	req := httptest.NewRequest("POST", "/v1/receipts/parse", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var resp parseResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode error: %v", err)
	}
	if resp.Data == nil {
		t.Fatal("expected data in response")
	}
	if len(resp.Data.Items) == 0 {
		t.Error("expected at least one item")
	}
	if resp.Meta.RequestID == "" {
		t.Error("expected request_id in meta")
	}
	if resp.Meta.Timestamp == "" {
		t.Error("expected timestamp in meta")
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

func TestParseReceiptHandler_ValidCircleID(t *testing.T) {
	r := setupTestRouter()
	body := `{"raw_text": "Burger  12.99", "circle_id": "550e8400-e29b-41d4-a716-446655440000"}`
	req := httptest.NewRequest("POST", "/v1/receipts/parse", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
}

func TestParseReceiptHandler_MaxLengthBoundary(t *testing.T) {
	r := setupTestRouter()

	// Exactly at the limit should succeed.
	exactText := strings.Repeat("a", 10000)
	bodyMap := map[string]string{"raw_text": exactText}
	body, _ := json.Marshal(bodyMap)
	req := httptest.NewRequest("POST", "/v1/receipts/parse", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 at boundary, got %d", w.Code)
	}
}

func TestParseReceiptHandler_ResponseStructure(t *testing.T) {
	r := setupTestRouter()
	body := `{"raw_text": "Burger  12.99\nSubtotal  12.99\nTax  1.04\nTotal  14.03"}`
	req := httptest.NewRequest("POST", "/v1/receipts/parse", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()

	r.ServeHTTP(w, req)

	var raw map[string]json.RawMessage
	if err := json.Unmarshal(w.Body.Bytes(), &raw); err != nil {
		t.Fatalf("unmarshal error: %v", err)
	}
	if _, ok := raw["data"]; !ok {
		t.Error("response missing 'data' key")
	}
	if _, ok := raw["meta"]; !ok {
		t.Error("response missing 'meta' key")
	}
}
