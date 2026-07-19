package api

import (
	"bytes"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// subsonicJSON fetches one /rest view with token auth and decodes the
// JSON envelope into out, for shapes the shared subsonicEnv omits.
func subsonicJSON(t *testing.T, h *harness, view, secret, extra string, out any) {
	t.Helper()
	salt := "radiosalt"
	sum := md5.Sum([]byte(secret + salt))
	q := "?u=admin&t=" + hex.EncodeToString(sum[:]) + "&s=" + salt + "&v=1.16.1&c=test&f=json" + extra
	resp, err := http.Get(h.ts.URL + "/rest/" + view + q)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	var wrapper map[string]json.RawMessage
	if err := json.Unmarshal(body, &wrapper); err != nil {
		t.Fatalf("%s: %v (body %s)", view, err, body)
	}
	env, ok := wrapper["subsonic-response"]
	if !ok {
		t.Fatalf("%s: no subsonic-response key in %s", view, body)
	}
	if err := json.Unmarshal(env, out); err != nil {
		t.Fatalf("%s: %v (envelope %s)", view, err, env)
	}
}

func TestRadioStationCrud(t *testing.T) {
	h := newHarness(t)

	resp := h.postJSON(t, "/api/v1/radio/stations", map[string]any{
		"name": "Deck FM", "streamUrl": "http://198.51.100.7/stream", "homepageUrl": "https://deck.example",
	})
	if resp.StatusCode != 201 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("create status = %d (%s)", resp.StatusCode, body)
	}
	st := decode[RadioStation](t, resp)
	if !strings.HasPrefix(st.Pid, "rs-") || st.Name != "Deck FM" || st.StreamUrl != "http://198.51.100.7/stream" {
		t.Fatalf("created station = %+v", st)
	}
	if st.HomepageUrl == nil || *st.HomepageUrl != "https://deck.example" {
		t.Fatalf("homepage = %v", st.HomepageUrl)
	}

	lst := decode[RadioStationList](t, get(t, h.ts, "/api/v1/radio/stations", h.token))
	if len(lst.Stations) != 1 || lst.Stations[0].Pid != st.Pid {
		t.Fatalf("listing = %+v", lst.Stations)
	}
	got := decode[RadioStation](t, get(t, h.ts, "/api/v1/radio/stations/"+st.Pid, h.token))
	if got.Pid != st.Pid || got.Name != st.Name {
		t.Fatalf("detail = %+v", got)
	}

	// Update replaces the fields.
	resp = h.putJSON(t, "/api/v1/radio/stations/"+st.Pid, map[string]any{
		"name": "Deck FM HQ", "streamUrl": "https://198.51.100.7/hq",
	})
	if resp.StatusCode != 200 {
		t.Fatalf("update status = %d", resp.StatusCode)
	}
	if upd := decode[RadioStation](t, resp); upd.Name != "Deck FM HQ" || upd.StreamUrl != "https://198.51.100.7/hq" {
		t.Fatalf("updated station = %+v", upd)
	}

	// A second station with the same stream URL conflicts.
	resp = h.postJSON(t, "/api/v1/radio/stations", map[string]any{
		"name": "Copycat", "streamUrl": "https://198.51.100.7/hq",
	})
	if resp.StatusCode != 409 {
		t.Fatalf("duplicate create status = %d, want 409", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "conflict" {
		t.Fatalf("duplicate create code = %q, want conflict", e.Code)
	}

	// Scheme policy: http passes (above), ftp is refused.
	resp = h.postJSON(t, "/api/v1/radio/stations", map[string]any{
		"name": "Old School", "streamUrl": "ftp://198.51.100.9/stream",
	})
	if resp.StatusCode != 400 {
		t.Fatalf("ftp create status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "invalid-request" {
		t.Fatalf("ftp create code = %q, want invalid-request", e.Code)
	}

	// Private-range destinations are refused by default.
	resp = h.postJSON(t, "/api/v1/radio/stations", map[string]any{
		"name": "Local Loop", "streamUrl": "http://127.0.0.1:9/stream",
	})
	if resp.StatusCode != 400 {
		t.Fatalf("loopback create status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "invalid-request" {
		t.Fatalf("loopback create code = %q, want invalid-request", e.Code)
	}

	resp = h.deleteReq(t, "/api/v1/radio/stations/"+st.Pid)
	if resp.StatusCode != 204 {
		t.Fatalf("delete status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	resp = get(t, h.ts, "/api/v1/radio/stations/"+st.Pid, h.token)
	if resp.StatusCode != 404 {
		t.Fatalf("deleted station status = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()
	resp = h.deleteReq(t, "/api/v1/radio/stations/"+st.Pid)
	if resp.StatusCode != 404 {
		t.Fatalf("second delete status = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestRadioPlayInfoAndProxy(t *testing.T) {
	// The proxy's guarded client refuses loopback by default, so the
	// loopback test station needs the LAN-stations escape hatch.
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateRadioHosts = true
	})

	payload := bytes.Repeat([]byte("waxdeck-radio-bytes."), 512)
	station := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("icy-name", "Fixture FM")
		w.Header().Set("Content-Type", "audio/mpeg")
		w.Write(payload)
	}))
	t.Cleanup(station.Close)

	resp := h.postJSON(t, "/api/v1/radio/stations", map[string]any{
		"name": "Loopback FM", "streamUrl": station.URL + "/stream",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create status = %d", resp.StatusCode)
	}
	st := decode[RadioStation](t, resp)

	resp = get(t, h.ts, "/api/v1/radio/stations/"+st.Pid+"/play-info", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("play-info status = %d", resp.StatusCode)
	}
	pi := decode[RadioPlayInfo](t, resp)
	if !strings.HasPrefix(pi.Url, "/media/radio/"+st.Pid+"?mt=") {
		t.Fatalf("play-info url = %q", pi.Url)
	}

	// The proxied stream is worthless without its token.
	bare, err := http.Get(h.ts.URL + "/media/radio/" + st.Pid)
	if err != nil {
		t.Fatal(err)
	}
	bare.Body.Close()
	if bare.StatusCode != 401 {
		t.Fatalf("tokenless proxy status = %d, want 401", bare.StatusCode)
	}

	// With the token the bytes stream through and the ICY station
	// header survives the proxy.
	streamResp, err := http.Get(h.ts.URL + pi.Url)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(streamResp.Body)
	streamResp.Body.Close()
	if streamResp.StatusCode != 200 {
		t.Fatalf("proxied stream status = %d", streamResp.StatusCode)
	}
	if !bytes.Equal(body, payload) {
		t.Fatalf("proxied %d bytes, want the %d byte station payload", len(body), len(payload))
	}
	if got := streamResp.Header.Get("Icy-Name"); got != "Fixture FM" {
		t.Fatalf("Icy-Name = %q, want Fixture FM", got)
	}
	if cc := streamResp.Header.Get("Cache-Control"); cc != "no-store" {
		t.Fatalf("Cache-Control = %q, want no-store", cc)
	}
}

func TestRadioDirectorySearch(t *testing.T) {
	directory := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/json/stations/search" {
			http.NotFound(w, r)
			return
		}
		if got := r.URL.Query().Get("name"); got != "jazz" {
			t.Errorf("directory name query = %q, want jazz", got)
		}
		if got := r.URL.Query().Get("hidebroken"); got != "true" {
			t.Errorf("directory hidebroken = %q, want true", got)
		}
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `[
			{"name":"Jazz24","url":"http://jazz.example/low","url_resolved":"http://jazz.example/stream",
			 "homepage":"https://jazz.example","favicon":"https://jazz.example/logo.png",
			 "tags":"jazz,smooth","country":"The Netherlands","codec":"MP3","bitrate":192},
			{"name":"","url":"http://nameless.example/stream"},
			{"name":"Silent FM","url":""}
		]`)
	}))
	t.Cleanup(directory.Close)

	// The directory fetch rides the same guarded client as the proxy;
	// reaching a loopback fake needs the LAN escape hatch here too.
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateRadioHosts = true
		cfg.RadioDirectoryBase = directory.URL
	})

	resp := get(t, h.ts, "/api/v1/radio/directory?query=jazz", h.token)
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("directory status = %d (%s)", resp.StatusCode, body)
	}
	res := decode[RadioDirectoryResults](t, resp)
	if len(res.Entries) != 1 {
		t.Fatalf("directory entries = %d, want 1 (rows without a name or URL are dropped)", len(res.Entries))
	}
	e := res.Entries[0]
	if e.Name != "Jazz24" || e.StreamUrl != "http://jazz.example/stream" {
		t.Fatalf("entry = %+v, want the resolved stream URL", e)
	}
	if e.HomepageUrl == nil || *e.HomepageUrl != "https://jazz.example" ||
		e.LogoUrl == nil || *e.LogoUrl != "https://jazz.example/logo.png" {
		t.Fatalf("entry links = %+v", e)
	}
	if e.Tags == nil || *e.Tags != "jazz,smooth" || e.Country == nil || *e.Country != "The Netherlands" {
		t.Fatalf("entry metadata = %+v", e)
	}
	if e.Codec == nil || *e.Codec != "MP3" || e.BitrateKbps == nil || *e.BitrateKbps != 192 {
		t.Fatalf("entry codec = %+v", e)
	}

	// An unreachable directory answers the typed 502.
	directory.Close()
	resp = get(t, h.ts, "/api/v1/radio/directory?query=jazz", h.token)
	if resp.StatusCode != 502 {
		t.Fatalf("unreachable directory status = %d, want 502", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "directory-unavailable" {
		t.Fatalf("unreachable directory code = %q, want directory-unavailable", e.Code)
	}
}

func TestSubsonicRadioParity(t *testing.T) {
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)

	resp := h.postJSON(t, "/api/v1/radio/stations", map[string]any{
		"name": "Deck FM", "streamUrl": "http://198.51.100.7/stream", "homepageUrl": "https://deck.example",
	})
	first := decode[RadioStation](t, resp)

	var env struct {
		Status                string `json:"status"`
		InternetRadioStations *struct {
			Stations []struct {
				ID          string `json:"id"`
				Name        string `json:"name"`
				StreamURL   string `json:"streamUrl"`
				HomepageURL string `json:"homePageUrl"`
			} `json:"internetRadioStation"`
		} `json:"internetRadioStations"`
	}
	subsonicJSON(t, h, "getInternetRadioStations", secret, "", &env)
	if env.Status != "ok" || env.InternetRadioStations == nil || len(env.InternetRadioStations.Stations) != 1 {
		t.Fatalf("getInternetRadioStations = %+v", env)
	}
	got := env.InternetRadioStations.Stations[0]
	if got.ID != first.Pid || got.Name != "Deck FM" || got.StreamURL != first.StreamUrl || got.HomepageURL != "https://deck.example" {
		t.Fatalf("station row = %+v, want %+v", got, first)
	}

	// The protocol's create lands in the same shared library.
	var createEnv struct {
		Status string `json:"status"`
	}
	subsonicJSON(t, h, "createInternetRadioStation", secret,
		"&name=Second+FM&streamUrl="+"http%3A%2F%2F198.51.100.8%2Fstream", &createEnv)
	if createEnv.Status != "ok" {
		t.Fatalf("createInternetRadioStation = %+v", createEnv)
	}
	lst := decode[RadioStationList](t, get(t, h.ts, "/api/v1/radio/stations", h.token))
	if len(lst.Stations) != 2 {
		t.Fatalf("stations after subsonic create = %d, want 2", len(lst.Stations))
	}

	// And the protocol's delete removes it.
	var delEnv struct {
		Status string `json:"status"`
		Error  *struct {
			Code int `json:"code"`
		} `json:"error"`
	}
	subsonicJSON(t, h, "deleteInternetRadioStation", secret, "&id="+first.Pid, &delEnv)
	if delEnv.Status != "ok" {
		t.Fatalf("deleteInternetRadioStation = %+v", delEnv)
	}
	lst = decode[RadioStationList](t, get(t, h.ts, "/api/v1/radio/stations", h.token))
	if len(lst.Stations) != 1 || lst.Stations[0].Name != "Second FM" {
		t.Fatalf("stations after subsonic delete = %+v", lst.Stations)
	}

	// An unknown station answers the protocol's not-found code.
	subsonicJSON(t, h, "deleteInternetRadioStation", secret, "&id="+first.Pid, &delEnv)
	if delEnv.Status != "failed" || delEnv.Error == nil || delEnv.Error.Code != 70 {
		t.Fatalf("delete of a missing station = %+v, want error 70", delEnv)
	}
}
