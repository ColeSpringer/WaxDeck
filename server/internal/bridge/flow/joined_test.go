package flow

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxflow/codec/mp3"

	"github.com/colespringer/waxdeck/fixtures"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/mp3join"
)

// mp3Part renders a tagged MP3 the way the engine streams one: an ID3v2
// tag, an Info frame stating the part's own length, then the audio.
func mp3Part(t *testing.T, dir, name string, d time.Duration, rate, channels int) []byte {
	t.Helper()
	paths, err := fixtures.Generate(dir, fixtures.Spec{
		Name: name, Codec: fixtures.CodecMP3, Duration: d,
		SampleRate: rate, Channels: channels,
		Tags: map[string]string{"TITLE": name},
	})
	if err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// mp3Frames splits a bare MP3 stream into its frames, failing on any byte
// that is not part of one.
func mp3Frames(t *testing.T, b []byte) [][]byte {
	t.Helper()
	var frames [][]byte
	for off := 0; off < len(b); {
		h, err := mp3.ParseHeader(b[off:])
		if err != nil || h.Size() == 0 || off+h.Size() > len(b) {
			t.Fatalf("byte %d of %d is not the start of a whole frame (%v)", off, len(b), err)
		}
		frames = append(frames, b[off:off+h.Size()])
		off += h.Size()
	}
	return frames
}

// partSpec is one part of a test book: what the catalog says of it.
type partSpec struct {
	name        string
	d           time.Duration
	codec       string
	bitrateKbps int
	rate, ch    int
}

// book is a multi-file book on disk and its catalog layout. The engine
// stand-in serves each part as the rendered MP3 under its root reference,
// whatever it is asked for: what the real engine would encode.
type book struct {
	dir   string
	parts []Part
	mp3   map[string][]byte // root reference to the part's rendering
}

func newBook(t *testing.T, specs ...partSpec) *book {
	t.Helper()
	bk := &book{dir: t.TempDir(), mp3: map[string][]byte{}}
	for _, s := range specs {
		rate, ch := s.rate, s.ch
		if rate == 0 {
			rate = 44100
		}
		if ch == 0 {
			ch = 2
		}
		rendered := mp3Part(t, bk.dir, s.name, s.d, rate, ch)
		path := filepath.Join(bk.dir, s.name+".mp3")
		fi, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		bk.mp3["lib/"+s.name+".mp3"] = rendered
		bk.parts = append(bk.parts, Part{
			FilePID: "fi-" + s.name,
			Src: Source{
				Path: path, Size: fi.Size(), MTimeNS: fi.ModTime().UnixNano(),
				Codec: s.codec, Container: s.codec, BitrateKbps: s.bitrateKbps,
				DurationMS: s.d.Milliseconds(), SpokenWord: true,
			},
			Rate: s.rate, Channels: s.ch,
		})
	}
	return bk
}

func (bk *book) StreamSource(_ context.Context, _, filePID string) (Source, error) {
	for _, p := range bk.parts {
		if filePID == "" || p.FilePID == filePID {
			return p.Src, nil
		}
	}
	return Source{}, errors.New("no such part")
}

func (bk *book) StreamParts(context.Context, string) ([]Part, error) { return bk.parts, nil }

// newJoinedBridge is newTestBridge over a book, with the engine stand-in
// answering every request but /caps.
func newJoinedBridge(t *testing.T, engine http.HandlerFunc, bk *book) (*Bridge, *fakeGate) {
	t.Helper()
	fake := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/caps" {
			fmt.Fprint(w, capsJSON())
			return
		}
		engine(w, r)
	}))
	t.Cleanup(fake.Close)
	b, err := New(context.Background(), Config{
		BaseURL:  fake.URL,
		APIKey:   "key",
		Roots:    []Root{{Name: "lib", Path: bk.dir}},
		Tokens:   auth.NewMediaTokens([]byte("test-secret-test-secret-test-sec"), 0),
		Resolver: bk,
	})
	if err != nil {
		t.Fatal(err)
	}
	connect(t, b)
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)
	return b, gate
}

// mintJoined mints the book as one stream and answers the info and the
// parameters its URL carries.
func mintJoined(t *testing.T, b *Bridge, opts PlayOptions) (PlayInfo, url.Values) {
	t.Helper()
	info, err := b.JoinedPlayInfo(context.Background(), "us-1", "bk-X", opts)
	if err != nil {
		t.Fatal(err)
	}
	u, err := url.Parse(info.URL)
	if err != nil {
		t.Fatal(err)
	}
	return info, u.Query()
}

// threeParts is the book most tests play: 4, 5 and 6 s of 64 kbps AAC.
func threeParts(t *testing.T) *book {
	return newBook(t,
		partSpec{name: "one", d: 4 * time.Second, codec: "aac", bitrateKbps: 64},
		partSpec{name: "two", d: 5 * time.Second, codec: "aac", bitrateKbps: 64},
		partSpec{name: "three", d: 6 * time.Second, codec: "aac", bitrateKbps: 64})
}

