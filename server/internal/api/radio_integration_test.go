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
	"sync/atomic"
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
	t.Parallel()
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
	t.Parallel()
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
	if got := streamResp.Header.Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("X-Content-Type-Options = %q, want nosniff", got)
	}
}

// A station that answers markup does not get to have it relayed as
// markup: the proxy serves an attacker-nameable host's bytes from
// WaxDeck's own origin, which is the same exposure the logo endpoint has
// and the same answer.
func TestRadioProxyRefusesExecutableContentTypes(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateRadioHosts = true
	})

	station := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprint(w, `<html><script>alert(document.cookie)</script></html>`)
	}))
	t.Cleanup(station.Close)

	resp := h.postJSON(t, "/api/v1/radio/stations", map[string]any{
		"name": "Markup FM", "streamUrl": station.URL + "/stream",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create status = %d", resp.StatusCode)
	}
	st := decode[RadioStation](t, resp)

	pi := decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+st.Pid+"/play-info", h.token))
	streamResp, err := http.Get(h.ts.URL + pi.Url)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = io.ReadAll(streamResp.Body)
	streamResp.Body.Close()
	// Relayed as audio, which is what a listener asked for: a station
	// answering markup has already failed to be a stream, and passing the
	// type on would make it a script in this origin instead.
	if got := streamResp.Header.Get("Content-Type"); got != "audio/mpeg" {
		t.Fatalf("Content-Type = %q, want audio/mpeg for a text/html station", got)
	}
	if got := streamResp.Header.Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("X-Content-Type-Options = %q, want nosniff", got)
	}
}

func TestRadioStreamContentType(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct{ declared, want string }{
		{"audio/mpeg", "audio/mpeg"},
		{"audio/aacp", "audio/aacp"},
		{"application/ogg", "application/ogg"},
		// A parameter rides along untouched; only the essence decides.
		{"audio/mpeg; charset=utf-8", "audio/mpeg; charset=utf-8"},
		// The executable families, and the empty default.
		{"", "audio/mpeg"},
		{"text/html", "audio/mpeg"},
		{"TEXT/HTML; charset=utf-8", "audio/mpeg"},
		{"image/svg+xml", "audio/mpeg"},
		{"application/xhtml+xml", "audio/mpeg"},
		{"text/xml", "audio/mpeg"},
	} {
		if got := radioStreamContentType(tc.declared); got != tc.want {
			t.Errorf("radioStreamContentType(%q) = %q, want %q", tc.declared, got, tc.want)
		}
	}
}

// A one-pixel PNG, so the sniff sees real image bytes rather than a
// string that happens to be long enough.
var pngPixel = []byte{
	0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a,
	0x00, 0x00, 0x00, 0x0d, 'I', 'H', 'D', 'R',
	0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
	0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
	0x89, 0x00, 0x00, 0x00, 0x0a, 'I', 'D', 'A', 'T',
	0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05,
	0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00,
	0x00, 0x00, 'I', 'E', 'N', 'D', 0xae, 0x42, 0x60, 0x82,
}

