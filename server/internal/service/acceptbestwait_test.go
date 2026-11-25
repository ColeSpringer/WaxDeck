package service

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/match"
)

// bestReleases answers every search with the same releases: "Quiet Wire"
// is the upload's best, "Loud Copper" a stranger a person may pick.
type bestReleases struct{}

var waitReleases = []*match.Release{
	{
		MBID: "rel-obvious", ReleaseGroupMBID: "rg-obvious",
		Title: "Quiet Wire", Artist: "Hold Steady State", Year: 2021, Media: 1,
		Tracks: []match.ReleaseTrack{{
			RecordingMBID: "00000000-0000-4000-8000-0000000000a1",
			Title:         "Quiet Wire", Position: 1, DurationSec: 3,
		}},
	},
	{
		MBID: "rel-other", ReleaseGroupMBID: "rg-other",
		Title: "Loud Copper", Artist: "Hold Steady State", Year: 2019, Media: 1,
		Tracks: []match.ReleaseTrack{{
			RecordingMBID: "00000000-0000-4000-8000-0000000000b1",
			Title:         "Loud Copper", Position: 1, DurationSec: 3,
		}},
	},
}

func (bestReleases) ReleaseByMBID(_ context.Context, mbid string) (*match.Release, error) {
	for _, r := range waitReleases {
		if r.MBID == mbid {
			return r, nil
		}
	}
	return nil, nil
}

func (bestReleases) ReleasesByGroup(context.Context, string) ([]*match.Release, error) {
	return nil, nil
}

func (bestReleases) LookupFingerprint(context.Context, match.Fingerprint) ([]match.FingerprintHit, error) {
	return nil, nil
}

func (bestReleases) SearchReleases(context.Context, string, string, int) ([]*match.Release, error) {
	return waitReleases, nil
}

func (bestReleases) SearchRecordings(context.Context, string, string, string, string) (match.RecordingSearch, error) {
	return match.RecordingSearch{Releases: waitReleases}, nil
}

// waitingBest uploads "Quiet Wire" asking to take its best match while
// busy holds the catalog, and answers its entry once that apply waits.
func waitingBest(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, busy *atomic.Bool) string {
	t.Helper()
	busy.Store(true)
	busyCatalog(svc, busy)
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "quiet", Codec: fixtures.CodecMP3, Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Quiet Wire", "ARTIST": "Hold Steady State"},
	})
	if err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	yes := true
	up, err := svc.Ingest.CreateUpload(ctx, uc, UploadCreateParams{
		FileName: filepath.Base(paths[0]), SizeBytes: int64(len(data)), MediaType: "music",
		Identify: &yes, AcceptBest: &yes,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Ingest.AppendUploadData(ctx, uc, up.ID, 0, bytes.NewReader(data)); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Ingest.CompleteUpload(ctx, uc, up.ID); err != nil {
		t.Fatal(err)
	}
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil || row.ReviewEntryID == "" {
		t.Fatalf("upload = %+v, %v; want it linked to an entry", row, err)
	}
	id := row.ReviewEntryID
	waitFor(t, func() bool {
		svc.Ingest.DrainMatchQueue(ctx)
		status, p := decidedEntry(t, ctx, svc, id)
		return status == reviewPending && p.WaitingApply == "rel-obvious" && p.WaitingForCatalog
	}, "the accept-best apply should wait for the busy catalog")
	return id
}

// retryNow frees the catalog and takes the entry's wait up at once, then
// waits out any retry the job follower started meanwhile.
func retryNow(t *testing.T, ctx context.Context, svc *Library, busy *atomic.Bool, id string) {
	t.Helper()
	busy.Store(false)
	svc.Ingest.importDeclinedEntry(ctx, id)
	waitFor(t, func() bool {
		release, ok := svc.Ingest.claimEntry(id)
		if ok {
			release()
		}
		return ok
	}, "the entry should come free")
}

// stillForAPerson fails unless the entry is pending with no wait left
// that a later retry could take up.
func stillForAPerson(t *testing.T, ctx context.Context, svc *Library, id string) {
	t.Helper()
	e, err := svc.db.ReviewEntryByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	status, p := decidedEntry(t, ctx, svc, id)
	if status != reviewPending || e.AppliedMBID != "" {
		t.Fatalf("entry = %s applied %q, want it pending for a person", status, e.AppliedMBID)
	}
	if p.WaitingApply != "" || p.WaitingForCatalog {
		t.Fatalf("entry still waits to apply %q (for the catalog %v)", p.WaitingApply, p.WaitingForCatalog)
	}
}

// An accept-best apply that meets another job holding the catalog takes
// its best once the catalog frees, as a declined import does, rather than
// leaving it for a person.
func TestAcceptBestThatMeetsABusyCatalogAppliesWhenItFrees(t *testing.T) {
	ctx, svc, uc := managedUploadFixtureWith(t, func(cfg *Config) { cfg.MatchSource = bestReleases{} })
	var busy atomic.Bool
	id := waitingBest(t, ctx, svc, uc, &busy)
	busy.Store(false)
	waitFor(t, func() bool {
		e, err := svc.db.ReviewEntryByID(ctx, id)
		return err == nil && e.Status == reviewAutoApplied
	}, "the accept-best apply should go once the catalog frees")
	e, err := svc.db.ReviewEntryByID(ctx, id)
	if err != nil || e.AppliedMBID != "rel-obvious" || !e.AcceptedBest {
		t.Fatalf("entry = %+v, %v; want rel-obvious applied as asked", e, err)
	}
}

// A person searching again while the apply waits for the catalog takes
// the entry from it: the wait never applies the old best past their
// typed search.
func TestAnApplyWaitingForTheCatalogYieldsToANewSearch(t *testing.T) {
	ctx, svc, uc := managedUploadFixtureWith(t, func(cfg *Config) { cfg.MatchSource = bestReleases{} })
	var busy atomic.Bool
	id := waitingBest(t, ctx, svc, uc, &busy)
	waitFor(t, func() bool {
		_, err := svc.Ingest.ReidentifyEntry(ctx, uc, id, ReviewOverrideDTO{Title: "Quiet Wire"})
		if err != nil && KindOf(err) != KindConflict {
			t.Fatal(err)
		}
		return err == nil
	}, "the re-identify should land")
	retryNow(t, ctx, svc, &busy, id)
	stillForAPerson(t, ctx, svc, id)
}

// A person's own apply while the auto-apply waits takes the entry from
// it, and their failing one leaves it for them, not for the old best.
func TestAnApplyWaitingForTheCatalogYieldsToAPersonsApply(t *testing.T) {
	ctx, svc, uc := managedUploadFixtureWith(t, func(cfg *Config) { cfg.MatchSource = bestReleases{} })
	var busy atomic.Bool
	id := waitingBest(t, ctx, svc, uc, &busy)
	waitFor(t, func() bool {
		_, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "approve", "rel-other", "", false)
		switch KindOf(err) {
		case KindConflict:
			return false
		case KindCatalogBusy:
			return true
		}
		t.Fatalf("a person's apply during the wait = %v, want it to meet the busy catalog", err)
		return false
	}, "the person's apply should meet the busy catalog")
	retryNow(t, ctx, svc, &busy, id)
	stillForAPerson(t, ctx, svc, id)
}

