// Package subsonic is the OpenSubsonic compatibility surface: ID3 and
// folder-emulated browsing, search, cover art, streaming, playlists,
// stars and ratings, scrobbling, bookmarks, read-only podcasts, and
// the internet radio library, so mature third-party clients work
// against WaxDeck while the first-party clients mature.
// It sits on the service layer like any first-party handler; user
// mapping, visibility, media-token minting, and the scrobble outbox
// apply identically.
//
// Identifier scheme: songs are real item PIDs, and so are artists and
// albums wherever the catalog holds an entity for them. A group with no
// entity behind it - a loose track has no album row - falls back to an
// identifier minted from its display strings, opaque to clients and
// stable across requests, which is also what still resolves an id a
// client cached before the surface moved to entity pids. Cover art for
// either resolves through one of the group's member items, whose art
// chain falls back to the album and artist.
package subsonic

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"hash/fnv"
	"log/slog"
	"math"
	"net/http"
	"net/url"
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/connect"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/httpcache"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// apiVersion is the Subsonic protocol version this surface speaks.
const apiVersion = "1.16.1"

// maxCoverArtSize bounds the size a getCoverArt caller may name. The
// same ceiling the first-party art endpoint refuses above, from the one
// place the ladder's top rung is written down: anything at or below it
// rounds to a rung the rest of the server already shares, and anything
// above it would be served as asked and cached under a size nothing
// else ever requests.
const maxCoverArtSize = service.ArtSizeMax

// streamer is the slice of the WaxFlow bridge the adapter needs; nil
// when streaming is not configured.
type streamer interface {
	PlayInfoFor(ctx context.Context, user, apiItemPID string, opts flow.PlayOptions) (flow.PlayInfo, error)
	JoinedPlayInfo(ctx context.Context, user, apiItemPID string, opts flow.PlayOptions) (flow.PlayInfo, error)
	Up() bool
}

// Handler serves /rest/*.
type Handler struct {
	svc *service.Library
	// bridge may hold a nil *flow.Bridge, which answers Up false: ask Up,
	// never compare the field with nil. engine says whether one is
	// configured at all, which Up cannot tell from one that is away.
	bridge  streamer
	engine  bool
	media   *auth.MediaTokens
	version string
	log     *slog.Logger

	// The grouped index, cached against the catalog content position
	// (polling clients browse far more often than the catalog
	// changes). Read-only once built, so an entry is shared across
	// requests. idxShared is the full-visibility view; idxScoped holds
	// one entry per distinct library grant set, which is what keeps a
	// restricted account's client walk from paying a whole-catalog
	// sweep per page. Both generations are stamped with the same
	// idxTail and so drop together.
	idxMu     sync.Mutex
	idxTail   int64
	idxShared *index
	idxScoped map[string]*index

	// Playlist totals for the list response, which has no members to add
	// up.
	totalsMu sync.Mutex
	totals   map[playlistTotalKey]playlistTotal

	// sessions is the connect subsystem getNowPlaying reads; nil when
	// none was handed over.
	sessions SessionSource

	// pages stands in for the service's music lists in tests: the list,
	// and the music folder it is read for, empty for the whole catalog.
	pages func(uc *service.UserCtx, list, folder string) pageSource
	// watch stands in for service.WatchDegraded in tests.
	watch func(context.Context) (context.Context, func() bool)
}

// watchReads opens a watcher on the reads made under the context it
// returns: a build that saw a read fall back is served, never kept.
func (h *Handler) watchReads(ctx context.Context) (context.Context, func() bool) {
	if h.watch != nil {
		return h.watch(ctx)
	}
	return service.WatchDegraded(ctx)
}

// playlistTotalKey scopes a total to who asked: membership is filtered
// per caller, so a cache keyed on the pid alone would leak.
type playlistTotalKey struct {
	userID string
	scope  string // the caller's ScopeKey: a grant or rule change misses
	pid    string
}

// playlistTotal is one computed answer, valid until the playlist is
// edited or playlistTotalsTTL passes. A TTL rather than the catalog
// content position, which is wrong both ways: a play-state write moves
// no content, and one scan invalidates every entry at once.
type playlistTotal struct {
	updatedAtNS int64
	at          time.Time
	songs       int
	seconds     int
}

// playlistTotalsTTL bounds how stale a list row's totals can be.
const playlistTotalsTTL = time.Minute

// playlistTotalsCap bounds the cache. Cleared whole rather than evicted:
// an entry is four integers and cheap to rebuild.
const playlistTotalsCap = 4096

// New builds the adapter. bridge may be nil: stream then serves
// original bytes directly through the tokenized download endpoint
// (media mints the tokens), refusing only span-carved tracks it
// cannot cut.
func New(svc *service.Library, bridge *flow.Bridge, media *auth.MediaTokens, version string, log *slog.Logger) *Handler {
	return &Handler{svc: svc, bridge: bridge, engine: bridge != nil, media: media, version: version, log: log}
}

// SessionSource is the slice of the connect subsystem getNowPlaying reads.
type SessionSource interface {
	Sessions(userID string) []connect.Session
}

// WithSessions has getNowPlaying answer from src, and returns h.
func (h *Handler) WithSessions(src SessionSource) *Handler {
	h.sessions = src
	return h
}

