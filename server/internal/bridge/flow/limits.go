package flow

import (
	"context"
	"errors"
	"net/http"
)

// TranscodeGate admits or refuses engine-backed stream sessions. The
// implementation lives with the service layer, which knows the acting
// user's permissions and the admin-set limits; the bridge only asks.
type TranscodeGate interface {
	// Acquire reserves a session slot for the user, returning a release
	// the caller runs when the stream ends. ErrTranscodeLimited when a
	// limit is reached. The context is the stream request's.
	Acquire(ctx context.Context, user string) (release func(), err error)
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
	release, err := b.gate.Acquire(ctx, user)
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
