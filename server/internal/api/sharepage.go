package api

import (
	"context"
	"errors"
	"fmt"
	"html/template"
	"io"
	"mime"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/httpcache"
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

// maxOwnerShareRelays bounds the relays every public link of one owner
// draws together, below the owner's own maxUserRelays: however popular
// the links, the owner's own listening and radio keep two slots.
const maxOwnerShareRelays = maxUserRelays - 2

// shareArtSize is the box the share page's cover is resolved at. From
// the service, which is the layer that can see the catalog's ladder and
// the one place these are kept on it.
const shareArtSize = service.ArtSizeShare

// errNoShare is a link that does not exist, has expired, or was revoked.
var errNoShare = errors.New("no such share")

// resolveShareRequest verifies the token and loads the live share. The
// error is errNoShare, or the catalog being away for a hand-off.
func (s *Server) resolveShareRequest(r *http.Request) (*service.SharePublic, string, error) {
	if s.shares == nil {
		return nil, "", errNoShare
	}
	id, err := s.shares.Verify(r.PathValue("token"))
	if err != nil {
		return nil, "", errNoShare
	}
	pub, err := s.svc.ResolveShare(r.Context(), id)
	if service.KindOf(err) == service.KindMaintenance {
		return nil, "", err
	}
	if err != nil {
		return nil, "", errNoShare
	}
	return pub, id, nil
}

// writeShareMiss answers a share route whose link did not resolve: the
// catalog away is a 503 a player retries, anything else the 404 given.
func writeShareMiss(w http.ResponseWriter, err error, notFound string) {
	if service.KindOf(err) == service.KindMaintenance {
		writeError(w, http.StatusServiceUnavailable, "catalog-maintenance", "the catalog is in maintenance; retry shortly")
		return
	}
	writeError(w, http.StatusNotFound, "not-found", notFound)
}

// shareHeaders are on every share response: capability URLs must not
// leak through referrers, public pages stay out of indexes, and no cache
// keeps an answer for a link that may be revoked. The artwork alone
// replaces the last: it is stored and revalidated at every use.
func shareHeaders(w http.ResponseWriter) {
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("X-Robots-Tag", "noindex, nofollow")
	w.Header().Set("Cache-Control", "no-store")
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
	pub, _, err := s.resolveShareRequest(r)
	if service.KindOf(err) == service.KindMaintenance {
		sharePlainPage(w, http.StatusServiceUnavailable, loc, loc.ShareAwayTitle, loc.ShareAwayBody)
		return
	}
	if err != nil {
		sharePlainPage(w, http.StatusNotFound, loc, loc.ShareNotFoundTitle, loc.ShareNotFoundBody)
		return
	}
	// The cover is resolved here rather than linked on faith: the page
	// runs no script, so an image that fails to load could not be traded
	// for the placeholder afterwards.
	art := false
	if pub.ArtItemPID != "" {
		blob, err := s.svc.PublicArt(r.Context(), pub.ArtItemPID, shareArtSize)
		art = err == nil && !artTooBigForSize(blob)
	}
	page := newSharePage(pub, loc, "/s/"+url.PathEscape(r.PathValue("token")), art, s.publicBase)
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Content-Security-Policy",
		"default-src 'none'; media-src 'self'; img-src 'self'; style-src 'unsafe-inline'")
	if err := sharePageTmpl.Execute(w, page); err != nil {
		s.log.Warn("rendering share page", "err", err)
	}
}

// sharePage is everything the landing page draws.
type sharePage struct {
	Lang        string
	T           *pagetext.Strings
	Title       string
	Subtitle    string
	ArtURL      string
	OGImage     string
	Rows        []sharePageRow
	Download    bool
	DownloadURL string
	ExpiresAt   string
	// Single is a share of one track, episode or book, whose title is
	// the page's heading already, so its row is not titled again.
	Single bool
}

// sharePageRow is one member's line. A member with nothing a visitor
// could hear draws a note where its player would be.
type sharePageRow struct {
	Index     int
	Title     string
	Artist    string
	Duration  string
	StreamURL string
	Playable  bool
}

