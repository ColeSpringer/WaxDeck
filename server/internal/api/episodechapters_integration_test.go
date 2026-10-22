package api

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// docHost is one document of a feed's host, a chapters or a transcript
// document, that the test controls: what it answers, where it sends the
// reader instead, how many times it was asked, and what credentials and
// agent each ask carried.
type docHost struct {
	mu       sync.Mutex
	body     string
	status   int
	redirect string
	moved    string
	hits     int
	auths    []string
	agents   []string
}

func (c *docHost) set(status int, body string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.status, c.body = status, body
}

func (c *docHost) redirectTo(target string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.redirect = target
}

// moveTo answers every ask but one at path, on the document's own host,
// with a redirect to path.
func (c *docHost) moveTo(path string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.moved = path
}

func (c *docHost) asked() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.hits
}

// authorizations is the Authorization header of each ask, empty for one that
// carried none.
func (c *docHost) authorizations() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return slices.Clone(c.auths)
}

// userAgents is the User-Agent of each ask.
func (c *docHost) userAgents() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return slices.Clone(c.agents)
}

func (c *docHost) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	c.mu.Lock()
	c.hits++
	c.auths = append(c.auths, r.Header.Get("Authorization"))
	c.agents = append(c.agents, r.Header.Get("User-Agent"))
	status, body, redirect, moved := c.status, c.body, c.redirect, c.moved
	c.mu.Unlock()
	if redirect != "" {
		http.Redirect(w, r, redirect, http.StatusFound)
		return
	}
	if moved != "" && r.URL.Path != moved {
		http.Redirect(w, r, moved, http.StatusFound)
		return
	}
	if status != http.StatusOK {
		http.Error(w, "no chapters here", status)
		return
	}
	w.Header().Set("Content-Type", "application/json+chapters")
	_, _ = io.WriteString(w, body)
}

const chaptersGUID = "wd-chapters-ep-001"

// chaptersDoc is where the feed's one episode points for its chapters, on the
// feed's own host; transcriptDoc is where it points for its transcript.
const (
	chaptersDoc   = "/" + chaptersGUID + ".chapters.json"
	transcriptDoc = "/" + chaptersGUID + ".vtt"
)

// newChaptersElsewhere serves doc as an open host of its own and answers the
// address of its document, for a feed that points its chapters off its own
// host.
func newChaptersElsewhere(t *testing.T, doc *docHost) string {
	t.Helper()
	return newDocElsewhere(t, doc, chaptersDoc)
}

// newDocElsewhere serves doc at path on an open host of its own and answers
// its address.
func newDocElsewhere(t *testing.T, doc *docHost, path string) string {
	t.Helper()
	mux := http.NewServeMux()
	mux.Handle(path, doc)
	host := httptest.NewServer(mux)
	t.Cleanup(host.Close)
	return host.URL + path
}

// newChaptersFeed serves a one-episode feed, the episode's audio, and a
// chapters document answered by doc. wrap, when set, stands in front of the
// whole host. A feed's chapters pointer names its own host unless pointer
// says otherwise. The episode declares three seconds, and nothing fetches it.
func newChaptersFeed(t *testing.T, doc *docHost, wrap func(http.Handler) http.Handler, pointer string) string {
	t.Helper()
	// Only the pointer matters here: the host answers for it.
	return newPointerFeed(t, doc, wrap, pointer, chaptersDoc, fixtures.EpisodeSpec{ChaptersJSON: `{"chapters":[]}`})
}

// newTranscriptFeed is newChaptersFeed for the episode's transcript.
func newTranscriptFeed(t *testing.T, doc *docHost, wrap func(http.Handler) http.Handler, pointer string) string {
	t.Helper()
	return newPointerFeed(t, doc, wrap, pointer, transcriptDoc, fixtures.EpisodeSpec{TranscriptVTT: "WEBVTT\n"})
}

