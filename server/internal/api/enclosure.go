package api

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// enclosurePlayInfo answers play-info for an episode whose audio is not
// on this server, when the resolver refused for exactly that reason and
// the feed named an enclosure this server can relay. False leaves the
// caller to report the conflict it was going to report, which is still
// the answer for an episode whose feed carries no enclosure.
//
// The facts come from the feed rather than from measured audio, which is
// what passthrough costs: no analysis, so no silence trim and no voice
// boost until the episode is fetched.
func (s *Server) enclosurePlayInfo(ctx context.Context, userID, pid string, cause error) (GetPlayInfo200JSONResponse, bool) {
	if s.media == nil || !errors.Is(cause, service.ErrEpisodeNotFetched) {
		return GetPlayInfo200JSONResponse{}, false
	}
	src, ok := s.svc.PassthroughEpisode(ctx, userID, pid)
	if !ok {
		return GetPlayInfo200JSONResponse{}, false
	}
	token, exp := s.media.Mint(userID, pid)
	return GetPlayInfo200JSONResponse{
		Pid:        pid,
		Url:        enclosureURL(pid, token),
		MimeType:   src.MimeType,
		DurationMs: src.DurationMS,
		// Best effort, and the spec says so: whether the podcast host
		// honors ranges is unknown until the first upstream request, and
		// probing at mint would put a third-party round trip inside every
		// play-info call. The relay forwards ranges either way.
		Seekable:  true,
		ExpiresAt: exp,
	}, true
}

// enclosureURL builds the origin-relative passthrough URL. The pid is
// the only thing that selects the target; there is no URL parameter, by
// design.
func enclosureURL(pid, token string) string {
	return "/media/enclosure?pid=" + url.QueryEscape(pid) + "&mt=" + url.QueryEscape(token)
}

// enclosureItem is the cast-endpoint form of enclosurePlayInfo: an
// origin-relative URL and the mime type to advertise for an unfetched
// episode in a device queue. The token takes the caller's ttl, which
// connect sizes to the whole queue's duration, so art and audio expire
// together rather than at a shorter hand-picked bound.
//
// force is the format the endpoint requires, and a non-empty one rules
// passthrough out. There is no local file to cut, so a relay serves
// whatever the podcast host sends: the jukebox reads a wav preamble off
// its input and fails on anything else, and a renderer given the mp3
// floor was given it because that is what it accepts. Handing either a
// raw enclosure trades a clear refusal for a failure inside the driver,
// which is the trade the multi-part refusal above already declines.
func (r *ConnectResolver) enclosureItem(ctx context.Context, userID, pid string, ttl time.Duration, force string, cause error) (string, string, bool) {
	if r.Media == nil || force != "" || !errors.Is(cause, service.ErrEpisodeNotFetched) {
		return "", "", false
	}
	src, ok := r.Svc.PassthroughEpisode(ctx, userID, pid)
	if !ok {
		return "", "", false
	}
	token, _ := r.Media.MintFor(userID, pid, ttl)
	return enclosureURL(pid, token), src.MimeType, true
}

// enclosureRelayHeaders is the allowlist of upstream response headers
// that reach the client. An allowlist rather than a denylist: a podcast
// host's Set-Cookie, its server banner, and whatever else it chooses to
// send are excluded because they are not on this list, not because
// somebody remembered to name them.
var enclosureRelayHeaders = []string{
	"Content-Type",
	"Content-Length",
	"Content-Range",
	"Accept-Ranges",
	"ETag",
	"Last-Modified",
	// Present only when the transport did not decode the body itself.
	// Go adds Accept-Encoding: gzip and transparently decompresses only
	// for a request carrying no Range, and it strips the header when it
	// does, so what survives here describes bytes that are still
	// encoded. Relaying a compressed ranged body without it would hand
	// the player noise.
	"Content-Encoding",
}

