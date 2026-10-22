package api

import (
	"context"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
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
func (s *Server) enclosurePlayInfo(ctx context.Context, userID, cred, pid string, cause error) (GetPlayInfo200JSONResponse, bool) {
	if s.media == nil || !errors.Is(cause, service.ErrEpisodeNotFetched) {
		return GetPlayInfo200JSONResponse{}, false
	}
	src, ok := s.svc.PassthroughEpisode(ctx, userID, pid)
	if !ok {
		return GetPlayInfo200JSONResponse{}, false
	}
	token, exp := s.media.MintFor(auth.MediaClaims{User: userID, Cred: cred, Purpose: auth.PurposeEnclosure, PID: pid}, 0)
	s.warmEnclosure(pid, src)
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
// which is the same trade the windowed-track refusal beside it
// declines.
func (r *ConnectResolver) enclosureItem(ctx context.Context, userID, pid string, ttl time.Duration, force string, cause error) (string, string, bool) {
	if r.Media == nil || force != "" || !errors.Is(cause, service.ErrEpisodeNotFetched) {
		return "", "", false
	}
	src, ok := r.Svc.PassthroughEpisode(ctx, userID, pid)
	if !ok {
		return "", "", false
	}
	token, _ := r.Media.MintFor(auth.MediaClaims{User: userID, Purpose: auth.PurposeEnclosure, PID: pid}, ttl)
	return enclosureURL(pid, token), src.MimeType, true
}

// enclosureRelayHeaders is the allowlist of upstream response headers
// that reach the client. An allowlist rather than a denylist: a podcast
// host's Set-Cookie, its server banner, and whatever else it chooses to
// send are excluded because they are not on this list, not because
// somebody remembered to name them. Content-Type is not on it either:
// the relay states that itself, from enclosureContentType.
var enclosureRelayHeaders = []string{
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
// Only audio goes out. A host answering with a page, a document or a
// picture is refused rather than relayed, and every relayed answer
// carries nosniff and a sandboxing policy, since the bytes are a
// stranger's and the URL is this origin's.
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
	claims, err := s.media.Verify(q.Get("mt"), auth.MediaWant{Purposes: []string{auth.PurposeEnclosure}, PID: pid})
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "missing, expired, or wrong media token")
		return
	}
	user := claims.User
	// The cap is taken before the catalog read, so a caller already at
	// the ceiling is refused without a database round trip; that is why
	// this route verifies and authorizes in two steps, not verifiedMedia.
	release, ok := s.relayStreams.acquire(user)
	if !ok {
		writeError(w, http.StatusTooManyRequests, "rate-limited",
			"too many concurrent relayed streams for this account")
		return
	}
	defer release()
	if !s.authorizeMedia(w, r, claims) {
		return
	}
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
	s.relayEnclosure(w, r, pid, src)
}

