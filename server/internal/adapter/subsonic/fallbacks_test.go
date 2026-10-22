package subsonic

import (
	"context"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// settle waits for the catalog positions to hold still, so a test about
// what is kept under one reads one position throughout.
func settle(t *testing.T, h *Handler) {
	t.Helper()
	ctx := context.Background()
	at := func() [2]int64 {
		plays, _ := h.svc.CatalogPlaysSeq(ctx)
		return [2]int64{plays, h.svc.CatalogContentSeq(ctx)}
	}
	last, stable := at(), 0
	for deadline := time.Now().Add(10 * time.Second); stable < 5; {
		if time.Now().After(deadline) {
			t.Fatal("the catalog positions never held still")
		}
		time.Sleep(20 * time.Millisecond)
		if now := at(); now == last {
			stable++
		} else {
			last, stable = now, 0
		}
	}
}

// fellBack is a watch whose reads fell back while fell holds.
func fellBack(fell *atomic.Bool) func(context.Context) (context.Context, func() bool) {
	return func(ctx context.Context) (context.Context, func() bool) {
		return ctx, fell.Load
	}
}

// heldIndexes counts the indexes the handler keeps.
func heldIndexes(h *Handler) int {
	h.idxMu.Lock()
	defer h.idxMu.Unlock()
	n := len(h.idxScoped)
	if h.idxShared != nil {
		n++
	}
	return n
}

// An index whose build saw a read fall back is served to the request that
// built it and never kept; the next build, over reads that held, is.
func TestAnIndexOverAFallbackIsNotKept(t *testing.T) {
	h, uc := serviceHandler(t)
	settle(t, h)
	var fell atomic.Bool
	h.watch = fellBack(&fell)
	ctx := context.Background()
	fell.Store(true)
	if _, err := h.index(ctx, uc); err != nil {
		t.Fatal(err)
	}
	if n := heldIndexes(h); n != 0 {
		t.Fatalf("an index built over a fallback was kept (%d held)", n)
	}
	fell.Store(false)
	if _, err := h.index(ctx, uc); err != nil {
		t.Fatal(err)
	}
	if n := heldIndexes(h); n != 1 {
		t.Fatalf("an index built over reads that held was not kept (%d held)", n)
	}
}

// A newest page read over a fallback fails the request that asked and
// leaves the fold where it was, so the next request reads the list again
// and answers it in its own order.
func TestANewestPageOverAFallbackIsNotKept(t *testing.T) {
	idx := buildIndex([]track{
		{PID: "t1", AlbumArtist: "X", Album: "A"}, {PID: "t2", AlbumArtist: "X", Album: "B"},
	}, nil)
	var fell atomic.Bool
	h := &Handler{watch: fellBack(&fell), pages: func(uc *service.UserCtx, list, folder string) pageSource {
		return func(ctx context.Context, cursor string) ([]string, string, error) {
			if fell.Load() {
				// What a rule compiled to match-nothing leaves of the list.
				return nil, "", nil
			}
			return []string{"t2", "t1"}, "", nil
		}
	}}
	newest := func() ([]*album, error) {
		r := httptest.NewRequest("GET", "/rest/getAlbumList2?type=newest", nil)
		if err := r.ParseForm(); err != nil {
			t.Fatal(err)
		}
		albums, _, ref, err := h.albumList(context.Background(), r, &service.UserCtx{}, idx)
		if ref != nil {
			t.Fatalf("refused: %+v", ref)
		}
		return albums, err
	}
	fell.Store(true)
	if albums, err := newest(); err == nil {
		t.Fatalf("a page read over a fallback answered [%s]", albumNames(albums))
	}
	if idx.newest.done {
		t.Fatal("a page read over a fallback marked the fold done")
	}
	fell.Store(false)
	if albums, err := newest(); err != nil || albumNames(albums) != "B, A" {
		t.Fatalf("the next request = [%s] (%v), want [B, A]", albumNames(albums), err)
	}
}

// A playlist's totals counted over a fallback answer the request that
// counted them and are not kept for the next one.
func TestPlaylistTotalsOverAFallbackAreNotKept(t *testing.T) {
	h, uc := serviceHandler(t)
	var fell atomic.Bool
	h.watch = fellBack(&fell)
	ctx := context.Background()
	pl, err := h.svc.CreatePlaylist(ctx, uc, service.PlaylistCreate{Name: "Counted", Kind: "static"})
	if err != nil {
		t.Fatal(err)
	}
	held := func() int {
		h.totalsMu.Lock()
		defer h.totalsMu.Unlock()
		return len(h.totals)
	}
	fell.Store(true)
	if _, _, err := h.playlistTotals(ctx, uc, uc.ScopeKey(), pl); err != nil {
		t.Fatal(err)
	}
	if n := held(); n != 0 {
		t.Fatalf("totals counted over a fallback were kept (%d held)", n)
	}
	fell.Store(false)
	if _, _, err := h.playlistTotals(ctx, uc, uc.ScopeKey(), pl); err != nil {
		t.Fatal(err)
	}
	if n := held(); n != 1 {
		t.Fatalf("totals counted over reads that held were not kept (%d held)", n)
	}
}
