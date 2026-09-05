package api

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

// decodeStatus asserts the status and decodes the body in one move
// (wantStatus closes the body, so the pair cannot compose).
func decodeStatus[T any](t *testing.T, resp *http.Response, want int, what string) T {
	t.Helper()
	if resp.StatusCode != want {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("%s status = %d, want %d (%s)", what, resp.StatusCode, want, body)
	}
	return decode[T](t, resp)
}

// fakeSyncEntry is one entry of the fake source's playlist.
type fakeSyncEntry struct {
	id, title, path string
	unavailable     bool
}

// fakeSyncSource is a mutable canned source: a provider whose playlist
// the tests edit between syncs, counting fetches so dedup is provable.
type fakeSyncSource struct {
	mu           sync.Mutex
	playlistURL  string
	title        string
	entries      []fakeSyncEntry
	fetches      map[string]int
	enumerateErr error
	// truncate marks the snapshot as cut short by the enumeration cap,
	// whatever it holds.
	truncate bool
	// probes counts snapshot reads of the playlist, which is the
	// network round trip a settings-only re-save must not spend.
	probes int
}

func syncWatchURL(id string) string { return "https://tube.example/watch?v=" + id }

func (f *fakeSyncSource) SourceType() model.SourceType { return model.SourceYouTube }

func (f *fakeSyncSource) setEntries(entries ...fakeSyncEntry) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.entries = entries
}

func (f *fakeSyncSource) probeCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.probes
}

func (f *fakeSyncSource) fetchCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	n := 0
	for _, c := range f.fetches {
		n += c
	}
	return n
}

func (f *fakeSyncSource) Resolve(_ context.Context, req source.Request) (*source.Resolved, error) {
	if req.URL != f.playlistURL {
		return nil, errors.New("not a playlist")
	}
	return &source.Resolved{IdentityKey: "youtube:PLsync", SourceType: model.SourceYouTube, Title: f.title}, nil
}

func (f *fakeSyncSource) Enumerate(_ context.Context, req source.Request) (*source.Enumeration, error) {
	if req.URL != f.playlistURL {
		return nil, errors.New("not a playlist")
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	feed := &model.Feed{Title: f.title}
	for _, e := range f.entries {
		feed.Episodes = append(feed.Episodes, model.FeedEpisode{
			GUID: e.id, Title: e.title, EnclosureURL: syncWatchURL(e.id),
		})
	}
	return &source.Enumeration{Feed: feed, IdentityKey: "youtube:PLsync", SourceID: "PLsync"}, nil
}

func (f *fakeSyncSource) Fetch(_ context.Context, req source.FetchRequest, w io.Writer) (*source.FetchResult, error) {
	f.mu.Lock()
	var path string
	for _, e := range f.entries {
		if syncWatchURL(e.id) == req.URL {
			path = e.path
			break
		}
	}
	if f.fetches == nil {
		f.fetches = map[string]int{}
	}
	f.fetches[req.URL]++
	f.mu.Unlock()
	if path == "" {
		return nil, errors.New("no such video")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	n, err := w.Write(raw)
	if err != nil {
		return nil, err
	}
	return &source.FetchResult{Bytes: int64(n), ContentType: "audio/mpeg"}, nil
}

func (f *fakeSyncSource) PlaylistSnapshot(_ context.Context, url string, opts syncsource.SnapshotOptions) (*syncsource.PlaylistSnapshot, error) {
	if url != f.playlistURL {
		return nil, errors.New("not a playlist")
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	f.probes++
	if f.enumerateErr != nil {
		return nil, f.enumerateErr
	}
	snap := &syncsource.PlaylistSnapshot{
		ID: "PLsync", IdentityKey: "youtube:PLsync", Title: f.title,
		Truncated: f.truncate,
	}
	for i, e := range f.entries {
		if opts.MaxEntries > 0 && i >= opts.MaxEntries {
			snap.Truncated = true
			break
		}
		entry := syncsource.PlaylistSnapshotEntry{
			ID: e.id, Index: i, URL: syncWatchURL(e.id), Title: e.title,
			Unavailable: e.unavailable, AvailabilityKnown: true,
		}
		if !e.unavailable {
			entry.ThumbnailURL = "https://img.example/" + e.id + ".jpg"
		}
		snap.Entries = append(snap.Entries, entry)
	}
	return snap, nil
}

var _ source.Provider = (*fakeSyncSource)(nil)
var _ syncsource.Snapshotter = (*fakeSyncSource)(nil)

// syncHarness builds a harness with the fake source wired, managed
// roots, and the admin's identify preference declined, so a sync's
// downloads file themselves as-is and the whole loop is observable
// without a matching bridge.
func syncHarness(t *testing.T, src *fakeSyncSource) *harness {
	t.Helper()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.SourceProviders = append(cfg.SourceProviders, src)
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
		cfg.AllowPrivateFeedHosts = true
	})
	resp := h.putJSON(t, "/api/v1/users/me/prefs", map[string]any{"identifyOptOut": true})
	wantStatus(t, resp, 200, "decline identify")
	return h
}

// syncFixtureEntries synthesizes count tagged tracks and returns them
// as source entries vid-1..vid-N.
func syncFixtureEntries(t *testing.T, dir string, count int) []fakeSyncEntry {
	t.Helper()
	specs := make([]fixtures.Spec, count)
	for i := range specs {
		specs[i] = fixtures.Spec{
			Name: fmt.Sprintf("sync-cut-%d", i+1), Codec: fixtures.CodecMP3,
			Duration: time.Duration(3+i) * time.Second,
			Tags: map[string]string{
				"TITLE":  fmt.Sprintf("Sync Cut %d", i+1),
				"ARTIST": "DJ Sync",
				"ALBUM":  fmt.Sprintf("Sync Singles %d", i+1),
			},
		}
	}
	paths, err := fixtures.Generate(dir, specs...)
	if err != nil {
		t.Fatal(err)
	}
	entries := make([]fakeSyncEntry, count)
	for i := range entries {
		entries[i] = fakeSyncEntry{
			id:    fmt.Sprintf("vid-%d", i+1),
			title: fmt.Sprintf("Sync Cut %d", i+1),
			path:  paths[i],
		}
	}
	return entries
}

func createStaticPlaylist(t *testing.T, h *harness, name string, itemPids ...string) Playlist {
	t.Helper()
	body := map[string]any{"name": name, "kind": "static"}
	if len(itemPids) > 0 {
		body["itemPids"] = itemPids
	}
	return decodeStatus[Playlist](t, h.postJSON(t, "/api/v1/playlists", body), 201, "create playlist")
}

func getSource(t *testing.T, h *harness, pid string) PlaylistSource {
	t.Helper()
	return decodeStatus[PlaylistSource](t, get(t, h.ts, "/api/v1/playlists/"+pid+"/source", h.token), 200, "read binding")
}

// syncNow queues a run and drains the tool worker through it.
func syncNow(t *testing.T, h *harness, pid string) ToolTask {
	t.Helper()
	task := decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/playlists/"+pid+"/source/sync", nil), 202, "sync now")
	drainTools(t, h)
	return decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+task.Id, h.token))
}

