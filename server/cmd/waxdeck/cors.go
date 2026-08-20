package main

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
)

// How long a browser may cache a preflight answer. A day: the answer is
// derived from configuration that only changes when the process
// restarts.
const corsMaxAge = "86400"

// withCORS answers cross-origin requests from origins the operator named.
//
// Off unless configured, and off means untouched: an empty list returns
// next itself rather than a wrapper, so the default deployment serves
// byte-for-byte what it served before this existed.
//
// It exists for the browser clients WaxDeck does not serve - a Feishin or
// an Airsonic web app running on its own origin and talking to this
// server's /rest surface. Those cannot be reached by the SPA fallback,
// and a same-origin-only server is simply unusable from them.
//
// Credentials are never allowed, deliberately and permanently. Subsonic
// authenticates per request, in the query string or a header, so a
// browser client has everything it needs without the cookie jar riding
// along; allowing credentials would mean any page on a named origin
// could act as a signed-in session. The exact-origin match below is only
// a real boundary while that stays true.
// exposedHeaders is what cross-origin JS may read off a response: the
// range headers a media client needs, and the artwork provenance the
// spec documents on GET /items/{pid}/art.
const exposedHeaders = "Accept-Ranges, Content-Range, Content-Length, " +
	"X-Art-Source, X-Art-Provider, X-Art-Source-Url, X-Art-Level"

