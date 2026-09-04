package api

import (
	"context"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/cast/castv2/testreceiver"
	"github.com/colespringer/waxdeck/server/internal/cast/dlna"
	"github.com/colespringer/waxdeck/server/internal/cast/dlna/testrenderer"
)

// TestConnectCastSession drives the kitchen-speaker acceptance path
// against a wire-honest fake Chromecast: discovery announce, a queue
// cast over REST, verbs over the command bus, and the mid-track
// handoff phone to speaker to phone that keeps the position.
func TestConnectCastSession(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	items := h.items(t, "")
	pidA := items.Items[0].Pid
	pidB := items.Items[1].Pid
	ctx := context.Background()

	recv := testreceiver.Start(t)
	dev := recv.Device()
	ep, err := h.connect.EndpointOnline(ctx, "cast", dev.Key(), "Kitchen speaker", recv.Addr(), true, false,
		dev.Dial(h.group, nil))
	if err != nil {
		t.Fatal(err)
	}

	// The shared device endpoint lists for every user.
	var eps struct {
		Endpoints []struct {
			Id, Kind, Name string
			Shared, Online bool
		}
	}
	pGet(t, h, "/api/v1/player/endpoints", h.token, &eps)
	found := false
	for _, e := range eps.Endpoints {
		if e.Id == ep.ID {
			found = true
			if e.Kind != "cast" || !e.Shared || !e.Online {
				t.Fatalf("cast endpoint shape %+v", e)
			}
		}
	}
	if !found {
		t.Fatalf("cast endpoint missing from %+v", eps.Endpoints)
	}

	// Cast a two-item queue. The harness engine mints timelines, so
	// the receiver gets ONE gapless HLS load covering the whole queue.
	var sess struct {
		Id, EndpointId, Authority string
		Playing                   bool
		Entries                   []struct{ Pid string }
	}
	pPost(t, h, "/api/v1/player/sessions", h.token, map[string]any{
		"endpointId": ep.ID,
		"itemPids":   []string{pidA, pidB},
	}, http.StatusCreated, &sess)
	if sess.Authority != "remote" || len(sess.Entries) != 2 {
		t.Fatalf("cast session %+v", sess)
	}
	loaded := recv.LoadedItems()
	if len(loaded) != 1 {
		t.Fatalf("expected one gapless timeline load, receiver got %d items", len(loaded))
	}
	if loaded[0].ContentType != "application/vnd.apple.mpegurl" ||
		!strings.Contains(loaded[0].ContentID, "/media/hls/master.m3u8?tl=") {
		t.Fatalf("timeline load %+v", loaded[0])
	}
	if !strings.HasPrefix(loaded[0].ContentID, h.lanBase) {
		t.Fatalf("load URL not on the advertise base: %s", loaded[0].ContentID)
	}

	// Verbs relay from a controller client to the device.
	controller := dialWS(t, h, h.token)
	controller.send(map[string]any{"type": "cmd", "id": "c1", "sessionId": sess.Id, "verb": "pause"})
	controller.expect("ack")
	waitFor2(t, func() bool { return recv.PlayerState() == "PAUSED" })

	controller.send(map[string]any{"type": "cmd", "id": "c2", "sessionId": sess.Id, "verb": "set-volume", "volume": 0.3})
	controller.expect("ack")
	waitFor2(t, func() bool { return recv.VolumeLevel() > 0.29 && recv.VolumeLevel() < 0.31 })

	controller.send(map[string]any{"type": "cmd", "id": "c3", "sessionId": sess.Id, "verb": "play"})
	controller.expect("ack")
	waitFor2(t, func() bool { return recv.PlayerState() == "PLAYING" })

	// Handoff back to a phone: register a client endpoint and transfer
	// the cast session onto it; the phone gets the queue and position.
	phoneToken := loginAs(t, h.ts, "admin", testPassword).Token
	phone := dialWS(t, h, phoneToken)
	phoneEndpoint := phone.register("Phone")
	st := newEndpointState()
	phone.pumpEndpoint(t, st)

	recv.Advance(1)
	var moved struct {
		Id, EndpointId, Authority string
	}
	pPost(t, h, "/api/v1/player/sessions/"+sess.Id+"/transfer", h.token,
		map[string]any{"endpointId": phoneEndpoint}, http.StatusOK, &moved)
	if moved.Id != sess.Id || moved.EndpointId != phoneEndpoint || moved.Authority != "mirror" {
		t.Fatalf("handoff result %+v", moved)
	}
	st.mu(func() {
		if st.loads != 1 || len(st.pids) != 2 {
			t.Fatalf("phone load %+v", st)
		}
	})

	// And back to the speaker: the same session id returns to the
	// device with a fresh load.
	pPost(t, h, "/api/v1/player/sessions/"+sess.Id+"/transfer", phoneToken,
		map[string]any{"endpointId": ep.ID}, http.StatusOK, &moved)
	if moved.EndpointId != ep.ID || moved.Authority != "remote" {
		t.Fatalf("return handoff %+v", moved)
	}
	waitFor2(t, func() bool { return len(recv.Loads()) >= 2 })
}

