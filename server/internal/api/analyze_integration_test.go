package api

import (
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

func TestAnalyzeThenWaveform(t *testing.T) {
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

func TestAnalyzeRequiresAdmin(t *testing.T) {
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
