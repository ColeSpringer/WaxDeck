package api

import (
	"fmt"
	"html/template"
	"mime"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/colespringer/waxdeck/server/internal/pagetext"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// The public share surface: server-rendered plain HTML at /s/{token},
// with media at /s/{token}/stream, /s/{token}/art, and
// /s/{token}/download. Opened by non-users on phones, so it never
// loads the SPA: one page, inline styles, no scripts. The token is a
// signed capability; every fetch re-resolves the share so revocation
// and expiry bite immediately.

// maxShareStreams bounds concurrent anonymous streams per share.
const maxShareStreams = 4

// shareStreamGate counts live streams per share id.
type shareStreamGate struct {
	mu   sync.Mutex
	live map[string]int
}

func (g *shareStreamGate) acquire(id string) (release func(), ok bool) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.live == nil {
		g.live = map[string]int{}
	}
	if g.live[id] >= maxShareStreams {
		return nil, false
	}
	g.live[id]++
	var once sync.Once
	return func() {
		once.Do(func() {
			g.mu.Lock()
			// Zeroed entries are dropped, or the map grows by one per
			// share id ever streamed for the life of the process.
			if g.live[id]--; g.live[id] <= 0 {
				delete(g.live, id)
			}
			g.mu.Unlock()
		})
	}, true
}

// resolveShareRequest verifies the token and loads the live share.
func (s *Server) resolveShareRequest(r *http.Request) (*service.SharePublic, string, bool) {
	if s.shares == nil {
		return nil, "", false
	}
	id, err := s.shares.Verify(r.PathValue("token"))
	if err != nil {
		return nil, "", false
	}
	pub, err := s.svc.ResolveShare(r.Context(), id)
	if err != nil {
		return nil, "", false
	}
	return pub, id, true
}

// shareHeaders are on every share response: capability URLs must not
// leak through referrers, and public pages stay out of indexes.
func shareHeaders(w http.ResponseWriter) {
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("X-Robots-Tag", "noindex, nofollow")
}

// ServeSharePage renders the landing page.
func (s *Server) ServeSharePage(w http.ResponseWriter, r *http.Request) {
	shareHeaders(w)
	// The two HTML answers are the only share responses that vary by
	// language; the stream and download routes carry bytes, and art is
	// cached publicly. Negotiated from the request rather than the
	// context: this page is not a strict-server handler.
	w.Header().Set("Vary", "Accept-Language")
	loc := pagetext.For(pagetext.Negotiate(r.Header.Get("Accept-Language")))
	pub, _, ok := s.resolveShareRequest(r)
	if !ok {
		shareNotFound(w, loc)
		return
	}
	base := "/s/" + url.PathEscape(r.PathValue("token"))
	type row struct {
		Index     int
		Title     string
		Artist    string
		Duration  string
		StreamURL string
	}
	data := struct {
		Lang        string
		T           *pagetext.Strings
		Title       string
		Subtitle    string
		ArtURL      string
		OGImage     string
		Rows        []row
		Download    bool
		DownloadURL string
		ExpiresAt   string
		Single      bool
	}{
		Lang:     loc.Lang,
		T:        loc,
		Title:    pub.Title,
		Subtitle: pub.Subtitle,
		// The page's one download link points at the first entry; a
		// virtual first entry has no standalone file (the download
		// route refuses it), so the link is not offered.
		Download: pub.Share.AllowDownload &&
			len(pub.Items) > 0 && !pub.Items[0].Virtual,
		Single: len(pub.Items) == 1,
	}
	if pub.ArtItemPID != "" {
		data.ArtURL = base + "/art"
		if s.publicBase != "" {
			data.OGImage = strings.TrimRight(s.publicBase, "/") + data.ArtURL
		}
	}
	if pub.Share.AllowDownload {
		data.DownloadURL = base + "/download"
	}
	if !pub.Share.ExpiresAt.IsZero() {
		data.ExpiresAt = loc.FormatDate(pub.Share.ExpiresAt.UTC())
	}
	for i, it := range pub.Items {
		streamURL := base + "/stream?i=" + strconv.Itoa(i)
		if i == 0 && pub.Share.PositionMs > 0 {
			// A media fragment starts playback at the shared timestamp
			// without a line of script.
			streamURL += "#t=" + strconv.FormatInt(pub.Share.PositionMs/1000, 10)
		}
		data.Rows = append(data.Rows, row{
			Index:     i,
			Title:     it.Title,
			Artist:    it.Artist,
			Duration:  formatShareDuration(it.DurationMS),
			StreamURL: streamURL,
		})
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Security-Policy",
		"default-src 'none'; media-src 'self'; img-src 'self'; style-src 'unsafe-inline'")
	if err := sharePageTmpl.Execute(w, data); err != nil {
		s.log.Warn("rendering share page", "err", err)
	}
}

