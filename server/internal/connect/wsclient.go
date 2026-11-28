package connect

import "sync"

// ClientLink is one WebSocket connection's command-bus handle. The
// transport layer constructs it with an enqueue function and calls
// the Service's Handle methods from its read loop; the Service pushes
// frames back through Send. Send is best-effort: false means the frame
// was not queued, the connection being gone or backed up. A watcher's
// push that fails is owed again by the next one, a watch whose first
// frame fails is not registered (the transport closes the connection),
// and a routed command treats the endpoint as offline.
type ClientLink struct {
	UserID     string
	UserName   string
	SessionID  string // device session id (se-), the endpoint identity seed
	DeviceName string

	send func(v any) bool

	mu         sync.Mutex
	registered bool
}

// NewClientLink builds a link for one live connection. send must not
// block or call into the Service: every frame for a watcher goes out
// under the Service's lock.
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
