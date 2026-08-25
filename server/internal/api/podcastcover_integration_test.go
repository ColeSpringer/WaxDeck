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

	// The two cases that discriminate the moved comparison - a cleared
	// cover refilling on the next sync, and a hand-set one never being
	// refetched - live in the entity-surface tests below, which the
	// podcast arm of `artEntityForType` made possible.
}

// TestPodcastCoverClearedRefillsOnNextSync pins the first upstream
// behaviour the entity surface unlocked: clearing a feed-sourced show
// cover leaves no pin standing, so the next sync reads the slot as
// empty and fetches the feed's image again.
func TestPodcastCoverClearedRefillsOnNextSync(t *testing.T) {
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

	resp = reqAs(t, h, "DELETE", "/api/v1/entities/podcast/"+show.Pid+"/artwork", h.token, nil)
	wantStatus(t, resp, 204, "clear the feed cover")

	// The next sync sees an empty, unpinned slot and refills it from
	// the feed; the rewrite advances Last-Modified so the enumeration
	// runs rather than short-circuiting.
	fs.write(t)
	resubscribe(t, h, fs.feedURL())
	if got := fs.fetches.Load(); got != 2 {
		t.Fatalf("a cleared cover was fetched %d times in total, want 2 (the refill)", got)
	}
	detail := decode[PodcastDetail](t, get(t, h.ts, "/api/v1/podcasts/"+show.Pid, h.token)).Show
	if detail.ArtSource == nil || detail.ArtSource.Source != "feed" {
		t.Errorf("refilled art source = %+v, want feed", detail.ArtSource)
	}
}

// TestPodcastCoverHandSetNeverRefetched pins the second upstream
// behaviour, driven by a ManagePodcasts account rather than an
// administrator: setting a cover by hand pins it, the pin
// short-circuits the sync's comparison entirely, and the way back to
// the feed's image is unpin plus clear - each step permitted to the
// same account.
func TestPodcastCoverHandSetNeverRefetched(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	fs := newCoverFeedServer(t)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": fs.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	show := decode[Subscription](t, resp).Show
	manager := podcastAccount(t, h, "cover-manager", true)

	resp = metadataPutBytes(t, h.ts, "/api/v1/entities/podcast/"+show.Pid+"/artwork", manager, tinyPNG(t))
	wantStatus(t, resp, 200, "manager sets the show cover")
	detail := decode[PodcastDetail](t, get(t, h.ts, "/api/v1/podcasts/"+show.Pid, h.token)).Show
	if detail.ArtSource == nil || detail.ArtSource.Source != "user" {
		t.Errorf("hand-set art source = %+v, want user", detail.ArtSource)
	}

	// The feed publishes a different image; the pinned cover costs no
	// fetch and keeps standing.
	before := fs.fetches.Load()
	fs.imageRef.Store("/cover/b.png")
	fs.write(t)
	resubscribe(t, h, fs.feedURL())
	if got := fs.fetches.Load(); got != before {
		t.Fatalf("a hand-set cover was refetched (fetches %d -> %d)", before, got)
	}

	// The way back to the feed's image is unpin plus clear, both the
	// manager's to do; the next sync then refills.
	resp = reqAs(t, h, "PUT", "/api/v1/entities/podcast/"+show.Pid+"/artwork/lock", manager, map[string]any{"locked": false})
	wantStatus(t, resp, 200, "manager unpins")
	resp = reqAs(t, h, "DELETE", "/api/v1/entities/podcast/"+show.Pid+"/artwork", manager, nil)
	wantStatus(t, resp, 204, "manager clears")
	fs.write(t)
	resubscribe(t, h, fs.feedURL())
	if got := fs.fetches.Load(); got != before+1 {
		t.Fatalf("an unpinned, cleared cover was fetched %d times, want %d (the refill)", got, before+1)
	}
	detail = decode[PodcastDetail](t, get(t, h.ts, "/api/v1/podcasts/"+show.Pid, h.token)).Show
	if detail.ArtSource == nil || detail.ArtSource.Source != "feed" {
		t.Errorf("refilled art source = %+v, want feed", detail.ArtSource)
	}
}

