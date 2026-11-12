package service

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"

	waxtap "github.com/colespringer/waxtap/v3"

	"github.com/colespringer/waxbin/waxerr"
)

// classifyFeedErr maps a subscribe failure onto the API error model. A
// feed the server will not take (not a feed, too large, on a private
// network) is the caller's address to change and refused as invalid; the
// host's own failure is unreachable. Either way the error says why in a
// sentence of its own and carries the reason. The rest answer by kind.
func (l *Podcasts) classifyFeedErr(ctx context.Context, err error) error {
	if !feedAtFault(ctx, err) {
		return classify(err)
	}
	reason, sentence := feedFailureReason(err)
	switch reason {
	case reasonNotAFeed, reasonTooLarge, reasonBlockedAddress:
		return &Error{Kind: KindInvalid, Msg: sentence, Err: &feedFault{reason: reason, err: err}}
	}
	return feedUnreachable(err)
}

// logFeedFailure logs a feed-side failure by its host, reason and cause,
// and never the URL or the error: a feed URL can be its own credential,
// and the error's text repeats it.
func (l *Podcasts) logFeedFailure(msg, rawURL, reason string, err error) {
	l.logFeedFailureAt(slog.LevelInfo, msg, rawURL, reason, err)
}

// logFeedFailureAt is logFeedFailure at the level the caller chooses.
func (l *Podcasts) logFeedFailureAt(level slog.Level, msg, rawURL, reason string, err error) {
	host := ""
	if u, perr := url.Parse(rawURL); perr == nil {
		host = u.Hostname()
	}
	l.log.Log(context.Background(), level, msg, "host", host, "reason", reason, "cause", feedCause(err))
}

// feedCause names what a feed-side failure was in words that carry no
// URL, for the log: the host's status, or the kind of network failure.
func feedCause(err error) string {
	if err == nil {
		return ""
	}
	msg := err.Error()
	var (
		status      *hostStatusError
		netErr      net.Error
		dnsErr      *net.DNSError
		opErr       *net.OpError
		urlErr      *url.Error
		verifyErr   *tls.CertificateVerificationError
		unknownAuth x509.UnknownAuthorityError
		badHost     x509.HostnameError
		badCert     x509.CertificateInvalidError
		badRecord   tls.RecordHeaderError
	)
	if errors.As(err, &status) {
		return "status " + strconv.Itoa(status.status)
	}
	if m := httpStatusFragment.FindStringSubmatch(msg); m != nil {
		return "status " + m[1]
	}
	switch {
	case errors.Is(err, errPrivateAddress), strings.Contains(msg, "non-public address"):
		return "non-public address"
	case errors.Is(err, errTranscriptTooLarge), byteLimitFragment.MatchString(msg):
		return "size limit"
	case redirectFragment.MatchString(msg):
		return "redirects"
	case errors.Is(err, context.DeadlineExceeded), errors.As(err, &netErr) && netErr.Timeout():
		return "timeout"
	case errors.As(err, &dnsErr):
		return "dns"
	case errors.As(err, &verifyErr), errors.As(err, &unknownAuth), errors.As(err, &badHost),
		errors.As(err, &badCert), errors.As(err, &badRecord):
		return "tls"
	case errors.As(err, &opErr) && opErr.Op == "dial":
		return "dial"
	case errors.Is(err, io.ErrUnexpectedEOF), errors.Is(err, io.EOF):
		return "connection closed"
	case errors.As(err, &opErr):
		return opErr.Op
	case errors.As(err, &urlErr) && urlErr.Op == "parse":
		return "address"
	}
	if code := waxerr.CodeOf(err); code != "" {
		return string(code)
	}
	return "error"
}

// feedUnreachable reports a feed's own failure. Its sentence names neither
// the URL nor anything the host said; the log keeps the reason and a
// cause without the URL (feedCause), never the error itself.
func feedUnreachable(err error) error {
	reason, sentence := feedFailureReason(err)
	return &Error{Kind: KindUpstream, Msg: sentence, Err: &feedFault{reason: reason, err: err}}
}

// The reasons a feed-side fetch fails for: a closed set, so a client can
// word each one itself.
const (
	reasonNotAFeed       = "not-a-feed"
	reasonTooLarge       = "too-large"
	reasonBlockedAddress = "blocked-address"
	reasonHostRefused    = "host-refused"
	reasonHostMissing    = "host-missing"
	reasonHostError      = "host-error"
	reasonUnreachable    = "unreachable"
)

// feedSentences is what the API says for each reason about a feed.
var feedSentences = map[string]string{
	reasonNotAFeed:       "That address did not return a podcast feed.",
	reasonTooLarge:       "That feed is larger than this server accepts (16 MiB).",
	reasonBlockedAddress: "This server does not fetch feeds from private or local network addresses.",
	reasonHostRefused:    "The feed's host refused the request; it may need a login.",
	reasonHostMissing:    "No feed was found at that address.",
	reasonHostError:      "The feed's host answered with an error.",
	reasonUnreachable:    "The feed's host could not be reached.",
}

// transcriptSentences is the same for an episode's transcript, which is
// another document from another address, with a cap of its own.
var transcriptSentences = map[string]string{
	reasonNotAFeed:       "The transcript's address did not return a transcript.",
	reasonTooLarge:       "That transcript is larger than this server accepts.",
	reasonBlockedAddress: "This server does not fetch transcripts from private or local network addresses.",
	reasonHostRefused:    "The transcript's host refused the request; it may need a login.",
	reasonHostMissing:    "No transcript was found at the address the feed gives.",
	reasonHostError:      "The transcript's host answered with an error.",
	reasonUnreachable:    "The transcript's host could not be reached.",
}

