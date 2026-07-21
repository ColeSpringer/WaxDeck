package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

// wsClient is a test-side command-bus client: one socket, a reader
// pump, and typed expectations.
type wsClient struct {
	t    *testing.T
	conn *websocket.Conn
	recv chan map[string]any
}

func dialWS(t *testing.T, h *harness, token string, topics ...string) *wsClient {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	t.Cleanup(cancel)
	wsURL := "ws" + strings.TrimPrefix(h.ts.URL, "http") + "/api/v1/ws"
	conn, _, err := websocket.Dial(ctx, wsURL, &websocket.DialOptions{
		HTTPHeader: http.Header{"Authorization": []string{"Bearer " + token}},
	})
	if err != nil {
		t.Fatalf("dialing ws: %v", err)
	}
	sub := map[string]any{}
	if len(topics) > 0 {
		sub["topics"] = topics
	}
	data, _ := json.Marshal(sub)
	if err := conn.Write(ctx, websocket.MessageText, data); err != nil {
		t.Fatalf("subscribing: %v", err)
	}
	c := &wsClient{t: t, conn: conn, recv: make(chan map[string]any, 64)}
	go func() {
		for {
			_, msg, err := conn.Read(context.Background())
			if err != nil {
				close(c.recv)
				return
			}
			var frame map[string]any
			if json.Unmarshal(msg, &frame) == nil {
				c.recv <- frame
			}
		}
	}()
	t.Cleanup(func() { conn.Close(websocket.StatusNormalClosure, "") })
	return c
}

func (c *wsClient) send(v map[string]any) {
	c.t.Helper()
	data, _ := json.Marshal(v)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := c.conn.Write(ctx, websocket.MessageText, data); err != nil {
		c.t.Fatalf("ws write: %v", err)
	}
}

// expect waits for the next frame of the given type, discarding
// others (invalidations interleave freely).
func (c *wsClient) expect(frameType string) map[string]any {
	c.t.Helper()
	deadline := time.After(10 * time.Second)
	for {
		select {
		case f, ok := <-c.recv:
			if !ok {
				c.t.Fatalf("socket closed waiting for %s", frameType)
			}
			if f["type"] == frameType {
				return f
			}
		case <-deadline:
			c.t.Fatalf("no %s frame arrived", frameType)
		}
	}
}

// register declares the connection a controllable endpoint and returns
// its endpoint id.
func (c *wsClient) register(name string) string {
	c.t.Helper()
	c.send(map[string]any{"type": "register-endpoint", "id": "r1", "name": name, "volumeControl": true, "rateControl": true})
	ack := c.expect("ack")
	id, _ := ack["endpointId"].(string)
	if id == "" {
		c.t.Fatalf("registration ack without endpointId: %v", ack)
	}
	return id
}

// pump answers routed endpoint commands like a real player client:
// acks every command and reports the implied state.
func (c *wsClient) pumpEndpoint(t *testing.T, state *endpointState) {
	t.Helper()
	go func() {
		for f := range c.recv {
			if f["type"] != "endpoint-cmd" {
				continue
			}
			id, _ := f["id"].(string)
			verb, _ := f["verb"].(string)
			state.mu(func() {
				switch verb {
				case "load":
					state.pids = stringSlice(f["itemPids"])
					state.index = intField(f, "index")
					state.positionMS = int64Field(f, "positionMs")
					state.playing = boolField(f, "play")
					state.loads++
				case "play":
					state.playing = true
				case "pause", "stop":
					state.playing = false
				case "seek":
					state.positionMS = int64Field(f, "positionMs")
				case "set-volume":
					state.volume = floatField(f, "volume")
				case "set-rate":
					state.rate = floatField(f, "rate")
				}
			})
			c.send(map[string]any{"type": "cmd-result", "id": id, "ok": true})
			// The report is what updates the mirror.
			rep := map[string]any{
				"type": "session-report", "playing": state.playing,
				"positionMs": state.positionMS, "index": state.index,
			}
			if verb == "load" {
				rep["itemPids"] = state.pids
				rep["queueVersion"] = 1
			}
			c.send(rep)
		}
	}()
}

type endpointState struct {
	lock       chan struct{}
	pids       []string
	index      int
	positionMS int64
	playing    bool
	volume     float64
	rate       float64
	loads      int
}

