package api

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"testing"
	"time"
)

// newEndlessFeed is a podcast host whose first episode never ends: its
// audio streams for as long as somebody takes it, a chunk every pace.
// Each of the others sends a little audio and then holds the response
// open until the test ends.
func newEndlessFeed(t *testing.T, episodes int, pace time.Duration) *feedServer {
	t.Helper()
	fs := newFeedServer(t, episodes)
	files := http.FileServer(http.Dir(fs.dir))
	chunk := bytes.Repeat([]byte{0xff}, 32<<10)
	done := make(chan struct{})
	t.Cleanup(func() { close(done) })
	held := map[string]bool{}
	for _, f := range fs.files[1:] {
		held["/"+f] = true
	}
	fs.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/"+fs.files[0]:
			w.Header().Set("Content-Type", "audio/mpeg")
			for r.Context().Err() == nil {
				if _, err := w.Write(chunk); err != nil {
					return
				}
				if pace > 0 {
					time.Sleep(pace)
				}
			}
		case held[r.URL.Path]:
			w.Header().Set("Content-Type", "audio/mpeg")
			w.Write(chunk[:4096])
			w.(http.Flusher).Flush()
			select {
			case <-done:
			case <-r.Context().Done():
			}
		default:
			files.ServeHTTP(w, r)
		}
	})
	return fs
}

// newRangedEndlessFeed is newEndlessFeed with a host that says it takes
// ranges, which is what a player reads to know it can resume.
func newRangedEndlessFeed(t *testing.T, episodes int, pace time.Duration) *feedServer {
	t.Helper()
	fs := newEndlessFeed(t, episodes, pace)
	endless := fs.ts.Config.Handler
	fs.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Accept-Ranges", "bytes")
		endless.ServeHTTP(w, r)
	})
	return fs
}

// episodesByTitle lists a show's episodes by title.
func episodesByTitle(t *testing.T, h *harness, feedURL string) map[string]EpisodeSummary {
	t.Helper()
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feedURL}), 201, "subscribing to "+feedURL)
	out := map[string]EpisodeSummary{}
	for _, ep := range decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)).Items {
		out[ep.Title] = ep
	}
	return out
}

// stalledVisitor asks the server at base for a stream, reads its status
// line, and never reads another byte of it.
func stalledVisitor(t *testing.T, base, path string) {
	t.Helper()
	host := strings.TrimPrefix(base, "http://")
	conn, err := net.Dial("tcp", host)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	if tcp, ok := conn.(*net.TCPConn); ok {
		tcp.SetReadBuffer(4 << 10)
	}
	if _, err := fmt.Fprintf(conn, "GET %s HTTP/1.1\r\nHost: %s\r\n\r\n", path, host); err != nil {
		t.Fatal(err)
	}
	status, err := bufio.NewReaderSize(conn, 64).ReadString('\n')
	if err != nil || !strings.Contains(status, " 200 ") {
		t.Fatalf("a visitor's stream = %q, %v; want 200", status, err)
	}
}

// streamStatus opens a stream, answers its status and lets it go at once.
func streamStatus(t *testing.T, url string) int {
	t.Helper()
	resp := openStream(t, context.Background(), url)
	resp.Body.Close()
	return resp.StatusCode
}

