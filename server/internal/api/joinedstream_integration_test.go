package api

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxflow"
	"github.com/colespringer/waxflow/codec/mp3"
	"github.com/colespringer/waxflow/container"
	"github.com/colespringer/waxlabel"

	"github.com/colespringer/waxdeck/fixtures"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/mp3join"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// requestLog records requests across the fake sidecar's goroutines.
type requestLog struct {
	mu  sync.Mutex
	got []loggedRequest
}

type loggedRequest struct {
	method string
	q      url.Values
}

func (l *requestLog) add(method string, q url.Values) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.got = append(l.got, loggedRequest{method, q})
}

func (l *requestLog) all() []loggedRequest {
	l.mu.Lock()
	defer l.mu.Unlock()
	return append([]loggedRequest(nil), l.got...)
}

// encodeMP3 answers the fake sidecar's mp3 request as the engine does: an
// encode of the source at the asked rate and shape, tagged, in the live
// form (an ID3v2 tag and an Info frame ahead of the audio). The cut is
// not applied; the request log is where a test reads it.
func encodeMP3(w http.ResponseWriter, r *http.Request, path string) {
	q := r.URL.Query()
	data, err := os.ReadFile(path)
	if err != nil {
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	}
	atoi := func(k string) int { n, _ := strconv.Atoi(q.Get(k)); return n }
	w.Header().Set("Content-Type", "audio/mpeg")
	if r.Method == http.MethodHead {
		return
	}
	waxflow.New().Transcode(r.Context(), container.BytesSource(data), strings.TrimPrefix(filepath.Ext(path), "."), w,
		waxflow.TranscodeOptions{
			Format: "mp3", MP3Bitrate: atoi("bitrate") * 1000, Rate: atoi("rate"), Channels: atoi("ch"),
			Tags: []container.Tag{{Key: "TITLE", Value: filepath.Base(path)}},
		})
}

// mp3Seconds is how long the engine's own decoder reads an MP3 stream to be.
func mp3Seconds(t *testing.T, b []byte) float64 {
	t.Helper()
	res, err := waxflow.New().Transcode(context.Background(), container.BytesSource(b), "mp3",
		io.Discard, waxflow.TranscodeOptions{Format: "wav"})
	if err != nil {
		t.Fatalf("decoding the stream: %v", err)
	}
	return float64(res.Samples) / float64(res.Format.Rate)
}

// subsonicBook scans the fixture book in parts (4, 5 and 6 s) into the
// harness and answers its pid and its parts' file pids in reading order.
func subsonicBook(t *testing.T, h *harness) (string, []string) {
	t.Helper()
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook").Items
	if len(books) != 1 {
		t.Fatalf("audiobooks = %d, want the fixture book", len(books))
	}
	parts, err := h.svc.BookParts(context.Background(), books[0].Pid)
	if err != nil || len(parts) != 3 {
		t.Fatalf("the fixture book lays out as %d parts (%v), want 3", len(parts), err)
	}
	var files []string
	for _, p := range parts {
		files = append(files, p.FilePID)
	}
	return books[0].Pid, files
}

// partsAsked is what the fake engine was asked to encode to mp3: each
// part's file name, and its cut after an @, in order.
func partsAsked(h *harness) []string {
	var out []string
	for _, r := range h.flowLog.all() {
		if r.q.Get("format") != "mp3" || r.method != http.MethodGet {
			continue
		}
		name := path.Base(r.q.Get("src"))
		if cut := r.q.Get("t"); cut != "" {
			name += "@" + cut
		}
		out = append(out, name)
	}
	return out
}

// A book in parts is one song to a Subsonic client, so its stream is the
// whole book: every part asked of the engine in reading order, arriving as
// one stream a player reads to the book's full length.
func TestSubsonicStreamOfABookInPartsPlaysTheWholeBook(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	h.engineMP3.Store(true)
	secret := newSubsonicSecret(t, h)
	book, parts := subsonicBook(t, h)

	loc := streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+book)
	if q := redirectQuery(t, loc); q.Get("f") != parts[0] || q.Get("join") != "1" || q.Get("fmt") != "mp3" || q.Has("t") {
		t.Fatalf("redirect = %s, want the whole book from part one as one mp3 stream", loc)
	}
	resp, err := http.Get(h.ts.URL + loc)
	if err != nil {
		t.Fatal(err)
	}
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil || resp.StatusCode != 200 || resp.Header.Get("Content-Type") != "audio/mpeg" || resp.ContentLength != -1 {
		t.Fatalf("the joined stream = %d %q, length %d (%v); want a 200 audio/mpeg of no stated length",
			resp.StatusCode, resp.Header.Get("Content-Type"), resp.ContentLength, err)
	}
	want := []string{"01 - Part One.m4b", "02 - Part Two.m4b", "03 - Part Three.m4b"}
	if got := partsAsked(h); !slices.Equal(got, want) {
		t.Fatalf("the engine encoded %v, want %v", got, want)
	}
	if secs := mp3Seconds(t, body); secs < 15 || secs > 15.3 {
		t.Fatalf("the stream plays %.3f s, want the book's 15", secs)
	}
}