// TestPodcastCoverPermissions draws the gate: ManagePodcasts (or admin)
// may set, clear, and pin a show's cover; an account without it is
// refused all four verbs; the podcast permission opens no other catalog
// entity; and the pc- prefix is enforced on the pid.
func TestPodcastCoverPermissions(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	fs := newCoverFeedServer(t)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": fs.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	show := decode[Subscription](t, resp).Show
	bystander := podcastAccount(t, h, "cover-bystander", false)

	base := "/api/v1/entities/podcast/" + show.Pid + "/artwork"
	resp = metadataPutBytes(t, h.ts, base, bystander, tinyPNG(t))
	wantStatus(t, resp, 403, "bystander set")
	resp = reqAs(t, h, "DELETE", base, bystander, nil)
	wantStatus(t, resp, 403, "bystander clear")
	resp = reqAs(t, h, "GET", base+"/lock", bystander, nil)
	wantStatus(t, resp, 403, "bystander pin read")
	resp = reqAs(t, h, "PUT", base+"/lock", bystander, map[string]any{"locked": true})
	wantStatus(t, resp, 403, "bystander pin write")

	// A default account holds the grant: ManagePodcasts is on in
	// DefaultPermissions, deliberately - the permission already carries
	// catalog-wide acts (adding shows, triggering fetches), and the
	// cover joins them. Pinned so a change to either side is a
	// conscious one.
	defaulted := podcastDefaultAccount(t, h, "cover-defaulted")
	resp = metadataPutBytes(t, h.ts, base, defaulted, tinyPNG(t))
	wantStatus(t, resp, 200, "default-permission account set")
	resp = reqAs(t, h, "PUT", base+"/lock", defaulted, map[string]any{"locked": false})
	wantStatus(t, resp, 200, "default-permission account unpin")
	resp = reqAs(t, h, "DELETE", base, defaulted, nil)
	wantStatus(t, resp, 204, "default-permission account clear")

	// The podcast permission opens no other catalog entity: artist art
	// stays administrators-only.
	manager := podcastAccount(t, h, "cover-manager-scope", true)
	resp = metadataPutBytes(t, h.ts, "/api/v1/entities/artist/ar-01JZX5N8QW3F4V9T2B7KD3M9R6/artwork", manager, tinyPNG(t))
	wantStatus(t, resp, 403, "manager on an artist entity")

	// A well-formed pid under the wrong prefix is not found, never a
	// write.
	resp = metadataPutBytes(t, h.ts, "/api/v1/entities/podcast/tr-01JZX5N8QW3F4V9T2B7KD3M9R6/artwork", h.token, tinyPNG(t))
	wantStatus(t, resp, 404, "podcast entity with a track pid")
}

// TestSessionCarriesEffectiveManagePodcasts pins the self view's field
// the client gates its podcast-curation affordances on. Effective, so
// an administrator reads true whatever their stored flag says.
func TestSessionCarriesEffectiveManagePodcasts(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	sessionManage := func(token string) *bool {
		resp := get(t, h.ts, "/api/v1/auth/session", token)
		info := decode[SessionInfo](t, resp)
		if info.User == nil {
			t.Fatal("session reports no user")
		}
		return info.User.ManagePodcasts
	}
	holder := podcastAccount(t, h, "session-holder", true)
	bystander := podcastAccount(t, h, "session-bystander", false)
	if got := sessionManage(holder); got == nil || !*got {
		t.Errorf("holder managePodcasts = %v, want true", got)
	}
	if got := sessionManage(bystander); got == nil || *got {
		t.Errorf("bystander managePodcasts = %v, want false", got)
	}
	if got := sessionManage(h.token); got == nil || !*got {
		t.Errorf("admin managePodcasts = %v, want true (effective)", got)
	}
}

// podcastDefaultAccount creates a non-admin account with no explicit
// permissions body, so it carries DefaultPermissions, and returns its
// token.
func podcastDefaultAccount(t *testing.T, h *harness, username string) string {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": username, "password": testPassword,
	})
	wantStatus(t, resp, 201, "create default account")
	return loginAs(t, h.ts, username, testPassword).Token
}

// podcastAccount creates a non-admin account with managePodcasts set as
// given and returns its token.
func podcastAccount(t *testing.T, h *harness, username string, manage bool) string {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": username, "password": testPassword,
		"permissions": map[string]any{
			"download": true, "delete": false, "explicitContent": true,
			"sharedOutputs": true, "managePodcasts": manage,
		},
	})
	wantStatus(t, resp, 201, "create account")
	return loginAs(t, h.ts, username, testPassword).Token
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
