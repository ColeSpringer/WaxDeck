package api

import (
	"net/http"
	"net/url"
	"strconv"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// castArtSize is the longest edge minted art URLs ask for. Cast
// receivers and DLNA renderers paint album art on a television or a
// small panel, so the original is wasted bytes over a LAN and a
// thumbnail rung is the honest request. 600 is what the public share
// page already uses for the same job.
const castArtSize = 600

// mediaArtURL builds the origin-relative tokenized art URL. Like the
// enclosure relay, the pid is the only thing that selects what is
// served; the token binds the same pid, so a token for one item reaches
// that item's artwork and nothing else.
func mediaArtURL(pid, token string, size int) string {
	return "/media/art?pid=" + url.QueryEscape(pid) +
		"&mt=" + url.QueryEscape(token) +
		"&size=" + strconv.Itoa(size)
}

// ServeMediaArt serves an item's artwork under a media token, for
// endpoints that cannot present a session.
//
// The session-authenticated `/items/{pid}/art` is the same bytes and is
// what every first-party client uses; a cast receiver has no cookie and
// no bearer token to send, so a queue loaded onto one arrived with no
// art URL at all and the device showed a blank tile. This is that
// endpoint behind the credential a device can carry, and nothing else:
// same service call, same visibility, same fallback chain.
//
// Caching is deliberately not the art endpoint's. That response is
// `private` and varies by credential because a browser shared by two
// accounts must not cross them; here the credential is in the URL, the
// URL is per-listener and short-lived, and the consumer is a renderer
// with no cache worth populating. `no-store` says that plainly rather
// than inviting an intermediary to key a copy on a token.
func (s *Server) ServeMediaArt(w http.ResponseWriter, r *http.Request) {
	if s.media == nil {
		writeError(w, http.StatusNotImplemented, "internal", "media tokens are not configured on this server")
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
	size := castArtSize
	if v := q.Get("size"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 16 || n > 2048 {
			writeError(w, http.StatusBadRequest, "invalid-request", "size must be between 16 and 2048")
			return
		}
		size = n
	}
	// The token names a user, and artwork follows that user's library
	// visibility exactly as it does on the session-authenticated read.
	// A token minted for an item the holder could see stays bound to
	// that item, so this re-resolve is belt and braces rather than the
	// only guard, and it is what keeps a grant revoked mid-queue from
	// continuing to serve.
	uc, err := s.svc.UserCtxByID(r.Context(), user)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "the token's account no longer exists")
		return
	}
	blob, err := s.svc.Art(r.Context(), uc, pid, "front", size)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound, service.KindInvalid:
			// Invalid lands here with not-found: a device asking for art
			// of something that has none gets the same nothing either
			// way, and it has no way to act on the difference.
			writeError(w, http.StatusNotFound, "not-found", "no artwork for pid "+pid)
		case service.KindMaintenance:
			writeError(w, http.StatusServiceUnavailable, "catalog-maintenance", "the catalog is in maintenance; retry shortly")
		default:
			// Anything else is this server failing, not the item lacking
			// a cover. Collapsing it into a 404 would make a database
			// error and a missing cover indistinguishable in the logs.
			writeError(w, http.StatusInternalServerError, "internal", "resolving artwork failed")
		}
		return
	}
	w.Header().Set("Content-Type", blob.MimeType)
	w.Header().Set("Content-Length", strconv.Itoa(len(blob.Bytes)))
	w.Header().Set("Cache-Control", "no-store")
	if r.Method == http.MethodHead {
		// Renderers probe before fetching, and net/http discards a HEAD
		// body anyway; the headers above are the whole answer.
		return
	}
	_, _ = w.Write(blob.Bytes)
}
