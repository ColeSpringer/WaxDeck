package api

import (
	"context"
	"maps"
	"net/http"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// wantSingleAlbum checks the album an unmatched download is filed under:
// "<Title> - Single" by its artist, unlocked and attributed to
// normalization, in the catalog, in the file and as an album of its own.
// It answers the album's pid.
func wantSingleAlbum(t *testing.T, h *harness, title, artist string) string {
	t.Helper()
	it := h.itemTitled(t, h.token, title)
	want := title + " - Single"
	if got := deref(it.Album); got != want {
		t.Errorf("%q album = %q, want %q", title, got, want)
	}
	if got := h.itemMeta(t, it.Pid).Fields["album_artist"]; got != artist {
		t.Errorf("%q album artist = %q, want %q", title, got, artist)
	}
	prov := provenanceOf(t, h, it.Pid)
	for _, field := range []string{"album", "album_artist"} {
		if p := prov[field]; p.source != "normalize" || p.locked {
			t.Errorf("%q %s provenance = %+v, want normalize, unlocked", title, field, p)
		}
	}
	if tags := fileTagsOf(t, h, it.Pid); tags[tag.Album] != want || tags[tag.AlbumArtist] != artist {
		t.Errorf("%q file tags = %q, want the album %q by %q", title, tags, want, artist)
	}
	if it.AlbumPid == nil {
		t.Errorf("%q has no album entity", title)
		return ""
	}
	album := decodeStatus[AlbumDetail](t, get(t, h.ts, "/api/v1/albums/"+*it.AlbumPid, h.token), 200, "album")
	if album.Title != want {
		t.Errorf("%q album entity = %q, want %q", title, album.Title, want)
	}
	return *it.AlbumPid
}

// fileTagsOf reads an item's file tags back off disk, the first value of
// each.
func fileTagsOf(t *testing.T, h *harness, pid string) map[tag.Key]string {
	t.Helper()
	files := h.itemFiles(t, h.token, pid)
	if len(files) == 0 || files[0].Path == nil {
		t.Fatalf("item %s lists no file path: %+v", pid, files)
	}
	path := *files[0].Path
	if !filepath.IsAbs(path) {
		path = filepath.Join(h.library, path)
	}
	doc, err := waxlabel.ParseFile(context.Background(), path)
	if err != nil {
		t.Fatalf("reading %s: %v", filepath.Base(path), err)
	}
	out := map[tag.Key]string{}
	for _, k := range []tag.Key{tag.Title, tag.Artist, tag.Album, tag.AlbumArtist} {
		if v, ok := doc.Get(k); ok && len(v) > 0 {
			out[k] = v[0]
		}
	}
	return out
}

// wantHeld checks a decision found its file's audio already in its place.
func wantHeld(t *testing.T, res ReviewDecideResult) {
	t.Helper()
	if res.Warnings == nil || !strings.Contains(strings.Join(*res.Warnings, "\n"), "already in the library; nothing was added") {
		t.Errorf("decision warnings = %v, want the file held", res.Warnings)
	}
}

// acquireOneAs acquires one address and answers the entry it opened.
func acquireOneAs(t *testing.T, h *harness, token string, body map[string]any) string {
	t.Helper()
	task := decodeStatus[ToolTask](t, postJSONAs(t, h, token, "/api/v1/acquisitions", body), 202, "acquisition")
	drainTools(t, h)
	drainMatches(t, h)
	got := decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+task.Id, token))
	if got.State != "done" || got.ResultPids == nil || len(*got.ResultPids) != 1 {
		t.Fatalf("acquiring %v: task = %+v", body["url"], got)
	}
	return (*got.ResultPids)[0]
}

// acquiringHarness serves src's addresses into managed roots.
func acquiringHarness(t *testing.T, src *fakeAcquireSource, opts ...func(*service.Config)) *harness {
	t.Helper()
	return newHarnessWith(t, func(cfg *service.Config) {
		cfg.SourceProviders = append(cfg.SourceProviders, src)
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
		cfg.AllowPrivateFeedHosts = true
		for _, o := range opts {
			o(cfg)
		}
	})
}

// cannedFiles synthesizes one MP3 per address, tagged as given.
func cannedFiles(t *testing.T, src *fakeAcquireSource, tags map[string]map[string]string) {
	t.Helper()
	media := t.TempDir()
	sec := 3
	for _, url := range slices.Sorted(maps.Keys(tags)) {
		tg := tags[url]
		paths, err := fixtures.Generate(media, fixtures.Spec{
			Name: strings.TrimPrefix(url, "https://tube.example/watch?v="), Codec: fixtures.CodecMP3,
			Duration: time.Duration(sec) * time.Second, Tags: tg,
		})
		if err != nil {
			t.Fatal(err)
		}
		src.files[url] = paths[0]
		sec++
	}
}

