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
