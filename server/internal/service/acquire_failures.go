package service

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
	"syscall"

	waxtap "github.com/colespringer/waxtap/v3"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

// The reasons a source refuses a link or an item: a closed set, so a
// client can word each one itself. The first group are verdicts, which no
// later try changes; the rest are the source's trouble, which can pass.
const (
	reasonPlaylistUnavailable = "playlist-unavailable"
	reasonPlaylistEmpty       = "playlist-empty"
	reasonVideoPrivate        = "video-private"
	reasonVideoUnavailable    = "video-unavailable"
	reasonAgeRestricted       = "age-restricted"
	reasonRegionBlocked       = "region-blocked"
	reasonMembersOnly         = "members-only"
	reasonLive                = "live"
	reasonNotStarted          = "not-started"
	reasonNoAudio             = "no-audio"
	reasonUnsupportedURL      = syncsource.ReasonUnsupportedURL

	reasonRateLimited  = "rate-limited"
	reasonSourceBroken = "source-broken"
	reasonTimedOut     = "timed-out"
	reasonStalled      = "stalled"
)

// errFetchStalled is a download stopped for showing no activity.
var errFetchStalled = errors.New("the download stopped moving")

// sourceReasons is what the API says for each reason, and whether the
// reason is a verdict.
var sourceReasons = map[string]struct {
	sentence  string
	permanent bool
}{
	reasonPlaylistUnavailable: {"The playlist is private or was deleted.", true},
	reasonPlaylistEmpty:       {"The playlist has no videos.", true},
	reasonVideoPrivate:        {"The video is private or needs a sign-in.", true},
	reasonVideoUnavailable:    {"The video is no longer available.", true},
	reasonAgeRestricted:       {"The video is age-restricted.", true},
	reasonRegionBlocked:       {"The video is not available in this server's region.", true},
	reasonMembersOnly:         {"The video is for channel members only.", true},
	reasonLive:                {"The video is a live stream; it can be downloaded once it ends.", true},
	reasonNotStarted:          {"The video is a premiere or a stream that has not started.", true},
	reasonNoAudio:             {"The video has no audio to download.", true},
	reasonUnsupportedURL:      {"The link is not a video, playlist or channel the source can read.", true},
	reasonRateLimited:         {"The source is limiting requests; try again later.", false},
	reasonSourceBroken:        {"The bridge to the source needs maintenance.", false},
	reasonTimedOut:            {"The source did not answer in time.", false},
	reasonStalled:             {"The download stopped moving.", false},
	reasonUnreachable:         {"The source could not be reached, or the connection broke off.", false},
}

// acquireReason reads a source failure as one of the source-refused
// reasons, and whether it is a verdict. WaxTap's sentinels survive the
// providers' and the catalog's wraps; a provider's own refusal names its
// reason. An error it cannot name answers "", which is no verdict.
func acquireReason(err error) (reason string, permanent bool) {
	if err == nil {
		return "", false
	}
	var refusal *syncsource.Refusal
	if errors.As(err, &refusal) {
		if r, known := sourceReasons[refusal.Reason]; known {
			return refusal.Reason, r.permanent
		}
		return "", false
	}
	is := func(targets ...error) bool {
		for _, target := range targets {
			if errors.Is(err, target) {
				return true
			}
		}
		return false
	}
	switch {
	case is(errFetchStalled):
		return reasonStalled, false
	case is(waxtap.ErrRateLimited, waxtap.ErrTemporarilyUnavailable):
		// First: WaxTap relabels a throttled read this way over the
		// availability sentinel the throttle answered with.
		return reasonRateLimited, false
	case is(waxtap.ErrLoginRequired):
		// A sign-in wall is also what a bot check or a content check
		// answers, so it waits; the private form WaxTap tells apart is
		// the restricted one below.
		return reasonVideoPrivate, false
	}
	reason = acquireVerdictOf(is)
	var (
		netErr  net.Error
		sidecar *waxtap.SidecarError
		status  *waxtap.HTTPStatusError
	)
	switch {
	case reason != "":
	case errors.As(err, &sidecar):
		// The session sidecar is the server's own bridge, whatever its
		// transport says.
		return reasonSourceBroken, false
	case errors.As(err, &status) && status.StatusCode >= 500:
		return reasonUnreachable, false
	case errors.As(err, &netErr) && netErr.Timeout():
		return reasonTimedOut, false
	case sourceUnreachable(err):
		return reasonUnreachable, false
	}
	return reason, sourceReasons[reason].permanent
}

// sourceUnreachable reports a source that could not be reached or broke
// off: no address, no connection, a failed handshake, a stream cut short.
// A request canceled on its own side is none of these.
func sourceUnreachable(err error) bool {
	if errors.Is(err, context.Canceled) {
		return false
	}
	var (
		urlErr    *url.Error
		netErr    net.Error
		verify    *tls.CertificateVerificationError
		record    tls.RecordHeaderError
		alert     tls.AlertError
		authority x509.UnknownAuthorityError
		hostname  x509.HostnameError
		invalid   x509.CertificateInvalidError
	)
	if errors.As(err, &urlErr) && urlErr.Op == "parse" {
		return false
	}
	return errors.As(err, &urlErr) || errors.As(err, &netErr) ||
		errors.As(err, &verify) || errors.As(err, &record) || errors.As(err, &alert) ||
		errors.As(err, &authority) || errors.As(err, &hostname) || errors.As(err, &invalid) ||
		errors.Is(err, io.ErrUnexpectedEOF) || errors.Is(err, net.ErrClosed) ||
		errors.Is(err, syscall.ECONNRESET) || errors.Is(err, syscall.ECONNREFUSED) ||
		errors.Is(err, syscall.ECONNABORTED) || errors.Is(err, syscall.EPIPE) ||
		errors.Is(err, waxtap.ErrIncompleteStream) || errors.Is(err, waxtap.ErrURLExpired)
}

