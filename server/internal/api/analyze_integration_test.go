package api

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// analyzeAndWait runs the analyze pass through the API and polls the job
// to done. The 202 is the point of the endpoint: StartAnalyze names its
// job as soon as the row exists, where the synchronous facade would
// block here for the length of the decode.
func analyzeAndWait(t *testing.T, h *harness) {
	t.Helper()
	req, _ := http.NewRequest("POST", h.ts.URL+"/api/v1/library/analyze", nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 202 {
		t.Fatalf("analyze status = %d, want 202", resp.StatusCode)
	}
	job := decode[Job](t, resp)
	if !strings.HasPrefix(job.Pid, "jb-") {
		t.Fatalf("job pid = %q, want jb- prefix", job.Pid)
	}
	if job.Kind != "analyze" {
		t.Fatalf("job kind = %q, want analyze", job.Kind)
	}
	deadline := time.Now().Add(60 * time.Second)
	for {
		resp := get(t, h.ts, "/api/v1/jobs/"+job.Pid, h.token)
		j := decode[Job](t, resp)
		switch j.State {
		case "done":
			return
		case "failed", "crashed", "canceled":
			t.Fatalf("analyze job ended %s: %v", j.State, deref(j.Error))
		}
		if time.Now().After(deadline) {
			t.Fatal("analyze job did not finish in time")
		}
		time.Sleep(50 * time.Millisecond)
	}
}

func waveform(t *testing.T, h *harness, pid string) Waveform {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/items/"+pid+"/waveform", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("waveform status = %d, want 200", resp.StatusCode)
	}
	return decode[Waveform](t, resp)
}

// waveformPart reads one part of a multi-file book's waveform.
func waveformPart(t *testing.T, h *harness, pid string, part int) Waveform {
	t.Helper()
	resp := get(t, h.ts, fmt.Sprintf("/api/v1/items/%s/waveform?partIndex=%d", pid, part), h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("waveform part %d status = %d, want 200", part, resp.StatusCode)
	}
	return decode[Waveform](t, resp)
}