// A book in parts mints as one stream from the part the position falls
// in: that part cut there, the rest whole after it, all of it MP3.
func TestJoinedPlayInfoMintsTheRestOfTheBookAsOneStream(t *testing.T) {
	b, _ := newJoinedBridge(t, http.NotFound, threeParts(t))
	info, q := mintJoined(t, b, PlayOptions{FilePID: "fi-two", StartMS: 2500})
	if q.Get("f") != "fi-two" || q.Get("join") != "1" || q.Get("fmt") != "mp3" || q.Get("t") != "2.5" {
		t.Fatalf("minted %s, want part two joined to the end as mp3, cut at 2.5", info.URL)
	}
	if info.MimeType != "audio/mpeg" || info.Seekable || info.StartOffsetMS != 2500 || info.DurationMS != 11_000 {
		t.Fatalf("info = %+v, want unseekable audio/mpeg of parts two and three, from 2.5 s in", info)
	}
	// The caller aligns the cut on the book, where whole seconds share an
	// encode; in the part it lands to the millisecond, inside the part.
	for start, want := range map[int64]string{630: "0.63", 999_999: "4.999"} {
		info, q := mintJoined(t, b, PlayOptions{FilePID: "fi-two", StartMS: start})
		if wantMS, _ := strconv.ParseFloat(want, 64); q.Get("t") != want || info.StartOffsetMS != int64(wantMS*1000+0.5) {
			t.Errorf("a start %d ms in = t %q, offset %d; want %s", start, q.Get("t"), info.StartOffsetMS, want)
		}
	}

	// From the top it opens on the first part, uncut.
	info, q = mintJoined(t, b, PlayOptions{})
	if q.Get("f") != "fi-one" || q.Get("join") != "1" || q.Has("t") || info.DurationMS != 15_000 || info.StartOffsetMS != 0 {
		t.Fatalf("from the top: %s (%+v), want the whole book from part one", info.URL, info)
	}
}

// The rate is the book's own, lowered and never raised by a client cap
// and the account's ceiling. A lossless or unmeasured part holds the book
// at the top rate.
func TestJoinedPlayInfoTakesTheBooksOwnRate(t *testing.T) {
	lossy := newBook(t,
		partSpec{name: "a", d: time.Second, codec: "mp3", bitrateKbps: 64},
		partSpec{name: "b", d: time.Second, codec: "mp3", bitrateKbps: 96})
	lossless := newBook(t,
		partSpec{name: "a", d: time.Second, codec: "mp3", bitrateKbps: 64},
		partSpec{name: "b", d: time.Second, codec: "flac", bitrateKbps: 900})
	unmeasured := newBook(t,
		partSpec{name: "a", d: time.Second, codec: "mp3", bitrateKbps: 64},
		partSpec{name: "b", d: time.Second, codec: "mp3"})
	for _, c := range []struct {
		name    string
		bk      *book
		cap     int
		ceiling int
		want    string
	}{
		{"the highest part's own", lossy, 0, 0, "96"},
		{"a cap above it", lossy, 128, 0, "96"},
		{"a cap below it", lossy, 48, 0, "48"},
		{"a cap below any codec's floor", lossy, 8, 0, "32"},
		{"the account's ceiling", lossy, 0, 40, "40"},
		{"a lossless part", lossless, 0, 0, "320"},
		{"a lossless part under a huge cap", lossless, 9999, 0, "320"},
		{"an unmeasured part", unmeasured, 0, 0, "320"},
	} {
		b, gate := newJoinedBridge(t, http.NotFound, c.bk)
		gate.ceiling = c.ceiling
		_, q := mintJoined(t, b, PlayOptions{MaxBitrateKbps: c.cap})
		if q.Get("br") != c.want {
			t.Errorf("%s: br = %q, want %s", c.name, q.Get("br"), c.want)
		}
	}
}

// engine stands in for the sidecar under joined fetches: it serves each
// part's rendering by root reference and records every request in order.
type engine struct {
	bk *book
	mu sync.Mutex
	// got is every request, in arrival order.
	got []engineReq
	// fail answers a part with this status in the engine's envelope,
	// under the engine's own code for it unless code names another.
	fail map[string]int
	code map[string]string
	// busy refuses a part this many times as the engine's pool being
	// full before it serves it; a negative count refuses it every time.
	busy map[string]int
	// endsEarly sends this many bytes of a part and ends the response
	// well-formed, as the engine ends a live encode that failed part-way.
	endsEarly map[string]int
	// cutShort sends half a part and drops the connection; hold sends half
	// and waits for the request to end, closing left when it does.
	cutShort, hold string
	left           chan struct{}
}

type engineReq struct {
	method, apiKey string
	q              url.Values
}

