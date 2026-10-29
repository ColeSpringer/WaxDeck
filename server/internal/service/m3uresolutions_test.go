package service

import (
	"crypto/sha256"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/playlist"
)

// countM3UResolves counts the catalog's resolves of M3U8 documents.
func countM3UResolves(svc *Library) func() int64 {
	var n atomic.Int64
	svc.m3uResolveHook = func() { n.Add(1) }
	return n.Load
}

// The app previews a document and then imports it: the catalog resolves
// it once, and the import builds what the preview said.
func TestAnM3UPreviewAndItsImportResolveOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	track := fixtureItemPIDs(t, ctx, svc, uc)[0]
	it, err := svc.getVisibleItem(ctx, uc, track)
	if err != nil {
		t.Fatal(err)
	}
	doc := "#EXTM3U\n" + it.DisplayPath + "\nnowhere/missing.flac\n"
	resolves := countM3UResolves(svc)

	preview, err := svc.PreviewPlaylistM3U(ctx, uc, doc)
	if err != nil {
		t.Fatal(err)
	}
	imported, err := svc.ImportPlaylistM3U(ctx, uc, "Previewed first", "", doc)
	if err != nil {
		t.Fatal(err)
	}
	if n := resolves(); n != 1 {
		t.Fatalf("a preview and its import resolved the document %d times, want once", n)
	}
	if preview.Matched != 1 || preview.Unmatched != 1 || imported.Matched != 1 || imported.Unmatched != 1 {
		t.Fatalf("preview %+v, import %+v: want one matched and one unmatched line in each", preview, imported)
	}
	if got := memberPIDs(t, ctx, svc, uc, imported.Playlist.PID); !samePIDs(got, []string{track}) {
		t.Fatalf("the import holds %v, want %s", got, track)
	}
}

// What the catalog resolved is the catalog's, and who may see it is the
// caller's: one resolution answers two callers of different reach, each
// through their own grants.
func TestOneM3UResolutionServesCallersOfDifferentReach(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	// First: the library it adds is a change to the catalog.
	blind := blindReader(t, ctx, svc, uc)
	track := fixtureItemPIDs(t, ctx, svc, uc)[0]
	it, err := svc.getVisibleItem(ctx, uc, track)
	if err != nil {
		t.Fatal(err)
	}
	doc := "#EXTM3U\n" + it.DisplayPath + "\n"
	resolves := countM3UResolves(svc)

	for _, c := range []struct {
		who     string
		as      *UserCtx
		matched int
	}{{"the administrator", uc, 1}, {"a reader granted another library", blind, 0}, {"the administrator again", uc, 1}} {
		got, err := svc.PreviewPlaylistM3U(ctx, c.as, doc)
		if err != nil {
			t.Fatal(err)
		}
		if got.Matched != c.matched || got.Matched+got.Unmatched != 1 {
			t.Errorf("%s: preview = %+v, want %d matched of one line", c.who, got, c.matched)
		}
		if c.matched == 0 && got.Lines[0].Item != nil {
			t.Errorf("%s: the hidden line carries %+v", c.who, got.Lines[0].Item)
		}
	}
	if n := resolves(); n != 1 {
		t.Fatalf("three previews resolved the document %d times, want once", n)
	}
}

// Any change to the catalog between the preview and the import resolves
// the document afresh, so the import never builds from what was true
// before: a track trashed in between is not imported.
func TestACatalogChangeResolvesAnM3UAfresh(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, _, tracks := newTrashFixture(t, "Kept", "Gone")
	doc := "#EXTM3U\n" + tracks["Kept"].path + "\n" + tracks["Gone"].path + "\n"
	resolves := countM3UResolves(svc)

	preview, err := svc.PreviewPlaylistM3U(ctx, admin, doc)
	if err != nil {
		t.Fatal(err)
	}
	if preview.Matched != 2 {
		t.Fatalf("the preview = %+v, want both lines matched", preview)
	}
	if _, err := svc.DeleteItems(ctx, admin, []string{tracks["Gone"].pid}, "trash", false); err != nil {
		t.Fatal(err)
	}
	imported, err := svc.ImportPlaylistM3U(ctx, admin, "After the trash", "", doc)
	if err != nil {
		t.Fatal(err)
	}
	if n := resolves(); n != 2 {
		t.Fatalf("a preview, a change and an import resolved the document %d times, want twice", n)
	}
	if imported.Matched != 1 || imported.Unmatched != 1 {
		t.Fatalf("the import = %+v, want the trashed line unmatched", imported)
	}
	if got := memberPIDs(t, ctx, svc, admin, imported.Playlist.PID); !samePIDs(got, []string{tracks["Kept"].pid}) {
		t.Fatalf("the import holds %v, want only %s", got, tracks["Kept"].pid)
	}
}

// The held resolutions stay within their bounds: so many documents, so
// many lines across them, for so long, and a document longer than the
// line bound is not held at all.
func TestM3UResolutionsStayBounded(t *testing.T) {
	t.Parallel()
	now := time.Unix(1_000_000, 0)
	c := &m3uResolutions{held: 2, heldLines: 5, heldFor: time.Minute, now: func() time.Time { return now }}
	key := func(doc string, pos int64) m3uKey { return m3uKey{doc: sha256.Sum256([]byte(doc)), pos: pos} }
	lines := func(n int) []playlist.M3UMatch { return make([]playlist.M3UMatch, n) }
	held := func(want ...string) {
		t.Helper()
		var got []string
		for _, doc := range []string{"a", "b", "c", "d", "e"} {
			if _, ok := c.get(key(doc, 1)); ok {
				got = append(got, doc)
			}
		}
		if strings.Join(got, ",") != strings.Join(want, ",") {
			t.Fatalf("held %v, want %v", got, want)
		}
	}

	c.put(key("a", 1), lines(2))
	c.put(key("b", 1), lines(2))
	held("a", "b")
	c.put(key("c", 1), lines(1))
	held("b", "c")
	// Four more lines are seven with both held: the older goes.
	c.put(key("d", 1), lines(4))
	held("c", "d")
	c.put(key("e", 1), lines(6))
	held("c", "d")
	if _, ok := c.get(key("c", 2)); ok {
		t.Fatal("a document held at one catalog position answered at another")
	}
	now = now.Add(time.Minute)
	held()
}
