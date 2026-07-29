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

// EndpointTarget describes the endpoint a load is being rendered for.
// Kind is what picks the format floor; Formats is what the endpoint
// itself said it accepts, when it says anything at all.
type EndpointTarget struct {
	Kind string
	// Formats are the media types the endpoint declared, lowercased and
	// in the endpoint's own spelling (renderers disagree about
	// `audio/flac` versus `audio/x-flac`, so a resolver normalizes
	// before comparing). Empty means the endpoint declared nothing, or
	// declared a wildcard, which constrains nothing either way: the
	// floor stands.
	Formats []string
}

// FormatSink is the optional capability of a driver whose endpoint
// declares what it can play. A driver that does not implement it is
// treated as having declared nothing, which is the same answer a driver
// whose device answered a wildcard gives.
type FormatSink interface {
	AcceptedFormats() []string
}

// TargetFor builds the target for an endpoint and the driver currently
// dialed to it.
func TargetFor(kind string, d Driver) EndpointTarget {
	t := EndpointTarget{Kind: kind}
	if fs, ok := d.(FormatSink); ok {
		t.Formats = fs.AcceptedFormats()
	}
	return t
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