func TestAnalyzeThenWaveform(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	// A cue-carved album beside the whole-file demo tracks: one backing
	// file, two virtual tracks over it, which is the case that must not
	// answer the backing file's envelope.
	ripDir := filepath.Join(h.library, "Wave Artist", "Wave Album")
	if _, err := fixtures.Generate(ripDir, fixtures.Spec{
		Name: "Wave Album", Codec: fixtures.CodecFLAC, Duration: 6 * time.Second,
		Tags: map[string]string{
			"TITLE": "Wave Album", "ALBUM": "Wave Album",
			"ARTIST": "Wave Artist", "ALBUMARTIST": "Wave Artist",
		},
	}); err != nil {
		t.Fatal(err)
	}
	sheet := "PERFORMER \"Wave Artist\"\nTITLE \"Wave Album\"\nFILE \"Wave Album.flac\" WAVE\n" +
		"  TRACK 01 AUDIO\n    TITLE \"Wave One\"\n    INDEX 01 00:00:00\n" +
		"  TRACK 02 AUDIO\n    TITLE \"Wave Two\"\n    INDEX 01 00:03:00\n"
	if err := os.WriteFile(filepath.Join(ripDir, "Wave Album.cue"), []byte(sheet), 0o644); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	byTitle := map[string]ItemSummary{}
	for _, it := range h.items(t, "?mediaType=music").Items {
		byTitle[it.Title] = it
	}
	track, ok := byTitle["Alpha Song"]
	if !ok {
		t.Fatalf("demo track missing from the scan: %v", byTitle)
	}
	virtual, ok := byTitle["Wave One"]
	if !ok {
		t.Fatalf("virtual cue track missing from the scan: %v", byTitle)
	}

	// A scan does not decode audio, so nothing has peaks until the
	// analyze pass runs. The whole-file track is the one that changes.
	if got := waveform(t, h, track.Pid); got.State != "pending" {
		t.Fatalf("before analyze, waveform state = %q, want pending", got.State)
	}
	// The virtual track is unavailable from the start and stays that
	// way: peaks belong to its backing file, and drawing that file's
	// envelope under one carved track would be a convincing wrong
	// answer.
	if got := waveform(t, h, virtual.Pid); got.State != "unavailable" {
		t.Fatalf("virtual track waveform state = %q, want unavailable", got.State)
	}

	analyzeAndWait(t, h)

	wf := waveform(t, h, track.Pid)
	if wf.State != "ready" {
		t.Fatalf("after analyze, waveform state = %q, want ready", wf.State)
	}
	if wf.Resolution == nil || *wf.Resolution <= 0 {
		t.Fatalf("waveform resolution = %v, want a positive bucket count", wf.Resolution)
	}
	if wf.Peaks == nil {
		t.Fatal("a ready waveform must carry peaks")
	}
	if len(*wf.Peaks) != *wf.Resolution {
		t.Fatalf("waveform carries %d peaks for resolution %d", len(*wf.Peaks), *wf.Resolution)
	}
	if wf.EssenceHash == nil || *wf.EssenceHash == "" {
		t.Fatal("a ready waveform must name the essence it was measured from")
	}
	// Synthesized fixtures are tones, not silence: a waveform of nothing
	// but zeroes would mean the narrowing dropped the signal.
	loud := false
	for _, v := range *wf.Peaks {
		if v < 0 || v > 255 {
			t.Fatalf("peak %d is outside 0..255", v)
		}
		if v > 0 {
			loud = true
		}
	}
	if !loud {
		t.Fatal("every peak is zero; the stored waveform did not survive narrowing")
	}

	// The virtual track is still unavailable now that its backing file
	// has been analyzed, which is the half of that decision the earlier
	// assertion could not see.
	if got := waveform(t, h, virtual.Pid); got.State != "unavailable" {
		t.Fatalf("analyzed virtual track waveform state = %q, want unavailable", got.State)
	}
}