func withCORS(origins []string, next http.Handler) http.Handler {
	if len(origins) == 0 {
		return next
	}
	allowed := make(map[string]struct{}, len(origins))
	for _, origin := range origins {
		allowed[origin] = struct{}{}
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		// Always, and before the match: the answer differs by origin
		// whether or not this one is allowed, so a cache that keyed on
		// the URL alone would serve one origin's answer to another.
		//
		// Added here and re-added at write time, because several
		// handlers `Set` a Vary of their own (artwork and the stream
		// endpoints do, from the spec) and Set replaces. Those are the
		// cacheable responses where losing it matters most.
		w.Header().Add("Vary", "Origin")
		w = &corsWriter{ResponseWriter: w}

		_, ok := allowed[origin]
		if ok {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			// Without this, cross-origin JS can read only the handful of
			// safelisted response headers - so a client fetching audio
			// could not see what it was given. These are the range
			// headers a media client reads, plus artwork's provenance;
			// everything else stays hidden.
			//
			// The X-Art-* four are here because a browser is the only
			// audience they have. WaxDeck's own clients read the same
			// values off the JSON reads (an `<img>` gives its caller no
			// access to response headers), so the header form exists
			// for a third-party consumer of the byte endpoint - and the
			// third parties this middleware exists for are browser
			// apps on another origin, which without this read null.
			w.Header().Set("Access-Control-Expose-Headers", exposedHeaders)
		}

		// A preflight is answered here rather than routed: it carries no
		// credentials and names a method the mux would reject on its own
		// terms, so passing it down would answer 405 to a request that is
		// asking a question about policy.
		if r.Method == http.MethodOptions && r.Header.Get("Access-Control-Request-Method") != "" {
			w.Header().Add("Vary", "Access-Control-Request-Headers")
			if !ok {
				// Not an allowed origin: no CORS headers were set, so the
				// browser rejects it. Answered rather than routed all the
				// same - the mux has nothing to say about a preflight.
				w.WriteHeader(http.StatusNoContent)
				return
			}
			// HEAD is a CORS-safelisted method, so the Fetch spec lets it
			// through whether or not it appears here; listed anyway
			// because a media client probing a stream with HEAD is
			// exactly the shape this exists for, and a reader should not
			// have to know that clause to believe it works.
			w.Header().Set("Access-Control-Allow-Methods", "GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS")
			// Echoed verbatim rather than enumerated. The browser asks
			// about exactly the headers it means to send, and a fixed list
			// is a list that goes stale the first time a client sends one
			// nobody thought of - which fails as an opaque CORS error
			// rather than as anything a log would explain.
			if req := r.Header.Get("Access-Control-Request-Headers"); req != "" {
				w.Header().Set("Access-Control-Allow-Headers", req)
			}
			w.Header().Set("Access-Control-Max-Age", corsMaxAge)
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// corsWriter keeps `Vary: Origin` on responses whose handler sets a Vary
// of its own, and is otherwise transparent.
//
// A handler's `Set("Vary", ...)` replaces what the wrapper added on the
// way in, which would let a shared cache serve one origin's response -
// carrying that origin's Access-Control-Allow-Origin - to another. This
// runs at write time, after the handler has had its say.
//
// The delegation below is not optional, and countingWriter (httpmetrics)
// explains why at length: it sits *inside* this wrapper, so its ReadFrom
// resolves against this type. Without ReadFrom here, http.ServeContent
// loses sendfile and every media byte goes back through a userspace copy
// loop. Flush goes through a ResponseController so it reaches the real
// writer, and Unwrap is what lets the WebSocket upgrade find it.
type corsWriter struct {
	http.ResponseWriter
	varied bool
}

func (w *corsWriter) keepVary() {
	if w.varied {
		return
	}
	w.varied = true
	h := w.Header()
	for _, v := range h.Values("Vary") {
		if strings.EqualFold(v, "Origin") {
			return
		}
	}
	h.Add("Vary", "Origin")
}

func (w *corsWriter) WriteHeader(status int) {
	w.keepVary()
	w.ResponseWriter.WriteHeader(status)
}

func (w *corsWriter) Write(b []byte) (int, error) {
	w.keepVary()
	return w.ResponseWriter.Write(b)
}

func (w *corsWriter) ReadFrom(r io.Reader) (int64, error) {
	w.keepVary()
	if rf, ok := w.ResponseWriter.(io.ReaderFrom); ok {
		return rf.ReadFrom(r)
	}
	return io.Copy(w.ResponseWriter, r)
}

func (w *corsWriter) Flush() {
	// A flush with nothing written yet commits an implicit 200, so this
	// is a header-committing path like the three above it - a handler
	// that replaced Vary and then flushed would otherwise publish a
	// grant a shared cache can key without Origin.
	w.keepVary()
	_ = http.NewResponseController(w.ResponseWriter).Flush()
}

func (w *corsWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

// normalizeOrigins trims each origin, drops a trailing slash, and
// refuses anything a browser could never send.
//
// The match is exact, so `https://app.example.com/` in an env file would
// never equal the `https://app.example.com` a browser sends, and the
// symptom is a client that cannot call the server with nothing in the
// log to say why. The tolerated slash is the near miss worth accepting;
// every other one - a bare `music.example.com`, a path, an uppercase
// host - is refused rather than accepted and quietly matched against
// nothing. Refusing to start is how the trusted-proxy list handles an
// unparseable value too: a security control that silently does nothing
// is worse than one that will not boot.
func normalizeOrigins(origins []string) ([]string, error) {
	out := make([]string, 0, len(origins))
	for _, raw := range origins {
		origin := strings.TrimSuffix(strings.TrimSpace(raw), "/")
		if origin == "" {
			continue
		}
		u, err := url.Parse(origin)
		switch {
		case err != nil:
			return nil, fmt.Errorf("origin %q: %w", raw, err)
		case u.Scheme != "http" && u.Scheme != "https":
			return nil, fmt.Errorf("origin %q: needs an http:// or https:// scheme", raw)
		case u.Host == "":
			return nil, fmt.Errorf("origin %q: names no host", raw)
		case u.Path != "":
			return nil, fmt.Errorf("origin %q: an origin carries no path", raw)
		case u.RawQuery != "" || u.Fragment != "" || u.User != nil:
			return nil, fmt.Errorf("origin %q: an origin is only scheme, host, and port", raw)
		case origin != strings.ToLower(origin):
			// Browsers send the origin lowercased, so an uppercase one
			// here matches nothing. Refused rather than folded: a config
			// that reads differently from how it behaves is the thing
			// this function exists to prevent.
			return nil, fmt.Errorf("origin %q: must be lowercase, as a browser sends it", raw)
		}
		out = append(out, origin)
	}
	return out, nil
}