func newEngine(bk *book) *engine {
	return &engine{bk: bk, fail: map[string]int{}, code: map[string]string{}, busy: map[string]int{},
		endsEarly: map[string]int{}, left: make(chan struct{})}
}

// set changes the stand-in's behaviour under its lock: the server's
// goroutines read it.
func (e *engine) set(f func(*engine)) {
	e.mu.Lock()
	defer e.mu.Unlock()
	f(e)
}

func (e *engine) requests() []engineReq {
	e.mu.Lock()
	defer e.mu.Unlock()
	return append([]engineReq(nil), e.got...)
}

func (e *engine) serve(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	src := q.Get("src")
	e.mu.Lock()
	e.got = append(e.got, engineReq{r.Method, r.Header.Get("X-API-Key"), q})
	status, code, cutShort, hold := e.fail[src], e.code[src], e.cutShort == src, e.hold == src
	busy, early := e.busy[src] != 0, e.endsEarly[src]
	if e.busy[src] > 0 {
		e.busy[src]--
	}
	e.mu.Unlock()
	retryAfter := "3"
	if busy {
		status, code, retryAfter = http.StatusServiceUnavailable, "overloaded", "1"
	}
	if status != 0 {
		if code == "" {
			code = map[int]string{404: "not-found", 410: "source-changed", 500: "internal", 503: "overloaded"}[status]
		}
		w.Header().Set("Content-Type", "application/json")
		if status == http.StatusServiceUnavailable {
			w.Header().Set("Retry-After", retryAfter)
		}
		w.WriteHeader(status)
		fmt.Fprintf(w, `{"schemaVersion":1,"code":%q,"error":"refused"}`, code)
		return
	}
	body, ok := e.bk.mp3[src]
	if !ok {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "audio/mpeg")
	switch {
	case r.Method == http.MethodHead:
		w.WriteHeader(http.StatusOK)
	case early > 0:
		w.Write(body[:early])
		w.(http.Flusher).Flush()
	case cutShort:
		w.Header().Set("Content-Length", strconv.Itoa(len(body)))
		w.Write(body[:len(body)/2])
	case hold:
		w.Write(body[:len(body)/2])
		w.(http.Flusher).Flush()
		<-r.Context().Done()
		close(e.left)
	default:
		w.Write(body)
	}
}

// fetchJoined serves req through ServeStream and says whether the handler
// broke the response off, as net/http does for ErrAbortHandler.
func fetchJoined(t *testing.T, b *Bridge, req *http.Request) (rec *httptest.ResponseRecorder, aborted bool) {
	t.Helper()
	rec = httptest.NewRecorder()
	func() {
		defer func() {
			if v := recover(); v != nil {
				if v != http.ErrAbortHandler {
					panic(v)
				}
				aborted = true
			}
		}()
		b.ServeStream(rec, req)
	}()
	return rec, aborted
}

// audioOf is the named parts end to end as the frame copier passes each
// whole one (mp3join's own tests pin what that is).
func audioOf(t *testing.T, bk *book, names ...string) []byte {
	t.Helper()
	var out bytes.Buffer
	for _, n := range names {
		if _, readErr, writeErr := mp3join.Copy(&out, bytes.NewReader(bk.mp3["lib/"+n+".mp3"]), mp3join.Shape{}, func() {}); readErr != nil || writeErr != nil {
			t.Fatal(readErr, writeErr)
		}
	}
	return out.Bytes()
}

// The book plays as one stream from the part the URL opens on: that part
// from its cut, then each part after it whole and in order, all encoded
// to one format, copied out as bare frames under a live encode's headers.
func TestServeStreamJoinsTheBookFromItsStartPart(t *testing.T) {
	bk := threeParts(t)
	e := newEngine(bk)
	b, gate := newJoinedBridge(t, e.serve, bk)
	info, _ := mintJoined(t, b, PlayOptions{FilePID: "fi-two", StartMS: 2500})

	rec, aborted := fetchJoined(t, b, httptest.NewRequest("GET", info.URL, nil))
	if aborted || rec.Code != 200 {
		t.Fatalf("joined fetch = %d (aborted %v): %.200s", rec.Code, aborted, rec.Body.String())
	}
	h := rec.Header()
	if h.Get("Content-Type") != "audio/mpeg" || h.Get("Content-Length") != "" ||
		h.Get("Accept-Ranges") != "none" || h.Get("Cache-Control") != "no-store" {
		t.Fatalf("headers = %v, want a live mp3 encode's: no length, no ranges, no store", h)
	}
	if want := audioOf(t, bk, "two", "three"); !bytes.Equal(rec.Body.Bytes(), want) {
		t.Fatalf("body = %d bytes, want the %d bytes of parts two and three's frames", rec.Body.Len(), len(want))
	}
	got := e.requests()
	if len(got) != 2 {
		t.Fatalf("the engine saw %d requests, want parts two and three", len(got))
	}
	for i, want := range []struct{ src, cut string }{{"lib/two.mp3", "2.5"}, {"lib/three.mp3", ""}} {
		q := got[i].q
		if got[i].method != "GET" || got[i].apiKey != "key" || q.Get("src") != want.src || q.Get("t") != want.cut ||
			q.Get("format") != "mp3" || q.Get("bitrate") != "64" || q.Get("rate") != "44100" || q.Get("ch") != "2" ||
			q.Get("id") == "" {
			t.Errorf("request %d = %s %v, want %s cut at %q as mp3 at 64 kbps, 44100 Hz stereo", i, got[i].method, q, want.src, want.cut)
		}
	}
	if gate.acquired != 1 || gate.held != 0 {
		t.Fatalf("slots taken %d, still held %d; want one for the whole book, given back", gate.acquired, gate.held)
	}
}

