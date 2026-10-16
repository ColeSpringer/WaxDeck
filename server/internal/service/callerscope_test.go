package service

import (
	"context"
	"fmt"
	"testing"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// scopedCount runs the caller scope over the whole catalog and answers how
// many items it lets through, which also proves the node compiles.
func scopedCount(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) (query.Query, int) {
	t.Helper()
	q := visibleItems().WhereNode(svc.callerScopeNode(ctx, uc, svc.newSubscriptionFilter(uc), true)).Build()
	page, err := svc.lib.QueryPage(ctx, q, "", 100, false, model.PID(uc.CatalogPID))
	if err != nil {
		t.Fatalf("running the caller scope: %v", err)
	}
	return q, len(page.Items)
}

// A caller who follows no show is offered no episode, and everything that
// is not an episode passes: the follow arm is an empty membership, which
// matches nothing, rather than no condition, which would match every
// episode. A caller granted no library is offered nothing at all.
func TestCallerScopeNodeFailsClosedWithoutSubscriptions(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	all := len(fixtureItemPIDs(t, ctx, svc, uc))

	q, n := scopedCount(t, ctx, svc, uc)
	shows := condsOn(t, q, "podcast_pid")
	if len(shows) != 1 || shows[0].Op != query.OpIn || len(shows[0].Values) != 0 {
		t.Fatalf("follow arm = %+v, want one empty membership", shows)
	}
	kinds := condsOn(t, q, "kind")
	if len(kinds) != 1 || kinds[0].Op != query.OpIsNot || kinds[0].Value != string(model.KindEpisode) {
		t.Fatalf("other arm = %+v, want kind is not episode", kinds)
	}
	if libs := condsOn(t, q, "library"); len(libs) != 0 {
		t.Errorf("a caller who sees every library carries a grant clause: %+v", libs)
	}
	if n != all {
		t.Errorf("the scope lets %d of %d tracks through, want all", n, all)
	}

	ungranted := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, Libraries: map[string]bool{}}
	q, n = scopedCount(t, ctx, svc, ungranted)
	if libs := condsOn(t, q, "library"); len(libs) != 1 || libs[0].Op != query.OpIn || len(libs[0].Values) != 0 {
		t.Fatalf("grant clause = %+v, want one empty membership", libs)
	}
	if n != 0 {
		t.Errorf("a caller granted nothing is offered %d items, want none", n)
	}
}

// A caller following more shows than one membership condition may hold,
// or granted more libraries, still gets a scope the catalog compiles: the
// set is chunked at the cap.
func TestCallerScopeNodeChunksPast500Shows(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	all := len(fixtureItemPIDs(t, ctx, svc, uc))
	for i := range 1001 {
		if err := svc.db.UpsertSubscription(ctx, wdb.Subscription{UserID: uc.ID, ShowPID: fmt.Sprintf("show-%04d", i)}); err != nil {
			t.Fatal(err)
		}
	}
	q, n := scopedCount(t, ctx, svc, uc)
	chunks := condsOn(t, q, "podcast_pid")
	held := 0
	for _, c := range chunks {
		if len(c.Values) > 500 {
			t.Errorf("a membership holds %d shows, over the cap", len(c.Values))
		}
		held += len(c.Values)
	}
	if len(chunks) != 3 || held != 1001 {
		t.Fatalf("1001 shows chunked into %d memberships holding %d, want 3 holding all", len(chunks), held)
	}
	if n != all {
		t.Errorf("the scope lets %d of %d tracks through, want all", n, all)
	}

	wide := &UserCtx{ID: uc.ID, CatalogPID: uc.CatalogPID, Libraries: map[string]bool{}}
	for i := range 501 {
		wide.Libraries[fmt.Sprintf("lib-%04d", i)] = true
	}
	q, _ = scopedCount(t, ctx, svc, wide)
	if libs := condsOn(t, q, "library"); len(libs) != 2 {
		t.Errorf("501 grants chunked into %d memberships, want 2", len(libs))
	}

	// The followed-episodes shelves scope by the same set and compile too.
	for _, f := range []SubscribedEpisodeFilter{EpisodesLatest, EpisodesUnplayed, EpisodesInProgress} {
		if _, _, err := svc.SubscribedEpisodes(ctx, uc, f, "", 20); err != nil {
			t.Errorf("%s episodes for a follower of 1001 shows: %v", f, err)
		}
	}
}

// A listing reads the caller's follows once, for its query, and hands
// the same set to the check its rows get afterwards; a listing whose
// filter already leaves episodes out carries no follow arm and reads
// nothing for one.
func TestListingQueryReadsTheFollowSetOnlyWhereEpisodesCanList(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	for _, tc := range []struct {
		name     string
		filter   ItemFilter
		episodes bool
	}{
		{"everything", ItemFilter{}, true},
		{"podcasts", ItemFilter{MediaType: "podcast"}, true},
		{"music", ItemFilter{MediaType: "music"}, false},
		{"audiobooks", ItemFilter{MediaType: "audiobook"}, false},
		{"an artist", ItemFilter{Facet: "artist", FacetKey: "ar-unknown"}, false},
	} {
		subs := svc.newSubscriptionFilter(uc)
		b, _, err := svc.listingQuery(ctx, uc, visibleItems(), tc.filter, subs)
		if err != nil {
			t.Fatalf("%s: %v", tc.name, err)
		}
		if arm := condsOn(t, b.Build(), "podcast_pid"); (len(arm) > 0) != tc.episodes {
			t.Errorf("%s: follow arm %+v, want one: %v", tc.name, arm, tc.episodes)
		}
		if subs.loaded != tc.episodes {
			t.Errorf("%s: follow set read %v, want %v", tc.name, subs.loaded, tc.episodes)
		}
	}
}