// relayEnclosure moves one episode's enclosure bytes from the podcast
// host to the listener: the chain walk, the status mapping, the header
// allowlist and the bounded copy. Whoever calls it has already decided
// the listener may hear this episode and has taken the slot it costs.
func (s *Server) relayEnclosure(w http.ResponseWriter, r *http.Request, pid string, src service.EnclosureSource) {
	w.Header().Set("X-Content-Type-Options", service.MediaNoSniff)
	w.Header().Set("Content-Security-Policy", service.MediaCSP)
	// A cancellable child of the request context, so the bounds below
	// can end a transfer the listener has not abandoned. Cancelling
	// releases the upstream socket as well as the read.
	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()

	// A remembered chain end is tried first. It is a shortcut, not an
	// address: anything wrong with it, an answer the type gate below
	// refuses included, drops the entry and the full chain is walked
	// once, which is what this handler did before the cache existed.
	var resp *http.Response
	if shortcut, ok := s.enclosures.lookup(pid, src.URL); ok {
		tried, triedErr := s.fetchEnclosure(ctx, r, src, shortcut)
		if usableEnclosureResponse(tried, triedErr) && gatedEnclosureResponse(tried, src.MimeType) {
			resp = tried
		} else {
			if tried != nil {
				tried.Body.Close()
			}
			s.enclosures.forget(pid)
		}
	}
	if resp == nil {
		walked, err := s.fetchEnclosure(ctx, r, src, src.URL)
		if err != nil {
			writeError(w, http.StatusBadGateway, "service-unreachable", "the podcast host could not be reached")
			return
		}
		resp = walked
		// Recorded only for a walk: re-recording the shortcut would let
		// one entry outlive every expiry its signature carried.
		s.rememberEnclosureRoute(pid, src, resp)
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusOK, http.StatusPartialContent:
		// Relayed below.
	case http.StatusRequestedRangeNotSatisfiable:
		// The listener's range, not the host's health: a client that
		// scrubbed past the end has to see that rather than a bad
		// gateway. The host's own length goes with it, which is how a
		// player that asked for exactly the end learns it has all of it.
		if v, ok := unsatisfiedRange(resp.Header.Get("Content-Range")); ok {
			w.Header().Set("Content-Range", v)
		}
		writeError(w, http.StatusRequestedRangeNotSatisfiable, "invalid-request",
			"the requested range is outside the episode")
		return
	case http.StatusUnauthorized, http.StatusForbidden:
		// Off the feed's origin the request went without the show's
		// login, which a fetch to the server does send.
		if src.AuthUser != "" && resp.Request != nil && resp.Request.URL != nil &&
			!sameEnclosureOrigin(resp.Request.URL.String(), src.FeedURL) {
			writeError(w, http.StatusBadGateway, "feed-unreachable",
				"the episode's audio host wants the show's login, which this server sends only to the feed's own host; fetch the episode to play it")
			return
		}
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

	upstreamType := resp.Header.Get("Content-Type")
	contentType, ok := enclosureContentType(upstreamType, src.MimeType)
	if !ok {
		// Whatever it is, a browser must never be handed it from this
		// origin. The route is dropped so the next listener walks the
		// chain again rather than trusting where this one ended. The
		// label's start is logged so a real host's odd audio type can
		// join the list; the host chose all of it.
		s.enclosures.forget(pid)
		s.log.Warn("the podcast host answered with something other than audio",
			"pid", pid, "contentType", clipLabel(upstreamType))
		writeError(w, http.StatusBadGateway, "feed-unreachable",
			"the podcast host answered with a page rather than audio")
		return
	}
	out := w.Header()
	for _, name := range enclosureRelayHeaders {
		for _, v := range resp.Header.Values(name) {
			out.Add(name, v)
		}
	}
	out.Set("Content-Type", contentType)

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
	//
	// The bytes are the podcast host's and this origin-relative URL is
	// per-listener - it carries that listener's media token - so a
	// shared cache holding either would be wrong. Nothing to do with
	// the route cache above, which holds no bytes and no token: that
	// one remembers where the feed's own enclosure URL redirects to,
	// which is the same address for every listener.
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

	// Reads and writes stay apart, not folded into io.Copy, because only
	// that says who ended the stream. A failed write is the listener
	// leaving. A failed read is the host unless the request is over, as
	// media elements abort and re-range all the time.
	//
	// Whoever stops the relay before the host's own clean end, a failed
	// read or a tripped bound, breaks the response off: a clean end would
	// read as the whole episode, with a length declared or not, and the
	// player would never ask for the rest.
	//
	// A finite file takes two bounds a live stream cannot, a size cap and
	// an average rate floor; the idle watchdog alone misses a host that
	// dribbles bytes forever.
	guard := newRelayGuard(s.enclosureBounds, cancel)
	defer guard.stop()
	buf := make([]byte, 32<<10)
	for {
		n, readErr := resp.Body.Read(buf)
		// Noted before readErr is examined, so a cancel that trips the
		// idle watchdog still finds the guard stopped and is logged. The
		// write below is bracketed so the listener's pace is never charged
		// to the host: a paused player stops reading once its buffer is
		// full and the write blocks for as long as the pause lasts.
		if !guard.note(n) {
			relayed, elapsed := guard.stats()
			s.log.Warn("the episode relay was cut short",
				"pid", pid, "reason", guard.reason(),
				"bytes", relayed, "elapsed", elapsed.Round(time.Second))
			panic(http.ErrAbortHandler)
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
			if errors.Is(readErr, io.EOF) {
				return
			}
			if r.Context().Err() == nil {
				s.log.Warn("the podcast host ended the episode early",
					"pid", pid, "err", readErr)
			}
			panic(http.ErrAbortHandler)
		}
	}
}

// enclosureContentType is the type a relayed answer goes out as, false
// when the host's answer is not audio and must not go out at all.
//
// The host's type goes through relayedType. A host that does not say, or
// says only octet-stream, takes the feed's declared type, held to the
// same rule (EnclosureMediaType): the feed's word is as untrusted as the
// host's, and a response with no type will not play.
func enclosureContentType(upstream, declared string) (string, bool) {
	mediaType, untyped, ok := relayedType(upstream)
	if untyped {
		return service.EnclosureMediaType(declared), true
	}
	return mediaType, ok
}

// unsatisfiedRange reports whether a host's Content-Range is the length
// form of a refused range, "bytes */N", which is all a 416 passes on.
func unsatisfiedRange(v string) (string, bool) {
	length, ok := strings.CutPrefix(strings.TrimSpace(v), "bytes */")
	if !ok || length == "" || len(length) > 19 || strings.Trim(length, "0123456789") != "" {
		return "", false
	}
	return "bytes */" + length, true
}

// clipLabel cuts a header value a host chose to its first 100 bytes for
// a log line.
func clipLabel(v string) string {
	if len(v) <= 100 {
		return v
	}
	return strings.ToValidUTF8(v[:100], "")
}

// gatedEnclosureResponse reports whether a usable answer passes the
// type gate the relay holds it to: a 416 carries no audio to judge.
func gatedEnclosureResponse(resp *http.Response, declared string) bool {
	if resp.StatusCode == http.StatusRequestedRangeNotSatisfiable {
		return true
	}
	_, ok := enclosureContentType(resp.Header.Get("Content-Type"), declared)
	return ok
}

// fetchEnclosure performs one upstream GET for the relay against
// target, carrying the listener's range headers, on a walk and on a
// remembered chain end alike.
func (s *Server) fetchEnclosure(ctx context.Context, r *http.Request, src service.EnclosureSource, target string) (*http.Response, error) {
	req, err := s.enclosureRequest(ctx, target)
	if err != nil {
		return nil, err
	}
	// The two conditional-range headers, forwarded verbatim. If-Range
	// alone is meaningless, and a host that honors it needs the validator
	// exactly as it issued it. A request for several ranges goes up as
	// one for the whole episode, which a server may always answer: the
	// host's multipart answer would carry part headers of its own past
	// the type gate, and no media element asks for one.
	if rng := r.Header.Get("Range"); rng != "" && !strings.Contains(rng, ",") {
		req.Header.Set("Range", rng)
		if v := r.Header.Get("If-Range"); v != "" {
			req.Header.Set("If-Range", v)
		}
	}
	return s.svc.FetchEnclosure(req, src)
}

// enclosureRequest builds one outbound GET at target on the feed's
// behalf, for the relay and the background warm alike.
//
// A private or paid feed refuses an unauthenticated GET. The credentials
// are the show's own and never reach the listener, nor any host but the
// feed's own: FetchEnclosure sets them on each request of the chain at
// the feed's origin, the first or a redirect hop, and takes them off any
// other (a measurement prefix, a CDN). The service layer decides whether
// this caller gets them at all.
func (s *Server) enclosureRequest(ctx context.Context, target string) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", s.svc.UserAgent())
	return req, nil
}