// One session slot covers the whole book, and a refused one opens no part.
func TestJoinedStreamIsOneTranscodeSession(t *testing.T) {
	bk := threeParts(t)
	e := newEngine(bk)
	b, gate := newJoinedBridge(t, e.serve, bk)
	info, _ := mintJoined(t, b, PlayOptions{})

	gate.refuse = true
	rec, _ := fetchJoined(t, b, httptest.NewRequest("GET", info.URL, nil))
	if rec.Code != http.StatusTooManyRequests || !strings.Contains(rec.Body.String(), "transcode-limited") {
		t.Fatalf("a full server = %d %s, want 429 transcode-limited", rec.Code, rec.Body.String())
	}
	if n := len(e.requests()); n != 0 {
		t.Fatalf("a refused stream asked the engine %d times", n)
	}

	gate.refuse = false
	rec, _ = fetchJoined(t, b, httptest.NewRequest("GET", info.URL, nil))
	if rec.Code != 200 || len(e.requests()) != 3 {
		t.Fatalf("the whole book = %d over %d engine requests, want 200 over 3", rec.Code, len(e.requests()))
	}
	if gate.acquired != 1 || gate.held != 0 || len(gate.kinds) != 1 || gate.kinds[0] != TranscodeStream {
		t.Fatalf("slots: %d taken (%v), %d held; want one stream slot for three parts, given back", gate.acquired, gate.kinds, gate.held)
	}
}

// A part that fails once audio has gone out breaks the response off after
// the last whole frame, so the listener's player sees a failed transfer
// rather than the book's end. The failure is logged and the slot goes back.
func TestJoinedStreamBreaksOffWhenALaterPartFails(t *testing.T) {
	for name, set := range map[string]func(*engine){
		"a part the engine refuses": func(e *engine) { e.fail["lib/three.mp3"] = 500 },
		"a part cut off mid-stream": func(e *engine) { e.cutShort = "lib/three.mp3" },
	} {
		t.Run(name, func(t *testing.T) {
			bk := threeParts(t)
			e := newEngine(bk)
			e.set(set)
			b, gate := newJoinedBridge(t, e.serve, bk)
			var logged bytes.Buffer
			b.log = slog.New(slog.NewTextHandler(&logged, nil))
			info, _ := mintJoined(t, b, PlayOptions{FilePID: "fi-two"})

			rec, aborted := fetchJoined(t, b, httptest.NewRequest("GET", info.URL, nil))
			if !aborted || rec.Code != 200 {
				t.Fatalf("status %d, aborted %v; want a 200 broken off", rec.Code, aborted)
			}
			body := rec.Body.Bytes()
			mp3Frames(t, body) // whole frames only
			if two := audioOf(t, bk, "two"); !bytes.HasPrefix(body, two) {
				t.Fatalf("body = %d bytes, want part two's %d whole first", len(body), len(two))
			}
			if !strings.Contains(logged.String(), "fi-three") {
				t.Fatalf("the failed part was not logged: %q", logged.String())
			}
			if gate.held != 0 {
				t.Fatalf("%d slots still held after the break", gate.held)
			}
		})
	}
}

// Before the first byte the first part's refusal is the response, in the
// API's own words, as for any stream: a busy engine is transcode-limited,
// a changed file stale; anything else keeps the engine's status.
func TestJoinedStreamAnswersTheFirstPartsRefusal(t *testing.T) {
	for _, c := range []struct {
		status     int
		want       int
		code       string
		retryAfter string
	}{
		{http.StatusServiceUnavailable, http.StatusTooManyRequests, "transcode-limited", "3"},
		{http.StatusGone, http.StatusGone, "stream-stale", ""},
		{http.StatusNotFound, http.StatusNotFound, "not-found", ""},
	} {
		bk := threeParts(t)
		e := newEngine(bk)
		e.set(func(e *engine) { e.fail["lib/one.mp3"] = c.status })
		b, gate := newJoinedBridge(t, e.serve, bk)
		info, _ := mintJoined(t, b, PlayOptions{})
		rec, aborted := fetchJoined(t, b, httptest.NewRequest("GET", info.URL, nil))
		var env struct{ Code string }
		json.Unmarshal(rec.Body.Bytes(), &env)
		if aborted || rec.Code != c.want || env.Code != c.code || rec.Header().Get("Retry-After") != c.retryAfter {
			t.Errorf("engine %d = %d %q (Retry-After %q, aborted %v), want %d %q", c.status, rec.Code, env.Code,
				rec.Header().Get("Retry-After"), aborted, c.want, c.code)
		}
		if n := len(e.requests()); n != 1 || gate.held != 0 {
			t.Errorf("engine %d: %d requests, %d slots held; want the first part asked alone, slot back", c.status, n, gate.held)
		}
	}
}

