package gpodder

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// countedFeed serves one valid feed and counts its requests.
func countedFeed(t *testing.T) (string, *atomic.Int32) {
	t.Helper()
	var hits atomic.Int32
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Counted</title>
<item><title>One</title><guid>counted-1</guid><enclosure url="http://%s/one.mp3" type="audio/mpeg" length="1"/></item>
</channel></rss>`, r.Host)
	}))
	t.Cleanup(ts.Close)
	return ts.URL + "/feed.xml", &hits
}

// One request resolves each feed once, however often and however spelled
// the upload names it.
func TestAFeedNamedTwiceInAnUploadIsFetchedOnce(t *testing.T) {
	e := newEnv(t)
	feed, hits := countedFeed(t)
	respelled := strings.Replace(feed, "http://", "HTTP://", 1) + "/"
	e.change("phone", []string{feed, feed, respelled}, nil)
	if got := hits.Load(); got != 1 {
		t.Fatalf("a delta naming one new feed three times fetched it %d times, want once", got)
	}
	other, otherHits := countedFeed(t)
	e.put("desk", "txt", other+"\n"+strings.Replace(other, "http://", "HTTP://", 1)+"/\n")
	if got := otherHits.Load(); got != 1 {
		t.Fatalf("a list naming one new feed twice fetched it %d times, want once", got)
	}
	e.wantList("after both uploads", feed, other)
}

// A parked feed keeps its place in the retry schedule however often a
// client names it again, and every device that asked holds it when it
// lands.
func TestAParkedFeedIsNotFetchedAgainWhenNamedAgain(t *testing.T) {
	e := newEnv(t)
	flaky, hits := flakyFeed(t, 1)
	e.change("phone", []string{flaky}, nil)
	e.put("phone", "txt", flaky+"\n")
	e.put("phone", "txt", flaky+"\n")
	e.change("tablet", []string{flaky}, nil)
	if got := hits.Load(); got != 1 {
		t.Fatalf("the host saw %d requests, want only the first ask", got)
	}
	e.svc.RetryPendingGpodderAt(e.ctx, time.Now().Add(6*time.Minute))
	e.wantList("after it landed", flaky)
	// The tablet asked too, so the phone letting go leaves it followed.
	e.put("phone", "json", `[]`)
	e.wantList("after the phone let go of a feed the tablet also asked for", flaky)
}

// An upload carries a bounded number of feeds or actions; past it the
// request is too large, which no client fixes by sending it again.
func TestUploadsAreBounded(t *testing.T) {
	e := newEnv(t)
	lines := make([]string, 2001)
	for i := range lines {
		lines[i] = fmt.Sprintf("https://feeds.example/%d.xml", i)
	}
	resp, raw := e.call("PUT", "/subscriptions/alice/desk.txt", strings.Join(lines, "\n"), true)
	mustStatus(t, resp, raw, 413)
	body, _ := json.Marshal(map[string][]string{"add": lines[:1000], "remove": lines[1000:]})
	resp, raw = e.call("POST", "/api/2/subscriptions/alice/phone.json", string(body), true)
	mustStatus(t, resp, raw, 413)

	actions := make([]string, 10001)
	for i := range actions {
		actions[i] = fmt.Sprintf(`{"podcast":"https://feeds.example/a.xml","episode":"https://feeds.example/%d.mp3","action":"download"}`, i)
	}
	resp, raw = e.call("POST", "/api/2/episodes/alice.json", "["+strings.Join(actions, ",")+"]", true)
	mustStatus(t, resp, raw, 413)
	if page := e.actions("since=0"); len(page.Actions) != 0 {
		t.Fatalf("a refused batch stored %d actions", len(page.Actions))
	}
	e.wantList("after the refused uploads")
}

// One request files a handful of inbox rows however many feeds it names
// that cannot land: the first few on their own, the rest counted in one.
// Sending the list again names the next few, until every feed has had its
// row; then it says nothing new.
func TestOneUploadFilesAHandfulOfRows(t *testing.T) {
	e := newEnvWith(t, func(cfg *service.Config) { cfg.AllowPrivateFeedHosts = false })
	add := make([]string, 50)
	for i := range add {
		add[i] = fmt.Sprintf("http://10.0.0.%d/feed.xml", i+1)
	}
	e.change("phone", add, nil)
	rows := e.failedAdds()
	if len(rows) != 6 {
		t.Fatalf("inbox = %d rows, want five of their own and one for the other 45", len(rows))
	}
	counted := 0
	for _, r := range rows {
		if strings.Contains(r.Body, "45 more") {
			counted++
		}
	}
	if counted != 1 {
		t.Fatalf("rows = %+v, want one counting the other 45", rows)
	}
	for range 9 {
		before := len(e.failedAdds())
		e.change("phone", add, nil)
		if filed := len(e.failedAdds()) - before; filed > 6 {
			t.Fatalf("the same upload again filed %d rows, want a handful", filed)
		}
	}
	named := 0
	for _, r := range e.failedAdds() {
		if strings.HasPrefix(r.Title, "Podcast not added: ") {
			named++
		}
	}
	if named != 50 {
		t.Fatalf("rows naming a feed after ten uploads = %d, want every one of the 50", named)
	}
	before := len(e.failedAdds())
	e.change("phone", add, nil)
	if after := len(e.failedAdds()); after != before {
		t.Fatalf("inbox after every feed was said = %d rows, want still %d", after, before)
	}
}

// A row of its own goes to a feed the inbox has not said yet: an upload
// naming five feeds already said and two new ones names the two, and one
// feed past the handful is counted as one.
func TestARowOfItsOwnGoesToAFeedNotYetSaid(t *testing.T) {
	e := newEnvWith(t, func(cfg *service.Config) { cfg.AllowPrivateFeedHosts = false })
	feed := func(i int) string { return fmt.Sprintf("http://10.0.0.%d/feed.xml", i) }
	var first []string
	for i := 1; i <= 5; i++ {
		first = append(first, feed(i))
	}
	e.change("phone", first, nil)
	e.change("phone", append(first, feed(6), feed(7)), nil)
	rows := e.failedAdds()
	named := map[string]bool{}
	for _, r := range rows {
		named[strings.TrimPrefix(r.Title, "Podcast not added: ")] = true
	}
	if len(rows) != 7 || !named["10.0.0.6"] || !named["10.0.0.7"] {
		t.Fatalf("inbox = %+v, want the two new feeds named beside the five", rows)
	}
	var next []string
	for i := 8; i <= 13; i++ {
		next = append(next, feed(i))
	}
	e.change("phone", next, nil)
	counted := 0
	for _, r := range e.failedAdds() {
		if strings.Contains(r.Body, "1 more feed that was not added.") {
			counted++
		}
	}
	if counted != 1 {
		t.Fatalf("inbox = %+v, want one row counting the sixth new feed as one", e.failedAdds())
	}
}