// A library switched to off while the apply waits is out of accept-best's
// reach: the wait applies nothing.
func TestAnApplyWaitingForTheCatalogYieldsToMatchingOff(t *testing.T) {
	ctx, svc, uc := managedUploadFixtureWith(t, func(cfg *Config) { cfg.MatchSource = bestReleases{} })
	var busy atomic.Bool
	id := waitingBest(t, ctx, svc, uc, &busy)
	libs, err := svc.Roots.Libraries(ctx)
	if err != nil || len(libs) == 0 {
		t.Fatalf("listing libraries: %v (%d)", err, len(libs))
	}
	for _, lib := range libs {
		if err := svc.Ingest.SetLibraryMatching(ctx, uc, lib.PID, LibraryMatching{Mode: matchingOff}); err != nil {
			t.Fatal(err)
		}
	}
	retryNow(t, ctx, svc, &busy, id)
	stillForAPerson(t, ctx, svc, id)
}

// An apply wait still valid after a restart is taken up and applies its
// best once.
func TestAnApplyWaitingForTheCatalogGoesOnceAfterARestart(t *testing.T) {
	dataDir := t.TempDir()
	setup := func(cfg *Config) {
		cfg.Roots[0].Managed = true
		cfg.MatchSource = bestReleases{}
	}
	ctx, svc, uc, stop := openServiceAt(t, dataDir, setup)
	var busy atomic.Bool
	id := waitingBest(t, ctx, svc, uc, &busy)
	stop()
	ctx, svc, _, _ = openServiceAt(t, dataDir, setup)
	waitFor(t, func() bool {
		e, err := svc.db.ReviewEntryByID(ctx, id)
		return err == nil && e.Status == reviewAutoApplied
	}, "the wait should be taken up after the restart")
	e, err := svc.db.ReviewEntryByID(ctx, id)
	if err != nil || e.AppliedMBID != "rel-obvious" || !e.AcceptedBest {
		t.Fatalf("entry = %+v, %v; want rel-obvious applied as asked", e, err)
	}
	if _, p := decidedEntry(t, ctx, svc, id); p.WaitingApply != "" || p.WaitingForCatalog {
		t.Fatalf("the applied entry still waits to apply %q", p.WaitingApply)
	}
	svc.Ingest.importDeclinedEntry(ctx, id)
	if again, err := svc.db.ReviewEntryByID(ctx, id); err != nil || again.DecidedAtNS != e.DecidedAtNS || again.Status != e.Status {
		t.Fatalf("a second retry moved the entry: %+v, %v", again, err)
	}
}