// serveAborts serves req through ServeStream into w and says whether the
// handler broke the response off, as net/http does for ErrAbortHandler.
func serveAborts(b *Bridge, w http.ResponseWriter, req *http.Request) (aborted bool) {
	defer func() {
		if v := recover(); v != nil {
			if v != http.ErrAbortHandler {
				panic(v)
			}
			aborted = true
		}
	}()
	b.ServeStream(w, req)
	return false
}

// A listener who leaves ends the response there: the part being read is
// let go, and no part after it is asked for.
func TestJoinedStreamStopsWhenTheListenerLeaves(t *testing.T) {
	bk := threeParts(t)
	e := newEngine(bk)
	e.set(func(e *engine) { e.hold = "lib/two.mp3" })
	b, gate := newJoinedBridge(t, e.serve, bk)
	info, _ := mintJoined(t, b, PlayOptions{FilePID: "fi-two"})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	w := &leavingWriter{ResponseRecorder: httptest.NewRecorder(), leave: cancel}
	serveAborts(b, w, httptest.NewRequest("GET", info.URL, nil).WithContext(ctx))
	select {
	case <-e.left:
	case <-time.After(10 * time.Second):
		t.Fatal("the engine's request for part two was never let go")
	}
	if n := len(e.requests()); n != 1 {
		t.Fatalf("the engine saw %d requests, want part two's alone", n)
	}
	if gate.held != 0 {
		t.Fatalf("%d slots still held after the listener left", gate.held)
	}
}

// leavingWriter is a client that hangs up as its first audio arrives.
type leavingWriter struct {
	*httptest.ResponseRecorder
	leave context.CancelFunc
}

func (w *leavingWriter) Write([]byte) (int, error) {
	w.leave()
	return 0, errors.New("the listener hung up")
}

// cancellingWriter is a listener still reading while the server cancels
// the request under it, as a shutdown does, once its first audio arrives.
type cancellingWriter struct {
	*httptest.ResponseRecorder
	cancel context.CancelFunc
}

func (w *cancellingWriter) Write(p []byte) (int, error) {
	w.cancel()
	return w.ResponseRecorder.Write(p)
}

// A request the server cancels (a shutdown cancels every one) breaks the
// response off as a lost part does: no length rides it, so a clean end
// would read as the book's end. Before the first byte it is the proxy's
// answer to an engine it could not reach, never an empty 200.
func TestJoinedStreamBreaksOffWhenTheServerCancels(t *testing.T) {
	bk := threeParts(t)
	e := newEngine(bk)
	e.set(func(e *engine) { e.hold = "lib/one.mp3" })
	b, gate := newJoinedBridge(t, e.serve, bk)
	info, _ := mintJoined(t, b, PlayOptions{})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	w := &cancellingWriter{ResponseRecorder: httptest.NewRecorder(), cancel: cancel}
	if !serveAborts(b, w, httptest.NewRequest("GET", info.URL, nil).WithContext(ctx)) {
		t.Fatalf("a request cancelled mid-part ended well-formed after %d bytes, want it broken off", w.Body.Len())
	}
	if gate.held != 0 {
		t.Fatalf("%d slots still held after the cancel", gate.held)
	}

	cancelled, cancelNow := context.WithCancel(context.Background())
	cancelNow()
	rec, aborted := fetchJoined(t, b, httptest.NewRequest("GET", info.URL, nil).WithContext(cancelled))
	if !aborted && rec.Code == http.StatusOK {
		t.Fatalf("a request cancelled before the first part = %d with %d bytes, want no 200", rec.Code, rec.Body.Len())
	}
	if gate.held != 0 {
		t.Fatalf("%d slots still held after the cancel", gate.held)
	}
}

