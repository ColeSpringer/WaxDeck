// Package subsonic is the OpenSubsonic compatibility surface: ID3 and
// folder-emulated browsing, search, cover art, streaming, playlists,
// stars and ratings, scrobbling, bookmark parity over spoken-word
// resume, read-only podcasts, and the internet radio library, so
// mature third-party clients work against WaxDeck while the
// first-party clients mature.
// It sits on the service layer like any first-party handler; user
// mapping, visibility, media-token minting, and the scrobble outbox
// apply identically.
//
// Identifier scheme: songs are real item PIDs. The item query grammar
// addresses artists and albums by display string, so artist and album
// identifiers are minted from those strings (opaque to clients, stable
// across requests). Cover art for a minted id resolves through one of
// its member items, whose art chain falls back to the album and artist.
package subsonic

import (
	"context"
	"encoding/base64"
	"math/rand/v2"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"sync"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// apiVersion is the Subsonic protocol version this surface speaks.
const apiVersion = "1.16.1"

// streamer is the slice of the WaxFlow bridge the adapter needs; nil
// when streaming is not configured.
type streamer interface {
	PlayInfoFor(ctx context.Context, user, apiItemPID string, opts flow.PlayOptions) (flow.PlayInfo, error)
}

// Handler serves /rest/*.
type Handler struct {
	svc     *service.Library
	bridge  streamer
	media   *auth.MediaTokens
	version string

	// The full-visibility grouped index, cached against the catalog
	// feed position (polling clients browse far more often than the
	// catalog changes). Read-only once built, so it is shared across
	// requests.
	idxMu     sync.Mutex
	idxTail   int64
	idxShared *index
}

// New builds the adapter. bridge may be nil: stream then serves
// original bytes directly through the tokenized download endpoint
// (media mints the tokens), refusing only span-carved tracks it
// cannot cut.
func New(svc *service.Library, bridge *flow.Bridge, media *auth.MediaTokens, version string) *Handler {
	h := &Handler{svc: svc, media: media, version: version}
	if bridge != nil {
		h.bridge = bridge
	}
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

	u, code, msg := h.authenticate(r)
	if u == nil {
		h.fail(w, r, code, msg)
		return
	}
	uc, err := h.svc.UserCtx(r.Context(), u)
	if err != nil {
		h.fail(w, r, 0, "resolving user failed")
		return
	}

	switch view {
	case "ping":
		h.ok(w, r, envelope{})
	case "getLicense":
		h.ok(w, r, envelope{License: &license{Valid: true}})
	case "getOpenSubsonicExtensions":
		h.getOpenSubsonicExtensions(w, r)
	case "getMusicFolders":
		h.getMusicFolders(w, r)
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
		h.getTopSongs(w, r)
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
	case "stream", "download":
		h.stream(w, r, uc)
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
		h.getBookmarks(w, r, uc)
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
		// Live session tracking arrives with the connect subsystem;
		// an empty list beats an error for the clients that poll it.
		h.ok(w, r, envelope{NowPlaying: &nowPlaying{}})
	case "jukeboxControl":
		h.fail(w, r, 0, "jukebox mode is not available on this server yet")
	case "savePlayQueue", "getPlayQueue":
		h.fail(w, r, 0, "play queue sync is not available on this server yet")
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
func (h *Handler) authenticate(r *http.Request) (*wdb.User, int, string) {
	if key := r.Form.Get("apiKey"); key != "" {
		u, err := h.svc.VerifyAppPasswordKey(r.Context(), key)
		if err != nil || u == nil {
			return nil, 44, "invalid API key"
		}
		return u, 0, ""
	}
	username := r.Form.Get("u")
	token := r.Form.Get("t")
	salt := r.Form.Get("s")
	if username == "" || token == "" || salt == "" {
		if r.Form.Get("p") != "" {
			return nil, 41, "password authentication is not supported; use token authentication with an app password"
		}
		return nil, 10, "missing authentication parameters"
	}
	u, err := h.svc.VerifyAppPasswordToken(r.Context(), username, token, salt)
	if err != nil || u == nil {
		return nil, 40, "wrong username or password"
	}
	return u, 0, ""
}

// --- browse ------------------------------------------------------------------

func (h *Handler) getMusicFolders(w http.ResponseWriter, r *http.Request) {
	libs, err := h.svc.Libraries(r.Context())
	if err != nil {
		h.fail(w, r, 0, "listing libraries failed")
		return
	}
	out := &musicFolders{}
	for i, lib := range libs {
		out.Folders = append(out.Folders, musicFolder{ID: i + 1, Name: lib.Name})
	}
	h.ok(w, r, envelope{MusicFolders: out})
}

func (h *Handler) getArtists(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
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
	name, ok := decodeArtistID(r.Form.Get("id"))
	if !ok {
		h.fail(w, r, 10, "missing or malformed id")
		return
	}
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	a := idx.artistByName[name]
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
	artist, album, ok := decodeAlbumID(r.Form.Get("id"))
	if !ok {
		h.fail(w, r, 10, "missing or malformed id")
		return
	}
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	al := idx.albumByKey[albumKey(artist, album)]
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
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	out := &albumList2{}
	for _, al := range h.pagedAlbums(r, idx) {
		out.Albums = append(out.Albums, al.id3())
	}
	h.ok(w, r, envelope{AlbumList2: out})
}

// pagedAlbums applies the album-list type, size, and offset shared by
// both list flavors (getAlbumList2 renders ID3 shapes, getAlbumList
// directory children).
func (h *Handler) pagedAlbums(r *http.Request, idx *index) []*album {
	size := formInt(r, "size", 10)
	if size < 1 {
		size = 10
	}
	if size > 500 {
		size = 500
	}
	offset := formInt(r, "offset", 0)
	if offset < 0 {
		offset = 0
	}

	albums := make([]*album, len(idx.albums))
	copy(albums, idx.albums)
	switch r.Form.Get("type") {
	case "random":
		rand.Shuffle(len(albums), func(i, j int) { albums[i], albums[j] = albums[j], albums[i] })
	case "byYear":
		sort.SliceStable(albums, func(i, j int) bool { return albums[i].year < albums[j].year })
	case "byGenre":
		g := r.Form.Get("genre")
		kept := albums[:0]
		for _, al := range albums {
			if al.genre == g {
				kept = append(kept, al)
			}
		}
		albums = kept
	default:
		// alphabeticalByName is the shape everything else falls back to:
		// played-derived lists need per-user history this surface does
		// not serve yet, and an ordered list beats an error for a
		// read-only browse.
	}
	var out []*album
	for i := offset; i < len(albums) && len(out) < size; i++ {
		out = append(out, albums[i])
	}
	return out
}

func (h *Handler) getSong(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	tr := idx.trackByPID[id]
	if tr == nil {
		h.fail(w, r, 70, "no such song")
		return
	}
	al := idx.albumByKey[albumKeyForTrack(*tr)]
	song := songChild(*tr, al)
	h.ok(w, r, envelope{Song: &song})
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
	idx, err := h.index(r.Context(), uc)
	if err != nil {
		h.fail(w, r, 0, "reading the library failed")
		return
	}
	match := func(s string) bool {
		return q == "" || strings.Contains(strings.ToLower(s), strings.ToLower(q))
	}
	out := &searchResult3{}
	artistCount := formInt(r, "artistCount", 20)
	albumCount := formInt(r, "albumCount", 20)
	songCount := formInt(r, "songCount", 20)
	for _, a := range idx.artists {
		if len(out.Artists) >= artistCount {
			break
		}
		if match(a.name) {
			out.Artists = append(out.Artists, a.id3())
		}
	}
	for _, al := range idx.albums {
		if len(out.Albums) >= albumCount {
			break
		}
		if match(al.name) || match(al.artist) {
			out.Albums = append(out.Albums, al.id3())
		}
	}
	for _, tr := range idx.tracks {
		if len(out.Songs) >= songCount {
			break
		}
		if match(tr.Title) || match(tr.Artist) || match(tr.Album) {
			al := idx.albumByKey[albumKeyForTrack(tr)]
			out.Songs = append(out.Songs, songChild(tr, al))
		}
	}
	h.ok(w, r, envelope{SearchResult3: out})
}

func (h *Handler) getCoverArt(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	pid := id
	// Minted artist and album ids resolve through a member item, whose
	// art chain falls back to album and artist artwork.
	if artist, album, ok := decodeAlbumID(id); ok {
		idx, err := h.index(r.Context(), uc)
		if err != nil {
			h.fail(w, r, 0, "reading the library failed")
			return
		}
		al := idx.albumByKey[albumKey(artist, album)]
		if al == nil || len(al.tracks) == 0 {
			h.fail(w, r, 70, "no such cover")
			return
		}
		pid = al.tracks[0].PID
	} else if name, ok := decodeArtistID(id); ok {
		idx, err := h.index(r.Context(), uc)
		if err != nil {
			h.fail(w, r, 0, "reading the library failed")
			return
		}
		a := idx.artistByName[name]
		if a == nil || len(a.albums) == 0 || len(a.albums[0].tracks) == 0 {
			h.fail(w, r, 70, "no such cover")
			return
		}
		pid = a.albums[0].tracks[0].PID
	}
	size := formInt(r, "size", 0)
	// Subsonic has no artwork-slot concept; it always serves the front cover.
	blob, err := h.svc.Art(r.Context(), uc, pid, "", size)
	if err != nil {
		h.fail(w, r, 70, "no such cover")
		return
	}
	w.Header().Set("Content-Type", blob.MimeType)
	w.Write(blob.Bytes)
}

func (h *Handler) stream(w http.ResponseWriter, r *http.Request, uc *service.UserCtx) {
	id := r.Form.Get("id")
	if id == "" {
		h.fail(w, r, 10, "missing id")
		return
	}
	if err := h.svc.VisibleItem(r.Context(), uc, id); err != nil {
		h.fail(w, r, 70, "no such song")
		return
	}
	// Without the streaming engine the original bytes serve directly.
	// Subsonic clients cannot clip, so a track carved out of a larger
	// file is the one thing this mode must refuse.
	if h.bridge == nil {
		if h.media == nil {
			h.fail(w, r, 0, "streaming is not configured on this server")
			return
		}
		res, err := h.svc.DirectPlayInfo(r.Context(), uc, id, "")
		if err != nil {
			h.failFromService(w, r, err, "no such song")
			return
		}
		if res.HasSpan {
			h.fail(w, r, 0, "this track is a window into a larger file; playing it needs the streaming engine")
			return
		}
		token, _ := h.media.Mint(uc.ID, id)
		http.Redirect(w, r, "/media/download?pid="+url.QueryEscape(id)+
			"&mt="+url.QueryEscape(token)+"&id="+url.QueryEscape(res.File.ETag), http.StatusFound)
		return
	}
	info, err := h.bridge.PlayInfoFor(r.Context(), uc.ID, id, flow.PlayOptions{})
	if err != nil {
		h.fail(w, r, 0, "resolving stream failed")
		return
	}
	// The tokenized URL is same-origin; a redirect keeps the adapter
	// out of the byte path and rides the same proxy as first-party
	// playback.
	http.Redirect(w, r, info.URL, http.StatusFound)
}

// --- the string-grouped index ------------------------------------------------

type track = service.TrackFacts

type album struct {
	artist string
	name   string
	year   int
	genre  string
	durMS  int64
	tracks []track
}

type artist struct {
	name   string
	albums []*album
}

type index struct {
	tracks       []track
	artists      []*artist
	albums       []*album
	artistByName map[string]*artist
	albumByKey   map[string]*album
	trackByPID   map[string]*track
}

// index returns the grouped view over the service's track sweep. The
// full-visibility view is cached against the catalog feed position,
// mirroring the sweep's own cache; restricted callers group per request
// over their filtered sweep, keeping visibility exact.
func (h *Handler) index(ctx context.Context, uc *service.UserCtx) (*index, error) {
	if !uc.AllLibraries {
		rows, err := h.svc.TrackFacts(ctx, uc)
		if err != nil {
			return nil, err
		}
		return buildIndex(rows), nil
	}
	tail := h.svc.CatalogTailSeq()
	h.idxMu.Lock()
	if h.idxShared != nil && h.idxTail == tail {
		idx := h.idxShared
		h.idxMu.Unlock()
		return idx, nil
	}
	h.idxMu.Unlock()
	rows, err := h.svc.TrackFacts(ctx, uc)
	if err != nil {
		return nil, err
	}
	idx := buildIndex(rows)
	h.idxMu.Lock()
	h.idxTail, h.idxShared = tail, idx
	h.idxMu.Unlock()
	return idx, nil
}

func buildIndex(rows []track) *index {
	idx := &index{
		tracks:       rows,
		artistByName: make(map[string]*artist),
		albumByKey:   make(map[string]*album),
		trackByPID:   make(map[string]*track, len(rows)),
	}
	for i := range rows {
		tr := rows[i]
		idx.trackByPID[tr.PID] = &rows[i]
		artistName, albumName := groupNames(tr)
		a := idx.artistByName[artistName]
		if a == nil {
			a = &artist{name: artistName}
			idx.artistByName[artistName] = a
			idx.artists = append(idx.artists, a)
		}
		key := albumKey(artistName, albumName)
		al := idx.albumByKey[key]
		if al == nil {
			al = &album{artist: artistName, name: albumName}
			idx.albumByKey[key] = al
			idx.albums = append(idx.albums, al)
			a.albums = append(a.albums, al)
		}
		al.tracks = append(al.tracks, tr)
		al.durMS += tr.DurationMS
		if al.year == 0 {
			al.year = tr.Year
		}
		if al.genre == "" {
			al.genre = tr.Genre
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
		return foldLess(idx.artists[i].name, idx.artists[j].name)
	})
	sort.Slice(idx.albums, func(i, j int) bool {
		if !strings.EqualFold(idx.albums[i].name, idx.albums[j].name) {
			return foldLess(idx.albums[i].name, idx.albums[j].name)
		}
		return foldLess(idx.albums[i].artist, idx.albums[j].artist)
	})
	for _, a := range idx.artists {
		sort.Slice(a.albums, func(i, j int) bool { return foldLess(a.albums[i].name, a.albums[j].name) })
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
	}
	return idx
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

// groupNames returns the names a track groups under, empty tags folded
// into the unknown buckets.
func groupNames(tr track) (artistName, albumName string) {
	artistName = tr.AlbumArtist
	if artistName == "" {
		artistName = unknownArtist
	}
	albumName = tr.Album
	if albumName == "" {
		albumName = unknownAlbum
	}
	return artistName, albumName
}

// albumKeyForTrack keys a track's album with the grouping defaults
// applied; keying on the raw tags misses the unknown buckets.
func albumKeyForTrack(tr track) string {
	artistName, albumName := groupNames(tr)
	return albumKey(artistName, albumName)
}

func albumKey(artist, album string) string { return artist + "\x1f" + album }

// Minted identifiers: "A!" + base64(artist) and "L!" + base64(artist
// US album). Opaque to clients, stable across requests, decodable
// without state.
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
