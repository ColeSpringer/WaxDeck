package service

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"runtime"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/colespringer/waxbin/model"
)

// A chapters document is read the way the catalog reads one when it
// downloads an episode: start order, negative starts dropped, titles
// trimmed, chapters that share a start collapsed to the last. Each ends
// where the next begins, so a client draws the same marks from either.
func TestParseChaptersDoc(t *testing.T) {
	t.Parallel()
	body := `{"version":"1.2.0","chapters":[
		{"startTime":90.5,"title":"  Closing  "},
		{"startTime":-3,"title":"Before the start"},
		{"startTime":0,"title":"Opening"},
		{"startTime":30,"title":"Middle"},
		{"startTime":30,"title":"Middle, revised"}]}`

	marks, err := parseChaptersDoc([]byte(body), 120_000)
	if err != nil {
		t.Fatal(err)
	}
	want := []ChapterMark{
		{Index: 0, Title: "Opening", StartMS: 0, EndMS: 30_000},
		{Index: 1, Title: "Middle, revised", StartMS: 30_000, EndMS: 90_500},
		{Index: 2, Title: "Closing", StartMS: 90_500, EndMS: 120_000},
	}
	if !slices.Equal(marks, want) {
		t.Errorf("marks = %+v, want %+v", marks, want)
	}

	// The last chapter is open-ended unless the episode is known to run
	// past where it starts.
	for _, length := range []int64{0, 90_500, 60_000} {
		marks, err := parseChaptersDoc([]byte(body), length)
		if err != nil {
			t.Fatal(err)
		}
		if last := marks[len(marks)-1]; last.EndMS != 0 {
			t.Errorf("with a length of %d the last chapter ends at %d, want it open", length, last.EndMS)
		}
	}
}

func TestParseChaptersDocRefusesWhatIsNotAChaptersDocument(t *testing.T) {
	t.Parallel()
	for name, body := range map[string]string{
		"a page":        "<html>not json</html>",
		"a list":        `[{"startTime":0,"title":"One"}]`,
		"chapters text": `{"chapters":"none"}`,
		"trailing data": `{"chapters":[]} {"chapters":[]}`,
		"a cut-off one": `{"chapters":[{"startTime":0,`,
	} {
		if marks, err := parseChaptersDoc([]byte(body), 0); err == nil {
			t.Errorf("%s parsed as chapters: %+v", name, marks)
		}
	}
	for name, body := range map[string]string{
		"no chapters": `{"version":"1.2.0"}`,
		"null":        `{"chapters":null}`,
		"empty":       `{"chapters":[]}`,
	} {
		if marks, err := parseChaptersDoc([]byte(body), 0); err != nil || len(marks) != 0 {
			t.Errorf("%s = %+v, %v; want none and no error", name, marks, err)
		}
	}
	// Keys match the way the catalog's decoder matches them.
	if marks, err := parseChaptersDoc([]byte(`{"Chapters":[{"StartTime":4,"Title":"Four"}]}`), 0); err != nil ||
		len(marks) != 1 || marks[0].StartMS != 4000 {
		t.Errorf("mixed-case keys = %+v, %v", marks, err)
	}
}

// The count is checked as entries are read, so a list no show has is
// refused at the limit and never decoded to the end: here the bytes after
// the limit are not even JSON, and the answer is still about the count.
func TestParseChaptersDocStopsAtTheLimitWithoutReadingOn(t *testing.T) {
	t.Parallel()
	body := `{"chapters":[` + strings.Repeat(`{"startTime":1},`, chaptersMaxMarks+1) + `<<not json>>`
	_, err := parseChaptersDoc([]byte(body), 0)
	if err == nil || !strings.Contains(err.Error(), fmt.Sprint(chaptersMaxMarks)) {
		t.Errorf("a list past the limit answered %v, want a refusal that names the limit", err)
	}
	// A list at the limit is fine.
	var at strings.Builder
	at.WriteString(`{"chapters":[`)
	for i := range chaptersMaxMarks {
		if i > 0 {
			at.WriteByte(',')
		}
		fmt.Fprintf(&at, `{"startTime":%d}`, i)
	}
	at.WriteString(`]}`)
	if marks, err := parseChaptersDoc([]byte(at.String()), 0); err != nil || len(marks) != chaptersMaxMarks {
		t.Errorf("a list at the limit = %d marks, %v", len(marks), err)
	}
}

