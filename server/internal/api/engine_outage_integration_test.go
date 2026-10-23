package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/connect"
)

// The streaming engine is optional at runtime as well as at install: a
// server whose engine is away serves originals directly, keeps a stream
// minted before the outage playing, refuses only what the engine alone
// makes, and says which is which on /health.

func healthOf(t *testing.T, h *harness) Health {
	t.Helper()
	return decode[Health](t, get(t, h.ts, "/api/v1/health", ""))
}

func musicPid(t *testing.T, h *harness, title string) string {
	t.Helper()
	for _, it := range h.items(t, "?mediaType=music").Items {
		if it.Title == title {
			return it.Pid
		}
	}
	t.Fatalf("no music item titled %q", title)
	return ""
}

func playInfoOf(t *testing.T, h *harness, pid, query string) PlayInfo {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/items/"+pid+"/play-info"+query, h.token)
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("play-info %s = %d: %s", pid, resp.StatusCode, body)
	}
	return decode[PlayInfo](t, resp)
}

// fetchBytes follows a media URL to its bytes.
func fetchBytes(t *testing.T, h *harness, path string) []byte {
	t.Helper()
	resp, err := http.Get(h.ts.URL + path)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK || len(body) == 0 {
		t.Fatalf("GET %s = %d with %d bytes", path, resp.StatusCode, len(body))
	}
	return body
}

// takeEngineAway stops the fake sidecar answering and probes, as the
// bridge's own loop does within its interval.
func takeEngineAway(t *testing.T, h *harness) {
	t.Helper()
	h.engineAway.Store(true)
	if err := h.bridge.Connect(context.Background()); err == nil {
		t.Fatal("a probe of an engine that is away answered nil")
	}
}

func bringEngineBack(t *testing.T, h *harness) {
	t.Helper()
	h.engineAway.Store(false)
	if err := h.bridge.Connect(context.Background()); err != nil {
		t.Fatalf("the engine did not come back: %v", err)
	}
}

// wantEngineDown checks the refusal a request only the engine can serve
// meets while it is away.
func wantEngineDown(t *testing.T, resp *http.Response, what string) {
	t.Helper()
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("%s = %d (%s), want 503", what, resp.StatusCode, body)
	}
	if got := resp.Header.Get("Retry-After"); got != "15" {
		t.Fatalf("%s Retry-After = %q, want 15", what, got)
	}
	var e Error
	if err := json.Unmarshal(body, &e); err != nil {
		t.Fatalf("%s body %q: %v", what, body, err)
	}
	if e.Code != "feature-unavailable" || e.Params == nil || (*e.Params)["feature"] != "streaming-engine" {
		t.Fatalf("%s body = %s, want feature-unavailable naming the streaming engine", what, body)
	}
}

// A server whose sidecar is not up yet starts, reports it, plays
// originals directly, and takes the engine on when it answers.
func TestTheServerStartsWithoutItsEngine(t *testing.T) {
	t.Parallel()
	h := newHarnessWithDeadSidecar(t)

	health := healthOf(t, h)
	if health.Status != "ok" {
		t.Fatalf("status = %q, want ok while the engine is away", health.Status)
	}
	if s := health.Streaming; s == nil || !s.Configured || s.Connected || s.Timelines || s.VoiceBoost || s.FileTools {
		t.Fatalf("streaming = %+v, want configured and nothing else", health.Streaming)
	}

	alpha := musicPid(t, h, "Alpha Song")
	direct := playInfoOf(t, h, alpha, "")
	if !strings.HasPrefix(direct.Url, "/media/download?pid=") || !direct.Seekable {
		t.Fatalf("play-info while away = %+v, want the direct url", direct)
	}
	fetchBytes(t, h, direct.Url)

	bringEngineBack(t, h)
	health = healthOf(t, h)
	if s := health.Streaming; s == nil || !s.Configured || !s.Connected || !s.Timelines || !s.VoiceBoost || !s.FileTools {
		t.Fatalf("streaming = %+v, want connected with what the engine offers", health.Streaming)
	}
	if pi := playInfoOf(t, h, alpha, ""); !strings.HasPrefix(pi.Url, "/media/stream?pid=") {
		t.Fatalf("play-info once the engine answered = %q, want a stream url", pi.Url)
	}
	// A direct url minted meanwhile keeps working, ranges included: a
	// device handed it cannot ask for another.
	fetchBytes(t, h, direct.Url)
	if got := fetchRange(t, h, direct.Url, "bytes=0-99"); len(got) != 100 {
		t.Fatalf("a range of the outage's direct url = %d bytes, want 100", len(got))
	}
}