func newEndpointState() *endpointState {
	s := &endpointState{lock: make(chan struct{}, 1)}
	s.lock <- struct{}{}
	return s
}

func (s *endpointState) mu(fn func()) {
	<-s.lock
	fn()
	s.lock <- struct{}{}
}

func stringSlice(v any) []string {
	arr, _ := v.([]any)
	out := make([]string, 0, len(arr))
	for _, e := range arr {
		if s, ok := e.(string); ok {
			out = append(out, s)
		}
	}
	return out
}

func intField(f map[string]any, k string) int {
	n, _ := f[k].(float64)
	return int(n)
}

func int64Field(f map[string]any, k string) int64 {
	n, _ := f[k].(float64)
	return int64(n)
}

func floatField(f map[string]any, k string) float64 {
	n, _ := f[k].(float64)
	return n
}

func boolField(f map[string]any, k string) bool {
	b, _ := f[k].(bool)
	return b
}

// TestConnectPlayOnClientEndpointAndRelay is the heart of the slice: a
// controller starts playback on another signed-in client, then relays
// seek and volume to it over the command bus.
func TestConnectPlayOnClientEndpointAndRelay(t *testing.T) {
	h := newHarness(t)
	items := h.items(t, "")
	pidA := items.Items[0].Pid
	pidB := items.Items[1].Pid

	// Two device sessions for the same account: the player client and
	// the controller.
	playerToken := loginAs(t, h.ts, "admin", testPassword).Token
	controllerToken := loginAs(t, h.ts, "admin", testPassword).Token

	player := dialWS(t, h, playerToken)
	endpointID := player.register("Kitchen laptop")
	st := newEndpointState()
	player.pumpEndpoint(t, st)

	controller := dialWS(t, h, controllerToken)

	// The endpoint lists for its owner.
	var eps struct {
		Endpoints []struct {
			Id, Kind, Name string
			Online, Mine   bool
		}
	}
	pGet(t, h, "/api/v1/player/endpoints", controllerToken, &eps)
	found := false
	for _, ep := range eps.Endpoints {
		if ep.Id == endpointID {
			found = true
			if ep.Kind != "client" || !ep.Mine || !ep.Online {
				t.Fatalf("endpoint shape %+v", ep)
			}
		}
	}
	if !found {
		t.Fatalf("registered endpoint missing from %+v", eps)
	}

	// Play on it.
	var sess struct {
		Id, EndpointId, Authority string
		Playing                   bool
		Entries                   []struct{ Pid, Title string }
	}
	pPost(t, h, "/api/v1/player/sessions", controllerToken, map[string]any{
		"endpointId": endpointID,
		"itemPids":   []string{pidA, pidB},
	}, http.StatusCreated, &sess)
	if sess.EndpointId != endpointID || len(sess.Entries) != 2 {
		t.Fatalf("session %+v", sess)
	}
	st.mu(func() {
		if st.loads != 1 || len(st.pids) != 2 || st.pids[0] != pidA {
			t.Fatalf("player load state %+v", st)
		}
	})

	// Watch the session from the controller and relay a seek.
	controller.send(map[string]any{"type": "watch", "sessionId": sess.Id})
	controller.expect("session")

	controller.send(map[string]any{"type": "cmd", "id": "c1", "sessionId": sess.Id, "verb": "seek", "positionMs": 42000})
	controller.expect("ack")
	st.mu(func() {
		if st.positionMS != 42000 {
			t.Fatalf("seek did not reach the player: %d", st.positionMS)
		}
	})

	controller.send(map[string]any{"type": "cmd", "id": "c2", "sessionId": sess.Id, "verb": "set-volume", "volume": 0.4})
	controller.expect("ack")
	st.mu(func() {
		if st.volume != 0.4 {
			t.Fatalf("volume did not reach the player: %f", st.volume)
		}
	})

	// The player's own reports flow back to the watcher. A paused
	// report carries its exact position (no extrapolation, no
	// clamping), so the value round-trips verbatim.
	player.send(map[string]any{"type": "session-report", "playing": false, "positionMs": 1750, "index": 0})
	deadline := time.After(10 * time.Second)
	for {
		var f map[string]any
		select {
		case f = <-controller.recv:
		case <-deadline:
			t.Fatal("watcher never saw the report")
		}
		if f["type"] != "session" {
			continue
		}
		session, _ := f["session"].(map[string]any)
		if !boolField(session, "playing") && int64Field(session, "positionMs") == 1750 {
			return
		}
	}
}

