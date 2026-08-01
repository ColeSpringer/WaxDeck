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
	// KindGone marks a sync cursor the stream can no longer serve
	// contiguously (410 sync-reset at the API).
	KindGone ErrorKind = "sync-reset"
	// KindForbidden marks an authenticated caller who is not allowed
	// to do this (403 forbidden at the API).
	KindForbidden ErrorKind = "forbidden"
	// KindUpstream marks a failure of a server the request depends on
	// but WaxDeck does not operate: a podcast feed's host answered an
	// error, timed out, or returned something unparseable (502
	// feed-unreachable at the API).
	KindUpstream ErrorKind = "feed-unreachable"
	// KindUnsupported marks a request needing an integration this
	// server is not running, such as the YouTube bridge (501
	// source-unavailable at the API).
	KindUnsupported ErrorKind = "source-unavailable"
	// KindDirectory marks an unreachable external directory service,
	// such as the radio station directory (502 directory-unavailable
	// at the API).
	KindDirectory ErrorKind = "directory-unavailable"
	// KindService marks an unreachable external service a request
	// depends on, such as a scrobbling provider (502
	// service-unreachable at the API).
	KindService ErrorKind = "service-unreachable"
	// KindQuota marks an upload the caller's storage quota refuses
	// (413 quota-exceeded at the API).
	KindQuota ErrorKind = "quota-exceeded"
	// KindLocked marks an edit against a locked metadata field made
	// without force (409 field-locked at the API).
	KindLocked ErrorKind = "field-locked"
	// KindFormat marks a file whose format the server does not accept
	// (415 unsupported-format at the API).
	KindFormat ErrorKind = "unsupported-format"
	// KindFeature marks a request needing an optional capability this
	// server is not running, such as the streaming engine (501
	// feature-unavailable at the API).
	KindFeature ErrorKind = "feature-unavailable"
	// KindReadOnly marks a file-writing operation refused because the
	// target library, or the whole server, is in read-only mode (409
	// read-only at the API).
	KindReadOnly ErrorKind = "read-only"
	// KindTranscodeLimit marks a stream refused because the server's or
	// the caller's concurrent transcode session limit is reached (429
	// transcode-limited at the API).
	KindTranscodeLimit ErrorKind = "transcode-limited"
	// KindCatalogBusy marks a request refused because another job holds
	// the shared file-mutation scope (409 catalog-busy at the API).
	// Unlike KindConflict it clears on its own.
	KindCatalogBusy ErrorKind = "catalog-busy"
)

// classifyMutation is classify for a call that takes the catalog's
// shared file-mutation scope. A conflict there is another job holding
// the scope, which clears on its own, so it answers catalog-busy rather
// than the conflict that means the caller has to change something.
func classifyMutation(err error) error {
	out := classify(err)
	if KindOf(out) != KindConflict {
		return out
	}
	return &Error{
		Kind: KindCatalogBusy,
		Msg:  "a conflicting catalog job is already running; retry when it finishes",
		Err:  err,
	}
}

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
	case waxerr.CodeConflict:
		return KindConflict
	case waxerr.CodeLocked:
		return KindLocked
	case waxerr.CodeUnsupported:
		return KindUnsupported
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