// fetchRange asks a media URL for a byte range, which has to answer 206.
func fetchRange(t *testing.T, h *harness, path, rng string) []byte {
	t.Helper()
	req, err := http.NewRequest(http.MethodGet, h.ts.URL+path, nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Range", rng)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusPartialContent {
		t.Fatalf("GET %s with %s = %d, want 206", path, rng, resp.StatusCode)
	}
	return body
}

// streamTokenURL is a download-route URL under a stream token bound to
// shape, carried on the URL as the stream route would carry it.
func streamTokenURL(t *testing.T, h *harness, pid string, shape url.Values) string {
	t.Helper()
	token, _ := h.media.MintFor(auth.MediaClaims{
		User: adminUserID(t, h), Purpose: auth.PurposeStream, PID: pid, Shape: shape.Encode(),
	}, time.Minute)
	u := "/media/download?pid=" + url.QueryEscape(pid) + "&mt=" + url.QueryEscape(token)
	if len(shape) > 0 {
		u += "&" + shape.Encode()
	}
	return u
}

func statusOf(t *testing.T, h *harness, path string) int {
	t.Helper()
	resp, err := http.Get(h.ts.URL + path)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	return resp.StatusCode
}

// The download route takes a stream token for the original's bytes of a
// whole file whatever the engine is doing, since the stream route passes
// those same bytes through. A token for what only the engine makes stays
// refused there: a capped or boosted stream, a transcode, a window of a
// rip, none of which is the whole file the route would hand over.
func TestTheDownloadRouteOpensOnlyTheOriginalsBytes(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	// Bravo is an mp3 file; the rip carves Alpha's flac into windows.
	window := carveAlpha(t, h)
	bravo := musicPid(t, h, "Bravo Song")

	for _, tc := range []struct {
		name  string
		pid   string
		shape url.Values
		want  int
	}{
		{"an original", bravo, nil, http.StatusOK},
		{"a copy of the source", bravo, url.Values{"fmt": {"mp3"}}, http.StatusOK},
		{"voice boost", bravo, url.Values{"vb": {"1"}}, http.StatusUnauthorized},
		{"a transcode", bravo, url.Values{"fmt": {"flac"}}, http.StatusUnauthorized},
		{"a bitrate cap", bravo, url.Values{"fmt": {"opus"}, "enc": {"1"}, "br": {"128"}}, http.StatusUnauthorized},
		{"a window of a rip", window, nil, http.StatusUnauthorized},
	} {
		if got := statusOf(t, h, streamTokenURL(t, h, tc.pid, tc.shape)); got != tc.want {
			t.Errorf("engine up, %s: %d, want %d", tc.name, got, tc.want)
		}
	}

	// While the engine is away the window plays directly, whole with its
	// span, as on a server without one.
	takeEngineAway(t, h)
	if got := statusOf(t, h, streamTokenURL(t, h, window, nil)); got != http.StatusOK {
		t.Errorf("engine away, a window of a rip: %d, want 200", got)
	}
	if got := statusOf(t, h, streamTokenURL(t, h, bravo, url.Values{"vb": {"1"}})); got != http.StatusUnauthorized {
		t.Errorf("engine away, voice boost: %d, want 401", got)
	}
}

