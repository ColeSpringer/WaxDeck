package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/adapter/subsonic"
	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/events"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// harness is a full server over a real catalog scanned from a
// synthesized fixture library, streaming through a fake WaxFlow that
// serves files from the same root.
type harness struct {
	ts      *httptest.Server
	token   string
	library string
	// podcastDir is the episode download root, set only by
	// newPodcastHarness. Tests that need to interfere with a downloaded
	// file on disk reach it here.
	podcastDir string
	svc        *service.Library
	store      *db.DB
	// media mints the query-string tokens the raw /media/* routes take,
	// for tests that drive one of those endpoints as a chosen user
	// rather than through a mint the API performed.
	media *auth.MediaTokens
	// bridge is the fake WaxFlow bridge, nil for a no-bridge harness.
	// Tests that drive the connect resolver directly need it to build
	// one of their own.
	bridge  *flow.Bridge
	connect *connect.Service
	backups *service.Backups
	group   *supervise.Group
	flowReq struct{ apiKey, format, dynamics, gain string } // captured by the fake sidecar
}

// skipWithoutUnwritablePaths skips a test that makes a path unwritable to
// force a write failure, on the platforms where that setup cannot fail.
// Root ignores the modes. Windows has no POSIX bits at all: os.Chmod only
// toggles the read-only attribute, which does not stop writes into a
// directory, and which waxlabel strips off a target before replacing it
// (destination_windows.go, clearTargetReadOnly) so its rename matches the
// POSIX one it mirrors. os.Geteuid answers -1 there, so it is checked first.
func skipWithoutUnwritablePaths(t *testing.T) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("windows os.Chmod cannot make a path unwritable, so the setup cannot fail")
	}
	if os.Geteuid() == 0 {
		t.Skip("root ignores permissions, so the unwritable setup cannot fail")
	}
}

func newHarness(t *testing.T, extraRoots ...service.Root) *harness {
	return newHarnessWith(t, nil, extraRoots...)
}

// newHarnessWith lets a test adjust the service configuration before
// the catalog opens (the podcast surface needs a download dir and the
// private-address guard relaxed for loopback feeds).
func newHarnessWith(t *testing.T, mutate func(*service.Config), extraRoots ...service.Root) *harness {
	t.Helper()
	return newHarnessCore(t, mutate, false, extraRoots...)
}

// newHarnessDirect builds the stack without the streaming bridge: the
// shape of a server running with no WAXDECK_FLOW_URL, where play-info
// serves original bytes directly.
func newHarnessDirect(t *testing.T) *harness {
	t.Helper()
	return newHarnessCore(t, nil, true)
}

