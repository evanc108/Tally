package paysession

import (
	"testing"
)

func TestTerminalStatuses(t *testing.T) {
	terminal := []string{"completed", "cancelled", "expired"}
	for _, s := range terminal {
		if !terminalStatuses[s] {
			t.Errorf("expected %q to be terminal", s)
		}
	}

	nonTerminal := []string{"draft", "splitting", "confirming", "ready"}
	for _, s := range nonTerminal {
		if terminalStatuses[s] {
			t.Errorf("expected %q to NOT be terminal", s)
		}
	}
}

func TestValidTransitions(t *testing.T) {
	tests := []struct {
		from, to string
		valid    bool
	}{
		// draft transitions
		{"draft", "splitting", true},
		{"draft", "cancelled", true},
		{"draft", "confirming", false},
		{"draft", "ready", false},
		{"draft", "completed", false},

		// splitting transitions
		{"splitting", "confirming", true},
		{"splitting", "ready", true},
		{"splitting", "cancelled", true},
		{"splitting", "draft", false},
		{"splitting", "completed", false},

		// confirming transitions
		{"confirming", "ready", true},
		{"confirming", "cancelled", true},
		{"confirming", "draft", false},
		{"confirming", "splitting", false},
		{"confirming", "completed", false},

		// ready transitions
		{"ready", "completed", true},
		{"ready", "cancelled", true},
		{"ready", "splitting", true},
		{"ready", "draft", false},
		{"ready", "confirming", false},

		// terminal states have no transitions
		{"completed", "draft", false},
		{"cancelled", "draft", false},
		{"expired", "draft", false},
	}

	for _, tt := range tests {
		allowed := validTransitions[tt.from][tt.to]
		if allowed != tt.valid {
			t.Errorf("transition %s → %s: got allowed=%v, want %v", tt.from, tt.to, allowed, tt.valid)
		}
	}
}

func TestTransitionMapCompleteness(t *testing.T) {
	// Every non-terminal status should have at least one valid transition
	nonTerminal := []string{"draft", "splitting", "confirming", "ready"}
	for _, s := range nonTerminal {
		transitions, ok := validTransitions[s]
		if !ok {
			t.Errorf("status %q has no entry in validTransitions", s)
			continue
		}
		if len(transitions) == 0 {
			t.Errorf("status %q has no valid transitions", s)
		}
	}

	// Terminal statuses should NOT have entries in validTransitions
	for _, s := range []string{"completed", "cancelled", "expired"} {
		if _, ok := validTransitions[s]; ok {
			t.Errorf("terminal status %q should not have entries in validTransitions", s)
		}
	}
}

func TestTransitionAllNonTerminalCanCancel(t *testing.T) {
	// Every non-terminal status should be cancellable
	for _, from := range []string{"draft", "splitting", "confirming", "ready"} {
		if !validTransitions[from]["cancelled"] {
			t.Errorf("status %q should allow transition to cancelled", from)
		}
	}
}