// ServeHTTP dispatches one /rest/ request: authenticate, route, render.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		h.fail(w, r, 10, "malformed request")
		return
	}
	view := strings.TrimPrefix(r.URL.Path, "/rest/")
	view = strings.TrimSuffix(view, ".view")

	u, appPasswordID, code, msg := h.authenticate(r)
	if u == nil {
		h.fail(w, r, code, msg)
		return
	}
	// Media URLs a verb mints die with the app password that asked.
	r = r.WithContext(context.WithValue(r.Context(), credKey{}, "ap:"+appPasswordID))
	uc, err := h.svc.UserCtx(r.Context(), u)
	if err != nil {
		h.fail(w, r, 0, "resolving user failed")
		return
	}
	r = withCaller(r, uc)

	switch view {
	case "ping":
		h.ok(w, r, envelope{})
	case "getLicense":
		h.ok(w, r, envelope{License: &license{Valid: true}})
	case "getUser":
		h.getUser(w, r, u, uc)
	case "getOpenSubsonicExtensions":
		h.getOpenSubsonicExtensions(w, r)
	case "tokenInfo":
		h.ok(w, r, envelope{TokenInfo: &tokenInfo{Username: u.Username}})
	case "getMusicFolders":
		h.getMusicFolders(w, r, uc)
	case "getIndexes":
		h.getIndexes(w, r, uc)
	case "getMusicDirectory":
		h.getMusicDirectory(w, r, uc)
	case "getArtists":
		h.getArtists(w, r, uc)
	case "getArtist":
		h.getArtist(w, r, uc)
	case "getAlbum":
		h.getAlbum(w, r, uc)
	case "getAlbumList":
		h.getAlbumList(w, r, uc)
	case "getAlbumList2":
		h.getAlbumList2(w, r, uc)
	case "getRandomSongs":
		h.getRandomSongs(w, r, uc)
	case "getSongsByGenre":
		h.getSongsByGenre(w, r, uc)
	case "getSong":
		h.getSong(w, r, uc)
	case "getGenres":
		h.getGenres(w, r, uc)
	case "getArtistInfo":
		h.getArtistInfo(w, r)
	case "getArtistInfo2":
		h.getArtistInfo2(w, r)
	case "getTopSongs":
		h.getTopSongs(w, r, uc)
	case "getSimilarSongs":
		h.getSimilarSongs(w, r, uc, "similarSongs")
	case "getSimilarSongs2":
		h.getSimilarSongs(w, r, uc, "similarSongs2")
	case "getSonicSimilarTracks":
		h.getSonicSimilarTracks(w, r, uc)
	case "findSonicPath":
		h.findSonicPath(w, r, uc)
	case "getScanStatus":
		h.getScanStatus(w, r, uc)
	case "search3":
		h.search3(w, r, uc)
	case "getCoverArt":
		h.getCoverArt(w, r, uc)
	case "stream":
		h.stream(w, r, uc)
	case "download":
		h.download(w, r, uc)
	case "getPlaylists":
		h.getPlaylists(w, r, uc)
	case "getPlaylist":
		h.getPlaylist(w, r, uc)
	case "createPlaylist":
		h.createPlaylist(w, r, uc)
	case "updatePlaylist":
		h.updatePlaylist(w, r, uc)
	case "deletePlaylist":
		h.deletePlaylist(w, r, uc)
	case "star":
		h.setStar(w, r, uc, true)
	case "unstar":
		h.setStar(w, r, uc, false)
	case "setRating":
		h.setRating(w, r, uc)
	case "getStarred":
		h.getStarred(w, r, uc)
	case "getStarred2":
		h.getStarred2(w, r, uc)
	case "getPodcasts":
		h.getPodcasts(w, r, uc)
	case "getNewestPodcasts":
		h.getNewestPodcasts(w, r, uc)
	case "scrobble":
		h.scrobble(w, r, uc)
	case "getBookmarks":
		h.getBookmarks(w, r, uc, u.Username)
	case "createBookmark":
		h.createBookmark(w, r, uc)
	case "deleteBookmark":
		h.deleteBookmark(w, r, uc)
	case "getInternetRadioStations":
		h.getInternetRadioStations(w, r)
	case "createInternetRadioStation":
		h.createInternetRadioStation(w, r, uc)
	case "updateInternetRadioStation":
		h.updateInternetRadioStation(w, r)
	case "deleteInternetRadioStation":
		h.deleteInternetRadioStation(w, r)
	case "getNowPlaying":
		h.getNowPlaying(w, r, uc)
	case "jukeboxControl":
		h.fail(w, r, 0, "jukebox mode is not available on this server")
	case "savePlayQueue", "getPlayQueue":
		h.fail(w, r, 0, "play queue sync is not available on this server")
	default:
		// Everything else is an explicit stub, never a 500.
		h.fail(w, r, 0, "not implemented by this server")
	}
}

// --- auth --------------------------------------------------------------------

// authenticate resolves the request's credentials to an account: the
// OpenSubsonic apiKey scheme or classic salted-token auth, both against
// app passwords only. The login password never works here, and failures
// answer identically so the surface confirms no account's existence.
// authenticate answers the account and the app password it presented.
func (h *Handler) authenticate(r *http.Request) (*wdb.User, string, int, string) {
	username := r.Form.Get("u")
	token := r.Form.Get("t")
	salt := r.Form.Get("s")
	password := r.Form.Get("p")
	if key := r.Form.Get("apiKey"); key != "" {
		if username != "" || token != "" || salt != "" || password != "" {
			return nil, "", 43, "an API key cannot be combined with other credentials"
		}
		u, id, err := h.svc.VerifyAppPasswordKey(r.Context(), key)
		if err != nil || u == nil {
			return nil, "", 44, "invalid API key"
		}
		return u, id, 0, ""
	}
	if password != "" {
		if token != "" || salt != "" {
			return nil, "", 43, "a password cannot be combined with a token"
		}
		return nil, "", 42, "password authentication is not supported; use token authentication with an app password"
	}
	if username == "" || token == "" || salt == "" {
		return nil, "", 10, "missing authentication parameters"
	}
	u, id, err := h.svc.VerifyAppPasswordToken(r.Context(), username, token, salt)
	if err != nil || u == nil {
		return nil, "", 40, "wrong username or password"
	}
	return u, id, 0, ""
}

// credKey carries the credential a request authenticated with to the
// verbs that mint media URLs.
type credKey struct{}

func credOf(r *http.Request) string {
	cred, _ := r.Context().Value(credKey{}).(string)
	return cred
}

// getUser answers the caller's account and what it may do. Clients call
// it as the first request after credentials are entered - it is how
// Feishin decides the sign-in worked - so a server without it is a
// server they cannot log in to, whatever else it implements.
//
// The username parameter is honored only for the caller's own account
// unless the caller is an administrator, which is the protocol's rule
// and also keeps the surface from confirming that some other account
// exists.
func (h *Handler) getUser(w http.ResponseWriter, r *http.Request, u *wdb.User, uc *service.UserCtx) {
	target, tc := u, uc
	if asked := r.Form.Get("username"); asked != "" && !strings.EqualFold(asked, u.Username) {
		if !uc.Admin {
			h.fail(w, r, 50, "you are not authorized to read that user")
			return
		}
		// Resolved for real, not echoed: answering the admin's own row
		// under somebody else's name would hand a management tool the
		// wrong account's roles.
		other, err := h.svc.UserByName(r.Context(), asked)
		if err != nil {
			h.failFromService(w, r, err, "no such user")
			return
		}
		oc, err := h.svc.UserCtx(r.Context(), other)
		if err != nil {
			h.fail(w, r, 0, "resolving user failed")
			return
		}
		target, tc = other, oc
	}
	h.ok(w, r, envelope{User: &subsonicUser{
		Username:          target.Username,
		ScrobblingEnabled: true,
		AdminRole:         tc.Admin,
		SettingsRole:      tc.Admin,
		// Cover art is set through the catalog's own editor, which is
		// an administrator surface.
		CoverArtRole: tc.Admin,
		DownloadRole: tc.Download,
		UploadRole:   tc.UploadEnabled,
		PlaylistRole: true,
		StreamRole:   true,
		// Nothing behind these: there are no comments, jukeboxControl
		// refuses, the transcoder serves audio only, and this surface has
		// no share verbs and no podcast management, so a client must not
		// draw those controls.
		CommentRole:         false,
		JukeboxRole:         false,
		VideoConversionRole: false,
		PodcastRole:         false,
		ShareRole:           false,
	}})
}

