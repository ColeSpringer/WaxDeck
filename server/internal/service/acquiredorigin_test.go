package service

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// The acquired-import sites (the merge tool's result, an upload's
// duplicate probe, and the review settle) know that a file arrived, not
// how. They pass no SourceType for that reason: upstream reads an empty
// one as "no claim about the mechanism", writing manual only when it
// first records a row and leaving a standing origin alone on a
// re-record. Passing manual is a claim, and a claim overwrites the rss
// or youtube origin a download had already recorded.
//
// The control half is the point of the test: the same import stamped
// manual does flatten the origin, so this fails if a site ever puts the
// field back.
func TestAcquiredImportKeepsAStandingOrigin(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name  string
		claim model.SourceType
		want  model.SourceType
	}{
		{name: "no claim", claim: "", want: model.SourceYouTube},
		{name: "manual claim", claim: model.SourceManual, want: model.SourceManual},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc := newAcquiredOriginFixture(t)

			page, err := svc.lib.QueryPage(ctx,
				visibleItems().OrderBy("title", false).Build(), "", 10, false, "")
			if err != nil {
				t.Fatal(err)
			}
			if len(page.Items) != 1 {
				t.Fatalf("scanned %d items, want 1", len(page.Items))
			}
			it := page.Items[0]

			// The origin a download would have recorded. LockOff
			// matters: a locked row is skipped in silence by the
			// automatic writers, which would make the assertion below
			// pass for the wrong reason.
			if err := svc.lib.SetAcquisition(ctx, it.PID, model.AcquisitionInput{
				SourceType: model.SourceYouTube,
				SourceURL:  "https://www.youtube.test/watch?v=abc123",
				SourceID:   "abc123",
				Provider:   "waxtap",
			}, waxbin.AcquisitionEditOptions{Lock: model.LockOff}); err != nil {
				t.Fatalf("recording the download's origin: %v", err)
			}

			res, err := svc.lib.ImportAcquired(ctx,
				waxbin.AcquiredFile{Path: string(it.Path)}, model.KindTrack,
				waxbin.AcquiredMeta{SourceType: tc.claim, Copy: false, DupPolicy: model.DupAllow})
			if err != nil {
				t.Fatalf("importing the acquired file: %v", err)
			}
			if res.Plan == nil {
				t.Fatal("the import planner produced no plan")
			}
			if _, err := svc.lib.ApplyImport(ctx, res.Plan); err != nil {
				t.Fatalf("applying the import: %v", err)
			}

			acq, err := svc.lib.Acquisition(ctx, it.PID)
			if err != nil {
				t.Fatalf("reading the origin back: %v", err)
			}
			if acq.SourceType != tc.want {
				t.Errorf("sourceType = %q, want %q", acq.SourceType, tc.want)
			}
			// The merge is field-wise, so the url and id ride through
			// either way: emptiness is not evidence.
			if acq.SourceID != "abc123" {
				t.Errorf("sourceId = %q, want the download's", acq.SourceID)
			}
		})
	}
}

func newAcquiredOriginFixture(t *testing.T) (context.Context, *Library) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	libDir := t.TempDir()
	if _, err := fixtures.Generate(libDir, fixtures.Spec{
		Name: "acquired", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Acquired Cut", "ARTIST": "Night Transit"},
	}); err != nil {
		t.Fatal(err)
	}
	dataDir := t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{
		DataDir: dataDir,
		Roots:   []Root{{Name: "lib", Path: libDir, Managed: true}},
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
		t.Fatalf("scanning the fixture library: %v", err)
	}
	return ctx, svc
}