// A part that holds no frame at all is lost whatever its length says: a
// part of a second or less, or of no known length, would otherwise pass
// within what a length rounds. Only the opening part of a cut stream may
// hold none, its cut landing past its last frame.
func TestJoinedStreamBreaksOffAtAPartHoldingNoFrame(t *testing.T) {
	for _, c := range []struct {
		name   string
		book   func(t *testing.T) *book
		empty  string
		opts   PlayOptions
		broken bool
	}{
		{"a part of a second", func(t *testing.T) *book {
			return newBook(t,
				partSpec{name: "one", d: 4 * time.Second, codec: "aac", bitrateKbps: 64},
				partSpec{name: "two", d: time.Second, codec: "aac", bitrateKbps: 64},
				partSpec{name: "three", d: 6 * time.Second, codec: "aac", bitrateKbps: 64})
		}, "lib/two.mp3", PlayOptions{}, true},
		{"a part of no known length", func(t *testing.T) *book {
			bk := threeParts(t)
			bk.parts[1].Src.DurationMS = 0
			return bk
		}, "lib/two.mp3", PlayOptions{}, true},
		{"the opening part cut past its last frame", threeParts, "lib/one.mp3",
			PlayOptions{FilePID: "fi-one", StartMS: 3999}, false},
	} {
		t.Run(c.name, func(t *testing.T) {
			bk := c.book(t)
			e := newEngine(bk)
			e.set(func(e *engine) { e.endsEarly[c.empty] = 1 })
			b, gate := newJoinedBridge(t, e.serve, bk)
			var logged bytes.Buffer
			b.log = slog.New(slog.NewTextHandler(&logged, nil))
			info, _ := mintJoined(t, b, c.opts)
			_, aborted := fetchJoined(t, b, httptest.NewRequest("GET", info.URL, nil))
			if aborted != c.broken {
				t.Fatalf("aborted %v after %d engine requests (log %q), want %v", aborted, len(e.requests()), logged.String(), c.broken)
			}
			if !c.broken && len(e.requests()) != 3 {
				t.Fatalf("the engine saw %d requests, want the book played on through part three", len(e.requests()))
			}
			if gate.held != 0 {
				t.Fatalf("%d slots still held", gate.held)
			}
		})
	}
}

// Ranges and HEAD as for any live encode: from the start is the whole
// stream, any other range is refused before a part opens or a slot is
// taken, and HEAD asks the engine about the first part without a body.
func TestJoinedStreamRangesAndHead(t *testing.T) {
	bk := threeParts(t)
	e := newEngine(bk)
	b, gate := newJoinedBridge(t, e.serve, bk)
	info, _ := mintJoined(t, b, PlayOptions{})

	req := httptest.NewRequest("GET", info.URL, nil)
	req.Header.Set("Range", "bytes=100-")
	rec, _ := fetchJoined(t, b, req)
	if rec.Code != http.StatusRequestedRangeNotSatisfiable || rec.Header().Get("Accept-Ranges") != "none" {
		t.Fatalf("a mid-stream range = %d (Accept-Ranges %q), want 416 none", rec.Code, rec.Header().Get("Accept-Ranges"))
	}
	if len(e.requests()) != 0 || gate.acquired != 0 {
		t.Fatalf("a refused range asked the engine %d times and took %d slots", len(e.requests()), gate.acquired)
	}

	req = httptest.NewRequest("GET", info.URL, nil)
	req.Header.Set("Range", "bytes=0-")
	rec, _ = fetchJoined(t, b, req)
	if rec.Code != 200 || !bytes.Equal(rec.Body.Bytes(), audioOf(t, bk, "one", "two", "three")) {
		t.Fatalf("a range from the start = %d with %d bytes, want 200 and the whole book", rec.Code, rec.Body.Len())
	}

	before := len(e.requests())
	rec, _ = fetchJoined(t, b, httptest.NewRequest("HEAD", info.URL, nil))
	if rec.Code != 200 || rec.Header().Get("Content-Type") != "audio/mpeg" || rec.Header().Get("Accept-Ranges") != "none" || rec.Body.Len() != 0 {
		t.Fatalf("HEAD = %d %v with %d bytes, want 200 audio/mpeg, no ranges, no body", rec.Code, rec.Header(), rec.Body.Len())
	}
	if got := e.requests()[before:]; len(got) != 1 || got[0].method != "HEAD" || got[0].q.Get("src") != "lib/one.mp3" {
		t.Fatalf("HEAD asked the engine %v, want one HEAD of the first part", got)
	}
}