// TestConnectClockSync pins the ping/pong shape.
func TestConnectClockSync(t *testing.T) {
	h := newHarness(t)
	c := dialWS(t, h, h.token)
	c.send(map[string]any{"type": "ping", "t": 12345})
	pong := c.expect("pong")
	if int64Field(pong, "t") != 12345 {
		t.Fatalf("pong echo %v", pong)
	}
	if int64Field(pong, "at") == 0 {
		t.Fatalf("pong carries no server clock: %v", pong)
	}
}

// TestConnectMirrorAndPlayerTopic drives the mirror-session path: a
// playing client reports, the session lists, and lifecycle rides the
// player topic.
func TestConnectMirrorAndPlayerTopic(t *testing.T) {
	h := newHarness(t)
	items := h.items(t, "")
	pid := items.Items[0].Pid

	playerToken := loginAs(t, h.ts, "admin", testPassword).Token
	watcherToken := loginAs(t, h.ts, "admin", testPassword).Token

	// The watcher subscribes to the player topic only.
	watcher := dialWS(t, h, watcherToken, "player")

	player := dialWS(t, h, playerToken)
	player.register("Phone")
	player.send(map[string]any{
		"type": "session-report", "playing": true, "positionMs": 5000, "index": 0,
		"itemPids": []string{pid}, "queueVersion": 1,
	})
	created := player.expect("session")
	session, _ := created["session"].(map[string]any)
	sessID, _ := session["id"].(string)
	if sessID == "" || session["authority"] != "mirror" {
		t.Fatalf("mirror session frame %v", created)
	}

	// Registration and session creation invalidate the player topic.
	inv := watcher.expect("invalidate")
	if inv["topic"] != "player" {
		t.Fatalf("invalidate topic %v", inv)
	}

	// The session lists over REST with hydrated entries.
	var sessions struct {
		Sessions []struct {
			Id      string
			Entries []struct{ Title string }
		}
	}
	pGet(t, h, "/api/v1/player/sessions", playerToken, &sessions)
	if len(sessions.Sessions) != 1 || sessions.Sessions[0].Id != sessID {
		t.Fatalf("sessions %+v", sessions)
	}
	if len(sessions.Sessions[0].Entries) != 1 || sessions.Sessions[0].Entries[0].Title == "" {
		t.Fatalf("entries not hydrated: %+v", sessions.Sessions[0])
	}

	// Ending over REST tears playback down.
	req, _ := http.NewRequest(http.MethodDelete, h.ts.URL+"/api/v1/player/sessions/"+sessID, nil)
	req.Header.Set("Authorization", "Bearer "+playerToken)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("delete status %d", resp.StatusCode)
	}
	pGet(t, h, "/api/v1/player/sessions", playerToken, &sessions)
	if len(sessions.Sessions) != 0 {
		t.Fatalf("session survived delete: %+v", sessions)
	}
}

// TestConnectTransferBetweenClients moves live playback between two
// player clients and keeps the position.
func TestConnectTransferBetweenClients(t *testing.T) {
	h := newHarness(t)
	items := h.items(t, "")
	pid := items.Items[0].Pid

	tokenA := loginAs(t, h.ts, "admin", testPassword).Token
	tokenB := loginAs(t, h.ts, "admin", testPassword).Token
	controllerToken := loginAs(t, h.ts, "admin", testPassword).Token

	clientA := dialWS(t, h, tokenA)
	clientA.register("Phone")

	clientB := dialWS(t, h, tokenB)
	endpointB := clientB.register("Desktop")
	stB := newEndpointState()
	clientB.pumpEndpoint(t, stB)

	// A plays locally and reports; the answer frame carries the
	// assigned session id. The stop pump starts only after that, so
	// the expectation and the pump never race for the frame.
	// The fixture tracks are a few seconds long, so the reported
	// position stays inside the entry (snapshots clamp to duration).
	clientA.send(map[string]any{
		"type": "session-report", "playing": false, "positionMs": 1000, "index": 0,
		"itemPids": []string{pid}, "queueVersion": 1,
	})
	created := clientA.expect("session")
	session, _ := created["session"].(map[string]any)
	sessID, _ := session["id"].(string)
	stA := newEndpointState()
	clientA.pumpEndpoint(t, stA)

	// The controller moves it to B.
	var moved struct {
		Id, EndpointId string
		PositionMs     int64
	}
	pPost(t, h, "/api/v1/player/sessions/"+sessID+"/transfer", controllerToken,
		map[string]any{"endpointId": endpointB}, http.StatusOK, &moved)
	if moved.Id != sessID || moved.EndpointId != endpointB {
		t.Fatalf("transfer result %+v", moved)
	}
	if moved.PositionMs < 1000 {
		t.Fatalf("position lost: %d", moved.PositionMs)
	}
	stB.mu(func() {
		if stB.loads != 1 || stB.positionMS < 1000 || len(stB.pids) != 1 {
			t.Fatalf("target load %+v", stB)
		}
	})
}

