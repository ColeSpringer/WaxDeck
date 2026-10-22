package api

import (
	"fmt"
	"html"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// typedEnclosureHost is a podcast host whose one episode its feed
// declares as one type and whose server answers as another (served
// empty sends no Content-Type at all), honouring ranges the way real
// podcast hosts do. It returns the feed's URL; the episode is at
// /episode beside it.
func typedEnclosureHost(t *testing.T, declared, served, body string) string {
	t.Helper()
	var ts *httptest.Server
	mux := http.NewServeMux()
	mux.HandleFunc("/feed.xml", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
<title>Typed Cast %s</title>
<description>One episode.</description>
<item>
	<title>Typed Episode</title>
	<guid isPermaLink="false">typed-1</guid>
	<pubDate>%s</pubDate>
	<enclosure url="%s/episode" type="%s" length="%d"/>
</item>
</channel></rss>`, html.EscapeString(declared+" as "+served),
			time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z),
			ts.URL, html.EscapeString(declared), len(body))
	})
	mux.HandleFunc("/episode", func(w http.ResponseWriter, r *http.Request) {
		if served == "" {
			// nil, not deleted: a handler that sets none gets one sniffed.
			w.Header()["Content-Type"] = nil
		} else {
			w.Header().Set("Content-Type", served)
		}
		http.ServeContent(w, r, "", time.Time{}, strings.NewReader(body))
	})
	ts = httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	return ts.URL + "/feed.xml"
}

// The relay hands a browser audio and nothing else, from this origin:
// a host's own type when it names audio, the feed's declared type held
// to the same rule when the host does not say, and a refusal with none
// of the host's bytes when it answers with a page. Every relayed answer
// tells the browser not to sniff or run what it was given.
func TestEnclosureRelayServesOnlyAudio(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	const audio = "ID3fake-mpeg-audio-bytes-for-the-relay"
	const page = "<!doctype html><html><script>alert(1)</script></html>"
	const xhtml = `<html xmlns="http://www.w3.org/1999/xhtml"><body>a stranger's page</body></html>`
	const mpd = `<MPD xmlns="urn:mpeg:dash:schema:mpd:2011"><BaseURL>https://tracker.example/</BaseURL></MPD>`
	for _, c := range []struct {
		name, declared, served, body string
		wantType                     string // empty: refused
	}{
		{"audio passes unchanged", "audio/mpeg", "audio/mpeg", audio, "audio/mpeg"},
		{"video enclosures are real", "video/mp4", "video/mp4", audio, "video/mp4"},
		{"an untyped answer takes the declared type", "audio/mp4", "", audio, "audio/mp4"},
		{"octet-stream takes the declared type", "audio/mpeg", "application/octet-stream", audio, "audio/mpeg"},
		{"a declared page is never served as one", "text/html", "application/octet-stream", page, "audio/mpeg"},
		{"a page is refused", "audio/mpeg", "text/html; charset=utf-8", page, ""},
		{"a document is refused", "audio/mpeg", "application/json", `{"not":"audio"}`, ""},
		{"markup under an audio label is refused", "audio/mpeg", "audio/x+xml", xhtml, ""},
		{"a playlist is refused", "audio/mpeg", "audio/x-mpegurl", hlsPlaylist, ""},
		{"a streaming manifest is refused", "audio/mpeg", "application/vnd.apple.mpegurl", hlsPlaylist, ""},
		{"a DASH manifest is refused", "audio/mpeg", "video/vnd.mpeg.dash.mpd", mpd, ""},
	} {
		t.Run(c.name, func(t *testing.T) {
			feed := typedEnclosureHost(t, c.declared, c.served, c.body)
			sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed}), 201, "subscribe")
			ep := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items[0]
			info := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token))
			if _, ok := relayableMediaTypes[info.MimeType]; !ok {
				t.Errorf("play-info mimeType = %q, want an audio or video type", info.MimeType)
			}
			resp := get(t, h.ts, info.Url, "")
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			if got := resp.Header.Get("X-Content-Type-Options"); got != "nosniff" {
				t.Errorf("X-Content-Type-Options = %q, want nosniff", got)
			}
			if got := resp.Header.Get("Content-Security-Policy"); got != "default-src 'none'; sandbox" {
				t.Errorf("Content-Security-Policy = %q", got)
			}
			if c.wantType == "" {
				if resp.StatusCode != http.StatusBadGateway || !strings.Contains(string(body), `"feed-unreachable"`) ||
					!strings.Contains(string(body), "a page rather than audio") {
					t.Errorf("refusal = %d: %s", resp.StatusCode, body)
				}
				if strings.Contains(string(body), c.body) {
					t.Errorf("the host's answer reached the listener: %s", body)
				}
				return
			}
			if resp.StatusCode != 200 || string(body) != c.body {
				t.Errorf("relay = %d: %q", resp.StatusCode, body)
			}
			if got := resp.Header.Get("Content-Type"); got != c.wantType {
				t.Errorf("Content-Type = %q, want %q", got, c.wantType)
			}
		})
	}
}

// hlsPlaylist is a stream playlist naming its one segment on a host the
// feed chose, which a player handed it would fetch itself.
const hlsPlaylist = "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nhttps://tracker.example/visitor-seg1.aac\n#EXT-X-ENDLIST\n"

// An enclosure its feed calls a playlist is never offered for relay, so
// nothing promises audio the relay would only refuse: the row says there
// is none, play-info answers the not-fetched conflict, and no link to it
// is minted.
func TestAnEnclosureItsFeedCallsAPlaylistIsNotRelayed(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	for _, declared := range []string{"audio/x-mpegurl", "application/vnd.apple.mpegurl", "audio/x-scpls"} {
		t.Run(declared, func(t *testing.T) {
			feed := typedEnclosureHost(t, declared, "", hlsPlaylist)
			sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed}), 201, "subscribe")
			ep := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items[0]
			if ep.HasEnclosure != nil && *ep.HasEnclosure {
				t.Errorf("hasEnclosure = true for an enclosure its feed calls %s", declared)
			}
			resp := get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			if resp.StatusCode != http.StatusConflict || strings.Contains(string(body), "/media/enclosure") {
				t.Errorf("play-info = %d: %s", resp.StatusCode, body)
			}
			resp = h.postJSON(t, "/api/v1/shares", map[string]any{"pid": ep.Pid})
			body, _ = io.ReadAll(resp.Body)
			resp.Body.Close()
			if resp.StatusCode != http.StatusConflict {
				t.Errorf("sharing it = %d: %s", resp.StatusCode, body)
			}
		})
	}
}

// relayableMediaTypes are the types play-info may name for a relayed
// episode in these tests.
var relayableMediaTypes = map[string]struct{}{"audio/mpeg": {}, "audio/mp4": {}, "video/mp4": {}}