// downloadSentences is the same for an episode's audio, which the fetch
// queue keeps for the episode's listing to show.
var downloadSentences = map[string]string{
	reasonNotAFeed:       "The episode's address did not return audio.",
	reasonTooLarge:       "The episode is larger than this server downloads.",
	reasonBlockedAddress: "This server does not download from private or local network addresses.",
	reasonHostRefused:    "The episode's host refused the download; it may need a login.",
	reasonHostMissing:    "The episode's host has no audio at that address anymore.",
	reasonHostError:      "The episode's host answered with an error.",
	reasonUnreachable:    "The episode's host could not be reached.",
}

// feedFault carries a feed-side failure's reason inside the service error,
// for the API to put in the body's params.
type feedFault struct {
	reason string
	err    error
}

func (f *feedFault) Error() string {
	if f.err == nil {
		return "feed-side failure: " + f.reason
	}
	return f.err.Error()
}

func (f *feedFault) Unwrap() error { return f.err }

// FeedFailureReason is the reason a feed-side failure carries, "" for any
// other error.
func FeedFailureReason(err error) string {
	var f *feedFault
	if errors.As(err, &f) {
		return f.reason
	}
	return ""
}

// feedReasonPermanent reports whether asking again can change the answer:
// a host's error or a host out of reach can pass, the rest answer the same
// until somebody changes the address or the server.
func feedReasonPermanent(reason string) bool {
	return reason != reasonHostError && reason != reasonUnreachable
}

// WaxBin's feed client words these failures without a type to test (its
// netsafe package is internal), so they are read off its messages, which
// feedfailure_test.go pins against the real client.
var (
	httpStatusFragment = regexp.MustCompile(`returned HTTP (\d{3})`)
	byteLimitFragment  = regexp.MustCompile(`exceeds \d+-byte limit`)
	redirectFragment   = regexp.MustCompile(`stopped after \d+ redirects|too many redirects`)
)

// feedFailureReason says why a feed-side fetch failed, and in what words,
// for an error feedAtFault holds to be the feed's.
func feedFailureReason(err error) (reason, sentence string) {
	reason = feedReason(err)
	return reason, feedSentences[reason]
}

func feedReason(err error) string {
	msg := err.Error()
	var status *hostStatusError
	switch {
	case errors.Is(err, errPrivateAddress), strings.Contains(msg, "non-public address"):
		return reasonBlockedAddress
	case errors.Is(err, errTranscriptTooLarge), byteLimitFragment.MatchString(msg):
		return reasonTooLarge
	case errors.As(err, &status):
		return statusReason(status.status)
	}
	if m := httpStatusFragment.FindStringSubmatch(msg); m != nil {
		code, _ := strconv.Atoi(m[1])
		return statusReason(code)
	}
	if reason, ok := tapReason(err); ok {
		return reason
	}
	var (
		syntax  *json.SyntaxError
		mistype *json.UnmarshalTypeError
		urlErr  *url.Error
		netErr  net.Error
	)
	switch {
	case waxerr.CodeOf(err) == waxerr.CodeNotFound:
		return reasonHostMissing
	case waxerr.CodeOf(err) == waxerr.CodeInvalid, waxerr.CodeOf(err) == waxerr.CodeUnsupported,
		errors.As(err, &syntax), errors.As(err, &mistype):
		return reasonNotAFeed
	case redirectFragment.MatchString(msg):
		return reasonHostError
	case errors.As(err, &urlErr) && (urlErr.Op == "parse" || strings.Contains(urlErr.Err.Error(), "unsupported protocol scheme")):
		// An address the client cannot even ask is wrong as written, and
		// no try later can reach it.
		return reasonNotAFeed
	case errors.As(err, &urlErr), errors.As(err, &netErr), errors.Is(err, io.ErrUnexpectedEOF):
		return reasonUnreachable
	}
	return reasonHostError
}

// tapReason reads a YouTube source's failure by the cause WaxTap names,
// which the provider's and the catalog's wraps keep. The rest of what it
// can say (a throttle, a page shape its parser does not know) is the
// host's trouble and left to pass.
func tapReason(err error) (string, bool) {
	var status *waxtap.HTTPStatusError
	switch {
	case errors.As(err, &status):
		return statusReason(status.StatusCode), true
	case errors.Is(err, waxtap.ErrPlaylistUnavailable):
		return reasonHostMissing, true
	case errors.Is(err, waxtap.ErrUnsupportedInput), errors.Is(err, waxtap.ErrInvalidPlaylistID),
		errors.Is(err, waxtap.ErrInvalidVideoID), errors.Is(err, waxtap.ErrVideoIDTooShort),
		errors.Is(err, waxtap.ErrVideoIDTooLong), errors.Is(err, waxtap.ErrPlaylistEmpty):
		return reasonNotAFeed, true
	case errors.Is(err, waxtap.ErrLoginRequired), errors.Is(err, waxtap.ErrMembersOnly),
		errors.Is(err, waxtap.ErrAgeRestricted), errors.Is(err, waxtap.ErrGeoBlocked),
		errors.Is(err, waxtap.ErrVideoRestricted):
		return reasonHostRefused, true
	}
	return "", false
}

// statusReason reads a host's HTTP answer: gone, refused, or an error of
// its own, which is the one a later try can find mended.
func statusReason(status int) string {
	switch {
	case status == http.StatusNotFound, status == http.StatusGone:
		return reasonHostMissing
	case status == http.StatusRequestTimeout, status == http.StatusTooEarly,
		status == http.StatusTooManyRequests, status >= 500:
		return reasonHostError
	case status >= 400:
		return reasonHostRefused
	}
	return reasonHostError
}