// newSharePage lays out a resolved share; art reports whether its cover
// resolved.
func newSharePage(pub *service.SharePublic, loc *pagetext.Strings, base string, art bool, publicBase string) sharePage {
	page := sharePage{
		Lang:     loc.Lang,
		T:        loc,
		Title:    pub.Title,
		Subtitle: pub.Subtitle,
		Single:   pub.Share.TargetKind != "album" && pub.Share.TargetKind != "playlist",
	}
	// The page's one download link points at the first entry, which has
	// to be a file here: a virtual entry has no standalone file, and an
	// episode the server has not fetched has none on this server at all.
	if pub.Share.AllowDownload && len(pub.Items) > 0 && !pub.Items[0].Virtual &&
		pub.Audio[pub.Items[0].PID] == service.ShareAudioLocal {
		page.Download, page.DownloadURL = true, base+"/download"
	}
	if art {
		page.ArtURL = base + "/art"
		if publicBase != "" {
			page.OGImage = strings.TrimRight(publicBase, "/") + page.ArtURL
		}
	}
	if !pub.Share.ExpiresAt.IsZero() {
		page.ExpiresAt = loc.FormatDate(pub.Share.ExpiresAt.UTC())
	}
	for i, it := range pub.Items {
		streamURL := base + "/stream?i=" + strconv.Itoa(i)
		if i == 0 && pub.Share.PositionMs > 0 {
			// A media fragment starts playback at the shared timestamp
			// without a line of script.
			streamURL += "#t=" + strconv.FormatInt(pub.Share.PositionMs/1000, 10)
		}
		page.Rows = append(page.Rows, sharePageRow{
			Index:     i,
			Title:     it.Title,
			Artist:    it.Artist,
			Duration:  formatShareDuration(it.DurationMS),
			StreamURL: streamURL,
			Playable:  pub.Audio[it.PID].Plays(),
		})
	}
	return page
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

// sharePlainPage is the one-line page a link answers when it has nothing
// to show.
func sharePlainPage(w http.ResponseWriter, status int, loc *pagetext.Strings, title, body string) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(status)
	// Neither value is user-supplied, so the concatenation stays; both
	// come from this repo's own tables.
	fmt.Fprintf(w, `<!doctype html><html lang="%s"><meta charset="utf-8"><title>%s</title>`+
		`<p style="font-family:system-ui;margin:3em auto;max-width:30em;text-align:center">`+
		`%s</p>`, loc.Lang, title, body)
}

// ServeShareStream streams one member of a share.
func (s *Server) ServeShareStream(w http.ResponseWriter, r *http.Request) {
	shareHeaders(w)
	// On every answer, whichever path serves it: the bytes are bound for
	// an anonymous browser, and only the relay's are held to a type.
	w.Header().Set("X-Content-Type-Options", service.MediaNoSniff)
	w.Header().Set("Content-Security-Policy", service.MediaCSP)
	pub, id, err := s.resolveShareRequest(r)
	if err != nil {
		writeShareMiss(w, err, "this link does not exist, has expired, or was revoked")
		return
	}
	it, ok := shareMember(pub, r)
	if !ok {
		writeError(w, http.StatusNotFound, "not-found", "no such entry")
		return
	}
	audio := pub.Audio[it.PID]
	if !audio.Plays() {
		writeError(w, http.StatusNotFound, "not-found", "this entry has no audio to play yet")
		return
	}
	release, ok := s.shareStreams.acquire(id)
	if !ok {
		writeError(w, http.StatusTooManyRequests, "rate-limited", "too many concurrent listeners on this link")
		return
	}
	defer release()
	bound, r, over := s.beginShareTransfer(w, r, id, pub.Share.ExpiresAt)
	defer over()
	// Mid-playback seeks are Range fetches from a nonzero offset;
	// everything else that actually reads audio is the start of a
	// listen. Browsers send `Range: bytes=0-` on a media element's
	// very first fetch, so counting only rangeless requests would
	// miss most real plays; Safari precedes its real (bounded) fetch
	// with a tiny probe like `bytes=0-1`, which must not count a
	// second play, and a HEAD reads no audio at all. Counted once the
	// audio starts, so a refusal on the way counts nothing.
	counter := &sharePlayCounter{ResponseWriter: bound}
	if r.Method == http.MethodGet && countableShareFetch(r.Header.Get("Range")) {
		counter.count = func() { s.svc.CountSharePlay(r.Context(), id) }
	}
	if audio == service.ShareAudioRelay {
		s.relayShareEpisode(counter, r, pub.OwnerUserID, it.PID)
		return
	}
	if s.bridge.Up() {
		s.bridge.ServeShareStream(counter, r, it.PID, pub.OwnerUserID)
		return
	}
	// Without the streaming engine the only bytes on offer are the
	// original file, and for a virtual track that is the whole backing
	// rip: far more audio than the owner shared. Refuse rather than
	// over-serve (the same posture as direct playback, which refuses
	// span-carved tracks it cannot cut). An engine that is configured
	// and away is a wait, said with when to come back.
	if it.Virtual {
		if s.bridge != nil {
			flow.RefuseEngineDown(w)
			return
		}
		writeError(w, http.StatusNotImplemented, "feature-unavailable",
			"this track plays a window of a shared source file, which needs the streaming engine")
		return
	}
	s.serveShareFile(counter, r, it.PID, false)
}

