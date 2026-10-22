package subsonic

import (
	"fmt"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A stored rating is 0..100; the protocol's is a whole 1..5.
func TestUserRatingFromAStoredRating(t *testing.T) {
	if got := userRating(nil); got != 0 {
		t.Errorf("unrated = %d, want 0 (omitted)", got)
	}
	for stored, want := range map[int]int{0: 1, 9: 1, 20: 1, 29: 1, 30: 2, 40: 2, 50: 3, 60: 3, 80: 4, 89: 4, 90: 5, 100: 5} {
		if got := userRating(&stored); got != want {
			t.Errorf("stored %d = %d stars, want %d", stored, got, want)
		}
	}
}

// Every shape the envelope carries is found: songs, album directories,
// albums with their tracks, artists in both browse modes.
func TestAnnotateFindsEveryShape(t *testing.T) {
	idx := buildIndex([]track{
		{PID: "tr-1", AlbumArtist: "X", Album: "A", AlbumPID: "al-A", AlbumArtistPID: "ar-X", FilePID: "fl-1"},
		{PID: "tr-2", AlbumArtist: "X", Album: "A", AlbumPID: "al-A", AlbumArtistPID: "ar-X", FilePID: "fl-2", Virtual: true},
	}, nil)
	al := idx.albums[0]
	a := idx.artists[0]
	song := songChild(idx.tracks[0], al)
	carved := songChild(idx.tracks[1], al)
	env := envelope{
		Album:   &albumWithSongs{albumID3: al.id3(), Songs: []child{song, carved}},
		Starred: &starred{Artists: []folderArtist{a.folder()}, Albums: []child{albumDirChild(al)}},
		Artists: &artistsID3{Index: []indexID3{{Artists: []artistID3{a.id3()}}}},
	}
	var found shapes
	found.collect(&env)
	if len(found.songs) != 2 || len(found.groups) != 1 || len(found.albums) != 1 ||
		len(found.artists) != 1 || len(found.folderArtists) != 1 {
		t.Fatalf("found %d songs, %d album folders, %d albums, %d artists, %d folder artists",
			len(found.songs), len(found.groups), len(found.albums), len(found.artists), len(found.folderArtists))
	}

	now := time.Date(2026, 10, 16, 12, 0, 0, 0, time.UTC)
	r := 80
	found.apply(
		map[string]service.ItemMark{"tr-1": {StarredAt: now, Rating: &r, PlayCount: 2, LastPlayedAt: now}, "tr-2": {PlayCount: 3}},
		map[string]service.EntityMark{"al-A": {StarredAt: now}, "ar-X": {Rating: &r}},
		map[string]service.FileFacts{"fl-1": {SizeBytes: 1000, BitrateKbps: 900, AddedAt: now}, "fl-2": {SizeBytes: 9000, BitrateKbps: 320, AddedAt: now}},
		map[string]int64{"tr-1": 4200},
	)
	s := env.Album.Songs[0]
	if s.Starred != "2026-10-16T12:00:00Z" || s.UserRating != 4 || s.PlayCount != 2 || s.Played == "" ||
		s.Size != 1000 || s.BitRate != 900 || s.Created == "" || s.BookmarkPosition != 4200 {
		t.Errorf("song = %+v", s)
	}
	if c := env.Album.Songs[1]; c.Size != 0 || c.BitRate != 320 {
		t.Errorf("a track carved out of a larger file = size %d bitrate %d, want no size", c.Size, c.BitRate)
	}
	if got := env.Album.albumID3; got.Starred == "" || got.PlayCount != 5 || got.Played == "" || got.Created == "" || got.UserRating != 0 {
		t.Errorf("album = %+v, want its star, its tracks' 5 plays, a last play and a created time", got)
	}
	if got := env.Starred.Albums[0]; got.Starred == "" || got.PlayCount != 5 {
		t.Errorf("album folder = %+v", got)
	}
	if got := env.Artists.Index[0].Artists[0]; got.UserRating != 4 || got.Starred != "" {
		t.Errorf("artist = %+v", got)
	}
	if got := env.Starred.Artists[0]; got.UserRating != 4 {
		t.Errorf("folder artist = %+v", got)
	}
}

// A group with no catalog entity behind it has no entity state to carry.
func TestAnnotateSkipsMintedGroups(t *testing.T) {
	idx := buildIndex([]track{{PID: "tr-1", AlbumArtist: "X", Album: "Loose"}}, nil)
	var found shapes
	env := envelope{AlbumList2: &albumList2{Albums: []albumID3{idx.albums[0].id3()}}}
	found.collect(&env)
	if pids := found.entityPIDs(); len(pids) != 0 {
		t.Fatalf("entity pids = %v, want none for a minted album", pids)
	}
}

// The JSON rendering says [] for a list with no members, which clients
// index into without a null check; the format name is any case, and
// jsonp wraps the document in the named callback.
func TestRenderListsAndFormats(t *testing.T) {
	h := &Handler{version: "test"}
	render := func(query string, env envelope) (string, string) {
		r := httptest.NewRequest("GET", "/rest/ping?"+query, nil)
		if err := r.ParseForm(); err != nil {
			t.Fatal(err)
		}
		w := httptest.NewRecorder()
		h.render(w, r, env)
		return w.Body.String(), w.Header().Get("Content-Type")
	}
	body, ct := render("f=JSON", envelope{SearchResult3: &searchResult3{}, AlbumList2: &albumList2{}})
	if ct != "application/json" || strings.Contains(body, "null") ||
		!strings.Contains(body, `"song":[]`) || !strings.Contains(body, `"album":[]`) {
		t.Errorf("json = %s (%s), want [] for every empty list", body, ct)
	}
	body, ct = render("f=jsonp&callback=onDone", envelope{})
	if ct != "application/javascript" || !strings.HasPrefix(body, "onDone(") || !strings.HasSuffix(body, ");") {
		t.Errorf("jsonp = %s (%s), want the document inside onDone(...)", body, ct)
	}
	body, _ = render("f=jsonp&callback=alert(1)//", envelope{})
	if strings.Contains(body, "alert") || !strings.Contains(body, `"code":10`) {
		t.Errorf("jsonp with a callback that is not a name = %s, want error 10 and no echo", body)
	}
	if body, ct = render("", envelope{}); ct != "application/xml" || !strings.Contains(body, "subsonic-response") {
		t.Errorf("default = %s (%s), want xml", body, ct)
	}
}

// An album's created is required and a song's is not, so when a response
// carries more files than one call reads, the albums' first files come
// first.
func TestAlbumFilesAreReadFirst(t *testing.T) {
	var rows []track
	for i := range 600 {
		rows = append(rows, track{PID: fmt.Sprintf("tr-s%d", i), AlbumArtist: "X", Album: "Singles",
			FilePID: fmt.Sprintf("fl-s%d", i)})
	}
	for i := range 20 {
		rows = append(rows, track{PID: fmt.Sprintf("tr-a%d", i), AlbumArtist: "X", Album: fmt.Sprintf("Album %02d", i),
			FilePID: fmt.Sprintf("fl-a%d", i)})
	}
	idx := buildIndex(rows, nil)
	env := envelope{SearchResult3: &searchResult3{}}
	var albums []*album
	for _, tr := range idx.tracks {
		al := idx.albumForTrack(tr)
		if al.name == "Singles" {
			env.SearchResult3.Songs = append(env.SearchResult3.Songs, songChild(tr, al))
		} else {
			albums = append(albums, al)
		}
	}
	for _, al := range albums {
		env.SearchResult3.Albums = append(env.SearchResult3.Albums, al.id3())
	}
	var found shapes
	found.collect(&env)
	pids := found.filePIDs()
	first := map[string]bool{}
	for _, p := range pids[:500] {
		first[p] = true
	}
	for _, al := range albums {
		if !first[al.tracks[0].FilePID] {
			t.Fatalf("album %s's first file is not among the first 500 read", al.name)
		}
	}
}

// Every nil list renders [], one inside an embedded shape included.
func TestEmptyListsReachEmbeddedShapes(t *testing.T) {
	type base struct {
		List []int `json:"list"`
	}
	type outer struct {
		base
		Other []int `json:"other"`
	}
	v := outer{}
	emptyLists(reflect.ValueOf(&v).Elem())
	if v.List == nil || v.Other == nil {
		t.Fatalf("lists = %v / %v, want both empty rather than nil", v.List, v.Other)
	}
}

// Marks a handler's own read already holds go on the response as they
// are, in place of a second read: here the catalog holds no star at all,
// so a mark that shows came from the list's read.
func TestAnnotateTakesTheMarksAListRead(t *testing.T) {
	h, uc := serviceHandler(t)
	const pid = "al-01JABCDEFGHJKMNPQRSTVWXYZ0"
	at := time.Date(2026, 10, 16, 12, 0, 0, 0, time.UTC)
	r := 60
	env := envelope{
		AlbumList2:  &albumList2{Albums: []albumID3{{ID: pid, Name: "Starred One"}}},
		entityMarks: map[string]service.EntityMark{pid: {StarredAt: at, Rating: &r}},
	}
	req := withCaller(httptest.NewRequest("GET", "/rest/getAlbumList2", nil), uc)
	h.annotate(req, &env)
	if got := env.AlbumList2.Albums[0]; got.Starred != "2026-10-16T12:00:00Z" || got.UserRating != 3 {
		t.Fatalf("album = %+v, want the list's star and its rating of 3", got)
	}
}