// format=raw asks for the file as it is, which a book in parts does not
// have: it still gets the book, joined, from the offset when one is sent.
// A format is a preference the one joinable output overrides, and a cap
// lowers the rate as anywhere.
func TestSubsonicRawOnABookInPartsStillPlaysTheBook(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	book, parts := subsonicBook(t, h)
	stream := "/rest/stream.view?apiKey=" + secret + "&id=" + book

	for _, c := range []struct {
		hint, part, cut, br string
	}{
		{hint: "&format=raw", part: parts[0]},
		{hint: "&format=raw&timeOffset=6.5", part: parts[1], cut: "2"},
		{hint: "&format=opus&maxBitRate=48", part: parts[0], br: "48"},
	} {
		q := redirectQuery(t, streamRedirect(t, h, stream+c.hint))
		if q.Get("join") != "1" || q.Get("fmt") != "mp3" || q.Get("f") != c.part || q.Get("t") != c.cut ||
			(c.br != "" && q.Get("br") != c.br) {
			t.Errorf("%s: redirect carries %v, want part %s joined as mp3, cut %q, br %q", c.hint, q, c.part, c.cut, c.br)
		}
	}
}

// One transcode slot covers the whole book: with the server allowed one,
// a joined stream is refused while someone else holds it, and plays every
// part once it is free.
func TestSubsonicBookInPartsTakesOneTranscodeSlot(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	h.engineMP3.Store(true)
	secret := newSubsonicSecret(t, h)
	book, _ := subsonicBook(t, h)
	wantStatus(t, h.putJSON(t, "/api/v1/admin/transcoding", map[string]any{
		"maxConcurrent": 1, "maxConcurrentPerUser": 0, "defaultMaxBitrateKbps": 0,
	}), 200, "one transcode server-wide")
	release, err := h.svc.TranscodeGate().Acquire(context.Background(), "someone-else", flow.TranscodeStream)
	if err != nil {
		t.Fatal(err)
	}
	loc := streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+book)
	if code := fetchStatus(t, h, loc); code != http.StatusTooManyRequests {
		t.Fatalf("the book while the server is full = %d, want 429", code)
	}
	if got := partsAsked(h); len(got) != 0 {
		t.Fatalf("a refused stream asked the engine for %v", got)
	}
	release()
	if code := fetchStatus(t, h, loc); code != 200 || len(partsAsked(h)) != 3 {
		t.Fatalf("the book once the slot is free = %d over %v, want 200 over its three parts", code, partsAsked(h))
	}
}

// A book in one file is one file, and streams as it always has.
func TestSubsonicSingleFileBookStreamsAsItself(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	if _, err := fixtures.GenerateChapteredBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook").Items
	if len(books) != 1 {
		t.Fatalf("audiobooks = %d, want the chaptered fixture", len(books))
	}
	loc := streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+books[0].Pid)
	if q := redirectQuery(t, loc); q.Has("join") || q.Has("fmt") || q.Has("f") {
		t.Fatalf("redirect = %s, want the file as it is", loc)
	}
	if code := fetchStatus(t, h, loc); code != 200 || h.flowReq.format != "auto" {
		t.Fatalf("the single-file book = %d as %q, want 200 as the original", code, h.flowReq.format)
	}
}

// A joined stream's layout comes off the catalog in one pass, each part
// with its own format facts, which are what the stream's envelope is
// chosen from. Nothing else lays out.
func TestStreamPartsLayOutABookInParts(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()
	book, files := subsonicBook(t, h)
	laid, err := h.svc.BookParts(ctx, book)
	if err != nil {
		t.Fatal(err)
	}
	parts, err := h.svc.StreamParts(ctx, book)
	if err != nil || len(parts) != 3 {
		t.Fatalf("parts = %d (%v), want the book's 3", len(parts), err)
	}
	seen := map[string]bool{}
	for i, p := range parts {
		if p.FilePID != files[i] || p.Src.DurationMS != laid[i].DurationMS {
			t.Fatalf("part %d = %s for %d ms, want %s for %d ms", i, p.FilePID, p.Src.DurationMS, files[i], laid[i].DurationMS)
		}
		if p.Src.Path == "" || seen[p.Src.Path] || p.Src.Size <= 0 || p.Src.MTimeNS == 0 || !p.Src.SpokenWord {
			t.Fatalf("part %d's source = %+v, want its own file, pinned, spoken word", i, p.Src)
		}
		seen[p.Src.Path] = true
		if p.Rate != 44100 || p.Channels != 2 {
			t.Fatalf("part %d is %d Hz x %d, want the fixture's 44100 x 2", i, p.Rate, p.Channels)
		}
	}
	track := h.items(t, "?mediaType=music").Items[0]
	if got, err := h.svc.StreamParts(ctx, track.Pid); err != nil || got != nil {
		t.Fatalf("a track laid out as %+v (%v), want nothing", got, err)
	}
}