// TestConnectCastBookQueue is a queue that mixes a multi-file
// audiobook with a track. A book cannot ride a gapless timeline - the
// boundary table places one member per entry - so the whole queue
// loads per item instead, and the book contributes one item per part.
// The music in the queue loses its seamless render until the book
// leaves, which is what the casting doc says happens.
func TestConnectCastBookQueue(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook")
	if len(books.Items) != 1 {
		t.Fatalf("audiobooks = %d, want the fixture's one", len(books.Items))
	}
	book := books.Items[0].Pid
	track := h.items(t, "?mediaType=music").Items[0].Pid

	recv := testreceiver.Start(t)
	dev := recv.Device()
	ep, err := h.connect.EndpointOnline(ctx, "cast", dev.Key(), "Kitchen speaker", recv.Addr(), true, false,
		dev.Dial(h.group, nil))
	if err != nil {
		t.Fatal(err)
	}

	var sess struct {
		Id      string
		Entries []struct{ Pid string }
	}
	pPost(t, h, "/api/v1/player/sessions", h.token, map[string]any{
		"endpointId": ep.ID,
		"itemPids":   []string{book, track},
	}, http.StatusCreated, &sess)
	if len(sess.Entries) != 2 {
		t.Fatalf("queue entries %+v, want the book and the track", sess.Entries)
	}
	loaded := recv.LoadedItems()
	if len(loaded) != 4 {
		t.Fatalf("receiver got %d items, want three book parts and the track", len(loaded))
	}
	for _, it := range loaded {
		if strings.Contains(it.ContentID, "/media/hls/master.m3u8?tl=") {
			t.Fatalf("a queue holding a book still minted a timeline: %s", it.ContentID)
		}
	}

	// Seven seconds into the book is part two (the fixture's parts run
	// 4s, 5s, 6s), which is a different file: the receiver reloads at
	// that item rather than seeking inside the one it has.
	controller := dialWS(t, h, h.token)
	controller.send(map[string]any{"type": "cmd", "id": "b1", "sessionId": sess.Id, "verb": "seek", "positionMs": 7000})
	controller.expect("ack")
	waitFor2(t, func() bool { return len(recv.Loads()) >= 2 })
	last := recv.Loads()[len(recv.Loads())-1]
	if last.StartIndex != 1 || last.CurrentTimeSeconds < 2.5 || last.CurrentTimeSeconds > 3.5 {
		t.Fatalf("seek to 7s of the book reloaded at item %d/%.1fs, want part two at 3s", last.StartIndex, last.CurrentTimeSeconds)
	}
}

func waitFor2(t *testing.T, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("condition never held")
}

// castProbe is a device probe over REST, decoded.
type castProbe struct {
	EndpointId, Name, Kind string
	Bases                  []struct {
		Base, Source string
		Reachable    bool
		Notes        []string
		Device       *struct {
			Verdict, Detail string
			LatencyMs       int64
		}
	}
}

// TestCastDeviceProbePlays is the device half of the connection check
// against a device that works: the receiver fetches the probe from the
// advertise base and reports playing, and the answer carries that
// beside the server's own reachability row for the same address.
func TestCastDeviceProbePlays(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()
	recv := testreceiver.Start(t)
	// A verdict is built on the request reaching this server, so the
	// fake has to make it: what a receiver says about itself is not
	// evidence it fetched anything.
	recv.FetchMedia()
	dev := recv.Device()
	ep, err := h.connect.EndpointOnline(ctx, "cast", dev.Key(), "Kitchen speaker", recv.Addr(), true, false,
		dev.Dial(h.group, nil))
	if err != nil {
		t.Fatal(err)
	}

	var probe castProbe
	pPost(t, h, "/api/v1/player/cast/preflight/"+ep.ID, h.token, nil, http.StatusOK, &probe)
	if probe.EndpointId != ep.ID || probe.Kind != "cast" || probe.Name != "Kitchen speaker" {
		t.Fatalf("probe names %+v", probe)
	}
	if len(probe.Bases) != 1 {
		t.Fatalf("bases = %+v, want the one the harness advertises", probe.Bases)
	}
	row := probe.Bases[0]
	if row.Base != h.lanBase || row.Source != "detected" {
		t.Fatalf("base row %+v", row)
	}
	if len(row.Notes) == 0 {
		t.Fatal("the server-side half of the row lost its notes")
	}
	if row.Device == nil || row.Device.Verdict != "played" {
		t.Fatalf("device verdict %+v, want played", row.Device)
	}

	// What the device was handed is the probe stream, and it is fetched
	// from the base being tested.
	loaded := recv.LoadedItems()
	if len(loaded) != 1 || !strings.HasPrefix(loaded[0].ContentID, h.lanBase+"/media/probe.wav?mt=") {
		t.Fatalf("probe load %+v", loaded)
	}
	if loaded[0].ContentType != "audio/wav" {
		t.Fatalf("probe content type %q", loaded[0].ContentType)
	}
	// And it is left silent: a connection check that leaves a second of
	// nothing looping is not one anybody runs twice.
	waitFor2(t, func() bool { return recv.PlayerState() != "PLAYING" })
}

