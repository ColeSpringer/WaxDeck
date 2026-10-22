package service

import (
	"context"
	"errors"
	"mime"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/waxerr"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// ErrEpisodeNotFetched marks the conflict an unfetched podcast episode
// answers from StreamSource and DirectPlayInfo. The URL-minting call
// sites match on it to fall back to enclosure passthrough; the kind and
// message are unchanged, so a caller that does not match still sees the
// same typed conflict it always did.
var ErrEpisodeNotFetched = errors.New("episode audio is not fetched to the server")

// EnclosureSource is what passthrough needs to relay one unfetched
// episode: the feed's enclosure URL and the facts play-info reports
// about it. The feed's declared enclosure size is deliberately absent;
// see the relay handler for why it is not used as a Content-Length.
//
// AuthUser and AuthPass carry the show's stored feed credentials when
// the caller is entitled to them; both empty means an open feed, or a
// caller this server will not spend the credentials on. They ride every
// request made at the origin of FeedURL, the show's own feed, a redirect
// hop that lands there included, and no other, whatever host the
// enclosure names: the rule its transcript and chapters are read under.
type EnclosureSource struct {
	URL        string
	MimeType   string
	DurationMS int64
	FeedURL    string
	AuthUser   string
	AuthPass   string
	// EpisodePID is the episode's bare catalog pid, under which what its
	// host answered is remembered.
	EpisodePID model.PID
}

// EnclosureStreamSource resolves an episode PID to its feed enclosure,
// for the passthrough relay and for the play-info that points at it.
//
// The URL comes from the catalog, never from the request. That is what
// keeps /media/enclosure from being an open proxy: a caller who holds a
// media token for an episode can reach that episode's enclosure and
// nothing else. Visibility is checked where the URL is minted and again
// on every fetch (AuthorizeMedia), as it is for /media/download.
//
// userID identifies the listener, for the credential rule below; it is
// the media token's subject at the relay and the caller at every mint.
func (l *Library) EnclosureStreamSource(ctx context.Context, userID, apiEpisodePID string) (EnclosureSource, error) {
	det, err := l.getEpisode(ctx, apiEpisodePID)
	if err != nil {
		return EnclosureSource{}, err
	}
	ep := det.Episode
	raw := strings.TrimSpace(ep.EnclosureURL)
	if raw == "" {
		return EnclosureSource{}, errNotFound("episode " + apiEpisodePID + " has no enclosure to stream")
	}
	// The show decides both what the enclosure is and whose credentials
	// it takes. A show that cannot be read relays nothing: this is the
	// rule a public share's anonymous listener goes through too.
	pod, err := l.lib.Podcasts().Get(ctx, ep.PodcastPID)
	if err != nil {
		return EnclosureSource{}, classify(err)
	}
	l.showSources.Store(pod.PID, pod.SourceType)
	if !relayableEnclosure(pod.SourceType, raw, ep.EnclosureType) {
		return EnclosureSource{}, errNotFound("episode " + apiEpisodePID + " has no streamable enclosure")
	}
	out := EnclosureSource{
		URL:        raw,
		MimeType:   EnclosureMediaType(ep.EnclosureType),
		DurationMS: ep.DurationMS,
		FeedURL:    pod.FeedURL,
		EpisodePID: ep.PID,
	}
	user, pass, err := l.feedCredentials(ctx, userID, pod)
	if err != nil {
		return EnclosureSource{}, err
	}
	out.AuthUser, out.AuthPass = user, pass
	return out, nil
}

// relayableEnclosure is the single rule behind both the resolver and the
// `hasEnclosure` an episode row reports, so a client is never told an
// episode is playable by a rule the relay does not share.
//
// A YouTube show's enclosure is never relayed. WaxDeck's own provider
// stores the video's watch page there, because that is where its
// downloader starts, and relaying it would hand a player a web page. Its
// declared type has to stay what it is, since the download names the
// file by it, so the show's source is what tells them apart. Nor is one
// its feed calls a playlist or a streaming manifest (see
// [playlistMediaType]).
func relayableEnclosure(source model.SourceType, rawURL, declaredType string) bool {
	return source != model.SourceYouTube && streamableEnclosure(rawURL) && !playlistMediaType(declaredType)
}

// streamableEnclosure reports whether a feed's enclosure URL is one the
// relay can actually fetch: present, and http or https.
//
// Only those two schemes relay. A feed carrying anything else is
// malformed, and refusing here keeps the scheme set the guarded client
// assumes from depending on what a feed said. Protocol-relative URLs
// (`//cdn.example/ep.mp3`) land here too: they parse cleanly with an
// empty scheme and do occur in real feeds.
func streamableEnclosure(rawURL string) bool {
	raw := strings.TrimSpace(rawURL)
	if raw == "" {
		return false
	}
	u, err := url.Parse(raw)
	return err == nil && (u.Scheme == "http" || u.Scheme == "https")
}

// RelayableMediaType reports whether a media type names something a
// player can be handed, answering it lowercased with its parameters
// dropped: audio or video of any one format, never a playlist, and the
// three application labels real podcast hosts serve audio under. The
// relay holds a host's answer to it and the feed's declared type is
// coerced by it, so what play-info says and what the relay serves agree.
func RelayableMediaType(raw string) (string, bool) {
	mediaType, ok := parsedMediaType(raw)
	if !ok {
		return "", false
	}
	switch mediaType {
	case "application/ogg", "application/mpeg", "application/mp4":
		return mediaType, true
	}
	top, sub, _ := strings.Cut(mediaType, "/")
	if (top != "audio" && top != "video") || !formatSubtype(sub) || playlistSubtypes[sub] {
		return "", false
	}
	return mediaType, true
}

func parsedMediaType(raw string) (string, bool) {
	mediaType, _, err := mime.ParseMediaType(raw)
	return mediaType, err == nil || errors.Is(err, mime.ErrInvalidMediaParameter)
}

// playlistSubtypes are the audio and video labels of playlists, stream
// manifests and metafiles (M3U and HLS, PLS, ASX and its kin, RealMedia's,
// DASH): bytes that name further addresses, which a player handed them
// fetches itself, from wherever they say.
var playlistSubtypes = map[string]bool{
	"mpegurl": true, "x-mpegurl": true, "x-mpequrl": true, "vnd.mpegurl": true, "vnd.apple.mpegurl": true,
	"m3u": true, "x-m3u": true, "scpls": true, "x-scpls": true,
	"x-ms-asx": true, "x-ms-wax": true, "x-ms-wvx": true, "x-ms-wmx": true,
	"x-pn-realaudio": true, "x-pn-realaudio-plugin": true, "vnd.mpeg.dash.mpd": true,
}

// playlistMediaType reports whether a type names a playlist or a stream
// manifest under any top type, the application labels included.
func playlistMediaType(raw string) bool {
	mediaType, ok := parsedMediaType(raw)
	if !ok {
		return false
	}
	_, sub, _ := strings.Cut(mediaType, "/")
	switch sub {
	case "dash+xml", "vnd.ms-sstr+xml", "xspf+xml", "pls+xml":
		return true
	}
	return playlistSubtypes[sub]
}

// formatSubtype reports whether a subtype names one format: a registered
// name's letters, digits and punctuation, without the structured-syntax
// suffix (+xml, +json, +zip) that says the bytes are that syntax rather
// than media, a browser rendering an XML one as a document, and never
// the wildcard, which names no format at all.
func formatSubtype(sub string) bool {
	if sub == "" || !asciiAlnum(sub[0]) {
		return false
	}
	for i := 1; i < len(sub); i++ {
		if !asciiAlnum(sub[i]) && !strings.ContainsRune("!#$&^_.-", rune(sub[i])) {
			return false
		}
	}
	return true
}

func asciiAlnum(c byte) bool {
	return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9'
}

// EnclosureMediaType is the type an unfetched episode is reported and
// relayed as: what its feed declared when that is audio, and mp3, the
// format nearly every podcast is, when the feed declared nothing or
// something else. The declared type is the feed's word and as untrusted
// as the host's.
func EnclosureMediaType(declared string) string {
	if mediaType, ok := RelayableMediaType(declared); ok {
		return mediaType
	}
	return "audio/mpeg"
}

// declaredContainers names, for each spelling a feed declares, the label
// the catalog gives such a file once it is fetched, so an unfetched
// episode reports the pair a fetched copy reads: that label and
// flow.ContainerMime of it.
var declaredContainers = map[string]string{
	"audio/mpeg": "mp3", "audio/mp3": "mp3", "audio/x-mp3": "mp3", "audio/mpeg3": "mp3",
	"audio/x-mpeg-3": "mp3", "audio/x-mpeg": "mp3", "audio/mpga": "mp3", "application/mpeg": "mp3",
	"audio/mp4": "mp4", "audio/x-m4a": "mp4", "audio/m4a": "mp4", "audio/mp4a-latm": "mp4",
	"application/mp4": "mp4", "audio/x-m4b": "mp4", "video/mp4": "mp4", "video/x-m4v": "mp4",
	"video/quicktime": "mp4", "audio/aac": "aac (adts)", "audio/x-aac": "aac (adts)", "audio/aacp": "aac (adts)",
	"audio/ogg": "ogg", "application/ogg": "ogg", "audio/vorbis": "ogg", "audio/opus": "ogg",
	"audio/flac": "flac", "audio/x-flac": "flac",
	"audio/wav": "wav", "audio/x-wav": "wav", "audio/wave": "wav", "audio/vnd.wave": "wav",
	"audio/aiff": "aiff", "audio/x-aiff": "aiff",
	"audio/webm": "webm", "video/webm": "webm",
	"audio/x-matroska": "matroska", "video/x-matroska": "matroska",
	"audio/x-ms-wma": "asf",
}

// episodeFormat is the format a client should expect of one episode:
// the fetched file's own container, or for an episode the server has
// not fetched (or whose file's container is unknown) the one a fetched
// copy of what its feed declared would read. A spelling the table does
// not know keeps the declared type, held to the relay's rule, with no
// container.
func episodeFormat(ep *model.Episode, fetchedContainer string) (container, mimeType string) {
	if fetchedType := flow.ContainerMime(fetchedContainer); ep.Downloaded && fetchedType != "application/octet-stream" {
		return fetchedContainer, fetchedType
	}
	if strings.TrimSpace(ep.EnclosureURL) == "" {
		return "", ""
	}
	declared := EnclosureMediaType(ep.EnclosureType)
	if label, ok := declaredContainers[declared]; ok {
		return label, flow.ContainerMime(label)
	}
	return "", declared
}

// showSourceType answers a show's source type, remembered for the life
// of the process. In practice a show's source never changes once it is
// cataloged, and the relay stores what it reads on every play, so one
// that did change heals at the next play attempt; a show dropped from
// the catalog only leaves an entry behind. A read that fails is not
// remembered, and answers false.
func (l *Library) showSourceType(ctx context.Context, showPID model.PID) (model.SourceType, bool) {
	if known, ok := l.showSources.Load(showPID); ok {
		return known.(model.SourceType), true
	}
	pod, err := l.readShow(ctx, showPID)
	if err != nil {
		return "", false
	}
	l.showSources.Store(pod.PID, pod.SourceType)
	return pod.SourceType, true
}

// readShow reads one show from the catalog, through showReadHook in a test.
func (l *Library) readShow(ctx context.Context, showPID model.PID) (*model.Podcast, error) {
	if l.showReadHook != nil {
		return l.showReadHook(ctx, showPID)
	}
	return l.lib.Podcasts().Get(ctx, showPID)
}

// feedCredentials resolves the show's stored basic-auth credentials for
// one listener, empty for an open feed.
//
// A private or paid feed refuses an unauthenticated GET, so passthrough
// without these is a 401 where fetching the same episode works: WaxBin's
// download passes the same pair, and so does the transcript fetch. This
// is what keeps the two paths at parity.
//
// A private show is spent for its own subscribers only, by the rule
// shares hold it to (showIsPrivate: credentials, or a subscriber's sticky
// private mark): its credentials, or a feed address that is its own
// token, are the show's, which any subscriber shares, and an episode read
// stays open to anyone who can see the podcast library. Without this any
// account on the server could stream a paid feed on the strength of
// somebody else's subscription. A non-subscriber gets the refusal an open
// feed's listener never sees, rather than a confusing 401 relayed from a
// host they cannot authenticate to.
//
// A read that fails is the server's failure, never a refusal and never
// half a login: a 401 that answered one would be kept as the host's word.
func (l *Library) feedCredentials(ctx context.Context, userID string, pod *model.Podcast) (string, string, error) {
	if !l.showIsPrivate(ctx, pod) {
		return "", "", nil
	}
	// Bare catalog pid, which is what the subscriptions table keys on.
	if _, err := l.db.SubscriptionFor(ctx, userID, string(pod.PID)); errors.Is(err, wdb.ErrNotFound) {
		return "", "", &Error{Kind: KindForbidden,
			Msg: "this show's feed is private to its subscribers; subscribe to stream it"}
	} else if err != nil {
		return "", "", &Error{Kind: KindInternal, Err: err}
	}
	if pod.AuthUser == "" {
		return "", "", nil
	}
	pass, err := l.feedSecret(ctx, pod.PID)
	if waxerr.CodeOf(err) == waxerr.CodeNotFound {
		// A login kept without its password: the user half alone, which is
		// what the download sends.
		return pod.AuthUser, "", nil
	}
	if err != nil {
		// One the store cannot open (sealed under another key) included:
		// the server's to fix, not the caller's.
		l.log.Warn("reading a show's feed password", "show", string(pod.PID), "err", err)
		return "", "", &Error{Kind: KindInternal, Err: err}
	}
	return pod.AuthUser, pass, nil
}

// feedSecret reads a show's stored feed password, through secretReadHook
// in a test.
func (l *Library) feedSecret(ctx context.Context, showPID model.PID) (string, error) {
	key := "podcast.auth." + string(showPID)
	if l.secretReadHook != nil {
		return l.secretReadHook(ctx, key)
	}
	return l.lib.GetSecret(ctx, key)
}

// PassthroughEpisode reports whether an item is an episode that would
// stream by enclosure passthrough for this caller: an episode whose
// audio is not on this server but whose feed named an enclosure the
// caller is allowed to reach. The URL-minting call sites ask this after
// catching ErrEpisodeNotFetched, so a caller a credentialed feed will
// not be spent on keeps the conflict instead of getting a URL that
// would refuse at the relay.
func (l *Library) PassthroughEpisode(ctx context.Context, userID, apiItemPID string) (EnclosureSource, bool) {
	src, err := l.EnclosureStreamSource(ctx, userID, apiItemPID)
	if err != nil {
		return EnclosureSource{}, false
	}
	return src, true
}

// FetchEnclosure sends one request of the passthrough relay for src's
// episode, a walk of its chain or a remembered chain end, with the show's
// login on each request of the chain at the feed's origin and on no other.
func (l *Library) FetchEnclosure(req *http.Request, src EnclosureSource) (*http.Response, error) {
	resp, err := sendWithLogin(l.enclosureClient(), req, feedLogin{feedURL: src.FeedURL, user: src.AuthUser, pass: src.AuthPass})
	if err == nil && src.EpisodePID != "" && (resp.StatusCode == http.StatusOK || resp.StatusCode == http.StatusPartialContent) {
		l.noteEnclosureAnswer(req, src, resp.Header.Get("Content-Type"))
	}
	return resp, err
}

// noteEnclosureAnswer remembers the feed's own address answering a
// playlist, so a fetch never stores one as the episode, and forgets it
// once an answer passes the relay's audio gate. A remembered chain end's
// playlist is not the episode's: the relay itself does not trust it.
func (l *Library) noteEnclosureAnswer(req *http.Request, src EnclosureSource, contentType string) {
	ctx := context.WithoutCancel(req.Context())
	key := syncKeyPlaylistEnclosure + string(src.EpisodePID)
	switch {
	case playlistMediaType(contentType):
		if feed, err := url.Parse(src.URL); err != nil || feed.String() != req.URL.String() {
			return
		}
		if err := l.db.SyncStateSet(ctx, key, src.URL); err != nil {
			l.log.Warn("remembering a playlist enclosure", "episode", string(src.EpisodePID), "err", err)
		}
	case relayedAudio(contentType):
		seen, err := l.db.SyncStateGet(ctx, key)
		if err != nil || seen == "" {
			return
		}
		if err := l.db.SyncStateSet(ctx, key, ""); err != nil {
			l.log.Warn("forgetting a playlist enclosure", "episode", string(src.EpisodePID), "err", err)
		}
	}
}

// relayedAudio reports whether the relay's type gate passes an answer so
// typed: audio it can name, or no type, for which it takes the feed's
// word.
func relayedAudio(contentType string) bool {
	if _, ok := RelayableMediaType(contentType); ok {
		return true
	}
	base, _, _ := strings.Cut(strings.ToLower(contentType), ";")
	switch strings.TrimSpace(base) {
	case "", "application/octet-stream", "binary/octet-stream":
		return true
	}
	return false
}

// syncKeyPlaylistEnclosure, plus a bare episode pid, holds the enclosure
// address a host answered with a playlist.
const syncKeyPlaylistEnclosure = "enclosure_playlist:"

// playlistEnclosure reports whether an episode's enclosure is a playlist
// or a stream manifest rather than audio: its feed says so, or its host
// answered one for the address the feed names now. Such an episode has
// nothing to fetch. A failed read answers false, leaving the download to
// judge.
func (l *Library) playlistEnclosure(ctx context.Context, ep *model.Episode) bool {
	if playlistMediaType(ep.EnclosureType) {
		return true
	}
	seen, err := l.db.SyncStateGet(ctx, syncKeyPlaylistEnclosure+string(ep.PID))
	if err != nil {
		l.log.Warn("reading what an enclosure's host answered", "episode", string(ep.PID), "err", err)
		return false
	}
	return seen != "" && seen == strings.TrimSpace(ep.EnclosureURL)
}

// enclosureClient is the guarded client the passthrough relay uses:
// private destinations refused at dial time (after DNS resolution,
// defeating rebinding) unless the server allows LAN feed hosts,
// redirects capped, response headers bounded, and deliberately no
// overall timeout. An episode is an hour of audio played in real time,
// so a client-level deadline would cut a listener off mid-episode; the
// request context is what bounds a relay.
//
// The guard follows allowPrivateFeedHosts rather than the radio flag:
// an enclosure is a feed's own file, so the deployment that hosts feeds
// on its own LAN is the one that needs it.
func (l *Library) enclosureClient() *http.Client {
	l.enclosureHTTPOnce.Do(func() {
		transport := guardedTransport(l.allowPrivateFeedHosts)
		transport.ResponseHeaderTimeout = 15 * time.Second
		transport.MaxResponseHeaderBytes = 64 << 10
		l.enclosureHTTP = &http.Client{
			Transport: transport,
			CheckRedirect: func(_ *http.Request, via []*http.Request) error {
				// Go's own default cap, not a tighter one: ad-tech
				// prefix chains on real enclosures run long (a verified
				// example walks podtrac, claritas, pdst, mgln, and
				// pscrb before art19 and its CDN answer - seven hops),
				// and a cap of five turned every episode of such a show
				// into a bad gateway. Ten still bounds a loop.
				if len(via) >= 10 {
					return errors.New("too many redirects")
				}
				return nil
			},
		}
	})
	return l.enclosureHTTP
}

// notFetchedEpisode builds the conflict an unfetched episode answers.
// One constructor keeps the two resolvers' wording identical and both
// matchable with errors.Is.
func notFetchedEpisode() error {
	return &Error{
		Kind: KindConflict,
		Msg:  "episode audio is not fetched to the server yet; queue it with the fetch endpoint",
		Err:  ErrEpisodeNotFetched,
	}
}

// unfetchedEpisode reports whether an item view is an episode whose
// audio this server does not hold.
func unfetchedEpisode(it *model.ItemView) bool {
	return it.Kind == model.KindEpisode && it.State != model.StatePresent
}
