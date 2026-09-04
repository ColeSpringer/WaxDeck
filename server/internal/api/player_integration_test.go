package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/cast/castv2/testreceiver"
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

// pumpRefusing answers routed endpoint commands the way a client that
// cannot do what was asked does: `ok: false` carrying a code and a
// message of its own. `load` is acked when ackLoad is set, so a
// session exists for the refusals that follow.
func (c *wsClient) pumpRefusing(t *testing.T, ackLoad bool, code, message string) {
	t.Helper()
	go func() {
		for f := range c.recv {
			if f["type"] != "endpoint-cmd" {
				continue
			}
			id, _ := f["id"].(string)
			if ackLoad && f["verb"] == "load" {
				c.send(map[string]any{"type": "cmd-result", "id": id, "ok": true})
				continue
			}
			c.send(map[string]any{
				"type": "cmd-result", "id": id, "ok": false,
				"code": code, "message": message,
			})
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
	t.Parallel()
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

// A refusal from the endpoint driving a session keeps its code out to
// whoever sent the command, over both seams: REST for the session
// verbs, and the socket for the control verbs the app actually uses.
func TestConnectRefusalKeepsItsCode(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	items := h.items(t, "")
	pidA := items.Items[0].Pid
	pidB := items.Items[1].Pid

	controllerToken := loginAs(t, h.ts, "admin", testPassword).Token
	controller := dialWS(t, h, controllerToken)

	t.Run("REST: a refused load answers with the client's code", func(t *testing.T) {
		player := dialWS(t, h, loginAs(t, h.ts, "admin", testPassword).Token)
		endpointID := player.register("Laptop that says no")
		player.pumpRefusing(t, false, "feature-unavailable", "this build has no audiobook engine")

		var errBody struct{ Code, Message string }
		pPost(t, h, "/api/v1/player/sessions", controllerToken, map[string]any{
			"endpointId": endpointID,
			"itemPids":   []string{pidA, pidB},
		}, http.StatusNotImplemented, &errBody)
		if errBody.Code != "feature-unavailable" {
			t.Errorf("code %q, want feature-unavailable", errBody.Code)
		}
		if !strings.Contains(errBody.Message, "this build has no audiobook engine") {
			t.Errorf("message %q lost the refusal's own words", errBody.Message)
		}
	})

	t.Run("REST: an undocumented code degrades but keeps its message", func(t *testing.T) {
		player := dialWS(t, h, loginAs(t, h.ts, "admin", testPassword).Token)
		endpointID := player.register("Laptop with opinions")
		player.pumpRefusing(t, false, "mercury-retrograde", "the stars are wrong")

		var errBody struct{ Code, Message string }
		pPost(t, h, "/api/v1/player/sessions", controllerToken, map[string]any{
			"endpointId": endpointID,
			"itemPids":   []string{pidA},
		}, http.StatusBadRequest, &errBody)
		if errBody.Code != "invalid-request" {
			t.Errorf("code %q, want invalid-request", errBody.Code)
		}
		if !strings.Contains(errBody.Message, "the stars are wrong") {
			t.Errorf("message %q lost the refusal's own words", errBody.Message)
		}
	})

	// The socket is the seam that mattered: every control verb the app
	// sends comes back through it, and it used to flatten all of them.
	t.Run("socket: a refused control verb answers with the client's code", func(t *testing.T) {
		player := dialWS(t, h, loginAs(t, h.ts, "admin", testPassword).Token)
		endpointID := player.register("Laptop mid-download")
		player.pumpRefusing(t, true, "conflict", "that track is still downloading")

		var sess struct{ Id string }
		pPost(t, h, "/api/v1/player/sessions", controllerToken, map[string]any{
			"endpointId": endpointID,
			"itemPids":   []string{pidA, pidB},
		}, http.StatusCreated, &sess)

		controller.send(map[string]any{"type": "cmd", "id": "r1", "sessionId": sess.Id, "verb": "next"})
		frame := controller.expect("error")
		if frame["code"] != "conflict" {
			t.Errorf("frame code %v, want conflict", frame["code"])
		}
		msg, _ := frame["message"].(string)
		if !strings.Contains(msg, "that track is still downloading") {
			t.Errorf("frame message %q lost the refusal's own words", msg)
		}
	})

	t.Run("socket: an undocumented code degrades but keeps its message", func(t *testing.T) {
		player := dialWS(t, h, loginAs(t, h.ts, "admin", testPassword).Token)
		endpointID := player.register("Laptop with a theory")
		player.pumpRefusing(t, true, "vibes-off", "not right now")

		var sess struct{ Id string }
		pPost(t, h, "/api/v1/player/sessions", controllerToken, map[string]any{
			"endpointId": endpointID,
			"itemPids":   []string{pidA, pidB},
		}, http.StatusCreated, &sess)

		controller.send(map[string]any{"type": "cmd", "id": "r2", "sessionId": sess.Id, "verb": "pause"})
		frame := controller.expect("error")
		if frame["code"] != "invalid-request" {
			t.Errorf("frame code %v, want invalid-request", frame["code"])
		}
		msg, _ := frame["message"].(string)
		if !strings.Contains(msg, "not right now") {
			t.Errorf("frame message %q lost the refusal's own words", msg)
		}
	})
}

// An ended session keeps its queue where a restore surface can read
// it, and leaves the live list alone.
func TestPlaybackSessionHistory(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	items := h.items(t, "")
	pidA := items.Items[0].Pid
	pidB := items.Items[1].Pid

	controllerToken := loginAs(t, h.ts, "admin", testPassword).Token
	player := dialWS(t, h, loginAs(t, h.ts, "admin", testPassword).Token)
	endpointID := player.register("Kitchen laptop")
	st := newEndpointState()
	player.pumpEndpoint(t, st)

	type historyEntry struct {
		Id, EndpointId, EndpointName, Authority string
		Index                                   int
		PositionMs                              int64
		PositionAt                              time.Time
		Rate                                    float64
		Entries                                 []struct{ Pid, Title string }
	}
	history := func(token string) []historyEntry {
		t.Helper()
		var out struct{ Sessions []historyEntry }
		pGet(t, h, "/api/v1/player/sessions/history", token, &out)
		return out.Sessions
	}

	if got := history(controllerToken); len(got) != 0 {
		t.Fatalf("history before anything played: %+v", got)
	}

	var sess struct{ Id string }
	pPost(t, h, "/api/v1/player/sessions", controllerToken, map[string]any{
		"endpointId": endpointID,
		"itemPids":   []string{pidA, pidB},
		"index":      1,
		"positionMs": 1000,
		// Loaded paused, so the final position is the one we set
		// rather than that plus however long the test took: ending a
		// playing session extrapolates it forward first.
		"play": false,
	}, http.StatusCreated, &sess)

	// A live session is not history.
	if got := history(controllerToken); len(got) != 0 {
		t.Fatalf("a live session showed up in history: %+v", got)
	}

	before := time.Now()
	req, _ := http.NewRequest(http.MethodDelete, h.ts.URL+"/api/v1/player/sessions/"+sess.Id, nil)
	req.Header.Set("Authorization", "Bearer "+controllerToken)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("ending the session: status %d", resp.StatusCode)
	}

	// Read straight back, with no poll: ending a session through the
	// REST call writes the row before answering, so a controller that
	// stops playback and offers to resume it does not race a teardown
	// goroutine. (Sessions that end other ways still persist from the
	// teardown, and the spec says so.)
	got := history(controllerToken)

	if len(got) != 1 {
		t.Fatalf("history %+v", got)
	}
	e := got[0]
	if e.Id != sess.Id || e.EndpointId != endpointID {
		t.Errorf("history entry identity %+v", e)
	}
	if e.EndpointName != "Kitchen laptop" {
		t.Errorf("endpointName %q, want the live endpoint's name", e.EndpointName)
	}
	if e.Authority != "mirror" {
		t.Errorf("authority %q, want mirror", e.Authority)
	}
	if len(e.Entries) != 2 || e.Entries[0].Pid != pidA || e.Entries[1].Pid != pidB {
		t.Errorf("the queue did not survive: %+v", e.Entries)
	}
	if e.Index != 1 || e.PositionMs != 1000 {
		t.Errorf("index/position %d/%d, want 1/1000", e.Index, e.PositionMs)
	}
	if e.Rate <= 0 {
		t.Errorf("rate %v, want a real rate", e.Rate)
	}
	if e.PositionAt.Before(before.Add(-time.Second)) || e.PositionAt.After(time.Now().Add(time.Second)) {
		t.Errorf("positionAt %v is not the instant the session ended (~%v)", e.PositionAt, before)
	}

	// The live list keeps its invariant: history is not in it.
	var live struct{ Sessions []struct{ Id string } }
	pGet(t, h, "/api/v1/player/sessions", controllerToken, &live)
	for _, s := range live.Sessions {
		if s.Id == sess.Id {
			t.Fatalf("the ended session is still in the live list: %+v", live)
		}
	}

	// History is the caller's own, whatever it played on: another
	// account sees none of it.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "listener", "password": "long-enough-pw",
	})
	wantStatus(t, resp, 201, "create second user")
	otherToken := loginAs(t, h.ts, "listener", "long-enough-pw").Token
	if other := history(otherToken); len(other) != 0 {
		t.Errorf("another user reads this history: %+v", other)
	}
}

