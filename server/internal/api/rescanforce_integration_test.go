package api

import (
	"os"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// A forced rescan re-reads files the incremental fast-path would skip:
// the repair pass for rows written before a parser fix. The probe edits
// a file's tags without moving its size or mtime - invisible to a plain
// rescan by construction - and asserts only {"force": true} heals the
// row, which proves the flag crosses the API and service into waxbin.
func TestRescanForceRereadsUnchangedFiles(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	spec := func(title string) fixtures.Spec {
		return fixtures.Spec{
			Name:     "retag-probe",
			Codec:    fixtures.CodecFLAC,
			Duration: 2 * time.Second,
			Tags: map[string]string{
				"TITLE":  title,
				"ARTIST": "Rescan Probe",
				"ALBUM":  "Fast Path",
			},
		}
	}
	paths, err := fixtures.Generate(h.library, spec("First Cut"))
	if err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	if got := probeTitle(t, h); got != "First Cut" {
		t.Fatalf("title after first scan = %q, want %q", got, "First Cut")
	}

	// Rewrite the file with a same-length title and put its mtime back,
	// so size and mtime both read unchanged. The synthesis is
	// deterministic, so equal-length tags mean equal-length files; the
	// size check fails loudly if that assumption ever breaks.
	before, err := os.Stat(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	edited, err := fixtures.Generate(t.TempDir(), spec("Fresh Cut"))
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(edited[0])
	if err != nil {
		t.Fatal(err)
	}
	if int64(len(raw)) != before.Size() {
		t.Fatalf("edited fixture is %d bytes, original %d; the probe needs equal sizes", len(raw), before.Size())
	}
	if err := os.WriteFile(paths[0], raw, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(paths[0], before.ModTime(), before.ModTime()); err != nil {
		t.Fatal(err)
	}

	// The plain rescan fast-paths the file and keeps the stale row.
	h.rescanAndWait(t)
	if got := probeTitle(t, h); got != "First Cut" {
		t.Fatalf("title after plain rescan = %q, want the stale %q", got, "First Cut")
	}

	// The forced one re-reads it.
	h.rescanAndWaitWith(t, `{"force": true}`)
	if got := probeTitle(t, h); got != "Fresh Cut" {
		t.Fatalf("title after forced rescan = %q, want %q", got, "Fresh Cut")
	}
}

// probeTitle finds the probe track by artist and returns its title.
func probeTitle(t *testing.T, h *harness) string {
	t.Helper()
	page := h.items(t, "?limit=200")
	for _, it := range page.Items {
		if it.Artist != nil && *it.Artist == "Rescan Probe" {
			return it.Title
		}
	}
	t.Fatal("probe track not found")
	return ""
}
