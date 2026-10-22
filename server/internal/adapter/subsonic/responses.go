package subsonic

import (
	"encoding/json"
	"encoding/xml"
	"fmt"
	"net/http"
	"reflect"
	"regexp"
	"strings"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// The wire shapes. One set of structs renders both response formats:
// XML per the classic protocol, and the OpenSubsonic JSON rendering
// under a "subsonic-response" key when f=json.

type envelope struct {
	XMLName       xml.Name `xml:"subsonic-response" json:"-"`
	Xmlns         string   `xml:"xmlns,attr" json:"-"`
	Status        string   `xml:"status,attr" json:"status"`
	Version       string   `xml:"version,attr" json:"version"`
	Type          string   `xml:"type,attr" json:"type"`
	ServerVersion string   `xml:"serverVersion,attr" json:"serverVersion"`
	OpenSubsonic  bool     `xml:"openSubsonic,attr" json:"openSubsonic"`

	Error         *subError         `xml:"error,omitempty" json:"error,omitempty"`
	License       *license          `xml:"license,omitempty" json:"license,omitempty"`
	User          *subsonicUser     `xml:"user,omitempty" json:"user,omitempty"`
	MusicFolders  *musicFolders     `xml:"musicFolders,omitempty" json:"musicFolders,omitempty"`
	Artists       *artistsID3       `xml:"artists,omitempty" json:"artists,omitempty"`
	Artist        *artistWithAlbums `xml:"artist,omitempty" json:"artist,omitempty"`
	Album         *albumWithSongs   `xml:"album,omitempty" json:"album,omitempty"`
	AlbumList2    *albumList2       `xml:"albumList2,omitempty" json:"albumList2,omitempty"`
	Song          *child            `xml:"song,omitempty" json:"song,omitempty"`
	Genres        *genres           `xml:"genres,omitempty" json:"genres,omitempty"`
	SearchResult3 *searchResult3    `xml:"searchResult3,omitempty" json:"searchResult3,omitempty"`

	Playlists             *playlists             `xml:"playlists,omitempty" json:"playlists,omitempty"`
	Playlist              *playlistWithSongs     `xml:"playlist,omitempty" json:"playlist,omitempty"`
	Starred2              *starred2              `xml:"starred2,omitempty" json:"starred2,omitempty"`
	Bookmarks             *bookmarks             `xml:"bookmarks,omitempty" json:"bookmarks,omitempty"`
	InternetRadioStations *internetRadioStations `xml:"internetRadioStations,omitempty" json:"internetRadioStations,omitempty"`
	NowPlaying            *nowPlaying            `xml:"nowPlaying,omitempty" json:"nowPlaying,omitempty"`

	OpenSubsonicExtensions []openSubsonicExtension `xml:"openSubsonicExtensions,omitempty" json:"openSubsonicExtensions,omitempty"`
	TokenInfo              *tokenInfo              `xml:"tokenInfo,omitempty" json:"tokenInfo,omitempty"`
	Indexes                *indexes                `xml:"indexes,omitempty" json:"indexes,omitempty"`
	Directory              *directory              `xml:"directory,omitempty" json:"directory,omitempty"`
	AlbumList              *albumList              `xml:"albumList,omitempty" json:"albumList,omitempty"`
	Starred                *starred                `xml:"starred,omitempty" json:"starred,omitempty"`
	RandomSongs            *songList               `xml:"randomSongs,omitempty" json:"randomSongs,omitempty"`
	SongsByGenre           *songList               `xml:"songsByGenre,omitempty" json:"songsByGenre,omitempty"`
	TopSongs               *songList               `xml:"topSongs,omitempty" json:"topSongs,omitempty"`
	ScanStatus             *scanStatus             `xml:"scanStatus,omitempty" json:"scanStatus,omitempty"`
	ArtistInfo             *artistInfo             `xml:"artistInfo,omitempty" json:"artistInfo,omitempty"`
	ArtistInfo2            *artistInfo             `xml:"artistInfo2,omitempty" json:"artistInfo2,omitempty"`
	Podcasts               *podcastsShape          `xml:"podcasts,omitempty" json:"podcasts,omitempty"`
	NewestPodcasts         *newestPodcasts         `xml:"newestPodcasts,omitempty" json:"newestPodcasts,omitempty"`
	SimilarSongs           *songList               `xml:"similarSongs,omitempty" json:"similarSongs,omitempty"`
	SimilarSongs2          *songList               `xml:"similarSongs2,omitempty" json:"similarSongs2,omitempty"`
	SonicSimilarTracks     *songList               `xml:"sonicSimilarTracks,omitempty" json:"sonicSimilarTracks,omitempty"`
	SonicPath              *songList               `xml:"sonicPath,omitempty" json:"sonicPath,omitempty"`

	// entityMarks are marks a handler's own read already holds, for the
	// entities they name, which the annotate pass takes as they are.
	entityMarks map[string]service.EntityMark
}

// tokenInfo names the account an API key belongs to.
type tokenInfo struct {
	Username string `xml:"username,attr" json:"username"`
}

// openSubsonicExtension is one advertised OpenSubsonic extension.
type openSubsonicExtension struct {
	Name     string `xml:"name,attr" json:"name"`
	Versions []int  `xml:"versions" json:"versions"`
}

// The folder-emulated browse shapes: the classic directory protocol
// rendered over the same tag-derived objects as the ID3 views.
type indexes struct {
	LastModified    int64         `xml:"lastModified,attr" json:"lastModified"`
	IgnoredArticles string        `xml:"ignoredArticles,attr" json:"ignoredArticles"`
	Index           []folderIndex `xml:"index" json:"index"`
}

type folderIndex struct {
	Name    string         `xml:"name,attr" json:"name"`
	Artists []folderArtist `xml:"artist" json:"artist"`
}

type folderArtist struct {
	ID   string `xml:"id,attr" json:"id"`
	Name string `xml:"name,attr" json:"name"`

	marks
}

// marks are the caller's own star and rating on a song, album or artist:
// the star's time as an RFC 3339 date, the stored 0..100 rating as 1..5.
type marks struct {
	Starred    string `xml:"starred,attr,omitempty" json:"starred,omitempty"`
	UserRating int    `xml:"userRating,attr,omitempty" json:"userRating,omitempty"`
}

// plays are the caller's play count and last play of a song or album.
type plays struct {
	PlayCount int    `xml:"playCount,attr,omitempty" json:"playCount,omitempty"`
	Played    string `xml:"played,attr,omitempty" json:"played,omitempty"`
}

type directory struct {
	ID       string  `xml:"id,attr" json:"id"`
	Parent   string  `xml:"parent,attr,omitempty" json:"parent,omitempty"`
	Name     string  `xml:"name,attr" json:"name"`
	Children []child `xml:"child" json:"child"`

	marks
}

type albumList struct {
	Albums []child `xml:"album" json:"album"`
}

type starred struct {
	Artists []folderArtist `xml:"artist" json:"artist"`
	Albums  []child        `xml:"album" json:"album"`
	Songs   []child        `xml:"song" json:"song"`
}

// songList is the shared {song[]} shape (randomSongs, songsByGenre,
// topSongs); the envelope field names the element.
type songList struct {
	Songs []child `xml:"song" json:"song"`
}

type scanStatus struct {
	Scanning bool  `xml:"scanning,attr" json:"scanning"`
	Count    int64 `xml:"count,attr" json:"count"`
}

// artistInfo is deliberately empty: no biography source exists here.
type artistInfo struct{}

type podcastsShape struct {
	Channels []podcastChannel `xml:"channel" json:"channel"`
}

type podcastChannel struct {
	ID       string           `xml:"id,attr" json:"id"`
	URL      string           `xml:"url,attr,omitempty" json:"url,omitempty"`
	Title    string           `xml:"title,attr" json:"title"`
	CoverArt string           `xml:"coverArt,attr,omitempty" json:"coverArt,omitempty"`
	Status   string           `xml:"status,attr" json:"status"`
	Episodes []podcastEpisode `xml:"episode" json:"episode,omitempty"`
}

type podcastEpisode struct {
	child
	StreamID    string `xml:"streamId,attr,omitempty" json:"streamId,omitempty"`
	ChannelID   string `xml:"channelId,attr" json:"channelId"`
	Status      string `xml:"status,attr" json:"status"`
	PublishDate string `xml:"publishDate,attr,omitempty" json:"publishDate,omitempty"`
}

type newestPodcasts struct {
	Episodes []podcastEpisode `xml:"episode" json:"episode"`
}

type subError struct {
	Code    int    `xml:"code,attr" json:"code"`
	Message string `xml:"message,attr" json:"message"`
}

type license struct {
	Valid bool `xml:"valid,attr" json:"valid"`
}

// subsonicUser is the account and its capability flags. Clients read it
// at sign-in to decide which controls to draw at all, so a role claimed
// here that the server then refuses is worse than one denied up front:
// every flag below maps to something WaxDeck actually honors, and the
// ones with nothing behind them here (comments, video conversion,
// shares, podcast management) are false rather than optimistic.
type subsonicUser struct {
	Username            string `xml:"username,attr" json:"username"`
	ScrobblingEnabled   bool   `xml:"scrobblingEnabled,attr" json:"scrobblingEnabled"`
	AdminRole           bool   `xml:"adminRole,attr" json:"adminRole"`
	SettingsRole        bool   `xml:"settingsRole,attr" json:"settingsRole"`
	DownloadRole        bool   `xml:"downloadRole,attr" json:"downloadRole"`
	UploadRole          bool   `xml:"uploadRole,attr" json:"uploadRole"`
	PlaylistRole        bool   `xml:"playlistRole,attr" json:"playlistRole"`
	CoverArtRole        bool   `xml:"coverArtRole,attr" json:"coverArtRole"`
	CommentRole         bool   `xml:"commentRole,attr" json:"commentRole"`
	PodcastRole         bool   `xml:"podcastRole,attr" json:"podcastRole"`
	StreamRole          bool   `xml:"streamRole,attr" json:"streamRole"`
	JukeboxRole         bool   `xml:"jukeboxRole,attr" json:"jukeboxRole"`
	ShareRole           bool   `xml:"shareRole,attr" json:"shareRole"`
	VideoConversionRole bool   `xml:"videoConversionRole,attr" json:"videoConversionRole"`
}

type musicFolders struct {
	Folders []musicFolder `xml:"musicFolder" json:"musicFolder"`
}

type musicFolder struct {
	ID   int64  `xml:"id,attr" json:"id"`
	Name string `xml:"name,attr" json:"name"`
}

type artistsID3 struct {
	IgnoredArticles string     `xml:"ignoredArticles,attr" json:"ignoredArticles"`
	Index           []indexID3 `xml:"index" json:"index"`
}

type indexID3 struct {
	Name    string      `xml:"name,attr" json:"name"`
	Artists []artistID3 `xml:"artist" json:"artist"`
}

type artistID3 struct {
	ID         string `xml:"id,attr" json:"id"`
	Name       string `xml:"name,attr" json:"name"`
	CoverArt   string `xml:"coverArt,attr,omitempty" json:"coverArt,omitempty"`
	AlbumCount int    `xml:"albumCount,attr" json:"albumCount"`

	marks
}

type artistWithAlbums struct {
	artistID3
	Albums []albumID3 `xml:"album" json:"album"`
}

type albumID3 struct {
	ID        string `xml:"id,attr" json:"id"`
	Name      string `xml:"name,attr" json:"name"`
	Artist    string `xml:"artist,attr" json:"artist"`
	ArtistID  string `xml:"artistId,attr" json:"artistId"`
	CoverArt  string `xml:"coverArt,attr,omitempty" json:"coverArt,omitempty"`
	SongCount int    `xml:"songCount,attr" json:"songCount"`
	Duration  int    `xml:"duration,attr" json:"duration"`
	Year      int    `xml:"year,attr,omitempty" json:"year,omitempty"`
	Genre     string `xml:"genre,attr,omitempty" json:"genre,omitempty"`

	// ExplicitStatus follows the child field of the same name: any
	// member track asserting the advisory marks the album, so a badge
	// on song rows has one on the album card those rows sit under.
	ExplicitStatus string `xml:"explicitStatus,attr,omitempty" json:"explicitStatus,omitempty"`

	// Created is when the album's first track's file arrived.
	Created string `xml:"created,attr,omitempty" json:"created,omitempty"`
	marks
	plays

	tracks []track
}

type albumWithSongs struct {
	albumID3
	Songs []child `xml:"song" json:"song"`
}

type albumList2 struct {
	Albums []albumID3 `xml:"album" json:"album"`
}

// child is the Subsonic song shape (the protocol's directory-era name).
//
// ExplicitStatus is the OpenSubsonic content advisory. Episodes carry
// their feed's declared flag, own or show-level (episodeShape and
// entryChild's summary arm); music tracks carry an ITUNESADVISORY tag
// asserting explicit, which the facts sweep resolves as one tag query
// rather than a read per song; albums derive any-member. Emission is
// positive-only everywhere: a feed flag is a bool that cannot tell
// clean from unsaid, and on the tag side a declared clean ("2") is
// deliberately not forwarded - the tag's value space is messy enough
// (multi-valued files, the legacy "4", rtng/freeform disagreement)
// that a wrong "clean" would be worse than the unknown an absent
// attribute already reads as.
type child struct {
	ID          string `xml:"id,attr" json:"id"`
	Parent      string `xml:"parent,attr,omitempty" json:"parent,omitempty"`
	IsDir       bool   `xml:"isDir,attr" json:"isDir"`
	Title       string `xml:"title,attr" json:"title"`
	Album       string `xml:"album,attr,omitempty" json:"album,omitempty"`
	Artist      string `xml:"artist,attr,omitempty" json:"artist,omitempty"`
	Track       int    `xml:"track,attr,omitempty" json:"track,omitempty"`
	DiscNumber  int    `xml:"discNumber,attr,omitempty" json:"discNumber,omitempty"`
	Year        int    `xml:"year,attr,omitempty" json:"year,omitempty"`
	BPM         int    `xml:"bpm,attr,omitempty" json:"bpm,omitempty"`
	Genre       string `xml:"genre,attr,omitempty" json:"genre,omitempty"`
	CoverArt    string `xml:"coverArt,attr,omitempty" json:"coverArt,omitempty"`
	Duration    int    `xml:"duration,attr" json:"duration"`
	Suffix      string `xml:"suffix,attr,omitempty" json:"suffix,omitempty"`
	ContentType string `xml:"contentType,attr,omitempty" json:"contentType,omitempty"`
	AlbumID     string `xml:"albumId,attr,omitempty" json:"albumId,omitempty"`
	ArtistID    string `xml:"artistId,attr,omitempty" json:"artistId,omitempty"`
	Type        string `xml:"type,attr" json:"type"`

	ExplicitStatus string `xml:"explicitStatus,attr,omitempty" json:"explicitStatus,omitempty"`

	// The primary file's size, bitrate and arrival; a track carved out
	// of a larger file carries no size, since its file is the whole rip.
	Size    int64  `xml:"size,attr,omitempty" json:"size,omitempty"`
	BitRate int    `xml:"bitRate,attr,omitempty" json:"bitRate,omitempty"`
	Created string `xml:"created,attr,omitempty" json:"created,omitempty"`
	marks
	plays
	// BookmarkPosition is where the caller's bookmark on the song stands,
	// in ms, as getBookmarks lists it.
	BookmarkPosition int64 `xml:"bookmarkPosition,attr,omitempty" json:"bookmarkPosition,omitempty"`

	// fileID and carved feed the facts above; tracks are an album
	// folder's, for its plays.
	fileID string
	carved bool
	tracks []track
}

type genres struct {
	Genres []genre `xml:"genre" json:"genre"`
}

type genre struct {
	Name      string `xml:",chardata" json:"value"`
	SongCount int    `xml:"songCount,attr" json:"songCount"`
	// AlbumCount counts the albums holding a track of the genre.
	AlbumCount int `xml:"albumCount,attr" json:"albumCount"`
}

type searchResult3 struct {
	Artists []artistID3 `xml:"artist" json:"artist"`
	Albums  []albumID3  `xml:"album" json:"album"`
	Songs   []child     `xml:"song" json:"song"`
}

type playlists struct {
	Playlists []playlistShape `xml:"playlist" json:"playlist"`
}

// playlistShape is the protocol's playlist header. Duration and song
// count are exact on both responses; the list response computes them
// through a per-caller cache. CoverArt is the playlist's own id, which
// getCoverArt resolves to the owner's cover or the members' mosaic.
type playlistShape struct {
	ID        string `xml:"id,attr" json:"id"`
	Name      string `xml:"name,attr" json:"name"`
	Owner     string `xml:"owner,attr,omitempty" json:"owner,omitempty"`
	Public    bool   `xml:"public,attr" json:"public"`
	SongCount int    `xml:"songCount,attr" json:"songCount"`
	Duration  int    `xml:"duration,attr" json:"duration"`
	Created   string `xml:"created,attr" json:"created"`
	Changed   string `xml:"changed,attr" json:"changed"`
	CoverArt  string `xml:"coverArt,attr,omitempty" json:"coverArt,omitempty"`
}

type playlistWithSongs struct {
	playlistShape
	Entries []child `xml:"entry" json:"entry"`
}

type starred2 struct {
	Artists []artistID3 `xml:"artist" json:"artist"`
	Albums  []albumID3  `xml:"album" json:"album"`
	Songs   []child     `xml:"song" json:"song"`
}

type bookmarks struct {
	Bookmarks []bookmark `xml:"bookmark" json:"bookmark"`
}

type bookmark struct {
	Position int64  `xml:"position,attr" json:"position"`
	Username string `xml:"username,attr" json:"username"`
	Comment  string `xml:"comment,attr,omitempty" json:"comment,omitempty"`
	Created  string `xml:"created,attr" json:"created"`
	Changed  string `xml:"changed,attr" json:"changed"`
	Entry    child  `xml:"entry" json:"entry"`
}

type internetRadioStations struct {
	Stations []internetRadioStation `xml:"internetRadioStation" json:"internetRadioStation"`
}

type internetRadioStation struct {
	ID          string `xml:"id,attr" json:"id"`
	Name        string `xml:"name,attr" json:"name"`
	StreamURL   string `xml:"streamUrl,attr" json:"streamUrl"`
	HomepageURL string `xml:"homePageUrl,attr,omitempty" json:"homePageUrl,omitempty"`
}

type nowPlaying struct {
	Entries []nowPlayingEntry `xml:"entry" json:"entry"`
}

// nowPlayingEntry is one session's current item: the song, who plays it,
// on which device, and how long ago the session last moved.
type nowPlayingEntry struct {
	child
	Username   string `xml:"username,attr" json:"username"`
	MinutesAgo int    `xml:"minutesAgo,attr" json:"minutesAgo"`
	PlayerID   int    `xml:"playerId,attr" json:"playerId"`
	PlayerName string `xml:"playerName,attr,omitempty" json:"playerName,omitempty"`
}

// --- shape builders ----------------------------------------------------------

func (a *artist) id3() artistID3 {
	out := artistID3{ID: a.id, Name: a.name, AlbumCount: len(a.albums)}
	out.CoverArt = out.ID
	return out
}

// folder renders an artist as a folder-mode index entry.
func (a *artist) folder() folderArtist {
	return folderArtist{ID: a.id, Name: a.name}
}

func (al *album) id3() albumID3 {
	out := albumID3{
		ID:        al.id,
		Name:      al.name,
		Artist:    al.artist,
		ArtistID:  al.artistID,
		CoverArt:  al.id,
		SongCount: len(al.tracks),
		Duration:  int(al.durMS / 1000),
		Year:      al.year,
		Genre:     al.genre,
		tracks:    al.tracks,
	}
	if al.explicit {
		out.ExplicitStatus = "explicit"
	}
	return out
}

// formatFacts derives a child's suffix and contentType from the stored
// container, over the one normalized mime table (flow.ContainerMime).
// The suffix is the extension a file of the family wears - the stored
// labels that are container names rather than extensions get spelled
// back ("matroska" is a .mka, "wavpack" a .wv, "asf" a .wma,
// "musepack" a .mpc) - and
// contentType is never omitted: Feishin's tracks index dereferences it
// on every row without checking, so one unknown-format file would
// otherwise hold the whole listing at a skeleton forever, retrying a
// response that never stops being 200.
func formatFacts(container string) (suffix, mime string) {
	switch key := flow.NormalizeContainer(container); key {
	case "matroska":
		suffix = "mka"
	case "wavpack":
		suffix = "wv"
	case "asf":
		suffix = "wma"
	case "musepack":
		suffix = "mpc"
	default:
		suffix = key
	}
	return suffix, flow.ContainerMime(container)
}

// albumDirChild renders an album as a folder-mode directory entry.
func albumDirChild(al *album) child {
	c := child{
		ID:       al.id,
		Parent:   al.artistID,
		IsDir:    true,
		Title:    al.name,
		Artist:   al.artist,
		Year:     al.year,
		Genre:    al.genre,
		CoverArt: al.id,
		Duration: int(al.durMS / 1000),
		AlbumID:  al.id,
		ArtistID: al.artistID,
		Type:     "music",
		tracks:   al.tracks,
	}
	if al.explicit {
		c.ExplicitStatus = "explicit"
	}
	return c
}

func songChild(tr track, al *album) child {
	suffix, mime := formatFacts(tr.Container)
	c := child{
		ID:          tr.PID,
		IsDir:       false,
		Title:       tr.Title,
		Album:       tr.Album,
		Artist:      tr.Artist,
		Track:       tr.TrackNo,
		DiscNumber:  tr.DiscNo,
		Year:        tr.Year,
		BPM:         tr.BPM,
		Genre:       tr.Genre,
		CoverArt:    tr.PID,
		Duration:    int(tr.DurationMS / 1000),
		Suffix:      suffix,
		ContentType: mime,
		Type:        "music",
		fileID:      tr.FilePID,
		carved:      tr.Virtual,
	}
	if tr.Explicit {
		// The facts sweep matches the tag values that assert explicit,
		// never a truthy parse, and any asserting value wins even beside
		// others - over-claiming explicit is an advisory's safe direction.
		// Why clean is not emitted: the ExplicitStatus doc on child.
		c.ExplicitStatus = "explicit"
	}
	if al != nil {
		c.AlbumID = al.id
		c.ArtistID = al.artistID
		c.Parent = c.AlbumID
		// An untagged file still belongs to a group, and that group has a
		// display name ("[Unknown Album]"). Sending its id without its
		// name leaves a client holding an album reference it cannot
		// draw: every row is bound to song.album, and the folder views
		// name the same group in full.
		if c.Album == "" {
			c.Album = al.name
		}
		if c.Artist == "" {
			c.Artist = al.artist
		}
	}
	return c
}

// --- rendering ---------------------------------------------------------------

// ok renders a success envelope in the requested format, the caller's
// marks filled in.
func (h *Handler) ok(w http.ResponseWriter, r *http.Request, env envelope) {
	env.Status = "ok"
	h.annotate(r, &env)
	h.render(w, r, env)
}

// fail renders a Subsonic error envelope. Never a bare 500: the
// protocol carries errors inside a 200 response.
func (h *Handler) fail(w http.ResponseWriter, r *http.Request, code int, message string) {
	h.render(w, r, envelope{Status: "failed", Error: &subError{Code: code, Message: message}})
}

// failStatus is fail under an HTTP status of its own, for the responses
// a browser loads directly, where only the status says it failed.
func (h *Handler) failStatus(w http.ResponseWriter, r *http.Request, status, code int, message string) {
	h.renderStatus(w, r, status, envelope{Status: "failed", Error: &subError{Code: code, Message: message}})
}

func (h *Handler) render(w http.ResponseWriter, r *http.Request, env envelope) {
	h.renderStatus(w, r, http.StatusOK, env)
}

// jsonpCallback is what a jsonp callback name may be: a dotted
// JavaScript identifier, nothing a response could be made to run.
var jsonpCallback = regexp.MustCompile(`^[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*$`)

func (h *Handler) renderStatus(w http.ResponseWriter, r *http.Request, status int, env envelope) {
	env.Xmlns = "http://subsonic.org/restapi"
	env.Version = apiVersion
	env.Type = "waxdeck"
	env.ServerVersion = h.version
	env.OpenSubsonic = true
	switch strings.ToLower(r.Form.Get("f")) {
	case "json":
		h.writeJSON(w, status, "", env)
	case "jsonp":
		callback := r.Form.Get("callback")
		if !jsonpCallback.MatchString(callback) {
			env = envelope{Xmlns: env.Xmlns, Version: env.Version, Type: env.Type, ServerVersion: env.ServerVersion,
				OpenSubsonic: true, Status: "failed", Error: &subError{Code: 10, Message: "jsonp needs a callback name"}}
			h.writeJSON(w, status, "", env)
			return
		}
		h.writeJSON(w, status, callback, env)
	default:
		w.Header().Set("Content-Type", "application/xml")
		w.WriteHeader(status)
		w.Write([]byte(xml.Header))
		xml.NewEncoder(w).Encode(env)
	}
}

// writeJSON renders the JSON form, wrapped in callback when one is named.
// Every list renders as [] when it has no members: clients index into
// them without checking for null.
func (h *Handler) writeJSON(w http.ResponseWriter, status int, callback string, env envelope) {
	emptyLists(reflect.ValueOf(&env).Elem())
	body, err := json.Marshal(map[string]envelope{"subsonic-response": env})
	if err != nil {
		http.Error(w, "rendering the response failed", http.StatusInternalServerError)
		return
	}
	if callback == "" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		w.Write(body)
		w.Write([]byte("\n"))
		return
	}
	w.Header().Set("Content-Type", "application/javascript")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.WriteHeader(status)
	fmt.Fprintf(w, "%s(%s);", callback, body)
}

// emptyLists replaces every nil slice the JSON rendering reaches from v
// with an empty one: exported fields, and embedded shapes whatever their
// own names, whose exported fields render as the outer shape's.
func emptyLists(v reflect.Value) {
	switch v.Kind() {
	case reflect.Pointer:
		if !v.IsNil() {
			emptyLists(v.Elem())
		}
	case reflect.Struct:
		t := v.Type()
		for i := range v.NumField() {
			if f := t.Field(i); f.IsExported() || f.Anonymous {
				emptyLists(v.Field(i))
			}
		}
	case reflect.Slice:
		if v.IsNil() {
			if v.CanSet() {
				v.Set(reflect.MakeSlice(v.Type(), 0, 0))
			}
			return
		}
		for i := range v.Len() {
			emptyLists(v.Index(i))
		}
	}
}