// --- browse ------------------------------------------------------------------

func (h *Handler) getArtists(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, ok := h.scopedIndex(w, r, uc)
	if !ok {
		return
	}
	out := &artistsID3{IgnoredArticles: ""}
	var section *indexID3
	for _, a := range idx.artists {
		letter := indexLetter(a.name)
		if section == nil || section.Name != letter {
			out.Index = append(out.Index, indexID3{Name: letter})
			section = &out.Index[len(out.Index)-1]
		}
		section.Artists = append(section.Artists, a.id3())
	}
	h.ok(w, r, envelope{Artists: out})
}

func (h *Handler) getArtist(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	if id == "" {
		h.fail(w, r, 10, "missing id")
		return
	}
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	a := idx.findArtist(id)
	if a == nil {
		h.fail(w, r, 70, "no such artist")
		return
	}
	out := &artistWithAlbums{artistID3: a.id3()}
	for _, al := range a.albums {
		out.Albums = append(out.Albums, al.id3())
	}
	h.ok(w, r, envelope{Artist: out})
}

func (h *Handler) getAlbum(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	if id == "" {
		h.fail(w, r, 10, "missing id")
		return
	}
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	al := idx.findAlbum(id)
	if al == nil {
		h.fail(w, r, 70, "no such album")
		return
	}
	out := &albumWithSongs{albumID3: al.id3()}
	for _, tr := range al.tracks {
		out.Songs = append(out.Songs, songChild(tr, al))
	}
	h.ok(w, r, envelope{Album: out})
}

func (h *Handler) getAlbumList2(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, ok := h.scopedIndex(w, r, uc)
	if !ok {
		return
	}
	albums, marks, ref, err := h.albumList(r.Context(), r, uc, idx)
	if ref != nil {
		h.fail(w, r, ref.code, ref.msg)
		return
	}
	if err != nil {
		h.failFromService(w, r, err, "listing albums failed")
		return
	}
	out := &albumList2{}
	for _, al := range albums {
		out.Albums = append(out.Albums, al.id3())
	}
	h.ok(w, r, envelope{AlbumList2: out, entityMarks: marks})
}

func (h *Handler) getSong(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	if id == "" {
		h.fail(w, r, 10, "missing id")
		return
	}
	// An episode's streamId is its own pid, so a client resolving one
	// asks for it here.
	if strings.HasPrefix(id, service.PrefixEpisode+"-") {
		ep, showExplicit, err := h.svc.EpisodeSummaryFor(r.Context(), uc, id)
		if err != nil {
			h.failFromService(w, r, err, "no such song")
			return
		}
		song := episodeShape(ep, service.PodcastShow{PID: ep.ShowPID, Explicit: showExplicit}).child
		h.ok(w, r, envelope{Song: &song})
		return
	}
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	if tr := idx.trackByPID[id]; tr != nil {
		song := songChild(*tr, idx.albumForTrack(*tr))
		h.ok(w, r, envelope{Song: &song})
		return
	}
	// A book is a song entry wherever the surface hands one out (starred
	// lists, playlists, bookmarks), so it resolves here too.
	items, err := h.svc.SubsonicItems(r.Context(), uc, []string{id})
	if err != nil {
		h.failFromService(w, r, err, "no such song")
		return
	}
	it, ok := items[id]
	if !ok {
		h.fail(w, r, 70, "no such song")
		return
	}
	song := h.entryChild(idx, it)
	h.ok(w, r, envelope{Song: &song})
}

// getNowPlaying answers the playback sessions the caller can see, each
// the item it is on, with who plays it, the device it plays on, and how
// many minutes ago the session last moved; a paused one only for ten
// minutes after it last moved. An item the caller may not be offered is
// left out, a housemate's on a shared device included.
func (h *Handler) getNowPlaying(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	out := &nowPlaying{}
	var sessions []connect.Session
	if h.sessions != nil {
		sessions = h.sessions.Sessions(uc.ID)
	}
	now := time.Now()
	on := nowPlayingSessions(sessions, now)
	pids := make([]string, len(on))
	for i, s := range on {
		pids[i] = s.Entries[s.Index].PID
	}
	if len(on) > 0 {
		idx, err := h.index(r.Context(), uc)
		if err != nil {
			h.fail(w, r, 0, "reading the library failed")
			return
		}
		items, err := h.svc.SubsonicItems(r.Context(), uc, pids)
		if err != nil {
			h.failFromService(w, r, err, "reading what is playing failed")
			return
		}
		for _, s := range on {
			it, ok := items[s.Entries[s.Index].PID]
			if !ok {
				continue
			}
			out.Entries = append(out.Entries, nowPlayingEntry{
				child:      h.entryChild(idx, it),
				Username:   s.OwnerName,
				MinutesAgo: max(0, int(now.Sub(s.UpdatedAt).Minutes())),
				PlayerID:   playerID(s.EndpointID),
				PlayerName: s.EndpointName,
			})
		}
	}
	h.ok(w, r, envelope{NowPlaying: out})
}

// pausedNowPlaying is how long after its last report a paused session
// still lists as now playing: one parked in an open tab or on a speaker
// lives for days.
const pausedNowPlaying = 10 * time.Minute

// nowPlayingSessions picks the sessions getNowPlaying lists: live ones on
// an entry of their queue, playing or paused within pausedNowPlaying.
func nowPlayingSessions(sessions []connect.Session, now time.Time) []connect.Session {
	var on []connect.Session
	for _, s := range sessions {
		if s.Ended || s.Index < 0 || s.Index >= len(s.Entries) {
			continue
		}
		if s.Playing || now.Sub(s.UpdatedAt) <= pausedNowPlaying {
			on = append(on, s)
		}
	}
	return on
}

// playerID is the protocol's integer player id for a device: stable for
// the device, and never negative.
func playerID(endpointID string) int {
	sum := fnv.New32a()
	sum.Write([]byte(endpointID))
	return int(sum.Sum32() & math.MaxInt32)
}

func (h *Handler) getGenres(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	counts := make(map[string]*genre)
	var order []string
	for _, tr := range idx.tracks {
		if tr.Genre == "" {
			continue
		}
		g := counts[tr.Genre]
		if g == nil {
			g = &genre{Name: tr.Genre}
			counts[tr.Genre] = g
			order = append(order, tr.Genre)
		}
		g.SongCount++
	}
	for _, al := range idx.albums {
		for _, name := range al.genres {
			counts[name].AlbumCount++
		}
	}
	sort.Strings(order)
	out := &genres{}
	for _, name := range order {
		out.Genres = append(out.Genres, *counts[name])
	}
	h.ok(w, r, envelope{Genres: out})
}

