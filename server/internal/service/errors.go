package service

import (
	"errors"
	"strings"

	"github.com/colespringer/waxbin/waxerr"
)

// ErrorKind classifies service failures for the API layer, which maps
// each kind to a status and stable error code without importing WaxBin.
type ErrorKind string

const (
	KindNotFound    ErrorKind = "not-found"
	KindInvalid     ErrorKind = "invalid-request"
	KindConflict    ErrorKind = "conflict"
	KindMaintenance ErrorKind = "catalog-maintenance"
	KindInternal    ErrorKind = "internal"
)

// Error is a classified service failure.
type Error struct {
	Kind ErrorKind
	Msg  string
	Err  error
}

func (e *Error) Error() string {
	if e.Msg != "" {
		return e.Msg
	}
	if e.Err != nil {
		return e.Err.Error()
	}
	return string(e.Kind)
}

func (e *Error) Unwrap() error { return e.Err }

// KindOf classifies any error: nil is the empty kind, service errors
// keep their kind, WaxBin errors map by code, everything else is
// internal.
func KindOf(err error) ErrorKind {
	if err == nil {
		return ""
	}
	var se *Error
	if errors.As(err, &se) {
		return se.Kind
	}
	return kindFromWaxErr(err)
}

func kindFromWaxErr(err error) ErrorKind {
	// While the CLI holds the catalog for a maintenance operation the
	// suspended store answers every read with a closed-database error.
	// This is the one place that string shows up as a signal; the API
	// layer turns it into the typed catalog-maintenance error clients
	// render as a banner.
	if err != nil && strings.Contains(err.Error(), "database is closed") {
		return KindMaintenance
	}
	switch waxerr.CodeOf(err) {
	case waxerr.CodeNotFound:
		return KindNotFound
	case waxerr.CodeInvalid:
		return KindInvalid
	case waxerr.CodeConflict, waxerr.CodeLocked:
		return KindConflict
	default:
		return KindInternal
	}
}

// classify wraps a WaxBin error into a service error, preserving the
// message for logs while the API layer decides what to expose.
func classify(err error) error {
	if err == nil {
		return nil
	}
	return &Error{Kind: kindFromWaxErr(err), Err: err}
}

// errNotFound builds a caller-facing not-found error.
func errNotFound(msg string) error { return &Error{Kind: KindNotFound, Msg: msg} }

// errInvalid builds a caller-facing invalid-request error.
func errInvalid(msg string) error { return &Error{Kind: KindInvalid, Msg: msg} }