// The cut is the client's to move, as on any cut stream, and lands on
// the first part only; a bad one is refused before anything opens.
func TestJoinedStreamCutIsTheFirstPartsAlone(t *testing.T) {
	bk := threeParts(t)
	e := newEngine(bk)
	b, gate := newJoinedBridge(t, e.serve, bk)
	info, _ := mintJoined(t, b, PlayOptions{FilePID: "fi-two", StartMS: 2500})

	rec, _ := fetchJoined(t, b, httptest.NewRequest("GET", withT(t, info.URL, "3.5"), nil))
	got := e.requests()
	if rec.Code != 200 || len(got) != 2 || got[0].q.Get("t") != "3.5" || got[1].q.Has("t") {
		t.Fatalf("a moved cut = %d over %v, want part two from 3.5 and part three whole", rec.Code, got)
	}
	// Past the first part's end, its last millisecond: the end itself is
	// an empty stream to the engine.
	rec, _ = fetchJoined(t, b, httptest.NewRequest("GET", withT(t, info.URL, "9"), nil))
	got = e.requests()
	if rec.Code != 200 || len(got) != 4 || got[2].q.Get("t") != "4.999" || got[3].q.Has("t") {
		t.Fatalf("a cut past the part = %d over %v, want part two from its last millisecond and part three whole", rec.Code, got[2:])
	}
	rec, _ = fetchJoined(t, b, httptest.NewRequest("GET", withT(t, info.URL, "abc"), nil))
	if rec.Code != http.StatusBadRequest || len(e.requests()) != 4 || gate.acquired != 2 {
		t.Fatalf("a bad cut = %d, asking the engine %d times and taking %d slots; want 400 with nothing opened",
			rec.Code, len(e.requests())-4, gate.acquired-2)
	}
}

// The account's ceiling is read again at fetch, as for any lossy encode,
// and the token binds the join: without it the URL is not the one minted.
func TestJoinedStreamFetchChecks(t *testing.T) {
	bk := threeParts(t)
	e := newEngine(bk)
	b, gate := newJoinedBridge(t, e.serve, bk)
	info, _ := mintJoined(t, b, PlayOptions{})

	gate.ceiling = 48
	if rec, _ := fetchJoined(t, b, httptest.NewRequest("GET", info.URL, nil)); rec.Code != 200 {
		t.Fatalf("fetch = %d", rec.Code)
	}
	for _, r := range e.requests() {
		if r.q.Get("bitrate") != "48" {
			t.Fatalf("the engine was asked for %q kbps under a 48 kbps ceiling", r.q.Get("bitrate"))
		}
	}

	u, _ := url.Parse(info.URL)
	q := u.Query()
	q.Del("join")
	u.RawQuery = q.Encode()
	if rec, _ := fetchJoined(t, b, httptest.NewRequest("GET", u.String(), nil)); rec.Code != http.StatusUnauthorized {
		t.Fatalf("the URL without its join = %d, want 401", rec.Code)
	}
}

// Every part is encoded to one envelope, since a player sets its decoder
// up once per stream: the highest part rate a frame can carry, rounded up,
// and the most channels, two at most; CD stereo where nothing is known.
func TestJoinedEnvelope(t *testing.T) {
	for _, c := range []struct {
		name           string
		parts          []Part
		rate, channels int
	}{
		{"one shape", []Part{{Rate: 22050, Channels: 1}, {Rate: 22050, Channels: 1}}, 22050, 1},
		{"mixed", []Part{{Rate: 22050, Channels: 1}, {Rate: 44100, Channels: 2}}, 44100, 2},
		{"unknown", []Part{{}, {}}, 44100, 2},
		{"above any frame's rate", []Part{{Rate: 96000, Channels: 6}}, 48000, 2},
		{"between rates", []Part{{Rate: 11000, Channels: 1}}, 11025, 1},
	} {
		if rate, channels := joinedEnvelope(c.parts); rate != c.rate || channels != c.channels {
			t.Errorf("%s: %d Hz x %d, want %d Hz x %d", c.name, rate, channels, c.rate, c.channels)
		}
	}
}

// infoCountUnstated is a rendering whose Info frame states no frame count,
// as the engine writes one for a source of unknown length.
func infoCountUnstated(t *testing.T, rendering []byte) []byte {
	t.Helper()
	out := append([]byte(nil), rendering...)
	size := int(out[6])<<21 | int(out[7])<<14 | int(out[8])<<7 | int(out[9])
	h, err := mp3.ParseHeader(out[10+size:])
	if err != nil {
		t.Fatal(err)
	}
	at := 10 + size + mp3.HeaderLen + h.SideInfoLen()
	if string(out[at:at+4]) != "Info" {
		t.Fatal("no Info frame to unstate")
	}
	copy(out[at+8:at+12], []byte{0, 0, 0, 0})
	return out
}