// A timeOffset lands on the book's own timeline: floored there to the
// whole second, where repeats share an encode, and cut inside its part to
// the millisecond. A part start is any millisecond on the book, so a cut
// floored inside the part would start up to a second early.
func TestSubsonicBookOffsetLandsOnTheBooksSecond(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	dir := filepath.Join(h.library, "Ada Author", "The Uneven Book")
	for i, d := range []time.Duration{4370 * time.Millisecond, 5 * time.Second, 6 * time.Second} {
		if _, err := fixtures.GenerateM4B(dir, fixtures.Spec{
			Name: fmt.Sprintf("%02d - Part", i+1), Duration: d,
			Tags: map[string]string{
				"TITLE": fmt.Sprintf("Part %d", i+1), "ALBUM": "The Uneven Book", "ARTIST": "Ada Author",
				"ALBUMARTIST": "Ada Author", "TRACKNUMBER": fmt.Sprint(i + 1),
			},
		}); err != nil {
			t.Fatal(err)
		}
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook").Items
	if len(books) != 1 {
		t.Fatalf("audiobooks = %d, want the uneven book", len(books))
	}
	parts, err := h.svc.BookParts(context.Background(), books[0].Pid)
	if err != nil || len(parts) != 3 || parts[1].StartMS%1000 == 0 {
		t.Fatalf("parts %+v (%v), want three with part two starting off a whole second", parts, err)
	}
	q := redirectQuery(t, streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+books[0].Pid+"&timeOffset=7.5"))
	want := strconv.FormatFloat(float64(7000-parts[1].StartMS)/1000, 'f', -1, 64)
	if q.Get("f") != parts[1].FilePID || q.Get("t") != want {
		t.Fatalf("redirect carries part %s cut at %q, want part two cut at %s (book second 7)", q.Get("f"), q.Get("t"), want)
	}
}

// A book's parts can be files of different formats (an m4b part and an MP3
// one), and each part is described by its own file wherever it resolves:
// play-info inside a part names that part's media type, and the engine's
// view of it, one part at a time or the whole book at once, its codec.
func TestABookPartIsDescribedByItsOwnFile(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()
	book := directBook(t, h, "The Mixed Book", func(dir string) error {
		at := filepath.Join(dir, "Ada Author", "The Mixed Book")
		tags := func(n int) map[string]string {
			return map[string]string{"TITLE": fmt.Sprintf("Part %d", n), "ALBUM": "The Mixed Book",
				"ARTIST": "Ada Author", "ALBUMARTIST": "Ada Author", "TRACKNUMBER": fmt.Sprint(n)}
		}
		if _, err := fixtures.GenerateM4B(at, fixtures.Spec{Name: "01 - Part", Duration: 4 * time.Second, Tags: tags(1)}); err != nil {
			return err
		}
		_, err := fixtures.Generate(at, fixtures.Spec{Name: "02 - Part", Codec: fixtures.CodecMP3, Duration: 4 * time.Second, Tags: tags(2)})
		return err
	})
	parts, err := h.svc.BookParts(ctx, book)
	if err != nil || len(parts) != 2 {
		t.Fatalf("the mixed book lays out as %d parts (%v), want 2", len(parts), err)
	}
	for i, want := range []string{"audio/mp4", "audio/mpeg"} {
		pi := decode[PlayInfo](t, get(t, h.ts, fmt.Sprintf("/api/v1/items/%s/play-info?positionMs=%d", book, parts[i].StartMS+1000), h.token))
		if pi.MimeType != want {
			t.Errorf("play-info inside part %d = %s, want %s", i+1, pi.MimeType, want)
		}
		src, err := h.svc.StreamSource(ctx, book, parts[i].FilePID)
		if err != nil || flow.ContainerMime(src.Container) != want {
			t.Errorf("part %d streams as %s/%s (%v), want %s", i+1, src.Codec, src.Container, err, want)
		}
	}
	uc, err := h.svc.UserCtxByID(ctx, adminUserID(t, h))
	if err != nil {
		t.Fatal(err)
	}
	pieces, err := h.svc.BookPieces(ctx, uc, book)
	if err != nil || len(pieces) != 2 {
		t.Fatalf("pieces = %d (%v), want 2", len(pieces), err)
	}
	for i, p := range pieces {
		if got := flow.ContainerMime(p.Src.Container); got != p.File.MimeType {
			t.Errorf("piece %d: the engine sees %s/%s (%s) of a %s file", i+1, p.Src.Codec, p.Src.Container, got, p.File.MimeType)
		}
	}
}