// waitForStatus polls a stream until it answers want, or fails after the
// timeout.
func waitForStatus(t *testing.T, url string, want int, timeout time.Duration, what string) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for {
		got := streamStatus(t, url)
		if got == want {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("%s: still %d after %v, want %d", what, got, timeout, want)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// holdShareWriters makes the stall bounds an hour, so a stalled visitor
// stays stalled for as long as a test needs.
func holdShareWriters(h *harness) {
	h.srv.relayWriteStall = time.Hour
	h.srv.relayWriteStallNoRange = time.Hour
}

// expireShareWriters runs out the bound of every share writer running, as
// an elapsed one would, so no assertion races a clock.
func expireShareWriters(h *harness) {
	h.srv.shareTransfers.mu.Lock()
	defer h.srv.shareTransfers.mu.Unlock()
	for _, running := range h.srv.shareTransfers.live {
		for t := range running {
			t.w.expire()
		}
	}
}

// Visitors who open a link's stream and stop reading give their slots
// back once a write has waited the bound out, the link's and its owner's
// both, rather than holding them for as long as the connection lives.
func TestVisitorsWhoStopReadingLetGoOfTheirSlots(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	holdShareWriters(h)
	eps := episodesByTitle(t, h, newEndlessFeed(t, 2, 0).feedURL())
	link := h.ts.URL + shareOf(t, h, eps["Episode 1"].Pid, nil).Url + "/stream?i=0"
	relay := h.ts.URL + decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+eps["Episode 2"].Pid+"/play-info", h.token)).Url

	for range maxShareStreams {
		stalledVisitor(t, h.ts.URL, strings.TrimPrefix(link, h.ts.URL))
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	for i := range maxUserRelays - maxShareStreams {
		resp := openStream(t, ctx, relay)
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("the owner's relay %d = %d, want 200", i+1, resp.StatusCode)
		}
	}
	if got := streamStatus(t, link); got != http.StatusTooManyRequests {
		t.Fatalf("the link while four visitors hold it = %d, want 429", got)
	}
	if got := streamStatus(t, relay); got != http.StatusTooManyRequests {
		t.Fatalf("the owner's relay while visitors hold half the slots = %d, want 429", got)
	}
	expireShareWriters(h)
	waitForStatus(t, relay, http.StatusOK, 15*time.Second, "the owner's relay once the visitors' bound ran out")
	waitForStatus(t, link, http.StatusOK, 15*time.Second, "the link once its visitors' bound ran out")
}

// Revoking a link ends a stream flowing on it at once, not at the next
// link check (an hour off here) and not when the episode ends.
func TestRevokingALinkEndsItsTransfers(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	h.srv.streamRecheckEvery = time.Hour
	share := shareOf(t, h, episodesByTitle(t, h, newEndlessFeed(t, 1, 5*time.Millisecond).feedURL())["Episode 1"].Pid, nil)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	resp := openStream(t, ctx, h.ts.URL+share.Url+"/stream?i=0")
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("stream = %d", resp.StatusCode)
	}
	if _, err := io.ReadFull(resp.Body, make([]byte, 64<<10)); err != nil {
		t.Fatalf("the stream did not start: %v", err)
	}

	wantStatus(t, h.deleteReq(t, "/api/v1/shares/"+share.Pid), 204, "revoking the link")
	ended := make(chan struct{})
	go func() {
		io.Copy(io.Discard, resp.Body)
		close(ended)
	}()
	select {
	case <-ended:
	case <-time.After(5 * time.Second):
		t.Fatal("the transfer was still running 5s after its link was revoked")
	}
}

// Every public link of one owner together draws fewer relays than the
// owner has, so the owner's own listening and radio always keep some,
// however many visitors the links have.
func TestAnOwnersLinksLeaveTheOwnerRelaySlots(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	held := episodesByTitle(t, h, newEndlessFeed(t, 2, 0).feedURL())["Episode 2"]
	first := h.ts.URL + shareOf(t, h, held.Pid, nil).Url + "/stream?i=0"
	second := h.ts.URL + shareOf(t, h, held.Pid, nil).Url + "/stream?i=0"
	relay := h.ts.URL + decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+held.Pid+"/play-info", h.token)).Url
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	hold := func(url, what string) {
		t.Helper()
		resp := openStream(t, ctx, url)
		t.Cleanup(func() { resp.Body.Close() })
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("%s = %d, want 200", what, resp.StatusCode)
		}
	}
	for i := range maxShareStreams {
		hold(first, fmt.Sprintf("the first link's visitor %d", i+1))
	}
	for i := range maxOwnerShareRelays - maxShareStreams {
		hold(second, fmt.Sprintf("the second link's visitor %d", i+1))
	}
	if got := streamStatus(t, second); got != http.StatusTooManyRequests {
		t.Errorf("a visitor past the owner's allowance for links = %d, want 429", got)
	}
	for i := range maxUserRelays - maxOwnerShareRelays {
		hold(relay, fmt.Sprintf("the owner's own relay %d", i+1))
	}
	if got := streamStatus(t, relay); got != http.StatusTooManyRequests {
		t.Errorf("the owner's relay past every slot = %d, want 429", got)
	}
}
