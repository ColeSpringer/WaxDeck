package connect

import "errors"

// Typed errors the API layer maps onto the wire vocabulary.
var (
	// ErrNotFound: no such endpoint or session visible to the caller.
	ErrNotFound = errors.New("not found")
	// ErrEndpointOffline: the target endpoint is not connected.
	ErrEndpointOffline = errors.New("endpoint offline")
	// ErrForbidden: the caller may see this but not do that.
	ErrForbidden = errors.New("forbidden")
	// ErrTimeout: a routed command's target did not answer in time.
	ErrTimeout = errors.New("timeout")
)

// InvalidError carries a request-shaped failure with its detail, and
// optionally the wire code that failure already had a name for. A
// refusal minted somewhere that knew what it was refusing - a client
// endpoint answering `cmd-result`, a handler turning a queue away from
// a device - sets Code so the controller can branch on it instead of
// parsing prose. The zero value keeps the old behavior: the transport
// decides, and both transports decide `invalid-request`.
//
// Params is that detail one level finer, for the codes covering more
// than one cause: `feature-unavailable` is the umbrella for everything
// a target cannot play, so it names the capability in `feature` and the
// subject in `pid` rather than leaving a controller to read the prose.
// Nil is the ordinary case and reads as empty.
type InvalidError struct {
	Msg    string
	Code   string
	Params map[string]string
}

func (e InvalidError) Error() string { return e.Msg }