// longMarksBook catalogs a book in two MP3 parts whose chapter marks run
// past their audio, as a part's CHAP frames can: part one is 4 s of audio
// with marks to 5 s, part two 5 s of audio with marks to 6 s.
func longMarksBook(t *testing.T, h *harness) string {
	t.Helper()
	return directBook(t, h, "The Long Marks", func(dir string) error {
		at := filepath.Join(dir, "Ada Author", "The Long Marks")
		for i, p := range []struct {
			d     time.Duration
			marks []waxlabel.Chapter
		}{
			{4 * time.Second, []waxlabel.Chapter{{End: 2 * time.Second, Title: "One"}, {Start: 2 * time.Second, End: 5 * time.Second, Title: "Two"}}},
			{5 * time.Second, []waxlabel.Chapter{{End: 3 * time.Second, Title: "Three"}, {Start: 3 * time.Second, End: 6 * time.Second, Title: "Four"}}},
		} {
			paths, err := fixtures.Generate(at, fixtures.Spec{
				Name: fmt.Sprintf("%02d - Part", i+1), Codec: fixtures.CodecMP3, Duration: p.d,
				Tags: map[string]string{"TITLE": fmt.Sprintf("Part %d", i+1), "ALBUM": "The Long Marks",
					"ARTIST": "Ada Author", "ALBUMARTIST": "Ada Author", "TRACKNUMBER": fmt.Sprint(i + 1)},
			})
			if err != nil {
				return err
			}
			doc, err := waxlabel.ParseFile(context.Background(), paths[0])
			if err != nil {
				return err
			}
			plan, err := doc.Edit().SetChapters(p.marks...).Prepare()
			if err != nil {
				return err
			}
			if _, _, err := plan.Execute(context.Background(), waxlabel.SaveBack()); err != nil {
				return err
			}
		}
		return nil
	})
}

// A book's chapter marks sit on the timeline its parts play on, the one
// play-info and every stored position use. Where a part's marks run past
// its audio, each is held to the part's audio and the parts after it are
// not pushed back: every mark is a position there is audio at, and the
// book ends where its last part does. The resume answer names the chapter
// on that timeline, a bookmark past the audio's end is refused, and the
// chapter list written back as it was read reads back the same.
func TestBookChaptersSitOnTheTimelineItsPartsPlayOn(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	book := longMarksBook(t, h)
	det := decode[BookDetail](t, get(t, h.ts, "/api/v1/books/"+book, h.token))
	if len(det.Parts) != 2 || det.Parts[1].StartMs != det.Parts[0].DurationMs {
		t.Fatalf("parts %+v, want two laid end to end", det.Parts)
	}
	end := det.Parts[1].StartMs + det.Parts[1].DurationMs
	if det.DurationMs != end {
		t.Errorf("the book lasts %d ms, want the end of its last part, %d", det.DurationMs, end)
	}
	one := det.Parts[0].DurationMs
	want := [][2]int64{{0, 2000}, {2000, one}, {one, one + 3000}, {one + 3000, end}}
	marks := func(d BookDetail) [][2]int64 {
		var out [][2]int64
		for _, ch := range d.Chapters {
			e := int64(-1)
			if ch.EndMs != nil {
				e = *ch.EndMs
			}
			out = append(out, [2]int64{ch.StartMs, e})
		}
		return out
	}
	if got := marks(det); fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("chapters %v, want %v on the parts' own timeline", got, want)
	}

	wantStatus(t, h.putJSON(t, "/api/v1/items/"+book+"/play-state", map[string]any{"positionMs": one + 500}), 204, "a position in part two")
	resume := decode[BookResume](t, get(t, h.ts, "/api/v1/books/"+book+"/resume", h.token))
	if resume.Chapter == nil || resume.Chapter.Title == nil || *resume.Chapter.Title != "Three" {
		t.Errorf("resume at %d names chapter %+v, want Three, part two's first", one+500, resume.Chapter)
	}

	wantStatus(t, h.postJSON(t, "/api/v1/books/"+book+"/bookmarks", map[string]any{"positionMs": end + 500}), 400, "a mark past the audio's end")
	wantStatus(t, h.postJSON(t, "/api/v1/books/"+book+"/bookmarks", map[string]any{"positionMs": end}), 201, "a mark at the audio's end")

	var edit []map[string]any
	for _, ch := range det.Chapters {
		m := map[string]any{"index": ch.Index, "startMs": ch.StartMs, "title": *ch.Title}
		if ch.EndMs != nil {
			m["endMs"] = *ch.EndMs
		}
		edit = append(edit, m)
	}
	wantStatus(t, h.putJSON(t, "/api/v1/books/"+book+"/chapters", map[string]any{"chapters": edit}), 200, "the chapters written back")
	again := decode[BookDetail](t, get(t, h.ts, "/api/v1/books/"+book, h.token))
	if got := marks(again); fmt.Sprint(got) != fmt.Sprint(want) || again.DurationMs != end {
		t.Fatalf("written back as read, the chapters read %v over %d ms, want %v over %d", got, again.DurationMs, want, end)
	}
}

