package api

import (
	"context"
	"errors"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// relayWriteStallLimit is how long one write of a share's stream or
// download may wait on a visitor who has stopped reading, where the
// player can resume by range. Unbounded, such a visitor holds the link's
// slots and its owner's for as long as the connection lives; a signed-in
// listener is not held to it, the slots being its own.
const relayWriteStallLimit = time.Minute

// relayWriteStallNoRangeLimit is the same bound where it cannot: a
// response cut there is playback lost, so it waits longer.
const relayWriteStallNoRangeLimit = 15 * time.Minute

// stallBoundChunk is the most that goes to the socket under one deadline,
// a write split or a file sent a stretch at a time to fit: what a
// listener has to drain inside the bound. The relay's own write size, so
// on every path only a listener reading under about 4 kbit/s, slower
// than any podcast plays, can be cut while it reads.
const stallBoundChunk = 32 << 10

// errStreamEnded is a write refused because the stream's reason to run
// is gone: its link was revoked or expired.
var errStreamEnded = errors.New("the stream's link no longer serves")

// stallBoundWriter renews a write deadline before every stretch it
// writes, so a stretch that waits on the listener longer than the stall
// fails and ends the response. The stall is the short one when the
// response says the player can resume by range, and the long one when it
// does not. With live set it also asks, at most once every `every` while
// bytes flow, whether the response should still be going, and ends it
// when not. Unwrap, Flush and ReadFrom keep it a streaming writer with
// the fast file path, as the other wrappers in front of it are.
type stallBoundWriter struct {
	http.ResponseWriter
	rc *http.ResponseController
	// resumable and unresumable are the two stalls; stall is the one in
	// force, chosen once the status goes out. rangeAsked says the request
	// carried a Range, which a 200 answer ignored.
	resumable, unresumable, stall time.Duration
	picked, rangeAsked            bool
	live                          func() bool
	every                         time.Duration
	checked                       time.Time
	ended                         bool
	// expired is the bound run out early, from expire; the one field
	// another goroutine touches.
	expired atomic.Bool
}

// boundWrites wraps a stream's writer in the stall bound, and in the
// liveness check when live is set.
func (s *Server) boundWrites(w http.ResponseWriter, live func() bool) *stallBoundWriter {
	return &stallBoundWriter{
		ResponseWriter: w,
		rc:             http.NewResponseController(w),
		resumable:      s.relayWriteStall,
		unresumable:    s.relayWriteStallNoRange,
		live:           live,
		every:          s.streamRecheckEvery,
		checked:        time.Now(),
	}
}

// expire runs the bound out now, as an elapsed one would: a write blocked
// on the listener fails at once, and the next one fails before it
// starts. Safe from any goroutine while the response is being served,
// and only then: the deadline belongs to a connection the server hands to
// its next request once the handler returns.
func (w *stallBoundWriter) expire() {
	w.expired.Store(true)
	_ = w.rc.SetWriteDeadline(time.Now())
}

// pick chooses the stall from the response going out: the short one when
// its status or headers say byte ranges work, so a paused player can ask
// for the rest on resume. A host that answered a ranged request with the
// whole file has shown they do not, whatever it advertises.
func (w *stallBoundWriter) pick(status int) {
	if w.picked || status < http.StatusOK {
		return
	}
	w.picked = true
	w.stall = w.unresumable
	ignored := w.rangeAsked && status == http.StatusOK
	offered := strings.EqualFold(strings.TrimSpace(w.Header().Get("Accept-Ranges")), "bytes")
	if status == http.StatusPartialContent || (offered && !ignored) {
		w.stall = w.resumable
	}
}

func (w *stallBoundWriter) WriteHeader(code int) {
	w.pick(code)
	w.ResponseWriter.WriteHeader(code)
}

// ready runs before each write: the liveness check when it is due, then
// a fresh deadline.
func (w *stallBoundWriter) ready() error {
	if w.ended {
		return errStreamEnded
	}
	w.pick(http.StatusOK)
	if w.live != nil && time.Since(w.checked) >= w.every {
		w.checked = time.Now()
		if !w.live() {
			w.ended = true
			// Nothing more goes out, the end of a chunked body included,
			// so the listener sees the stream cut rather than finished.
			_ = w.rc.SetWriteDeadline(time.Now())
			return errStreamEnded
		}
	}
	if w.stall > 0 {
		// A writer that cannot take a deadline streams unbounded; the
		// error is not a reason to refuse the stream.
		_ = w.rc.SetWriteDeadline(time.Now().Add(w.stall))
	}
	// After the fresh deadline, so an expiry landing at any moment is
	// either seen here or overrides it.
	if w.expired.Load() {
		_ = w.rc.SetWriteDeadline(time.Now())
		return os.ErrDeadlineExceeded
	}
	return nil
}

// Write sends b a stretch at a time, each under a deadline of its own, so
// a writer above that hands over a large buffer at once holds a slow
// listener to no more than a stretch either.
func (w *stallBoundWriter) Write(b []byte) (int, error) {
	if len(b) == 0 {
		if err := w.ready(); err != nil {
			return 0, err
		}
		return w.ResponseWriter.Write(b)
	}
	var written int
	for len(b) > 0 {
		if err := w.ready(); err != nil {
			return written, err
		}
		n, err := w.ResponseWriter.Write(b[:min(len(b), stallBoundChunk)])
		written += n
		if err != nil {
			return written, err
		}
		b = b[n:]
	}
	return written, nil
}

// ReadFrom keeps sendfile for a file, which http.ServeContent hands over
// under one limit, and still renews the deadline: the file goes out a
// stretch at a time, each under a limit of its own over the file itself,
// since a limit over a limit is no longer a file to the socket.
func (w *stallBoundWriter) ReadFrom(src io.Reader) (int64, error) {
	rf, ok := w.ResponseWriter.(io.ReaderFrom)
	if !ok {
		return io.Copy(writeOnly{w}, src)
	}
	from, left := src, int64(-1)
	if lr, ok := src.(*io.LimitedReader); ok {
		from, left = lr.R, lr.N
		defer func() { lr.N = max(left, 0) }()
	}
	var total int64
	for left != 0 {
		if err := w.ready(); err != nil {
			return total, err
		}
		step := int64(stallBoundChunk)
		if left > 0 {
			step = min(step, left)
		}
		n, err := rf.ReadFrom(io.LimitReader(from, step))
		total += n
		if left > 0 {
			left -= n
		}
		if err != nil || n < step {
			return total, err
		}
	}
	return total, nil
}

func (w *stallBoundWriter) Flush() { _ = w.rc.Flush() }

func (w *stallBoundWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

// writeOnly hides every method but Write, so io.Copy into it cannot find
// a ReadFrom and recurse.
type writeOnly struct{ io.Writer }

// shareTransfers are the share streams and downloads running now, by
// share, so a link that ends can end them without waiting for a write or
// a read to notice.
type shareTransfers struct {
	mu   sync.Mutex
	live map[string]map[*shareTransfer]struct{}
}

// shareTransfer is one running transfer: the writer its bytes go through,
// and the cancel of the request context whatever feeds it reads on.
type shareTransfer struct {
	mu     sync.Mutex
	w      *stallBoundWriter
	cancel context.CancelFunc
	over   bool
}

// end stops the transfer, a blocked write and a blocked read alike, unless
// it is over already: the writer's deadline is the connection's, which
// the next request may be using.
func (t *shareTransfer) end() {
	t.mu.Lock()
	defer t.mu.Unlock()
	if !t.over {
		t.w.expire()
		t.cancel()
	}
}

// finish marks the transfer over, as its handler is about to return.
func (t *shareTransfer) finish() {
	t.mu.Lock()
	t.over = true
	t.mu.Unlock()
	t.cancel()
}

// shareKey is a share's key in the registry whatever case a caller spells
// its pid in: Crockford's alphabet reads either, and the stored spelling
// is upper.
func shareKey(shareID string) string { return strings.ToUpper(shareID) }

// add registers a running transfer of shareID, then asks live whether the
// link still serves and ends the transfer if not, and answers the function
// that ends its registration. The order is the point: a revoke that
// committed before the registration found nothing of the transfer to end
// and is seen by the ask, and one that commits after it finds the
// transfer. A share with an expiry ends its transfers when it comes.
func (s *shareTransfers) add(shareID string, t *shareTransfer, expiresAt time.Time, live func() bool) (remove func()) {
	shareID = shareKey(shareID)
	s.mu.Lock()
	if s.live == nil {
		s.live = map[string]map[*shareTransfer]struct{}{}
	}
	if s.live[shareID] == nil {
		s.live[shareID] = map[*shareTransfer]struct{}{}
	}
	s.live[shareID][t] = struct{}{}
	s.mu.Unlock()
	var expiry *time.Timer
	if !expiresAt.IsZero() {
		expiry = time.AfterFunc(time.Until(expiresAt), t.end)
	}
	if !live() {
		t.end()
	}
	return func() {
		if expiry != nil {
			expiry.Stop()
		}
		s.mu.Lock()
		defer s.mu.Unlock()
		delete(s.live[shareID], t)
		if len(s.live[shareID]) == 0 {
			delete(s.live, shareID)
		}
	}
}

// end stops every transfer running on shareID.
func (s *shareTransfers) end(shareID string) {
	shareID = shareKey(shareID)
	s.mu.Lock()
	running := make([]*shareTransfer, 0, len(s.live[shareID]))
	for t := range s.live[shareID] {
		running = append(running, t)
	}
	s.mu.Unlock()
	for _, t := range running {
		t.end()
	}
}
