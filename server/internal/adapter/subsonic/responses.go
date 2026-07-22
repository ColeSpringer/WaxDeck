package subsonic

import (
	"encoding/json"
	"encoding/xml"
	"net/http"
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
}

type directory struct {
	ID       string  `xml:"id,attr" json:"id"`
	Parent   string  `xml:"parent,attr,omitempty" json:"parent,omitempty"`
	Name     string  `xml:"name,attr" json:"name"`
	Children []child `xml:"child" json:"child"`
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

type musicFolders struct {
	Folders []musicFolder `xml:"musicFolder" json:"musicFolder"`
}

type musicFolder struct {
	ID   int    `xml:"id,attr" json:"id"`
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
}

type albumWithSongs struct {
	albumID3
	Songs []child `xml:"song" json:"song"`
}

type albumList2 struct {
	Albums []albumID3 `xml:"album" json:"album"`
}

// child is the Subsonic song shape (the protocol's directory-era name).
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
	Genre       string `xml:"genre,attr,omitempty" json:"genre,omitempty"`
	CoverArt    string `xml:"coverArt,attr,omitempty" json:"coverArt,omitempty"`
	Duration    int    `xml:"duration,attr" json:"duration"`
	Suffix      string `xml:"suffix,attr,omitempty" json:"suffix,omitempty"`
	ContentType string `xml:"contentType,attr,omitempty" json:"contentType,omitempty"`
	AlbumID     string `xml:"albumId,attr,omitempty" json:"albumId,omitempty"`
	ArtistID    string `xml:"artistId,attr,omitempty" json:"artistId,omitempty"`
	Type        string `xml:"type,attr" json:"type"`
}

type genres struct {
	Genres []genre `xml:"genre" json:"genre"`
}

type genre struct {
	Name      string `xml:",chardata" json:"value"`
	SongCount int    `xml:"songCount,attr" json:"songCount"`
	// AlbumCount is nominally part of the shape; the read-only surface
	// reports songs only.
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
// count are exact on detail responses; list responses report the
// stored count for manual playlists and zero for smart ones, whose
// membership is computed on read.
type playlistShape struct {
	ID        string `xml:"id,attr" json:"id"`
	Name      string `xml:"name,attr" json:"name"`
	Owner     string `xml:"owner,attr,omitempty" json:"owner,omitempty"`
	Public    bool   `xml:"public,attr" json:"public"`
	SongCount int    `xml:"songCount,attr" json:"songCount"`
	Duration  int    `xml:"duration,attr" json:"duration"`
	Created   string `xml:"created,attr" json:"created"`
	Changed   string `xml:"changed,attr" json:"changed"`
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
	Entries []child `xml:"entry" json:"entry"`
}

// --- shape builders ----------------------------------------------------------

func (a *artist) id3() artistID3 {
	out := artistID3{ID: encodeArtistID(a.name), Name: a.name, AlbumCount: len(a.albums)}
	out.CoverArt = out.ID
	return out
}

func (al *album) id3() albumID3 {
	id := encodeAlbumID(al.artist, al.name)
	return albumID3{
		ID:        id,
		Name:      al.name,
		Artist:    al.artist,
		ArtistID:  encodeArtistID(al.artist),
		CoverArt:  id,
		SongCount: len(al.tracks),
		Duration:  int(al.durMS / 1000),
		Year:      al.year,
		Genre:     al.genre,
	}
}

// subsonicMimes maps source containers for the contentType attribute.
var subsonicMimes = map[string]string{
	"flac": "audio/flac",
	"mp3":  "audio/mpeg",
	"ogg":  "audio/ogg",
	"mp4":  "audio/mp4",
	"wav":  "audio/wav",
	"aiff": "audio/aiff",
	"adts": "audio/aac",
}

// albumDirChild renders an album as a folder-mode directory entry.
func albumDirChild(al *album) child {
	id := encodeAlbumID(al.artist, al.name)
	return child{
		ID:       id,
		Parent:   encodeArtistID(al.artist),
		IsDir:    true,
		Title:    al.name,
		Artist:   al.artist,
		Year:     al.year,
		Genre:    al.genre,
		CoverArt: id,
		Duration: int(al.durMS / 1000),
		AlbumID:  id,
		ArtistID: encodeArtistID(al.artist),
		Type:     "music",
	}
}

func songChild(tr track, al *album) child {
	c := child{
		ID:          tr.PID,
		IsDir:       false,
		Title:       tr.Title,
		Album:       tr.Album,
		Artist:      tr.Artist,
		Track:       tr.TrackNo,
		DiscNumber:  tr.DiscNo,
		Year:        tr.Year,
		Genre:       tr.Genre,
		CoverArt:    tr.PID,
		Duration:    int(tr.DurationMS / 1000),
		Suffix:      tr.Container,
		ContentType: subsonicMimes[tr.Container],
		Type:        "music",
	}
	if al != nil {
		c.AlbumID = encodeAlbumID(al.artist, al.name)
		c.ArtistID = encodeArtistID(al.artist)
		c.Parent = c.AlbumID
	}
	return c
}

// --- rendering ---------------------------------------------------------------

// ok renders a success envelope in the requested format.
func (h *Handler) ok(w http.ResponseWriter, r *http.Request, env envelope) {
	env.Status = "ok"
	h.render(w, r, env)
}

// fail renders a Subsonic error envelope. Never a bare 500: the
// protocol carries errors inside a 200 response.
func (h *Handler) fail(w http.ResponseWriter, r *http.Request, code int, message string) {
	h.render(w, r, envelope{Status: "failed", Error: &subError{Code: code, Message: message}})
}

func (h *Handler) render(w http.ResponseWriter, r *http.Request, env envelope) {
	env.Xmlns = "http://subsonic.org/restapi"
	env.Version = apiVersion
	env.Type = "waxdeck"
	env.ServerVersion = h.version
	env.OpenSubsonic = true
	if r.Form.Get("f") == "json" {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]envelope{"subsonic-response": env})
		return
	}
	w.Header().Set("Content-Type", "application/xml")
	w.Write([]byte(xml.Header))
	xml.NewEncoder(w).Encode(env)
}