func TestRadioStationLogoProxy(t *testing.T) {
	t.Parallel()
	var fetches, misses int
	logoHost := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/logo.png":
			fetches++
			// Labelled the way a good many hosts label favicons: the
			// bytes decide the served type, not this.
			w.Header().Set("Content-Type", "image/x-icon")
			w.Write(pngPixel)
		case "/nameless":
			// No Content-Type at all, which is ordinary for a favicon on a
			// static host. Saying nothing is not a claim of anything, so the
			// bytes get to decide as they do everywhere else here.
			fetches++
			w.Write(pngPixel)
		case "/notanimage":
			misses++
			w.Header().Set("Content-Type", "text/html")
			fmt.Fprint(w, "<html>gone</html>")
		case "/huge":
			w.Header().Set("Content-Type", "image/png")
			w.Write(bytes.Repeat([]byte{0x89}, (512<<10)+1))
		case "/logo.svg":
			// The XSS attempt: a station's logo URL is attacker-supplied
			// and this endpoint serves from WaxDeck's own origin, so an
			// SVG proxied here would run its script under the caller's
			// session. Labelled honestly, because the point is that an
			// honest label is not enough to get it served.
			w.Header().Set("Content-Type", "image/svg+xml")
			fmt.Fprint(w, `<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>`)
		case "/logo.html":
			// The same attempt wearing an image's label: the served type
			// is decided by the bytes, so claiming image/png buys nothing.
			w.Header().Set("Content-Type", "image/png")
			fmt.Fprint(w, `<html><script>alert(1)</script></html>`)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(logoHost.Close)

	// The logo fetch rides the stream proxy's guarded client, so a
	// loopback fake needs the LAN escape hatch.
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateRadioHosts = true
	})

	create := func(name, logo string) RadioStation {
		t.Helper()
		body := map[string]any{"name": name, "streamUrl": "http://198.51.100.7/" + name}
		if logo != "" {
			body["logoUrl"] = logo
		}
		resp := h.postJSON(t, "/api/v1/radio/stations", body)
		if resp.StatusCode != 201 {
			raw, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			t.Fatalf("create %s status = %d (%s)", name, resp.StatusCode, raw)
		}
		return decode[RadioStation](t, resp)
	}

	withLogo := create("logo-fm", logoHost.URL+"/logo.png")

	// The bytes come back as what they are rather than as what the host
	// called them, with a validator and the day of freshness.
	resp := get(t, h.ts, "/api/v1/radio/stations/"+withLogo.Pid+"/logo", h.token)
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("logo status = %d (%s)", resp.StatusCode, body)
	}
	if !bytes.Equal(body, pngPixel) {
		t.Fatalf("logo served %d bytes, want the %d byte fixture", len(body), len(pngPixel))
	}
	if ct := resp.Header.Get("Content-Type"); ct != "image/png" {
		t.Fatalf("Content-Type = %q, want image/png (sniffed, not the host's image/x-icon)", ct)
	}
	etag := resp.Header.Get("ETag")
	if etag == "" {
		t.Fatal("logo carried no ETag")
	}
	if cc := resp.Header.Get("Cache-Control"); !strings.Contains(cc, "private") || !strings.Contains(cc, "max-age=86400") {
		t.Fatalf("Cache-Control = %q", cc)
	}
	// Nothing varies by credential: the station library is shared.
	if v := resp.Header.Get("Vary"); v != "" {
		t.Fatalf("Vary = %q, want none", v)
	}
	// The hardening pair. These bytes came from a host any account can
	// name and they are served from this origin, so a browser must not be
	// free to re-decide the body, and a document opened straight from this
	// URL must not be able to run anything.
	if got := resp.Header.Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("X-Content-Type-Options = %q, want nosniff", got)
	}
	if csp := resp.Header.Get("Content-Security-Policy"); !strings.Contains(csp, "default-src 'none'") ||
		!strings.Contains(csp, "sandbox") {
		t.Fatalf("Content-Security-Policy = %q", csp)
	}

	// A `size` is still accepted and still changes nothing, which is what
	// the contract says. Today's client no longer sends one - one identical
	// body behind a URL per rung is a fetch per rung for nothing - but a
	// hand-typed URL and an older build both still land here.
	resp = get(t, h.ts, "/api/v1/radio/stations/"+withLogo.Pid+"/logo?size=256", h.token)
	sized, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || !bytes.Equal(sized, pngPixel) {
		t.Fatalf("sized logo status = %d, %d bytes", resp.StatusCode, len(sized))
	}

	// Both of those were served from one upstream fetch: the cache is
	// what keeps a household browsing the dial off the station's host.
	if fetches != 1 {
		t.Fatalf("upstream fetches = %d, want 1 (the second read is cached)", fetches)
	}

	// A host that named no type is served on the strength of its bytes.
	// The declared type is a filter against downloading a page to learn it
	// is a page; it was never the authority on what a body is, and a
	// silent host has claimed nothing to disagree with.
	nameless := create("nameless-fm", logoHost.URL+"/nameless")
	resp = get(t, h.ts, "/api/v1/radio/stations/"+nameless.Pid+"/logo", h.token)
	namelessBody, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || !bytes.Equal(namelessBody, pngPixel) {
		t.Fatalf("Content-Type-less logo status = %d, %d bytes", resp.StatusCode, len(namelessBody))
	}
	if ct := resp.Header.Get("Content-Type"); ct != "image/png" {
		t.Fatalf("Content-Type = %q, want the sniffed image/png", ct)
	}

	// A matching validator answers 304 with the same freshness, so a
	// revalidation refreshes the cached copy instead of leaving it stale.
	req, _ := http.NewRequest("GET", h.ts.URL+"/api/v1/radio/stations/"+withLogo.Pid+"/logo", nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	req.Header.Set("If-None-Match", etag)
	fresh, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	fresh.Body.Close()
	if fresh.StatusCode != 304 {
		t.Fatalf("If-None-Match status = %d, want 304", fresh.StatusCode)
	}
	if fresh.Header.Get("ETag") != etag || fresh.Header.Get("Cache-Control") == "" {
		t.Fatalf("304 headers = %v", fresh.Header)
	}

	// Every way there is nothing to draw is the same 404, because a
	// client draws a monogram for all of them - and two of these are the
	// stored-XSS attempt rather than a broken station: anything that could
	// execute in this origin is refused rather than sanitized, because a
	// decorative favicon is not worth an SVG sanitizer's bypasses.
	for _, station := range []struct {
		name string
		logo string
	}{
		{"nologo-fm", ""},
		{"html-fm", logoHost.URL + "/notanimage"},
		{"huge-fm", logoHost.URL + "/huge"},
		{"missing-fm", logoHost.URL + "/gone.png"},
		{"svg-fm", logoHost.URL + "/logo.svg"},
		{"markup-as-png-fm", logoHost.URL + "/logo.html"},
	} {
		st := create(station.name, station.logo)
		resp := get(t, h.ts, "/api/v1/radio/stations/"+st.Pid+"/logo", h.token)
		raw, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 404 {
			t.Fatalf("%s logo status = %d, want 404 (%s)", station.name, resp.StatusCode, raw)
		}
	}

	// A failure is remembered too, and that is the point of the shorter
	// miss TTL rather than an oversight: a grid of thirty stations behind
	// one dead host would otherwise cost thirty upstream fetches per paint,
	// per device, forever.
	htmlStation := create("cached-miss-fm", logoHost.URL+"/notanimage")
	// From zero: the cache is keyed by pid rather than by URL, so the
	// station created for the 404 sweep above fetched this same path once
	// already, and correctly so - two stations naming one dead host are two
	// stations.
	misses = 0
	for range 3 {
		resp := get(t, h.ts, "/api/v1/radio/stations/"+htmlStation.Pid+"/logo", h.token)
		resp.Body.Close()
		if resp.StatusCode != 404 {
			t.Fatalf("repeat miss status = %d, want 404", resp.StatusCode)
		}
	}
	if misses != 1 {
		t.Fatalf("upstream fetches for a failing host = %d, want 1", misses)
	}

	// A station nobody is signed in to see nothing of: the read needs a
	// session like every other.
	anon := get(t, h.ts, "/api/v1/radio/stations/"+withLogo.Pid+"/logo", "")
	anon.Body.Close()
	if anon.StatusCode != 401 {
		t.Fatalf("tokenless logo status = %d, want 401", anon.StatusCode)
	}

	// Changing the URL drops the cached copy, so the new logo is drawn
	// rather than a day-old copy of the old one.
	resp = h.putJSON(t, "/api/v1/radio/stations/"+withLogo.Pid, map[string]any{
		"name": "logo-fm", "streamUrl": "http://198.51.100.7/logo-fm",
		"logoUrl": logoHost.URL + "/gone.png",
	})
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("update status = %d", resp.StatusCode)
	}
	resp = get(t, h.ts, "/api/v1/radio/stations/"+withLogo.Pid+"/logo", h.token)
	resp.Body.Close()
	if resp.StatusCode != 404 {
		t.Fatalf("logo after re-pointing = %d, want 404 from the new URL", resp.StatusCode)
	}
}

