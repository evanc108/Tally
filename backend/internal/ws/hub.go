// Package ws implements WebSocket real-time broadcast for payment sessions.
//
// Architecture: one Hub per active payment session. Clients connect via
// /v1/groups/:id/sessions/:sessionId/ws and receive JSON events for item
// claims, member confirmations, and session state changes.
package ws

import (
	"encoding/json"
	"log/slog"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// Event types sent from server → client.
const (
	EventItemClaimed     = "item_claimed"
	EventItemReleased    = "item_released"
	EventMemberConfirmed = "member_confirmed"
	EventSessionUpdated  = "session_updated"
	EventSplitsUpdated   = "splits_updated"
)

// Event is the envelope for all WebSocket messages.
type Event struct {
	Type    string      `json:"type"`
	Payload interface{} `json:"payload"`
}

// client wraps a single WebSocket connection.
type client struct {
	conn     *websocket.Conn
	send     chan []byte
	memberID string
}

// Hub manages all WebSocket clients for a single payment session.
type Hub struct {
	sessionID string
	clients   map[*client]bool
	mu        sync.RWMutex

	register   chan *client
	unregister chan *client
	broadcast  chan []byte
	done       chan struct{}
}

// NewHub creates a Hub for the given session and starts its run loop.
func NewHub(sessionID string) *Hub {
	h := &Hub{
		sessionID:  sessionID,
		clients:    make(map[*client]bool),
		register:   make(chan *client),
		unregister: make(chan *client),
		broadcast:  make(chan []byte, 64),
		done:       make(chan struct{}),
	}
	go h.run()
	return h
}

func (h *Hub) run() {
	for {
		select {
		case c := <-h.register:
			h.mu.Lock()
			h.clients[c] = true
			h.mu.Unlock()
			slog.Info("ws client connected", "session_id", h.sessionID, "member_id", c.memberID)

		case c := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[c]; ok {
				delete(h.clients, c)
				close(c.send)
			}
			h.mu.Unlock()
			slog.Info("ws client disconnected", "session_id", h.sessionID, "member_id", c.memberID)

		case msg := <-h.broadcast:
			h.mu.RLock()
			for c := range h.clients {
				select {
				case c.send <- msg:
				default:
					// Client buffer full — drop connection.
					close(c.send)
					delete(h.clients, c)
				}
			}
			h.mu.RUnlock()

		case <-h.done:
			h.mu.Lock()
			for c := range h.clients {
				close(c.send)
				delete(h.clients, c)
			}
			h.mu.Unlock()
			return
		}
	}
}

// Broadcast sends an Event to all connected clients.
func (h *Hub) Broadcast(evt Event) {
	data, err := json.Marshal(evt)
	if err != nil {
		slog.Error("ws marshal event failed", "error", err, "type", evt.Type)
		return
	}
	h.broadcast <- data
}

// ClientCount returns the number of connected clients.
func (h *Hub) ClientCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients)
}

// Close shuts down the hub and disconnects all clients.
func (h *Hub) Close() {
	close(h.done)
}

// ── Hub Manager ──────────────────────────────────────────────────────────────

// Manager manages Hubs keyed by session ID. Thread-safe.
type Manager struct {
	hubs map[string]*Hub
	mu   sync.RWMutex
}

// NewManager creates a Manager.
func NewManager() *Manager {
	return &Manager{
		hubs: make(map[string]*Hub),
	}
}

// GetOrCreate returns the Hub for sessionID, creating one if it doesn't exist.
func (m *Manager) GetOrCreate(sessionID string) *Hub {
	m.mu.Lock()
	defer m.mu.Unlock()
	if h, ok := m.hubs[sessionID]; ok {
		return h
	}
	h := NewHub(sessionID)
	m.hubs[sessionID] = h
	return h
}

// Get returns the Hub for sessionID, or nil if none exists.
func (m *Manager) Get(sessionID string) *Hub {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.hubs[sessionID]
}

// Remove closes and removes the Hub for sessionID.
func (m *Manager) Remove(sessionID string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if h, ok := m.hubs[sessionID]; ok {
		h.Close()
		delete(m.hubs, sessionID)
	}
}

// ── WebSocket read/write pumps ───────────────────────────────────────────────

const (
	writeWait  = 10 * time.Second
	pongWait   = 60 * time.Second
	pingPeriod = 30 * time.Second
	maxMsgSize = 1024
)

// AddClient upgrades an HTTP connection to WebSocket and registers it with
// the hub. Blocks until the connection is closed.
func (h *Hub) AddClient(conn *websocket.Conn, memberID string) {
	c := &client{
		conn:     conn,
		send:     make(chan []byte, 64),
		memberID: memberID,
	}
	h.register <- c

	go c.writePump()
	c.readPump(h) // blocks until disconnect
}

func (c *client) readPump(h *Hub) {
	defer func() {
		h.unregister <- c
		c.conn.Close()
	}()
	c.conn.SetReadLimit(maxMsgSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		// We don't expect client→server messages, but must read to handle
		// control frames (pong). Discard any data messages.
		_, _, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err,
				websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				slog.Warn("ws read error", "member_id", c.memberID, "error", err)
			}
			return
		}
	}
}

func (c *client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case msg, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
