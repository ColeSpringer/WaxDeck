package api

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	neturl "net/url"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// tightListener keeps each accepted connection's send buffer small, so a
// reader's pace reaches the handler's writes at once rather than after
// megabytes of kernel buffering.
type tightListener struct{ net.Listener }

func (l tightListener) Accept() (net.Conn, error) {
	c, err := l.Listener.Accept()
	if tc, ok := c.(*net.TCPConn); ok {
		tc.SetWriteBuffer(16 << 10)
	}
	return c, err
}

// tightServer serves a harness's enclosure relay and share media routes
// on a tightListener, answering its base URL.
func tightServer(t *testing.T, h *harness) string {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("GET /media/enclosure", h.srv.ServeEnclosure)
	mux.HandleFunc("GET /s/{token}/stream", h.srv.ServeShareStream)
	mux.HandleFunc("GET /s/{token}/download", h.srv.ServeShareDownload)
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewUnstartedServer(mux)
	ts.Listener.Close()
	ts.Listener = tightListener{ln}
	ts.Start()
	t.Cleanup(ts.Close)
	return ts.URL
}

// pacedRead asks for url on a connection with a small receive buffer,
// waits out pause once the answer's head is in, then reads the body at
// rate bytes a second (zero: as fast as it comes) until it ends or limit
// bytes are in. It answers the status (zero when there was none), the
// bytes read and how the body ended: nil when it ran to its end or to
// limit. Safe off the test's goroutine.
func pacedRead(url string, pause time.Duration, rate int, limit int64) (int, int64, error) {
	u, err := neturl.Parse(url)
	if err != nil {
		return 0, 0, err
	}
	conn, err := net.Dial("tcp", u.Host)
	if err != nil {
		return 0, 0, err
	}
	defer conn.Close()
	if tcp, ok := conn.(*net.TCPConn); ok {
		tcp.SetReadBuffer(64 << 10)
	}
	if _, err := fmt.Fprintf(conn, "GET %s HTTP/1.1\r\nHost: %s\r\n\r\n", u.RequestURI(), u.Host); err != nil {
		return 0, 0, err
	}
	resp, err := http.ReadResponse(bufio.NewReader(conn), nil)
	if err != nil {
		return 0, 0, err
	}
	time.Sleep(pause)
	buf := make([]byte, 16<<10)
	var step time.Duration
	if rate > 0 {
		step = time.Second * time.Duration(len(buf)) / time.Duration(rate)
	}
	var got int64
	for got < limit {
		n, err := io.ReadFull(resp.Body, buf[:min(int64(len(buf)), limit-got)])
		got += int64(n)
		if err == io.EOF || (err == io.ErrUnexpectedEOF && n < len(buf) && got == resp.ContentLength) {
			return resp.StatusCode, got, nil
		}
		if err != nil {
			return resp.StatusCode, got, err
		}
		time.Sleep(step)
	}
	return resp.StatusCode, got, nil
}

// longTrack adds a track of about 2.3 MB, more than any socket buffer
// here holds, to a harness's library, answering its pid and its size.
func longTrack(t *testing.T, h *harness) (string, int64) {
	t.Helper()
	paths, err := fixtures.Generate(h.library, fixtures.Spec{
		Name: "long-track", Codec: fixtures.CodecPCM, Duration: 3 * time.Second, SampleRate: 192000,
	})
	if err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	for _, it := range h.items(t, "?mediaType=music&limit=200").Items {
		if it.Title == "long-track" || it.Title == filepath.Base(paths[0]) {
			return it.Pid, info.Size()
		}
	}
	t.Fatal("the long track is not in the library")
	return "", 0
}

// A signed-in listener may pause for as long as it likes: the slots its
// relay holds are its own, and the spec promises a paused player is never
// a reason to be cut. A link's anonymous visitor pausing as long is let
// go, so the link's and its owner's slots come back.
func TestASignedInRelayRidesOutAPauseThatEndsAShareStream(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	h.srv.relayWriteStall = 300 * time.Millisecond
	base := tightServer(t, h)
	ep := episodesByTitle(t, h, newRangedEndlessFeed(t, 1, 0).feedURL())["Episode 1"]
	relay := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)).Url
	link := shareOf(t, h, ep.Pid, nil).Url + "/stream?i=0"
	// More than every buffer between the two ends holds, so a stream
	// that was cut cannot deliver it from what was already in flight.
	const after = 512 << 10

	status, got, err := pacedRead(base+relay, 5*h.srv.relayWriteStall, 0, after)
	if status != http.StatusOK || err != nil || got != after {
		t.Errorf("a signed-in relay after a pause = %d, %d bytes, %v; want 200 and the stream going on", status, got, err)
	}
	status, got, err = pacedRead(base+link, 5*h.srv.relayWriteStall, 0, after)
	if status != http.StatusOK || err == nil {
		t.Errorf("a share stream after the same pause = %d, %d bytes, %v; want it cut", status, got, err)
	}
}