// The editor reads a book's chapters on the timeline it writes them on:
// the metadata read lists the marks the book detail does, and saving them
// back with a title changed, as the editor does, moves none of them, at
// the first save or any after it.
func TestTheEditorReadsChaptersOnTheTimelineItWritesThem(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	book := longMarksBook(t, h)
	marks := func(chs []ChapterMark) [][2]int64 {
		var out [][2]int64
		for _, ch := range chs {
			e := int64(-1)
			if ch.EndMs != nil {
				e = *ch.EndMs
			}
			out = append(out, [2]int64{ch.StartMs, e})
		}
		return out
	}
	det := decode[BookDetail](t, get(t, h.ts, "/api/v1/books/"+book, h.token))
	want := marks(det.Chapters)
	for save := range 3 {
		meta := decode[ItemMetadata](t, get(t, h.ts, "/api/v1/items/"+book+"/metadata", h.token))
		if meta.Chapters == nil {
			t.Fatalf("after %d saves the editor reads no chapters", save)
		}
		if got := marks(*meta.Chapters); fmt.Sprint(got) != fmt.Sprint(want) {
			t.Fatalf("after %d saves the editor reads %v, want the book's %v", save, got, want)
		}
		var edit []map[string]any
		for _, ch := range *meta.Chapters {
			m := map[string]any{"index": ch.Index, "startMs": ch.StartMs, "title": *ch.Title}
			if ch.Index == 0 {
				m["title"] = fmt.Sprintf("Opening %d", save)
			}
			if ch.EndMs != nil {
				m["endMs"] = *ch.EndMs
			}
			edit = append(edit, m)
		}
		// Each save locks the list, so the next one forces past the lock.
		wantStatus(t, h.putJSON(t, "/api/v1/books/"+book+"/chapters", map[string]any{"chapters": edit, "force": true}), 200, "the editor's save")
		again := decode[BookDetail](t, get(t, h.ts, "/api/v1/books/"+book, h.token))
		if got := marks(again.Chapters); fmt.Sprint(got) != fmt.Sprint(want) {
			t.Fatalf("save %d moved the chapters to %v, want %v", save+1, got, want)
		}
	}
}

// directBook catalogs a book in parts in its own audiobook library on a
// server, made of what make writes into the library's directory, and
// answers the book's pid.
func directBook(t *testing.T, h *harness, title string, make func(dir string) error) string {
	t.Helper()
	dir := t.TempDir()
	if err := make(dir); err != nil {
		t.Fatal(err)
	}
	decodeStatus[Library](t, h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": title, "path": dir, "media": "audiobook",
	}), 201, "an audiobook library")
	for deadline := time.Now().Add(30 * time.Second); time.Now().Before(deadline); time.Sleep(50 * time.Millisecond) {
		for _, it := range h.items(t, "?mediaType=audiobook&limit=500").Items {
			if it.Title == title {
				waitForScans(t, h)
				return it.Pid
			}
		}
	}
	t.Fatalf("no book titled %q", title)
	return ""
}