func TestPlaylistSourceBindingLifecycle(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	src.setEntries(syncFixtureEntries(t, media, 1)...)
	h := syncHarness(t, src)

	pl := createStaticPlaylist(t, h, "Bound")

	// Unbound reads answer not-found.
	resp := get(t, h.ts, "/api/v1/playlists/"+pl.Pid+"/source", h.token)
	wantStatus(t, resp, 404, "unbound read")

	// A bad interval and a bodyless-form bind are refused.
	resp = h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "mirror", "intervalHours": 2,
	})
	wantStatus(t, resp, 400, "bad interval")
	resp = h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{"mode": "mirror"})
	wantStatus(t, resp, 400, "no source form")

	// The bind echoes the stored binding, with the source's own title
	// from the probe.
	resp = h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "append", "intervalHours": 6,
	})
	bound := decodeStatus[PlaylistSource](t, resp, 200, "bind")
	if bound.Source != "youtube" || !bound.Live || bound.Mode != "append" {
		t.Fatalf("bound = %+v", bound)
	}
	if bound.IntervalHours == nil || *bound.IntervalHours != 6 {
		t.Fatalf("bound interval = %v", bound.IntervalHours)
	}
	if bound.Title == nil || *bound.Title != "Sync Tapes" {
		t.Fatalf("bound title = %v", bound.Title)
	}
	if got := getSource(t, h, pl.Pid); got.Mode != "append" || got.Disabled {
		t.Fatalf("read-back = %+v", got)
	}

	// A smart playlist has no membership to bind.
	resp = h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "smart", "kind": "smart", "rule": musicRatingRule(5),
	})
	smart := decodeStatus[Playlist](t, resp, 201, "create smart")
	resp = h.putJSON(t, "/api/v1/playlists/"+smart.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "mirror", "intervalHours": 6,
	})
	wantStatus(t, resp, 400, "bind smart")

	// Another account cannot see, bind, or sync a private playlist.
	other := podcastAccount(t, h, "sync-bystander", false)
	resp = reqAs(t, h, "GET", "/api/v1/playlists/"+pl.Pid+"/source", other, nil)
	wantStatus(t, resp, 404, "bystander read")
	resp = reqAs(t, h, "POST", "/api/v1/playlists/"+pl.Pid+"/source/sync", other, nil)
	wantStatus(t, resp, 404, "bystander sync")

	// mirror-trash needs the delete right; podcastAccount mints without
	// it. The refusal needs an owned playlist, so the bystander binds
	// their own.
	theirs := struct{ Pid string }{}
	{
		resp := reqAs(t, h, "POST", "/api/v1/playlists", other, map[string]any{"name": "theirs", "kind": "static"})
		theirs.Pid = decodeStatus[Playlist](t, resp, 201, "bystander playlist").Pid
	}
	resp = reqAs(t, h, "PUT", "/api/v1/playlists/"+theirs.Pid+"/source", other, map[string]any{
		"url": src.playlistURL, "mode": "mirror-trash", "intervalHours": 6,
	})
	wantStatus(t, resp, 403, "mirror-trash without the delete right")
	// The admin holds it implicitly.
	resp = h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "mirror-trash", "intervalHours": 6,
	})
	wantStatus(t, resp, 200, "mirror-trash as admin")

	// Unbind keeps the playlist and answers not-found afterward.
	resp = reqAs(t, h, "DELETE", "/api/v1/playlists/"+pl.Pid+"/source", h.token, nil)
	wantStatus(t, resp, 204, "unbind")
	resp = get(t, h.ts, "/api/v1/playlists/"+pl.Pid+"/source", h.token)
	wantStatus(t, resp, 404, "read after unbind")
	resp = get(t, h.ts, "/api/v1/playlists/"+pl.Pid, h.token)
	wantStatus(t, resp, 200, "playlist survives unbind")
}