// A title is clipped to what a chapter list can draw, at a character
// boundary, so one chapter cannot hold what the cache would have to keep.
func TestParseChaptersDocClipsLongTitles(t *testing.T) {
	t.Parallel()
	long := strings.Repeat("\u00e9", 1000)
	marks, err := parseChaptersDoc(fmt.Appendf(nil, `{"chapters":[{"startTime":0,"title":%q}]}`, long), 0)
	if err != nil {
		t.Fatal(err)
	}
	title := marks[0].Title
	if len(title) > chaptersMaxTitle || len(title) < chaptersMaxTitle-1 || !utf8.ValidString(title) {
		t.Errorf("a title of %d bytes came back as %d bytes (valid: %v), want it clipped to %d at a character",
			len(long), len(title), utf8.ValidString(title), chaptersMaxTitle)
	}
	if short, err := parseChaptersDoc([]byte(`{"chapters":[{"startTime":0,"title":"Plain"}]}`), 0); err != nil || short[0].Title != "Plain" {
		t.Errorf("a short title = %+v, %v", short, err)
	}
}

// A start that is no time on an episode's timeline is dropped like a
// negative one: converted to milliseconds it would wrap, and the list would
// no longer be in order.
func TestParseChaptersDocDropsStartsThatAreNotTimes(t *testing.T) {
	t.Parallel()
	marks, err := parseChaptersDoc([]byte(
		`{"chapters":[{"startTime":1e300,"title":"absurd"},{"startTime":5,"title":"fine"}]}`), 60_000)
	if err != nil {
		t.Fatal(err)
	}
	want := []ChapterMark{{Index: 0, Title: "fine", StartMS: 5_000, EndMS: 60_000}}
	if !slices.Equal(marks, want) {
		t.Errorf("marks = %+v, want %+v", marks, want)
	}
}

// What was read for display is kept for hours when it held chapters and for
// minutes when it did not, so a host that is down is asked now and then and
// a feed that adds its chapters later is seen.
func TestChaptersCacheKeepsHitsForHoursAndMissesForMinutes(t *testing.T) {
	t.Parallel()
	now := time.Date(2026, 10, 16, 9, 0, 0, 0, time.UTC)
	c := &chaptersCache{now: func() time.Time { return now }}
	hit := chaptersKey{episode: "ep-hit", url: "https://example.com/c.json"}
	miss := chaptersKey{episode: "ep-miss", url: "https://example.com/c.json"}
	c.put(hit, []ChapterMark{{Title: "One"}})
	c.put(miss, nil)

	for _, key := range []chaptersKey{hit, miss} {
		if _, ok := c.get(key); !ok {
			t.Fatalf("%v is not cached straight after", key)
		}
	}
	now = now.Add(chaptersMissTTL - time.Second)
	if _, ok := c.get(miss); !ok {
		t.Error("a miss is forgotten before its time")
	}
	now = now.Add(2 * time.Second)
	if _, ok := c.get(miss); ok {
		t.Error("a miss outlived its time")
	}
	if marks, ok := c.get(hit); !ok || len(marks) != 1 {
		t.Errorf("a hit = %+v, %v ten minutes on, want it kept", marks, ok)
	}
	now = now.Add(chaptersHitTTL)
	if _, ok := c.get(hit); ok {
		t.Error("a hit outlived its time")
	}
}

// A failure never replaces a success that is still fresh for the same
// document; once the success has aged out, the failure is what is true.
func TestChaptersCacheKeepsAFreshHitOverALaterMiss(t *testing.T) {
	t.Parallel()
	now := time.Date(2026, 10, 16, 9, 0, 0, 0, time.UTC)
	c := &chaptersCache{now: func() time.Time { return now }}
	key := chaptersKey{episode: "ep-1", url: "u"}
	c.put(key, []ChapterMark{{Title: "One"}})
	c.put(key, nil)
	if marks, ok := c.get(key); !ok || len(marks) != 1 {
		t.Fatalf("after a miss over a fresh hit = %+v, %v; want the hit", marks, ok)
	}
	now = now.Add(chaptersHitTTL + time.Second)
	c.put(key, nil)
	if marks, ok := c.get(key); !ok || len(marks) != 0 {
		t.Errorf("a miss after the hit aged out = %+v, %v; want the miss", marks, ok)
	}
}

func TestChaptersCacheIsBoundedAndDropsTheOldestFirst(t *testing.T) {
	t.Parallel()
	c := &chaptersCache{}
	key := func(i int) chaptersKey { return chaptersKey{episode: model.PID(fmt.Sprintf("ep-%d", i)), url: "u"} }
	for i := range chaptersCacheMax + 1 {
		c.put(key(i), []ChapterMark{{Title: "x"}})
	}
	if _, ok := c.get(key(0)); ok {
		t.Error("the oldest entry survived the bound")
	}
	for _, i := range []int{1, chaptersCacheMax / 2, chaptersCacheMax} {
		if _, ok := c.get(key(i)); !ok {
			t.Errorf("entry %d was dropped before the oldest", i)
		}
	}

	// Writing a key again makes it the newest, not a second entry.
	c.put(key(1), []ChapterMark{{Title: "again"}})
	c.put(key(chaptersCacheMax+1), []ChapterMark{{Title: "x"}})
	if _, ok := c.get(key(1)); !ok {
		t.Error("a rewritten entry was dropped as if it were old")
	}
	if _, ok := c.get(key(2)); ok {
		t.Error("the oldest entry after a rewrite survived")
	}
}

