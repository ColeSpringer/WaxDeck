package api

import (
	"context"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/cast/castv2/testreceiver"
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
	if !strings.HasPrefix(loaded[0].ContentID, "http://192.0.2.10:4420") {
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
