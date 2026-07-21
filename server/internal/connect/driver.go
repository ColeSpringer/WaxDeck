// Package connect is the multi-device control core: the endpoint
// registry (who can play), the session manager (what is playing
// where), and the command routing between controllers, the server, and
// player endpoints. Remote endpoints (cast, DLNA, jukebox) are driven
// by the server through the Driver interface; first-party clients
// drive themselves and mirror their state here, staying remotely
// controllable through routed commands over their WebSocket.
package connect

import (
	"context"
	"time"
)

// MediaItem is one device-fetchable stream: an absolute URL the
// endpoint pulls itself, plus display metadata for the device's own
// UI (cast receivers and renderers show it).
type MediaItem struct {
	PID        string
	URL        string
	MimeType   string
	Title      string
	Artist     string
	ArtURL     string
	DurationMS int64
}

// DriverEvent is one state observation from a driven endpoint. Fields
// are absolute: Index and PositionMS locate playback inside the loaded
// items at the At instant. Finished means the whole load ran out (not
// a single track ending; drivers advance through their items
// themselves). Fatal means the endpoint is gone and the driver is
// dead; the session ends.
type DriverEvent struct {
	At         time.Time
	Playing    bool
	Index      int
	PositionMS int64
	Volume     *float64
	Finished   bool
	Fatal      bool
	Err        error
}

// Driver drives one physical output for one load at a time. Load
// replaces whatever is playing. Implementations serialize their own
// protocol I/O; calls may block on the device. Events delivers state
// observations until Close; it is never closed by the driver before
// Close so consumers can range freely.
type Driver interface {
	Load(ctx context.Context, items []MediaItem, index int, positionMS int64, play bool) error
	Play(ctx context.Context) error
	Pause(ctx context.Context) error
	Stop(ctx context.Context) error
	SeekTo(ctx context.Context, positionMS int64) error
	SetVolume(ctx context.Context, volume float64) error
	SetRate(ctx context.Context, rate float64) error
	Events() <-chan DriverEvent
	Close() error
}

// DialFunc opens a live driver to a device endpoint. The session
// manager dials when a session starts and closes when it ends, so
// idle devices hold no connections.
type DialFunc func(ctx context.Context) (Driver, error)
