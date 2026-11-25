package api

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// downloadFixture is what the provider leaves in a download: a tagged
// file with the thumbnail as its front picture and the origin tags.
func downloadFixture(t *testing.T, title, videoURL string) string {
	t.Helper()
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "thumbed", Codec: fixtures.CodecMP3, Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": title, "ARTIST": "DJ Harness"},
	})
	if err != nil {
		t.Fatal(err)
	}
	doc, err := waxlabel.ParseFile(context.Background(), paths[0])
	if err != nil {
		t.Fatal(err)
	}
	ed := doc.Edit().Set(tag.SourceURL, videoURL).Set(tag.SourceID, "thumb")
	ed.AddPicture(waxlabel.Picture{Type: waxlabel.PicFrontCover, MIME: "image/png", Data: coverBytes(t, 90)})
	plan, err := ed.Prepare()
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := plan.Execute(context.Background(), waxlabel.SaveBack()); err != nil {
		t.Fatalf("embedding the thumbnail: %v", err)
	}
	return paths[0]
}

func acquireHarness(t *testing.T, src *fakeAcquireSource) *harness {
	t.Helper()
	return newHarnessWith(t, func(cfg *service.Config) {
		cfg.SourceProviders = append(cfg.SourceProviders, src)
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
		cfg.AllowPrivateFeedHosts = true
	})
}

// acquireAsIs downloads one video and files it as it is.
func acquireAsIs(t *testing.T, h *harness, videoURL string) {
	t.Helper()
	task := decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/acquisitions",
		map[string]any{"url": videoURL, "mediaType": "music"}), 202, "acquisition")
	drainTools(t, h)
	drainMatches(t, h)
	got := decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+task.Id, h.token))
	if got.State != "done" || got.ResultPids == nil || len(*got.ResultPids) != 1 {
		t.Fatalf("acquire task = %+v", got)
	}
	entryID := (*got.ResultPids)[0]
	if entry := reviewAs(t, h, h.token, entryID); entry.Status != "pending" {
		t.Fatalf("entry status = %q, want pending for an as-is decision", entry.Status)
	}
	decodeStatus[ReviewDecideResult](t, h.postJSON(t, "/api/v1/review/queue/"+entryID+"/decide",
		map[string]any{"action": "as-is"}), 200, "as-is")
	h.rescanAndWait(t)
}

// itemsTitled lists the pids of the library's items with this title.
func itemsTitled(t *testing.T, h *harness, title string) []string {
	t.Helper()
	var pids []string
	for _, it := range h.items(t, "?limit=200").Items {
		if it.Title == title {
			pids = append(pids, it.Pid)
		}
	}
	return pids
}

// origin reads an item's acquisition origin as type and source URL.
func origin(t *testing.T, h *harness, pid string) (string, string) {
	t.Helper()
	acq := h.itemMeta(t, pid).Acquisition
	if acq == nil {
		return "none", ""
	}
	return acq.SourceType, deref(acq.SourceUrl)
}

// A download records the source it came through as the item's origin,
// and its embedded thumbnail is that source's picture, not the file's
// own: item detail names the source after an as-is import, and a forced
// rescan, which re-reads the picture as the file's, does not undo that.
func TestADownloadsThumbnailIsTheSources(t *testing.T) {
	t.Parallel()
	const videoURL = "https://tube.example/watch?v=thumb"
	src := &fakeAcquireSource{files: map[string]string{videoURL: downloadFixture(t, "Thumbnail Cut", videoURL)}}
	h := acquireHarness(t, src)
	acquireAsIs(t, h, videoURL)

	pids := itemsTitled(t, h, "Thumbnail Cut")
	if len(pids) != 1 {
		t.Fatalf("items titled Thumbnail Cut = %v, want one", pids)
	}
	pid := pids[0]
	if typ, url := origin(t, h, pid); typ != "youtube" || url != "https://tube.example/watch" {
		t.Errorf("origin = %s %q, want youtube and the item's URL", typ, url)
	}
	check := func(when string) {
		t.Helper()
		typ, _ := origin(t, h, pid)
		item := decode[Item](t, get(t, h.ts, "/api/v1/items/"+pid, h.token))
		if item.ArtSource == nil {
			t.Fatalf("%s: item detail carries no artSource (origin %s)", when, typ)
		}
		if item.ArtSource.Source != "acquisition" || deref(item.ArtSource.Provider) != "youtube" {
			t.Errorf("%s: artSource = %s/%s, want acquisition/youtube (origin %s)",
				when, item.ArtSource.Source, deref(item.ArtSource.Provider), typ)
		}
		// Where a download came from is its acquisition record, not the
		// cover's.
		if item.ArtSource.SourceUrl != nil {
			t.Errorf("%s: artSource sourceUrl = %q, want none", when, *item.ArtSource.SourceUrl)
		}
		art := get(t, h.ts, "/api/v1/items/"+pid+"/art", h.token)
		art.Body.Close()
		if art.StatusCode != 200 {
			t.Fatalf("%s: art read = %d", when, art.StatusCode)
		}
		if s, p := art.Header.Get("X-Art-Source"), art.Header.Get("X-Art-Provider"); s != "acquisition" || p != "youtube" {
			t.Errorf("%s: art headers = %s/%s, want acquisition/youtube", when, s, p)
		}
		if _, ok := art.Header["X-Art-Source-Url"]; ok {
			t.Errorf("%s: art headers carry X-Art-Source-Url %q, want none", when, art.Header.Get("X-Art-Source-Url"))
		}
		roles := decode[ArtRoles](t, get(t, h.ts, "/api/v1/items/"+pid+"/art-roles", h.token))
		if roles.ArtSource == nil || roles.ArtSource.Source != "acquisition" {
			t.Errorf("%s: the artwork read's artSource = %+v, want acquisition", when, roles.ArtSource)
		}
		// The single's album page borrows the thumbnail from its track.
		if item.AlbumPid == nil {
			t.Fatalf("%s: the download has no album", when)
		}
		album := decode[AlbumDetail](t, get(t, h.ts, "/api/v1/albums/"+*item.AlbumPid, h.token))
		if a := album.ArtSource; a == nil || a.Source != "acquisition" || deref(a.Provider) != "youtube" ||
			a.Derived == nil || !*a.Derived {
			t.Errorf("%s: the album's artSource = %+v, want acquisition/youtube, derived", when, a)
		}
	}
	check("after the as-is import")
	h.rescanAndWaitWith(t, `{"force": true}`)
	check("after a forced rescan")
}