// carveAlpha lays a cue sheet over the fixture flac, which the scan
// then carves into windows, and returns the second one's pid: a track
// that is a window into a larger file.
func carveAlpha(t *testing.T, h *harness) string {
	t.Helper()
	flacs, err := filepath.Glob(filepath.Join(h.library, "alpha*"))
	if err != nil || len(flacs) != 1 {
		t.Fatalf("locating the fixture flac: %v %v", flacs, err)
	}
	cue := fmt.Sprintf("PERFORMER \"Cue Artist\"\nTITLE \"Cue Album\"\nFILE %q WAVE\n"+
		"  TRACK 01 AUDIO\n    TITLE \"Cue One\"\n    INDEX 01 00:00:00\n"+
		"  TRACK 02 AUDIO\n    TITLE \"Cue Two\"\n    INDEX 01 00:01:00\n",
		filepath.Base(flacs[0]))
	if err := os.WriteFile(filepath.Join(h.library, "alpha.cue"), []byte(cue), 0o644); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	return musicPid(t, h, "Cue Two")
}

// wantEngineAwayRefusal checks a device queue refused because the engine
// is away: the outage's feature, naming the item, which a controller
// reads as "shortly" rather than "never on this server".
func wantEngineAwayRefusal(t *testing.T, what string, err error, pid string) {
	t.Helper()
	var inv connect.InvalidError
	if !errors.As(err, &inv) || inv.Code != "feature-unavailable" ||
		inv.Params["feature"] != flow.FeatureStreamingEngine || inv.Params["pid"] != pid {
		t.Fatalf("%s: err = %#v, want feature-unavailable naming the streaming engine and %s", what, err, pid)
	}
}

// What only the engine can render for a device waits for it, in the
// outage's words: everything for the jukebox, whose player reads WAV
// alone, so an original is no fallback for it (a track, a book's part),
// and a carved track for any device, which plays once the engine
// answers again, unlike on a server without one.
func TestDeviceQueuesOnlyTheEngineRendersWaitForIt(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	window := carveAlpha(t, h)
	books := h.items(t, "?mediaType=audiobook")
	if len(books.Items) != 1 {
		t.Fatalf("audiobooks = %d, want 1", len(books.Items))
	}
	book, bravo := books.Items[0].Pid, musicPid(t, h, "Bravo Song")
	user := adminUserID(t, h)
	takeEngineAway(t, h)

	for _, tc := range []struct {
		what, pid string
		kind      string
	}{
		{"a track for the jukebox", bravo, connect.KindJukebox},
		{"a book for the jukebox", book, connect.KindJukebox},
		{"a window for a renderer", window, connect.KindDLNA},
		{"a window for a cast device", window, connect.KindCast},
	} {
		_, err := castResolver(h).StreamItems(context.Background(), user,
			[]connect.QueueEntry{{PID: tc.pid, DurationMS: 30_000}},
			connect.EndpointTarget{Kind: tc.kind}, "", time.Hour)
		wantEngineAwayRefusal(t, tc.what, err, tc.pid)
	}
	// What a renderer plays from the original still goes out.
	if _, err := castResolver(h).StreamItems(context.Background(), user,
		[]connect.QueueEntry{{PID: bravo, DurationMS: 30_000}},
		connect.EndpointTarget{Kind: connect.KindDLNA}, "", time.Hour); err != nil {
		t.Fatalf("a track for a renderer while away: %v", err)
	}
}

// quietDriver is a device that takes whatever it is sent and reports
// nothing.
type quietDriver struct{ events chan connect.DriverEvent }

func (quietDriver) Load(context.Context, []connect.MediaItem, int, int64, bool) error { return nil }
func (quietDriver) Play(context.Context) error                                        { return nil }
func (quietDriver) Pause(context.Context) error                                       { return nil }
func (quietDriver) Stop(context.Context) error                                        { return nil }
func (quietDriver) SeekTo(context.Context, int64) error                               { return nil }
func (quietDriver) SetVolume(context.Context, float64) error                          { return nil }
func (quietDriver) SetRate(context.Context, float64) error                            { return nil }
func (d quietDriver) Events() <-chan connect.DriverEvent                              { return d.events }
func (quietDriver) Close() error                                                      { return nil }