// Any other change to the entry while the apply waits withholds it too:
// the wait applies only to the entry as it left it.
func TestAnApplyWaitingForTheCatalogYieldsToAnyChangeOfItsEntry(t *testing.T) {
	ctx, svc, uc := managedUploadFixtureWith(t, func(cfg *Config) { cfg.MatchSource = bestReleases{} })
	var busy atomic.Bool
	id := waitingBest(t, ctx, svc, uc, &busy)
	var release func()
	waitFor(t, func() bool {
		var ok bool
		release, ok = svc.Ingest.claimEntry(id)
		return ok
	}, "the entry should come free to change")
	e, err := svc.db.ReviewEntryByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	_, p := decidedEntry(t, ctx, svc, id)
	p.Suggested = &reviewOverride{Artist: "Someone Else", Title: "Quiet Wire"}
	e.Payload = marshalJSON(p)
	if err := svc.db.UpdateReviewEntry(ctx, e); err != nil {
		t.Fatal(err)
	}
	release()
	retryNow(t, ctx, svc, &busy, id)
	stillForAPerson(t, ctx, svc, id)
}

// A new search that fails after taking the entry from its waiting apply
// leaves no wait a restart could take up: the drop is written first.
func TestAFailedNewSearchLeavesNoApplyWaitForARestart(t *testing.T) {
	dataDir := t.TempDir()
	setup := func(cfg *Config) {
		cfg.Roots[0].Managed = true
		cfg.MatchSource = bestReleases{}
	}
	ctx, svc, uc, stop := openServiceAt(t, dataDir, setup)
	var busy atomic.Bool
	id := waitingBest(t, ctx, svc, uc, &busy)
	for _, sql := range []string{
		`CREATE TRIGGER refuse_queue BEFORE INSERT ON match_queue BEGIN SELECT RAISE(ABORT, 'refused'); END`,
		`CREATE TRIGGER refuse_requeue BEFORE UPDATE ON match_queue BEGIN SELECT RAISE(ABORT, 'refused'); END`,
	} {
		if _, err := svc.db.Writer().ExecContext(ctx, sql); err != nil {
			t.Fatal(err)
		}
	}
	waitFor(t, func() bool {
		_, err := svc.Ingest.ReidentifyEntry(ctx, uc, id, ReviewOverrideDTO{Title: "Quiet Wire"})
		switch KindOf(err) {
		case KindConflict:
			return false
		case KindInternal:
			return true
		}
		t.Fatalf("the new search = %v, want it refused by the queue", err)
		return false
	}, "the new search should reach the queue")
	for _, sql := range []string{`DROP TRIGGER refuse_queue`, `DROP TRIGGER refuse_requeue`} {
		if _, err := svc.db.Writer().ExecContext(ctx, sql); err != nil {
			t.Fatal(err)
		}
	}
	stop()
	ctx, svc, _, _ = openServiceAt(t, dataDir, setup)
	retryNow(t, ctx, svc, &busy, id)
	stillForAPerson(t, ctx, svc, id)
}

// Searching again takes a declined import's wait for the catalog with
// it, the one held in memory as well as the saved one.
func TestANewSearchDropsADeclinedImportsWait(t *testing.T) {
	t.Parallel()
	f := openApprovalFixture(t, approvalSetup{})
	e := pendingMatch(t, f.ctx, f.svc, approvedCandidate(), f.it)
	var payload reviewPayload
	if err := json.Unmarshal([]byte(e.Payload), &payload); err != nil {
		t.Fatal(err)
	}
	payload.IdentifyDeclined, payload.WaitingForCatalog = true, true
	e.Kind, e.Payload = reviewKindImport, marshalJSON(payload)
	if err := f.svc.db.UpdateReviewEntry(f.ctx, e); err != nil {
		t.Fatal(err)
	}
	f.svc.Ingest.waitingForCatalog.Store(e.ID, struct{}{})
	if _, err := f.svc.Ingest.ReidentifyEntry(f.ctx, f.uc, e.ID, ReviewOverrideDTO{Title: "Approved Cut"}); err != nil {
		t.Fatal(err)
	}
	if _, p := decidedEntry(t, f.ctx, f.svc, e.ID); p.WaitingForCatalog {
		t.Error("the saved wait outlived the new search")
	}
	if f.svc.Ingest.waitingImports() {
		t.Error("the wait held in memory outlived the new search")
	}
}
