package service

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"testing"

	"github.com/colespringer/waxbin"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// WMA and Musepack are the two formats the decode stack reads and
// cannot write, so they are checked in rather than synthesized. This
// pins that a scan catalogs them under the labels the rest of the
// server keys on: the mime tables, the split-format pick, and the
// lossless test all switch on these exact strings, and a label that
// drifted would strand the format at whichever of them read it first.
//
// Both samples carry chapters and neither keeps them here, which is not
// a gap in this test: upstream stores chapters on books alone, and a
// book is an .m4b, an iTunes media kind of 2, or a narrator credit -
// none of which a .wma or .mpc arrives with. That the files themselves
// carry markers is pinned where it is true, in the fixtures package.
func TestVendoredExoticFormatsScan(t *testing.T) {
	t.Parallel()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	libDir := t.TempDir()
	if _, err := fixtures.WriteVendored(libDir, fixtures.AllExotics...); err != nil {
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
		t.Fatalf("scanning the vendored samples: %v", err)
	}

	// Keyed by the file the item came from, since neither sample's tags
	// are what identifies it here.
	want := map[string]struct{ container, codec string }{
		fixtures.ExoticMusepack: {container: "musepack", codec: "musepack"},
		fixtures.ExoticWMA:      {container: "asf", codec: "wma"},
	}
	page, err := svc.lib.QueryPage(ctx,
		visibleItems().OrderBy("title", false).Build(), "", 50, false, "")
	if err != nil {
		t.Fatal(err)
	}
	seen := map[string]bool{}
	for _, it := range page.Items {
		name := filepath.Base(string(it.Path))
		exp, ok := want[name]
		if !ok {
			continue
		}
		seen[name] = true
		t.Run(name, func(t *testing.T) {
			if it.Container != exp.container || it.Codec != exp.codec {
				t.Errorf("container/codec = %q/%q, want %q/%q",
					it.Container, it.Codec, exp.container, exp.codec)
			}
			if it.DurationMS <= 0 {
				t.Errorf("duration = %d, want the decoded length", it.DurationMS)
			}
		})
	}
	for name := range want {
		if !seen[name] {
			t.Errorf("%s did not scan", name)
		}
	}
}