// Without the engine nothing is encoded, but a book whose parts are all
// MP3 at one rate needs no encode to be one stream: each part's frames
// join as they are, its tags and length frame left out, so the client
// plays the whole book. It answers as the engine's joined stream does: no
// length, no range but the whole.
func TestSubsonicMP3BookInPartsJoinsWithoutTheEngine(t *testing.T) {
	t.Parallel()
	h := newHarnessDirect(t)
	secret := newSubsonicSecret(t, h)
	book := directBook(t, h, "The Loose Chapters", func(dir string) error {
		_, err := fixtures.GenerateLooseMP3Book(dir) // parts of 3 and 4 s
		return err
	})

	loc := streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+book)
	if !strings.HasPrefix(loc, "/media/download?") || redirectQuery(t, loc).Get(service.JoinKey) != "1" {
		t.Fatalf("redirect = %s, want the book's parts joined as they are", loc)
	}
	resp, err := http.Get(h.ts.URL + loc)
	if err != nil {
		t.Fatal(err)
	}
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil || resp.StatusCode != 200 || resp.Header.Get("Content-Type") != "audio/mpeg" ||
		resp.ContentLength != -1 || resp.Header.Get("Accept-Ranges") != "none" {
		t.Fatalf("the joined book = %d %q, length %d, ranges %q (%v); want 200 audio/mpeg of no length, no ranges",
			resp.StatusCode, resp.Header.Get("Content-Type"), resp.ContentLength, resp.Header.Get("Accept-Ranges"), err)
	}
	bareFrames(t, body)
	if secs := mp3Seconds(t, body); secs < 7 || secs > 7.2 {
		t.Fatalf("the joined book plays %.3f s, want its 7", secs)
	}

	req, _ := http.NewRequest("GET", h.ts.URL+loc, nil)
	req.Header.Set("Range", "bytes=100-")
	if resp, err := http.DefaultClient.Do(req); err != nil || resp.StatusCode != http.StatusRequestedRangeNotSatisfiable {
		t.Fatalf("a range past the start = %v (%v), want 416", resp.StatusCode, err)
	}
	if resp, err := http.Head(h.ts.URL + loc); err != nil || resp.StatusCode != 200 || resp.Header.Get("Content-Type") != "audio/mpeg" {
		t.Fatalf("HEAD = %v (%v), want 200 audio/mpeg", resp.StatusCode, err)
	}
}

// Parts in another format, or MP3 at two rates, need an encode to join,
// which a server without the engine does not run: such a book streams its
// first part as its file.
func TestSubsonicOtherBooksInPartsStreamPartOneWithoutTheEngine(t *testing.T) {
	t.Parallel()
	for name, make := range map[string]func(dir string) error{
		"m4b parts": func(dir string) error {
			_, err := fixtures.GenerateBook(dir)
			return err
		},
		"mp3 parts at two rates": func(dir string) error {
			for i, rate := range []int{44100, 22050} {
				if _, err := fixtures.Generate(filepath.Join(dir, "Ada Author", "The Fixture Book"), fixtures.Spec{
					Name: fmt.Sprintf("%02d - Part", i+1), Codec: fixtures.CodecMP3, Duration: 2 * time.Second, SampleRate: rate,
					Tags: map[string]string{"TITLE": fmt.Sprintf("Part %d", i+1), "ALBUM": "The Fixture Book",
						"ARTIST": "Ada Author", "ALBUMARTIST": "Ada Author", "TRACKNUMBER": fmt.Sprint(i + 1)},
				}); err != nil {
					return err
				}
			}
			return nil
		},
	} {
		t.Run(name, func(t *testing.T) {
			h := newHarnessDirect(t)
			secret := newSubsonicSecret(t, h)
			book := directBook(t, h, "The Fixture Book", make)
			loc := streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+book)
			if q := redirectQuery(t, loc); q.Has(service.JoinKey) || q.Get("id") == "" {
				t.Fatalf("redirect = %s, want the first part's file", loc)
			}
			if code := fetchStatus(t, h, loc); code != 200 {
				t.Fatalf("the first part = %d", code)
			}
		})
	}
}

// bareFrames asserts b is MP3 frames end to end, none of them a frame
// stating a stream's length: a part's tag or Info frame would break the
// walk or show as one.
func bareFrames(t *testing.T, b []byte) {
	t.Helper()
	for off := 0; off < len(b); {
		h, err := mp3.ParseHeader(b[off:])
		if err != nil || h.Size() == 0 || off+h.Size() > len(b) {
			t.Fatalf("byte %d of %d is not the start of a whole frame (%v)", off, len(b), err)
		}
		at := off + mp3.HeaderLen + h.SideInfoLen()
		if magic := string(b[at : at+4]); magic == "Info" || magic == "Xing" {
			t.Fatalf("the frame at byte %d is a part's %s frame", off, magic)
		}
		off += h.Size()
	}
}