func (h *Handler) search3(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	q := strings.TrimSpace(r.Form.Get("query"))
	// Clients send empty or `""` probes to enumerate; answer over the
	// index instead of erroring.
	q = strings.Trim(q, `"`)
	idx, ok := h.scopedIndex(w, r, uc)
	if !ok {
		return
	}
	match := func(s string) bool {
		return q == "" || strings.Contains(strings.ToLower(s), strings.ToLower(q))
	}
	out := &searchResult3{}
	// Clamped as the other lists are, except that zero asks for none: a
	// client counting songs asks for no artists and no albums beside them.
	count := func(name string) int { return min(max(formInt(r, name, 20), 0), 500) }
	artistCount, albumCount, songCount := count("artistCount"), count("albumCount"), count("songCount")
	// The offsets are how a client walks a result set larger than one
	// page, and clients lean on them harder than "page 2" suggests:
	// Feishin discovers how many tracks a server holds by asking for
	// one song at a rising offset until the answer is empty, so a
	// surface that ignores songOffset answers song one forever and its
	// track list never finishes loading.
	artistSkip := max(formInt(r, "artistOffset", 0), 0)
	albumSkip := max(formInt(r, "albumOffset", 0), 0)
	songSkip := max(formInt(r, "songOffset", 0), 0)
	for _, a := range idx.artists {
		if len(out.Artists) >= artistCount {
			break
		}
		if match(a.name) {
			if artistSkip > 0 {
				artistSkip--
				continue
			}
			out.Artists = append(out.Artists, a.id3())
		}
	}
	for _, al := range idx.albums {
		if len(out.Albums) >= albumCount {
			break
		}
		if match(al.name) || match(al.artist) {
			if albumSkip > 0 {
				albumSkip--
				continue
			}
			out.Albums = append(out.Albums, al.id3())
		}
	}
	for _, tr := range idx.tracks {
		if len(out.Songs) >= songCount {
			break
		}
		if match(tr.Title) || match(tr.Artist) || match(tr.Album) {
			if songSkip > 0 {
				songSkip--
				continue
			}
			al := idx.albumForTrack(tr)
			out.Songs = append(out.Songs, songChild(tr, al))
		}
	}
	h.ok(w, r, envelope{SearchResult3: out})
}

func (h *Handler) getCoverArt(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	if id == "" {
		h.fail(w, r, 10, "missing id")
		return
	}
	pid := id
	// Artist and album ids resolve through a member item, whose art
	// chain falls back to album and artist artwork. An entity pid could
	// be handed to the art path directly, but the artist level has no
	// derived fallback to a member's embedded cover the way the album
	// level does, so going through a member is what keeps artist covers
	// working for a library whose artists carry no art of their own.
	// Playlist ids need none of that: a playlist is a terminal art level
	// holding its own cover, and it goes straight to the art path, which
	// applies the same owner-or-shared gate as every other playlist read.
	if entityGroupID(id) {
		idx, err := h.index(r.Context(), uc)
		if err != nil {
			h.fail(w, r, 0, "reading the library failed")
			return
		}
		var tracks []track
		if al := idx.findAlbum(id); al != nil {
			tracks = al.tracks
		} else if a := idx.findArtist(id); a != nil && len(a.albums) > 0 {
			tracks = a.albums[0].tracks
		}
		if len(tracks) == 0 {
			h.failStatus(w, r, http.StatusNotFound, 70, "no such cover")
			return
		}
		pid = tracks[0].PID
	}
	size := formInt(r, "size", 0)
	// The protocol lets a client name any size, and a size past the top
	// of the ladder is served as asked rather than rounded - so an
	// arbitrary one would mint a bespoke derivative row per client whim.
	// Clamped to the ceiling the first-party endpoint enforces, which is
	// the top rung.
	if size > maxCoverArtSize {
		size = maxCoverArtSize
	}
	// Subsonic has no artwork-slot concept; it always serves the front cover.
	blob, err := h.svc.Art(r.Context(), uc, pid, "", size)
	if err != nil {
		// A cover that is not there is a 404 an image element can see;
		// a read that failed for another reason says so as the protocol
		// does.
		if service.KindOf(err) == service.KindNotFound {
			h.failStatus(w, r, http.StatusNotFound, 70, "no such cover")
			return
		}
		h.failFromService(w, r, err, "no such cover")
		return
	}
	// The same validator the first-party art endpoint mints: the source
	// hash scoped by the rung that answered, not by the size typed into
	// the query. Covers are the bulkiest thing these clients refetch,
	// and the protocol says nothing against ordinary HTTP revalidation.
	etag := fmt.Sprintf("%q", fmt.Sprintf("%s-%d", blob.SourceHash, blob.Box))
	w.Header().Set("ETag", etag)
	if httpcache.ETagMatches(r.Header.Get("If-None-Match"), etag) {
		w.WriteHeader(http.StatusNotModified)
		return
	}
	w.Header().Set("Content-Type", blob.MimeType)
	// A Subsonic client carries its credentials in the query string, so
	// this URL is one a browser can open by hand; the hardening pair is
	// what keeps a picture that turned out to be markup from running as
	// the reader.
	w.Header().Set("X-Content-Type-Options", service.ArtNoSniff)
	w.Header().Set("Content-Security-Policy", service.ArtCSP)
	w.Write(blob.Bytes)
}

func (h *Handler) stream(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	if id == "" {
		h.fail(w, r, 10, "missing id")
		return
	}
	// Only a book can lay out in parts, and the visibility read says
	// whether this is one, so nothing else is read for its layout.
	book, err := h.svc.VisibleBook(r.Context(), uc, id)
	if err != nil {
		h.fail(w, r, 70, "no such song")
		return
	}
	if !h.bridge.Up() {
		h.streamDirect(w, r, uc, id, book)
		return
	}
	format := strings.ToLower(strings.TrimSpace(r.Form.Get("format")))
	// A book in parts is one song here, so it streams as one.
	if book {
		parts, err := h.svc.BookParts(r.Context(), id)
		if err != nil {
			h.fail(w, r, 0, "resolving stream failed")
			return
		}
		if len(parts) > 1 {
			h.streamBook(w, r, uc, id, format, parts)
			return
		}
	}
	// A bitrate cap and a start offset are the stream parameters this
	// surface honours; the mint clamps both.
	//
	// `format` is read only as a capped encode's target. `raw` is the
	// protocol's own "do not transcode", so it beats the cap outright;
	// anything else is what the client says it decodes, and a cap that
	// landed in another container would be silence on a client that
	// asked for the best quality it could play. A client that names no
	// format gets MP3, the one lossy format every client decodes. A
	// format on its own still changes nothing: without a cap, the
	// client's or the account's, there is no encode to aim.
	opts := flow.PlayOptions{Cred: credOf(r)}
	if format != "raw" {
		opts.CapFormat = format
		if format == "" {
			opts.CapFormat = "mp3"
		}
	}
	if br := formInt(r, "maxBitRate", 0); br > 0 && format != "raw" {
		// Passed on as asked: the protocol has no way to refuse a number
		// and clients send whatever their setting says, so the mint's own
		// clamp is what makes it a bitrate the engine can speak.
		opts.MaxBitrateKbps = br
	}
	// An offset is the only way this protocol positions a stream, so it
	// cuts an original too (which plays directly otherwise); raw is the
	// file as it is, which a cut is not.
	if ms, ok := timeOffsetMS(r); ok && format != "raw" {
		opts.StartMS = ms
		opts.CutOriginal = true
	}
	info, err := h.bridge.PlayInfoFor(r.Context(), uc.ID, id, opts)
	if errors.Is(err, flow.ErrEngineDown) {
		h.streamDirect(w, r, uc, id, book)
		return
	}
	if err != nil {
		// An episode the server has not fetched is relayed as the feed's
		// own file, which no offset cuts. Handed over from its top, it
		// would play while a client positioning by timeOffset alone reads
		// its clock as the place it asked for, and saves that back.
		if opts.StartMS > 0 && errors.Is(err, service.ErrEpisodeNotFetched) {
			h.fail(w, r, 0, "this episode's audio is not on the server, so it cannot start part way in")
			return
		}
		if h.redirectToEnclosure(w, r, uc.ID, id, err) {
			return
		}
		h.fail(w, r, 0, "resolving stream failed")
		return
	}
	// The tokenized URL is same-origin; a redirect keeps the adapter
	// out of the byte path and rides the same proxy as first-party
	// playback.
	http.Redirect(w, r, info.URL, http.StatusFound)
}