func newHarnessCore(t *testing.T, mutate func(*service.Config), noBridge bool, extraRoots ...service.Root) *harness {
	t.Helper()
	h := &harness{}
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	if os.Getenv("HARNESS_LOG") != "" {
		log = slog.New(slog.NewTextHandler(os.Stderr, nil))
	}

	h.library = t.TempDir()
	generateDemoLibrary(t, h.library)

	dataDir := t.TempDir()
	store, err := db.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	h.store = store
	t.Cleanup(func() { store.Close() })

	secret := []byte("0123456789abcdef0123456789abcdef")
	sealer, err := auth.NewSealer(secret, "waxdeck-app-password-v1")
	if err != nil {
		t.Fatal(err)
	}
	cipher, err := auth.NewAADSealer(secret, "waxdeck-catalog-secret-v1")
	if err != nil {
		t.Fatal(err)
	}

	group := supervise.NewGroup(log)
	h.group = group
	cfg := service.Config{
		DataDir:      dataDir,
		Roots:        append([]service.Root{{Name: "lib", Path: h.library}}, extraRoots...),
		Sealer:       sealer,
		SecretCipher: cipher,
		Logger:       log,
	}
	if mutate != nil {
		mutate(&cfg)
	}
	svc, err := service.Open(ctx, cfg, store, group)
	if err != nil {
		t.Fatal(err)
	}
	h.svc = svc
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
	})

	media := auth.NewMediaTokens(secret, 0)
	var bridge *flow.Bridge
	if !noBridge {
		bridge = newFakeFlowBridge(t, ctx, h, cfg, media, svc, log)
		svc.SetFlowJobs(bridge)
	}
	h.bridge = bridge

	hub := events.New(svc)
	group.Go(ctx, "event-hub", hub.Run)

	connectSvc, err := connect.New(ctx, connect.Config{
		Store:            store,
		Group:            group,
		Resolver:         &ConnectResolver{Svc: svc, Bridge: bridge, Media: media},
		Sink:             &ConnectSink{Svc: svc},
		Bases:            connect.Bases{LAN: "http://192.0.2.10:4420", Loopback: "http://127.0.0.1:4420"},
		InvalidatePlayer: hub.MarkPlayerAll,
	})
	if err != nil {
		t.Fatal(err)
	}
	h.connect = connectSvc
	group.Go(ctx, "connect", connectSvc.Run)

	h.backups = service.NewBackups(svc, dataDir, nil)
	srv := NewServer("test", Options{
		Service:  svc,
		Bridge:   bridge,
		Sessions: auth.NewSessions(store),
		Media:    media,
		Connect:  connectSvc,
		Group:    group,
		Bases:    connect.Bases{LAN: "http://192.0.2.10:4420"},
		Backups:  h.backups,
		// A real server always mints share tokens from its secret
		// (main.go), and the share endpoints reach for them without a
		// guard: leaving this unset made the harness the only place a
		// share link could not be minted.
		Shares: auth.NewShareTokens(secret),
	})
	apiHandler := HandlerWithOptions(
		NewStrictHandlerWithOptions(srv, nil, StrictHTTPServerOptions{
			RequestErrorHandlerFunc:  RequestErrorHandler,
			ResponseErrorHandlerFunc: ResponseErrorHandler,
		}),
		StdHTTPServerOptions{
			BaseURL:     "/api/v1",
			Middlewares: []MiddlewareFunc{srv.AuthMiddleware},
		},
	)
	mux := http.NewServeMux()
	mux.Handle("/api/v1/", apiHandler)
	mux.Handle("GET /api/v1/ws", srv.AuthMiddleware(srv.ServeWS(hub)))
	mux.Handle(BackupArchiveRoute, srv.AuthMiddleware(http.HandlerFunc(srv.ServeBackupArchive)))
	mux.HandleFunc("GET /media/download", srv.ServeDownload)
	mux.HandleFunc("GET /media/enclosure", srv.ServeEnclosure)
	mux.HandleFunc("GET /media/art", srv.ServeMediaArt)
	mux.HandleFunc("GET /media/radio/{pid}", srv.ServeRadio)
	// The public share surface, mounted as main.go mounts it (minus the
	// metrics wrapper, which is main.go's own): the landing page reads
	// its token out of the route pattern, so it needs the real pattern.
	mux.HandleFunc("GET /s/{token}", srv.ServeSharePage)
	mux.HandleFunc("GET /s/{token}/stream", srv.ServeShareStream)
	mux.HandleFunc("GET /s/{token}/art", srv.ServeShareArt)
	mux.HandleFunc("GET /s/{token}/download", srv.ServeShareDownload)
	mux.Handle("/rest/", subsonic.New(svc, bridge, media, "test", log))
	if bridge != nil {
		mux.HandleFunc("/media/stream", bridge.ServeStream)
		mux.HandleFunc("/media/hls/", bridge.ServeHLS)
	}
	h.ts = httptest.NewServer(mux)
	t.Cleanup(h.ts.Close)

	h.media = media
	h.token = login(t, h.ts)
	h.rescanAndWait(t)
	return h
}