// TestPlaylistSourceSettingsOnlyResave covers the re-save form: a body
// naming no source changes the settings on the binding already stored
// and leaves everything else - the source, its refs, its entries, and,
// on a live binding, the network probe that would otherwise run for
// every mode flip.
func TestPlaylistSourceSettingsOnlyResave(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	src.setEntries(syncFixtureEntries(t, media, 1)...)
	h := syncHarness(t, src)

	// Matched first, since it is the form that cannot be re-sent: the
	// export is not stored anywhere the client can read back.
	items := h.items(t, "")
	first := items.Items[0]
	if first.Artist == nil {
		t.Fatal("fixture item carries no artist")
	}
	matched := createStaticPlaylist(t, h, "Resaved matched")
	payload := fmt.Sprintf("%s - %s\nNobody Here - Never Recorded", *first.Artist, first.Title)
	bound := decodeStatus[PlaylistSource](t, h.putJSON(t, "/api/v1/playlists/"+matched.Pid+"/source", map[string]any{
		"source": "text", "payload": payload, "mode": "append",
	}), 200, "bind matched")
	if bound.RefCount == nil || *bound.RefCount != 2 {
		t.Fatalf("matched binding = %+v", bound)
	}

	// Synced once, so there is per-entry bookkeeping to lose: a matched
	// re-put used to clear it on every save.
	if task := syncNow(t, h, matched.Pid); task.State != "done" {
		t.Fatalf("matched sync = %+v", task)
	}
	before := sourceEntryStates(t, h, matched.Pid)
	if len(before) == 0 {
		t.Fatal("a synced matched binding should hold per-entry state")
	}

	resaved := decodeStatus[PlaylistSource](t, h.putJSON(t, "/api/v1/playlists/"+matched.Pid+"/source", map[string]any{
		"mode": "mirror",
	}), 200, "re-save matched")
	if resaved.Mode != "mirror" || resaved.Live || resaved.Source != "text" {
		t.Fatalf("re-saved matched = %+v", resaved)
	}
	// The refs are the thing: a re-save that rebuilt the row would have
	// needed the export again and come back holding nothing.
	if resaved.RefCount == nil || *resaved.RefCount != 2 {
		t.Fatalf("re-saved refCount = %v, want 2", resaved.RefCount)
	}
	if read := getSource(t, h, matched.Pid); read.Mode != "mirror" ||
		read.RefCount == nil || *read.RefCount != 2 {
		t.Fatalf("read-back = %+v", read)
	}
	if after := sourceEntryStates(t, h, matched.Pid); len(after) != len(before) {
		t.Fatalf("re-save left %d entry states, want the %d it had", len(after), len(before))
	}

	// mirror-trash is still out of reach for a matched binding, which
	// downloads nothing and so has nothing to trash.
	wantStatus(t, h.putJSON(t, "/api/v1/playlists/"+matched.Pid+"/source", map[string]any{
		"mode": "mirror-trash",
	}), 400, "mirror-trash on a matched binding")
	// And an interval, which a matched binding never has.
	wantStatus(t, h.putJSON(t, "/api/v1/playlists/"+matched.Pid+"/source", map[string]any{
		"mode": "append", "intervalHours": 6,
	}), 400, "an interval on a matched binding")

	// The preview twin: the stored binding under the settings Save
	// would send.
	preview := decodeStatus[PlaylistSyncPreview](t, h.postJSON(t,
		"/api/v1/playlists/"+matched.Pid+"/source/preview", map[string]any{"mode": "append"}),
		200, "settings-only preview")
	if preview.Entries != 2 {
		t.Fatalf("settings-only preview = %+v", preview)
	}

	// Live: the mode and the interval change, and the source is not
	// probed for it.
	live := createStaticPlaylist(t, h, "Resaved live")
	decodeStatus[PlaylistSource](t, h.putJSON(t, "/api/v1/playlists/"+live.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "append", "intervalHours": 6,
	}), 200, "bind live")
	probes := src.probeCount()
	if probes == 0 {
		t.Fatal("binding a live source should have probed it")
	}

	flipped := decodeStatus[PlaylistSource](t, h.putJSON(t, "/api/v1/playlists/"+live.Pid+"/source", map[string]any{
		"mode": "mirror", "intervalHours": 12,
	}), 200, "re-save live")
	if flipped.Mode != "mirror" || !flipped.Live ||
		flipped.IntervalHours == nil || *flipped.IntervalHours != 12 {
		t.Fatalf("re-saved live = %+v", flipped)
	}
	if flipped.Url == nil || *flipped.Url != src.playlistURL {
		t.Fatalf("re-saved live url = %v", flipped.Url)
	}
	if got := src.probeCount(); got != probes {
		t.Fatalf("a settings-only re-save probed the source %d times", got-probes)
	}
	// A live binding still needs its interval named.
	wantStatus(t, h.putJSON(t, "/api/v1/playlists/"+live.Pid+"/source", map[string]any{
		"mode": "mirror",
	}), 400, "a live re-save with no interval")

	// An explicit empty url named a source and named it badly, which is
	// the refusal it always was: reading it as a re-save would keep the
	// binding somebody was replacing and answer 200 for it.
	wantStatus(t, h.putJSON(t, "/api/v1/playlists/"+live.Pid+"/source", map[string]any{
		"mode": "mirror", "url": "", "intervalHours": 6,
	}), 400, "a bind with a blank url")
	if held := getSource(t, h, live.Pid); held.Url == nil || *held.Url != src.playlistURL {
		t.Fatalf("the refused bind moved the stored url: %+v", held.Url)
	}

	// With no binding under it, the form is a bind that named nothing.
	bare := createStaticPlaylist(t, h, "Resaved nothing")
	wantStatus(t, h.putJSON(t, "/api/v1/playlists/"+bare.Pid+"/source", map[string]any{
		"mode": "mirror",
	}), 400, "a settings-only body with no binding")
	// And Preview answers the same body the same way. The two are one
	// form on one sheet; a 404 here would be a sentence about a binding
	// the visitor is trying to create.
	wantStatus(t, h.postJSON(t, "/api/v1/playlists/"+bare.Pid+"/source/preview", map[string]any{
		"mode": "mirror",
	}), 400, "a settings-only preview with no binding")
	// No body at all is the other reading, and keeps its own answer.
	wantStatus(t, h.postJSON(t, "/api/v1/playlists/"+bare.Pid+"/source/preview", nil),
		404, "a bodyless preview with no binding")
}

// TestPlaylistSourceResaveClearsHealth pins what a settings-only save
// does to the binding's accounting: a suspended one is let run again -
// which is the whole point of correcting its settings - and a mode
// escalation takes the bind's grace period before the sweeper can act
// on it.
func TestPlaylistSourceResaveClearsHealth(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	src.setEntries(syncFixtureEntries(t, media, 1)...)
	h := syncHarness(t, src)
	ctx := context.Background()

	pl := createStaticPlaylist(t, h, "Suspended")
	decodeStatus[PlaylistSource](t, h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "append", "intervalHours": 24,
	}), 200, "bind live")

	// Suspended the way ten failures leave it, and stamped as attempted
	// a long time ago so the sweeper would take it the moment it could.
	row, err := h.store.PlaylistSourceFor(ctx, pl.Pid[3:])
	if err != nil {
		t.Fatal(err)
	}
	row.ConsecutiveFailures, row.Disabled = 10, true
	row.LastError = "the tube is down"
	row.LastAttemptNS = time.Now().Add(-48 * time.Hour).UnixNano()
	if err := h.store.PutPlaylistSource(ctx, row); err != nil {
		t.Fatal(err)
	}

	resaved := decodeStatus[PlaylistSource](t, h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"mode": "append", "intervalHours": 1,
	}), 200, "re-save the interval")
	if resaved.Disabled || resaved.ConsecutiveFailures != 0 || resaved.LastError != nil {
		t.Fatalf("a re-save left the health standing: %+v", resaved)
	}
	// The interval alone moved, so the next run is still measured from
	// the last real attempt rather than pushed out by the save.
	after, err := h.store.PlaylistSourceFor(ctx, pl.Pid[3:])
	if err != nil {
		t.Fatal(err)
	}
	if after.LastAttemptNS != row.LastAttemptNS {
		t.Fatal("an interval-only re-save moved the last-attempt stamp")
	}

	// A changed mode does move it: escalating to mirror-trash must not
	// put files in the trash before the next scheduled run.
	decodeStatus[PlaylistSource](t, h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"mode": "mirror-trash", "intervalHours": 1,
	}), 200, "escalate the mode")
	escalated, err := h.store.PlaylistSourceFor(ctx, pl.Pid[3:])
	if err != nil {
		t.Fatal(err)
	}
	if escalated.LastAttemptNS <= row.LastAttemptNS {
		t.Fatal("a mode escalation kept the old attempt stamp, so the sweeper can trash at once")
	}
}