// streamDirect serves the original bytes, by redirect to the download
// route: what a server without the streaming engine always does, and one
// whose engine is away does until it answers. Subsonic clients cannot
// clip, so a track carved out of a larger file is the one thing this
// must refuse; and an offset is refused while the engine is away, since
// a client positioning by timeOffset alone would read its clock as the
// place it asked for while the file plays from its top.
func (h *Handler) streamDirect(w http.ResponseWriter, r *http.Request, uc *service.UserCtx, id string, book bool) {
	if h.media == nil {
		h.fail(w, r, 0, "streaming is not configured on this server")
		return
	}
	raw := strings.ToLower(strings.TrimSpace(r.Form.Get("format"))) == "raw"
	if _, offset := timeOffsetMS(r); offset && h.engine && !raw {
		h.fail(w, r, 0, "the streaming engine is not reachable right now, so this cannot start part way in")
		return
	}
	// A book in parts streams as one where no encode is needed: parts
	// all MP3 at one rate and one channel count join frame by frame.
	// Any other plays its first part, named, since the download route
	// serves a book in parts one file at a time.
	var parts []flow.Part
	if book {
		var err error
		if parts, err = h.svc.StreamParts(r.Context(), id); err != nil {
			h.failFromService(w, r, err, "no such song")
			return
		}
	}
	if service.JoinableMP3(parts) {
		token, _ := h.media.MintFor(auth.MediaClaims{
			User: uc.ID, Cred: credOf(r), Purpose: auth.PurposeStream, PID: id, Shape: service.JoinShape,
		}, 0)
		http.Redirect(w, r, "/media/download?pid="+url.QueryEscape(id)+
			"&mt="+url.QueryEscape(token)+"&"+service.JoinShape, http.StatusFound)
		return
	}
	part := ""
	if len(parts) > 1 {
		part = parts[0].FilePID
	}
	res, err := h.svc.DirectPlayInfo(r.Context(), uc, id, part)
	if err != nil {
		if h.redirectToEnclosure(w, r, uc.ID, id, err) {
			return
		}
		h.failFromService(w, r, err, "no such song")
		return
	}
	if res.HasSpan {
		h.fail(w, r, 0, "this track is a window into a larger file; playing it needs the streaming engine")
		return
	}
	token, _ := h.media.MintFor(auth.MediaClaims{
		User: uc.ID, Cred: credOf(r), Purpose: auth.PurposeStream, PID: id,
	}, 0)
	loc := "/media/download?pid=" + url.QueryEscape(id) + "&mt=" + url.QueryEscape(token) +
		"&id=" + url.QueryEscape(res.File.ETag)
	if part != "" {
		loc += "&f=" + url.QueryEscape(part)
	}
	http.Redirect(w, r, loc, http.StatusFound)
}

// streamBook redirects to a book in parts, laid out as parts, as the one
// stream the client plays it as: from the part its offset falls in,
// resolved as play-info resolves it and cut from inside, through the last
// part. The stream is an encode whatever is asked, since only an encode
// joins the parts, so a format is a preference it overrides, and raw, the
// file as it is, which such a book has none of, still gets the book from
// its offset, at the book's own rate rather than a cap.
func (h *Handler) streamBook(w http.ResponseWriter, r *http.Request, uc *service.UserCtx, id, format string, parts []service.PlayPart) {
	opts := flow.PlayOptions{Cred: credOf(r)}
	if br := formInt(r, "maxBitRate", 0); br > 0 && format != "raw" {
		opts.MaxBitrateKbps = br
	}
	// Floored on the book, where whole seconds share an encode; a part
	// starts at any millisecond, so the cut inside it is exact.
	if ms, ok := timeOffsetMS(r); ok && ms >= 1000 {
		ms -= ms % 1000
		part := service.PlayPartAt(parts, ms)
		opts.FilePID = part.FilePID
		opts.StartMS = max(ms-part.StartMS, 0)
	}
	info, err := h.bridge.JoinedPlayInfo(r.Context(), uc.ID, id, opts)
	if errors.Is(err, flow.ErrEngineDown) {
		h.streamDirect(w, r, uc, id, true)
		return
	}
	if err != nil {
		h.fail(w, r, 0, "resolving stream failed")
		return
	}
	http.Redirect(w, r, info.URL, http.StatusFound)
}

// timeOffsetMS reads stream's timeOffset, in seconds; anything but a
// finite positive number is no offset. The mint clamps it into the item,
// so the bound here only keeps the conversion in range.
func timeOffsetMS(r *http.Request) (int64, bool) {
	secs, err := strconv.ParseFloat(strings.TrimSpace(r.Form.Get("timeOffset")), 64)
	if err != nil || math.IsNaN(secs) || math.IsInf(secs, 0) || secs <= 0 {
		return 0, false
	}
	return int64(min(secs, 1e9) * 1000), true
}

// redirectToEnclosure sends a client to the passthrough relay when the
// stream resolver refused because the episode's audio is not on this
// server and the feed named an enclosure. Same shape as the two other
// branches of stream: a same-origin redirect keeps the adapter out of
// the byte path.
//
// maxBitRate and format conversion do not apply to a passthrough
// episode. There is no local file for the streaming engine to cut, so
// the relay is raw and those parameters are ignored rather than
// silently honored, which is the same thing the direct-bytes branch
// above already does.
func (h *Handler) redirectToEnclosure(w http.ResponseWriter, r *http.Request, userID, id string, cause error) bool {
	if h.media == nil || !errors.Is(cause, service.ErrEpisodeNotFetched) {
		return false
	}
	if _, ok := h.svc.PassthroughEpisode(r.Context(), userID, id); !ok {
		return false
	}
	token, _ := h.media.MintFor(auth.MediaClaims{
		User: userID, Cred: credOf(r), Purpose: auth.PurposeEnclosure, PID: id,
	}, 0)
	http.Redirect(w, r, "/media/enclosure?pid="+url.QueryEscape(id)+
		"&mt="+url.QueryEscape(token), http.StatusFound)
	return true
}

