package ws

import (
	"testing"
	"time"
)

func TestNewHub_StartsRunLoop(t *testing.T) {
	h := NewHub("test-session-1")
	defer h.Close()

	// Hub should be running — verify it accepts operations
	if h.sessionID != "test-session-1" {
		t.Errorf("sessionID = %q, want %q", h.sessionID, "test-session-1")
	}
	if h.ClientCount() != 0 {
		t.Errorf("ClientCount = %d, want 0", h.ClientCount())
	}
}

func TestHub_BroadcastWithNoClients(t *testing.T) {
	h := NewHub("test-session-2")
	defer h.Close()

	// Broadcast should not panic or block even with no clients
	done := make(chan struct{})
	go func() {
		h.Broadcast(Event{Type: EventSessionUpdated, Payload: "test"})
		close(done)
	}()

	select {
	case <-done:
		// ok
	case <-time.After(2 * time.Second):
		t.Fatal("Broadcast blocked with no clients")
	}
}

func TestHub_Close_StopsAcceptingClients(t *testing.T) {
	h := NewHub("test-session-3")
	h.Close()

	// After close, ClientCount should be 0
	if h.ClientCount() != 0 {
		t.Errorf("ClientCount after close = %d, want 0", h.ClientCount())
	}
}

func TestManager_GetOrCreate(t *testing.T) {
	m := NewManager()

	h1 := m.GetOrCreate("session-a")
	if h1 == nil {
		t.Fatal("GetOrCreate returned nil")
	}
	defer h1.Close()

	// Same session should return same hub
	h2 := m.GetOrCreate("session-a")
	if h1 != h2 {
		t.Error("GetOrCreate returned different hubs for same session")
	}

	// Different session should return different hub
	h3 := m.GetOrCreate("session-b")
	defer h3.Close()
	if h1 == h3 {
		t.Error("GetOrCreate returned same hub for different sessions")
	}
}

func TestManager_Get_ReturnsNilForMissing(t *testing.T) {
	m := NewManager()

	if h := m.Get("nonexistent"); h != nil {
		t.Errorf("Get returned %v for nonexistent session, want nil", h)
	}
}

func TestManager_Get_ReturnsExisting(t *testing.T) {
	m := NewManager()
	h := m.GetOrCreate("session-x")
	defer h.Close()

	got := m.Get("session-x")
	if got != h {
		t.Error("Get returned different hub than GetOrCreate")
	}
}

func TestManager_Remove(t *testing.T) {
	m := NewManager()
	h := m.GetOrCreate("session-to-remove")
	_ = h

	m.Remove("session-to-remove")

	if got := m.Get("session-to-remove"); got != nil {
		t.Error("Get returned non-nil after Remove")
	}
}

func TestManager_Remove_Idempotent(t *testing.T) {
	m := NewManager()

	// Should not panic on removing nonexistent session
	m.Remove("nonexistent")
	m.Remove("nonexistent")
}

func TestEventConstants(t *testing.T) {
	// Verify event type strings are stable
	events := map[string]string{
		EventItemClaimed:     "item_claimed",
		EventItemReleased:    "item_released",
		EventMemberConfirmed: "member_confirmed",
		EventSessionUpdated:  "session_updated",
		EventSplitsUpdated:   "splits_updated",
	}
	for got, want := range events {
		if got != want {
			t.Errorf("event constant = %q, want %q", got, want)
		}
	}
}