// A visitor who has stopped reading is let go after the stall bound where
// the player can resume by range, as it does after any dropped connection.
// Where it cannot, as with a host that ignores ranges or a live encode,
// cutting the response loses the playback, so the wait is the longer bound.
func TestAPausedVisitorIsLetGoSoonOnlyWhereThePlayerCanResume(t *testing.T) {
	t.Parallel()
	const after = 512 << 10
	for _, c := range []struct {
		name  string
		pid   func(*testing.T) (*harness, string)
		pause time.Duration
		cut   bool
	}{
		{"a file that takes ranges", func(t *testing.T) (*harness, string) {
			h := newHarnessDirect(t)
			pid, _ := longTrack(t, h)
			return h, pid
		}, 2 * time.Second, true},
		{"audio relayed from a host that takes ranges", func(t *testing.T) (*harness, string) {
			h := newPodcastHarness(t)
			return h, episodesByTitle(t, h, newRangedEndlessFeed(t, 1, 0).feedURL())["Episode 1"].Pid
		}, 2 * time.Second, true},
		{"audio relayed from a host that ignores ranges", func(t *testing.T) (*harness, string) {
			h := newPodcastHarness(t)
			return h, episodesByTitle(t, h, newEndlessFeed(t, 1, 0).feedURL())["Episode 1"].Pid
		}, time.Second, false},
		{"audio relayed from a host that ignores ranges, paused past the longer bound", func(t *testing.T) (*harness, string) {
			h := newPodcastHarness(t)
			return h, episodesByTitle(t, h, newEndlessFeed(t, 1, 0).feedURL())["Episode 1"].Pid
		}, 5 * time.Second, true},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			h, pid := c.pid(t)
			h.srv.relayWriteStall = 300 * time.Millisecond
			h.srv.relayWriteStallNoRange = 3 * time.Second
			base := tightServer(t, h)
			status, got, err := pacedRead(base+shareOf(t, h, pid, nil).Url+"/stream?i=0", c.pause, 0, after)
			switch {
			case status != http.StatusOK:
				t.Errorf("stream = %d", status)
			case c.cut && err == nil:
				t.Errorf("a visitor paused %v read %d bytes of a stream that should have been cut", c.pause, got)
			case !c.cut && (err != nil || got != after):
				t.Errorf("a visitor paused %v read %d bytes, %v; want the stream going on", c.pause, got, err)
			}
		})
	}
}

// A listener who reads steadily at the pace audio plays is never cut, on
// every path a link's audio takes: the deadline covers a small stretch,
// not a stretch a slow reader cannot drain in time. Scaled: a three-second
// bound against a reader at a quarter of a megabyte a second stands for
// the minute against a podcast's real-time rate, with seconds to spare
// for a stalled box, and a megabyte and a half is more than any one
// stretch.
func TestASteadySlowListenerIsNeverCut(t *testing.T) {
	t.Parallel()
	const rate, limit = 256 << 10, 3 << 19
	for _, c := range []struct {
		name    string
		harness func(*testing.T) *harness
		relay   bool
	}{
		{"the file, without the engine", newHarnessDirect, false},
		{"the engine", func(t *testing.T) *harness { return newHarness(t) }, false},
		{"the relay", newPodcastHarness, true},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			h := c.harness(t)
			h.srv.relayWriteStall = 3 * time.Second
			base := tightServer(t, h)
			var pid string
			if c.relay {
				pid = episodesByTitle(t, h, newRangedEndlessFeed(t, 1, 0).feedURL())["Episode 1"].Pid
			} else {
				pid, _ = longTrack(t, h)
			}
			status, got, err := pacedRead(base+shareOf(t, h, pid, nil).Url+"/stream?i=0", 0, rate, limit)
			if status != http.StatusOK || err != nil {
				t.Errorf("a steady reader at %d KB/s = %d after %d bytes: %v", rate>>10, status, got, err)
			}
		})
	}
}

// A share's download takes one of the link's slots as a stream does, and
// a visitor who stops reading it gives the slot back once a write has
// waited the bound out.
func TestAStalledDownloadLetsGoOfItsLink(t *testing.T) {
	t.Parallel()
	h := newHarnessDirect(t)
	holdShareWriters(h)
	base := tightServer(t, h)
	pid, _ := longTrack(t, h)
	share := shareOf(t, h, pid, map[string]any{"allowDownload": true})
	for range maxShareStreams {
		stalledVisitor(t, base, share.Url+"/download?i=0")
	}
	if got := streamStatus(t, base+share.Url+"/stream?i=0"); got != http.StatusTooManyRequests {
		t.Fatalf("the link while four downloads hold it = %d, want 429", got)
	}
	expireShareWriters(h)
	waitForStatus(t, base+share.Url+"/download?i=0", http.StatusOK, 15*time.Second, "the link once its downloads' bound ran out")
}

// Revoking a link ends a download already running on it, as it ends a
// stream, without waiting for a link check (an hour off here).
func TestRevokingALinkEndsItsDownloads(t *testing.T) {
	t.Parallel()
	h := newHarnessDirect(t)
	h.srv.streamRecheckEvery = time.Hour
	base := tightServer(t, h)
	pid, size := longTrack(t, h)
	share := shareOf(t, h, pid, map[string]any{"allowDownload": true})
	type result struct {
		got int64
		err error
	}
	done := make(chan result, 1)
	go func() {
		_, got, err := pacedRead(base+share.Url+"/download?i=0", 0, 256<<10, size+1)
		done <- result{got, err}
	}()
	time.Sleep(300 * time.Millisecond)
	wantStatus(t, h.deleteReq(t, "/api/v1/shares/"+share.Pid), 204, "revoking the link")
	select {
	case r := <-done:
		if r.err == nil || r.got >= size {
			t.Errorf("the download after its link was revoked got %d of %d bytes, %v; want it cut", r.got, size, r.err)
		}
	case <-time.After(15 * time.Second):
		t.Fatal("the download was still running 15s after its link was revoked")
	}
}