// download serves the protocol's untouched original, which is what the
// download right governs: refused without it (error 50), resolved with
// the visibility download-info applies, and never transcoded, so
// maxBitRate and format do not apply.
func (h *Handler) download(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	if id == "" {
		h.fail(w, r, 10, "missing id")
		return
	}
	if !uc.Admin && !uc.Download {
		h.fail(w, r, 50, "this account cannot download originals")
		return
	}
	if h.media == nil {
		h.fail(w, r, 0, "downloads are not configured on this server")
		return
	}
	res, err := h.svc.DownloadInfo(r.Context(), uc, id)
	if err != nil {
		// An episode whose audio was never fetched has its original at
		// the feed, which the relay serves untouched, as stream does.
		if h.redirectToEnclosure(w, r, uc.ID, id, err) {
			return
		}
		h.failFromService(w, r, err, "no such song")
		return
	}
	// One song is one file to a Subsonic client: a book in parts, or a
	// track carved out of a larger file, has no such file to hand over.
	if len(res.Files) != 1 || res.HasSpan {
		h.fail(w, r, 0, "this item is not one whole file; download it from the WaxDeck app")
		return
	}
	f := res.Files[0]
	token, _ := h.media.MintFor(auth.MediaClaims{
		User: uc.ID, Cred: credOf(r), Purpose: auth.PurposeDownload, PID: id,
	}, 0)
	http.Redirect(w, r, "/media/download?pid="+url.QueryEscape(id)+"&mt="+url.QueryEscape(token)+
		"&f="+url.QueryEscape(f.FilePID)+"&id="+url.QueryEscape(f.ETag), http.StatusFound)
}

// --- the entity-keyed index --------------------------------------------------

type track = service.TrackFacts

type album struct {
	// id is what the protocol carries: the catalog's album entity pid
	// where the tracks have one, a minted identifier otherwise. pid is
	// empty in the minted case, which is how the entity-scoped surfaces
	// tell the two apart.
	id       string
	pid      string
	artist   string
	artistID string
	name     string
	year     int
	// genre is the one most of the tracks carry; genres is every one any
	// of them does, which is what a genre list matches on.
	genre    string
	genres   []string
	durMS    int64
	explicit bool
	tracks   []track
}

// hasGenre reports whether any of the album's tracks carries g.
func (al *album) hasGenre(g string) bool {
	return slices.Contains(al.genres, g)
}

type artist struct {
	id     string
	pid    string
	name   string
	albums []*album
}

type index struct {
	// tail is the catalog position the index was built at, and facts the
	// entity facts it was built with, which a folder's index is cut from.
	// folder is the library a cut holds, empty for a caller's whole index.
	tail   int64
	facts  map[string]service.EntityFacts
	folder string

	// What is derived from the index once it is built: the folder cuts,
	// the newest list folded as far as anyone has asked, the albums in
	// artist order, and each caller's folds of their own played lists.
	cutsMu       sync.Mutex
	cuts         map[string]*index
	newestMu     sync.Mutex
	newest       fold
	byArtistOnce sync.Once
	byArtist     []*album
	playedMu     sync.Mutex
	played       map[string]*playedFolds

	tracks     []track
	artists    []*artist
	albums     []*album
	artistByID map[string]*artist
	albumByID  map[string]*album
	trackByPID map[string]*track
	// albumByTrack records the group each track actually joined, keyed
	// by item pid. Reconstructing it from the track's tags would miss
	// wherever the group took the catalog's canonical spelling instead.
	albumByTrack map[string]*album

	// Display-key maps, kept only so an identifier a client cached
	// before the surface moved to entity pids still resolves. Best
	// effort: an id minted from a tag spelling this build no longer
	// displays misses, and the client refetches the index.
	artistByName map[string]*artist
	albumByKey   map[string]*album
}

// findArtist resolves an artist identifier from either scheme: the
// entity pid the surface hands out now, or a minted id a client cached
// before the cutover. Every caller goes through it rather than
// re-deriving the fallback.
func (idx *index) findArtist(id string) *artist {
	if a := idx.artistByID[id]; a != nil {
		return a
	}
	if name, ok := decodeArtistID(id); ok {
		return idx.artistByName[name]
	}
	return nil
}

// findAlbum is findArtist's album twin.
func (idx *index) findAlbum(id string) *album {
	if al := idx.albumByID[id]; al != nil {
		return al
	}
	if artistName, albumName, ok := decodeAlbumID(id); ok {
		return idx.albumByKey[albumKey(artistName, albumName)]
	}
	return nil
}

// albumForTrack finds the album a track grouped under, which every song
// response needs for its album and artist linkage.
func (idx *index) albumForTrack(tr track) *album {
	return idx.albumByTrack[tr.PID]
}

// idxScopedCap bounds the per-grant-set cache. An entry holds the whole
// sweep it grouped, and only the full-visibility sweep is cached in the
// service beneath, so each scoped entry is an unshared copy of most of
// the catalog. That makes this a memory cap rather than a hit rate:
// four is chosen against the resident cost, not against how many
// accounts are browsing, and every restricted account sharing one grant
// set shares one entry. An entry browsed by music folder also holds its
// folder cuts, together up to one more copy of its tracks.
const idxScopedCap = 4

// indexScope identifies the visibility an index was built for: empty
// for an unrestricted caller, otherwise the caller's sorted library
// grants and content rules behind prefixes, so an account granted
// nothing does not read as an administrator. Library pids are ULIDs,
// so the comma cannot appear inside one; the rule component is
// length-prefixed so no rule value can fake a boundary.
//
// The key must name every per-caller input of the sweep it fronts:
// sweepTrackFacts filters on viewVisible (the row's library against
// uc.Libraries) and conjoins the caller's tag rules (contentRuleNode). A
// third input added there has to be added here in the same change, or
// one account reads another's index. The service-level trackFacts cache
// shares the assumption, gated on the same rule-free predicate.
func indexScope(uc *service.UserCtx) string {
	scope := ""
	if !uc.AllLibraries {
		libs := make([]string, 0, len(uc.Libraries))
		for lib, granted := range uc.Libraries {
			if granted {
				libs = append(libs, lib)
			}
		}
		sort.Strings(libs)
		scope = "r:" + strings.Join(libs, ",")
	}
	return scope + contentRuleScope(uc)
}