// sourceEntryStates reads a binding's per-entry bookkeeping, which no
// endpoint answers: it is the thing a re-save must not throw away.
func sourceEntryStates(t *testing.T, h *harness, apiPlaylistPID string) map[string]string {
	t.Helper()
	states, err := h.store.PlaylistSourceEntryStates(context.Background(), apiPlaylistPID[3:])
	if err != nil {
		t.Fatalf("reading entry states: %v", err)
	}
	return states
}

// TestSessionCarriesEffectiveDelete pins the self view's delete field,
// which gates the client's mirror-trash affordance. Effective: an
// administrator reads true whatever their stored flag says.
func TestSessionCarriesEffectiveDelete(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	sessionDelete := func(token string) *bool {
		resp := get(t, h.ts, "/api/v1/auth/session", token)
		info := decode[SessionInfo](t, resp)
		if info.User == nil {
			t.Fatal("session reports no user")
		}
		return info.User.Delete
	}
	if got := sessionDelete(h.token); got == nil || !*got {
		t.Errorf("admin delete = %v, want true", got)
	}
	plain := podcastAccount(t, h, "delete-bystander", false)
	if got := sessionDelete(plain); got == nil || *got {
		t.Errorf("bystander delete = %v, want false", got)
	}
}

// TestPlaylistSyncLiveEndToEnd drives the whole live loop: downloads
// ride the review queue, entries attach once settled, mirror follows
// source order, a removed entry keeps its file, a returning entry
// re-attaches without a second download, a moved item self-heals by
// essence, and mirror-trash sends a removed entry's file to the trash.
func TestPlaylistSyncLiveEndToEnd(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	entries := syncFixtureEntries(t, media, 3)
	src.setEntries(entries...)
	h := syncHarness(t, src)
	ctx := context.Background()

	pl := createStaticPlaylist(t, h, "Mirror Me")
	resp := h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "append", "intervalHours": 6,
	})
	wantStatus(t, resp, 200, "bind")

	// A preview before anything ran: three downloads, nothing else.
	preview := decodeStatus[PlaylistSyncPreview](t, h.postJSON(t, "/api/v1/playlists/"+pl.Pid+"/source/preview", nil), 200, "preview")
	if preview.Entries != 3 || preview.WouldDownload != 3 || preview.WouldAdd != 0 {
		t.Fatalf("bind-time preview = %+v", preview)
	}
	// Binding alone downloaded nothing.
	if n := src.fetchCount(); n != 0 {
		t.Fatalf("bind fetched %d files", n)
	}

	// Run one downloads; the members attach on run two, once the
	// as-is imports settled the map.
	task := syncNow(t, h, pl.Pid)
	if task.State != "done" {
		t.Fatalf("first sync = %+v", task)
	}
	after := getSource(t, h, pl.Pid)
	if after.LastRun == nil || after.LastRun.Queued != 3 || after.LastRun.Added != 0 {
		t.Fatalf("first run counts = %+v", after.LastRun)
	}
	if src.fetchCount() != 3 {
		t.Fatalf("first sync fetched %d, want 3", src.fetchCount())
	}
	mint := decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server", h.token))
	task = syncNow(t, h, pl.Pid)
	if task.State != "done" {
		t.Fatalf("second sync = %+v", task)
	}
	members := playlistItems(t, h, h.token, pl.Pid)
	if len(members) != 3 {
		t.Fatalf("members after attach = %v", entryPids(members))
	}
	for i, e := range members {
		if e.Item.Title != entries[i].title {
			t.Fatalf("member %d = %q, want %q", i, e.Item.Title, entries[i].title)
		}
	}
	after = getSource(t, h, pl.Pid)
	if after.LastRun == nil || after.LastRun.Added != 3 {
		t.Fatalf("second run counts = %+v", after.LastRun)
	}
	if src.fetchCount() != 3 {
		t.Fatalf("attach run re-downloaded: %d fetches", src.fetchCount())
	}

	// The run that changed the playlist announced itself on the event
	// stream under the playlist's pid.
	page := decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server?since="+mint.NextSince, h.token))
	found := false
	for _, e := range page.Events {
		if e.Kind == "playlist-synced" && e.Pid != nil && *e.Pid == pl.Pid {
			found = true
		}
	}
	if !found {
		t.Fatal("no playlist-synced event on the stream")
	}

	// Mirror: membership and order follow the source.
	resp = h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "mirror", "intervalHours": 6,
	})
	wantStatus(t, resp, 200, "switch to mirror")
	src.setEntries(entries[2], entries[0], entries[1])
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("reorder sync = %+v", task)
	}
	members = playlistItems(t, h, h.token, pl.Pid)
	want := []string{entries[2].title, entries[0].title, entries[1].title}
	for i, e := range members {
		if e.Item.Title != want[i] {
			t.Fatalf("mirrored order[%d] = %q, want %q", i, e.Item.Title, want[i])
		}
	}
	trackPid := members[0].Item.Pid // entries[2]'s item

	// A removed entry detaches; its file stays in the library.
	src.setEntries(entries[0], entries[1])
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("removal sync = %+v", task)
	}
	members = playlistItems(t, h, h.token, pl.Pid)
	if len(members) != 2 {
		t.Fatalf("members after removal = %v", entryPids(members))
	}
	items := h.items(t, "")
	kept := false
	for _, it := range items.Items {
		if it.Pid == trackPid {
			kept = true
		}
	}
	if !kept {
		t.Fatal("mirror removal took the file with it")
	}

	// The entry returns: re-attached from the map, no second download.
	before := src.fetchCount()
	src.setEntries(entries[0], entries[1], entries[2])
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("re-add sync = %+v", task)
	}
	members = playlistItems(t, h, h.token, pl.Pid)
	if len(members) != 3 || members[2].Item.Pid != trackPid {
		t.Fatalf("re-add members = %v", entryPids(members))
	}
	if src.fetchCount() != before {
		t.Fatalf("re-add downloaded again: %d fetches, was %d", src.fetchCount(), before)
	}

	// Self-heal: point the map at a pid that does not exist, keeping
	// the essence, the way a merge moves an item. The sync re-resolves
	// through the portable-ref ladder instead of re-downloading.
	refs := decode[PortablePlaylist](t, get(t, h.ts, "/api/v1/playlists/"+pl.Pid+"/portable", h.token))
	essence := ""
	for _, r := range refs.Refs {
		if r.Title == entries[2].title && r.Essence != nil {
			essence = *r.Essence
		}
	}
	if essence == "" {
		t.Fatal("no essence in the portable export")
	}
	if err := h.store.SetPlaylistSourceMapItem(ctx, "youtube", entries[2].id,
		"tr-01AAAAAAAAAAAAAAAAAAAAAAAAAA", essence, time.Now().UnixNano()); err != nil {
		t.Fatal(err)
	}
	before = src.fetchCount()
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("heal sync = %+v", task)
	}
	if src.fetchCount() != before {
		t.Fatalf("heal downloaded again: %d fetches, was %d", src.fetchCount(), before)
	}
	members = playlistItems(t, h, h.token, pl.Pid)
	if len(members) != 3 || members[2].Item.Pid != trackPid {
		t.Fatalf("healed members = %v", entryPids(members))
	}
	m, err := h.store.PlaylistSourceMapFor(ctx, "youtube", []string{entries[2].id})
	if err != nil {
		t.Fatal(err)
	}
	// The map stores bare catalog pids; the API layer prefixes.
	if got := "tr-" + m[entries[2].id].ItemPID; got != trackPid {
		t.Fatalf("healed map row = %+v, want item %s", m[entries[2].id], trackPid)
	}

	// mirror-trash: a removed entry's file goes to the recoverable
	// trash - membership first, then the trash, so the replace guard
	// never fires - and only a file this sync's own download brought
	// in. entries[1] is still "attached" from its original download;
	// entries[2] left under plain mirror and re-attached from the map,
	// which makes it "linked" - present because of the sync, but not
	// the sync's file to take.
	resp = h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "mirror-trash", "intervalHours": 6,
	})
	wantStatus(t, resp, 200, "switch to mirror-trash")
	ownedPid := ""
	for _, m := range members {
		if m.Item.Title == entries[1].title {
			ownedPid = m.Item.Pid
		}
	}
	src.setEntries(entries[0])
	task = syncNow(t, h, pl.Pid)
	if task.State != "done" {
		t.Fatalf("trash sync = %+v", task)
	}
	after = getSource(t, h, pl.Pid)
	if after.LastRun == nil || after.LastRun.Trashed != 1 || after.LastRun.Removed != 2 {
		t.Fatalf("trash run counts = %+v", after.LastRun)
	}
	members = playlistItems(t, h, h.token, pl.Pid)
	if len(members) != 1 {
		t.Fatalf("members after trash = %v", entryPids(members))
	}
	items = h.items(t, "")
	linkedListed := false
	for _, it := range items.Items {
		if it.Pid == ownedPid {
			t.Fatal("the sync-owned file was not trashed")
		}
		if it.Pid == trackPid {
			linkedListed = true
		}
	}
	if !linkedListed {
		t.Fatal("the linked file was trashed; only the sync's own downloads may be")
	}
}

