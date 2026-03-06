package ws

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		// In production, restrict to known origins.
		return true
	},
}

// HandleWebSocket is the Gin handler for WebSocket upgrade requests.
// GET /v1/groups/:id/sessions/:sessionId/ws
//
// Expects:
//   - "member_id" in gin context (set by RequireGroupMember middleware)
//   - ":sessionId" URL parameter
//
// The Manager is injected at construction time.
type WSHandler struct {
	manager *Manager
}

// NewWSHandler creates a handler that uses the given Manager.
func NewWSHandler(m *Manager) *WSHandler {
	return &WSHandler{manager: m}
}

// HandleUpgrade upgrades the HTTP connection to WebSocket and joins the
// session's hub. Blocks until the connection closes.
func (h *WSHandler) HandleUpgrade(c *gin.Context) {
	sessionID := c.Param("sessionId")
	if sessionID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing session_id"})
		return
	}

	memberIDRaw, ok := c.Get("member_id")
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	memberID := memberIDRaw.(interface{ String() string }).String()

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		// Upgrade writes the error response itself; don't double-write.
		return
	}

	hub := h.manager.GetOrCreate(sessionID)
	hub.AddClient(conn, memberID) // blocks until disconnect
}