// ServeEnclosure relays a podcast episode's feed enclosure through this
// origin for an episode whose audio the server has not fetched.
//
// A proxy, not a redirect: a redirect would hand the listener's IP to
// the podcast host, and the web build could not play the result anyway
// (cross-origin, and http enclosures under an https origin are mixed
// content). The target URL is read from the episode in the catalog and
// never taken from the query, so a media token for one episode reaches
// that episode's enclosure and nothing else.
//
// Ranges pass both ways, which is the substance of this handler: a
// listener scrubs an episode, so Range and If-Range go upstream and 206,
// Content-Range, and Accept-Ranges come back. A host that ignores ranges
// answers 200 and the relay carries that through unchanged.
//
// Passthrough audio is not analyzed, so silence trim and voice boost are
// absent until the episode is fetched, and there is no local file to cut,
// so format conversion does not apply.
func (s *Server) ServeEnclosure(w http.ResponseWriter, r *http.Request) {
	if s.media == nil {
		writeError(w, http.StatusNotImplemented, "internal", "streaming is not configured on this server")
		return
	}
	q := r.URL.Query()
	pid := q.Get("pid")
	if pid == "" {
		writeError(w, http.StatusBadRequest, "invalid-request", "pid is required")
		return
	}
	user, err := s.media.Verify(q.Get("mt"), pid)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "missing, expired, or wrong media token")
		return
	}
	// The cap is taken before the catalog read, so a caller already at
	// the ceiling is refused without a database round trip.
	release, ok := s.relayStreams.acquire(user)
	if !ok {
		writeError(w, http.StatusTooManyRequests, "rate-limited",
			"too many concurrent relayed streams for this account")
		return
	}
	defer release()
	src, err := s.svc.EnclosureStreamSource(r.Context(), user, pid)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound, service.KindInvalid:
			writeError(w, http.StatusNotFound, "not-found", "no streamable enclosure for "+pid)
		case service.KindForbidden:
			writeError(w, http.StatusForbidden, "forbidden", err.Error())
		case service.KindMaintenance:
			writeError(w, http.StatusServiceUnavailable, "catalog-maintenance", "the catalog is in maintenance; retry shortly")
		default:
			writeError(w, http.StatusInternalServerError, "internal", "resolving the enclosure failed")
		}
		return
	}

	// A cancellable child of the request context, so the bounds below
	// can end a transfer the listener has not abandoned. Cancelling
	// releases the upstream socket as well as the read.
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, src.URL, nil)
	if err != nil {
		writeError(w, http.StatusBadGateway, "service-unreachable", "the podcast host could not be contacted")
		return
	}
	req.Header.Set("User-Agent", "WaxDeck")
	// A private or paid feed refuses an unauthenticated GET. The
	// credentials are the show's own and never reach the listener: they
	// are set on this outbound request, and Go strips Authorization from
	// a redirect that leaves the host, so a CDN hop does not carry them
	// either. The service layer decides whether this caller gets them.
	if src.AuthUser != "" {
		req.SetBasicAuth(src.AuthUser, src.AuthPass)
	}
	// The two conditional-range headers, forwarded verbatim. If-Range
	// alone is meaningless, and a host that honors it needs the validator
	// exactly as it issued it.
	for _, h := range []string{"Range", "If-Range"} {
		if v := r.Header.Get(h); v != "" {
			req.Header.Set(h, v)
		}
	}
	resp, err := s.svc.EnclosureHTTP().Do(req)
	if err != nil {
		writeError(w, http.StatusBadGateway, "service-unreachable", "the podcast host could not be reached")
		return
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusOK, http.StatusPartialContent:
		// Relayed below.
	case http.StatusRequestedRangeNotSatisfiable:
		// The listener's range, not the host's health: a client that
		// scrubbed past the end has to see that rather than a bad
		// gateway, which would send it looking for a network fault.
		writeError(w, http.StatusRequestedRangeNotSatisfiable, "invalid-request",
			"the requested range is outside the episode")
		return
	case http.StatusUnauthorized, http.StatusForbidden:
		// A credentialed feed whose stored credentials no longer work,
		// or a signed CDN URL from a feed refresh that has since
		// expired. Both are fixed by re-subscribing or refreshing the
		// feed, not by retrying, and neither is this server being
		// unreachable.
		writeError(w, http.StatusBadGateway, "feed-unreachable",
			"the podcast host refused this episode's credentials; refresh the feed or check the show's login")
		return
	default:
		writeError(w, http.StatusBadGateway, "service-unreachable",
			"the podcast host answered status "+strconv.Itoa(resp.StatusCode))
		return
	}

	out := w.Header()
	for _, name := range enclosureRelayHeaders {
		for _, v := range resp.Header.Values(name) {
			out.Add(name, v)
		}
	}
	// The one header this relay invents. A response with no Content-Type
	// will not play at all, and the feed's declared enclosure type is the
	// standard answer for what the audio is; guessing wrong costs a
	// mislabeled codec, which players sniff past.
	//
	// Content-Length is deliberately not backfilled from the feed's
	// declared enclosure size, which the plan proposed and which is a
	// trap: a host that omits it is answering chunked, the size a feed
	// declares is routinely stale, and declaring a length this relay
	// cannot honour makes the server truncate the body or leave the
	// client waiting for bytes that never come. A missing Content-Length
	// is a benign loss; a wrong one is a broken episode. Accept-Ranges
	// is not invented either, for the same reason in miniature: the host
	// is the only party that knows, and play-info already tells clients
	// that seeking is best effort for passthrough.
	if out.Get("Content-Type") == "" {
		out.Set("Content-Type", src.MimeType)
	}
	// The bytes are the podcast host's and the URL is per-listener; a
	// shared cache holding either would be wrong.
	out.Set("Cache-Control", "no-store")
	w.WriteHeader(resp.StatusCode)

	// A HEAD reaches this handler: Go's ServeMux routes HEAD to a GET
	// pattern, and this route is registered as one. net/http discards
	// whatever a handler writes for a HEAD, so relaying the body would
	// pull the whole episode off the podcast host only to throw it away
	// -- and cast renderers, DLNA devices, and Safari all probe with a
	// HEAD before playing, which is exactly the traffic passthrough
	// invites. The headers above are the entire answer; returning here
	// closes the upstream body through the deferred Close and abandons
	// the transfer.
	if r.Method == http.MethodHead {
		return
	}

	// Unbuffered, and the read and write halves are kept apart rather
	// than folded into io.Copy, because only that distinction says who
	// ended the stream.
	//
	// A write failure is the listener: they closed the tab, skipped, or
	// seeked, and a seek is not an error the operator wants a line
	// about. A read failure whose cause is the request context is the
	// same listener seen from the other side, since the upstream GET
	// rides r.Context(): media elements abort and re-range constantly,
	// so this is the common case, and it is exactly what a string match
	// on "broken pipe" misses. Only a read that failed for its own
	// reason is a real event: the podcast host cut the episode short,
	// which is worth a line because the listener heard it stop.
	//
	// ServeRadio makes the same split and logs neither side; the
	// difference here is that an episode has a definite length, so a
	// truncated one is a fact about the host rather than the ordinary
	// end of a live stream.
	//
	// An episode is a finite file, so this relay takes the two bounds a
	// finite transfer can carry that a live stream cannot: an overall
	// size cap and an average rate floor. Both describe a transfer that
	// was never going to finish, which is the case an idle deadline
	// alone misses -- a host dribbling bytes forever is never idle.
	guard := newRelayGuard(relayLimits{
		idle:      enclosureIdle,
		maxBytes:  enclosureMaxBytes,
		minRate:   enclosureMinRate,
		rateGrace: enclosureRateGrace,
	}, cancel)
	defer guard.stop()
	buf := make([]byte, 32<<10)
	for {
		n, readErr := resp.Body.Read(buf)
		// Noted before the write, and the write bracketed, so that the
		// listener's own pace is never charged to the podcast host. A
		// paused media element stops reading once its buffer fills and
		// the write below blocks for as long as the pause lasts; judged
		// from out here that is indistinguishable from a dead host.
		if !guard.note(n) {
			// A bound tripped, which is this server ending the transfer
			// rather than either endpoint doing it. The listener sees a
			// truncated episode either way, so it is worth a line: the
			// operator is the only one who can tell whether the host is
			// broken or the cap is too tight, and the measured bytes and
			// duration are what let them tell.
			//
			// Reached on every trip, including the idle timer's: note is
			// called before readErr is examined, and trip marks the guard
			// stopped before it cancels, so the read that returns because
			// of that cancel still finds a stopped guard here. A cut is
			// never silent.
			relayed, elapsed := guard.stats()
			s.log.Warn("the episode relay was cut short",
				"pid", pid, "reason", guard.reason(),
				"bytes", relayed, "elapsed", elapsed.Round(time.Second))
			return
		}
		if n > 0 {
			done := guard.writing()
			_, writeErr := w.Write(buf[:n])
			done()
			if writeErr != nil {
				return
			}
		}
		if readErr != nil {
			if !errors.Is(readErr, io.EOF) && r.Context().Err() == nil {
				s.log.Warn("the podcast host ended the episode early",
					"pid", pid, "err", readErr)
			}
			return
		}
	}
}