// TestPlaylistSyncAppendKeepsHandEdits pins append mode's contract: a
// member the owner removed by hand is tombstoned, never re-added, and
// manual additions survive every run.
func TestPlaylistSyncAppendKeepsHandEdits(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	entries := syncFixtureEntries(t, media, 2)
	src.setEntries(entries...)
	h := syncHarness(t, src)

	// A manual member from the fixture library seeds the playlist.
	seed := h.items(t, "").Items[0].Pid
	pl := createStaticPlaylist(t, h, "Curated", seed)
	resp := h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "append", "intervalHours": 6,
	})
	wantStatus(t, resp, 200, "bind")

	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("download sync = %+v", task)
	}
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("attach sync = %+v", task)
	}
	members := playlistItems(t, h, h.token, pl.Pid)
	if len(members) != 3 || members[0].Item.Pid != seed {
		t.Fatalf("members after attach = %v", entryPids(members))
	}
	syncedPid := members[1].Item.Pid

	// The owner removes the first synced member by hand.
	base := getPlaylistUpdatedAt(t, h, pl.Pid)
	resp = h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/items", map[string]any{
		"itemPids": []string{seed, members[2].Item.Pid}, "baseUpdatedAt": base,
	})
	wantStatus(t, resp, 204, "hand removal")

	// The next run tombstones it instead of re-adding, downloads
	// nothing, and leaves the manual member alone.
	before := src.fetchCount()
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("tombstone sync = %+v", task)
	}
	members = playlistItems(t, h, h.token, pl.Pid)
	if len(members) != 2 || members[0].Item.Pid != seed {
		t.Fatalf("members after tombstone sync = %v", entryPids(members))
	}
	for _, m := range members {
		if m.Item.Pid == syncedPid {
			t.Fatal("append re-added a hand-removed member")
		}
	}
	if src.fetchCount() != before {
		t.Fatal("append re-downloaded a hand-removed member")
	}
	states, err := h.store.PlaylistSourceEntryStates(context.Background(), rawPlaylistPID(pl.Pid))
	if err != nil {
		t.Fatal(err)
	}
	if states[entries[0].id] != "tombstoned" {
		t.Fatalf("entry states = %v", states)
	}
}

// TestPlaylistSyncDetachesOutOfBandTrash pins the trashed-member arm:
// a member the owner trashed through the delete surface would wedge
// every replace behind the trashed-member guard, so the reconciler
// detaches it first and never re-downloads it.
func TestPlaylistSyncDetachesOutOfBandTrash(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	entries := syncFixtureEntries(t, media, 2)
	src.setEntries(entries...)
	h := syncHarness(t, src)

	pl := createStaticPlaylist(t, h, "Trailed")
	resp := h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "mirror", "intervalHours": 6,
	})
	wantStatus(t, resp, 200, "bind")
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("download sync = %+v", task)
	}
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("attach sync = %+v", task)
	}
	members := playlistItems(t, h, h.token, pl.Pid)
	if len(members) != 2 {
		t.Fatalf("members = %v", entryPids(members))
	}
	trashed := members[0].Item.Pid

	// The owner trashes a synced member out of band.
	resp = h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{trashed}, "mode": "trash",
	})
	wantStatus(t, resp, 200, "trash member")

	// The next run detaches it and does not fetch it again; the entry
	// still lists at the source, and a trashed item must read as "the
	// owner removed this", never as "vanished, download it again".
	before := src.fetchCount()
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("post-trash sync = %+v", task)
	}
	members = playlistItems(t, h, h.token, pl.Pid)
	if len(members) != 1 || members[0].Item.Pid == trashed {
		t.Fatalf("members after out-of-band trash = %v", entryPids(members))
	}
	if src.fetchCount() != before {
		t.Fatal("a trashed member was re-downloaded")
	}
}