// Entries are bounded by what they weigh as well as by how many there are:
// a few long lists push the oldest out long before the count does.
func TestChaptersCacheIsBoundedByBytes(t *testing.T) {
	t.Parallel()
	c := &chaptersCache{}
	heavy := make([]ChapterMark, chaptersMaxMarks)
	for i := range heavy {
		heavy[i] = ChapterMark{Index: i, Title: strings.Repeat("t", chaptersMaxTitle), StartMS: int64(i)}
	}
	key := func(i int) chaptersKey { return chaptersKey{episode: model.PID(fmt.Sprintf("ep-%d", i)), url: "u"} }
	const writes = 40
	for i := range writes {
		c.put(key(i), heavy)
	}
	if _, ok := c.get(key(0)); ok {
		t.Errorf("%d long lists are all kept, past any byte bound", writes)
	}
	if _, ok := c.get(key(writes - 1)); !ok {
		t.Error("the newest list was dropped to make room for nothing")
	}
	kept := 0
	for i := range writes {
		if _, ok := c.get(key(i)); ok {
			kept++
		}
	}
	if kept == 0 || kept > writes/2 {
		t.Errorf("%d of %d long lists kept, want a few", kept, writes)
	}
}

func TestChaptersCacheHandsOutCopies(t *testing.T) {
	t.Parallel()
	c := &chaptersCache{}
	key := chaptersKey{episode: "ep-1", url: "u"}
	in := []ChapterMark{{Title: "One"}}
	c.put(key, in)
	in[0].Title = "changed by the writer"
	got, _ := c.get(key)
	got[0].Title = "changed by a reader"
	again, _ := c.get(key)
	if again[0].Title != "One" {
		t.Errorf("the cache holds %q, want what was put", again[0].Title)
	}
}

// chaptersLibrary is a service whose guarded client reaches loopback hosts,
// with the fetch budget a test chooses (zero keeps the real one). The client
// is built on first use, so the setting is read then.
func chaptersLibrary(t *testing.T, budget time.Duration) *Library {
	t.Helper()
	_, svc, _ := newCatalogFixture(t)
	svc.allowPrivateFeedHosts = true
	svc.chapterDocs.timeout = budget
	return withOpenShows(svc)
}

// withOpenShows reads every show as an open feed, so a made-up episode has
// a show for the fetch to read its terms from.
func withOpenShows(svc *Library) *Library {
	svc.showReadHook = func(_ context.Context, pid model.PID) (*model.Podcast, error) {
		return &model.Podcast{PID: pid, FeedURL: "https://feeds.example/feed.xml"}, nil
	}
	return svc
}

func chaptersEpisode(pid, rawURL string) *model.Episode {
	return &model.Episode{PID: model.PID(pid), ChaptersURL: rawURL, DurationMS: 60_000}
}

const oneChapterDoc = `{"chapters":[{"startTime":0,"title":"One"}]}`

// The document's host is the feed's to name, so it is fetched through the
// guarded client: an address that is private after DNS is refused unless
// the server allows LAN feed hosts, and a body past the cap is refused
// before it is decoded.
func TestChaptersDocumentFetchIsGuarded(t *testing.T) {
	t.Parallel()
	var hits atomic.Int32
	var body atomic.Value
	body.Store(oneChapterDoc)
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		_, _ = io.WriteString(w, body.Load().(string))
	}))
	t.Cleanup(host.Close)
	ep := chaptersEpisode("ep-1", host.URL+"/chapters.json")
	ctx := context.Background()

	_, closed, _ := newCatalogFixture(t)
	withOpenShows(closed)
	if marks, err := closed.fetchChapters(ctx, ep, ep.ChaptersURL, feedLogin{}); err == nil || len(marks) != 0 ||
		!strings.Contains(err.Error(), "private address") {
		t.Fatalf("fetch at a loopback address = %+v, %v; want it refused as private", marks, err)
	}
	if got := closed.fetchedChapters(ctx, "", ep); len(got) != 0 {
		t.Errorf("a refused fetch gave chapters %+v", got)
	}
	if n := hits.Load(); n != 0 {
		t.Fatalf("the host was reached %d times through the guard", n)
	}

	// The same fetch with LAN hosts allowed, which also shows the refusal
	// above was the guard's and not a broken fixture.
	open := chaptersLibrary(t, 0)
	marks, err := open.fetchChapters(ctx, ep, ep.ChaptersURL, feedLogin{})
	if err != nil || len(marks) != 1 || marks[0].Title != "One" || marks[0].EndMS != 60_000 {
		t.Fatalf("fetch with LAN hosts allowed = %+v, %v", marks, err)
	}

	body.Store(strings.Repeat("x", chaptersMaxBytes+1))
	if marks, err := open.fetchChapters(ctx, ep, ep.ChaptersURL, feedLogin{}); err == nil || len(marks) != 0 ||
		!strings.Contains(err.Error(), "size cap") {
		t.Errorf("a body past the cap = %+v, %v; want it refused for its size", marks, err)
	}
}

