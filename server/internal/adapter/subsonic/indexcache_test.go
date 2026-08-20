package subsonic

import (
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A restricted account's grants are the whole key, and an account
// granted nothing must not read as an administrator - the empty scope
// is the full-visibility one.
func TestIndexScopeKeysOnGrantsAlone(t *testing.T) {
	admin := indexScope(&service.UserCtx{AllLibraries: true})
	if admin != "" {
		t.Fatalf("full visibility scope = %q, want empty", admin)
	}
	none := indexScope(&service.UserCtx{})
	if none == admin {
		t.Fatal("an account granted no library shares the administrator's index")
	}
	// Grant order is a map's, so the key has to sort.
	a := indexScope(&service.UserCtx{Libraries: map[string]bool{"lib-a": true, "lib-b": true}})
	b := indexScope(&service.UserCtx{Libraries: map[string]bool{"lib-b": true, "lib-a": true}})
	if a != b {
		t.Fatalf("the same grants keyed two ways: %q vs %q", a, b)
	}
	if c := indexScope(&service.UserCtx{Libraries: map[string]bool{"lib-a": true}}); c == a {
		t.Fatal("a narrower grant set shares the wider one's index")
	}
	// A revoked grant is a false value, not an absent key.
	if d := indexScope(&service.UserCtx{Libraries: map[string]bool{"lib-a": true, "lib-b": false}}); d != indexScope(&service.UserCtx{Libraries: map[string]bool{"lib-a": true}}) {
		t.Fatalf("a revoked grant still keys the index: %q", d)
	}
}

// The point of the scoped cache: a client walking search3 at rising
// offsets pays one sweep, not one per page.
func TestScopedIndexIsReusedAcrossPages(t *testing.T) {
	h := &Handler{}
	scope := indexScope(&service.UserCtx{Libraries: map[string]bool{"lib-a": true}})
	built := &index{}
	if got := h.cachedIndex(7, scope); got != nil {
		t.Fatal("a cold cache answered")
	}
	h.cacheIndex(7, scope, built)
	for page := range 3 {
		if got := h.cachedIndex(7, scope); got != built {
			t.Fatalf("page %d rebuilt the index", page)
		}
	}
}

func TestScopedIndexDoesNotCrossGrantSets(t *testing.T) {
	h := &Handler{}
	a := indexScope(&service.UserCtx{Libraries: map[string]bool{"lib-a": true}})
	b := indexScope(&service.UserCtx{Libraries: map[string]bool{"lib-b": true}})
	h.cacheIndex(7, a, &index{})
	if got := h.cachedIndex(7, b); got != nil {
		t.Fatal("a different grant set read another's index")
	}
	if got := h.cachedIndex(7, ""); got != nil {
		t.Fatal("a full-visibility caller read a restricted index")
	}
}

// One tail comparison invalidates every generation, restricted and
// shared alike: the catalog moved, so they are all stale together.
func TestCatalogChangeDropsEveryIndex(t *testing.T) {
	h := &Handler{}
	scope := indexScope(&service.UserCtx{Libraries: map[string]bool{"lib-a": true}})
	h.cacheIndex(7, "", &index{})
	h.cacheIndex(7, scope, &index{})
	if h.cachedIndex(7, "") == nil || h.cachedIndex(7, scope) == nil {
		t.Fatal("entries were not cached at all")
	}
	if got := h.cachedIndex(8, scope); got != nil {
		t.Fatal("a moved catalog served a stale scoped index")
	}
	h.cacheIndex(8, scope, &index{})
	if got := h.cachedIndex(8, ""); got != nil {
		t.Fatal("the shared index survived the catalog change")
	}
}

// Re-caching a scope the map already holds replaces it, and must not
// evict a neighbour to make room it does not need.
func TestScopedIndexRecacheEvictsNothing(t *testing.T) {
	h := &Handler{}
	scopes := make([]string, 0, idxScopedCap)
	for i := range idxScopedCap {
		scope := indexScope(&service.UserCtx{Libraries: map[string]bool{
			string(rune('a' + i)): true,
		}})
		scopes = append(scopes, scope)
		h.cacheIndex(7, scope, &index{})
	}
	// At the cap, and every scope still held.
	h.cacheIndex(7, scopes[0], &index{})
	if len(h.idxScoped) != idxScopedCap {
		t.Fatalf("scoped entries = %d, want the cap of %d", len(h.idxScoped), idxScopedCap)
	}
	for _, scope := range scopes {
		if h.idxScoped[scope] == nil {
			t.Fatalf("re-caching an entry evicted %q, which needed no room", scope)
		}
	}
}

// The cap is a memory bound; hitting it must not throw away every
// entry, because each one costs a whole-catalog sweep to rebuild.
func TestScopedIndexCapEvictsOneAtATime(t *testing.T) {
	h := &Handler{}
	for i := range idxScopedCap + 3 {
		h.cacheIndex(7, indexScope(&service.UserCtx{Libraries: map[string]bool{
			string(rune('a' + i)): true,
		}}), &index{})
	}
	if len(h.idxScoped) != idxScopedCap {
		t.Fatalf("scoped entries = %d, want the cap of %d", len(h.idxScoped), idxScopedCap)
	}
	// The most recent write survives; only room for it was made.
	last := indexScope(&service.UserCtx{Libraries: map[string]bool{
		string(rune('a' + idxScopedCap + 2)): true,
	}})
	if h.idxScoped[last] == nil {
		t.Fatal("the entry the cap was enforced for was itself evicted")
	}
}