// newPointerFeed serves a one-episode feed whose episode points at one
// document, at path on the feed's own host unless pointer names another, and
// doc answering at path (and anywhere under /moved/). pointed carries the
// document's field of the episode spec.
func newPointerFeed(t *testing.T, doc *docHost, wrap func(http.Handler) http.Handler, pointer, path string, pointed fixtures.EpisodeSpec) string {
	t.Helper()
	dir := t.TempDir()
	mux := http.NewServeMux()
	var handler http.Handler = mux
	if wrap != nil {
		handler = wrap(mux)
	}
	host := httptest.NewServer(handler)
	t.Cleanup(host.Close)
	ep := pointed
	ep.Title = "Chapter Pilot"
	ep.GUID = chaptersGUID
	ep.PubDate = time.Date(2026, 1, 15, 9, 30, 0, 0, time.UTC)
	ep.Spec = fixtures.Spec{
		Codec: fixtures.CodecMP3, Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Chapter Pilot", "ARTIST": "Chapters Host", "ALBUM": "Chapters Cast"},
	}
	feedPath, err := fixtures.GeneratePodcastFeed(dir, fixtures.FeedSpec{
		Title:       "Chapters Cast",
		Author:      "Chapters Host",
		Description: "A show whose chapters live at a URL.",
		Episodes:    []fixtures.EpisodeSpec{ep},
	}, host.URL)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(feedPath)
	if err != nil {
		t.Fatal(err)
	}
	own := host.URL + path
	if !strings.Contains(string(raw), own) {
		t.Fatalf("the generated feed does not point at %s", own)
	}
	if pointer != "" {
		if err := os.WriteFile(filepath.Join(dir, "feed.xml"), []byte(strings.ReplaceAll(string(raw), own, pointer)), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	mux.Handle("/", http.FileServer(http.Dir(dir)))
	mux.Handle(path, doc)
	mux.Handle("/moved/", doc)
	return host.URL + "/feed.xml"
}

// memberOnly puts a host behind the credentials of a paid feed.
func memberOnly(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if user, pass, ok := r.BasicAuth(); !ok || user != "member" || pass != "s3cret" {
			w.Header().Set("WWW-Authenticate", `Basic realm="private"`)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

var memberCreds = map[string]any{"username": "member", "password": "s3cret"}

// chaptersFixture subscribes to such a feed and answers its one episode.
type chaptersFixture struct {
	h       *harness
	doc     *docHost
	episode EpisodeSummary
}

func subscribeToChaptersFeed(t *testing.T, doc *docHost, wrap func(http.Handler) http.Handler, pointer string, creds map[string]any) chaptersFixture {
	t.Helper()
	h := newPodcastHarness(t)
	body := map[string]any{"url": newChaptersFeed(t, doc, wrap, pointer)}
	for k, v := range creds {
		body[k] = v
	}
	resp := h.postJSON(t, "/api/v1/podcasts", body)
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)
	eps := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items
	if len(eps) != 1 || eps[0].Downloaded {
		t.Fatalf("episodes = %+v, want one that nothing has fetched", eps)
	}
	return chaptersFixture{h: h, doc: doc, episode: eps[0]}
}

func (f chaptersFixture) detailAs(t *testing.T, token string) Episode {
	t.Helper()
	return decodeStatus[Episode](t, get(t, f.h.ts, "/api/v1/episodes/"+f.episode.Pid, token),
		http.StatusOK, "episode detail")
}

func (f chaptersFixture) detail(t *testing.T) Episode {
	t.Helper()
	return f.detailAs(t, f.h.token)
}

// chapterTitles flattens an episode's chapters to their titles.
func chapterTitles(e Episode) []string {
	var out []string
	if e.Chapters != nil {
		for _, c := range *e.Chapters {
			out = append(out, deref(c.Title))
		}
	}
	return out
}

const chaptersDocV1 = `{"version":"1.2.0","chapters":[` +
	`{"startTime":2,"title":" After "},{"startTime":-1,"title":"Bad"},{"startTime":0,"title":"Before"}]}`

// The catalog reads an episode's chapters document when it downloads the
// episode, so one that is only streamed has none stored. Its detail still
// carries them, read from the feed's document, laid out the way stored
// chapters are: in start order, each ending where the next begins and the
// last at the episode's end.
func TestUnfetchedEpisodeDetailCarriesItsChapters(t *testing.T) {
	t.Parallel()
	doc := &docHost{}
	doc.set(http.StatusOK, chaptersDocV1)
	f := subscribeToChaptersFeed(t, doc, nil, "", nil)

	got := f.detail(t)
	if want := []string{"Before", "After"}; !slices.Equal(chapterTitles(got), want) {
		t.Fatalf("chapters = %v, want %v (in order, the negative start dropped, titles trimmed)", chapterTitles(got), want)
	}
	marks := *got.Chapters
	if marks[0].Index != 0 || marks[0].StartMs != 0 || derefInt64(marks[0].EndMs) != 2000 ||
		marks[1].Index != 1 || marks[1].StartMs != 2000 || derefInt64(marks[1].EndMs) != 3000 {
		t.Errorf("marks = %+v, want 0-2000 then 2000-3000 (the episode's declared length)", marks)
	}

	// A player reading the detail again, and again, does not ask the host
	// again.
	for range 2 {
		f.detail(t)
	}
	if n := doc.asked(); n != 1 {
		t.Errorf("the chapters host was asked %d times, want once", n)
	}
}

// A host that refuses, a document that is not chapters, and one with none
// all leave the detail as it always was: it answers, without chapters. The
// failure is remembered for a while, so a dead host is not asked on every
// read.
func TestUnreadableChaptersDocumentsLeaveTheDetailWithoutChapters(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name   string
		status int
		body   string
	}{
		{"missing", http.StatusNotFound, ""},
		{"failing", http.StatusInternalServerError, ""},
		{"garbage", http.StatusOK, "this is not json"},
		{"empty", http.StatusOK, `{"version":"1.2.0","chapters":[]}`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			doc := &docHost{}
			doc.set(tc.status, tc.body)
			f := subscribeToChaptersFeed(t, doc, nil, "", nil)

			for range 2 {
				if got := chapterTitles(f.detail(t)); len(got) != 0 {
					t.Fatalf("chapters = %v, want none", got)
				}
			}
			if n := doc.asked(); n != 1 {
				t.Errorf("the chapters host was asked %d times, want once", n)
			}
		})
	}
}

// What the catalog stored from a download is the episode's chapters, and
// what was read for display before it does not outlive it.
func TestStoredChaptersWinOverTheDocumentReadForDisplay(t *testing.T) {
	t.Parallel()
	doc := &docHost{}
	doc.set(http.StatusOK, chaptersDocV1)
	f := subscribeToChaptersFeed(t, doc, nil, "", nil)
	if got := chapterTitles(f.detail(t)); !slices.Equal(got, []string{"Before", "After"}) {
		t.Fatalf("chapters before the fetch = %v, want the document's", got)
	}

	// The feed revises its chapters, and the download reads the revision.
	doc.set(http.StatusOK, `{"chapters":[{"startTime":0,"title":"Revised"}]}`)
	wantStatus(t, f.h.postJSON(t, "/api/v1/episodes/"+f.episode.Pid+"/fetch", nil), http.StatusAccepted, "fetch")
	drainFetches(t, f.h)

	got := f.detail(t)
	if titles := chapterTitles(got); !slices.Equal(titles, []string{"Revised"}) {
		t.Errorf("chapters after the fetch = %v, want the stored ones", titles)
	}
}

// A private feed's host answers its chapters document to the show's
// stored credentials, as it does its transcript and its audio.
func TestChaptersDocumentIsReadWithTheShowsCredentials(t *testing.T) {
	t.Parallel()
	doc := &docHost{}
	doc.set(http.StatusOK, chaptersDocV1)
	f := subscribeToChaptersFeed(t, doc, memberOnly, "", memberCreds)

	if got := chapterTitles(f.detail(t)); !slices.Equal(got, []string{"Before", "After"}) {
		t.Errorf("chapters = %v, want the private document's", got)
	}
}

// The credentials are the show's, spent only for a subscriber: an episode
// read stays open to anyone who can see the podcast library, and the audio
// relay refuses the rest, so the chapters do too. Nothing is asked of the
// host for them, and the answer a subscriber's read kept is not theirs.
func TestChaptersOfACredentialedShowAreForItsSubscribersOnly(t *testing.T) {
	t.Parallel()
	doc := &docHost{}
	doc.set(http.StatusOK, chaptersDocV1)
	f := subscribeToChaptersFeed(t, doc, memberOnly, "", memberCreds)
	_, sam := listenerAccount(t, f.h, "sam", true)

	if got := chapterTitles(f.detailAs(t, sam)); len(got) != 0 {
		t.Fatalf("a non-subscriber read chapters %v", got)
	}
	if n := doc.asked(); n != 0 {
		t.Fatalf("the host was asked %d times on a non-subscriber's behalf", n)
	}

	if got := chapterTitles(f.detail(t)); !slices.Equal(got, []string{"Before", "After"}) {
		t.Fatalf("the subscriber read %v, want the document's", got)
	}
	if n := doc.asked(); n != 1 {
		t.Fatalf("the host was asked %d times for the subscriber, want once", n)
	}

	if got := chapterTitles(f.detailAs(t, sam)); len(got) != 0 {
		t.Errorf("a non-subscriber was handed the subscriber's kept chapters %v", got)
	}
	if n := doc.asked(); n != 1 {
		t.Errorf("the host was asked %d times in all, want the subscriber's one", n)
	}
}

// The credentials go to the feed's own host and nowhere else. A pointer at
// another host is read without them, which costs a document that is public
// on a CDN nothing.
func TestChaptersDocumentOnAnotherHostGetsNoCredentials(t *testing.T) {
	t.Parallel()
	doc, elsewhere := &docHost{}, &docHost{}
	doc.set(http.StatusOK, chaptersDocV1)
	elsewhere.set(http.StatusOK, chaptersDocV1)
	pointer := newChaptersElsewhere(t, elsewhere)
	f := subscribeToChaptersFeed(t, doc, memberOnly, pointer, memberCreds)

	if got := chapterTitles(f.detail(t)); !slices.Equal(got, []string{"Before", "After"}) {
		t.Fatalf("chapters = %v, want the other host's document", got)
	}
	if auths := elsewhere.authorizations(); len(auths) != 1 || auths[0] != "" {
		t.Errorf("the other host was sent %q, want one request with no Authorization", auths)
	}
	if n := doc.asked(); n != 0 {
		t.Errorf("the feed's own host was asked %d times for a document it does not hold", n)
	}
}

// A document that sends the reader elsewhere takes the credentials no
// further: they stay with the host that was asked for them, even where the
// other address is the same machine on another port, which is the case an
// HTTP client's own rule lets them through.
func TestChaptersDocumentRedirectedAwayLosesTheCredentials(t *testing.T) {
	t.Parallel()
	doc, elsewhere := &docHost{}, &docHost{}
	elsewhere.set(http.StatusOK, chaptersDocV1)
	doc.redirectTo(newChaptersElsewhere(t, elsewhere))
	f := subscribeToChaptersFeed(t, doc, memberOnly, "", memberCreds)

	if got := chapterTitles(f.detail(t)); !slices.Equal(got, []string{"Before", "After"}) {
		t.Fatalf("chapters = %v, want the document the redirect led to", got)
	}
	if auths := doc.authorizations(); len(auths) != 1 || auths[0] == "" {
		t.Errorf("the feed's host was sent %q, want one request with its credentials", auths)
	}
	if auths := elsewhere.authorizations(); len(auths) != 1 || auths[0] != "" {
		t.Errorf("the host the redirect led to was sent %q, want one request with no Authorization", auths)
	}
}

// A pointer at another host that sends the reader back to the feed's own
// host is read there with the credentials: each ask carries them by where
// it is, not by where the pointer was.
func TestChaptersDocumentSentBackToTheOriginGetsTheCredentials(t *testing.T) {
	t.Parallel()
	doc, elsewhere := &docHost{}, &docHost{}
	doc.set(http.StatusOK, chaptersDocV1)
	h := newPodcastHarness(t)
	feed := newChaptersFeed(t, doc, memberOnly, newChaptersElsewhere(t, elsewhere))
	elsewhere.redirectTo(strings.TrimSuffix(feed, "/feed.xml") + chaptersDoc)
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{
		"url": feed, "username": "member", "password": "s3cret",
	}), http.StatusCreated, "subscribe")
	eps := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items
	if len(eps) != 1 {
		t.Fatalf("episodes = %+v, want one", eps)
	}
	f := chaptersFixture{h: h, doc: doc, episode: eps[0]}

	if got := chapterTitles(f.detail(t)); !slices.Equal(got, []string{"Before", "After"}) {
		t.Fatalf("chapters = %v, want the feed's own document", got)
	}
	if auths := elsewhere.authorizations(); len(auths) != 1 || auths[0] != "" {
		t.Errorf("the other host was sent %q, want one request with no Authorization", auths)
	}
	if auths := doc.authorizations(); len(auths) != 1 || auths[0] == "" {
		t.Errorf("the feed's host was sent %q, want one request with its credentials", auths)
	}
}