// Whether a document needs the show's credentials, and for whom, is the
// show's to say, so a show that cannot be read gives no chapters and asks no
// host, as it relays no audio. It is not remembered as a miss.
func TestChaptersOfAShowThatCannotBeReadAreNone(t *testing.T) {
	t.Parallel()
	var hits atomic.Int32
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		_, _ = io.WriteString(w, oneChapterDoc)
	}))
	t.Cleanup(host.Close)
	svc := chaptersLibrary(t, 0)
	var busy atomic.Bool
	busy.Store(true)
	svc.showReadHook = func(_ context.Context, pid model.PID) (*model.Podcast, error) {
		if busy.Load() {
			return nil, errors.New("the catalog is busy")
		}
		return &model.Podcast{PID: pid, FeedURL: host.URL + "/feed.xml"}, nil
	}
	ep := chaptersEpisode("ep-1", host.URL+"/chapters.json")

	if got := svc.fetchedChapters(context.Background(), "", ep); len(got) != 0 {
		t.Errorf("chapters while the show cannot be read = %+v, want none", got)
	}
	if n := hits.Load(); n != 0 {
		t.Errorf("the host was asked %d times while the show could not be read", n)
	}
	busy.Store(false)
	if got := svc.fetchedChapters(context.Background(), "", ep); len(got) != 1 {
		t.Errorf("chapters once the show reads = %+v, want the document's", got)
	}
}

// A redirect is followed within the same cap the transcript client has: a
// document four hops away is read and one five hops away is not.
func TestChaptersRedirectsAreCapped(t *testing.T) {
	t.Parallel()
	mux := http.NewServeMux()
	mux.HandleFunc("/hop/{n}", func(w http.ResponseWriter, r *http.Request) {
		var n int
		_, _ = fmt.Sscan(r.PathValue("n"), &n)
		if n == 0 {
			_, _ = io.WriteString(w, oneChapterDoc)
			return
		}
		http.Redirect(w, r, fmt.Sprintf("/hop/%d", n-1), http.StatusFound)
	})
	host := httptest.NewServer(mux)
	t.Cleanup(host.Close)
	svc := chaptersLibrary(t, 0)
	ctx := context.Background()

	if got := svc.fetchedChapters(ctx, "", chaptersEpisode("ep-near", host.URL+"/hop/4")); len(got) != 1 {
		t.Errorf("a document four redirects away gave %+v", got)
	}
	if got := svc.fetchedChapters(ctx, "", chaptersEpisode("ep-far", host.URL+"/hop/5")); len(got) != 0 {
		t.Errorf("a document five redirects away gave %+v, want the cap to refuse it", got)
	}
}

// The guard is on every connection the client makes, so a redirect hop to a
// private address is refused as a first hop is. The first hop here is a
// stand-in for a public host: the test routes an address the guard allows to
// a local server that sends the reader to a private one, and the hop after
// it dials through the client's own guarded dialer.
func TestChaptersARedirectHopToAPrivateAddressIsRefused(t *testing.T) {
	t.Parallel()
	var privateHits atomic.Int32
	private := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		privateHits.Add(1)
		_, _ = io.WriteString(w, oneChapterDoc)
	}))
	t.Cleanup(private.Close)
	first := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, private.URL+"/c.json", http.StatusFound)
	}))
	t.Cleanup(first.Close)
	const publicAddr = "203.0.113.7:80"
	ep := chaptersEpisode("ep-1", "http://"+publicAddr+"/c.json")

	routed := func(svc *Library) {
		transport := svc.transcriptClient().Transport.(*http.Transport)
		transport.Proxy = nil
		guarded := transport.DialContext
		transport.DialContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
			if addr == publicAddr {
				return (&net.Dialer{}).DialContext(ctx, network, first.Listener.Addr().String())
			}
			return guarded(ctx, network, addr)
		}
	}

	_, closed, _ := newCatalogFixture(t)
	withOpenShows(closed)
	routed(closed)
	if got := closed.fetchedChapters(context.Background(), "", ep); len(got) != 0 {
		t.Errorf("a redirect to a private address gave %+v", got)
	}
	if n := privateHits.Load(); n != 0 {
		t.Fatalf("the private host was reached %d times through a redirect", n)
	}

	// The same chain with LAN hosts allowed is followed to the end, so the
	// refusal above was the guard's.
	open := chaptersLibrary(t, 0)
	routed(open)
	if got := open.fetchedChapters(context.Background(), "", ep); len(got) != 1 {
		t.Errorf("the same chain with LAN hosts allowed gave %+v, want the document", got)
	}
}