// TestCastDeviceProbeReportsRefusal is the failure this exists to
// catch: the device took the URL and could not play it, and what it
// said travels back rather than a bare "no".
func TestCastDeviceProbeReportsRefusal(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()
	recv := testreceiver.Start(t)
	dev := recv.Device()
	ep, err := h.connect.EndpointOnline(ctx, "cast", dev.Key(), "Kitchen speaker", recv.Addr(), true, false,
		dev.Dial(h.group, nil))
	if err != nil {
		t.Fatal(err)
	}
	recv.FailNextLoad("MEDIA_UNKNOWN")

	var probe castProbe
	pPost(t, h, "/api/v1/player/cast/preflight/"+ep.ID, h.token, nil, http.StatusOK, &probe)
	if len(probe.Bases) != 1 || probe.Bases[0].Device == nil {
		t.Fatalf("probe %+v", probe)
	}
	got := probe.Bases[0].Device
	if got.Verdict != "failed" {
		t.Fatalf("verdict %q, want failed", got.Verdict)
	}
	if !strings.Contains(got.Detail, "MEDIA_UNKNOWN") {
		t.Fatalf("detail %q, want the device's own reason in it", got.Detail)
	}
}

// TestCastDeviceProbeRefusesForeignApp: loading media takes a
// Chromecast over, so a probe asks what is running first. Nobody's film
// is interrupted by a connection check.
func TestCastDeviceProbeRefusesForeignApp(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()
	recv := testreceiver.Start(t)
	dev := recv.Device()
	ep, err := h.connect.EndpointOnline(ctx, "cast", dev.Key(), "Kitchen speaker", recv.Addr(), true, false,
		dev.Dial(h.group, nil))
	if err != nil {
		t.Fatal(err)
	}
	recv.RunForeignApp("233637DE", "YouTube")

	var body Error
	pPost(t, h, "/api/v1/player/cast/preflight/"+ep.ID, h.token, nil, http.StatusConflict, &body)
	if body.Code != "endpoint-busy" {
		t.Fatalf("code %q, want endpoint-busy", body.Code)
	}
	if !strings.Contains(body.Message, "YouTube") {
		t.Fatalf("message %q, want the app the device named", body.Message)
	}
	if len(recv.LoadedItems()) != 0 {
		t.Fatal("the probe loaded media over a running app")
	}
}

// TestRendererProbeRefusesAndFaults covers the DLNA half: a renderer
// already playing is busy, and one that refuses the URL says so with
// the fault it answered.
func TestRendererProbeRefusesAndFaults(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()
	rend := testrenderer.Start(t)
	rend.FetchMedia()
	ep, err := h.connect.EndpointOnline(ctx, "dlna", "udn-1", "Living room", rend.Location(), true, false,
		dlna.Device{Location: rend.Location()}.Dial(h.group, nil))
	if err != nil {
		t.Fatal(err)
	}

	rend.ForceState("PLAYING")
	var body Error
	pPost(t, h, "/api/v1/player/cast/preflight/"+ep.ID, h.token, nil, http.StatusConflict, &body)
	if body.Code != "endpoint-busy" {
		t.Fatalf("code %q, want endpoint-busy for a renderer already playing", body.Code)
	}

	rend.ForceState("STOPPED")
	rend.FaultNextSetURI(714, "Illegal MIME-type")
	var probe castProbe
	pPost(t, h, "/api/v1/player/cast/preflight/"+ep.ID, h.token, nil, http.StatusOK, &probe)
	if len(probe.Bases) != 1 {
		t.Fatalf("bases %+v, want the one address the harness advertises", probe.Bases)
	}
	got := probe.Bases[0].Device
	if got == nil || got.Verdict != "failed" || !strings.Contains(got.Detail, "714") {
		t.Fatalf("verdict %+v, want the renderer's own fault", got)
	}

	// Cleared, the same renderer reaches the server through that
	// address and the verdict says so.
	var again castProbe
	pPost(t, h, "/api/v1/player/cast/preflight/"+ep.ID, h.token, nil, http.StatusOK, &again)
	if len(again.Bases) != 1 || again.Bases[0].Device == nil || again.Bases[0].Device.Verdict != "played" {
		t.Fatalf("second run %+v, want played", again.Bases)
	}
}

