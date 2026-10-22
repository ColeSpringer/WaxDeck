package service

import (
	"fmt"
	"sync/atomic"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// showEpisodePIDs lists every episode of one show, newest first.
func showEpisodePIDs(t *testing.T, f stubFeedFixture, showPID string) []string {
	t.Helper()
	var out []string
	cursor := ""
	for {
		rows, next, err := f.svc.Episodes(f.ctx, f.uc, showPID, cursor, 200)
		if err != nil {
			t.Fatal(err)
		}
		for _, r := range rows {
			out = append(out, r.PID)
		}
		if next == "" {
			return out
		}
		cursor = next
	}
}

// sharedList shares a static playlist of the given members and resolves
// the link, answering the members it serves, or nil and the error.
func sharedList(t *testing.T, f stubFeedFixture, members []string) ([]ItemSummary, error) {
	t.Helper()
	pl, err := f.svc.CreatePlaylist(f.ctx, f.uc, PlaylistCreate{Name: "Mixed", Kind: string(model.PlaylistStatic), ItemPIDs: members})
	if err != nil {
		t.Fatal(err)
	}
	sh, err := f.svc.CreateShare(f.ctx, f.uc, pl.PID, 0, false, 0)
	if err != nil {
		t.Fatal(err)
	}
	_, id, _ := parseAPIPID(sh.ID)
	pub, err := f.svc.ResolveShare(f.ctx, string(id))
	if err != nil {
		return nil, err
	}
	return pub.Items, nil
}

// A list's link counts only what it can serve against its member cap:
// a private show's episodes are left out first, so a list that leads
// with hundreds of them still serves what follows.
func TestASharedListCountsOnlyServableMembersAgainstItsCap(t *testing.T) {
	t.Parallel()
	feed := &stubFeed{kind: model.SourceRSS, n: 500, prefix: "Episode"}
	f := openStubFeeds(t, feed)
	paid := f.subscribe(t, "https://feeds.example/paid", "rss")
	open := f.subscribe(t, "https://feeds.example/open", "rss")
	_, paidShow, _ := parseAPIPID(paid.Show.PID)
	f.svc.markShowPrivate(f.ctx, string(paidShow))

	private := showEpisodePIDs(t, f, paid.Show.PID)
	if len(private) != 500 {
		t.Fatalf("the paid show lists %d episodes, want 500", len(private))
	}
	audible := showEpisodePIDs(t, f, open.Show.PID)[0]
	items, err := sharedList(t, f, append(append([]string{}, private...), audible))
	if err != nil {
		t.Fatalf("a list ending in one audible episode after 500 private ones: %v", err)
	}
	if len(items) != 1 || items[0].PID != audible {
		t.Errorf("served %d members (%+v), want the one audible episode", len(items), items)
	}

	if _, err := sharedList(t, f, private[:3]); KindOf(err) != KindNotFound {
		t.Errorf("a list of private episodes only: %v, want not-found", err)
	}
}

// Resolving a list's link reads each show of its episodes once, whether or
// not the process already knows the shows' sources: the privacy filter and
// the check that an episode has audio to relay share the read.
func TestResolvingASharedListReadsEachShowOnce(t *testing.T) {
	t.Parallel()
	const shows, perShow = 4, 3
	feed := &stubFeed{kind: model.SourceRSS, n: perShow, prefix: "Episode"}
	f := openStubFeeds(t, feed)
	var members []string
	for i := range shows {
		sub := f.subscribe(t, fmt.Sprintf("https://feeds.example/show-%d", i), "rss")
		members = append(members, showEpisodePIDs(t, f, sub.Show.PID)...)
	}
	pl, err := f.svc.CreatePlaylist(f.ctx, f.uc, PlaylistCreate{Name: "Mixed", Kind: string(model.PlaylistStatic), ItemPIDs: members})
	if err != nil {
		t.Fatal(err)
	}
	sh, err := f.svc.CreateShare(f.ctx, f.uc, pl.PID, 0, false, 0)
	if err != nil {
		t.Fatal(err)
	}
	_, id, _ := parseAPIPID(sh.ID)
	var fail atomic.Bool
	reads := countShowReads(f.svc, &fail)

	for _, process := range []string{"cold", "warm"} {
		if process == "cold" {
			f.svc.showSources.Clear()
		}
		reads.Store(0)
		pub, err := f.svc.ResolveShare(f.ctx, string(id))
		if err != nil {
			t.Fatal(err)
		}
		if got := reads.Load(); got != shows {
			t.Errorf("%s: resolving read the shows %d times, want once each (%d)", process, got, shows)
		}
		for _, it := range pub.Items {
			if pub.Audio[it.PID] != ShareAudioRelay {
				t.Errorf("%s: %s plays %q, want relay", process, it.Title, pub.Audio[it.PID])
			}
		}
		if len(pub.Items) != shows*perShow {
			t.Errorf("%s: served %d members, want %d", process, len(pub.Items), shows*perShow)
		}
	}
}
