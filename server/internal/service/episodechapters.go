package service

import (
	"bytes"
	"cmp"
	"container/list"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"github.com/colespringer/waxbin/model"
)

// An episode's chapters for display, read from the document its feed
// points at. The catalog reads that document only when it downloads the
// episode, so one played by enclosure passthrough has no stored chapters;
// the detail read fetches the document itself, the way the transcript cues
// are. Chapters the catalog stored always win.
//
// The address is the feed's to name and the read is open to anyone who can
// see the podcast library, so everything about the fetch is bounded: how
// long it may take, how much of the document is read, how many chapters and
// how long a title it may carry, how much of it is kept, and how many
// readers ask the host at once.

const (
	// chaptersFetchTimeout bounds one fetch, which sits on the detail read.
	// A healthy host answers in a fraction of it; one that does not costs
	// it once for all of its documents, not once per episode.
	chaptersFetchTimeout = 3 * time.Second
	// chaptersMaxBytes caps the body. A list at the chapter limit with every
	// title at its clip is about 600 KB, so no honest document meets it, and
	// a hostile one is stopped where even reading it is cheap.
	chaptersMaxBytes = 1 << 20
	// chaptersMaxMarks refuses a list no show has, and chaptersMaxTitle clips
	// a title past what a chapter list can draw. chaptersMaxStart is the
	// latest start, in seconds, that is a time on an episode's timeline:
	// past it a start in milliseconds would wrap.
	chaptersMaxMarks = 2000
	chaptersMaxTitle = 256
	chaptersMaxStart = 1e9
	// chaptersHitTTL keeps a document that held chapters, and
	// chaptersMissTTL one that failed or held none: a host that is down is
	// asked now and then, and chapters a feed adds later are seen.
	chaptersHitTTL  = 6 * time.Hour
	chaptersMissTTL = 10 * time.Minute
	// chaptersCacheMax and chaptersCacheBytes bound what is kept, by entries
	// and by weight; the oldest entry goes first. The per-entry and per-mark
	// figures are the weight of what an entry holds beyond its titles.
	chaptersCacheMax   = 512
	chaptersCacheBytes = 4 << 20
	chaptersEntryBytes = 128
	chaptersMarkBytes  = 48
)

// errChaptersRefused marks a request stopped by the fetch's own redirect
// rules, which no host is to blame for. errChaptersTooLarge, errChaptersDoc
// and chaptersStatus are the document's and the host's failures, typed so
// the log can say which stopped a read without the error's text, which
// repeats the address.
var (
	errChaptersRefused  = errors.New("chapters redirect refused")
	errChaptersTooLarge = errors.New("chapters document exceeds the size cap")
	errChaptersDoc      = errors.New("parsing chapters document")
)

type chaptersStatus int

func (s chaptersStatus) Error() string {
	return fmt.Sprintf("chapters host answered status %d", int(s))
}

// chaptersCause names what stopped a chapters read in words that carry no
// address, as feedCause does for a feed's.
func chaptersCause(err error) string {
	var status chaptersStatus
	switch {
	case errors.As(err, &status):
		return "status " + strconv.Itoa(int(status))
	case errors.Is(err, errChaptersRefused):
		return "redirect refused"
	case errors.Is(err, errChaptersTooLarge):
		return "size limit"
	case errors.Is(err, errChaptersDoc):
		return "not a chapters document"
	}
	return feedCause(err)
}

// chaptersHostError is a request that got no answer from the host it was
// made to, as against a document that is missing or bad. The host is the one
// that failed, which a redirect makes other than the one the pointer named.
type chaptersHostError struct {
	host string
	err  error
}

func (e *chaptersHostError) Error() string {
	return "chapters host " + e.host + " gave no answer: " + e.err.Error()
}

func (e *chaptersHostError) Unwrap() error { return e.err }

// chaptersAsk is the request a fetch has in flight and when it was sent. A
// redirect moves it to another host.
type chaptersAsk struct {
	host  string
	since time.Time
}

// failed types what stopped the request in flight as its host's failure to
// answer. Two stops are not: the fetch's own redirect rules, and the budget
// running out under a request sent with under half of it left, which shows
// only that the time was spent before the request got there.
func (a *chaptersAsk) failed(budgetSpent bool, budget time.Duration, err error) error {
	if errors.Is(err, errChaptersRefused) || (budgetSpent && time.Since(a.since) < budget/2) {
		return err
	}
	return &chaptersHostError{host: a.host, err: err}
}