func formatShareDuration(ms int64) string {
	if ms <= 0 {
		return ""
	}
	total := ms / 1000
	if total >= 3600 {
		return fmt.Sprintf("%d:%02d:%02d", total/3600, (total%3600)/60, total%60)
	}
	return fmt.Sprintf("%d:%02d", total/60, total%60)
}

func shareNotFound(w http.ResponseWriter, loc *pagetext.Strings) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusNotFound)
	// Neither value is user-supplied, so the concatenation stays; both
	// come from this repo's own tables.
	fmt.Fprintf(w, `<!doctype html><html lang="%s"><meta charset="utf-8"><title>%s</title>`+
		`<p style="font-family:system-ui;margin:3em auto;max-width:30em;text-align:center">`+
		`%s</p>`, loc.Lang, loc.ShareNotFoundTitle, loc.ShareNotFoundBody)
}

// ServeShareStream streams one member of a share.
func (s *Server) ServeShareStream(w http.ResponseWriter, r *http.Request) {
	shareHeaders(w)
	pub, id, ok := s.resolveShareRequest(r)
	if !ok {
		writeError(w, http.StatusNotFound, "not-found", "this link does not exist, has expired, or was revoked")
		return
	}
	it, ok := shareMember(pub, r)
	if !ok {
		writeError(w, http.StatusNotFound, "not-found", "no such entry")
		return
	}
	release, ok := s.shareStreams.acquire(id)
	if !ok {
		writeError(w, http.StatusTooManyRequests, "rate-limited", "too many concurrent listeners on this link")
		return
	}
	defer release()
	// Mid-playback seeks are Range fetches from a nonzero offset;
	// everything else that actually reads audio is the start of a
	// listen. Browsers send `Range: bytes=0-` on a media element's
	// very first fetch, so counting only rangeless requests would
	// miss most real plays; Safari precedes its real (bounded) fetch
	// with a tiny probe like `bytes=0-1`, which must not count a
	// second play.
	if countableShareFetch(r.Header.Get("Range")) {
		s.svc.CountSharePlay(r.Context(), id)
	}
	if s.bridge != nil {
		s.bridge.ServeShareStream(w, r, it.PID, pub.OwnerUserID)
		return
	}
	// Without the streaming engine the only bytes on offer are the
	// original file, and for a virtual track that is the whole backing
	// rip: far more audio than the owner shared. Refuse rather than
	// over-serve (the same posture as direct playback, which refuses
	// span-carved tracks it cannot cut).
	if it.Virtual {
		writeError(w, http.StatusNotImplemented, "feature-unavailable",
			"this track plays a window of a shared source file, which needs the streaming engine")
		return
	}
	s.serveShareFile(w, r, it.PID, false)
}

// countableProbeFloor separates a browser's start-of-file probe from a
// fetch that actually plays: Safari asks for `bytes=0-1` before its
// real request, while any genuine audio fetch spans far more than a
// kilobyte (even a seconds-long low-bitrate clip does).
const countableProbeFloor = 1024

// countableShareFetch reports whether one stream request begins a
// listen: no range at all, an open-ended start-of-file range, or a
// bounded start-of-file range past the probe floor. Nonzero offsets
// are mid-playback seeks, and unparsable range strings count nothing
// (failing toward undercounting).
func countableShareFetch(rangeHeader string) bool {
	if rangeHeader == "" {
		return true
	}
	rest, ok := strings.CutPrefix(rangeHeader, "bytes=0-")
	if !ok {
		return false
	}
	if rest == "" {
		return true
	}
	end, err := strconv.ParseInt(rest, 10, 64)
	if err != nil {
		return false
	}
	return end+1 >= countableProbeFloor
}

// ServeShareDownload serves the original file as an attachment.
func (s *Server) ServeShareDownload(w http.ResponseWriter, r *http.Request) {
	shareHeaders(w)
	pub, _, ok := s.resolveShareRequest(r)
	if !ok {
		writeError(w, http.StatusNotFound, "not-found", "this link does not exist, has expired, or was revoked")
		return
	}
	if !pub.Share.AllowDownload {
		writeError(w, http.StatusForbidden, "forbidden", "this link does not offer downloads")
		return
	}
	it, ok := shareMember(pub, r)
	if !ok {
		writeError(w, http.StatusNotFound, "not-found", "no such entry")
		return
	}
	// A virtual track's original bytes are the whole backing rip, not
	// the shared window; handing that to an anonymous visitor would
	// serve every track in the rip, shared or not.
	if it.Virtual {
		writeError(w, http.StatusForbidden, "forbidden",
			"this entry plays a window of a shared source file and has no standalone file to download")
		return
	}
	s.serveShareFile(w, r, it.PID, true)
}

