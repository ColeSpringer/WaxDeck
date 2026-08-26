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

// newAdvisoryFixture is a scanned library whose files carry the
// ITUNESADVISORY tag the way real encoders write it - in the freeform
// tag long tail - so the flag travels the whole scan path rather than
// being injected through the editor.
func newAdvisoryFixture(t *testing.T) (context.Context, *Library, *UserCtx) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	track := func(name, title, advisory string, d time.Duration) fixtures.Spec {
		tags := map[string]string{
			"TITLE":  title,
			"ARTIST": "Advisory Ensemble",
			"ALBUM":  "Sticker Season",
		}
		if advisory != "" {
			tags["ITUNESADVISORY"] = advisory
		}
		return fixtures.Spec{Name: name, Codec: fixtures.CodecFLAC, Duration: d, Tags: tags}
	}
	libDir := t.TempDir()
	if _, err := fixtures.Generate(libDir,
		track("flagged", "Flagged", "1", 2*time.Second),
		track("legacy", "Legacy Sticker", "4", 2500*time.Millisecond),
		track("declared-clean", "Declared Clean", "2", 3*time.Second),
		track("unsaid", "Unsaid", "", 3500*time.Millisecond),
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

// TestTrackFactsExplicitFromAdvisoryTag pins the advisory contract the
// Subsonic emission rides on: ITUNESADVISORY "1" and the legacy "4"
// mark a track explicit. "2" is a declared clean and stays unasserted
// rather than being truthy-parsed, and an edit through the tag surface
// reaches the facts once the change feed consumes it - the cached
// sweep keys on the feed position, so a tag write that failed to move
// it would serve a stale advisory forever.
func TestTrackFactsExplicitFromAdvisoryTag(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newAdvisoryFixture(t)

	rows, err := svc.TrackFacts(ctx, uc)
	if err != nil {
		t.Fatalf("TrackFacts: %v", err)
	}
	want := map[string]bool{
		"Flagged": true, "Legacy Sticker": true,
		"Declared Clean": false, "Unsaid": false,
	}
	if len(rows) != len(want) {
		t.Fatalf("rows = %d, want the %d fixture tracks", len(rows), len(want))
	}
	var unsaidPID string
	for _, tr := range rows {
		wantExplicit, ok := want[tr.Title]
		if !ok {
			t.Fatalf("unexpected fixture track %q", tr.Title)
		}
		if tr.Explicit != wantExplicit {
			t.Errorf("%q explicit = %t, want %t", tr.Title, tr.Explicit, wantExplicit)
		}
		if tr.Title == "Unsaid" {
			unsaidPID = tr.PID
		}
	}

	if _, err := svc.SetItemTag(ctx, uc, unsaidPID, "ITUNESADVISORY", []string{"1"}, true, false); err != nil {
		t.Fatalf("tagging through the editor: %v", err)
	}
	deadline := time.Now().Add(10 * time.Second)
	for {
		rows, err := svc.TrackFacts(ctx, uc)
		if err != nil {
			t.Fatalf("TrackFacts after the edit: %v", err)
		}
		flagged := false
		for _, tr := range rows {
			if tr.PID == unsaidPID {
				flagged = tr.Explicit
			}
		}
		if flagged {
			return
		}
		if time.Now().After(deadline) {
			t.Fatal("the editor-set advisory never reached the facts sweep")
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// TestTrackFactsCarryContentRules: a tag-deny account (the admin
// screen's kids preset denies ITUNESADVISORY=1) must not receive the
// tracks its rules hide - the compatibility surface's browse verbs all
// render this sweep, and it used to apply library grants only. The
// admin call ahead of it seeds the shared cache, so the restricted rows
// also prove a narrowed sweep is never served from (or published to)
// that entry.
func TestTrackFactsCarryContentRules(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newAdvisoryFixture(t)

	if _, err := svc.TrackFacts(ctx, uc); err != nil {
		t.Fatalf("seeding the unrestricted cache: %v", err)
	}

	restricted := &UserCtx{
		ID:           uc.ID,
		CatalogPID:   uc.CatalogPID,
		AllLibraries: true,
		Explicit:     true,
		TagDeny:      []TagRule{{Key: advisoryTagKey, Value: "1"}},
	}
	rows, err := svc.TrackFacts(ctx, restricted)
	if err != nil {
		t.Fatalf("restricted TrackFacts: %v", err)
	}
	// The rule denies the value "1" only, so the legacy-"4" track stays
	// visible (and stays labeled): the rule narrows what its author
	// wrote, not what the emission infers.
	want := map[string]bool{"Legacy Sticker": true, "Declared Clean": false, "Unsaid": false}
	if len(rows) != len(want) {
		t.Fatalf("restricted rows = %d (%+v), want %d", len(rows), rows, len(want))
	}
	for _, tr := range rows {
		wantExplicit, ok := want[tr.Title]
		if !ok {
			t.Errorf("restricted sweep leaked %q", tr.Title)
			continue
		}
		if tr.Explicit != wantExplicit {
			t.Errorf("%q explicit = %t, want %t", tr.Title, tr.Explicit, wantExplicit)
		}
	}

	// The narrowed sweep must not have poisoned the shared entry.
	rows, err = svc.TrackFacts(ctx, uc)
	if err != nil {
		t.Fatalf("unrestricted TrackFacts after the restricted one: %v", err)
	}
	if len(rows) != 4 {
		t.Fatalf("unrestricted rows = %d after a restricted sweep, want 4", len(rows))
	}
}