// threePartMP3Book writes "Ida Writer/The Three Parts" into dir, MP3 parts
// of 3, 4 and 5 s, and answers their paths in reading order.
func threePartMP3Book(dir string) ([]string, error) {
	var out []string
	for i := range 3 {
		paths, err := fixtures.Generate(filepath.Join(dir, "Ida Writer", "The Three Parts"), fixtures.Spec{
			Name: fmt.Sprintf("%02d - Part", i+1), Codec: fixtures.CodecMP3, Duration: time.Duration(3+i) * time.Second,
			Tags: map[string]string{
				"TITLE": fmt.Sprintf("Part %d", i+1), "ARTIST": "Ida Writer", "ALBUM": "The Three Parts",
				"ALBUMARTIST": "Ida Writer", "TRACKNUMBER": fmt.Sprint(i + 1),
			},
		})
		if err != nil {
			return nil, err
		}
		out = append(out, paths...)
	}
	return out, nil
}

// joinedFetch fetches a joined stream and answers its body and whether
// the transfer broke off rather than ending.
func joinedFetch(t *testing.T, h *harness, loc string) ([]byte, bool) {
	t.Helper()
	resp, err := http.Get(h.ts.URL + loc)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("the joined stream = %d", resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	return body, err != nil
}

// mp3Copy is a file's frames as the join passes them.
func mp3Copy(t *testing.T, path string) []byte {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	var out bytes.Buffer
	if _, readErr, writeErr := mp3join.Copy(&out, f, mp3join.Shape{}, func() {}); readErr != nil || writeErr != nil {
		t.Fatal(readErr, writeErr)
	}
	return out.Bytes()
}

// A part shorter on disk than its length (a truncated copy, a partial
// write, a file rewritten in place) reads to a clean end, so the join
// holds each part to its length as the engine's join does: one that ends
// well short, or holds no frame at all, breaks the transfer off rather
// than ending it as the book's end.
func TestSubsonicMP3BookInPartsBreaksOffAtAShortPart(t *testing.T) {
	t.Parallel()
	for name, c := range map[string]struct {
		part int
		keep func(size int64) int64
	}{
		"a middle part cut in half":      {1, func(size int64) int64 { return size / 2 }},
		"the last part cut in half":      {2, func(size int64) int64 { return size / 2 }},
		"a middle part holding no frame": {1, func(int64) int64 { return 100 }},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			h := newHarnessDirect(t)
			secret := newSubsonicSecret(t, h)
			var parts []string
			book := directBook(t, h, "The Three Parts", func(dir string) (err error) {
				parts, err = threePartMP3Book(dir)
				return err
			})
			loc := streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+book)
			if _, broken := joinedFetch(t, h, loc); broken {
				t.Fatal("the whole book broke off")
			}
			st, err := os.Stat(parts[c.part])
			if err != nil {
				t.Fatal(err)
			}
			if err := os.Truncate(parts[c.part], c.keep(st.Size())); err != nil {
				t.Fatal(err)
			}
			if _, broken := joinedFetch(t, h, loc); !broken {
				t.Fatal("the book ended well-formed past a part short on disk, want the transfer broken off")
			}
		})
	}
}

// cancellingRecorder is a listener still reading while the server cancels
// the request under it, as a shutdown does, once its first audio arrives.
type cancellingRecorder struct {
	*httptest.ResponseRecorder
	cancel context.CancelFunc
}

func (w *cancellingRecorder) Write(p []byte) (int, error) {
	w.cancel()
	return w.ResponseRecorder.Write(p)
}

// A request the server cancels mid-book (a shutdown cancels every one)
// breaks the transfer off as a lost part does: no length rides it, so a
// clean end would read as the book's end.
func TestSubsonicMP3BookInPartsBreaksOffWhenTheServerCancels(t *testing.T) {
	t.Parallel()
	h := newHarnessDirect(t)
	secret := newSubsonicSecret(t, h)
	book := directBook(t, h, "The Three Parts", func(dir string) error {
		_, err := threePartMP3Book(dir)
		return err
	})
	loc := streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+book)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	w := &cancellingRecorder{ResponseRecorder: httptest.NewRecorder(), cancel: cancel}
	aborted := func() (aborted bool) {
		defer func() {
			if v := recover(); v != nil {
				if v != http.ErrAbortHandler {
					panic(v)
				}
				aborted = true
			}
		}()
		h.srv.ServeDownload(w, httptest.NewRequest("GET", loc, nil).WithContext(ctx))
		return false
	}()
	if !aborted {
		t.Fatalf("a request cancelled mid-book ended well-formed after %d bytes, want it broken off", w.Body.Len())
	}
}