// TestConnectClockSync pins the ping/pong shape.
func TestConnectClockSync(t *testing.T) {
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
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
	// The harness advertises its own address, which is the reachable
	// case: the server fetching its own health check through the
	// address a device would use is what this endpoint answers.
	if b.Base != h.lanBase || b.Source != "detected" || !b.Reachable {
		t.Fatalf("base %+v, want the advertise address reachable", b)
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

// TestBookPlaysOnDeviceEndpoint is the multi-file audiobook reaching a
// cast device: one queue entry, one media item per part on the
// receiver, and positions on the book's own timeline in both
// directions - a seek is read as book milliseconds and the session
// reports them back the same way.
func TestBookPlaysOnDeviceEndpoint(t *testing.T) {
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
	book := books.Items[0]

	recv := testreceiver.Start(t)
	dev := recv.Device()
	ep, err := h.connect.EndpointOnline(ctx, "cast", dev.Key(), "Kitchen speaker", recv.Addr(), true, false,
		dev.Dial(h.group, nil))
	if err != nil {
		t.Fatal(err)
	}

	var sess struct {
		Id         string
		Index      int
		PositionMs int64
		Entries    []struct{ Pid string }
	}
	pPost(t, h, "/api/v1/player/sessions", h.token, map[string]any{
		"endpointId": ep.ID,
		"itemPids":   []string{book.Pid},
	}, http.StatusCreated, &sess)
	if len(sess.Entries) != 1 || sess.Entries[0].Pid != book.Pid {
		t.Fatalf("a book is one queue entry: %+v", sess.Entries)
	}
	loaded := recv.LoadedItems()
	if len(loaded) != 3 {
		t.Fatalf("receiver got %d items, want one per part of the fixture book", len(loaded))
	}
	for _, it := range loaded {
		if it.Title != book.Title {
			t.Fatalf("a part names itself %q rather than the book: %+v", it.Title, it)
		}
	}
	if loaded[0].ContentID == loaded[1].ContentID {
		t.Fatalf("every part fetched the same bytes: %s", loaded[0].ContentID)
	}

	// The fixture's parts are 4s, 5s and 6s, so eight seconds into the
	// book is four into part two.
	controller := dialWS(t, h, h.token)
	controller.send(map[string]any{"type": "cmd", "id": "s1", "sessionId": sess.Id, "verb": "seek", "positionMs": 8000})
	controller.expect("ack")
	waitFor2(t, func() bool { return len(recv.Loads()) >= 2 })
	last := recv.Loads()[len(recv.Loads())-1]
	if last.StartIndex != 1 || last.CurrentTimeSeconds < 3.5 || last.CurrentTimeSeconds > 4.5 {
		t.Fatalf("seek to 8s of the book reloaded at item %d/%.1fs, want part two at 4s", last.StartIndex, last.CurrentTimeSeconds)
	}

	var after struct {
		Index      int
		PositionMs int64
	}
	pGet(t, h, "/api/v1/player/sessions/"+sess.Id, h.token, &after)
	if after.Index != 0 || after.PositionMs < 8000 || after.PositionMs > 9000 {
		t.Fatalf("session reads entry %d at %dms, want the book entry near 8000", after.Index, after.PositionMs)
	}
}