// ServeShareArt serves the share's representative artwork.
func (s *Server) ServeShareArt(w http.ResponseWriter, r *http.Request) {
	shareHeaders(w)
	pub, _, ok := s.resolveShareRequest(r)
	if !ok || pub.ArtItemPID == "" {
		writeError(w, http.StatusNotFound, "not-found", "no artwork")
		return
	}
	blob, err := s.svc.PublicArt(r.Context(), pub.ArtItemPID, 600)
	if err != nil {
		writeError(w, http.StatusNotFound, "not-found", "no artwork")
		return
	}
	w.Header().Set("Content-Type", blob.MimeType)
	// The one art response with no session behind it and an hour of
	// public caching in front of it, which is where the hardening pair
	// earns the most.
	w.Header().Set("X-Content-Type-Options", service.ArtNoSniff)
	w.Header().Set("Content-Security-Policy", service.ArtCSP)
	w.Header().Set("Cache-Control", "public, max-age=3600")
	_, _ = w.Write(blob.Bytes)
}

// shareMember picks the requested member row (i=, default 0).
func shareMember(pub *service.SharePublic, r *http.Request) (service.ItemSummary, bool) {
	idx := 0
	if v := r.URL.Query().Get("i"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 0 {
			return service.ItemSummary{}, false
		}
		idx = n
	}
	if idx >= len(pub.Items) {
		return service.ItemSummary{}, false
	}
	return pub.Items[idx], true
}

// serveShareFile serves the item's original bytes with Range support.
func (s *Server) serveShareFile(w http.ResponseWriter, r *http.Request, apiItemPID string, attachment bool) {
	f, err := s.svc.DownloadSource(r.Context(), apiItemPID, "")
	if err != nil {
		writeError(w, http.StatusNotFound, "not-found", "the file is not available")
		return
	}
	file, err := os.Open(f.Path)
	if err != nil {
		writeError(w, http.StatusNotFound, "not-found", "the file is not available")
		return
	}
	defer file.Close()
	w.Header().Set("Content-Type", f.MimeType)
	if attachment {
		w.Header().Set("Content-Disposition",
			mime.FormatMediaType("attachment", map[string]string{"filename": f.FileName}))
	}
	http.ServeContent(w, r, "", time.Unix(0, f.MTimeNS), file)
}

// sharePageTmpl is the whole landing page: no scripts, inline styles,
// OpenGraph and Twitter tags for link previews, one audio element per
// entry (preload=none keeps a long playlist cheap).
var sharePageTmpl = template.Must(template.New("share").Parse(`<!doctype html>
<html lang="{{.Lang}}">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>{{.Title}}</title>
<meta property="og:title" content="{{.Title}}">
{{if .Subtitle}}<meta property="og:description" content="{{.Subtitle}}">{{end}}
{{if .OGImage}}<meta property="og:image" content="{{.OGImage}}">{{end}}
<meta property="og:type" content="music.song">
<meta name="twitter:card" content="summary">
<style>
  :root { color-scheme: light dark; }
  body { font-family: system-ui, sans-serif; margin: 0; padding: 2rem 1rem;
         background: Canvas; color: CanvasText; }
  main { max-width: 34rem; margin: 0 auto; }
  .art { width: 14rem; height: 14rem; border-radius: 0.75rem; object-fit: cover;
         display: block; margin: 0 auto 1.5rem; box-shadow: 0 4px 24px rgba(0,0,0,.25); }
  h1 { font-size: 1.4rem; text-align: center; margin: 0 0 0.25rem; }
  .sub { text-align: center; margin: 0 0 1.5rem; opacity: 0.7; }
  ol { list-style: none; padding: 0; margin: 0; }
  li { padding: 0.75rem 0; border-top: 1px solid color-mix(in srgb, CanvasText 15%, transparent); }
  li:first-child { border-top: none; }
  .row { display: flex; justify-content: space-between; gap: 0.5rem; margin-bottom: 0.4rem; }
  .t { font-weight: 600; }
  .a { opacity: 0.7; }
  .d { opacity: 0.55; font-variant-numeric: tabular-nums; }
  audio { width: 100%; }
  .foot { margin-top: 1.5rem; text-align: center; font-size: 0.85rem; opacity: 0.6; }
  .dl { display: inline-block; margin-top: 1rem; }
</style>
<main>
  {{if .ArtURL}}<img class="art" src="{{.ArtURL}}" alt="">{{end}}
  <h1>{{.Title}}</h1>
  {{if .Subtitle}}<p class="sub">{{.Subtitle}}</p>{{end}}
  <ol>
    {{range .Rows}}
    <li>
      {{if not $.Single}}<div class="row"><span><span class="t">{{.Title}}</span>{{if .Artist}} <span class="a">{{.Artist}}</span>{{end}}</span><span class="d">{{.Duration}}</span></div>{{end}}
      <audio controls preload="none" src="{{.StreamURL}}"></audio>
    </li>
    {{end}}
  </ol>
  {{if .Download}}<p style="text-align:center"><a class="dl" href="{{.DownloadURL}}">{{.T.ShareDownload}}</a></p>{{end}}
  <p class="foot">{{.T.ShareSharedWith}}{{if .ExpiresAt}} &middot; {{.T.ShareExpiresPrefix}} {{.ExpiresAt}}{{end}}</p>
</main>
</html>
`))
