package service

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxdeck/fixtures"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// newCatalogFixture is a real Library over a small scanned catalog of
// tagged tracks, plus an admin context: enough for the import resolve
// ladder and the discovery metadata fallback. Durations are distinct so
// the catalog's fingerprint dedup never merges the synthesized tones.
func newCatalogFixture(t *testing.T) (context.Context, *Library, *UserCtx) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

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
	libDir := t.TempDir()
	if _, err := fixtures.Generate(libDir,
		track("amber", "Amber Waves", "Test Ensemble", "Ambient", 2*time.Second),
		track("basalt", "Basalt Steps", "Test Ensemble", "Ambient", 2500*time.Millisecond),
		track("cobalt", "Cobalt Sky", "Test Ensemble", "Ambient", 3*time.Second),
		track("delta", "Delta Groove", "Brass Nine", "Jazz", 3500*time.Millisecond),
	); err != nil {
		t.Fatalf("generating fixtures: %v", err)
	}

	dataDir := t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{
		DataDir: dataDir,
		Roots:   []Root{{Name: "lib", Path: libDir}},
		Logger:  log,
	}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatalf("scanning fixture library: %v", err)
	}

	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "admin", Password: "correct-horse", Roles: []string{"admin"},
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return ctx, svc, uc
}

func TestImportStreamingPlaylistTextDescriptive(t *testing.T) {
	ctx, svc, uc := newCatalogFixture(t)

	payload := "# exported list\n" +
		"Test Ensemble - Amber Waves\n" +
		"Test Ensemble \u2013 Basalt Steps\n" +
		"Test Ensemble - Never Recorded\n" +
		"Delta Groove\n"
	out, err := svc.ImportStreamingPlaylist(ctx, uc, PlaylistImportInput{
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
	pl, err := svc.PlaylistByPID(ctx, uc, out.PlaylistPID)
	if err != nil {
		t.Fatal(err)
	}
	if pl.Name != "Road Tape" {
		t.Fatalf("playlist name = %q", pl.Name)
	}
	page, err := svc.PlaylistItems(ctx, uc, out.PlaylistPID, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Entries) != 2 ||
		page.Entries[0].Item.Title != "Amber Waves" ||
		page.Entries[1].Item.Title != "Basalt Steps" {
		t.Fatalf("playlist entries = %+v, want Amber Waves then Basalt Steps", page.Entries)
	}

	// Nothing resolved means no playlist at all, not an empty one.
	none, err := svc.ImportStreamingPlaylist(ctx, uc, PlaylistImportInput{
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
	ctx, svc, uc := newCatalogFixture(t)

	// Find the seed by title through the import resolver itself.
	seedOut, err := svc.ImportStreamingPlaylist(ctx, uc, PlaylistImportInput{
		Source:  "text",
		Payload: "Test Ensemble - Amber Waves\n",
	})
	if err != nil || seedOut.Resolved != 1 {
		t.Fatalf("resolving the seed = (%+v, %v)", seedOut, err)
	}
	page, err := svc.PlaylistItems(ctx, uc, seedOut.PlaylistPID, "", 1)
	if err != nil || len(page.Entries) != 1 {
		t.Fatalf("seed lookup = (%+v, %v)", page, err)
	}
	seedPID := page.Entries[0].Item.PID

	// No worker has ever posted embeddings, so the sonic engine is
	// empty and the answer must come from the metadata fallback.
	res, err := svc.SimilarTracksFor(ctx, uc, seedPID, 10)
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
	ctx, svc, uc := newCatalogFixture(t)

	// An export whose artist cells join every credit: the full cell
	// misses the descriptive rung, and the primary-credit retry lands
	// it. The unknown title stays missing with its cell intact.
	payload := "Test Ensemble, Guest Voice - Amber Waves\n" +
		"Test Ensemble feat. Guest Voice - Basalt Steps\n" +
		"Somebody, Else - Never Recorded\n"
	out, err := svc.ImportStreamingPlaylist(ctx, uc, PlaylistImportInput{
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
	ctx, svc, uc := newCatalogFixture(t)

	res, err := svc.Search(ctx, uc, "Test Ensemble", 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(res.Artists) == 0 {
		t.Fatal("fixture artist not in search results")
	}
	artistPID := res.Artists[0].PID

	page, err := svc.Items(ctx, uc, ItemFilter{MediaType: "music"}, "", 10)
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
	mix, err := svc.InstantMix(ctx, uc, InstantMixInput{
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
}