// fetchedChapters answers the chapters of an episode the catalog holds
// none for, from its feed's chapters document, for the reader userID. A
// failure is no chapters: the read that asked has its answer without them.
func (l *Library) fetchedChapters(ctx context.Context, userID string, ep *model.Episode) []ChapterMark {
	rawURL := strings.TrimSpace(ep.ChaptersURL)
	target, err := url.Parse(rawURL)
	if rawURL == "" || err != nil || (target.Scheme != "http" && target.Scheme != "https") || target.Host == "" {
		return nil
	}
	// A credentialed show's feed is read on the terms its audio is: for a
	// subscriber, and for no one else, before anything is asked or kept. A
	// show that cannot be read gives none, as it relays nothing.
	pod, err := l.readShow(ctx, ep.PodcastPID)
	if err != nil {
		return nil
	}
	user, pass, err := l.feedCredentials(ctx, userID, pod)
	if err != nil {
		return nil
	}
	login := feedLogin{feedURL: pod.FeedURL, user: user, pass: pass}

	key := chaptersKey{episode: ep.PID, url: rawURL}
	for {
		marks, kept, call, lead := l.chapterDocs.claim(key, chaptersHostKey(target.Host))
		switch {
		case kept:
			return marks
		case lead:
			return l.readChapters(ctx, ep, rawURL, login, key, call)
		}
		select {
		case <-call.done:
			if call.settled {
				return slices.Clone(call.marks)
			}
			// The reader who led left before the host answered: take its place.
		case <-ctx.Done():
			return nil
		}
	}
}

// readChapters leads one fetch: it asks the host, settles the call for the
// readers waiting on it, and remembers the outcome, and the host too when it
// gave no answer.
func (l *Library) readChapters(ctx context.Context, ep *model.Episode, rawURL string, login feedLogin, key chaptersKey, call *chaptersCall) []ChapterMark {
	var marks []ChapterMark
	settled := false
	defer func() { l.chapterDocs.settle(key, call, marks, settled) }()

	got, err := l.fetchChapters(ctx, ep, rawURL, login)
	switch {
	case err == nil:
		marks, settled = got, true
	case ctx.Err() != nil:
		// The reader left; the host has not been judged.
	default:
		settled = true
		host := ""
		if u, perr := url.Parse(key.url); perr == nil {
			host = u.Host
		}
		var down *chaptersHostError
		if errors.As(err, &down) {
			host = down.host
			l.chapterDocs.put(chaptersHostKey(down.host), nil)
		}
		// The host and the cause, never the error: its text repeats the
		// document's address, which can carry the feed's token.
		l.log.Debug("reading an episode's chapters document", "episode", ep.PID, "host", host, "cause", chaptersCause(err))
	}
	return marks
}