// A download's suggested artist and title land when the decision asks
// for them, as the decider's own edit, and the album default reads the
// title they left.
func TestAnUnmatchedDownloadTakesTheSuggestedArtistAndTitle(t *testing.T) {
	t.Parallel()
	const (
		suggested = "https://tube.example/watch?v=suggested"
		again     = "https://tube.example/watch?v=again"
		switched  = "https://tube.example/watch?v=switched"
		sideA     = "https://tube.example/watch?v=side-a"
		sideB     = "https://tube.example/watch?v=side-b"
	)
	src := &fakeAcquireSource{
		playlistURL: "https://tube.example/playlist?list=PLsides",
		files:       map[string]string{},
		entries: []struct{ title, url string }{
			{"Side A", sideA},
			{"Side B", sideB},
		},
	}
	topic := func(title string) map[string]string {
		return map[string]string{"TITLE": title, "ARTIST": "Blue Room Records - Topic"}
	}
	cannedFiles(t, src, map[string]map[string]string{
		suggested: topic("Nas - How Ya Livin' (Official Video)"),
		again:     topic("Nas - One Mic (Official Video)"),
		switched:  topic("Nas - Chapter One (Official Video)"),
		sideA:     {"TITLE": "Side A", "ARTIST": "Hold Steady State", "ALBUM": "Two Sides"},
		sideB:     {"TITLE": "Side B", "ARTIST": "Hold Steady State", "ALBUM": "Two Sides"},
	})
	h := acquiringHarness(t, src, func(cfg *service.Config) { cfg.MatchSource = &recordingSource{} })
	decide := func(id string, body map[string]any) *http.Response {
		return postJSONAs(t, h, h.token, "/api/v1/review/queue/"+id+"/decide", body)
	}

	// An album-shaped unit offers no suggestion: asking for one is refused
	// before anything lands, and once decided the entry answers conflict
	// first.
	sides := acquireOneAs(t, h, h.token, map[string]any{"url": src.playlistURL, "mediaType": "music"})
	if s := getReview(t, h, sides).Suggested; s != nil {
		t.Fatalf("an album-shaped unit offered %+v", s)
	}
	refusal := decodeStatus[Error](t, decide(sides, map[string]any{"action": "as-is", "useSuggested": true}), 400, "as-is with no suggestion")
	if refusal.Code != "invalid-request" {
		t.Errorf("refusal = %+v, want invalid-request", refusal)
	}
	if e := getReview(t, h, sides); e.Status != "pending" || e.MediumFixed != nil {
		t.Fatalf("refused entry = %+v, want it pending with nothing landed", e)
	}
	decideAs(t, h, h.token, sides, map[string]any{"action": "as-is"})
	conflict := decodeStatus[Error](t, decide(sides, map[string]any{"action": "as-is", "useSuggested": true}), 409, "a decided entry")
	if conflict.Code != "conflict" {
		t.Errorf("refusal = %+v, want conflict", conflict)
	}

	id := acquireOneAs(t, h, h.token, map[string]any{"url": suggested, "mediaType": "music"})
	if s := getReview(t, h, id).Suggested; s == nil || deref(s.Artist) != "Nas" || deref(s.Title) != "How Ya Livin'" {
		t.Fatalf("suggestion = %+v, want Nas and How Ya Livin'", s)
	}
	decideAs(t, h, h.token, id, map[string]any{"action": "as-is", "useSuggested": true})
	it := h.itemTitled(t, h.token, "How Ya Livin'")
	if a := deref(it.Artist); a != "Nas" {
		t.Errorf("artist = %q, want the suggested one", a)
	}
	prov := provenanceOf(t, h, it.Pid)
	for _, field := range []string{"title", "artist"} {
		if p := prov[field]; p.source != "user" || !p.locked {
			t.Errorf("%s provenance = %+v, want a locked user edit", field, p)
		}
	}
	if tags := fileTagsOf(t, h, it.Pid); tags[tag.Title] != "How Ya Livin'" || tags[tag.Artist] != "Nas" {
		t.Errorf("file tags = %q, want the suggested title and artist", tags)
	}
	wantSingleAlbum(t, h, "How Ya Livin'", "Nas")

	// Downloaded again, the same audio is held where the first one's
	// delivered tags put it, though its item now reads otherwise.
	twice := acquireOneAs(t, h, h.token, map[string]any{"url": suggested, "mediaType": "music"})
	wantHeld(t, decideAs(t, h, h.token, twice, map[string]any{"action": "as-is", "useSuggested": true}))
	if it := h.itemTitled(t, h.token, "How Ya Livin'"); deref(it.Artist) != "Nas" {
		t.Errorf("held item artist = %q, want the suggestion it took", deref(it.Artist))
	}

	// A file joining an item the library holds keeps that item's metadata.
	acquireOneAs(t, h, h.token, map[string]any{"url": again, "mediaType": "music", "identify": false})
	joined := acquireOneAs(t, h, h.token, map[string]any{"url": again, "mediaType": "music"})
	if s := getReview(t, h, joined).Suggested; s == nil {
		t.Fatal("the second download offered no suggestion")
	}
	wantHeld(t, decideAs(t, h, h.token, joined, map[string]any{"action": "as-is", "useSuggested": true}))
	held := h.itemTitled(t, h.token, "Nas - One Mic")
	if a := deref(held.Artist); a != "Blue Room Records" {
		t.Errorf("held item artist = %q, want its own", a)
	}
	if p := provenanceOf(t, h, held.Pid)["title"]; p.source == "user" {
		t.Errorf("held item title provenance = %+v, want no edit", p)
	}

	// An import as an audiobook neither takes the suggestion nor an album,
	// and is not refused for asking.
	book := acquireOneAs(t, h, h.token, map[string]any{"url": switched, "mediaType": "music"})
	decideAs(t, h, h.token, book, map[string]any{"action": "as-is", "mediaType": "audiobook", "useSuggested": true})
	h.rescanAndWait(t)
	var imported []string
	for _, it := range h.items(t, "?limit=500").Items {
		if strings.Contains(it.Title, "Chapter One") {
			imported = append(imported, it.Title+" / "+deref(it.Album))
		}
	}
	if !slices.Equal(imported, []string{"Nas - Chapter One / "}) {
		t.Errorf("audiobook import = %q, want it as delivered, with no album", imported)
	}
}