// A reader that left is not a verdict on the host: what its cancelled
// request failed to read is not remembered, and the next reader asks.
func TestChaptersAReaderWhoLeftDoesNotMakeAMiss(t *testing.T) {
	t.Parallel()
	var hits atomic.Int32
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		_, _ = io.WriteString(w, oneChapterDoc)
	}))
	t.Cleanup(host.Close)
	svc := chaptersLibrary(t, 0)
	ep := chaptersEpisode("ep-1", host.URL+"/c.json")

	gone, leave := context.WithCancel(context.Background())
	leave()
	if got := svc.fetchedChapters(gone, "", ep); len(got) != 0 {
		t.Errorf("a cancelled read gave %+v", got)
	}
	if got := svc.fetchedChapters(context.Background(), "", ep); len(got) != 1 {
		t.Errorf("the read after it gave %+v, want the document: the cancelled one was remembered as a failure", got)
	}
	if n := hits.Load(); n != 1 {
		t.Errorf("the host was asked %d times, want once, by the reader who stayed", n)
	}
}

// Readers of one cold document share one fetch. The host answers only when
// released, so every reader that arrives meanwhile has to wait on it, and
// the host is asked once.
func TestChaptersReadersShareOneFetch(t *testing.T) {
	t.Parallel()
	var hits atomic.Int32
	release := make(chan struct{})
	var once sync.Once
	open := func() { once.Do(func() { close(release) }) }
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		<-release
		_, _ = io.WriteString(w, oneChapterDoc)
	}))
	t.Cleanup(host.Close)
	t.Cleanup(open)
	svc := chaptersLibrary(t, 0)
	ep := chaptersEpisode("ep-1", host.URL+"/c.json")

	const readers = 8
	results := make(chan []ChapterMark, readers)
	for range readers {
		go func() { results <- svc.fetchedChapters(context.Background(), "", ep) }()
	}
	// Long enough for the readers to arrive and wait; any that is late finds
	// the answer kept instead, and the count is the same.
	time.Sleep(200 * time.Millisecond)
	open()
	for range readers {
		if got := <-results; len(got) != 1 || got[0].Title != "One" {
			t.Errorf("a reader got %+v, want the document's one chapter", got)
		}
	}
	if n := hits.Load(); n != 1 {
		t.Errorf("the host was asked %d times for %d readers, want once", n, readers)
	}
}

// A reader waiting on another's fetch keeps its own context: it leaves when
// it is done waiting, and the fetch it was waiting on goes on.
func TestChaptersAWaiterKeepsItsOwnContext(t *testing.T) {
	t.Parallel()
	var hits atomic.Int32
	release := make(chan struct{})
	var once sync.Once
	open := func() { once.Do(func() { close(release) }) }
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		<-release
		_, _ = io.WriteString(w, oneChapterDoc)
	}))
	t.Cleanup(host.Close)
	t.Cleanup(open)
	svc := chaptersLibrary(t, 0)
	ep := chaptersEpisode("ep-1", host.URL+"/c.json")

	leader := make(chan []ChapterMark, 1)
	go func() { leader <- svc.fetchedChapters(context.Background(), "", ep) }()
	for hits.Load() == 0 {
		time.Sleep(5 * time.Millisecond)
	}

	waiting, giveUp := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer giveUp()
	started := time.Now()
	if got := svc.fetchedChapters(waiting, "", ep); len(got) != 0 {
		t.Errorf("a waiter that gave up got %+v", got)
	}
	if waited := time.Since(started); waited > 2*time.Second {
		t.Errorf("the waiter stayed %s, past its own deadline", waited)
	}

	open()
	if got := <-leader; len(got) != 1 {
		t.Errorf("the reader who led got %+v after its waiter left", got)
	}
	if got := svc.fetchedChapters(context.Background(), "", ep); len(got) != 1 {
		t.Errorf("the read after got %+v, want the kept document", got)
	}
	if n := hits.Load(); n != 1 {
		t.Errorf("the host was asked %d times, want once", n)
	}
}