// TestCastDeviceProbeNeedsTheFetch is the whole verdict in one case: a
// device that says it is playing without ever having fetched the
// address must not pass it. A cast receiver reports BUFFERING while it
// is still resolving a name it will never resolve, so what the device
// says about itself is not evidence it reached this server - and a
// base that can never work would otherwise pass in a couple of hundred
// milliseconds, which is exactly the failure this check exists to
// catch.
func TestCastDeviceProbeNeedsTheFetch(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()
	// Deliberately not FetchMedia: the receiver reports PLAYING off the
	// load, the way one does before it has opened anything.
	recv := testreceiver.Start(t)
	dev := recv.Device()
	ep, err := h.connect.EndpointOnline(ctx, "cast", dev.Key(), "Kitchen speaker", recv.Addr(), true, false,
		dev.Dial(h.group, nil))
	if err != nil {
		t.Fatal(err)
	}

	var probe castProbe
	pPost(t, h, "/api/v1/player/cast/preflight/"+ep.ID, h.token, nil, http.StatusOK, &probe)
	if len(probe.Bases) != 1 || probe.Bases[0].Device == nil {
		t.Fatalf("probe %+v", probe)
	}
	got := probe.Bases[0].Device
	if got.Verdict == "played" {
		t.Fatalf("a device that never fetched the address passed it: %+v", got)
	}
	if !strings.Contains(got.Detail, "fetch") {
		t.Fatalf("detail %q, want it to say the address was never fetched", got.Detail)
	}
}

// TestCastDeviceProbeIgnoresTheIdleScreen: a Chromecast with nothing
// casting runs its ambient app, which is an application in the status
// like any other. Reading that as busy makes the check unusable on
// every idle device there is.
func TestCastDeviceProbeIgnoresTheIdleScreen(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()
	recv := testreceiver.Start(t)
	recv.FetchMedia()
	recv.RunIdleScreen()
	dev := recv.Device()
	ep, err := h.connect.EndpointOnline(ctx, "cast", dev.Key(), "Kitchen speaker", recv.Addr(), true, false,
		dev.Dial(h.group, nil))
	if err != nil {
		t.Fatal(err)
	}

	var probe castProbe
	pPost(t, h, "/api/v1/player/cast/preflight/"+ep.ID, h.token, nil, http.StatusOK, &probe)
	if len(probe.Bases) != 1 || probe.Bases[0].Device == nil || probe.Bases[0].Device.Verdict != "played" {
		t.Fatalf("an idle device refused the check: %+v", probe.Bases)
	}
}

// TestProbeAudioIsTokenBound covers the stream a device probe hands
// out: real WAV, and reachable only with the token the probe minted -
// an unauthenticated LAN peer must not find a free second of audio to
// fetch in a loop.
func TestProbeAudioIsTokenBound(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	resp, err := http.Get(h.ts.URL + "/media/probe.wav")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("untokenized probe fetch status %d, want 401", resp.StatusCode)
	}

	token, _ := h.media.MintFor(adminUserID(t, h), probePID, time.Minute)
	resp, err = http.Get(h.ts.URL + mediaProbeURL(token, "0"))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("probe fetch status %d", resp.StatusCode)
	}
	if got := resp.Header.Get("Content-Type"); got != "audio/wav" {
		t.Fatalf("content type %q", got)
	}
	if got := resp.Header.Get("Cache-Control"); got != "no-store" {
		t.Fatalf("cache-control %q", got)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	// A RIFF/WAVE header and exactly a second of 44.1 kHz 16-bit mono.
	if len(body) != 44+44100*2 {
		t.Fatalf("probe is %d bytes, want a second of 44.1 kHz 16-bit mono plus its header", len(body))
	}
	if string(body[:4]) != "RIFF" || string(body[8:12]) != "WAVE" {
		t.Fatalf("probe is not a WAV: % x", body[:12])
	}

	// A token minted for an item does not open it, and this one does
	// not open an item.
	items := h.items(t, "")
	itemToken, _ := h.media.MintFor(adminUserID(t, h), items.Items[0].Pid, time.Minute)
	resp, err = http.Get(h.ts.URL + mediaProbeURL(itemToken, "0"))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("an item's token opened the probe: status %d", resp.StatusCode)
	}
}