func TestWaveformCaching(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	h.rescanAndWait(t)
	items := h.items(t, "?mediaType=music").Items
	if len(items) == 0 {
		t.Fatal("no items scanned")
	}
	pid := items[0].Pid

	// Pending is never cached: the next analyze pass contradicts it.
	resp := get(t, h.ts, "/api/v1/items/"+pid+"/waveform", h.token)
	resp.Body.Close()
	if got := resp.Header.Get("Cache-Control"); got != "no-store" {
		t.Fatalf("pending Cache-Control = %q, want no-store", got)
	}
	if got := resp.Header.Get("ETag"); got != "" {
		t.Fatalf("pending answer carries an ETag %q; it has nothing to validate", got)
	}

	analyzeAndWait(t, h)

	resp = get(t, h.ts, "/api/v1/items/"+pid+"/waveform", h.token)
	resp.Body.Close()
	etag := resp.Header.Get("ETag")
	if etag == "" {
		t.Fatal("a ready waveform must carry an ETag")
	}
	if got := resp.Header.Get("Cache-Control"); got != "private, max-age=86400, stale-while-revalidate=604800" {
		t.Fatalf("ready Cache-Control = %q", got)
	}
	if got := resp.Header.Get("Vary"); got != "Cookie, Authorization" {
		t.Fatalf("ready Vary = %q", got)
	}

	// A revalidation answers 304 and repeats the freshness, so the
	// cached copy is refreshed rather than left as stale as it was.
	req, _ := http.NewRequest("GET", h.ts.URL+"/api/v1/items/"+pid+"/waveform", nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	req.Header.Set("If-None-Match", etag)
	again, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	again.Body.Close()
	if again.StatusCode != http.StatusNotModified {
		t.Fatalf("revalidation status = %d, want 304", again.StatusCode)
	}
	if got := again.Header.Get("ETag"); got != etag {
		t.Fatalf("304 ETag = %q, want %q", got, etag)
	}
	if got := again.Header.Get("Cache-Control"); got == "" {
		t.Fatal("304 dropped the freshness the body carried")
	}
}

func TestWaveformEpisodeIsPermanentlyUnavailable(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	page := decode[EpisodePage](t, resp)
	if len(page.Items) == 0 {
		t.Fatal("no episodes cataloged")
	}
	ep := page.Items[0]

	// Unfetched: no local audio at all.
	if got := waveform(t, h, ep.Pid); got.State != "unavailable" {
		t.Fatalf("unfetched episode waveform = %q, want unavailable", got.State)
	}

	// Fetched, and analyzed as far as it ever will be. Podcast-mode
	// libraries are excluded from the analyze pass upstream by design,
	// so the answer must stay unavailable rather than turning into a
	// pending a client would poll forever.
	resp = h.postJSON(t, "/api/v1/episodes/"+ep.Pid+"/fetch", nil)
	if resp.StatusCode != 202 {
		t.Fatalf("fetch status = %d, want 202", resp.StatusCode)
	}
	resp.Body.Close()
	drainFetches(t, h)
	analyzeAndWait(t, h)
	if got := waveform(t, h, ep.Pid); got.State != "unavailable" {
		t.Fatalf("fetched episode waveform = %q, want unavailable", got.State)
	}
}

// Every part has had its own peaks row all along; only the read was
// pinned to the primary file, which is not part one.
func TestWaveformPerPart(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook").Items
	if len(books) != 1 {
		t.Fatalf("audiobooks = %d, want the one fixture book", len(books))
	}
	book := books[0]

	// Analyzable, not analyzed: pending, never unavailable.
	if got := waveformPart(t, h, book.Pid, 1); got.State != "pending" {
		t.Fatalf("part 1 before analyze = %q, want pending", got.State)
	}

	analyzeAndWait(t, h)

	// Distinct tone durations mean distinct essences, so equal hashes
	// would mean every part answered one file's row.
	seen := map[string]bool{}
	for part := range 3 {
		wf := waveformPart(t, h, book.Pid, part)
		if wf.State != "ready" {
			t.Fatalf("part %d = %q, want ready", part, wf.State)
		}
		if wf.PartIndex == nil || *wf.PartIndex != part {
			t.Errorf("part %d echoed partIndex %v", part, wf.PartIndex)
		}
		if wf.EssenceHash == nil || *wf.EssenceHash == "" {
			t.Fatalf("part %d carries no essence hash", part)
		}
		if seen[*wf.EssenceHash] {
			t.Errorf("part %d repeats an earlier part's essence %q", part, *wf.EssenceHash)
		}
		seen[*wf.EssenceHash] = true
		if wf.Peaks == nil || len(*wf.Peaks) == 0 {
			t.Errorf("part %d is ready with no peaks", part)
		}
	}

	// Part zero, not unavailable: the compatible direction for a client
	// that predates parts.
	bare := waveform(t, h, book.Pid)
	if bare.State != "ready" {
		t.Fatalf("omitted partIndex = %q, want part zero's ready", bare.State)
	}
	if bare.PartIndex == nil || *bare.PartIndex != 0 {
		t.Errorf("omitted partIndex echoed %v, want 0", bare.PartIndex)
	}
	zero := waveformPart(t, h, book.Pid, 0)
	if bare.EssenceHash == nil || zero.EssenceHash == nil || *bare.EssenceHash != *zero.EssenceHash {
		t.Errorf("omitted index answered %v, partIndex=0 answered %v", bare.EssenceHash, zero.EssenceHash)
	}

	// The ETag is per part now, since it derives from the part's essence.
	first := get(t, h.ts, "/api/v1/items/"+book.Pid+"/waveform?partIndex=0", h.token)
	first.Body.Close()
	second := get(t, h.ts, "/api/v1/items/"+book.Pid+"/waveform?partIndex=1", h.token)
	second.Body.Close()
	if a, b := first.Header.Get("ETag"), second.Header.Get("ETag"); a == "" || a == b {
		t.Errorf("part ETags = %q and %q, want two distinct validators", a, b)
	}

	// 404, not 400: neither this endpoint nor the skip map declares one.
	resp := get(t, h.ts, "/api/v1/items/"+book.Pid+"/waveform?partIndex=9", h.token)
	resp.Body.Close()
	if resp.StatusCode != 404 {
		t.Errorf("out-of-range partIndex = %d, want 404", resp.StatusCode)
	}

	// Ignored rather than refused, and echoed back for nobody else.
	music := h.items(t, "?mediaType=music").Items
	if len(music) == 0 {
		t.Fatal("no music scanned")
	}
	if got := waveformPart(t, h, music[0].Pid, 3); got.PartIndex != nil {
		t.Errorf("a track echoed partIndex %d; only multi-file books do", *got.PartIndex)
	}
}

// stageBookWithOnePartLate scans and analyzes a book missing its last
// part, then adds that part and rescans, so the pass genuinely ran over
// a subset and one part is analyzable and unanalyzed. Answers the
// book's pid.
//
// Staged in two steps rather than faked, because the whole point is the
// analysis stamp: a part the pass has never seen and a part it stamped
// and could not measure are the same missing peaks row, and every
// pending-or-unavailable decision downstream turns on telling them
// apart.
func stageBookWithOnePartLate(t *testing.T, h *harness) string {
	t.Helper()
	staged := t.TempDir()
	stagedDir, err := fixtures.GenerateBook(staged)
	if err != nil {
		t.Fatal(err)
	}
	rel, err := filepath.Rel(staged, stagedDir)
	if err != nil {
		t.Fatal(err)
	}
	bookDir := filepath.Join(h.library, rel)
	if err := os.MkdirAll(bookDir, 0o755); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(stagedDir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 3 {
		t.Fatalf("staged parts = %d, want the fixture's 3", len(entries))
	}
	move := func(name string) {
		t.Helper()
		raw, err := os.ReadFile(filepath.Join(stagedDir, name))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(bookDir, name), raw, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	last := entries[len(entries)-1].Name()
	for _, e := range entries[:len(entries)-1] {
		move(e.Name())
	}
	h.rescanAndWait(t)
	analyzeAndWait(t, h)

	move(last)
	h.rescanAndWait(t)

	books := h.items(t, "?mediaType=audiobook").Items
	if len(books) != 1 {
		t.Fatalf("audiobooks = %d, want 1", len(books))
	}
	return books[0].Pid
}

// The stamp is the requested part's file now, so a book can read both
// states across its parts.
func TestWaveformPartlyAnalyzedBookReadsPending(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	book := stageBookWithOnePartLate(t, h)

	if got := waveformPart(t, h, book, 0); got.State != "ready" {
		t.Errorf("part 0 = %q, want the analyzed part to stay ready", got.State)
	}
	// Unavailable here would draw a plain bar forever.
	if got := waveformPart(t, h, book, 2); got.State != "pending" {
		t.Errorf("the late part = %q, want pending rather than unavailable", got.State)
	}
}

// waveformWhole reads one envelope across an item's whole timeline.
func waveformWhole(t *testing.T, h *harness, pid string) Waveform {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/items/"+pid+"/waveform?span=item", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("whole-item waveform status = %d, want 200", resp.StatusCode)
	}
	return decode[Waveform](t, resp)
}

// What a book scrubber draws: the book's own timeline rather than
// whichever file the reader happens to be inside.
func TestWaveformWholeBook(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook").Items
	if len(books) != 1 {
		t.Fatalf("audiobooks = %d, want the one fixture book", len(books))
	}
	book := books[0]

	// Analyzable and unanalyzed reads the same under either span.
	if got := waveformWhole(t, h, book.Pid); got.State != "pending" {
		t.Fatalf("before analyze, whole book = %q, want pending", got.State)
	}

	analyzeAndWait(t, h)

	whole := waveformWhole(t, h, book.Pid)
	if whole.State != "ready" {
		t.Fatalf("whole book = %q, want ready", whole.State)
	}
	if whole.Peaks == nil || whole.Resolution == nil {
		t.Fatal("a ready whole-book envelope must carry peaks and a resolution")
	}
	if len(*whole.Peaks) != *whole.Resolution {
		t.Fatalf("%d peaks for resolution %d", len(*whole.Peaks), *whole.Resolution)
	}
	// One envelope, not one part's: it is not the answer any single
	// part gives, because it is derived from all of them.
	zero := waveformPart(t, h, book.Pid, 0)
	if zero.EssenceHash == nil || whole.EssenceHash == nil {
		t.Fatal("both answers must name what they were measured from")
	}
	if *whole.EssenceHash == *zero.EssenceHash {
		t.Fatal("the whole-book validator is part zero's; re-analysing another part would not invalidate it")
	}
	// A digest of the parts rather than a list of them: the per-part
	// dependency is unit-tested against wholeItemValidator, and what
	// matters over the wire is that it stays short enough to ride an
	// If-None-Match through a reverse proxy however long the book is.
	// A hundred-part book joined raw runs to kilobytes.
	if len(*whole.EssenceHash) > 64 {
		t.Errorf("whole-book validator is %d chars; it has to fit a header buffer", len(*whole.EssenceHash))
	}
	// A part index means nothing across the whole book, so it is not
	// echoed and not obeyed.
	if whole.PartIndex != nil {
		t.Errorf("whole-book answer echoed partIndex %d", *whole.PartIndex)
	}
	resp := get(t, h.ts, "/api/v1/items/"+book.Pid+"/waveform?span=item&partIndex=2", h.token)
	got := decode[Waveform](t, resp)
	if got.EssenceHash == nil || *got.EssenceHash != *whole.EssenceHash {
		t.Errorf("partIndex changed the whole-book answer")
	}
	// Synthesized parts are tones: an all-zero stitch would mean the
	// weighting dropped the signal.
	loud := false
	for _, v := range *whole.Peaks {
		if v > 0 {
			loud = true
			break
		}
	}
	if !loud {
		t.Fatal("every stitched peak is zero")
	}

	// Cacheable like any ready answer, and revalidating is a 304.
	first := get(t, h.ts, "/api/v1/items/"+book.Pid+"/waveform?span=item", h.token)
	first.Body.Close()
	etag := first.Header.Get("ETag")
	if etag == "" {
		t.Fatal("a ready whole-book envelope must carry an ETag")
	}
	req, _ := http.NewRequest("GET", h.ts.URL+"/api/v1/items/"+book.Pid+"/waveform?span=item", nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	req.Header.Set("If-None-Match", etag)
	again, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	again.Body.Close()
	if again.StatusCode != 304 {
		t.Fatalf("revalidated whole-book waveform = %d, want 304", again.StatusCode)
	}

	// A single-file item has no parts to stitch, so the whole-item span
	// is the answer the default already gives.
	music := h.items(t, "?mediaType=music").Items
	if len(music) == 0 {
		t.Fatal("no music scanned")
	}
	track := music[0].Pid
	one, byPart := waveformWhole(t, h, track), waveform(t, h, track)
	if one.State != byPart.State {
		t.Fatalf("single file: span=item = %q, default = %q", one.State, byPart.State)
	}
	if one.Peaks == nil || byPart.Peaks == nil || len(*one.Peaks) != len(*byPart.Peaks) {
		t.Fatal("single file: the two spans answered different envelopes")
	}
	for i := range *one.Peaks {
		if (*one.Peaks)[i] != (*byPart.Peaks)[i] {
			t.Fatalf("single file: the two spans differ at bucket %d", i)
		}
	}
}

// All parts or nothing: half an envelope drawn across a whole timeline
// would be silence somebody could seek into.
func TestWaveformWholeBookWaitsForEveryPart(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	book := stageBookWithOnePartLate(t, h)

	if got := waveformPart(t, h, book, 0); got.State != "ready" {
		t.Fatalf("part 0 = %q, want ready", got.State)
	}
	if got := waveformWhole(t, h, book); got.State != "pending" {
		t.Fatalf("whole book with one part unanalyzed = %q, want pending", got.State)
	}

	// And once the straggler lands, the whole book has an envelope.
	analyzeAndWait(t, h)
	if got := waveformWhole(t, h, book); got.State != "ready" {
		t.Fatalf("after the second pass, whole book = %q, want ready", got.State)
	}
}

func TestAnalyzeRequiresAdmin(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "listener", "password": "long-enough-pw",
	})
	wantStatus(t, resp, 201, "create non-admin user")
	userToken := loginAs(t, h.ts, "listener", "long-enough-pw").Token
	wantStatus(t, reqAs(t, h, "POST", "/api/v1/library/analyze", userToken, nil),
		403, "non-admin analyze")
}

func TestAnalyzeScheduleIsListedAndOffByDefault(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	resp := get(t, h.ts, "/api/v1/admin/schedules", h.token)
	schedules := decode[ScheduleList](t, resp).Schedules
	var found *Schedule
	for i, s := range schedules {
		if string(s.Kind) == "analyze" {
			found = &schedules[i]
		}
	}
	if found == nil {
		t.Fatalf("no analyze schedule listed: %+v", schedules)
	}
	if found.Enabled {
		t.Fatal("the analyze schedule must ship disabled; it decodes the whole library")
	}
	// It is a real schedule, not a placeholder: it takes a cron and
	// switches on like the others.
	resp = h.putJSON(t, "/api/v1/admin/schedules/analyze",
		map[string]any{"cron": "0 2 * * 0", "enabled": true})
	if resp.StatusCode != 200 {
		t.Fatalf("enabling the analyze schedule = %d, want 200", resp.StatusCode)
	}
	got := decode[Schedule](t, resp)
	if !got.Enabled || got.Cron != "0 2 * * 0" {
		t.Fatalf("saved analyze schedule = %+v", got)
	}
	if got.NextRunAt == nil {
		t.Fatal("an enabled schedule reports its next firing")
	}
}

// A multi-file book whose one part is deleted behind the server's back
// answers unavailable for that part.
//
// The item-level MarkMissing cannot record this: it stats every backing
// file and vetoes on any survivor, so the book stays `present` and the
// state read the skip map otherwise relies on never fires. Without the
// named-part resolve, every GET re-enqueues doomed work and re-answers
// pending forever.
func TestSkipMapUnavailableForADeletedBookPart(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook").Items
	if len(books) != 1 {
		t.Fatalf("audiobooks = %d, want the one fixture book", len(books))
	}
	book := books[0]

	skip := func(part int) SkipMap {
		t.Helper()
		return decode[SkipMap](t, get(t,
			h.ts, fmt.Sprintf("/api/v1/items/%s/skip-map?partIndex=%d", book.Pid, part), h.token))
	}
	if got := skip(1).State; got != "pending" {
		t.Fatalf("part 1 before the deletion = %q, want pending", got)
	}

	// Delete one part's bytes only; its siblings stay, which is what
	// makes the item-level verb refuse.
	det := decode[BookDetail](t, get(t, h.ts, "/api/v1/books/"+book.Pid, h.token))
	if len(det.Parts) < 2 {
		t.Fatalf("book has %d parts, want a multi-file fixture", len(det.Parts))
	}
	var removed int
	err := filepath.Walk(h.library, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() || removed > 0 {
			return err
		}
		if strings.Contains(filepath.Base(path), "02") {
			if err := os.Remove(path); err != nil {
				return err
			}
			removed++
		}
		return nil
	})
	if err != nil || removed == 0 {
		t.Fatalf("removing one book part: err=%v removed=%d", err, removed)
	}

	// The surviving parts still answer; the deleted one says so rather
	// than pending forever.
	if got := skip(1).State; got != "unavailable" {
		t.Errorf("deleted part = %q, want unavailable", got)
	}
}
