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

// InvalidError carries a request-shaped failure with its detail.
type InvalidError struct{ Msg string }

func (e InvalidError) Error() string { return e.Msg }
