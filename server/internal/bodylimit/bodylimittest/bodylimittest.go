// Package bodylimittest measures, over a real connection, how far a
// server read into a body longer than it accepts before it answered.
// Only a real connection shows it: what stops the read is net/http's own
// writer, which a recorder is not.
package bodylimittest

import (
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

// Tolerated is how far past its limit a server may have read a streamed
// body by the time it refuses it: the request's head, the chunk framing
// and a buffer's read-ahead, about 10 KB for a 24 MB limit. A server never
// told the limit was passed reads a further 256 KB of the body first,
// looking for its end.
const Tolerated = 64 << 10

// excess is how much longer than its limit the body sent is: past
// everything a server might read on for.
const excess = 4 << 20

// Overrun sends handler one request whose body is streamed, no length
// declared, and far longer than limit, and answers how many bytes past
// limit the server had read off the connection when it began its answer.
// newRequest builds the request around filler, the endless inside of
// whatever the body is.
//
// What the server reads after answering is not counted: that is up to
// 256 KB of whatever the client still sends, which net/http reads of any
// unfinished body as it closes it.
func Overrun(t testing.TB, handler http.Handler, limit int64, newRequest func(url string, filler io.Reader) *http.Request) int64 {
	t.Helper()
	counts := &counts{}
	ts := httptest.NewUnstartedServer(handler)
	ts.Listener = countingListener{ts.Listener, counts}
	ts.Start()
	// For a caller's newRequest that fails the test; closing twice is fine.
	defer ts.Close()

	req := newRequest(ts.URL, io.LimitReader(letters{}, limit+excess))
	req.ContentLength = -1
	transport := &http.Transport{}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport}
	// The server hangs up with the body still going out, which a client
	// may report as a failed request: what the server read is the measure.
	if resp, err := client.Do(req); err == nil {
		_, _ = io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
	}
	// Waits for the connection to be done with.
	ts.Close()

	if !counts.answered.Load() {
		t.Fatal("the server never answered")
	}
	got := counts.readAtAnswer.Load()
	if got < limit {
		t.Fatalf("the server answered %d bytes in, short of the %d-byte limit: the body never reached what bounds it", got, limit)
	}
	return got - limit
}

// Behind serves next through a writer that wraps the server's own, as a
// middleware's does: the metrics, CORS and API writers.
func Behind(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		next.ServeHTTP(wrapping{w}, r)
	})
}

type wrapping struct{ http.ResponseWriter }

func (w wrapping) Unwrap() http.ResponseWriter { return w.ResponseWriter }

// letters reads as letters without end: the inside of a JSON string, or
// of any body a reader takes whole.
type letters struct{}

func (letters) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = 'a'
	}
	return len(p), nil
}

// counts is what the server has read off its connection, and what it had
// read when it first wrote to it.
type counts struct {
	read, readAtAnswer atomic.Int64
	answered           atomic.Bool
}

type countingListener struct {
	net.Listener
	counts *counts
}

func (l countingListener) Accept() (net.Conn, error) {
	c, err := l.Listener.Accept()
	if err != nil {
		return nil, err
	}
	return &countingConn{Conn: c, counts: l.counts}, nil
}

type countingConn struct {
	net.Conn
	counts *counts
}

func (c *countingConn) Read(p []byte) (int, error) {
	n, err := c.Conn.Read(p)
	c.counts.read.Add(int64(n))
	return n, err
}

func (c *countingConn) Write(p []byte) (int, error) {
	if c.counts.answered.CompareAndSwap(false, true) {
		c.counts.readAtAnswer.Store(c.counts.read.Load())
	}
	return c.Conn.Write(p)
}