// TestPlaylistSyncBacksOffAConcurrentGuard pins the conflict arm: a
// replace the guard refuses (here, a member episode of a show the
// owner has since unsubscribed) backs the run off cleanly - task done,
// membership untouched, no failure charged to the source.
func TestPlaylistSyncBacksOffAConcurrentGuard(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 2)

	// A second subscriber keeps the show's episodes in the catalog
	// after the owner unsubscribes.
	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "keeper", "password": testPassword})
	wantStatus(t, resp, 201, "second account")
	keeper := loginAs(t, h.ts, "keeper", testPassword)
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()}), 201, "subscribe")
	resp = reqAs(t, h, "POST", "/api/v1/podcasts", keeper.Token, map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 200 && resp.StatusCode != 201 {
		t.Fatalf("keeper subscribe status = %d", resp.StatusCode)
	}
	resp.Body.Close()

	episodes := decode[ItemPage](t, get(t, h.ts, "/api/v1/library/items?mediaType=podcast", h.token))
	if len(episodes.Items) == 0 {
		t.Fatal("no episodes landed")
	}
	pl := createStaticPlaylist(t, h, "Mixed Bag", episodes.Items[0].Pid)

	// A matched binding whose sync would rewrite membership.
	tracks := h.items(t, "")
	first := tracks.Items[0]
	if first.Artist == nil {
		t.Fatal("fixture item carries no artist")
	}
	resp = h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"source": "text", "mode": "mirror",
		"payload": fmt.Sprintf("%s - %s", *first.Artist, first.Title),
	})
	wantStatus(t, resp, 200, "bind matched")

	// The owner unsubscribes; the stored episode member is now behind
	// the subscription guard.
	req, _ := http.NewRequest("DELETE", h.ts.URL+"/api/v1/podcasts/"+sub.Show.Pid, nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	delResp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	delResp.Body.Close()

	task := syncNow(t, h, pl.Pid)
	if task.State != "done" {
		t.Fatalf("guarded sync = %+v", task)
	}
	// The owner's own listing hides the episode now; re-subscribing
	// shows the stored membership the backoff left untouched.
	resubscribe(t, h, feed.feedURL())
	members := playlistItems(t, h, h.token, pl.Pid)
	if len(members) != 1 || members[0].Item.Pid != episodes.Items[0].Pid {
		t.Fatalf("members after backoff = %v", entryPids(members))
	}
	after := getSource(t, h, pl.Pid)
	if after.ConsecutiveFailures != 0 || after.Disabled {
		t.Fatalf("backoff charged the source: %+v", after)
	}
	if after.LastSyncedAt != nil {
		t.Fatalf("backoff recorded a success: %+v", after)
	}
}

// TestPlaylistSyncMatchedSource covers the on-demand half: a streaming
// export binds, the preview reports the misses, and a sync attaches
// what the resolve ladder matched, downloading nothing.
func TestPlaylistSyncMatchedSource(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	items := h.items(t, "")
	first := items.Items[0]

	pl := createStaticPlaylist(t, h, "From Spotify")
	if first.Artist == nil {
		t.Fatal("fixture item carries no artist")
	}
	payload := fmt.Sprintf("%s - %s\nNobody Here - Never Recorded", *first.Artist, first.Title)
	resp := h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"source": "text", "payload": payload, "mode": "append",
	})
	bound := decodeStatus[PlaylistSource](t, resp, 200, "bind matched")
	if bound.Live || bound.Source != "text" || bound.RefCount == nil || *bound.RefCount != 2 {
		t.Fatalf("matched binding = %+v", bound)
	}

	preview := decodeStatus[PlaylistSyncPreview](t, h.postJSON(t, "/api/v1/playlists/"+pl.Pid+"/source/preview", nil), 200, "preview")
	if preview.Entries != 2 || preview.WouldAdd != 1 || preview.Missing != 1 || preview.WouldDownload != 0 {
		t.Fatalf("matched preview = %+v", preview)
	}
	if preview.Misses == nil || len(*preview.Misses) != 1 || (*preview.Misses)[0].Title != "Never Recorded" {
		t.Fatalf("misses = %+v", preview.Misses)
	}

	task := syncNow(t, h, pl.Pid)
	if task.State != "done" {
		t.Fatalf("matched sync = %+v", task)
	}
	members := playlistItems(t, h, h.token, pl.Pid)
	if len(members) != 1 || members[0].Item.Pid != first.Pid {
		t.Fatalf("matched members = %v", entryPids(members))
	}
	after := getSource(t, h, pl.Pid)
	if after.LastRun == nil || after.LastRun.Added != 1 || after.LastRun.Missing != 1 {
		t.Fatalf("matched run counts = %+v", after.LastRun)
	}
}

// TestPlaylistSyncFailureAccounting pins the feedwork shape: a failing
// run records its error, the tenth consecutive failure suspends the
// schedule and announces it once, and a successful manual sync is the
// recovery path.
func TestPlaylistSyncFailureAccounting(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	src.setEntries(syncFixtureEntries(t, media, 1)...)
	h := syncHarness(t, src)
	ctx := context.Background()

	pl := createStaticPlaylist(t, h, "Flaky")
	resp := h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "append", "intervalHours": 6,
	})
	wantStatus(t, resp, 200, "bind")

	// Nine failures stand recorded; the failing run ahead is the edge.
	for i := 0; i < 9; i++ {
		if _, err := h.store.RecordPlaylistSyncFailure(ctx, rawPlaylistPID(pl.Pid), "prior", time.Now().UnixNano(), 100); err != nil {
			t.Fatal(err)
		}
	}
	src.mu.Lock()
	src.enumerateErr = errors.New("the tube is down")
	src.mu.Unlock()
	mint := decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server", h.token))
	task := syncNow(t, h, pl.Pid)
	if task.State == "done" {
		t.Fatalf("failing sync finished clean: %+v", task)
	}
	after := getSource(t, h, pl.Pid)
	if !after.Disabled || after.ConsecutiveFailures != 10 {
		t.Fatalf("after tenth failure = %+v", after)
	}
	if after.LastError == nil || *after.LastError == "" {
		t.Fatal("no lastError recorded")
	}
	page := decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server?since="+mint.NextSince, h.token))
	found := false
	for _, e := range page.Events {
		if e.Kind == "playlist-synced" && e.Pid != nil && *e.Pid == pl.Pid {
			found = true
		}
	}
	if !found {
		t.Fatal("the disable edge did not announce")
	}

	// Recovery is a successful run resetting the accounting - pinned at
	// the store level (TestPlaylistSyncFailureAccountingDisablesOnTheEdge);
	// the failed task itself stays leased for the worker's own retry
	// backoff, so re-running it here would mean waiting the lease out.
}

