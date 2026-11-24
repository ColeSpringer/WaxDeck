package service

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"
	"github.com/colespringer/waxdeck/fixtures"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// The identifiers the fixture's one identified track carries.
const (
	catalogFixtureISRC = "USRC17607839"
	catalogFixtureMBID = "b9b3d3f9-1e2b-4a1e-9a4a-1a2b3c4d5e6f"
)

// newCatalogFixture is a real Library over a small scanned catalog of
// tagged tracks, plus an admin context: enough for the import resolve
// ladder and the discovery metadata fallback.
func newCatalogFixture(t *testing.T) (context.Context, *Library, *UserCtx) {
	t.Helper()
	return newCatalogFixtureWith(t, catalogFixtureOptions{})
}

// catalogFixtureOptions widens the fixture: more files beside the four
// tracks, and the config switches a test needs.
type catalogFixtureOptions struct {
	extra            func(t *testing.T, libDir string)
	workerLocalPaths bool
	// logs receives the service's log; nil discards it.
	logs io.Writer
	// sources is Config.SourceProviders.
	sources []source.Provider
	// enrichers is Config.EnrichmentProviders.
	enrichers []enrich.Provider
	// podcasts gives the library an episode root, so a test can subscribe.
	podcasts bool
}

func newCatalogFixtureWith(t *testing.T, opts catalogFixtureOptions) (context.Context, *Library, *UserCtx) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	if opts.logs != nil {
		// Debug too: a test reading the log checks what was not said.
		log = slog.New(slog.NewTextHandler(opts.logs, &slog.HandlerOptions{Level: slog.LevelDebug}))
	}

	track := func(name, title, artist, genre string, d time.Duration) fixtures.Spec {
		return fixtures.Spec{
			Name:     name,
			Codec:    fixtures.CodecFLAC,
			Duration: d,
			Tags: map[string]string{
				"TITLE":  title,
				"ARTIST": artist,
				"ALBUM":  "Signal Garden",
				"GENRE":  genre,
			},
		}
	}
	// One track carries the recording identifiers, the way a matched
	// library does and a scanned one mostly does not: the read surfaces
	// need both shapes in the same catalog to tell "absent" from
	// "never read".
	identified := func(spec fixtures.Spec) fixtures.Spec {
		spec.Tags["ISRC"] = catalogFixtureISRC
		spec.Tags["MUSICBRAINZ_TRACKID"] = catalogFixtureMBID
		return spec
	}
	libDir := t.TempDir()
	if _, err := fixtures.Generate(libDir,
		track("amber", "Amber Waves", "Test Ensemble", "Ambient", 2*time.Second),
		track("basalt", "Basalt Steps", "Test Ensemble", "Ambient", 2500*time.Millisecond),
		track("cobalt", "Cobalt Sky", "Test Ensemble", "Ambient", 3*time.Second),
		identified(track("delta", "Delta Groove", "Brass Nine", "Jazz", 3500*time.Millisecond)),
	); err != nil {
		t.Fatalf("generating fixtures: %v", err)
	}
	if opts.extra != nil {
		opts.extra(t, libDir)
	}

	dataDir := t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	cfg := Config{
		DataDir:             dataDir,
		Roots:               []Root{{Name: "lib", Path: libDir}},
		Logger:              log,
		WorkerLocalPaths:    opts.workerLocalPaths,
		SourceProviders:     opts.sources,
		EnrichmentProviders: opts.enrichers,
	}
	if opts.podcasts {
		cfg.PodcastDir = t.TempDir()
		cfg.PodcastRootName = "podcasts"
	}
	svc, err := Open(ctx, cfg, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})
	scan, err := svc.lib.Scan(ctx, waxbin.ScanRequest{})
	if err != nil {
		t.Fatalf("scanning fixture library: %v", err)
	}
	// Before any account exists, so the scan's job news reaches nobody
	// instead of landing in whichever test window the follower is late for.
	jobFollowerSettled(t, svc, scan.JobPID)

	acct, err := svc.Identity.CreateAccount(ctx, AccountCreate{
		Username: "admin", Password: "correct-horse", Roles: []string{"admin"},
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.Grants.UserCtxFor(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return ctx, svc, uc
}

// jobFollowerSettled waits until the job follower has read pid's job and
// announced what it found. The follower takes a wake only between rounds,
// so once the wake sent after handing it the job is taken, the round that
// read the job is over. It does not wait for an end the follower hands to
// Jobs.settleLater (a job with an origin row, or an enrich, set-kind or
// remove-root one), which may still be running.
func jobFollowerSettled(t *testing.T, svc *Library, pid model.PID) {
	t.Helper()
	svc.Jobs.followJob(pid)
	select {
	case svc.Jobs.jobWake <- struct{}{}:
	case <-time.After(10 * time.Second):
		t.Fatal("the job follower never took a wake")
	}
	waitFor(t, func() bool { return len(svc.Jobs.jobWake) == 0 }, "the job follower finishing its round")
}

func TestImportStreamingPlaylistTextDescriptive(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	payload := "# exported list\n" +
		"Test Ensemble - Amber Waves\n" +
		"Test Ensemble \u2013 Basalt Steps\n" +
		"Test Ensemble - Never Recorded\n" +
		"Delta Groove\n"
	out, err := svc.Playlists.ImportStreamingPlaylist(ctx, uc, PlaylistImportInput{
		Source:  "text",
		Name:    "Road Tape",
		Payload: payload,
	})
	if err != nil {
		t.Fatal(err)
	}
	if out.Requested != 4 || out.Resolved != 2 {
		t.Fatalf("outcome = %+v, want 2 of 4 resolved", out)
	}
	if out.Rungs.Descriptive != 2 || out.Rungs.Essence != 0 || out.Rungs.StrongID != 0 || out.Rungs.Fingerprint != 0 {
		t.Fatalf("rungs = %+v, want both matches on the descriptive rung", out.Rungs)
	}
	// The report names what stayed missing: the unknown title, and the
	// bare-title line the descriptive rung cannot anchor without an
	// artist.
	if len(out.Missing) != 2 {
		t.Fatalf("missing = %+v, want 2 entries", out.Missing)
	}
	if out.Missing[0].Artist != "Test Ensemble" || out.Missing[0].Title != "Never Recorded" {
		t.Fatalf("first miss = %+v", out.Missing[0])
	}
	if out.Missing[1].Artist != "" || out.Missing[1].Title != "Delta Groove" {
		t.Fatalf("second miss = %+v", out.Missing[1])
	}
	if out.Name != "Road Tape" || out.PlaylistPID == "" {
		t.Fatalf("outcome = %+v, want a created playlist named Road Tape", out)
	}

	// The playlist really exists and carries the matches in export order.
	pl, err := svc.Playlists.ByPID(ctx, uc, out.PlaylistPID)
	if err != nil {
		t.Fatal(err)
	}
	if pl.Name != "Road Tape" {
		t.Fatalf("playlist name = %q", pl.Name)
	}
	page, err := svc.Playlists.Items(ctx, uc, out.PlaylistPID, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Entries) != 2 ||
		page.Entries[0].Item.Title != "Amber Waves" ||
		page.Entries[1].Item.Title != "Basalt Steps" {
		t.Fatalf("playlist entries = %+v, want Amber Waves then Basalt Steps", page.Entries)
	}

	// Nothing resolved means no playlist at all, not an empty one.
	none, err := svc.Playlists.ImportStreamingPlaylist(ctx, uc, PlaylistImportInput{
		Source:  "text",
		Payload: "Nobody - Nothing At All\n",
	})
	if err != nil {
		t.Fatal(err)
	}
	if none.Resolved != 0 || none.PlaylistPID != "" || len(none.Missing) != 1 {
		t.Fatalf("all-miss outcome = %+v, want no playlist", none)
	}
}

func TestSimilarTracksForMetadataFallback(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	// Find the seed by title through the import resolver itself.
	seedOut, err := svc.Playlists.ImportStreamingPlaylist(ctx, uc, PlaylistImportInput{
		Source:  "text",
		Payload: "Test Ensemble - Amber Waves\n",
	})
	if err != nil || seedOut.Resolved != 1 {
		t.Fatalf("resolving the seed = (%+v, %v)", seedOut, err)
	}
	page, err := svc.Playlists.Items(ctx, uc, seedOut.PlaylistPID, "", 1)
	if err != nil || len(page.Entries) != 1 {
		t.Fatalf("seed lookup = (%+v, %v)", page, err)
	}
	seedPID := page.Entries[0].Item.PID

	// No worker has ever posted embeddings, so the sonic engine is
	// empty and the answer must come from the metadata fallback.
	res, err := svc.Similarity.SimilarTracksFor(ctx, uc, seedPID, 10)
	if err != nil {
		t.Fatal(err)
	}
	if res.Basis != BasisMetadata {
		t.Fatalf("basis = %q, want %q", res.Basis, BasisMetadata)
	}
	if len(res.Items) == 0 {
		t.Fatal("metadata fallback returned nothing")
	}
	known := map[string]bool{"Basalt Steps": true, "Cobalt Sky": true, "Delta Groove": true}
	for _, it := range res.Items {
		if it.PID == seedPID {
			t.Fatal("the seed track appeared in its own similar list")
		}
		if !known[it.Title] {
			t.Fatalf("unexpected item %+v", it)
		}
	}
}

func TestImportRetriesMissesWithTrimmedArtist(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	// An export whose artist cells join every credit: the full cell
	// misses the descriptive rung, and the primary-credit retry lands
	// it. The unknown title stays missing with its cell intact.
	payload := "Test Ensemble, Guest Voice - Amber Waves\n" +
		"Test Ensemble feat. Guest Voice - Basalt Steps\n" +
		"Somebody, Else - Never Recorded\n"
	out, err := svc.Playlists.ImportStreamingPlaylist(ctx, uc, PlaylistImportInput{
		Source:  "text",
		Name:    "Joined Credits",
		Payload: payload,
	})
	if err != nil {
		t.Fatal(err)
	}
	if out.Requested != 3 || out.Resolved != 2 {
		t.Fatalf("outcome = %+v, want the two joined-credit rows resolved", out)
	}
	if len(out.Missing) != 1 || out.Missing[0].Artist != "Somebody, Else" {
		t.Fatalf("missing = %+v, want the unknown title with its cell intact", out.Missing)
	}
}

func TestArtistMixHonorsExcludePids(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	res, err := svc.Reads.Search(ctx, uc, "Test Ensemble", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Artists) == 0 {
		t.Fatal("fixture artist not in search results")
	}
	artistPID := res.Artists[0].PID

	page, err := svc.Reads.Items(ctx, uc, ItemFilter{MediaType: "music"}, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	excluded := ""
	for _, it := range page.Items {
		if it.Title == "Amber Waves" {
			excluded = it.PID
		}
	}
	if excluded == "" {
		t.Fatal("fixture track missing")
	}

	// An artist seed must not resurrect a pid the caller excluded
	// (already played this radio session): the seed's own tracks stay
	// eligible by absence from the exclude set, never by overwriting
	// caller entries with false.
	mix, err := svc.Similarity.InstantMix(ctx, uc, InstantMixInput{
		SeedPID:     artistPID,
		Size:        10,
		ExcludePIDs: []string{excluded},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(mix.Items) == 0 {
		t.Fatal("empty mix")
	}
	for _, it := range mix.Items {
		if it.PID == excluded {
			t.Fatalf("mix contains excluded pid %s", excluded)
		}
	}
	if mix.Excluded != 1 {
		t.Fatalf("excluded = %d, want the one dropped candidate counted", mix.Excluded)
	}
}

func TestInstantMixCountsExclusions(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)

	page, err := svc.Reads.Items(ctx, uc, ItemFilter{MediaType: "music"}, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	seed := ""
	others := []string{}
	for _, it := range page.Items {
		if it.Title == "Amber Waves" {
			seed = it.PID
		} else {
			others = append(others, it.PID)
		}
	}
	if seed == "" || len(others) != 3 {
		t.Fatalf("fixture library = %+v, want the seed plus three others", page.Items)
	}

	// Every other track excluded: the mix is empty, and the count says
	// why - each of the three was met and dropped. The seed's own drop
	// stays out of it, so a bare seed still reads as "no candidates".
	mix, err := svc.Similarity.InstantMix(ctx, uc, InstantMixInput{
		SeedPID:     seed,
		Size:        10,
		ExcludePIDs: others,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(mix.Items) != 0 {
		t.Fatalf("mix = %+v, want empty with everything excluded", mix.Items)
	}
	if mix.Excluded != 3 {
		t.Fatalf("excluded = %d, want 3", mix.Excluded)
	}

	// Nothing excluded: the count stays zero even though the seed
	// itself was dropped from its own candidate pools.
	open, err := svc.Similarity.InstantMix(ctx, uc, InstantMixInput{SeedPID: seed, Size: 10})
	if err != nil {
		t.Fatal(err)
	}
	if len(open.Items) == 0 || open.Excluded != 0 {
		t.Fatalf("open mix = %d items, excluded %d; want items with a zero count", len(open.Items), open.Excluded)
	}
}

// spokenWordBesideMusic is the catalog fixture with a book and a followed
// show beside its tracks. The book shares the ensemble's artist and genre,
// so the pools drawn by artist and by genre can reach it; an episode has
// no artist credit or genre, so the random pool is the only one it can
// enter.
func spokenWordBesideMusic(t *testing.T) (context.Context, *Library, *UserCtx) {
	t.Helper()
	feed := &stubFeed{kind: model.SourceRSS, n: 3, prefix: "Ensemble Talk"}
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{
		podcasts: true,
		sources:  []source.Provider{feed},
		extra: func(t *testing.T, dir string) {
			if _, err := fixtures.GenerateM4B(dir, fixtures.Spec{
				Name: "ensemble-book", Duration: 2 * time.Second,
				Tags: map[string]string{
					"TITLE": "Ensemble Tales", "ALBUM": "Signal Garden",
					"ARTIST": "Test Ensemble", "ALBUMARTIST": "Test Ensemble", "GENRE": "Ambient",
				},
			}); err != nil {
				t.Fatal(err)
			}
		},
	})
	if _, _, err := svc.Podcasts.Subscribe(ctx, uc, SubscribeRequest{URL: "https://feeds.example/ensemble", SourceType: "rss"}); err != nil {
		t.Fatal(err)
	}
	for _, kind := range []string{"audiobook", "podcast"} {
		page, err := svc.Reads.Items(ctx, uc, ItemFilter{MediaType: kind}, "", 10)
		if err != nil || len(page.Items) == 0 {
			t.Fatalf("fixture %s = (%+v, %v), want one beside the tracks", kind, page.Items, err)
		}
	}
	return ctx, svc, uc
}

// onlyMusic fails the test for any item that is not a track.
func onlyMusic(t *testing.T, what string, items []ItemSummary) {
	t.Helper()
	if len(items) == 0 {
		t.Fatalf("%s: empty", what)
	}
	for _, it := range items {
		if it.MediaType != "music" {
			t.Fatalf("%s holds %s %q (%s)", what, it.MediaType, it.Title, it.PID)
		}
	}
}

// What follows music is music: a mix from a track, an artist, an album or
// a genre leaves out the book sharing the seed's artist and genre, and the
// episodes its random pool could draw, however far it wanders.
func TestInstantMixIsMusicOnly(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := spokenWordBesideMusic(t)

	res, err := svc.Reads.Search(ctx, uc, "Test Ensemble", 10)
	if err != nil || len(res.Artists) == 0 {
		t.Fatalf("fixture artist = (%+v, %v)", res.Artists, err)
	}
	artistPID := res.Artists[0].PID
	tracks, err := svc.Reads.Items(ctx, uc, ItemFilter{MediaType: "music"}, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	var trackPID, albumPID string
	for _, it := range tracks.Items {
		if it.Title == "Amber Waves" {
			trackPID, albumPID = it.PID, it.AlbumPID
		}
	}
	if trackPID == "" || albumPID == "" {
		t.Fatalf("fixture track = (%q, %q)", trackPID, albumPID)
	}

	for _, seed := range []InstantMixInput{
		{SeedPID: trackPID},
		{SeedPID: artistPID},
		{SeedPID: albumPID},
		{Genre: "Ambient"},
	} {
		for _, adv := range []float64{0, 1} {
			seed.Adventurousness = adv
			seed.Size = 200
			mix, err := svc.Similarity.InstantMix(ctx, uc, seed)
			if err != nil {
				t.Fatalf("mix %+v: %v", seed, err)
			}
			onlyMusic(t, fmt.Sprintf("mix %+v", seed), mix.Items)
		}
	}
}

// The similar-tracks list is held to tracks the same way, on the metadata
// path every fresh library answers from.
func TestSimilarTracksMusicOnly(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := spokenWordBesideMusic(t)

	tracks, err := svc.Reads.Items(ctx, uc, ItemFilter{MediaType: "music"}, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	seed := ""
	for _, it := range tracks.Items {
		if it.Title == "Amber Waves" {
			seed = it.PID
		}
	}
	if seed == "" {
		t.Fatal("fixture track missing")
	}

	res, err := svc.Similarity.SimilarTracksFor(ctx, uc, seed, 50)
	if err != nil {
		t.Fatal(err)
	}
	if res.Basis != BasisMetadata {
		t.Fatalf("basis = %q, want %q", res.Basis, BasisMetadata)
	}
	onlyMusic(t, "similar tracks", res.Items)
}
