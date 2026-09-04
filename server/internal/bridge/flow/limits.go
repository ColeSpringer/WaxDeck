package flow

import (
	"context"
	"errors"
	"net/http"
)

// TranscodeKind names what a slot is being held for, so the activity
// read can say how much of a count is one thing or the other. The caps
// do not distinguish: a slot is a slot, and this is only ever reporting.
type TranscodeKind string

const (
	// TranscodeStream is one engine-backed progressive stream.
	TranscodeStream TranscodeKind = "stream"
	// TranscodeTimeline is one listener's gapless queue rendering. One
	// slot covers every timeline they hold live at once, because a queue
	// edit mints another while the one playing is still being fetched
	// and refusing that would stall the music the edit was made in.
	TranscodeTimeline TranscodeKind = "timeline"
)

// TranscodeGate admits or refuses engine-backed sessions. The
// implementation lives with the service layer, which knows the acting
// user's permissions and the admin-set limits; the bridge only asks.
type TranscodeGate interface {
	// Acquire reserves a session slot for the user, returning a release
	// the caller runs when the session ends. ErrTranscodeLimited when a
	// limit is reached. The context is the request's.
	Acquire(ctx context.Context, user string, kind TranscodeKind) (release func(), err error)
	// MaxBitrateKbps reports the user's transcode bitrate ceiling in
	// kbit/s; 0 means none.
	MaxBitrateKbps(ctx context.Context, user string) int
}

// ErrTranscodeLimited is the gate's refusal.
var ErrTranscodeLimited = errors.New("transcode session limit reached")

// SetTranscodeGate wires the session gate; nil (the default) admits
// everything. Called once at startup, before the bridge serves.
func (b *Bridge) SetTranscodeGate(g TranscodeGate) { b.gate = g }

// admit reserves a session slot, answering the request itself on
// refusal. The returned release is non-nil exactly when admitted.
// Callers gate only engine-backed shapes: direct-played originals
// (byte-range seekable passthrough) never count, both because the
// contract says so and because players probe seekable URLs with
// several concurrent range requests that must not eat session slots.
func (b *Bridge) admit(ctx context.Context, w http.ResponseWriter, user string) (func(), bool) {
	if b.gate == nil {
		return func() {}, true
	}
	release, err := b.gate.Acquire(ctx, user, TranscodeStream)
	if err != nil {
		writeJSONError(w, http.StatusTooManyRequests, "transcode-limited",
			"the server's transcode session limit is reached; retry when a stream ends, or play a direct-play format")
		return nil, false
	}
	return release, true
}

// lossyBitrateFormats are the outputs a bitrate ceiling applies to;
// lossless outputs carry no bitrate parameter.
var lossyBitrateFormats = map[string]bool{
	"mp3": true, "opus": true, "vorbis": true, "aac": true,
}
