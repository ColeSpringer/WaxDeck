package connect

import "sync"

// ClientLink is one WebSocket connection's command-bus handle. The
// transport layer constructs it with an enqueue function and calls
// the Service's Handle methods from its read loop; the Service pushes
// frames back through Send. Send is best-effort: false means the
// connection is gone or hopelessly backed up, and the caller treats
// the link as dead.
type ClientLink struct {
	UserID     string
	UserName   string
	SessionID  string // device session id (se-), the endpoint identity seed
	DeviceName string

	send func(v any) bool

	mu         sync.Mutex
	registered bool
}

// NewClientLink builds a link for one live connection.
func NewClientLink(userID, userName, sessionID, deviceName string, send func(v any) bool) *ClientLink {
	return &ClientLink{
		UserID:     userID,
		UserName:   userName,
		SessionID:  sessionID,
		DeviceName: deviceName,
		send:       send,
	}
}

// Send enqueues a frame for delivery. Safe from any goroutine.
func (l *ClientLink) Send(v any) bool {
	if l.send == nil {
		return false
	}
	return l.send(v)
}

func (l *ClientLink) setRegistered(v bool) {
	l.mu.Lock()
	l.registered = v
	l.mu.Unlock()
}

func (l *ClientLink) isRegistered() bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.registered
}