func acquireVerdictOf(is func(...error) bool) string {
	switch {
	case is(waxtap.ErrPlaylistUnavailable):
		return reasonPlaylistUnavailable
	case is(waxtap.ErrPlaylistEmpty):
		return reasonPlaylistEmpty
	case is(waxtap.ErrVideoRestricted):
		return reasonVideoPrivate
	case is(waxtap.ErrVideoUnavailable):
		return reasonVideoUnavailable
	case is(waxtap.ErrAgeRestricted):
		return reasonAgeRestricted
	case is(waxtap.ErrGeoBlocked):
		return reasonRegionBlocked
	case is(waxtap.ErrMembersOnly):
		return reasonMembersOnly
	case is(waxtap.ErrLiveContent):
		return reasonLive
	case is(waxtap.ErrLiveNotStarted):
		return reasonNotStarted
	case is(waxtap.ErrNoAudioFormats):
		return reasonNoAudio
	case is(waxtap.ErrIsPlaylist, waxtap.ErrIsChannel, waxtap.ErrInvalidVideoID, waxtap.ErrVideoIDTooShort,
		waxtap.ErrVideoIDTooLong, waxtap.ErrInvalidPlaylistID, waxtap.ErrShortsPlaylist):
		// Not the general ErrUnsupportedInput the Shorts shelf wraps:
		// that is WaxTap's word for damaged local media too.
		return reasonUnsupportedURL
	case is(waxtap.ErrExtractionFailed, waxtap.ErrCipherSolve, waxtap.ErrNeedsPOToken, waxtap.ErrPlaylistParse):
		return reasonSourceBroken
	case is(context.DeadlineExceeded):
		return reasonTimedOut
	}
	return ""
}

// sourceRefused is the refusal of a link for reason, in the API's words,
// carrying the reason and the failure under it.
func sourceRefused(reason string, err error) error {
	return &Error{
		Kind:   KindRefused,
		Msg:    sourceReasons[reason].sentence,
		Err:    err,
		Params: map[string]string{"reason": reason},
	}
}

// finalFailure is a failure of a run no retry changes, of the kind a
// client words it by.
func finalFailure(kind ErrorKind, msg string, params map[string]string) error {
	return &Error{Kind: kind, Msg: msg, Err: errToolPermanent, Params: params}
}

// stagedBefore is a final failure that cut a list short, saying how much of
// it staged before, its kind and params kept.
func stagedBefore(staged, total int, err error) error {
	return finalFailure(KindOf(err), fmt.Sprintf("%d of %d items staged before: %s", staged, total, taskFailureText(err)), RefusalParams(err))
}

// sourceFault is a failure of the source an acquisition or a sync reads,
// which the run fails on or waits out by what the source said, apart from
// its own trouble (the database, the staging disk).
type sourceFault struct{ err error }

func (f *sourceFault) Error() string { return f.err.Error() }
func (f *sourceFault) Unwrap() error { return f.err }

// sourceWait is how an acquisition's or a sync's run meets a failure of its
// source. A verdict fails the task, as does a refusal no wait can change,
// or a failure past the task's waits: by the reason the classifier names,
// else by the failure's classification. Anything else waits, as long as
// the source asked when it was throttled, the attempt given back.
func (l *Tools) sourceWait(ctx context.Context, t *wdb.ToolTask, err error) error {
	reason, verdict := acquireReason(err)
	if verdict {
		return fmt.Errorf("%w: %w", errToolPermanent, sourceRefused(reason, err))
	}
	if kindIsPermanent(KindOf(err)) {
		return fmt.Errorf("%w: %w", errToolPermanent, err)
	}
	waits := -1
	if perr := l.editTaskParams(ctx, t, func(p *toolTaskParams) {
		waits = p.SourceWaits
		if waits < toolSourceWaits {
			p.SourceWaits++
		}
	}); perr != nil {
		l.log.Warn("recording a source wait", "task", t.ID, "err", perr)
		return err
	}
	if waits >= toolSourceWaits {
		if reason != "" {
			return fmt.Errorf("%w: %w", errToolPermanent, sourceRefused(reason, err))
		}
		return fmt.Errorf("%w: %w", errToolPermanent, err)
	}
	wait := &toolRetry{after: toolBackoff(waits + 1), err: err, reason: "source-retry"}
	if reason != "" {
		// Kept with the wait, for a task the attempts retire before it
		// runs again.
		wait.err = &Error{Kind: KindRefused, Err: err, Params: map[string]string{"reason": reason}}
	}
	switch reason {
	case reasonStalled:
		wait.reason = reasonStalled
	case reasonRateLimited:
		wait.reason = "rate-limited"
		var limited *waxtap.RateLimitError
		if errors.As(err, &limited) && limited.RetryAfter > 0 {
			wait.after = min(limited.RetryAfter, toolBackoffMax)
		}
	}
	return wait
}