// A logo URL aimed at a private address is refused for the reason a
// stream URL is: the row is attacker-supplied, and the proxy would
// otherwise read internal services on the caller's behalf.
func TestRadioStationLogoRefusesPrivateHosts(t *testing.T) {
	t.Parallel()
	logoHost := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/png")
		w.Write(pngPixel)
	}))
	t.Cleanup(logoHost.Close)

	// No escape hatch this time, so the dial-time guard is live. The
	// station's own stream URL is a public address the write-time check
	// accepts; the logo is the loopback one.
	h := newHarness(t)
	resp := h.postJSON(t, "/api/v1/radio/stations", map[string]any{
		"name": "sneaky-fm", "streamUrl": "http://198.51.100.7/stream",
		"logoUrl": logoHost.URL + "/logo.png",
	})
	if resp.StatusCode != 201 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("create status = %d (%s)", resp.StatusCode, body)
	}
	st := decode[RadioStation](t, resp)

	resp = get(t, h.ts, "/api/v1/radio/stations/"+st.Pid+"/logo", h.token)
	resp.Body.Close()
	if resp.StatusCode != 404 {
		t.Fatalf("private-host logo status = %d, want 404", resp.StatusCode)
	}
}

func TestRadioDirectorySearch(t *testing.T) {
	t.Parallel()
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

// sickRadioMirror answers every search the way the volunteer pool does
// on a bad afternoon, counting what it was asked.
func sickRadioMirror(t *testing.T, hits *atomic.Int64) string {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		http.Error(w, "busy", http.StatusServiceUnavailable)
	}))
	t.Cleanup(srv.Close)
	return srv.URL
}