// The default is a placeholder: a later identification and approval
// replaces it with the release.
func TestAReidentifiedSingleTakesTheApprovedAlbum(t *testing.T) {
	t.Parallel()
	const quiet = "https://tube.example/watch?v=quiet"
	src := &fakeAcquireSource{files: map[string]string{}}
	cannedFiles(t, src, map[string]map[string]string{quiet: {"TITLE": "Quiet Wire", "ARTIST": "Hold Steady State"}})
	h := acquiringHarness(t, src, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{releases: obviousRelease()}
	})

	id := acquireOneAs(t, h, h.token, map[string]any{"url": quiet, "mediaType": "music", "identify": false})
	if e := getReview(t, h, id); e.Status != "as-is" {
		t.Fatalf("declined entry status = %q, want as-is", e.Status)
	}
	pid := h.itemTitled(t, h.token, "Quiet Wire").Pid
	wantSingleAlbum(t, h, "Quiet Wire", "Hold Steady State")

	entryID := decodeStatus[RematchResult](t, h.postJSON(t, "/api/v1/items/"+pid+"/rematch", nil), 202, "rematch").ReviewEntryId
	drainMatches(t, h)
	if e := getReview(t, h, entryID); e.Status != "pending" || e.Best == nil {
		t.Fatalf("rematch entry = %+v, want a candidate to approve", e)
	}
	decideAs(t, h, h.token, entryID, map[string]any{"action": "approve"})
	it := h.itemTitled(t, h.token, "Quiet Wire")
	if a := deref(it.Album); a != "Quiet Wire" {
		t.Errorf("album after the approval = %q, want the release's", a)
	}
	if p := provenanceOf(t, h, pid)["album"]; p.source != "enrichment" || !p.locked {
		t.Errorf("album provenance = %+v, want a locked enrichment", p)
	}
	if tags := fileTagsOf(t, h, pid); tags[tag.Album] != "Quiet Wire" {
		t.Errorf("file album = %q, want the release's", tags[tag.Album])
	}
}

// Only a music download is given the default: an audiobook acquisition
// and an uploaded file land without one.
func TestOnlyAcquiredMusicIsFiledAsASingle(t *testing.T) {
	t.Parallel()
	const chapter = "https://tube.example/watch?v=chapter"
	src := &fakeAcquireSource{files: map[string]string{}}
	cannedFiles(t, src, map[string]map[string]string{chapter: {"TITLE": "Chapter One", "ARTIST": "Wren Hollis"}})
	h := acquiringHarness(t, src)

	id := acquireOneAs(t, h, h.token, map[string]any{"url": chapter, "mediaType": "audiobook", "identify": false})
	if e := getReview(t, h, id); e.Status != "as-is" {
		t.Fatalf("declined audiobook acquisition status = %q, want as-is", e.Status)
	}
	up := uploadDeclaring(t, h, h.token, quietTrack(t, "Uploaded Single"), map[string]any{"identify": false})
	drainMatches(t, h)
	if e := entryOf(t, h, h.token, up); e.Status != "as-is" {
		t.Fatalf("declined upload status = %q, want as-is", e.Status)
	}
	h.rescanAndWait(t)
	for _, it := range h.items(t, "?limit=500").Items {
		if strings.HasSuffix(deref(it.Album), " - Single") {
			t.Errorf("%q was given the album %q", it.Title, deref(it.Album))
		}
	}
	if it := h.itemTitled(t, h.token, "Uploaded Single"); it.AlbumPid != nil {
		t.Errorf("an uploaded single has the album %q", deref(it.Album))
	}
}
