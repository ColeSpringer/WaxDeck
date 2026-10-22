package service

import (
	"fmt"
	"html"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
	"unicode/utf8"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// A feed's title is cut to its first thousand characters, never partway
// through a character.
func TestClipFeedTitleKeepsTheFirstThousandCharacters(t *testing.T) {
	long := strings.Repeat("é", 1500)
	if got := clipFeedTitle(long); got != strings.Repeat("é", 1000) {
		t.Errorf("a 1500-character title clips to %d characters, want the first 1000", utf8.RuneCountInString(got))
	}
	short := strings.Repeat("é", 1000)
	if got := clipFeedTitle(short); got != short {
		t.Errorf("a 1000-character title clips to %d characters, want it whole", utf8.RuneCountInString(got))
	}
}

// A feed can carry a title as long as the feed itself. Every answer that
// names the show or an episode gives the first thousand characters: the
// show and its subscription, its card, the episode rows and detail, a
// search hit, an item row, the queue, a share, the listening log and top
// shows, and the inbox's notices.
func TestFeedTitlesAreClippedWhereverTheyAreShown(t *testing.T) {
	showTitle, episodeTitle, laterTitle := "Show "+strings.Repeat("é", 5000), "Episode zebra "+strings.Repeat("ü", 5000), "Later "+strings.Repeat("ø", 5000)
	var syncs, broken atomic.Int32
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".mp3") {
			w.Header().Set("Content-Type", "audio/mpeg")
			_, _ = w.Write([]byte("ID3\x04\x00\x00\x00\x00\x00\x00"))
			return
		}
		if broken.Load() != 0 {
			http.Error(w, "down", http.StatusInternalServerError)
			return
		}
		later := ""
		if syncs.Add(1) > 1 {
			later = fmt.Sprintf(`<item><title>%s</title><guid>clip-2</guid><enclosure url="http://%s/two.mp3" type="audio/mpeg" length="10"/></item>`,
				html.EscapeString(laterTitle), r.Host)
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>%s</title>%s
<item><title>%s</title><guid>clip-1</guid><pubDate>%s</pubDate><enclosure url="http://%s/one.mp3" type="audio/mpeg" length="10"/></item>
</channel></rss>`, html.EscapeString(showTitle), later, html.EscapeString(episodeTitle),
			time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z), r.Host)
	}))
	t.Cleanup(host.Close)
	dir := t.TempDir()
	ctx, svc, admin, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	clipped := func(what, got, full string) {
		t.Helper()
		if n := utf8.RuneCountInString(got); n != 1000 || !strings.HasPrefix(full, got) {
			t.Errorf("%s gives %d characters of the title, want its first 1000", what, n)
		}
	}
	clippedAfter := func(what, got, prefix, full string) {
		t.Helper()
		rest, ok := strings.CutPrefix(got, prefix)
		if !ok {
			t.Errorf("%s = %.40q..., want it to start %q", what, got, prefix)
			return
		}
		clipped(what, rest, full)
	}

	sub, _, err := svc.Subscribe(ctx, admin, SubscribeRequest{URL: host.URL + "/feed.xml"})
	if err != nil {
		t.Fatal(err)
	}
	clipped("the subscribe answer", sub.Show.Title, showTitle)
	detail, err := svc.PodcastDetailFor(ctx, admin, sub.Show.PID)
	if err != nil {
		t.Fatal(err)
	}
	clipped("the show detail", detail.Show.Title, showTitle)
	subs, _, err := svc.Subscriptions(ctx, admin, "", 10, false)
	if err != nil || len(subs) != 1 {
		t.Fatalf("subscriptions = %+v (%v), want one", subs, err)
	}
	clipped("the subscription list", subs[0].Show.Title, showTitle)
	cards, _, err := svc.EntityCards(ctx, admin, []string{sub.Show.PID})
	if err != nil || len(cards) != 1 {
		t.Fatalf("cards = %+v (%v), want the show's", cards, err)
	}
	clipped("the show's card", cards[0].Title, showTitle)

	eps, _, err := svc.Episodes(ctx, admin, sub.Show.PID, "", 10)
	if err != nil || len(eps) != 1 {
		t.Fatalf("episodes = %+v (%v), want one", eps, err)
	}
	ep := eps[0]
	clipped("the episode row", ep.Title, episodeTitle)
	clipped("the episode row's show", ep.Artist, showTitle)
	clipped("the episode row's album", ep.Album, showTitle)
	epDetail, err := svc.EpisodeDetailFor(ctx, admin, ep.PID)
	if err != nil {
		t.Fatal(err)
	}
	clipped("the episode detail", epDetail.Title, episodeTitle)
	found, err := svc.Search(ctx, admin, "zebra", 10)
	if err != nil || len(found.Episodes) != 1 {
		t.Fatalf("search = %+v (%v), want the episode", found.Episodes, err)
	}
	clipped("the search hit", found.Episodes[0].Title, episodeTitle)
	clipped("the search hit's show", found.Episodes[0].Subtitle, showTitle)
	_, bareEp, _ := parseAPIPID(ep.PID)
	it, err := svc.lib.Get(ctx, bareEp)
	if err != nil {
		t.Fatal(err)
	}
	row := summary(it)
	clipped("an item row", row.Title, episodeTitle)
	clipped("an item row's artist", row.Artist, showTitle)
	queue, err := svc.QueueEntries(ctx, admin.ID, []string{ep.PID})
	if err != nil || len(queue) != 1 {
		t.Fatalf("queue = %+v (%v), want the episode", queue, err)
	}
	clipped("the queue entry", queue[0].Title, episodeTitle)
	clipped("the queue entry's artist", queue[0].Artist, showTitle)

	share, err := svc.CreateShare(ctx, admin, ep.PID, 0, false, 0)
	if err != nil {
		t.Fatal(err)
	}
	clipped("the new share", share.TargetTitle, episodeTitle)
	shares, err := svc.Shares(ctx, admin, false, "", 10)
	if err != nil || len(shares.Shares) != 1 {
		t.Fatalf("shares = %+v (%v), want one", shares, err)
	}
	clipped("the share listing", shares.Shares[0].TargetTitle, episodeTitle)
	public, err := svc.ResolveShare(ctx, strings.TrimPrefix(share.ID, "sh-"))
	if err != nil {
		t.Fatal(err)
	}
	clipped("the share page's title", public.Title, episodeTitle)
	clipped("the share page's subtitle", public.Subtitle, showTitle)

	if _, err := svc.db.InsertListens(ctx, []wdb.ListenSession{{UserID: admin.ID, SessionID: "clip-1",
		ItemPID: string(bareEp), MediaType: "podcast", StartedAt: time.Now().Add(-time.Minute), MsPlayed: 60_000}}); err != nil {
		t.Fatal(err)
	}
	log, err := svc.ListenLog(ctx, admin, "", "", 10)
	if err != nil || len(log.Sessions) != 1 {
		t.Fatalf("listening log = %+v (%v), want the session", log, err)
	}
	clipped("the listening log", log.Sessions[0].Title, episodeTitle)
	clipped("the listening log's artist", log.Sessions[0].Artist, showTitle)
	top, err := svc.TopListFor(ctx, admin, "shows", "30d", 10)
	if err != nil || len(top.Entries) != 1 {
		t.Fatalf("top shows = %+v (%v), want the show", top, err)
	}
	clipped("the top shows", top.Entries[0].Name, showTitle)

	if err := svc.QueueEpisodeFetch(ctx, admin, ep.PID); err != nil {
		t.Fatal(err)
	}
	svc.DrainFetchQueue(ctx)
	_, bareShow, _ := parseAPIPID(sub.Show.PID)
	if _, err := svc.syncShow(ctx, bareShow, syncOwn); err != nil {
		t.Fatal(err)
	}
	broken.Store(1)
	for range feedDisableAfter {
		_, _ = svc.syncShow(ctx, bareShow, syncOwn)
	}
	page, err := svc.Notifications(ctx, admin, "", 100)
	if err != nil {
		t.Fatal(err)
	}
	said := map[string]bool{}
	for _, n := range page.Notifications {
		said[n.Event] = true
		switch n.Event {
		case "episode-downloaded":
			clippedAfter("the fetched notice's title", n.Title, "Episode fetched: ", episodeTitle)
			clipped("the fetched notice's body", n.Body, showTitle)
		case "episode-arrived":
			clippedAfter("the arrival notice's title", n.Title, "New episode: ", showTitle)
			clipped("the arrival notice's body", n.Body, laterTitle)
		case "feed-disabled":
			clippedAfter("the disabled notice's title", n.Title, "Podcast feed disabled: ", showTitle)
			if body, _, _ := strings.Cut(n.Body, " failed "); body != clipFeedTitle(showTitle) {
				t.Errorf("the disabled notice's body names %d characters of the show, want its first 1000", utf8.RuneCountInString(body))
			}
		}
	}
	for _, event := range []string{"episode-downloaded", "episode-arrived", "feed-disabled"} {
		if !said[event] {
			t.Errorf("the inbox holds no %s notice: %+v", event, page.Notifications)
		}
	}
}