// A document that moves within the feed's own origin keeps the credentials:
// the next ask goes to the host they belong to.
func TestChaptersDocumentMovedWithinTheOriginKeepsTheCredentials(t *testing.T) {
	t.Parallel()
	doc := &docHost{}
	doc.set(http.StatusOK, chaptersDocV1)
	doc.moveTo("/moved/chapters.json")
	f := subscribeToChaptersFeed(t, doc, memberOnly, "", memberCreds)

	if got := chapterTitles(f.detail(t)); !slices.Equal(got, []string{"Before", "After"}) {
		t.Fatalf("chapters = %v, want the document at its new path", got)
	}
	if auths := doc.authorizations(); len(auths) != 2 || auths[0] == "" || auths[1] != auths[0] {
		t.Errorf("the feed's host was sent %q, want both asks with its credentials", auths)
	}
}

// The chapters document is asked for by name, as the audio and the
// transcript are: some hosts refuse a client that does not say who it is.
func TestChaptersDocumentIsAskedForByName(t *testing.T) {
	t.Parallel()
	doc := &docHost{}
	doc.set(http.StatusOK, chaptersDocV1)
	f := subscribeToChaptersFeed(t, doc, nil, "", nil)

	f.detail(t)
	if agents := doc.userAgents(); len(agents) != 1 || !strings.HasPrefix(agents[0], "WaxDeck/") {
		t.Errorf("the chapters document was asked for as %q, want the server's name", agents)
	}
}