// newFakeFlowBridge builds the fake WaxFlow sidecar (/caps as the
// flavored build reports it, /stream serving the named source file,
// ranges included) and the bridge over it.
func newFakeFlowBridge(t *testing.T, ctx context.Context, h *harness, cfg service.Config, media *auth.MediaTokens, svc *service.Library, log *slog.Logger) *flow.Bridge {
	t.Helper()
	// toolJobs answers the merge and split job surface with real
	// synthesized audio; analyze jobs fall through to the static
	// handling below. Defined in tools_integration_test.go.
	toolJobs := newFakeToolJobStore(t, h.library)
	fakeFlow := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if toolJobs.handle(w, r) {
			return
		}
		switch r.URL.Path {
		case "/caps":
			fmt.Fprint(w, `{
				"schemaVersion": 1,
				"outputs": [
					{"name":"wav","live":true},{"name":"flac","live":true},
					{"name":"mp3","live":true},{"name":"opus","live":true},
					{"name":"aac","live":true},{"name":"alac","live":true}
				],
				"delivery": {"progressive":true,"hls":true,"hlsFormats":["opus","flac","aac","alac"],
					"cutFormats":["opus","aac"],"pid":true,"timelines":true,"jobs":true},
				"dsp": {"gainModes":["off","track","album"],"gainMaxDb":12,"gainMaxVoiceDb":24,
					"dynamics":["off","voice"]}
			}`)
		case "/hls/timeline":
			var req struct {
				Srcs []struct{ Src string } `json:"srcs"`
			}
			json.NewDecoder(r.Body).Decode(&req)
			w.WriteHeader(http.StatusCreated)
			boundaries := make([]map[string]int64, 0, len(req.Srcs))
			var off int64
			for range req.Srcs {
				boundaries = append(boundaries, map[string]int64{"offsetSamples": off, "durationSamples": 44100})
				off += 44100
			}
			json.NewEncoder(w).Encode(map[string]any{
				"schemaVersion": 1, "tl": "tl-fake-digest", "members": len(req.Srcs),
				"durationSeconds": float64(len(req.Srcs)), "envelopeRate": 44100,
				"boundaries": boundaries,
			})
		case "/sign":
			var req struct {
				Path   string            `json:"path"`
				Params map[string]string `json:"params"`
			}
			json.NewDecoder(r.Body).Decode(&req)
			if req.Params["tl"] != "" && req.Params["gain"] == "" {
				// Mirrors the real daemon: tag-driven gain modes are
				// refused on timelines, explicit values only.
				http.Error(w, `{"error":"tag gain on timeline","code":"invalid-request"}`, http.StatusBadRequest)
				return
			}
			q := url.Values{}
			for k, v := range req.Params {
				q.Set(k, v)
			}
			q.Set("sig", "fakesig")
			json.NewEncoder(w).Encode(map[string]any{
				"schemaVersion": 1, "url": req.Path + "?" + q.Encode(),
				"exp": time.Now().Add(time.Hour).Unix(),
			})
		case "/hls/master.m3u8":
			if r.URL.Query().Get("sig") == "" {
				http.Error(w, "unsigned", http.StatusUnauthorized)
				return
			}
			w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
			fmt.Fprint(w, "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=160000\nmedia.m3u8?v=1&sig=child\n")
		case "/jobs":
			// One-shot analyze jobs finish instantly in the fake.
			fmt.Fprint(w, `{"schemaVersion":2,"id":"job1","state":"done",
				"analysis":{"integratedLufs":-20.5,"truePeakDb":-1.2,"rate":44100}}`)
		case "/jobs/job1":
			fmt.Fprint(w, `{"schemaVersion":2,"id":"job1","state":"done",
				"analysis":{"integratedLufs":-20.5,"truePeakDb":-1.2,"rate":44100}}`)
		case "/jobs/job1/result":
			fmt.Fprint(w, `{"schemaVersion":1,"version":"silence-1","thresholdDb":-50,
				"minSeconds":0.5,"rate":44100,"durationSeconds":5,
				"spans":[{"fromSample":0,"toSample":66150,"fromSeconds":0,"toSeconds":1.5},
					{"fromSample":176400,"toSample":220500,"fromSeconds":4,"toSeconds":5}]}`)
		case "/stream":
			h.flowReq.apiKey = r.Header.Get("X-API-Key")
			h.flowReq.format = r.URL.Query().Get("format")
			h.flowReq.dynamics = r.URL.Query().Get("dynamics")
			h.flowReq.gain = r.URL.Query().Get("gain")
			src := r.URL.Query().Get("src")
			if r.URL.Query().Get("id") == "" {
				http.Error(w, "missing id", http.StatusBadRequest)
				return
			}
			if rel, ok := strings.CutPrefix(src, "lib/"); ok {
				http.ServeFile(w, r, filepath.Join(h.library, filepath.FromSlash(rel)))
				return
			}
			if rel, ok := strings.CutPrefix(src, "podcasts/"); ok && cfg.PodcastDir != "" {
				http.ServeFile(w, r, filepath.Join(cfg.PodcastDir, filepath.FromSlash(rel)))
				return
			}
			http.Error(w, "bad src", http.StatusBadRequest)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(fakeFlow.Close)

	flowRoots := []flow.Root{{Name: "lib", Path: h.library}}
	if cfg.PodcastDir != "" {
		flowRoots = append(flowRoots, flow.Root{Name: "podcasts", Path: cfg.PodcastDir})
	}
	bridge, err := flow.New(ctx, flow.Config{
		BaseURL:  fakeFlow.URL,
		APIKey:   "test-flow-key",
		Roots:    flowRoots,
		Tokens:   media,
		Resolver: svc,
		Logger:   log,
	})
	if err != nil {
		t.Fatal(err)
	}
	return bridge
}

// rescanAndWait runs a scan through the API and polls the job to done.
func (h *harness) rescanAndWait(t *testing.T) {
	t.Helper()
	req, _ := http.NewRequest("POST", h.ts.URL+"/api/v1/library/rescan", nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 202 {
		t.Fatalf("rescan status = %d, want 202", resp.StatusCode)
	}
	job := decode[Job](t, resp)
	if !strings.HasPrefix(job.Pid, "jb-") {
		t.Fatalf("job pid = %q, want jb- prefix", job.Pid)
	}
	deadline := time.Now().Add(30 * time.Second)
	for {
		resp := get(t, h.ts, "/api/v1/jobs/"+job.Pid, h.token)
		j := decode[Job](t, resp)
		switch j.State {
		case "done":
			return
		case "failed", "crashed", "canceled":
			t.Fatalf("scan job ended %s: %v", j.State, deref(j.Error))
		}
		if time.Now().After(deadline) {
			t.Fatal("scan job did not finish in time")
		}
		time.Sleep(50 * time.Millisecond)
	}
}

func (h *harness) items(t *testing.T, query string) ItemPage {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/library/items"+query, h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("items%s status = %d", query, resp.StatusCode)
	}
	return decode[ItemPage](t, resp)
}

func (h *harness) postJSON(t *testing.T, path string, body any) *http.Response {
	t.Helper()
	raw, _ := json.Marshal(body)
	req, _ := http.NewRequest("POST", h.ts.URL+path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func TestCatalogBrowse(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	page := h.items(t, "")
	if len(page.Items) != 4 {
		t.Fatalf("scanned %d items, want 4: %+v", len(page.Items), page.Items)
	}
	for i, want := range []string{"Alpha Song", "Bravo Song", "Charlie Song", "Delta Song"} {
		if page.Items[i].Title != want {
			t.Fatalf("item %d title = %q, want %q", i, page.Items[i].Title, want)
		}
		if !strings.HasPrefix(page.Items[i].Pid, "tr-") {
			t.Fatalf("item pid = %q, want tr- prefix", page.Items[i].Pid)
		}
	}

	// Keyset pagination: one item at a time, no skips, no duplicates.
	var seen []string
	cursor := ""
	for range 10 {
		q := "?limit=1"
		if cursor != "" {
			q += "&cursor=" + url.QueryEscape(cursor)
		}
		p := h.items(t, q)
		for _, it := range p.Items {
			seen = append(seen, it.Pid)
		}
		if p.NextCursor == nil {
			break
		}
		cursor = *p.NextCursor
	}
	uniq := map[string]bool{}
	for _, pid := range seen {
		uniq[pid] = true
	}
	if len(seen) != 4 || len(uniq) != 4 {
		t.Fatalf("paged pids = %v, want 4 distinct", seen)
	}

	// The music filter matches everything here (all fixtures are tracks).
	if p := h.items(t, "?mediaType=music"); len(p.Items) != 4 {
		t.Fatalf("music filter returned %d items", len(p.Items))
	}
	if p := h.items(t, "?mediaType=audiobook"); len(p.Items) != 0 {
		t.Fatalf("audiobook filter returned %d items", len(p.Items))
	}

	// Browse lists answer too.
	resp := get(t, h.ts, "/api/v1/library/browse?list=recently-added", h.token)
	if bp := decode[ItemPage](t, resp); len(bp.Items) != 4 {
		t.Fatalf("recently-added returned %d items", len(bp.Items))
	}

	// A random browse without a seed gets a fresh one back, and passing
	// it again reproduces the same order.
	resp = get(t, h.ts, "/api/v1/library/browse?list=random", h.token)
	rp := decode[ItemPage](t, resp)
	if rp.Seed == nil {
		t.Fatal("random browse returned no seed")
	}
	resp = get(t, h.ts, fmt.Sprintf("/api/v1/library/browse?list=random&seed=%d", *rp.Seed), h.token)
	same := decode[ItemPage](t, resp)
	for i := range rp.Items {
		if rp.Items[i].Pid != same.Items[i].Pid {
			t.Fatalf("same seed produced a different order at %d", i)
		}
	}

	// Search finds one title.
	resp = get(t, h.ts, "/api/v1/library/search?q=Charlie", h.token)
	sr := decode[SearchResults](t, resp)
	if len(sr.Tracks) != 1 || sr.Tracks[0].Title != "Charlie Song" {
		t.Fatalf("search tracks = %+v", sr.Tracks)
	}

	// Detail carries the source codec.
	resp = get(t, h.ts, "/api/v1/items/"+page.Items[0].Pid, h.token)
	item := decode[Item](t, resp)
	if item.Codec == nil || *item.Codec != "flac" {
		t.Fatalf("alpha codec = %v, want flac", item.Codec)
	}

	// No artwork or lyrics in these fixtures: structured 404s.
	for _, sub := range []string{"art", "lyrics"} {
		resp := get(t, h.ts, "/api/v1/items/"+page.Items[0].Pid+"/"+sub, h.token)
		if resp.StatusCode != 404 {
			t.Fatalf("%s status = %d, want 404", sub, resp.StatusCode)
		}
		resp.Body.Close()
	}
}

func TestStreamRoundTrip(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "?limit=1")
	pid := page.Items[0].Pid

	resp := get(t, h.ts, "/api/v1/items/"+pid+"/play-info", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("play-info status = %d", resp.StatusCode)
	}
	pi := decode[PlayInfo](t, resp)
	if pi.MimeType != "audio/flac" || !pi.Seekable {
		t.Fatalf("play-info = %+v", pi)
	}

	// The stream URL is origin-relative and playable without headers.
	streamResp, err := http.Get(h.ts.URL + pi.Url)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(streamResp.Body)
	streamResp.Body.Close()
	if streamResp.StatusCode != 200 {
		t.Fatalf("stream status = %d", streamResp.StatusCode)
	}
	want, err := os.ReadFile(filepath.Join(h.library, "alpha.flac"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(body, want) {
		t.Fatalf("streamed %d bytes, want the %d byte source", len(body), len(want))
	}
	if h.flowReq.apiKey != "test-flow-key" {
		t.Fatalf("sidecar saw API key %q", h.flowReq.apiKey)
	}
	if h.flowReq.format != "auto" {
		t.Fatalf("whole-file stream format = %q, want auto", h.flowReq.format)
	}

	// Range requests pass through the proxy.
	req, _ := http.NewRequest("GET", h.ts.URL+pi.Url, nil)
	req.Header.Set("Range", "bytes=0-99")
	rangeResp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	rangeBody, _ := io.ReadAll(rangeResp.Body)
	rangeResp.Body.Close()
	if rangeResp.StatusCode != http.StatusPartialContent || len(rangeBody) != 100 {
		t.Fatalf("range status = %d, body = %d bytes", rangeResp.StatusCode, len(rangeBody))
	}

	// A token minted for one item authorizes nothing else.
	other := h.items(t, "?limit=2").Items[1]
	u, _ := url.Parse(pi.Url)
	crossed := "/media/stream?pid=" + url.QueryEscape(other.Pid) + "&mt=" + url.QueryEscape(u.Query().Get("mt"))
	crossResp, err := http.Get(h.ts.URL + crossed)
	if err != nil {
		t.Fatal(err)
	}
	crossResp.Body.Close()
	if crossResp.StatusCode != 401 {
		t.Fatalf("cross-item token status = %d, want 401", crossResp.StatusCode)
	}

	// No token at all: 401.
	bare, err := http.Get(h.ts.URL + "/media/stream?pid=" + url.QueryEscape(pid))
	if err != nil {
		t.Fatal(err)
	}
	bare.Body.Close()
	if bare.StatusCode != 401 {
		t.Fatalf("tokenless stream status = %d, want 401", bare.StatusCode)
	}
}

func TestResumeAndListens(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	page := h.items(t, "?limit=2")
	pid := page.Items[0].Pid

	// Checkpoint a position and read it back: the resume path.
	resp := h.putJSON(t, "/api/v1/items/"+pid+"/play-state", PlayStateUpdate{PositionMs: 750})
	if resp.StatusCode != 204 {
		t.Fatalf("checkpoint status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	st := decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-state", h.token))
	if st.PositionMs != 750 {
		t.Fatalf("resume position = %d, want 750", st.PositionMs)
	}

	// Report one qualifying session, one for an unknown item, and one
	// with a source outside the declared enum: the two bad ones are
	// permanently rejected, never silently stored.
	bogus := "bogus"
	report := ListenReport{Sessions: []ListenSession{
		{SessionId: "sess-1", Pid: pid, StartedAt: time.Now().UTC(), MsPlayed: 900, Finished: ptr(true)},
		{SessionId: "sess-2", Pid: "tr-01JZX5N8QW3F4V9T2B7KD3M9R6", StartedAt: time.Now().UTC(), MsPlayed: 900},
		{SessionId: "sess-3", Pid: pid, StartedAt: time.Now().UTC(), MsPlayed: 900, Source: (*ListenSessionSource)(&bogus)},
	}}
	res := decode[ListenIngestResult](t, h.postJSON(t, "/api/v1/listens", report))
	if res.Accepted != 1 || res.Duplicates != 0 || res.Rejected == nil || len(*res.Rejected) != 2 {
		t.Fatalf("first ingest = %+v", res)
	}

	// Replaying the same batch is acknowledged without double-counting.
	res = decode[ListenIngestResult](t, h.postJSON(t, "/api/v1/listens", report))
	if res.Accepted != 0 || res.Duplicates != 1 {
		t.Fatalf("replay ingest = %+v", res)
	}

	// Exactly one play landed on the item.
	st = decode[PlayState](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-state", h.token))
	if !st.Played || st.PlayCount != 1 {
		t.Fatalf("post-listen state = %+v, want played once", st)
	}
}

func (h *harness) putJSON(t *testing.T, path string, body any) *http.Response {
	t.Helper()
	raw, _ := json.Marshal(body)
	req, _ := http.NewRequest("PUT", h.ts.URL+path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

// putJSON sends an authenticated PUT with a JSON body.
func putJSON(t *testing.T, ts *httptest.Server, path, token string, body any) *http.Response {
	t.Helper()
	raw, _ := json.Marshal(body)
	req, _ := http.NewRequest("PUT", ts.URL+path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

// TestTwoUsersIsolatedState is the multi-user acceptance at the API
// level: two accounts share the catalog but never each other's
// playback state, stars, or ratings.
func TestTwoUsersIsolatedState(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	// A second, non-admin account.
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "sam", "password": testPassword,
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)

	page := h.items(t, "")
	if len(page.Items) < 2 {
		t.Fatalf("want at least 2 items, got %d", len(page.Items))
	}
	first, second := page.Items[0].Pid, page.Items[1].Pid

	// Sam sees the whole shared catalog.
	resp = get(t, h.ts, "/api/v1/library/items", sam.Token)
	if p := decode[ItemPage](t, resp); len(p.Items) != len(page.Items) {
		t.Fatalf("sam sees %d items, admin sees %d", len(p.Items), len(page.Items))
	}

	// Admin stars, rates, and checkpoints the first item.
	if resp := putJSON(t, h.ts, "/api/v1/items/"+first+"/star", h.token, map[string]any{"starred": true}); resp.StatusCode != 200 {
		t.Fatalf("admin star status = %d", resp.StatusCode)
	} else {
		st := decode[PlayState](t, resp)
		if !st.Starred {
			t.Fatal("admin star did not stick")
		}
	}
	if resp := putJSON(t, h.ts, "/api/v1/items/"+first+"/rating", h.token, map[string]any{"rating": 80}); resp.StatusCode != 200 {
		t.Fatalf("admin rating status = %d", resp.StatusCode)
	} else {
		st := decode[PlayState](t, resp)
		if st.Rating == nil || *st.Rating != 80 {
			t.Fatalf("admin rating = %v, want 80", st.Rating)
		}
	}
	if resp := putJSON(t, h.ts, "/api/v1/items/"+first+"/play-state", h.token, map[string]any{"positionMs": 4200}); resp.StatusCode != 204 {
		t.Fatalf("admin checkpoint status = %d", resp.StatusCode)
	} else {
		resp.Body.Close()
	}

	// Sam's view of the same item is untouched.
	resp = get(t, h.ts, "/api/v1/items/"+first+"/play-state", sam.Token)
	samState := decode[PlayState](t, resp)
	if samState.Starred || samState.Rating != nil || samState.PositionMs != 0 {
		t.Fatalf("sam's state leaked admin's: %+v", samState)
	}

	// Sam stars the second item; the starred lists diverge.
	if resp := putJSON(t, h.ts, "/api/v1/items/"+second+"/star", sam.Token, map[string]any{"starred": true}); resp.StatusCode != 200 {
		t.Fatalf("sam star status = %d", resp.StatusCode)
	} else {
		resp.Body.Close()
	}
	adminStarred := decode[ItemPage](t, get(t, h.ts, "/api/v1/library/browse?list=starred", h.token))
	samStarred := decode[ItemPage](t, get(t, h.ts, "/api/v1/library/browse?list=starred", sam.Token))
	if len(adminStarred.Items) != 1 || adminStarred.Items[0].Pid != first {
		t.Fatalf("admin starred list = %+v, want just %s", adminStarred.Items, first)
	}
	if len(samStarred.Items) != 1 || samStarred.Items[0].Pid != second {
		t.Fatalf("sam starred list = %+v, want just %s", samStarred.Items, second)
	}

	// Clearing a rating with null works and stays per-user.
	if resp := putJSON(t, h.ts, "/api/v1/items/"+first+"/rating", h.token, map[string]any{"rating": nil}); resp.StatusCode != 200 {
		t.Fatalf("clear rating status = %d", resp.StatusCode)
	} else {
		st := decode[PlayState](t, resp)
		if st.Rating != nil {
			t.Fatalf("cleared rating = %v, want nil", st.Rating)
		}
	}

	// Listens account per user: the same session id from both users is
	// two distinct sessions, not a dedupe collision.
	sid := "01JZTESTISOLATIONSESSION01"
	for _, tok := range []string{h.token, sam.Token} {
		resp := postListens(t, h.ts, tok, sid, first)
		res := decode[ListenIngestResult](t, resp)
		if res.Accepted != 1 || res.Duplicates != 0 {
			t.Fatalf("listen ingest = %+v, want accepted 1", res)
		}
	}
	// A replay by the same user does dedupe.
	resp = postListens(t, h.ts, sam.Token, sid, first)
	if res := decode[ListenIngestResult](t, resp); res.Duplicates != 1 || res.Accepted != 0 {
		t.Fatalf("replay ingest = %+v, want duplicate 1", res)
	}
}

// postListens reports one finished listen session.
func postListens(t *testing.T, ts *httptest.Server, token, sessionID, pid string) *http.Response {
	t.Helper()
	body := map[string]any{"sessions": []map[string]any{{
		"sessionId": sessionID,
		"pid":       pid,
		"startedAt": time.Now().UTC().Format(time.RFC3339),
		"msPlayed":  300000,
		"finished":  true,
	}}}
	raw, _ := json.Marshal(body)
	req, _ := http.NewRequest("POST", ts.URL+"/api/v1/listens", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("listens status = %d", resp.StatusCode)
	}
	return resp
}