// fetchChapters pulls and parses one chapters document through the transcript
// fetch's guarded client, the show's login on each request at its feed's
// origin.
func (l *Library) fetchChapters(ctx context.Context, ep *model.Episode, rawURL string, login feedLogin) ([]ChapterMark, error) {
	budget := l.chapterDocs.budget()
	fetchCtx, cancel := context.WithTimeout(ctx, budget)
	defer cancel()
	req, err := http.NewRequestWithContext(fetchCtx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, fmt.Errorf("bad chapters url: %w", err)
	}
	req.Header.Set("User-Agent", l.UserAgent())
	ask := &chaptersAsk{host: req.URL.Host, since: time.Now()}
	resp, err := sendWithLogin(l.chaptersClient(ask), req, login)
	if err != nil {
		return nil, ask.failed(fetchCtx.Err() != nil, budget, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, chaptersStatus(resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, chaptersMaxBytes+1))
	if err != nil {
		return nil, ask.failed(fetchCtx.Err() != nil, budget, err)
	}
	if len(body) > chaptersMaxBytes {
		return nil, errChaptersTooLarge
	}
	return parseChaptersDoc(body, ep.DurationMS)
}

// chaptersClient is the guarded client with a say in every redirect hop,
// which it reports to ask. A hop is followed only to a web address, to a
// host not known to be down, and within the guarded client's cap. The copy
// shares the guarded client's transport, and so its dial guard.
func (l *Library) chaptersClient(ask *chaptersAsk) *http.Client {
	base := l.transcriptClient()
	client := *base
	client.CheckRedirect = func(next *http.Request, via []*http.Request) error {
		if scheme := next.URL.Scheme; scheme != "http" && scheme != "https" {
			return fmt.Errorf("%w: not a web address", errChaptersRefused)
		}
		if _, down := l.chapterDocs.get(chaptersHostKey(next.URL.Host)); down {
			return fmt.Errorf("%w: host is known to be down", errChaptersRefused)
		}
		if base.CheckRedirect != nil {
			if err := base.CheckRedirect(next, via); err != nil {
				return fmt.Errorf("%w: %w", errChaptersRefused, err)
			}
		}
		ask.host, ask.since = next.URL.Host, time.Now()
		return nil
	}
	return &client
}

// chaptersDocEntry is one chapter as the document lists it.
type chaptersDocEntry struct {
	StartTime float64 `json:"startTime"`
	Title     string  `json:"title"`
}

// readChaptersDoc lists the chapters of a document, refusing a list past
// the limit as soon as it is seen to be one: the entries are read one at a
// time, so what a hostile list costs is the limit, not its length.
func readChaptersDoc(body []byte) ([]chaptersDocEntry, error) {
	bad := func(err error) error { return fmt.Errorf("%w: %w", errChaptersDoc, err) }
	dec := json.NewDecoder(bytes.NewReader(body))
	if tok, err := dec.Token(); err != nil {
		return nil, bad(err)
	} else if d, ok := tok.(json.Delim); !ok || d != '{' {
		return nil, bad(errors.New("not an object"))
	}
	var entries []chaptersDocEntry
	for dec.More() {
		tok, err := dec.Token()
		if err != nil {
			return nil, bad(err)
		}
		if key, _ := tok.(string); !strings.EqualFold(key, "chapters") {
			var skip json.RawMessage
			if err := dec.Decode(&skip); err != nil {
				return nil, bad(err)
			}
			continue
		}
		// The last list wins, as it does for the catalog's decoder.
		entries = entries[:0]
		tok, err = dec.Token()
		if err != nil {
			return nil, bad(err)
		}
		if tok == nil {
			continue
		}
		if d, ok := tok.(json.Delim); !ok || d != '[' {
			return nil, bad(errors.New("chapters is not a list"))
		}
		for dec.More() {
			if len(entries) == chaptersMaxMarks {
				return nil, fmt.Errorf("%w: it lists more than the %d chapters allowed", errChaptersDoc, chaptersMaxMarks)
			}
			var entry chaptersDocEntry
			if err := dec.Decode(&entry); err != nil {
				return nil, bad(err)
			}
			entries = append(entries, entry)
		}
		if _, err := dec.Token(); err != nil {
			return nil, bad(err)
		}
	}
	if _, err := dec.Token(); err != nil {
		return nil, bad(err)
	}
	if _, err := dec.Token(); err != io.EOF {
		return nil, bad(errors.New("data after the document"))
	}
	return entries, nil
}

// parseChaptersDoc reads a Podcasting 2.0 chapters document the way the
// catalog does when it stores one: start times in seconds, titles trimmed,
// in start order, with negative starts (and ones past any timeline)
// dropped and chapters that share a start collapsed to the last. Each
// chapter ends where the next begins and the last at durationMS, when that
// is past its start, so a client draws the same marks from either source.
// A title is clipped to chaptersMaxTitle bytes.
func parseChaptersDoc(body []byte, durationMS int64) ([]ChapterMark, error) {
	entries, err := readChaptersDoc(body)
	if err != nil {
		return nil, err
	}
	slices.SortStableFunc(entries, func(a, b chaptersDocEntry) int {
		return cmp.Compare(a.StartTime, b.StartTime)
	})
	var marks []ChapterMark
	for _, c := range entries {
		if c.StartTime < 0 || c.StartTime > chaptersMaxStart {
			continue
		}
		mark := ChapterMark{Title: clipTitle(strings.TrimSpace(c.Title)), StartMS: int64(c.StartTime * 1000)}
		if n := len(marks); n > 0 && marks[n-1].StartMS == mark.StartMS {
			marks[n-1] = mark
			continue
		}
		marks = append(marks, mark)
	}
	for i := range marks {
		marks[i].Index = i
		if i+1 < len(marks) {
			marks[i].EndMS = marks[i+1].StartMS
		} else if durationMS > marks[i].StartMS {
			marks[i].EndMS = durationMS
		}
	}
	return marks, nil
}

// clipTitle cuts a title to chaptersMaxTitle bytes at a character boundary.
func clipTitle(s string) string {
	if len(s) <= chaptersMaxTitle {
		return s
	}
	cut := chaptersMaxTitle
	for cut > 0 && !utf8.RuneStart(s[cut]) {
		cut--
	}
	return s[:cut]
}

// chaptersKey names a document as one episode points at it, so a feed that
// moves its chapters is read again. A key with no episode names a host.
type chaptersKey struct {
	episode model.PID
	url     string
}

// chaptersHostKey names a host whose documents are not asked for while it is
// known to be down.
func chaptersHostKey(host string) chaptersKey {
	return chaptersKey{url: "host " + strings.ToLower(host)}
}

// ownMarks copies a list and its titles. A title clipped out of a larger
// decoded string keeps all of that string alive, so what the cache keeps is
// a copy of its own, and weighs what it holds.
func ownMarks(marks []ChapterMark) []ChapterMark {
	owned := slices.Clone(marks)
	for i := range owned {
		owned[i].Title = strings.Clone(owned[i].Title)
	}
	return owned
}

type chaptersEntry struct {
	key     chaptersKey
	marks   []ChapterMark
	size    int
	expires time.Time
}

// chaptersCall is one fetch in flight, which the readers who asked for the
// same document meanwhile wait on. settled is false when the reader who led
// it left before the host answered, so what it found is no one's answer.
type chaptersCall struct {
	done    chan struct{}
	marks   []ChapterMark
	settled bool
}

// chaptersCache keeps what chapters documents read, in memory, and the
// fetches in flight for them: a restart reads them again, which costs one
// small request each. The zero value works.
type chaptersCache struct {
	mu      sync.Mutex
	entries map[chaptersKey]*list.Element // of *chaptersEntry
	order   list.List                     // oldest first
	bytes   int
	calls   map[chaptersKey]*chaptersCall
	now     func() time.Time // test seam
	timeout time.Duration    // test seam: the fetch budget, zero for chaptersFetchTimeout
}

func (c *chaptersCache) clock() time.Time {
	if c.now != nil {
		return c.now()
	}
	return time.Now()
}

func (c *chaptersCache) budget() time.Duration {
	if c.timeout > 0 {
		return c.timeout
	}
	return chaptersFetchTimeout
}

// get answers a kept document's chapters, which are none for one that
// failed or held none, and whether anything is kept.
func (c *chaptersCache) get(key chaptersKey) ([]ChapterMark, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.keptLocked(key)
}

func (c *chaptersCache) keptLocked(key chaptersKey) ([]ChapterMark, bool) {
	el, ok := c.entries[key]
	if !ok {
		return nil, false
	}
	e := el.Value.(*chaptersEntry)
	if !c.clock().Before(e.expires) {
		c.removeLocked(el)
		return nil, false
	}
	return slices.Clone(e.marks), true
}

// put keeps what a document read, for as long as its kind of result is
// worth trusting. A failure does not replace a success that is still fresh.
func (c *chaptersCache) put(key chaptersKey, marks []ChapterMark) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.putLocked(key, marks)
}