// A download whose audio the library already holds joins that item as a
// copy, and the item keeps the origin it had.
func TestADownloadJoiningAHeldItemKeepsItsOrigin(t *testing.T) {
	t.Parallel()
	const videoURL = "https://tube.example/watch?v=again"
	path := downloadFixture(t, "Held Cut", videoURL)
	src := &fakeAcquireSource{files: map[string]string{videoURL: path}}
	h := acquireHarness(t, src)

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(h.library, "held-cut.mp3"), raw, 0o644); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	pids := itemsTitled(t, h, "Held Cut")
	if len(pids) != 1 {
		t.Fatalf("items titled Held Cut = %v, want the library's one", pids)
	}
	held := pids[0]
	wantStatus(t, h.putJSON(t, "/api/v1/items/"+held+"/acquisition", map[string]any{
		"sourceType": "rss", "sourceUrl": "https://feeds.example/show.xml", "lock": false, "writeBack": false,
	}), 200, "recording the held item's origin")

	acquireAsIs(t, h, videoURL)
	if pids := itemsTitled(t, h, "Held Cut"); len(pids) != 1 || pids[0] != held {
		t.Fatalf("items titled Held Cut = %v, want the download joined %s", pids, held)
	}
	if typ, url := origin(t, h, held); typ != "rss" || url != "https://feeds.example/show.xml" {
		t.Errorf("the held item's origin = %s %q, want the rss origin it had", typ, url)
	}
}

// An upload makes no claim about where its bytes came from.
func TestAnUploadRecordsNoSourceAsItsOrigin(t *testing.T) {
	t.Parallel()
	h := acquireHarness(t, &fakeAcquireSource{})
	uploadDeclaring(t, h, h.token, downloadFixture(t, "Uploaded Cut", "https://tube.example/watch?v=up"),
		map[string]any{"identify": false})
	drainMatches(t, h)
	h.rescanAndWait(t)
	pids := itemsTitled(t, h, "Uploaded Cut")
	if len(pids) != 1 {
		t.Fatalf("items titled Uploaded Cut = %v, want one", pids)
	}
	if typ, _ := origin(t, h, pids[0]); typ != "manual" {
		t.Errorf("an upload's origin = %s, want manual", typ)
	}
	item := decode[Item](t, get(t, h.ts, "/api/v1/items/"+pids[0], h.token))
	if item.ArtSource == nil || item.ArtSource.Source != "tag" {
		t.Errorf("an upload's artSource = %+v, want the file's own", item.ArtSource)
	}
}

// A playlist sync's download records the source too.
func TestAPlaylistSyncDownloadRecordsItsSource(t *testing.T) {
	t.Parallel()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	entries := syncFixtureEntries(t, t.TempDir(), 1)
	src.setEntries(entries...)
	h := syncHarness(t, src)
	pl := createStaticPlaylist(t, h, "Mirror Me")
	wantStatus(t, h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "append", "intervalHours": 6,
	}), 200, "bind")
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("sync = %+v", task)
	}
	drainMatches(t, h)
	h.rescanAndWait(t)
	pids := itemsTitled(t, h, entries[0].title)
	if len(pids) != 1 {
		t.Fatalf("items titled %q = %v, want one", entries[0].title, pids)
	}
	if typ, url := origin(t, h, pids[0]); typ != "youtube" || url != "https://tube.example/watch" {
		t.Errorf("a synced download's origin = %s %q, want youtube and the entry's URL", typ, url)
	}
}