// usableEnclosureResponse reports whether an upstream answer is one
// this relay can act on: exactly the statuses the switch below serves
// or reports, and nothing else.
//
// The set, not `< 400`. Go's client returns a 3xx with a nil error in
// documented cases - a redirect carrying no Location, a 304, a 305 -
// and every one of those falls through to the bad-gateway default. Read
// as usable, a remembered chain end that started answering one would
// never be invalidated, so the 502 would repeat for the whole TTL
// without the chain being re-walked even after the host recovered.
//
// 416 is in the set because it is the one refusal that is about the
// listener rather than the URL: they scrubbed past the end of the
// episode, and walking the whole chain would answer 416 again from
// further away.
//
// The same predicate decides what is worth remembering. A chain that
// ended in a 404 or an expired credential is a chain worth walking
// again, not one worth caching: cached, every retry costs the shortcut
// plus the walk and never converges, and a media element retries
// hardest on exactly this failure.
func usableEnclosureResponse(resp *http.Response, err error) bool {
	if err != nil || resp == nil {
		return false
	}
	switch resp.StatusCode {
	case http.StatusOK, http.StatusPartialContent, http.StatusRequestedRangeNotSatisfiable:
		return true
	default:
		return false
	}
}

// rememberEnclosureRoute records where a walk ended, when the entry
// would be worth having.
//
// Three refusals. A response the relay cannot act on says nothing about
// where the chain ends - see [usableEnclosureResponse]. A chain that ends
// in something the relay would refuse as not audio is not a route to
// try first. And a credentialed feed whose chain ends off its own origin
// is not shortcut: the walk can have reached that end through a request
// carrying the show's login, which a shortcut would skip, so only a
// walk says the end still answers. Remembering nothing there keeps
// such a feed at one walk per range, which is what it cost before this
// cache existed.
func (s *Server) rememberEnclosureRoute(pid string, src service.EnclosureSource, resp *http.Response) {
	if !usableEnclosureResponse(resp, nil) || !gatedEnclosureResponse(resp, src.MimeType) ||
		resp.Request == nil || resp.Request.URL == nil {
		return
	}
	resolved := resp.Request.URL.String()
	if src.AuthUser != "" && !sameEnclosureOrigin(resolved, src.FeedURL) {
		return
	}
	s.enclosures.remember(pid, src.URL, resolved)
}

