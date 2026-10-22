package api

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// The station relay serves a stranger's bytes from this origin, so it
// answers only audio, under the enclosure relay's gate: a page, a
// stylesheet, a feed, a multipart stream or a type list naming markup is
// refused, an untyped stream goes out as octet-stream, and every answer
// carries nosniff and the sandboxing policy.
func TestTheStationRelayAnswersOnlyAudio(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateRadioHosts = true
	})
	station := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if ct := r.URL.Query().Get("ct"); ct != "" {
			w.Header().Set("Content-Type", ct)
		} else {
			w.Header()["Content-Type"] = nil
		}
		io.WriteString(w, `<html xmlns="http://www.w3.org/1999/xhtml"><script>alert(document.cookie)</script></html>`)
	}))
	t.Cleanup(station.Close)

	relay := func(ct string) *http.Response {
		t.Helper()
		resp := h.postJSON(t, "/api/v1/radio/stations", map[string]any{
			"name": "Typed FM " + ct, "streamUrl": station.URL + "/stream?ct=" + url.QueryEscape(ct),
		})
		st := decodeStatus[RadioStation](t, resp, 201, "creating a station")
		pi := decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+st.Pid+"/play-info", h.token))
		return get(t, h.ts, pi.Url, "")
	}
	wantSandboxed := func(resp *http.Response, what string) {
		t.Helper()
		if got := resp.Header.Get("X-Content-Type-Options"); got != service.MediaNoSniff {
			t.Errorf("%s: X-Content-Type-Options = %q", what, got)
		}
		if got := resp.Header.Get("Content-Security-Policy"); got != service.MediaCSP {
			t.Errorf("%s: Content-Security-Policy = %q, want %q", what, got, service.MediaCSP)
		}
	}

	for _, ct := range []string{
		"text/xsl", "application/rss+xml", "application/atom+xml", "image/svg+xml",
		"multipart/x-mixed-replace; boundary=x", "audio/mpeg, text/html", "text/html",
		"text/plain", "audio/x-mpegurl",
	} {
		resp := relay(ct)
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		var e Error
		if resp.StatusCode != http.StatusBadGateway || json.Unmarshal(body, &e) != nil || e.Code != "service-unreachable" {
			t.Errorf("%q: %d %s, want the relay's refusal", ct, resp.StatusCode, body)
		}
		if strings.Contains(string(body), "<script>") {
			t.Errorf("%q: the station's markup was relayed", ct)
		}
		wantSandboxed(resp, ct)
	}

	for ct, want := range map[string]string{
		"audio/mpeg":                "audio/mpeg",
		"audio/aac":                 "audio/aac",
		"application/ogg":           "application/ogg",
		"audio/mpeg; charset=utf-8": "audio/mpeg",
		"":                          "application/octet-stream",
		"application/octet-stream":  "application/octet-stream",
	} {
		resp := relay(ct)
		_, _ = io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK || resp.Header.Get("Content-Type") != want {
			t.Errorf("%q: %d as %q, want 200 as %q", ct, resp.StatusCode, resp.Header.Get("Content-Type"), want)
		}
		wantSandboxed(resp, ct)
	}

	// A refusal before the station is asked carries the pair too.
	wantSandboxed(get(t, h.ts, "/media/radio/rs-unknown", ""), "a tokenless request")
}

// The gate reads a type the way a browser would, whatever its case or
// parameters, and only an absent or octet-stream type is untyped.
func TestTheRelaysTypeGate(t *testing.T) {
	t.Parallel()
	for upstream, want := range map[string]struct {
		mediaType     string
		untyped, pass bool
	}{
		"AUDIO/MPEG; charset=utf-8":     {"audio/mpeg", false, true},
		"audio/aacp":                    {"audio/aacp", false, true},
		"video/mp4":                     {"video/mp4", false, true},
		"":                              {"", true, true},
		" Application/Octet-Stream":     {"", true, true},
		"binary/octet-stream":           {"", true, true},
		"audio/*":                       {"", false, false},
		"audio/mpeg+xml":                {"", false, false},
		"application/vnd.apple.mpegurl": {"", false, false},
		"text/html; charset=utf-8":      {"", false, false},
	} {
		mediaType, untyped, pass := relayedType(upstream)
		if mediaType != want.mediaType || untyped != want.untyped || pass != want.pass {
			t.Errorf("relayedType(%q) = %q, %v, %v, want %+v", upstream, mediaType, untyped, pass, want)
		}
	}
}
