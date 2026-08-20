package api

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// coverFeedServer is a feed that declares a channel image, counting how
// often the image itself is fetched. The count is the point: the sync
// deciding whether to refetch is what these tests are about, and it is
// not otherwise observable through the API.
type coverFeedServer struct {
	dir      string
	ts       *httptest.Server
	fetches  atomic.Int64
	imageRef atomic.Value // string: the image path the feed currently declares
	writes   int
}

func newCoverFeedServer(t *testing.T) *coverFeedServer {
	t.Helper()
	fs := &coverFeedServer{dir: t.TempDir()}
	fs.imageRef.Store("/cover/a.png")
	png := tinyPNG(t)
	mux := http.NewServeMux()
	mux.HandleFunc("/feed.xml", func(w http.ResponseWriter, r *http.Request) {
		http.ServeFile(w, r, filepath.Join(fs.dir, "feed.xml"))
	})
	mux.HandleFunc("/cover/", func(w http.ResponseWriter, _ *http.Request) {
		fs.fetches.Add(1)
		w.Header().Set("Content-Type", "image/png")
		w.Write(png)
	})
	fs.ts = httptest.NewServer(mux)
	t.Cleanup(fs.ts.Close)
	fs.write(t)
	return fs
}

func (fs *coverFeedServer) imageURL() string {
	return fs.ts.URL + fs.imageRef.Load().(string)
}

func (fs *coverFeedServer) feedURL() string { return fs.ts.URL + "/feed.xml" }