// contentRuleScope is the tag-rule component of indexScope, empty
// exactly when contentRuleNode narrows nothing (an administrator, or
// no rules), so rule-free callers keep sharing the entries they always
// shared.
func contentRuleScope(uc *service.UserCtx) string {
	if uc.Admin || (len(uc.TagAllow) == 0 && len(uc.TagDeny) == 0) {
		return ""
	}
	var b strings.Builder
	writeRules := func(label string, rules []service.TagRule) {
		b.WriteString(label)
		for _, r := range rules {
			fmt.Fprintf(&b, "%d:%s=%d:%s,", len(r.Key), r.Key, len(r.Value), r.Value)
		}
	}
	writeRules("|allow:", uc.TagAllow)
	writeRules("|deny:", uc.TagDeny)
	return b.String()
}

// index returns the grouped view over the service's track sweep,
// cached against the catalog content position for every caller. A
// restricted caller's entry is keyed on their grants as well, which
// keeps visibility exact - the sweep it caches is already filtered -
// while letting a client that pages hard read one build instead of one
// per page.
func (h *Handler) index(ctx context.Context, uc *service.UserCtx) (*index, error) {
	tail := h.svc.CatalogContentSeq(ctx)
	scope := indexScope(uc)
	if idx := h.cachedIndex(tail, scope); idx != nil {
		return idx, nil
	}
	build, fell := h.watchReads(ctx)
	rows, err := h.svc.TrackFacts(build, uc)
	if err != nil {
		return nil, err
	}
	facts, err := h.entityFacts(build, rows)
	if err != nil {
		return nil, err
	}
	idx := buildIndex(rows, facts)
	idx.tail = tail
	// The catalog position is re-read rather than trusted: a sweep takes
	// time, and during a scan the tail moves throughout it. A build that
	// finished against a position the catalog has already left can never
	// be served - readers match on the current tail - and caching it
	// would stamp the whole cache with a stale generation and throw away
	// every entry built since. A build a read fell back under (a content
	// rule compiled to match-nothing, the advisory flags lost) is this
	// request's alone.
	if !fell() && h.svc.CatalogContentSeq(ctx) == tail {
		h.cacheIndex(tail, scope, idx)
	}
	return idx, nil
}

// cachedIndex reads the entry for this tail and scope, or nil.
func (h *Handler) cachedIndex(tail int64, scope string) *index {
	h.idxMu.Lock()
	defer h.idxMu.Unlock()
	if h.idxTail != tail {
		return nil
	}
	if scope == "" {
		return h.idxShared
	}
	return h.idxScoped[scope]
}

// cacheIndex stores one built index under the catalog generation it was
// built for. Callers store only a build that is still current (see
// index); a tail that differs from the cached one is therefore a newer
// generation, and the shared view and every scoped one are stale
// together, so they drop together.
func (h *Handler) cacheIndex(tail int64, scope string, idx *index) {
	h.idxMu.Lock()
	defer h.idxMu.Unlock()
	if h.idxTail != tail {
		h.idxTail, h.idxShared, h.idxScoped = tail, nil, nil
	}
	if scope == "" {
		h.idxShared = idx
		return
	}
	if h.idxScoped == nil {
		h.idxScoped = make(map[string]*index, idxScopedCap)
	}
	// Evict one rather than clearing the map: unlike the playlist totals
	// beside it, an entry here costs a whole-catalog sweep to rebuild,
	// so throwing away three good ones to make room for a fourth is the
	// expensive answer. Re-caching a scope already held replaces it and
	// needs no room made, which is why the cap is checked against the
	// entry rather than against the map alone.
	if _, held := h.idxScoped[scope]; !held {
		for len(h.idxScoped) >= idxScopedCap {
			for k := range h.idxScoped {
				delete(h.idxScoped, k)
				break
			}
		}
	}
	h.idxScoped[scope] = idx
}

// entityFacts resolves the catalog's display name for every artist and
// album entity the sweep references, and each album's year, keyed by API
// pid. Once a group is keyed on identity its label can no longer come
// from whichever member row the sweep reached first: two tracks of one
// album with differently spelled tags would otherwise name the group
// nondeterministically, in a cached index. One batched lookup per kind.
func (h *Handler) entityFacts(ctx context.Context, rows []track) (map[string]service.EntityFacts, error) {
	seen := make(map[string]bool, len(rows))
	var pids []string
	for _, tr := range rows {
		for _, pid := range []string{tr.AlbumArtistPID, tr.AlbumPID} {
			if pid != "" && !seen[pid] {
				seen[pid] = true
				pids = append(pids, pid)
			}
		}
	}
	if len(pids) == 0 {
		return nil, nil
	}
	return h.svc.EntityFacts(ctx, pids)
}

func buildIndex(rows []track, facts map[string]service.EntityFacts) *index {
	idx := &index{
		facts:        facts,
		tracks:       rows,
		artistByID:   make(map[string]*artist),
		albumByID:    make(map[string]*album),
		trackByPID:   make(map[string]*track, len(rows)),
		albumByTrack: make(map[string]*album, len(rows)),
		artistByName: make(map[string]*artist),
		albumByKey:   make(map[string]*album),
	}
	// An album whose tracks credit several artists (a compilation with
	// no album-artist tag) is one catalog album but reaches several
	// artist groups. Attach it to each so no artist ends up albumless,
	// while its own responses keep the single artist id the protocol
	// allows.
	attached := make(map[*artist]map[*album]bool)
	for i := range rows {
		tr := rows[i]
		idx.trackByPID[tr.PID] = &rows[i]
		artistName, albumName := groupNames(tr, facts)

		artistID := tr.AlbumArtistPID
		if artistID == "" {
			artistID = encodeArtistID(artistName)
		}
		a := idx.artistByID[artistID]
		if a == nil {
			a = &artist{id: artistID, pid: tr.AlbumArtistPID, name: artistName}
			idx.artistByID[artistID] = a
			idx.artists = append(idx.artists, a)
			attached[a] = make(map[*album]bool)
		}

		albumID := tr.AlbumPID
		if albumID == "" {
			albumID = encodeAlbumID(artistName, albumName)
		}
		al := idx.albumByID[albumID]
		if al == nil {
			al = &album{id: albumID, pid: tr.AlbumPID, artist: a.name, artistID: a.id, name: albumName}
			idx.albumByID[albumID] = al
			idx.albums = append(idx.albums, al)
		}
		if !attached[a][al] {
			attached[a][al] = true
			a.albums = append(a.albums, al)
		}
		idx.albumByTrack[tr.PID] = al
		al.tracks = append(al.tracks, tr)
		al.durMS += tr.DurationMS
		if tr.Explicit {
			al.explicit = true
		}
	}
	// Artists order by index section first ("#" then A to Z), folded
	// names within one: getArtists sections the sorted run by initial
	// letter, so anything less (byte order splits on case, name order
	// splits on symbols past 'z') emits some letter's section twice.
	sort.Slice(idx.artists, func(i, j int) bool {
		li, lj := indexLetter(idx.artists[i].name), indexLetter(idx.artists[j].name)
		if li != lj {
			return li < lj
		}
		if !strings.EqualFold(idx.artists[i].name, idx.artists[j].name) {
			return foldLess(idx.artists[i].name, idx.artists[j].name)
		}
		// Two distinct entities can share a display name; the id breaks
		// the tie so the order stays stable across builds.
		return idx.artists[i].id < idx.artists[j].id
	})
	sort.Slice(idx.albums, func(i, j int) bool {
		if !strings.EqualFold(idx.albums[i].name, idx.albums[j].name) {
			return foldLess(idx.albums[i].name, idx.albums[j].name)
		}
		if !strings.EqualFold(idx.albums[i].artist, idx.albums[j].artist) {
			return foldLess(idx.albums[i].artist, idx.albums[j].artist)
		}
		return idx.albums[i].id < idx.albums[j].id
	})
	for _, a := range idx.artists {
		sort.Slice(a.albums, func(i, j int) bool {
			if !strings.EqualFold(a.albums[i].name, a.albums[j].name) {
				return foldLess(a.albums[i].name, a.albums[j].name)
			}
			return a.albums[i].id < a.albums[j].id
		})
	}
	for _, al := range idx.albums {
		sort.Slice(al.tracks, func(i, j int) bool {
			ti, tj := al.tracks[i], al.tracks[j]
			if ti.DiscNo != tj.DiscNo {
				return ti.DiscNo < tj.DiscNo
			}
			if ti.TrackNo != tj.TrackNo {
				return ti.TrackNo < tj.TrackNo
			}
			return ti.Title < tj.Title
		})
		al.year, al.genre, al.genres = albumYearAndGenres(al, facts)
	}
	// The legacy id maps, filled in sorted order so a display-name
	// collision resolves the same way on every build.
	for _, a := range idx.artists {
		if _, ok := idx.artistByName[a.name]; !ok {
			idx.artistByName[a.name] = a
		}
	}
	for _, al := range idx.albums {
		if k := albumKey(al.artist, al.name); idx.albumByKey[k] == nil {
			idx.albumByKey[k] = al
		}
	}
	return idx
}