// enclosureWarmDeadline bounds one background chain resolve. Longer
// than the walk should ever take and far shorter than a listen, because
// this is a head start and nothing is waiting on it.
const enclosureWarmDeadline = 30 * time.Second

// enclosureWarmDrain is the most of a warm's body that is read out so its
// connection can be reused.
const enclosureWarmDrain = 4 << 10

// warmEnclosure resolves an episode's redirect chain in the background,
// so the walk is already paid for by the time the engine's own GET
// arrives.
//
// This is the other half of the first-play cost: play-info answers in
// milliseconds and the listener then waits on seven hops before a byte
// of audio moves. One ranged GET for a single byte walks the same chain
// and fills the route cache; if it loses the race the relay walks it
// itself, exactly as before.
//
// Single-flight per episode, because a queue of taps on one show would
// otherwise walk one chain once per tap.
func (s *Server) warmEnclosure(pid string, src service.EnclosureSource) {
	if !s.enclosures.claimWarm(pid, src.URL) {
		return
	}
	// The process context rather than the request's, which ends as soon
	// as play-info is written: the whole point is to outlive it. Not
	// `context.WithoutCancel`, which strips the shutdown signal along
	// with the request's - Group.Wait blocks until every worker
	// returns, so an uncancellable walk against a host that accepted
	// and went silent would hold a stop open for its whole deadline.
	warm, cancel := context.WithTimeout(s.procCtx, enclosureWarmDeadline)
	started := s.group.GoOnce(warm, "enclosure-warm", func(wctx context.Context) error {
		defer cancel()
		defer s.enclosures.releaseWarm(pid)
		req, err := s.enclosureRequest(wctx, src.URL)
		if err != nil {
			return nil
		}
		// One byte: the chain is walked by the request, not by the body.
		req.Header.Set("Range", "bytes=0-0")
		resp, err := s.svc.FetchEnclosure(req, src)
		if err != nil {
			// Nothing to report: the relay will walk the chain itself
			// and answer the listener with whatever this would have
			// said.
			return nil
		}
		// A short body is read out so the connection can serve the
		// listener's own request; a host that ignored the range and sends
		// the whole episode is let go of instead.
		defer func() {
			io.CopyN(io.Discard, resp.Body, enclosureWarmDrain)
			resp.Body.Close()
		}()
		s.rememberEnclosureRoute(pid, src, resp)
		return nil
	})
	if !started {
		cancel()
		s.enclosures.releaseWarm(pid)
	}
}