// write renders the feed at whatever image it currently declares. The
// enumeration is conditional on Last-Modified, so each write advances
// the file's timestamp the way a feed publishing a change does.
func (fs *coverFeedServer) write(t *testing.T) {
	t.Helper()
	doc := fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
<channel>
<title>Cover Cast</title>
<description>A show with a picture.</description>
<itunes:image href="%s"/>
<item>
	<title>Only Episode</title>
	<guid isPermaLink="false">cover-ep-1</guid>
	<pubDate>%s</pubDate>
	<description>Notes.</description>
</item>
</channel>
</rss>`, fs.imageURL(), time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z))
	path := filepath.Join(fs.dir, "feed.xml")
	if err := os.WriteFile(path, []byte(doc), 0o644); err != nil {
		t.Fatal(err)
	}
	fs.writes++
	stamp := time.Now().Add(time.Duration(fs.writes) * 2 * time.Second)
	if err := os.Chtimes(path, stamp, stamp); err != nil {
		t.Fatal(err)
	}
}

// TestPodcastCoverSyncComparesTheStoredCover covers what the upstream
// bump makes true for free, so it is a test rather than a change: the
// sync now compares the feed's image URL against the cover the show
// actually holds, not against a remembered URL on the show row.
//
// WaxDeck touches neither the image URL nor the comparison, which is
// exactly why this needs pinning: nothing in this repository would fail
// if the behaviour regressed upstream.
func TestPodcastCoverSyncComparesTheStoredCover(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	fs := newCoverFeedServer(t)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": fs.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	show := decode[Subscription](t, resp).Show
	if got := fs.fetches.Load(); got != 1 {
		t.Fatalf("the first sync fetched the channel image %d times, want 1", got)
	}

	// The show's cover is the feed's, and says so: this is the mark a
	// show header draws, and the one case where "from the feed" is the
	// whole answer.
	detail := decode[PodcastDetail](t, get(t, h.ts, "/api/v1/podcasts/"+show.Pid, h.token)).Show
	if detail.ArtSource == nil {
		t.Fatal("the show detail read reports no art source for a feed cover")
	}
	if detail.ArtSource.Source != "feed" {
		t.Errorf("show art source = %q, want feed", detail.ArtSource.Source)
	}
	if got := deref(detail.ArtSource.SourceUrl); !strings.HasSuffix(got, "/cover/a.png") {
		t.Errorf("show art sourceUrl = %q, want the feed's image", got)
	}

	// A second sync over an unchanged image does not fetch it again.
	// This is the comparison that moved: it is now against the stored
	// cover's own source URL rather than a remembered one on the show.
	//
	// Re-adding is the sync this drives, not the refresh endpoint: a
	// manual refresh inside a minute of the last one is deliberately a
	// no-op, so it would prove nothing here. Re-adding an existing show
	// syncs it, which is the path an OPML re-import takes.
	fs.write(t)
	resubscribe(t, h, fs.feedURL())
	if got := fs.fetches.Load(); got != 1 {
		t.Fatalf("an unchanged channel image was fetched %d times, want 1", got)
	}

	// A feed that publishes a different image is refetched, and the show
	// reports the new address.
	fs.imageRef.Store("/cover/b.png")
	fs.write(t)
	resubscribe(t, h, fs.feedURL())
	if got := fs.fetches.Load(); got != 2 {
		t.Fatalf("a changed channel image was fetched %d times in total, want 2", got)
	}
	detail = decode[PodcastDetail](t, get(t, h.ts, "/api/v1/podcasts/"+show.Pid, h.token)).Show
	if got := deref(detail.ArtSource.SourceUrl); !strings.HasSuffix(got, "/cover/b.png") {
		t.Errorf("show art sourceUrl = %q, want the feed's new image", got)
	}

	// What this cannot reach, and why. The two cases above both pass
	// against a remembered URL on the show row as well, so neither
	// discriminates the comparison that actually moved upstream. The
	// two that would - a cleared cover refilling on the next sync, and
	// a hand-set one never being refetched - both need the show's cover
	// to be settable as an entity, and `artEntityForType` has no
	// podcast case: the permission question behind adding one
	// (ManagePodcasts or admin) is unsettled and is recorded in
	// docs/deferred-work.md. When it settles, both belong here.
}

// resubscribe re-adds a show, which syncs it.
func resubscribe(t *testing.T, h *harness, feedURL string) {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feedURL})
	defer resp.Body.Close()
	if resp.StatusCode != 200 && resp.StatusCode != 201 {
		t.Fatalf("re-subscribe status = %d", resp.StatusCode)
	}
}

// TestLibraryRootCaseFolding covers the second free fix: library lookup
// folds case on Windows, so one tree stops registering as two. WaxDeck
// registers roots through its own admin surface, which is the path that
// would mint the duplicate.
func TestLibraryRootCaseFolding(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	dir := t.TempDir()

	first := h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "cased", "path": dir, "media": "music",
	})
	if first.StatusCode != 201 {
		t.Fatalf("first register status = %d", first.StatusCode)
	}
	lib := decode[LibraryCreated](t, first)

	// The same tree under a different spelling. Only a filesystem that
	// folds case has one tree here at all: anywhere else the recased
	// path is simply a path that does not exist, and the refusal that
	// earns would say nothing about the lookup under test - which is
	// how this test spent its first life passing on CI without ever
	// reaching the behaviour it names.
	recased := swapCase(dir)
	if recased == dir {
		t.Skip("the temp path has no letters to recase")
	}
	if !foldsCase(t, dir, recased) {
		t.Skip("this filesystem is case-sensitive, so there is no duplicate root to mint")
	}
	second := h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "recased", "path": recased, "media": "music",
	})
	switch second.StatusCode {
	case 200, 201:
		if body := decode[LibraryCreated](t, second); body.Pid != lib.Pid {
			t.Fatalf("a re-cased path registered as a second library (%s vs %s)", body.Pid, lib.Pid)
		}
	case 400, 409:
		// Refused as overlapping an existing root, which is the same
		// statement: the two spellings are one tree.
		second.Body.Close()
	default:
		t.Fatalf("re-cased register status = %d", second.StatusCode)
	}
}

// foldsCase reports whether the filesystem behind dir resolves recased
// to that same directory. Probed rather than inferred from GOOS: a
// case-sensitive volume mounted on Windows and a case-insensitive one
// on Linux are both ordinary, and inferring would make this test lie on
// either.
func foldsCase(t *testing.T, dir, recased string) bool {
	t.Helper()
	const probe = "case-probe"
	if err := os.WriteFile(filepath.Join(dir, probe), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	// The file name is untouched; only the directory spelling changed,
	// so a hit means the path folded.
	_, err := os.Stat(filepath.Join(recased, probe))
	return err == nil
}

// swapCase flips the case of every letter in a path, so a caller can ask
// for the same tree under a spelling no filesystem would have handed it.
func swapCase(s string) string {
	return strings.Map(func(r rune) rune {
		switch {
		case r >= 'a' && r <= 'z':
			return r - 32
		case r >= 'A' && r <= 'Z':
			return r + 32
		}
		return r
	}, s)
}