// beginShareTransfer starts one share stream or download, whichever path
// serves it. Its writes are held to the stall bound, so a visitor who
// stops reading lets go of the link's slots, and to the link still
// serving: two row reads every few seconds while audio flows, where
// resolving again would read the whole target, so a change to the target
// itself bites on the next request. The link's end, a revoke or its
// expiry, ends the transfer at once, whatever it is waiting on. It
// answers the request to serve from, and over, which the caller defers.
func (s *Server) beginShareTransfer(w http.ResponseWriter, r *http.Request, shareID string, expiresAt time.Time) (bound *stallBoundWriter, served *http.Request, over func()) {
	ctx, cancel := context.WithCancel(r.Context())
	live := func() bool { return service.KindOf(s.svc.ShareLive(ctx, shareID)) != service.KindNotFound }
	bound = s.boundWrites(w, live)
	bound.rangeAsked = r.Header.Get("Range") != ""
	t := &shareTransfer{w: bound, cancel: cancel}
	remove := s.shareTransfers.add(shareID, t, expiresAt, live)
	return bound, r.WithContext(ctx), func() {
		remove()
		t.finish()
	}
}

// relayShareEpisode plays a share's unfetched episode through the
// enclosure relay. The visitor is anonymous, so the owner's relay slots
// pay for it, within the share of them the owner's links may take, and
// the source resolves for no account: a feed's credentials are never
// spent on a public link.
func (s *Server) relayShareEpisode(w http.ResponseWriter, r *http.Request, ownerID, pid string) {
	releaseLinks, ok := s.shareRelays.acquire(ownerID)
	if !ok {
		writeError(w, http.StatusTooManyRequests, "rate-limited",
			"too many concurrent relayed streams on this owner's links")
		return
	}
	defer releaseLinks()
	release, ok := s.relayStreams.acquire(ownerID)
	if !ok {
		writeError(w, http.StatusTooManyRequests, "rate-limited",
			"too many concurrent relayed streams for this link's owner")
		return
	}
	defer release()
	src, err := s.svc.EnclosureStreamSource(r.Context(), "", pid)
	if err != nil {
		switch service.KindOf(err) {
		case service.KindNotFound, service.KindInvalid, service.KindForbidden:
			writeError(w, http.StatusNotFound, "not-found", "this entry has no audio to play yet")
		case service.KindMaintenance:
			writeError(w, http.StatusServiceUnavailable, "catalog-maintenance", "the catalog is in maintenance; retry shortly")
		default:
			writeError(w, http.StatusInternalServerError, "internal", "resolving the episode failed")
		}
		return
	}
	s.relayEnclosure(w, r, pid, src)
}

// sharePlayCounter counts a share's play once its audio starts: on the
// first success status, 200 or 206, written for a request that begins a
// listen (count is nil for one that does not).
type sharePlayCounter struct {
	http.ResponseWriter
	count   func()
	started bool
}

func (c *sharePlayCounter) WriteHeader(code int) {
	// Informational answers are not the response starting.
	if code >= 200 && !c.started {
		c.started = true
		if c.count != nil && (code == http.StatusOK || code == http.StatusPartialContent) {
			c.count()
		}
	}
	c.ResponseWriter.WriteHeader(code)
}

func (c *sharePlayCounter) Write(b []byte) (int, error) {
	if !c.started {
		c.WriteHeader(http.StatusOK)
	}
	return c.ResponseWriter.Write(b)
}