// The engine ends a live encode that fails part-way as cleanly as one
// that finishes, and no length rides it, so a part that ends well short
// of its length breaks the book off as a lost part does. Its length is
// the lesser of what its own Info frame states and the catalog's; a part
// a few frames short, within what a stated length rounds, plays on.
func TestJoinedStreamBreaksOffWhenAPartEndsShort(t *testing.T) {
	for _, c := range []struct {
		name     string
		unstated bool
		send     func(two []byte) int
		broken   bool
	}{
		{"half of a part", false, func(two []byte) int { return len(two) / 2 }, true},
		{"half of a part stating no length", true, func(two []byte) int { return len(two) / 2 }, true},
		{"a part but its last frames", false, func(two []byte) int { return len(two) - 5*418 }, false},
	} {
		t.Run(c.name, func(t *testing.T) {
			bk := threeParts(t)
			if c.unstated {
				bk.mp3["lib/two.mp3"] = infoCountUnstated(t, bk.mp3["lib/two.mp3"])
			}
			e := newEngine(bk)
			e.set(func(e *engine) { e.endsEarly["lib/two.mp3"] = c.send(bk.mp3["lib/two.mp3"]) })
			b, gate := newJoinedBridge(t, e.serve, bk)
			var logged bytes.Buffer
			b.log = slog.New(slog.NewTextHandler(&logged, nil))
			info, _ := mintJoined(t, b, PlayOptions{})

			rec, aborted := fetchJoined(t, b, httptest.NewRequest("GET", info.URL, nil))
			body := rec.Body.Bytes()
			mp3Frames(t, body) // whole frames only
			asked := len(e.requests())
			if c.broken {
				if !aborted || asked != 2 || !strings.Contains(logged.String(), "fi-two") {
					t.Fatalf("aborted %v after %d engine requests, log %q; want a break at part two, logged, part three never asked",
						aborted, asked, logged.String())
				}
				if one := audioOf(t, bk, "one"); !bytes.HasPrefix(body, one) {
					t.Fatalf("body = %d bytes, want part one's %d whole first", len(body), len(one))
				}
			} else if aborted || asked != 3 || !bytes.HasSuffix(body, audioOf(t, bk, "three")) {
				t.Fatalf("aborted %v after %d engine requests; want the book played on through part three", aborted, asked)
			}
			if gate.held != 0 {
				t.Fatalf("%d slots still held", gate.held)
			}
		})
	}
}

// At a seam the part needs a slot of the engine's own, and the engine
// refuses one only while its pool is full: that refusal is waited out as
// its Retry-After asks, a few times within a bound, before the book is
// broken off. Any other refusal there breaks it off at once.
func TestJoinedStreamWaitsOutABusyEngineAtASeam(t *testing.T) {
	defer func(u time.Duration) { seamWaitUnit = u }(seamWaitUnit)
	seamWaitUnit = time.Millisecond
	for _, c := range []struct {
		name     string
		set      func(e *engine)
		askedTwo int
		broken   bool
	}{
		{"busy once", func(e *engine) { e.busy["lib/two.mp3"] = 1 }, 2, false},
		{"busy throughout", func(e *engine) { e.busy["lib/two.mp3"] = -1 }, 4, true},
		{"unavailable otherwise", func(e *engine) {
			e.fail["lib/two.mp3"] = http.StatusServiceUnavailable
			e.code["lib/two.mp3"] = "internal"
		}, 1, true},
	} {
		t.Run(c.name, func(t *testing.T) {
			bk := threeParts(t)
			e := newEngine(bk)
			e.set(c.set)
			b, gate := newJoinedBridge(t, e.serve, bk)
			info, _ := mintJoined(t, b, PlayOptions{})
			rec, aborted := fetchJoined(t, b, httptest.NewRequest("GET", info.URL, nil))
			two := 0
			for _, r := range e.requests() {
				if r.q.Get("src") == "lib/two.mp3" {
					two++
				}
			}
			if aborted != c.broken || two != c.askedTwo {
				t.Fatalf("aborted %v, part two asked %d times; want aborted %v after %d", aborted, two, c.broken, c.askedTwo)
			}
			if !c.broken && !bytes.Equal(rec.Body.Bytes(), audioOf(t, bk, "one", "two", "three")) {
				t.Fatalf("body = %d bytes, want the whole book", rec.Body.Len())
			}
			if gate.acquired != 1 || gate.held != 0 {
				t.Fatalf("slots taken %d, held %d; want the one slot throughout, given back", gate.acquired, gate.held)
			}
		})
	}
}

// Every part is asked for at the book's one shape; a part the engine
// answers at another breaks the book off before a byte of it is sent, as
// a player set up for one rate would meet it mid-stream.
func TestJoinedStreamBreaksOffAtAPartOfAnotherShape(t *testing.T) {
	bk := threeParts(t)
	bk.mp3["lib/three.mp3"] = mp3Part(t, t.TempDir(), "three", 6*time.Second, 22050, 1)
	e := newEngine(bk)
	b, gate := newJoinedBridge(t, e.serve, bk)
	var logged bytes.Buffer
	b.log = slog.New(slog.NewTextHandler(&logged, nil))
	info, _ := mintJoined(t, b, PlayOptions{FilePID: "fi-two"})

	rec, aborted := fetchJoined(t, b, httptest.NewRequest("GET", info.URL, nil))
	if !aborted || !bytes.Equal(rec.Body.Bytes(), audioOf(t, bk, "two")) || !strings.Contains(logged.String(), "fi-three") {
		t.Fatalf("aborted %v with %d bytes, log %q; want part two alone, then a logged break at part three",
			aborted, rec.Body.Len(), logged.String())
	}
	if gate.held != 0 {
		t.Fatalf("%d slots still held", gate.held)
	}
}
