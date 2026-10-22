package api

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// scriptedEpisodeHost is a podcast host whose one episode is whatever
// script writes to the raw connection after the request: the framing of
// the answer, and how it ends, are the script's.
func scriptedEpisodeHost(t *testing.T, script func(conn net.Conn, gone <-chan struct{})) string {
	t.Helper()
	var ts *httptest.Server
	mux := http.NewServeMux()
	mux.HandleFunc("/feed.xml", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
<title>Scripted Cast</title>
<description>One episode.</description>
<item>
	<title>Scripted Episode</title>
	<guid isPermaLink="false">scripted-1</guid>
	<pubDate>%s</pubDate>
	<enclosure url="%s/episode" type="audio/mpeg" length="1048576"/>
</item>
</channel></rss>`, time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z), ts.URL)
	})
	gone := make(chan struct{})
	mux.HandleFunc("/episode", func(w http.ResponseWriter, r *http.Request) {
		conn, _, err := w.(http.Hijacker).Hijack()
		if err != nil {
			return
		}
		defer conn.Close()
		script(conn, gone)
	})
	ts = httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	t.Cleanup(func() { close(gone) })
	return ts.URL + "/feed.xml"
}

const (
	chunkedHead  = "HTTP/1.1 200 OK\r\nContent-Type: audio/mpeg\r\nTransfer-Encoding: chunked\r\n\r\n"
	declaredHead = "HTTP/1.1 200 OK\r\nContent-Type: audio/mpeg\r\nContent-Length: %d\r\n\r\n"
	scriptedPart = 64 << 10
)

func writeChunk(conn net.Conn, n int) error {
	if _, err := fmt.Fprintf(conn, "%x\r\n", n); err != nil {
		return err
	}
	if _, err := conn.Write(make([]byte, n)); err != nil {
		return err
	}
	_, err := io.WriteString(conn, "\r\n")
	return err
}

// A relay that stops before the episode is whole breaks the transfer off,
// so the player sees it broken and asks for the rest by range, whether or
// not the host declared a length: a host that dies mid-episode, one that
// goes quiet, and one that runs past the size cap alike. A host that ends
// the episode at its own clean end ends it for the listener too. The
// signed-in relay and a public link's are one relay.
func TestARelayThatStopsShortBreaksTheTransferOff(t *testing.T) {
	t.Parallel()
	type shape struct {
		name   string
		script func(conn net.Conn, gone <-chan struct{})
		bounds func(*relayLimits)
		// whole is the length of an answer that is complete; zero when
		// the listener must see the transfer break.
		whole int
	}
	shapes := []shape{
		{name: "a chunked answer that dies mid-episode", script: func(conn net.Conn, _ <-chan struct{}) {
			io.WriteString(conn, chunkedHead)
			writeChunk(conn, scriptedPart)
		}},
		{name: "a declared-length answer that dies mid-episode", script: func(conn net.Conn, _ <-chan struct{}) {
			fmt.Fprintf(conn, declaredHead, 1<<20)
			conn.Write(make([]byte, scriptedPart))
		}},
		{name: "a chunked answer that ends well", whole: scriptedPart, script: func(conn net.Conn, _ <-chan struct{}) {
			io.WriteString(conn, chunkedHead)
			writeChunk(conn, scriptedPart)
			io.WriteString(conn, "0\r\n\r\n")
		}},
		{name: "a declared-length answer that ends well", whole: scriptedPart, script: func(conn net.Conn, _ <-chan struct{}) {
			fmt.Fprintf(conn, declaredHead, scriptedPart)
			conn.Write(make([]byte, scriptedPart))
		}},
		{name: "a chunked answer gone quiet", bounds: func(l *relayLimits) { l.idle = 200 * time.Millisecond },
			script: func(conn net.Conn, gone <-chan struct{}) {
				io.WriteString(conn, chunkedHead)
				writeChunk(conn, scriptedPart)
				<-gone
			}},
		{name: "a declared-length answer gone quiet", bounds: func(l *relayLimits) { l.idle = 200 * time.Millisecond },
			script: func(conn net.Conn, gone <-chan struct{}) {
				fmt.Fprintf(conn, declaredHead, 1<<20)
				conn.Write(make([]byte, scriptedPart))
				<-gone
			}},
		{name: "an endless chunked answer", bounds: func(l *relayLimits) { l.maxBytes = 256 << 10 },
			script: func(conn net.Conn, _ <-chan struct{}) {
				io.WriteString(conn, chunkedHead)
				for writeChunk(conn, 32<<10) == nil {
				}
			}},
		{name: "a declared-length answer past the cap", bounds: func(l *relayLimits) { l.maxBytes = 256 << 10 },
			script: func(conn net.Conn, _ <-chan struct{}) {
				fmt.Fprintf(conn, declaredHead, 4<<20)
				conn.Write(make([]byte, 4<<20))
			}},
	}
	for _, c := range shapes {
		for _, via := range []string{"the signed-in relay", "a public link"} {
			t.Run(c.name+" through "+via, func(t *testing.T) {
				t.Parallel()
				h := newPodcastHarness(t)
				if c.bounds != nil {
					c.bounds(&h.srv.enclosureBounds)
				}
				_, ep := firstEpisode(t, h, scriptedEpisodeHost(t, c.script), nil)
				url := h.ts.URL + decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)).Url
				if via == "a public link" {
					url = h.ts.URL + shareOf(t, h, ep.Pid, nil).Url + "/stream?i=0"
				}

				ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
				defer cancel()
				resp := openStream(t, ctx, url)
				defer resp.Body.Close()
				body, err := io.ReadAll(resp.Body)
				if resp.StatusCode != http.StatusOK {
					t.Fatalf("relay = %d", resp.StatusCode)
				}
				if c.whole > 0 {
					if err != nil || len(body) != c.whole {
						t.Errorf("a complete answer reached the listener as %d bytes and %v, want %d and no error", len(body), err, c.whole)
					}
					return
				}
				if err == nil {
					t.Errorf("the listener was handed %d bytes as a finished episode", len(body))
				} else if errors.Is(err, context.DeadlineExceeded) {
					t.Errorf("the transfer was still open after 10s: %v", err)
				}
			})
		}
	}
}