// TestPlaylistSyncRefusesUnsafeListings pins the two listings a mirror
// must never act on: a truncated one (the tail it cannot see would be
// removed - and trashed - as if the source dropped it) and a clean
// empty answer on a binding with history (one bad page would empty the
// playlist). Append only ever adds, so it proceeds either way.
func TestPlaylistSyncRefusesUnsafeListings(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	entries := syncFixtureEntries(t, media, 2)
	src.setEntries(entries...)
	h := syncHarness(t, src)

	pl := createStaticPlaylist(t, h, "Guarded")
	resp := h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "mirror", "intervalHours": 6,
	})
	wantStatus(t, resp, 200, "bind")
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("download sync = %+v", task)
	}
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("attach sync = %+v", task)
	}
	if got := playlistItems(t, h, h.token, pl.Pid); len(got) != 2 {
		t.Fatalf("members before the guards = %v", entryPids(got))
	}

	// A truncated listing refuses under mirror; membership stands.
	src.mu.Lock()
	src.truncate = true
	src.mu.Unlock()
	if task := syncNow(t, h, pl.Pid); task.State == "done" {
		t.Fatalf("a truncated mirror sync finished clean: %+v", task)
	}
	if got := playlistItems(t, h, h.token, pl.Pid); len(got) != 2 {
		t.Fatalf("truncated listing moved membership: %v", entryPids(got))
	}
	after := getSource(t, h, pl.Pid)
	if after.LastError == nil || *after.LastError == "" {
		t.Fatal("the truncation refusal recorded no error")
	}

	// An empty answer on a binding with history refuses too.
	src.mu.Lock()
	src.truncate = false
	src.entries = nil
	src.mu.Unlock()
	if task := syncNow(t, h, pl.Pid); task.State == "done" {
		t.Fatalf("an empty-answer mirror sync finished clean: %+v", task)
	}
	if got := playlistItems(t, h, h.token, pl.Pid); len(got) != 2 {
		t.Fatalf("empty answer emptied the playlist: %v", entryPids(got))
	}
	items := h.items(t, "")
	kept := 0
	for _, it := range items.Items {
		for _, e := range entries {
			if it.Title == e.title {
				kept++
			}
		}
	}
	if kept != 2 {
		t.Fatalf("the guards let files reach the trash: %d of 2 listed", kept)
	}
}

// TestPlaylistSyncNeverTrashesBorrowedFiles pins the ownership rule
// across bindings: playlist A's sync downloads the files, playlist B
// mirrors-trash over the same source and attaches them through the
// shared map as "linked" - and when the source empties out from under
// B, B removes its members but takes no files with it. It also pins
// the settle nudge: A's downloads settling re-arms B's schedule.
func TestPlaylistSyncNeverTrashesBorrowedFiles(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	entries := syncFixtureEntries(t, media, 2)
	src.setEntries(entries...)
	h := syncHarness(t, src)
	ctx := context.Background()

	a := createStaticPlaylist(t, h, "Downloader")
	b := createStaticPlaylist(t, h, "Borrower")
	for _, pid := range []string{a.Pid, b.Pid} {
		mode := "append"
		if pid == b.Pid {
			mode = "mirror-trash"
		}
		resp := h.putJSON(t, "/api/v1/playlists/"+pid+"/source", map[string]any{
			"url": src.playlistURL, "mode": mode, "intervalHours": 6,
		})
		wantStatus(t, resp, 200, "bind "+mode)
	}

	// A downloads; the settle inside its run re-arms B's schedule.
	if task := syncNow(t, h, a.Pid); task.State != "done" {
		t.Fatalf("A's download sync = %+v", task)
	}
	bRow, err := h.store.PlaylistSourceFor(ctx, rawPlaylistPID(b.Pid))
	if err != nil {
		t.Fatal(err)
	}
	if bRow.LastAttemptNS != 0 {
		t.Fatalf("a settled download did not re-arm the sibling binding: %+v", bRow.LastAttemptNS)
	}

	// B attaches the same items without downloading a byte of its own.
	before := src.fetchCount()
	if task := syncNow(t, h, b.Pid); task.State != "done" {
		t.Fatalf("B's attach sync = %+v", task)
	}
	if src.fetchCount() != before {
		t.Fatalf("B downloaded what the map already held: %d fetches, was %d", src.fetchCount(), before)
	}
	members := playlistItems(t, h, h.token, b.Pid)
	if len(members) != 2 {
		t.Fatalf("B's members = %v", entryPids(members))
	}

	// The source empties for B... but not really: the guard refuses an
	// empty answer, so shrink to one instead and watch the removed
	// entry's file survive.
	src.setEntries(entries[0])
	if task := syncNow(t, h, b.Pid); task.State != "done" {
		t.Fatalf("B's removal sync = %+v", task)
	}
	after := getSource(t, h, b.Pid)
	if after.LastRun == nil || after.LastRun.Trashed != 0 || after.LastRun.Removed != 1 {
		t.Fatalf("B's removal counts = %+v", after.LastRun)
	}
	items := h.items(t, "")
	found := false
	for _, it := range items.Items {
		if it.Title == entries[1].title {
			found = true
		}
	}
	if !found {
		t.Fatal("mirror-trash took a borrowed file")
	}
}

// TestPlaylistSyncHonorsAReviewDiscard pins the rejection loop: a
// person discarding a sync download in review tombstones the entry for
// the playlist, so the next runs neither re-download nor refill the
// queue with the same decision.
func TestPlaylistSyncHonorsAReviewDiscard(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	entries := syncFixtureEntries(t, media, 1)
	src.setEntries(entries...)
	// Identification stays on, so the download waits in review where a
	// person can throw it out.
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{releases: obviousRelease()}
		cfg.SourceProviders = append(cfg.SourceProviders, src)
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
		cfg.AllowPrivateFeedHosts = true
	})
	ctx := context.Background()

	pl := createStaticPlaylist(t, h, "Rejected")
	resp := h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "mirror", "intervalHours": 6,
	})
	wantStatus(t, resp, 200, "bind")
	task := syncNow(t, h, pl.Pid)
	if task.State != "done" || task.ResultPids == nil || len(*task.ResultPids) != 1 {
		t.Fatalf("download sync = %+v", task)
	}
	drainMatches(t, h)
	entryID := (*task.ResultPids)[0]
	resp = h.postJSON(t, "/api/v1/review/queue/"+entryID+"/decide", map[string]any{"action": "discard"})
	wantStatus(t, resp, 200, "discard the download")

	// The next run tombstones the entry instead of downloading again...
	before := src.fetchCount()
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("post-discard sync = %+v", task)
	}
	states, err := h.store.PlaylistSourceEntryStates(ctx, rawPlaylistPID(pl.Pid))
	if err != nil {
		t.Fatal(err)
	}
	if states[entries[0].id] != "tombstoned" {
		t.Fatalf("discard did not tombstone: %v", states)
	}
	// ...and the one after respects the tombstone.
	if task := syncNow(t, h, pl.Pid); task.State != "done" {
		t.Fatalf("tombstoned sync = %+v", task)
	}
	if src.fetchCount() != before {
		t.Fatalf("a discarded download was fetched again: %d, was %d", src.fetchCount(), before)
	}
}

