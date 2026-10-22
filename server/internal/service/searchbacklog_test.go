package service

import (
	"fmt"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
)

// grantedSearcher is a catalog whose one show has episodes episodes, the
// oldest of them fetched, searched by an account granted the podcast
// library alone that follows the show, with the candidate pool shrunk to
// three. tracks music tracks matching the same word sit in a library the
// account is not granted.
type grantedSearcher struct {
	f        stubFeedFixture
	listener *UserCtx
	show     string
	fetched  string
}

func newGrantedSearcher(t *testing.T, episodes, tracks int) grantedSearcher {
	t.Helper()
	feed := &stubFeed{kind: model.SourceRSS, n: episodes, prefix: "Wax"}
	f := openStubFeeds(t, feed)
	f.svc.searchCandidates = 3
	held := f.subscribe(t, "https://feeds.example/held", "rss")
	all := showEpisodePIDs(t, f, held.Show.PID)
	fetched := all[len(all)-1]
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "wax", Codec: fixtures.CodecMP3, Container: fixtures.ContainerMP3, Duration: 2 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	_, bare, _ := parseAPIPID(fetched)
	if _, err := f.svc.lib.Podcasts().ImportEpisodeFile(f.ctx, bare, paths[0], false); err != nil {
		t.Fatal(err)
	}
	if tracks > 0 {
		var music string
		for _, r := range f.svc.libraryRoots() {
			if r.Name == "lib" {
				music = r.Path
			}
		}
		specs := make([]fixtures.Spec, 0, tracks)
		for i := range tracks {
			specs = append(specs, fixtures.Spec{
				Name: fmt.Sprintf("wax-track-%d", i), Codec: fixtures.CodecFLAC,
				Tags: map[string]string{"TITLE": fmt.Sprintf("Wax Track %d", i), "ARTIST": "Wax Band", "ALBUM": "Wax Album"},
			})
		}
		if _, err := fixtures.Generate(music, specs...); err != nil {
			t.Fatal(err)
		}
		if _, err := f.svc.lib.Scan(f.ctx, waxbin.ScanRequest{}); err != nil {
			t.Fatal(err)
		}
	}
	podcastLib, _ := f.svc.podcastLibrary(f.ctx)
	if podcastLib == "" {
		t.Fatal("no podcast library after a fetch")
	}
	acct, err := f.svc.CreateAccount(f.ctx, AccountCreate{
		Username: "listener", Password: "correct-horse", AccessMode: "granted",
		LibraryPIDs: []string{apiPID(PrefixLibrary, model.PID(podcastLib))},
	})
	if err != nil {
		t.Fatal(err)
	}
	listener, err := f.svc.UserCtx(f.ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := f.svc.Subscribe(f.ctx, listener, SubscribeRequest{URL: "https://feeds.example/held", SourceType: "rss"}); err != nil {
		t.Fatal(err)
	}
	return grantedSearcher{f: f, listener: listener, show: held.Show.PID, fetched: fetched}
}

func (g grantedSearcher) search(t *testing.T) SearchResults {
	t.Helper()
	res, err := g.f.svc.Search(g.f.ctx, g.listener, "Wax", 20)
	if err != nil {
		t.Fatal(err)
	}
	return res
}

func (g grantedSearcher) found(res SearchResults) bool {
	for _, hit := range res.Episodes {
		if hit.PID == g.fetched {
			return true
		}
	}
	return false
}

// An account granted the podcast library finds a fetched episode by
// search however many newer matches the libraries it is not granted
// hold, and those matches never make its answer read as cut short: only
// the unfetched backlog, which no library scope reaches, is searched
// beyond what it is granted.
func TestAGrantedSearchKeepsItsFetchedEpisodes(t *testing.T) {
	t.Parallel()
	g := newGrantedSearcher(t, 1, 5)
	res := g.search(t)
	if !g.found(res) {
		t.Errorf("the fetched episode is not a hit: %+v", res.Episodes)
	}
	if res.Truncated {
		t.Error("the answer reads as cut short by matches the account cannot see")
	}
}

// The unfetched backlog is the account's own to see, so a backlog with
// more matches than the pool takes says the answer was cut short, as it
// does for an administrator searching the same catalog.
func TestAGrantedSearchSaysWhenItsBacklogOverflows(t *testing.T) {
	t.Parallel()
	g := newGrantedSearcher(t, 6, 0)
	res := g.search(t)
	if !g.found(res) {
		t.Errorf("the fetched episode is not a hit: %+v", res.Episodes)
	}
	if !res.Truncated {
		t.Error("five unfetched matches over a pool of three read as a complete answer")
	}
}