// Over REST that refusal is the outage's 503 with when to ask again, as
// a timeline mint's is, whether the session starts on the jukebox or is
// moved there.
func TestTheJukeboxRefusesASessionWhileTheEngineIsAway(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	jukebox, err := h.connect.EndpointOnline(context.Background(), connect.KindJukebox, "jukebox", "Jukebox", "", true, false,
		func(context.Context) (connect.Driver, error) {
			return quietDriver{events: make(chan connect.DriverEvent)}, nil
		})
	if err != nil {
		t.Fatal(err)
	}
	bravo := musicPid(t, h, "Bravo Song")
	client := dialWS(t, h, loginAs(t, h.ts, "admin", testPassword).Token)
	client.register("Phone")
	client.send(map[string]any{
		"type": "session-report", "playing": false, "positionMs": 1000, "index": 0,
		"itemPids": []string{bravo}, "queueVersion": 1,
	})
	session, _ := client.expect("session")["session"].(map[string]any)
	sessID, _ := session["id"].(string)
	client.pumpEndpoint(t, newEndpointState())

	takeEngineAway(t, h)
	wantEngineDown(t, h.postJSON(t, "/api/v1/player/sessions",
		map[string]any{"endpointId": jukebox.ID, "itemPids": []string{bravo}}), "a session started on the jukebox")
	wantEngineDown(t, h.postJSON(t, "/api/v1/player/sessions/"+sessID+"/transfer",
		map[string]any{"endpointId": jukebox.ID}), "a session moved to the jukebox")
}

// A carved track on a share link waits for the engine as well: the
// visitor is told to come back shortly, where a server without one
// says it cannot.
func TestASharedWindowWaitsForTheEngine(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	share := shareOf(t, h, carveAlpha(t, h), nil)
	takeEngineAway(t, h)
	resp, body := anon(t, h, http.MethodGet, share.Url+"/stream?i=0", "")
	resp.Body = io.NopCloser(bytes.NewReader(body))
	wantEngineDown(t, resp, "a shared window while the engine is away")
}

// A timeline mint whose call finds the engine gone is the outage from
// that moment: the caller gets the outage's refusal, which says to play
// per item and ask again, rather than an internal error, and the bridge
// takes the engine for gone without waiting for its next probe.
func TestATimelineMintThatFindsTheEngineGoneIsTheOutage(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pids := []string{musicPid(t, h, "Alpha Song"), musicPid(t, h, "Bravo Song")}
	h.dropTimeline.Store(true)
	wantEngineDown(t, h.postJSON(t, "/api/v1/player/timeline", map[string]any{"itemPids": pids}),
		"a timeline mint the engine dropped")
	if h.bridge.Up() {
		t.Fatal("the bridge still takes the engine for up")
	}
}