// One sick mirror used to be the whole feature failing: the pooled
// connection pinned it and the retry landed back on it. A search now
// moves on, and the healthy mirror answers whichever position the
// shuffle put it in.
func TestRadioDirectoryMirrorRotation(t *testing.T) {
	t.Parallel()
	var hits atomic.Int64
	healthy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, `[{"name":"Jazz24","url":"http://jazz.example/stream"}]`)
	}))
	t.Cleanup(healthy.Close)

	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateRadioHosts = true
		cfg.RadioDirectoryMirrors = []string{
			sickRadioMirror(t, &hits), sickRadioMirror(t, &hits), healthy.URL,
		}
	})

	resp := get(t, h.ts, "/api/v1/radio/directory?query=jazz", h.token)
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("directory status = %d (%s), want the healthy mirror's answer", resp.StatusCode, body)
	}
	res := decode[RadioDirectoryResults](t, resp)
	if len(res.Entries) != 1 || res.Entries[0].Name != "Jazz24" {
		t.Fatalf("entries = %+v, want the healthy mirror's one station", res.Entries)
	}
}

// When every mirror says it is busy, that is a different thing from the
// directory being broken, and the listener is told the difference. The
// hop count is the rotation bound: four mirrors, three attempts.
func TestRadioDirectoryAllMirrorsBusy(t *testing.T) {
	t.Parallel()
	var hits atomic.Int64
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateRadioHosts = true
		cfg.RadioDirectoryMirrors = []string{
			sickRadioMirror(t, &hits), sickRadioMirror(t, &hits),
			sickRadioMirror(t, &hits), sickRadioMirror(t, &hits),
		}
	})

	resp := get(t, h.ts, "/api/v1/radio/directory?query=jazz", h.token)
	if resp.StatusCode != 502 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("all-busy status = %d (%s), want 502", resp.StatusCode, body)
	}
	e := decode[Error](t, resp)
	if e.Code != "directory-unavailable" {
		t.Fatalf("all-busy code = %q, want directory-unavailable", e.Code)
	}
	if !strings.Contains(e.Message, "busy") {
		t.Fatalf("all-busy message = %q, want the busy wording rather than a raw status", e.Message)
	}
	if got := hits.Load(); got != 3 {
		t.Fatalf("mirror requests = %d, want 3 (rotate, but bounded)", got)
	}
}

func TestSubsonicRadioParity(t *testing.T) {
	t.Parallel()
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