// silentHost is a listener that takes connections and never answers them,
// and the count of connections it took.
func silentHost(t *testing.T) (addr string, accepts *atomic.Int32) {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	accepts = new(atomic.Int32)
	var held []net.Conn
	var heldMu sync.Mutex
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			accepts.Add(1)
			heldMu.Lock()
			held = append(held, conn)
			heldMu.Unlock()
		}
	}()
	t.Cleanup(func() {
		_ = listener.Close()
		heldMu.Lock()
		defer heldMu.Unlock()
		for _, c := range held {
			_ = c.Close()
		}
	})
	return listener.Addr().String(), accepts
}

// A host that takes a connection and never answers costs one wait, the
// fetch budget, for all of its documents: the failure is remembered for the
// host as well as for the episode, so the next episode's read does not wait.
func TestChaptersAHostThatDoesNotAnswerCostsOneWait(t *testing.T) {
	t.Parallel()
	addr, accepts := silentHost(t)
	const budget = 600 * time.Millisecond
	svc := chaptersLibrary(t, budget)
	base := "http://" + addr
	ctx := context.Background()

	started := time.Now()
	if got := svc.fetchedChapters(ctx, "", chaptersEpisode("ep-a", base+"/a.json")); len(got) != 0 {
		t.Errorf("a host that never answers gave %+v", got)
	}
	if waited := time.Since(started); waited < budget-50*time.Millisecond || waited > 5*time.Second {
		t.Errorf("the first read took %s, want about the %s budget", waited, budget)
	}

	started = time.Now()
	if got := svc.fetchedChapters(ctx, "", chaptersEpisode("ep-b", base+"/b.json")); len(got) != 0 {
		t.Errorf("another episode of the same host gave %+v", got)
	}
	if waited := time.Since(started); waited > budget/2 {
		t.Errorf("the second episode waited %s on a host already known to be down", waited)
	}
	if n := accepts.Load(); n != 1 {
		t.Errorf("the host took %d connections, want the one", n)
	}
}

// A host that answers the headers and then holds the body back is as down as
// one that answers nothing: the budget runs out inside the read, and the next
// episode of that host does not wait for it again.
func TestChaptersAHostThatStallsTheBodyCostsOneWait(t *testing.T) {
	t.Parallel()
	var hits atomic.Int32
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		w.Header().Set("Content-Length", "1000")
		w.WriteHeader(http.StatusOK)
		w.(http.Flusher).Flush()
		<-r.Context().Done()
	}))
	t.Cleanup(host.Close)
	const budget = 600 * time.Millisecond
	svc := chaptersLibrary(t, budget)
	ctx := context.Background()

	started := time.Now()
	if got := svc.fetchedChapters(ctx, "", chaptersEpisode("ep-a", host.URL+"/a.json")); len(got) != 0 {
		t.Errorf("a body that never arrives gave %+v", got)
	}
	if waited := time.Since(started); waited < budget-50*time.Millisecond || waited > 5*time.Second {
		t.Errorf("the first read took %s, want about the %s budget", waited, budget)
	}

	started = time.Now()
	if got := svc.fetchedChapters(ctx, "", chaptersEpisode("ep-b", host.URL+"/b.json")); len(got) != 0 {
		t.Errorf("another episode of the same host gave %+v", got)
	}
	if waited := time.Since(started); waited > budget/2 {
		t.Errorf("the second episode waited %s on a host already known to stall", waited)
	}
	if n := hits.Load(); n != 1 {
		t.Errorf("the host was asked %d times, want once", n)
	}
}

// The host remembered as down is the one that failed, not the one the
// pointer named: a healthy host that sends a document to a dead one keeps
// serving its other documents.
func TestChaptersADeadRedirectTargetDoesNotMarkTheFirstHopDown(t *testing.T) {
	t.Parallel()
	dead, _ := silentHost(t)
	mux := http.NewServeMux()
	mux.HandleFunc("/a.json", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "http://"+dead+"/x.json", http.StatusFound)
	})
	mux.HandleFunc("/b.json", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, oneChapterDoc)
	})
	host := httptest.NewServer(mux)
	t.Cleanup(host.Close)
	svc := chaptersLibrary(t, time.Second)
	ctx := context.Background()

	if got := svc.fetchedChapters(ctx, "", chaptersEpisode("ep-a", host.URL+"/a.json")); len(got) != 0 {
		t.Errorf("a document that redirects to a dead host gave %+v", got)
	}
	if got := svc.fetchedChapters(ctx, "", chaptersEpisode("ep-b", host.URL+"/b.json")); len(got) != 1 {
		t.Errorf("another document of the healthy first host gave %+v, want it read: the first host was marked down for the dead one's failure", got)
	}
}