// TestPlaylistSyncRechecksTheDeleteRight pins that revoking Delete
// stops an existing mirror-trash binding from trashing on its next
// run, scheduled or manual.
func TestPlaylistSyncRechecksTheDeleteRight(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	entries := syncFixtureEntries(t, media, 2)
	src.setEntries(entries...)
	h := syncHarness(t, src)

	// A plain owner holding upload and delete, minted by the admin.
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "trash-holder", "password": testPassword, "uploadEnabled": true,
		"permissions": map[string]any{
			"download": true, "delete": true, "explicitContent": true,
			"sharedOutputs": true, "managePodcasts": false,
		},
	})
	wantStatus(t, resp, 201, "mint the owner")
	owner := loginAs(t, h.ts, "trash-holder", testPassword)
	resp = reqAs(t, h, "PUT", "/api/v1/users/me/prefs", owner.Token, map[string]any{"identifyOptOut": true})
	wantStatus(t, resp, 200, "owner declines identify")

	created := decodeStatus[Playlist](t, reqAs(t, h, "POST", "/api/v1/playlists", owner.Token,
		map[string]any{"name": "Revocable", "kind": "static"}), 201, "owner playlist")
	resp = reqAs(t, h, "PUT", "/api/v1/playlists/"+created.Pid+"/source", owner.Token, map[string]any{
		"url": src.playlistURL, "mode": "mirror-trash", "intervalHours": 6,
	})
	wantStatus(t, resp, 200, "bind mirror-trash with the right")

	syncAs := func(what string) ToolTask {
		t.Helper()
		task := decodeStatus[ToolTask](t, reqAs(t, h, "POST", "/api/v1/playlists/"+created.Pid+"/source/sync", owner.Token, nil), 202, what)
		drainTools(t, h)
		return decode[ToolTask](t, reqAs(t, h, "GET", "/api/v1/tools/tasks/"+task.Id, owner.Token, nil))
	}
	if task := syncAs("download sync"); task.State != "done" {
		t.Fatalf("download sync = %+v", task)
	}
	if task := syncAs("attach sync"); task.State != "done" {
		t.Fatalf("attach sync = %+v", task)
	}
	if got := playlistItems(t, h, owner.Token, created.Pid); len(got) != 2 {
		t.Fatalf("members before revocation = %v", entryPids(got))
	}

	// The admin revokes Delete; the standing binding must stop trashing.
	ownerID := decodeStatus[SessionInfo](t, reqAs(t, h, "GET", "/api/v1/auth/session", owner.Token, nil), 200, "owner session").User.Id
	resp = reqAs(t, h, "PATCH", "/api/v1/users/"+ownerID, h.token, map[string]any{
		"permissions": map[string]any{
			"download": true, "delete": false, "explicitContent": true,
			"sharedOutputs": true, "managePodcasts": false,
		},
	})
	wantStatus(t, resp, 200, "revoke delete")

	src.setEntries(entries[0])
	task := syncAs("revoked sync")
	if task.State != "failed" {
		t.Fatalf("revoked-right sync = %+v", task)
	}
	items := h.items(t, "")
	found := false
	for _, it := range items.Items {
		if it.Title == entries[1].title {
			found = true
		}
	}
	if !found {
		t.Fatal("a revoked delete right still trashed a file")
	}
}

// TestPlaylistSyncPreviewAnswers400ForABadURL pins preview as the
// validate-before-save affordance: a URL no provider enumerates is the
// caller's to fix, not a 500.
func TestPlaylistSyncPreviewAnswers400ForABadURL(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	src.setEntries(syncFixtureEntries(t, media, 1)...)
	h := syncHarness(t, src)

	pl := createStaticPlaylist(t, h, "Probed")
	resp := h.postJSON(t, "/api/v1/playlists/"+pl.Pid+"/source/preview", map[string]any{
		"url": "https://tube.example/not-a-playlist", "mode": "mirror", "intervalHours": 6,
	})
	wantStatus(t, resp, 400, "preview of a URL nothing enumerates")
}

// TestUnbindHandsTheSourceCoverBack pins that removing the binding
// releases a source-origin cover to the mosaic; nothing would be left
// to refresh it otherwise.
func TestUnbindHandsTheSourceCoverBack(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeSyncSource{playlistURL: "https://tube.example/playlist?list=PLsync", title: "Sync Tapes"}
	src.setEntries(syncFixtureEntries(t, media, 1)...)
	h := syncHarness(t, src)
	ctx := context.Background()

	pl := createStaticPlaylist(t, h, "Covered")
	resp := h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/source", map[string]any{
		"url": src.playlistURL, "mode": "append", "intervalHours": 6,
	})
	wantStatus(t, resp, 200, "bind")
	// The thumbnail host is unreachable in tests, so the stored state
	// is seeded the way a successful fetch would have left it.
	if err := h.store.PutPlaylistCover(ctx, db.PlaylistCover{
		PlaylistPID: rawPlaylistPID(pl.Pid), Origin: db.CoverSource,
		Fingerprint: "https://img.example/vid-1.jpg", UpdatedAtNS: time.Now().UnixNano(),
	}); err != nil {
		t.Fatal(err)
	}

	resp = reqAs(t, h, "DELETE", "/api/v1/playlists/"+pl.Pid+"/source", h.token, nil)
	wantStatus(t, resp, 204, "unbind")
	// The handback regenerates the mosaic, which records itself; what
	// must be gone is the source origin, not the row.
	if rec, err := h.store.PlaylistCoverFor(ctx, rawPlaylistPID(pl.Pid)); err == nil && rec.Origin == db.CoverSource {
		t.Fatal("the source cover state survived the unbind")
	}
}

// getPlaylistUpdatedAt reads the detail's updatedAt in the wire
// spelling the replace guard compares against.
func getPlaylistUpdatedAt(t *testing.T, h *harness, pid string) string {
	t.Helper()
	det := decode[Playlist](t, get(t, h.ts, "/api/v1/playlists/"+pid, h.token))
	return det.UpdatedAt.UTC().Format(time.RFC3339Nano)
}

// rawPlaylistPID strips the API prefix for store-level reads.
func rawPlaylistPID(apiPid string) string {
	return apiPid[len("pl-"):]
}
