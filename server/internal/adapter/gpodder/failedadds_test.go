package gpodder

import (
	"bytes"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// flakyFeed answers 503 for its first failures requests, then a feed.
func flakyFeed(t *testing.T, failures int32) (string, *atomic.Int32) {
	t.Helper()
	var hits atomic.Int32
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if hits.Add(1) <= failures {
			http.Error(w, "down for maintenance", http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Back Again</title>
<item><title>Return</title><guid>back-again-1</guid><enclosure url="http://%s/return.mp3" type="audio/mpeg" length="1"/></item>
</channel></rss>`, r.Host)
	}))
	t.Cleanup(ts.Close)
	return ts.URL + "/feed.xml", &hits
}

// webPage serves an HTML page where a feed was expected.
func webPage(t *testing.T) string {
	t.Helper()
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		io.WriteString(w, "<!doctype html><html><body>a web page</body></html>")
	}))
	t.Cleanup(ts.Close)
	return ts.URL + "/"
}

// deadAddress is a loopback address nothing listens on.
func deadAddress(t *testing.T) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := ln.Addr().String()
	ln.Close()
	return "http://" + addr
}

// failedAdds is the account's inbox rows for adds that did not land.
func (e *env) failedAdds() []service.InboxNotification {
	e.t.Helper()
	page, err := e.svc.Notifications(e.ctx, e.uc, "", 100)
	if err != nil {
		e.t.Fatal(err)
	}
	var out []service.InboxNotification
	for _, n := range page.Notifications {
		if n.Event == "subscription-failed" {
			out = append(out, n)
		}
	}
	return out
}

// A feed that is down is parked, in no list and no delta, and tried again
// on a backoff until it lands for the device that asked, whose add then
// reaches the other devices like any other.
func TestAFeedThatIsDownIsParkedUntilItLands(t *testing.T) {
	e := newEnv(t)
	flaky, hits := flakyFeed(t, 2)
	ack := e.change("phone", []string{flaky}, nil)
	if len(ack.UpdateURLs) != 0 {
		t.Fatalf("update_urls = %v, want none for a parked feed", ack.UpdateURLs)
	}
	start := time.Now()
	e.wantList("while parked")
	if d := e.changesSince("tablet", 0); len(d.Add) != 0 {
		t.Fatalf("delta while parked = %+v", d)
	}

	for _, step := range []struct {
		after time.Duration
		hits  int32
	}{
		{0, 1},                // not due: five minutes first
		{6 * time.Minute, 2},  // due, and down again
		{10 * time.Minute, 2}, // a quarter hour after that try, not yet
		{22 * time.Minute, 3}, // due, and back
	} {
		e.svc.RetryPendingGpodderAt(e.ctx, start.Add(step.after))
		if got := hits.Load(); got != step.hits {
			t.Fatalf("after a retry at +%v the host saw %d requests, want %d", step.after, got, step.hits)
		}
	}
	e.wantList("after it landed", flaky)
	if d := e.changesSince("tablet", ack.Timestamp); !slices.Contains(d.Add, flaky) {
		t.Fatalf("the tablet's delta = %+v, want the landed add", d)
	}
	if rows := e.failedAdds(); len(rows) != 0 {
		t.Fatalf("inbox = %+v, want nothing for a feed that landed", rows)
	}
	// The phone asked for it, so the phone holds it.
	e.put("phone", "json", `[]`)
	e.wantList("after the phone let go of the feed it asked for")
}

// A device that stops asking for a parked feed forgets it, by a remove or
// by a list that leaves it out.
func TestAParkedFeedTheDeviceDropsIsForgotten(t *testing.T) {
	e := newEnv(t)
	first, firstHits := flakyFeed(t, 1)
	second, secondHits := flakyFeed(t, 1)
	e.change("phone", []string{first, second}, nil)
	e.change("phone", nil, []string{first})
	e.put("phone", "json", `[]`)
	e.svc.RetryPendingGpodderAt(e.ctx, time.Now().Add(6*time.Minute))
	if firstHits.Load() != 1 || secondHits.Load() != 1 {
		t.Fatalf("hosts saw %d and %d requests, want neither tried again", firstHits.Load(), secondHits.Load())
	}
	e.wantList("after the phone dropped both")
}

// A feed that can never land is answered the protocol's way, [url, ""],
// and the inbox says why once, however often the device asks again.
func TestAFeedThatCannotLandIsRefused(t *testing.T) {
	e := newEnv(t)
	gone, page := e.feed.URL+"/nothing-here.xml", webPage(t)
	ack := e.change("phone", []string{gone, page}, nil)
	if !slices.Equal(ack.UpdateURLs, [][2]string{{gone, ""}, {page, ""}}) {
		t.Fatalf("update_urls = %v, want both refused", ack.UpdateURLs)
	}
	e.wantList("after the refused adds")
	rows := e.failedAdds()
	if len(rows) != 2 {
		t.Fatalf("inbox = %+v, want one row per refused feed", rows)
	}
	var bodies []string
	for _, r := range rows {
		if r.Title != "Podcast not added: 127.0.0.1" || strings.Contains(r.Body, "/nothing-here") {
			t.Errorf("row = %+v, want the feed named by its host alone", r)
		}
		bodies = append(bodies, r.Body)
	}
	all := strings.Join(bodies, "\n")
	for _, why := range []string{"No feed was found at that address.", "That address did not return a podcast feed."} {
		if !strings.Contains(all, why) {
			t.Errorf("no row says %q: %q", why, all)
		}
	}

	// Asked again, respelled, it is answered once, as refused.
	spaced := " " + gone + " "
	if ack := e.change("phone", []string{spaced}, nil); !slices.Equal(ack.UpdateURLs, [][2]string{{spaced, ""}}) {
		t.Fatalf("update_urls for a respelled refusal = %v, want the one refusal", ack.UpdateURLs)
	}
	e.put("phone", "txt", gone+"\n"+page+"\n")
	if again := e.failedAdds(); len(again) != 2 {
		t.Fatalf("inbox after asking again = %d rows, want still two", len(again))
	}
}

// logLines is a log sink a test reads while the server writes to it.
type logLines struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (l *logLines) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.Write(p)
}

func (l *logLines) String() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.buf.String()
}

// A refused feed is the inbox's to record: a full list names it on every
// sync, and the log keeps no line per sync of it at the level a server
// runs at.
func TestARefusedFeedLogsNoLinePerSync(t *testing.T) {
	var logged logLines
	e := newEnvWith(t, func(cfg *service.Config) {
		cfg.Logger = slog.New(slog.NewTextHandler(&logged, &slog.HandlerOptions{Level: slog.LevelInfo}))
	})
	gone := e.feed.URL + "/nothing-here.xml"
	e.put("phone", "txt", gone+"\n")
	first := len(logged.String())
	e.put("phone", "txt", gone+"\n")
	if again := logged.String()[first:]; again != "" {
		t.Errorf("the second sync logged %q", again)
	}
	if rows := e.failedAdds(); len(rows) != 1 {
		t.Errorf("inbox = %+v, want the refusal recorded once", rows)
	}
}

// A server that keeps its fetches off the local network refuses such a
// feed for good, and says so.
func TestAPrivateAddressIsRefused(t *testing.T) {
	e := newEnvWith(t, func(cfg *service.Config) { cfg.AllowPrivateFeedHosts = false })
	ack := e.change("phone", []string{e.feedURL()}, nil)
	if !slices.Equal(ack.UpdateURLs, [][2]string{{e.feedURL(), ""}}) {
		t.Fatalf("update_urls = %v, want the feed refused", ack.UpdateURLs)
	}
	if rows := e.failedAdds(); len(rows) != 1 || !strings.Contains(rows[0].Body, "private or local network") {
		t.Fatalf("inbox = %+v, want the private address named as why", rows)
	}
}

// An account that may not manage podcasts changes nothing from a gpodder
// client either, and is told so once.
func TestAnAccountThatMayNotManagePodcastsChangesNothing(t *testing.T) {
	e := newEnv(t)
	a, b := e.feedURLOf(1), e.feedURLOf(2)
	e.subscribeFirstParty(a)
	perms := service.DefaultPermissions()
	perms.ManagePodcasts = false
	if _, err := e.svc.UpdateAccount(e.ctx, e.uc.ID, service.AccountUpdate{Permissions: &perms}); err != nil {
		t.Fatal(err)
	}
	ack := e.change("phone", []string{b}, []string{a})
	if !slices.Equal(ack.UpdateURLs, [][2]string{{b, ""}}) {
		t.Fatalf("update_urls = %v, want the add refused", ack.UpdateURLs)
	}
	e.put("phone", "json", `[]`)
	e.wantList("after a refused change and a refused list", a)
	if rows := e.failedAdds(); len(rows) != 1 || rows[0].Title != "Podcasts not changed" {
		t.Fatalf("inbox = %+v, want one row saying so", rows)
	}
}

// An account parks a bounded number of feeds; past that an add is
// refused rather than kept.
func TestParkedFeedsAreCapped(t *testing.T) {
	e := newEnv(t)
	dead := deadAddress(t)
	add := make([]string, 0, 201)
	for i := range 201 {
		add = append(add, fmt.Sprintf("%s/feed-%d.xml", dead, i))
	}
	ack := e.change("phone", add, nil)
	if !slices.Equal(ack.UpdateURLs, [][2]string{{add[200], ""}}) {
		t.Fatalf("update_urls = %v, want only the 201st refused", ack.UpdateURLs)
	}
	// Refused like any other add, it is said like any other refusal.
	rows := e.failedAdds()
	if len(rows) != 1 || !strings.Contains(rows[0].Body, "200") || !strings.Contains(rows[0].Body, "again") {
		t.Fatalf("inbox = %+v, want one row saying the account is at its 200 and to ask again later", rows)
	}
}

// A feed still failing a week after it was parked is given up, and the
// inbox says so.
func TestAParkedFeedIsGivenUpAfterAWeek(t *testing.T) {
	e := newEnv(t)
	dead := deadAddress(t) + "/feed.xml"
	e.change("phone", []string{dead}, nil)
	e.svc.RetryPendingGpodderAt(e.ctx, time.Now().Add(8*24*time.Hour))
	rows := e.failedAdds()
	if len(rows) != 1 || !strings.Contains(rows[0].Body, "a week later") ||
		!strings.Contains(rows[0].Body, "The feed's host could not be reached.") {
		t.Fatalf("inbox = %+v, want the give-up said once", rows)
	}
	e.svc.RetryPendingGpodderAt(e.ctx, time.Now().Add(9*24*time.Hour))
	if again := e.failedAdds(); len(again) != 1 {
		t.Fatalf("inbox after another pass = %d rows, want the feed gone after the first", len(again))
	}
}