// A redirect that goes nowhere is the pointer's fault and not a host that
// does not answer: it makes the document a miss and the host's other
// documents are still read.
func TestChaptersARedirectLoopDoesNotMarkItsHostDown(t *testing.T) {
	t.Parallel()
	mux := http.NewServeMux()
	mux.HandleFunc("/loop", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/loop", http.StatusFound)
	})
	mux.HandleFunc("/b.json", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, oneChapterDoc)
	})
	host := httptest.NewServer(mux)
	t.Cleanup(host.Close)
	svc := chaptersLibrary(t, 0)
	ctx := context.Background()

	if got := svc.fetchedChapters(ctx, "", chaptersEpisode("ep-loop", host.URL+"/loop")); len(got) != 0 {
		t.Errorf("a redirect loop gave %+v", got)
	}
	if got := svc.fetchedChapters(ctx, "", chaptersEpisode("ep-b", host.URL+"/b.json")); len(got) != 1 {
		t.Errorf("another document of the host gave %+v, want it read: a loop is not a host that does not answer", got)
	}
}

// What the first read paid to find a host down is not paid again by a
// document that reaches the host through a redirect: the hop is not made.
func TestChaptersARedirectToAHostKnownToBeDownIsNotFollowed(t *testing.T) {
	t.Parallel()
	dead, accepts := silentHost(t)
	mux := http.NewServeMux()
	for _, name := range []string{"a", "b"} {
		mux.HandleFunc("/"+name+".json", func(w http.ResponseWriter, r *http.Request) {
			http.Redirect(w, r, "http://"+dead+"/x.json", http.StatusFound)
		})
	}
	host := httptest.NewServer(mux)
	t.Cleanup(host.Close)
	const budget = 1500 * time.Millisecond
	svc := chaptersLibrary(t, budget)
	ctx := context.Background()

	started := time.Now()
	svc.fetchedChapters(ctx, "", chaptersEpisode("ep-a", host.URL+"/a.json"))
	if waited := time.Since(started); waited < budget-50*time.Millisecond {
		t.Errorf("the first read took %s, want about the %s budget spent on the dead host", waited, budget)
	}

	started = time.Now()
	svc.fetchedChapters(ctx, "", chaptersEpisode("ep-b", host.URL+"/b.json"))
	if waited := time.Since(started); waited > budget/2 {
		t.Errorf("the second read waited %s on a redirect target already known to be down", waited)
	}
	if n := accepts.Load(); n != 1 {
		t.Errorf("the dead host took %d connections, want the one", n)
	}
}

// A request is blamed for the budget running out only if it held the budget
// for at least half of it: one sent with almost none left shows nothing about
// the host it went to. Otherwise a host could spend the time and redirect to
// another to have that one remembered as down.
func TestChaptersALateHopIsNotBlamedForTheBudgetItWasGiven(t *testing.T) {
	t.Parallel()
	dead, _ := silentHost(t)
	slow := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		time.Sleep(700 * time.Millisecond) // past half of the budget
		http.Redirect(w, r, "http://"+dead+"/x.json", http.StatusFound)
	}))
	t.Cleanup(slow.Close)
	const budget = time.Second
	svc := chaptersLibrary(t, budget)
	ctx := context.Background()

	svc.fetchedChapters(ctx, "", chaptersEpisode("ep-a", slow.URL+"/a.json"))

	started := time.Now()
	svc.fetchedChapters(ctx, "", chaptersEpisode("ep-b", "http://"+dead+"/b.json"))
	if waited := time.Since(started); waited < budget-100*time.Millisecond {
		t.Errorf("a document at the host took %s, want it asked for (about %s): the host was remembered as down for the time the slow one spent", waited, budget)
	}
}

// A redirect to something that is not a web address is refused, and the host
// it names is not blamed for it: otherwise a pointer could have any host it
// can name remembered as down.
func TestChaptersARedirectToAnotherSchemeBlamesNoOne(t *testing.T) {
	t.Parallel()
	bystander := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = io.WriteString(w, oneChapterDoc)
	}))
	t.Cleanup(bystander.Close)
	named := strings.TrimPrefix(bystander.URL, "http://")
	sender := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "ftp://"+named+"/x.json", http.StatusFound)
	}))
	t.Cleanup(sender.Close)
	svc := chaptersLibrary(t, 0)
	ctx := context.Background()

	if got := svc.fetchedChapters(ctx, "", chaptersEpisode("ep-a", sender.URL+"/a.json")); len(got) != 0 {
		t.Errorf("a redirect to another scheme gave %+v", got)
	}
	if got := svc.fetchedChapters(ctx, "", chaptersEpisode("ep-b", bystander.URL+"/b.json")); len(got) != 1 {
		t.Errorf("a document at the host the redirect named gave %+v, want it read", got)
	}
}

