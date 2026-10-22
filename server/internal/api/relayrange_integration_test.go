package api

import (
	"fmt"
	"net"
	"net/http"
	"regexp"
	"testing"
)

var unsatisfiedRangeForm = regexp.MustCompile(`^bytes \*/[0-9]+$`)

// A range that starts at or past the end of the audio is refused with the
// length it missed, as RFC 9110 asks, whichever way the audio is served: a
// player re-opening a stream at exactly its length reads the answer as the
// end of the audio rather than as a failure. A podcast host's own word
// for the length passes through; a host that sends none, or sends
// something that is not a length, leaves the refusal without one.
func TestAnUnsatisfiableRangeAnswersWithTheLengthItMissed(t *testing.T) {
	t.Parallel()
	const audio = "ID3fake-mpeg-audio-bytes-for-the-relay"
	refuse := func(header string) func(net.Conn, <-chan struct{}) {
		return func(conn net.Conn, _ <-chan struct{}) {
			fmt.Fprintf(conn, "HTTP/1.1 416 Range Not Satisfiable\r\n%sContent-Length: 0\r\n\r\n", header)
		}
	}
	relays := []struct {
		name, feed string
		want       string // the Content-Range of the refusal; empty: none
	}{
		{"a host that sends the length", typedEnclosureHost(t, "audio/mpeg", "audio/mpeg", audio), fmt.Sprintf("bytes */%d", len(audio))},
		{"a host that sends none", scriptedEpisodeHost(t, refuse("")), ""},
		{"a host that sends something else", scriptedEpisodeHost(t, refuse("Content-Range: bytes 0-9/*\r\n")), ""},
		{"a host that sends a bad length", scriptedEpisodeHost(t, refuse("Content-Range: bytes */many\r\n")), ""},
	}
	h := newPodcastHarness(t)
	for _, c := range relays {
		_, ep := firstEpisode(t, h, c.feed, nil)
		relay := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)).Url
		link := shareOf(t, h, ep.Pid, nil).Url + "/stream?i=0"
		for via, url := range map[string]string{"the signed-in relay": relay, "a public link": link} {
			resp, _ := relayAs(t, h, http.MethodGet, url, "bytes=9999-")
			if resp.StatusCode != http.StatusRequestedRangeNotSatisfiable {
				t.Errorf("%s, %s: %d, want 416", c.name, via, resp.StatusCode)
			}
			if got := resp.Header.Get("Content-Range"); got != c.want {
				t.Errorf("%s, %s: Content-Range = %q, want %q", c.name, via, got, c.want)
			}
		}
	}

	for _, c := range []struct {
		name   string
		harner func(*testing.T) *harness
	}{
		{"audio from the file", newHarnessDirect},
		{"audio through the engine", func(t *testing.T) *harness { return newHarness(t) }},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			h := c.harner(t)
			track := h.items(t, "?mediaType=music").Items[0]
			play := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+track.Pid+"/play-info", h.token)).Url
			link := shareOf(t, h, track.Pid, nil).Url + "/stream?i=0"
			for via, url := range map[string]string{"the signed-in stream": play, "a public link": link} {
				resp, _ := relayAs(t, h, http.MethodGet, url, "bytes=999999999-")
				if resp.StatusCode != http.StatusRequestedRangeNotSatisfiable {
					t.Errorf("%s: %d, want 416", via, resp.StatusCode)
				}
				if got := resp.Header.Get("Content-Range"); !unsatisfiedRangeForm.MatchString(got) {
					t.Errorf("%s: Content-Range = %q, want bytes */<length>", via, got)
				}
			}
		})
	}
}