// albumYearAndGenres derives an album's year and genres from all of its
// tracks, in album order: the catalog's year where it holds the album,
// its rule over the tracks' years otherwise, and as the genre the one
// most tracks carry, the earliest of a tie.
func albumYearAndGenres(al *album, facts map[string]service.EntityFacts) (int, string, []string) {
	years := make([]int, 0, len(al.tracks))
	counts := map[string]int{}
	var genres []string
	for _, tr := range al.tracks {
		years = append(years, tr.Year)
		if tr.Genre == "" {
			continue
		}
		if counts[tr.Genre] == 0 {
			genres = append(genres, tr.Genre)
		}
		counts[tr.Genre]++
	}
	year := service.AlbumYear(years)
	if f, ok := facts[al.pid]; ok && al.pid != "" {
		year = f.Year
	}
	top := ""
	for _, g := range genres {
		if counts[g] > counts[top] {
			top = g
		}
	}
	return year, top, genres
}

// foldLess orders case-insensitively, falling back to byte order so
// equal-fold names still sort deterministically.
func foldLess(a, b string) bool {
	la, lb := strings.ToLower(a), strings.ToLower(b)
	if la != lb {
		return la < lb
	}
	return a < b
}

// The unknown-tag buckets. Grouping and every album lookup must apply
// the same defaults, or an untagged track's song responses lose the
// album and artist linkage its browse responses carry.
const (
	unknownArtist = "[Unknown Artist]"
	unknownAlbum  = "[Unknown Album]"
)

// groupNames returns the names a track groups under: the catalog's
// canonical entity name where the track carries an entity handle, its
// own tags otherwise, empty tags folded into the unknown buckets.
func groupNames(tr track, facts map[string]service.EntityFacts) (artistName, albumName string) {
	artistName = tr.AlbumArtist
	if n := facts[tr.AlbumArtistPID].Name; n != "" {
		artistName = n
	}
	if artistName == "" {
		artistName = unknownArtist
	}
	albumName = tr.Album
	if n := facts[tr.AlbumPID].Name; n != "" {
		albumName = n
	}
	if albumName == "" {
		albumName = unknownAlbum
	}
	return artistName, albumName
}

func albumKey(artist, album string) string { return artist + "\x1f" + album }

// entityGroupID reports whether an id names an artist or album group
// rather than a song, in either identifier scheme. It is the routing
// test wherever the protocol overloads one parameter across the two:
// getCoverArt (where it also keeps the song case off the index, which
// the cover path would otherwise build on every thumbnail request) and
// the star and rating writes.
func entityGroupID(id string) bool {
	return strings.HasPrefix(id, "A!") || strings.HasPrefix(id, "L!") ||
		strings.HasPrefix(id, service.PrefixArtist+"-") ||
		strings.HasPrefix(id, service.PrefixAlbum+"-")
}

// Minted identifiers: "A!" + base64(artist) and "L!" + base64(artist
// US album). They name a group the catalog holds no entity for - a
// loose track has no album row - and stay decodable without state so an
// id a client cached before the surface moved to entity pids still
// resolves.
func encodeArtistID(name string) string {
	return "A!" + base64.RawURLEncoding.EncodeToString([]byte(name))
}

func decodeArtistID(id string) (string, bool) {
	rest, found := strings.CutPrefix(id, "A!")
	if !found {
		return "", false
	}
	raw, err := base64.RawURLEncoding.DecodeString(rest)
	if err != nil {
		return "", false
	}
	return string(raw), true
}

func encodeAlbumID(artist, album string) string {
	return "L!" + base64.RawURLEncoding.EncodeToString([]byte(albumKey(artist, album)))
}

func decodeAlbumID(id string) (artist, album string, ok bool) {
	rest, found := strings.CutPrefix(id, "L!")
	if !found {
		return "", "", false
	}
	raw, err := base64.RawURLEncoding.DecodeString(rest)
	if err != nil {
		return "", "", false
	}
	a, b, found := strings.Cut(string(raw), "\x1f")
	if !found {
		return "", "", false
	}
	return a, b, true
}

func indexLetter(name string) string {
	for _, r := range name {
		switch {
		case r >= 'a' && r <= 'z':
			return strings.ToUpper(string(r))
		case r >= 'A' && r <= 'Z':
			return string(r)
		case r >= '0' && r <= '9':
			return "#"
		default:
			return "#"
		}
	}
	return "#"
}

func formInt(r *http.Request, name string, def int) int {
	v := r.Form.Get(name)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return n
}

// warn logs, tolerating a handler built without a logger (tests).
func (h *Handler) warn(msg string, args ...any) {
	if h.log != nil {
		h.log.Warn(msg, args...)
	}
}