// A part whose frames are not the book's shape (rewritten since the scan
// at another rate) breaks the transfer off before a byte of it is sent.
func TestSubsonicMP3BookInPartsBreaksOffAtAPartOfAnotherShape(t *testing.T) {
	t.Parallel()
	h := newHarnessDirect(t)
	secret := newSubsonicSecret(t, h)
	var parts []string
	book := directBook(t, h, "The Three Parts", func(dir string) (err error) {
		parts, err = threePartMP3Book(dir)
		return err
	})
	loc := streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+book)
	other, err := fixtures.Generate(t.TempDir(), fixtures.Spec{Name: "other", Codec: fixtures.CodecMP3, Duration: 4 * time.Second, SampleRate: 22050, Channels: 1})
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(other[0])
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(parts[1], raw, 0o644); err != nil {
		t.Fatal(err)
	}
	body, broken := joinedFetch(t, h, loc)
	if one := mp3Copy(t, parts[0]); !broken || !bytes.Equal(body, one) {
		t.Fatalf("broken %v after %d bytes, want part one's %d and then the break", broken, len(body), len(one))
	}
}

// joinURL is the engine-less join's URL for pid under token.
func joinURL(pid, token string) string {
	return "/media/download?pid=" + url.QueryEscape(pid) + "&mt=" + url.QueryEscape(token) + "&" + service.JoinShape
}

// The engine-less join's token opens its own book's join and nothing
// else: the check each fetch runs reads the token's pid while the route
// streams the URL's, so a token that held on another pid would open every
// joinable book on the server. Each refusal is a 401, as for any token
// that does not fit its URL.
func TestSubsonicMP3BookJoinTokenOpensItsBookAlone(t *testing.T) {
	t.Parallel()
	h := newHarnessDirect(t)
	secret := newSubsonicSecret(t, h)
	book := directBook(t, h, "The Loose Chapters", func(dir string) error {
		_, err := fixtures.GenerateLooseMP3Book(dir)
		return err
	})
	other := directBook(t, h, "The Misfiled Lectures", func(dir string) error {
		_, err := fixtures.GenerateMisfiledBook(dir)
		return err
	})
	loc := streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+book)
	token := redirectQuery(t, loc).Get("mt")
	user := adminUserID(t, h)
	mint := func(purpose, shape string) string {
		tok, _ := h.media.MintFor(auth.MediaClaims{User: user, Purpose: purpose, PID: book, Shape: shape}, 0)
		return tok
	}
	if code := fetchStatus(t, h, loc); code != 200 {
		t.Fatalf("the join as minted = %d", code)
	}
	if code := fetchStatus(t, h, joinURL(other, mint(auth.PurposeStream, service.JoinShape))); code != http.StatusUnauthorized {
		t.Fatalf("a join token for one book on another's join = %d, want 401", code)
	}
	for name, u := range map[string]string{
		"the join token on another book":      joinURL(other, token),
		"the join token without the join":     "/media/download?pid=" + url.QueryEscape(book) + "&mt=" + url.QueryEscape(token),
		"a plain stream token on the join":    joinURL(book, mint(auth.PurposeStream, "")),
		"a download token shaped as the join": joinURL(book, mint(auth.PurposeDownload, service.JoinShape)),
	} {
		if code := fetchStatus(t, h, u); code != http.StatusUnauthorized {
			t.Errorf("%s = %d, want 401", name, code)
		}
	}
}

// While the engine runs, an engine-less join token opens nothing: the
// engine-less route is closed, and the engine's own joined stream binds a
// shape of its own, so the two tokens never fit each other's URLs.
func TestEngineLessJoinTokensOpenNothingWhileTheEngineRuns(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	h.engineMP3.Store(true)
	book := directBook(t, h, "The Loose Chapters", func(dir string) error {
		_, err := fixtures.GenerateLooseMP3Book(dir)
		return err
	})
	token, _ := h.media.MintFor(auth.MediaClaims{
		User: adminUserID(t, h), Purpose: auth.PurposeStream, PID: book, Shape: service.JoinShape,
	}, 0)
	q := "pid=" + url.QueryEscape(book) + "&mt=" + url.QueryEscape(token)
	for name, u := range map[string]string{
		"the engine-less join":                     joinURL(book, token),
		"the engine's joined stream":               "/media/stream?" + q + "&join=1",
		"the engine's stream with the join's flag": "/media/stream?" + q + "&" + service.JoinShape,
	} {
		if code := fetchStatus(t, h, u); code != http.StatusUnauthorized {
			t.Errorf("%s = %d, want 401", name, code)
		}
	}
	if got := partsAsked(h); len(got) != 0 {
		t.Fatalf("the engine was asked for %v", got)
	}
}