// ReadFrom keeps the file path's sendfile, and Flush, through a
// ResponseController so it reaches the real writer whatever wraps it,
// keeps the writer a streaming one for the engine's proxy, which flushes
// as audio arrives.
func (c *sharePlayCounter) ReadFrom(src io.Reader) (int64, error) {
	if !c.started {
		c.WriteHeader(http.StatusOK)
	}
	if rf, ok := c.ResponseWriter.(io.ReaderFrom); ok {
		return rf.ReadFrom(src)
	}
	return io.Copy(c.ResponseWriter, src)
}

func (c *sharePlayCounter) Flush() {
	_ = http.NewResponseController(c.ResponseWriter).Flush()
}

func (c *sharePlayCounter) Unwrap() http.ResponseWriter { return c.ResponseWriter }

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

// ServeShareDownload serves the original file as an attachment. A
// download takes one of the link's slots, as a stream does.
func (s *Server) ServeShareDownload(w http.ResponseWriter, r *http.Request) {
	shareHeaders(w)
	pub, id, err := s.resolveShareRequest(r)
	if err != nil {
		writeShareMiss(w, err, "this link does not exist, has expired, or was revoked")
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
	if pub.Audio[it.PID] != service.ShareAudioLocal {
		writeError(w, http.StatusNotFound, "not-found", "this entry has no file on this server to download")
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
	release, ok := s.shareStreams.acquire(id)
	if !ok {
		writeError(w, http.StatusTooManyRequests, "rate-limited", "too many concurrent listeners on this link")
		return
	}
	defer release()
	bound, r, over := s.beginShareTransfer(w, r, id, pub.Share.ExpiresAt)
	defer over()
	s.serveShareFile(bound, r, it.PID, true)
}

// ServeShareArt serves the share's representative artwork.
func (s *Server) ServeShareArt(w http.ResponseWriter, r *http.Request) {
	shareHeaders(w)
	pub, _, err := s.resolveShareRequest(r)
	if err != nil {
		writeShareMiss(w, err, "no artwork")
		return
	}
	if pub.ArtItemPID == "" {
		writeError(w, http.StatusNotFound, "not-found", "no artwork")
		return
	}
	blob, err := s.svc.PublicArt(r.Context(), pub.ArtItemPID, shareArtSize)
	if err != nil {
		writeError(w, http.StatusNotFound, "not-found", "no artwork")
		return
	}
	// The same bound the sized item endpoint applies; the page renders
	// its placeholder instead of hauling an unscalable original.
	if artTooBigForSize(blob) {
		writeError(w, http.StatusNotFound, "not-found", "no artwork")
		return
	}
	// Revalidated on every use rather than cached as is: the share was
	// just resolved above, so a link revoked, expired or gone dormant
	// stops serving its cover with the rest of it, and an unchanged
	// cover costs a 304.
	w.Header().Set("Cache-Control", "public, no-cache")
	if blob.SourceHash != "" {
		etag := `"` + blob.SourceHash + "-" + strconv.Itoa(shareArtSize) + `"`
		w.Header().Set("ETag", etag)
		if httpcache.ETagMatches(r.Header.Get("If-None-Match"), etag) {
			w.WriteHeader(http.StatusNotModified)
			return
		}
	}
	w.Header().Set("Content-Type", blob.MimeType)
	// The one art response with no session behind it, which is where
	// the hardening pair earns the most.
	w.Header().Set("X-Content-Type-Options", service.ArtNoSniff)
	w.Header().Set("Content-Security-Policy", service.ArtCSP)
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
// entry that has audio (preload=none keeps a long playlist cheap).
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
  .na { margin: 0; opacity: 0.6; font-style: italic; }
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
      {{if .Playable}}<audio controls preload="none" src="{{.StreamURL}}"></audio>{{else}}<p class="na">{{$.T.ShareNotAvailable}}</p>{{end}}
    </li>
    {{end}}
  </ol>
  {{if .Download}}<p style="text-align:center"><a class="dl" href="{{.DownloadURL}}">{{.T.ShareDownload}}</a></p>{{end}}
  <p class="foot">{{.T.ShareSharedWith}}{{if .ExpiresAt}} &middot; {{.T.ShareExpiresPrefix}} {{.ExpiresAt}}{{end}}</p>
</main>
</html>
`))