func (c *chaptersCache) putLocked(key chaptersKey, marks []ChapterMark) {
	ttl := chaptersMissTTL
	if len(marks) > 0 {
		ttl = chaptersHitTTL
	}
	if el, ok := c.entries[key]; ok {
		if cur := el.Value.(*chaptersEntry); len(marks) == 0 && len(cur.marks) > 0 && c.clock().Before(cur.expires) {
			return
		}
		c.removeLocked(el)
	}
	if c.entries == nil {
		c.entries = map[chaptersKey]*list.Element{}
	}
	e := &chaptersEntry{
		key:     chaptersKey{episode: model.PID(strings.Clone(string(key.episode))), url: strings.Clone(key.url)},
		marks:   ownMarks(marks),
		expires: c.clock().Add(ttl),
	}
	e.size = chaptersEntryBytes + len(e.key.episode) + len(e.key.url) + len(e.marks)*chaptersMarkBytes
	for _, m := range e.marks {
		e.size += len(m.Title)
	}
	c.entries[e.key] = c.order.PushBack(e)
	c.bytes += e.size
	for c.order.Len() > 0 && (c.order.Len() > chaptersCacheMax || c.bytes > chaptersCacheBytes) {
		c.removeLocked(c.order.Front())
	}
}

func (c *chaptersCache) removeLocked(el *list.Element) {
	e := c.order.Remove(el).(*chaptersEntry)
	delete(c.entries, e.key)
	c.bytes -= e.size
}

// claim answers what is kept for a document, or for its host being down,
// else the fetch already in flight for it, else a new fetch the caller
// leads and must settle.
func (c *chaptersCache) claim(key, host chaptersKey) (marks []ChapterMark, kept bool, call *chaptersCall, lead bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if marks, ok := c.keptLocked(key); ok {
		return marks, true, nil, false
	}
	if _, ok := c.keptLocked(host); ok {
		return nil, true, nil, false
	}
	if call, ok := c.calls[key]; ok {
		return nil, false, call, false
	}
	if c.calls == nil {
		c.calls = map[chaptersKey]*chaptersCall{}
	}
	call = &chaptersCall{done: make(chan struct{})}
	c.calls[key] = call
	return nil, false, call, true
}

// settle ends a fetch led from claim: what it found is kept when settled,
// and the readers waiting on it are let go.
func (c *chaptersCache) settle(key chaptersKey, call *chaptersCall, marks []ChapterMark, settled bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.calls[key] == call {
		delete(c.calls, key)
	}
	call.marks, call.settled = slices.Clone(marks), settled
	if settled {
		c.putLocked(key, marks)
	}
	close(call.done)
}