// A queue sent to a device while the engine is away keeps playing after
// it returns: the device holds URLs it cannot mint again.
func TestADeviceQueueLoadedDuringAnOutagePlaysOnAfterIt(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	takeEngineAway(t, h)
	items, err := castResolver(h).StreamItems(context.Background(), adminUserID(t, h),
		castEntries(t, h, "Alpha Song", "Bravo Song"),
		connect.EndpointTarget{Kind: connect.KindDLNA}, "", time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	bringEngineBack(t, h)
	for _, item := range items {
		if !strings.HasPrefix(item.URL, "/media/download?") {
			t.Fatalf("item url while away = %q, want the direct url", item.URL)
		}
		if got := fetchRange(t, h, item.URL, "bytes=0-99"); len(got) != 100 {
			t.Fatalf("a range of %s after the outage = %d bytes, want 100", item.URL, len(got))
		}
	}
}

// An outage at runtime: play-info mints what an engine-less server
// does, a stream minted before it plays on through the download route,
// and what only the engine makes is refused in words a client keys on.
func TestAnEngineOutageServesOriginalsAndRefusesTheRest(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook")
	if len(books.Items) != 1 {
		t.Fatalf("audiobooks = %d, want 1", len(books.Items))
	}
	book := books.Items[0].Pid
	alpha := musicPid(t, h, "Alpha Song")

	original := playInfoOf(t, h, alpha, "")
	part := playInfoOf(t, h, book, "?positionMs=0")
	if !strings.HasPrefix(original.Url, "/media/stream?") || !strings.Contains(part.Url, "f=") {
		t.Fatalf("minted while up: %q and %q, want stream urls", original.Url, part.Url)
	}
	boostToken, _ := h.media.MintFor(auth.MediaClaims{
		User: adminUserID(t, h), Purpose: auth.PurposeStream, PID: alpha, Shape: "vb=1",
	}, time.Minute)
	boosted := "/media/stream?pid=" + url.QueryEscape(alpha) + "&mt=" + url.QueryEscape(boostToken) + "&vb=1"
	streamed := fetchBytes(t, h, original.Url)

	takeEngineAway(t, h)

	if s := healthOf(t, h).Streaming; s == nil || !s.Configured || s.Connected {
		t.Fatalf("streaming while away = %+v, want configured and not connected", s)
	}
	direct := playInfoOf(t, h, alpha, "")
	if !strings.HasPrefix(direct.Url, "/media/download?pid=") {
		t.Fatalf("play-info while away = %q, want the direct url", direct.Url)
	}
	if got := fetchBytes(t, h, direct.Url); !bytes.Equal(got, streamed) {
		t.Fatal("the direct url serves other bytes than the stream did")
	}

	// Minted before the outage: the stream route hands it on.
	noFollow := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	resp, err := noFollow.Get(h.ts.URL + original.Url)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if loc := resp.Header.Get("Location"); resp.StatusCode != http.StatusFound || !strings.HasPrefix(loc, "/media/download?") {
		t.Fatalf("an original minted before the outage = %d to %q, want 302 to the download route", resp.StatusCode, loc)
	}
	if got := fetchBytes(t, h, original.Url); !bytes.Equal(got, streamed) {
		t.Fatal("the redirected stream serves other bytes")
	}
	fetchBytes(t, h, part.Url)

	streamResp, err := http.Get(h.ts.URL + boosted)
	if err != nil {
		t.Fatal(err)
	}
	wantEngineDown(t, streamResp, "a boosted stream")

	timeline := postJSON(t, h.ts.URL+"/api/v1/player/timeline", h.token, `{"itemPids":["`+alpha+`"]}`)
	wantEngineDown(t, timeline, "a queue timeline")

	// Subsonic takes the same branch: the original, by redirect. An
	// offset, which only the engine cuts, is refused rather than played
	// from the top under a client that reads its clock as the offset.
	secret := newSubsonicSecret(t, h)
	if loc := streamRedirect(t, h, "/rest/stream?apiKey="+secret+"&id="+alpha); !strings.HasPrefix(loc, "/media/download?") {
		t.Fatalf("subsonic stream while away = %q, want the download route", loc)
	}
	resp, err = noFollow.Get(h.ts.URL + "/rest/stream?apiKey=" + secret + "&f=json&c=test&id=" + alpha + "&timeOffset=2")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK || !strings.Contains(string(body), `"status":"failed"`) {
		t.Fatalf("an offset while away = %d to %q (%s), want a refusal", resp.StatusCode, resp.Header.Get("Location"), body)
	}

	bringEngineBack(t, h)
	if pi := playInfoOf(t, h, alpha, ""); !strings.HasPrefix(pi.Url, "/media/stream?pid=") {
		t.Fatalf("play-info after the outage = %q, want a stream url again", pi.Url)
	}
}

// /health says whether there is an engine at all, and whether this
// server keeps podcasts.
func TestHealthReportsTheEngineAndPodcasts(t *testing.T) {
	t.Parallel()
	direct := healthOf(t, newHarnessDirect(t))
	if s := direct.Streaming; s == nil || s.Configured || s.Connected {
		t.Fatalf("streaming without an engine = %+v, want not configured", s)
	}
	if direct.Podcasts == nil || *direct.Podcasts {
		t.Fatalf("podcasts without a podcast dir = %v, want false", direct.Podcasts)
	}

	withPodcasts := healthOf(t, newPodcastHarness(t))
	if p := withPodcasts.Podcasts; p == nil || !*p {
		t.Fatalf("podcasts with a podcast dir = %v, want true", p)
	}
	if s := withPodcasts.Streaming; s == nil || !s.Configured || !s.Connected {
		t.Fatalf("streaming with the engine answering = %+v, want connected", s)
	}
}
