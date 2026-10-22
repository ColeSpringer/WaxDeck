package service

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// downThenUp is a feed host that answers 503 to its first failures
// requests and a feed after them, counting every request.
func downThenUp(t *testing.T, failures int32) (string, *atomic.Int32) {
	t.Helper()
	var hits atomic.Int32
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if hits.Add(1) <= failures {
			http.Error(w, "down", http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Back</title>
<item><title>One</title><guid>back-1</guid><enclosure url="http://%s/one.mp3" type="audio/mpeg" length="1"/></item>
</channel></rss>`, r.Host)
	}))
	t.Cleanup(ts.Close)
	return ts.URL + "/feed.xml", &hits
}

// A parked feed belongs to an account that can sign in. Once that
// account is disabled, its parked feeds are dropped rather than fetched
// and landed for it.
func TestADisabledAccountsParkedFeedsAreDropped(t *testing.T) {
	ctx, svc, _, _ := openPodcastFixture(t)
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "bob", Password: "correct-horse-2"})
	if err != nil {
		t.Fatal(err)
	}
	bob, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	feed, hits := downThenUp(t, 1)
	outcomes, err := svc.GpodderApplyChanges(ctx, bob, "phone", []string{feed}, nil)
	if err != nil || outcomes[feed] != GpodderParked {
		t.Fatalf("outcomes = %v (%v), want the feed parked", outcomes, err)
	}
	off := true
	if _, err := svc.UpdateAccount(ctx, bob.ID, AccountUpdate{Disabled: &off}); err != nil {
		t.Fatal(err)
	}

	svc.RetryPendingGpodderAt(ctx, time.Now().Add(6*time.Minute))
	if got := hits.Load(); got != 1 {
		t.Errorf("the host saw %d requests, want none after the park", got)
	}
	if subs, err := svc.db.SubscriptionsByUser(ctx, bob.ID); err != nil || len(subs) != 0 {
		t.Errorf("the disabled account's subscriptions = %+v (%v), want none", subs, err)
	}
	if parked, err := svc.db.GpodderParks(ctx, bob.ID); err != nil || len(parked) != 0 {
		t.Errorf("the disabled account's parked feeds = %+v (%v), want them dropped", parked, err)
	}
}

// An action stamped before a download read it but committed after is in
// the next download: the cursor trails the writes it may not have seen.
func TestAnActionCommittedAfterAPollIsInTheNext(t *testing.T) {
	ctx, svc, uc, _ := openPodcastFixture(t)
	stamp := time.Now().Unix()
	arrived, release := stallAt(t, "record")
	recorded := make(chan error, 1)
	go func() {
		recorded <- svc.GpodderRecordActions(ctx, uc, []wdb.GpodderAction{{
			PodcastURL: "https://feeds.example/a.xml", EpisodeURL: "https://feeds.example/1.mp3",
			DeviceID: "phone", Action: "download", UploadedSec: stamp,
		}})
	}()
	<-arrived
	// The poll lands in a later second than the stamp, which is where a
	// cursor of "now, less a second" took the stamp's second for read.
	time.Sleep(time.Until(time.Unix(stamp+1, 0).Add(20 * time.Millisecond)))
	_, cursor, err := svc.GpodderActionsSince(ctx, uc, "", 0, "", "")
	if err != nil {
		t.Fatal(err)
	}
	release()
	if err := <-recorded; err != nil {
		t.Fatal(err)
	}
	rows, _, err := svc.GpodderActionsSince(ctx, uc, "", cursor, "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 {
		t.Fatalf("actions after cursor %d = %d, want the late commit stamped at %d", cursor, len(rows), stamp)
	}
}

// A recorded time before 1970 cannot be told in nanoseconds without
// wrapping, so it reads as now, as a time in the future does.
func TestARecordedTimeOutsideTheClockReadsAsNow(t *testing.T) {
	t.Parallel()
	before := time.Now().UnixNano()
	for _, at := range []time.Time{
		time.Date(1600, 1, 1, 0, 0, 0, 0, time.UTC),
		time.Date(1969, 12, 31, 0, 0, 0, 0, time.UTC),
		time.Now().Add(time.Hour),
	} {
		if got := clampRecorded(at); got < before || got > time.Now().UnixNano() {
			t.Errorf("clampRecorded(%v) = %d, want now", at, got)
		}
	}
	if past := time.Now().Add(-time.Hour); clampRecorded(past) != past.UnixNano() {
		t.Error("a recorded time an hour ago moved")
	}
}

// An account that cannot see the podcast library is refused whatever the
// feed, a show the catalog already holds included: answered as permanent
// and said once, with no park, one inbox row however many feeds and syncs
// it covers, and no feed URL in any log line along the way.
func TestAnAccountRefusalIsSaidOnce(t *testing.T) {
	var logged lockedBuffer
	dir := t.TempDir()
	ctx, svc, admin, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
		cfg.Logger = slog.New(slog.NewTextHandler(&logged, &slog.HandlerOptions{Level: slog.LevelDebug}))
	})
	feed, hits := downThenUp(t, 0)
	// A show the catalog already holds, one of its episodes fetched so the
	// podcast library exists and the refusal is the missing grant.
	known, _, err := svc.Subscribe(ctx, admin, SubscribeRequest{URL: feed})
	if err != nil {
		t.Fatal(err)
	}
	fetchOneEpisode(t, ctx, svc, admin, known.Show.PID)
	if pid, _ := svc.podcastLibrary(ctx); pid == "" {
		t.Fatal("no podcast library after a fetch")
	}
	uc := grantedListener(t, ctx, svc, "carol", "configured")

	asked := []string{feed, "https://feeds.example/s3cr3t-token/one.xml", "https://other.example/s3cr3t-token/two.xml"}
	for range 3 {
		outcomes, err := svc.GpodderApplyChanges(ctx, uc, "phone", asked, nil)
		if err != nil {
			t.Fatal(err)
		}
		for _, u := range asked {
			if outcomes[u] != GpodderRefused {
				t.Fatalf("outcomes = %v, want every feed refused", outcomes)
			}
		}
	}
	if _, err := svc.GpodderReplaceDeviceList(ctx, uc, "phone", asked); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.ImportOPML(ctx, uc, []byte(`<opml version="2.0"><body><outline text="x" xmlUrl="https://feeds.example/s3cr3t-token/three.xml"/></body></opml>`)); err != nil {
		t.Fatal(err)
	}
	if parks, _ := svc.db.GpodderParks(ctx, uc.ID); len(parks) != 0 {
		t.Errorf("parked = %+v, want a refusal of the account parked nowhere", parks)
	}
	if subs, _ := svc.db.SubscriptionsByUser(ctx, uc.ID); len(subs) != 0 {
		t.Errorf("subscriptions = %+v, want the known show refused too", subs)
	}
	if got := hits.Load(); got != 1 {
		t.Errorf("the feed host saw %d requests, want only the administrator's subscribe", got)
	}
	page, err := svc.Notifications(ctx, uc, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	var rows []InboxNotification
	for _, n := range page.Notifications {
		if n.Event == "subscription-failed" {
			rows = append(rows, n)
		}
	}
	if len(rows) != 1 || !strings.Contains(rows[0].Body, "This account cannot see the podcast library; an administrator can grant it.") ||
		strings.Contains(rows[0].Title+rows[0].Body, "example") {
		t.Fatalf("inbox = %+v, want one row saying the refusal, naming no feed", rows)
	}
	if out := logged.String(); strings.Contains(out, "s3cr3t-token") || strings.Contains(out, strings.TrimPrefix(feed, "http://")) {
		t.Errorf("the log names a feed: %q", out)
	}
}

// fetchOneEpisode files a generated file as the first episode of a show,
// which is what makes the catalog create its podcast library.
func fetchOneEpisode(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, showPID string) {
	t.Helper()
	eps, _, err := svc.Episodes(ctx, uc, showPID, "", 1)
	if err != nil || len(eps) == 0 {
		t.Fatalf("the show's episodes = %+v, %v", eps, err)
	}
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "one", Codec: fixtures.CodecMP3, Container: fixtures.ContainerMP3, Duration: time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	_, bare, _ := parseAPIPID(eps[0].PID)
	if _, err := svc.lib.Podcasts().ImportEpisodeFile(ctx, bare, paths[0], false); err != nil {
		t.Fatal(err)
	}
}

// grantedListener makes an account granted the library named lib alone.
func grantedListener(t *testing.T, ctx context.Context, svc *Library, name, lib string) *UserCtx {
	t.Helper()
	var pid string
	for _, r := range svc.libraryRoots() {
		if r.Name == lib {
			pid = r.PID
		}
	}
	if pid == "" {
		t.Fatalf("no library named %q", lib)
	}
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: name, Password: "correct-horse", AccessMode: "granted",
		LibraryPIDs: []string{apiPID(PrefixLibrary, model.PID(pid))},
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return uc
}