// TestQueueTimelineEndpoint mints a gapless timeline over the REST
// surface and plays the playlist chain through the proxied HLS tree.
func TestQueueTimelineEndpoint(t *testing.T) {
	h := newHarness(t)
	items := h.items(t, "")
	pidA := items.Items[0].Pid
	pidB := items.Items[1].Pid

	var tl struct {
		Url, MimeType string
		DurationMs    int64
		EnvelopeRate  int
		Boundaries    []struct {
			Pid           string
			OffsetSamples int64
		}
	}
	pPost(t, h, "/api/v1/player/timeline", h.token, map[string]any{
		"itemPids": []string{pidA, pidB},
	}, http.StatusCreated, &tl)
	if tl.MimeType != "application/vnd.apple.mpegurl" || tl.EnvelopeRate != 44100 {
		t.Fatalf("timeline %+v", tl)
	}
	if len(tl.Boundaries) != 2 || tl.Boundaries[0].Pid != pidA || tl.Boundaries[1].OffsetSamples == 0 {
		t.Fatalf("boundaries %+v", tl.Boundaries)
	}

	// The minted URL serves the master playlist with stamped children.
	resp, err := http.Get(h.ts.URL + tl.Url)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("master status %d", resp.StatusCode)
	}
	buf := make([]byte, 4096)
	n, _ := resp.Body.Read(buf)
	body := string(buf[:n])
	if !strings.Contains(body, "media.m3u8") || !strings.Contains(body, "mt=") {
		t.Fatalf("master body %q", body)
	}
}

// TestCastPreflight answers candidates with plain-language notes.
func TestCastPreflight(t *testing.T) {
	h := newHarness(t)
	var out struct {
		Bases []struct {
			Base, Source string
			Reachable    bool
			Notes        []string
		}
	}
	pGet(t, h, "/api/v1/player/cast/preflight", h.token, &out)
	if len(out.Bases) != 1 {
		t.Fatalf("bases %+v", out.Bases)
	}
	b := out.Bases[0]
	if b.Source != "detected" || b.Reachable {
		// The harness LAN base is a documentation address; unreachable
		// is the honest verdict, with notes saying why.
		if b.Reachable {
			t.Fatalf("documentation address reachable: %+v", b)
		}
	}
	if len(b.Notes) == 0 {
		t.Fatalf("no notes: %+v", b)
	}
}

// pPost posts a JSON body, asserts the status, and decodes the answer
// into out (nil skips decoding).
func pPost(t *testing.T, h *harness, path, token string, body any, wantStatus int, out any) {
	t.Helper()
	data, _ := json.Marshal(body)
	req, _ := http.NewRequest(http.MethodPost, h.ts.URL+path, strings.NewReader(string(data)))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != wantStatus {
		buf := make([]byte, 2048)
		n, _ := resp.Body.Read(buf)
		t.Fatalf("%s status %d, want %d: %s", path, resp.StatusCode, wantStatus, buf[:n])
	}
	if out != nil {
		if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
			t.Fatalf("decoding %s: %v", path, err)
		}
	}
}

// pGet fetches and decodes a JSON answer.
func pGet(t *testing.T, h *harness, path, token string, out any) {
	t.Helper()
	resp := get(t, h.ts, path, token)
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("%s status %d", path, resp.StatusCode)
	}
	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		t.Fatalf("decoding %s: %v", path, err)
	}
}