// The credentialed path keeps the client's redirect cap: a loop is cut by
// it, not left to run to the end of the budget.
func TestChaptersACredentialedRedirectLoopIsCutByTheCap(t *testing.T) {
	t.Parallel()
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/loop", http.StatusFound)
	}))
	t.Cleanup(host.Close)
	svc := chaptersLibrary(t, 0)
	ep := chaptersEpisode("ep-1", host.URL+"/loop")

	started := time.Now()
	login := feedLogin{feedURL: host.URL + "/feed.xml", user: "member", pass: "s3cret"}
	_, err := svc.fetchChapters(context.Background(), ep, ep.ChaptersURL, login)
	if err == nil || !strings.Contains(err.Error(), "too many redirects") {
		t.Fatalf("a credentialed redirect loop = %v, want the redirect cap", err)
	}
	if waited := time.Since(started); waited > time.Second {
		t.Errorf("the loop took %s, want the cap to cut it", waited)
	}
}

// A reader waiting on another's fetch takes its place when that reader
// leaves before the host answers, and reads the document itself: a healthy
// host is not a failure because the first reader gave up on it.
func TestChaptersAWaiterTakesOverWhenTheLeaderLeaves(t *testing.T) {
	t.Parallel()
	var hits atomic.Int32
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if hits.Add(1) == 1 {
			<-r.Context().Done() // the first ask is held until its client gives up
			return
		}
		_, _ = io.WriteString(w, oneChapterDoc)
	}))
	t.Cleanup(host.Close)
	svc := chaptersLibrary(t, 0)
	ep := chaptersEpisode("ep-1", host.URL+"/c.json")

	leading, leave := context.WithCancel(context.Background())
	defer leave()
	leader := make(chan []ChapterMark, 1)
	go func() { leader <- svc.fetchedChapters(leading, "", ep) }()
	for hits.Load() == 0 {
		time.Sleep(5 * time.Millisecond)
	}
	waiter := make(chan []ChapterMark, 1)
	go func() { waiter <- svc.fetchedChapters(context.Background(), "", ep) }()
	// Long enough for the waiter to be waiting on the leader.
	time.Sleep(200 * time.Millisecond)
	leave()

	if got := <-waiter; len(got) != 1 || got[0].Title != "One" {
		t.Errorf("the waiter got %+v, want the document read in the leader's place", got)
	}
	if got := <-leader; len(got) != 0 {
		t.Errorf("the reader who left got %+v", got)
	}
	if n := hits.Load(); n != 2 {
		t.Errorf("the host was asked %d times, want the held ask and the waiter's", n)
	}
}

// What the cache holds is what it weighs. A title cut out of a larger decoded
// string would keep all of that string alive, so a document of megabyte
// titles would pin megabytes per entry behind a weight of a few hundred
// bytes; the cache copies what it keeps. It reads the process heap, so it
// does not run beside the parallel tests.
func TestChaptersCacheHoldsOnlyWhatItWeighs(t *testing.T) {
	body := []byte(`{"chapters":[{"startTime":0,"title":"` + strings.Repeat("t", chaptersMaxBytes-64) + `"}]}`)
	c := &chaptersCache{}
	runtime.GC()
	var before, after runtime.MemStats
	runtime.ReadMemStats(&before)

	const lists = 12
	for i := range lists {
		marks, err := parseChaptersDoc(body, 0)
		if err != nil {
			t.Fatal(err)
		}
		c.put(chaptersKey{episode: model.PID(fmt.Sprintf("ep-%d", i)), url: "u"}, marks)
	}
	runtime.GC()
	runtime.ReadMemStats(&after)

	// The cache weighs a few KB; the process noise between the two readings
	// is tens of KB, and the bug held a megabyte per list.
	held := int64(after.HeapAlloc) - int64(before.HeapAlloc)
	if held > int64(c.bytes)+256<<10 {
		t.Errorf("%d lists weighing %d bytes hold %d bytes of heap, want about what they weigh", lists, c.bytes, held)
	}
	if got, ok := c.get(chaptersKey{episode: "ep-0", url: "u"}); !ok || len(got) != 1 || len(got[0].Title) != chaptersMaxTitle {
		t.Errorf("the first list = %d marks (kept: %v), want its clipped title", len(got), ok)
	}
}

// An episode's added time is read from the catalog, and a read that fails
// says so in the log rather than leaving an episode undated in silence.
func TestEpisodeAddedNSSaysWhenItCannotRead(t *testing.T) {
	t.Parallel()
	logs := &syncBuffer{}
	_, svc, _ := newCatalogFixtureWith(t, catalogFixtureOptions{logs: logs})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	if got := svc.episodeAddedNS(ctx, "01JZX5N8QW3F4V9T2B7KD3M9R6"); got != 0 {
		t.Errorf("added time of a read that failed = %d, want 0", got)
	}
	if out := logs.String(); !strings.Contains(out, "reading an episode's added time") {
		t.Errorf("the failed read left no trace in the log:\n%s", out)
	}
}
