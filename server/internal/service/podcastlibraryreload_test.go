package service

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"

	"github.com/colespringer/waxdeck/fixtures"
)

// The podcast library is found the moment the first download creates it,
// even right after a lookup missed it: a miss holds the library table's
// next reload off for a second, and the download that creates the
// library drops the table.
func TestTheFirstDownloadsPodcastLibraryIsFoundAtOnce(t *testing.T) {
	t.Parallel()
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "one", Codec: fixtures.CodecMP3, Container: fixtures.ContainerMP3, Duration: 2 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	audio, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".mp3") {
			w.Header().Set("Content-Type", "audio/mpeg")
			w.Write(audio)
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>First Show</title>
<item><title>One</title><guid>first-1</guid><enclosure url="http://%s/one.mp3" type="audio/mpeg" length="%d"/></item>
</channel></rss>`, r.Host, len(audio))
	}))
	t.Cleanup(ts.Close)
	dir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: ts.URL + "/feed.xml"})
	if err != nil {
		t.Fatal(err)
	}
	eps, _, err := svc.Episodes(ctx, uc, sub.Show.PID, "", 10)
	if err != nil || len(eps) != 1 {
		t.Fatalf("episodes = %+v (%v), want one", eps, err)
	}
	if pid, _ := svc.podcastLibrary(ctx); pid != "" {
		t.Fatalf("a podcast library %q before any download", pid)
	}
	if err := svc.QueueEpisodeFetch(ctx, uc, eps[0].PID); err != nil {
		t.Fatal(err)
	}
	svc.DrainFetchQueue(ctx)
	if pid, _ := svc.podcastLibrary(ctx); pid == "" {
		t.Error("the podcast library the first download just created reads as none")
	}
}

// A podcast library the catalog creates another way (an episode file
// imported) is found once the change feed reads its row, even right after
// a lookup missed it.
func TestAPodcastLibraryTheFeedReadsIsFoundAtOnce(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	feed := &stubFeed{kind: model.SourceRSS, n: 1, prefix: "Episode"}
	ctx, svc, _, _ := openServiceAt(t, dataDir, func(cfg *Config) {
		cfg.PodcastDir, cfg.PodcastRootName = filepath.Join(dataDir, "podcasts"), "podcasts"
		cfg.SourceProviders = []source.Provider{feed}
	})
	f := stubFeedFixture{ctx: ctx, svc: svc, uc: mustAdmin(t, svc)}
	sub := f.subscribe(t, "https://feeds.example/one", "rss")
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "one", Codec: fixtures.CodecMP3, Container: fixtures.ContainerMP3, Duration: 2 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	_, bare, _ := parseAPIPID(showEpisodePIDs(t, f, sub.Show.PID)[0])
	if pid, _ := svc.podcastLibrary(ctx); pid != "" {
		t.Fatalf("a podcast library %q before any episode landed", pid)
	}
	if _, err := svc.lib.Podcasts().ImportEpisodeFile(ctx, bare, paths[0], false); err != nil {
		t.Fatal(err)
	}
	feedCaughtUp(t, ctx, svc)
	if pid, _ := svc.podcastLibrary(ctx); pid == "" {
		t.Error("the podcast library the feed just read the creation of reads as none")
	}
}
