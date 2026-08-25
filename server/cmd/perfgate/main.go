// Command perfgate measures the server-side query latencies the large-
// library gate budgets: keyset pages (shallow and deep), per-user
// browse lists (the play_state LEFT JOIN bet), full-text search, and
// the sync surface, against a corpus library (see fixtures/cmd/
// corpusgen). It scans the corpus into a fresh catalog, runs each probe
// repeatedly, and reports medians against the budgets, exiting nonzero
// on a miss.
//
//	perfgate -library /tmp/corpus [-runs 20]
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"sort"
	"time"

	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// The pre-agreed server-side budgets for the large-library gate,
// measured as medians on developer-class hardware.
var budgets = map[string]time.Duration{
	"page-first":        100 * time.Millisecond,
	"page-deep":         100 * time.Millisecond,
	"browse-starred":    150 * time.Millisecond,
	"browse-mostplayed": 150 * time.Millisecond,
	"search-common":     200 * time.Millisecond,
	"search-rare":       200 * time.Millisecond,
	"sync-snapshot":     250 * time.Millisecond,
	"sync-delta":        250 * time.Millisecond,
	"playstates-batch":  250 * time.Millisecond,
}

func main() {
	library := flag.String("library", "", "corpus library root (required)")
	runs := flag.Int("runs", 20, "probe repetitions (median reported)")
	flag.Parse()
	if *library == "" {
		fmt.Fprintln(os.Stderr, "perfgate: -library is required")
		os.Exit(2)
	}
	if err := run(*library, *runs); err != nil {
		fmt.Fprintln(os.Stderr, "perfgate:", err)
		os.Exit(1)
	}
}

func run(library string, runs int) error {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	dataDir, err := os.MkdirTemp("", "perfgate-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(dataDir)

	store, err := db.Open(ctx, dataDir+"/waxdeck.db")
	if err != nil {
		return err
	}
	defer store.Close()
	group := supervise.NewGroup(log)
	fmt.Println("perfgate: opening and scanning the corpus (one-time cost)...")
	scanStart := time.Now()
	svc, err := service.Open(ctx, service.Config{
		DataDir:     dataDir,
		Roots:       []service.Root{{Name: "corpus", Path: library}},
		ScanOnStart: false,
		Logger:      log,
	}, store, group)
	if err != nil {
		return err
	}
	defer func() {
		cancel()
		group.Wait()
		svc.Close()
	}()

	admin, err := svc.Bootstrap(ctx, "gate", "gate-password", "")
	if err != nil {
		return err
	}
	uc, err := svc.UserCtx(ctx, admin.User)
	if err != nil {
		return err
	}

	job, err := svc.Rescan(ctx, false)
	if err != nil {
		return err
	}
	for {
		j, err := svc.JobStatus(ctx, job.PID)
		if err != nil {
			return err
		}
		if j.State == "done" {
			break
		}
		if j.State == "failed" || j.State == "crashed" {
			return fmt.Errorf("scan %s: %s", j.State, j.Error)
		}
		time.Sleep(200 * time.Millisecond)
	}
	fmt.Printf("perfgate: scan finished in %s\n", time.Since(scanStart).Round(time.Second))

	first, err := svc.Items(ctx, uc, service.ItemFilter{}, "", 100)
	if err != nil {
		return err
	}
	if len(first.Items) == 0 {
		return fmt.Errorf("the corpus scanned to an empty catalog")
	}
	fmt.Printf("perfgate: first page holds %d items; walking to a deep page...\n", len(first.Items))

	// Walk ~200 pages in so the deep probe pays real keyset depth, and
	// seed user state so the A9 joins have rows to find.
	deepCursor := first.Next
	for i := 0; i < 200 && deepCursor != ""; i++ {
		page, err := svc.Items(ctx, uc, service.ItemFilter{}, deepCursor, 100)
		if err != nil {
			return err
		}
		if page.Next == "" {
			break
		}
		deepCursor = page.Next
	}
	starredPIDs := make([]string, 0, 200)
	for i, it := range first.Items {
		if _, err := svc.SetStar(ctx, uc, it.PID, true, nil); err != nil {
			return err
		}
		if _, err := svc.Checkpoint(ctx, uc, it.PID, int64(1000+i), nil); err != nil {
			return err
		}
		starredPIDs = append(starredPIDs, it.PID)
	}

	deltaSince := ""
	{
		page, err := svc.SyncCatalogSnapshot(ctx, uc, "", 500)
		if err != nil {
			return err
		}
		deltaSince = page.NextSince
	}
	// Touch items so the delta probe has changes to serve.
	for _, pid := range starredPIDs[:50] {
		if _, err := svc.SetStar(ctx, uc, pid, true, nil); err != nil {
			return err
		}
	}

	probes := []struct {
		name string
		fn   func() error
	}{
		{"page-first", func() error {
			_, err := svc.Items(ctx, uc, service.ItemFilter{}, "", 100)
			return err
		}},
		{"page-deep", func() error {
			_, err := svc.Items(ctx, uc, service.ItemFilter{}, deepCursor, 100)
			return err
		}},
		{"browse-starred", func() error {
			_, err := svc.Browse(ctx, uc, "starred", service.ItemFilter{}, 0, "", 100)
			return err
		}},
		{"browse-mostplayed", func() error {
			_, err := svc.Browse(ctx, uc, "most-played", service.ItemFilter{}, 0, "", 100)
			return err
		}},
		{"search-common", func() error {
			_, err := svc.Search(ctx, uc, "Corpus", 20)
			return err
		}},
		{"search-rare", func() error {
			_, err := svc.Search(ctx, uc, "00042-007", 20)
			return err
		}},
		{"sync-snapshot", func() error {
			_, err := svc.SyncCatalogSnapshot(ctx, uc, "", 500)
			return err
		}},
		{"sync-delta", func() error {
			_, err := svc.SyncCatalogDelta(ctx, uc, deltaSince, 500)
			return err
		}},
		{"playstates-batch", func() error {
			_, err := svc.PlayStates(ctx, uc, starredPIDs)
			return err
		}},
	}

	fmt.Printf("\n%-20s %10s %10s %10s   verdict\n", "probe", "median", "p95", "budget")
	failed := false
	for _, p := range probes {
		times := make([]time.Duration, 0, runs)
		for i := 0; i < runs; i++ {
			t0 := time.Now()
			if err := p.fn(); err != nil {
				return fmt.Errorf("%s: %w", p.name, err)
			}
			times = append(times, time.Since(t0))
		}
		sort.Slice(times, func(i, j int) bool { return times[i] < times[j] })
		median := times[len(times)/2]
		p95 := times[len(times)*95/100]
		budget := budgets[p.name]
		verdict := "PASS"
		if median > budget {
			verdict = "FAIL"
			failed = true
		}
		fmt.Printf("%-20s %10s %10s %10s   %s\n",
			p.name, median.Round(time.Microsecond), p95.Round(time.Microsecond), budget, verdict)
	}
	if failed {
		return fmt.Errorf("one or more probes exceeded budget")
	}
	fmt.Println("\nperfgate: all probes within budget")
	return nil
}
