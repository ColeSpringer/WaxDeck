// Package scrobble holds the outbound scrobbling clients: Last.fm and
// ListenBrainz. The service layer owns connections and queueing; this
// package only speaks the wire protocols.
package scrobble

import (
	"errors"
	"net/http"
	"time"
)

// Track is one delivered listen.
type Track struct {
	Artist     string
	Title      string
	Album      string
	DurationMS int64
	// ListenedAt is when the listen started, unix seconds. Zero for a
	// now-playing update.
	ListenedAt int64
}

// Permanent marks a delivery the service itself rejected: retrying the
// same submission cannot succeed. Transport failures and throttling
// stay plain errors, which callers retry.
type Permanent struct{ Err error }

func (p *Permanent) Error() string { return "permanent: " + p.Err.Error() }
func (p *Permanent) Unwrap() error { return p.Err }

// IsPermanent reports whether err marks an unretryable rejection.
func IsPermanent(err error) bool {
	var p *Permanent
	return errors.As(err, &p)
}

// httpClient is the shared bounded client; scrobble calls are small
// and quick or not worth waiting on.
var httpClient = &http.Client{Timeout: 15 * time.Second}
