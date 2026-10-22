package api

import (
	"bytes"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// unwrapOnly is a middleware writer that claims nothing but Unwrap, the
// shape a wrapper added in front of these may well take.
type unwrapOnly struct{ w http.ResponseWriter }

func (u unwrapOnly) Header() http.Header         { return u.w.Header() }
func (u unwrapOnly) Write(b []byte) (int, error) { return u.w.Write(b) }
func (u unwrapOnly) WriteHeader(code int)        { u.w.WriteHeader(code) }
func (u unwrapOnly) Unwrap() http.ResponseWriter { return u.w }

// A share stream's writers flush through whatever stands between them
// and the real writer, which the engine's proxy relies on to deliver
// audio as it arrives.
func TestShareStreamWritersFlushThroughWrappers(t *testing.T) {
	t.Parallel()
	rec := httptest.NewRecorder()
	(&sharePlayCounter{ResponseWriter: unwrapOnly{rec}}).Flush()
	if !rec.Flushed {
		t.Error("the play counter's flush stopped at a wrapper")
	}
	rec = httptest.NewRecorder()
	(&Server{}).boundWrites(unwrapOnly{rec}, nil).Flush()
	if !rec.Flushed {
		t.Error("the stall bound's flush stopped at a wrapper")
	}
}

// handedFrom is a writer whose ReadFrom notes what it was handed, and
// for a limit, how far it reached when handed.
type handedFrom struct {
	http.ResponseWriter
	handed []io.Reader
	limits []int64
}

func (h *handedFrom) ReadFrom(src io.Reader) (int64, error) {
	h.handed = append(h.handed, src)
	if lr, ok := src.(*io.LimitedReader); ok {
		h.limits = append(h.limits, lr.N)
	} else {
		h.limits = append(h.limits, -1)
	}
	return io.Copy(h.ResponseWriter, src)
}

// A file sent through a share stream's writers reaches the writer below
// as the file under a limit, the form sendfile takes, a short stretch at
// a time: the stall bound renews its deadline between stretches, so a
// stretch is what a slow listener must drain inside the bound.
func TestShareStreamWritersKeepTheFilePath(t *testing.T) {
	t.Parallel()
	want := bytes.Repeat([]byte("0123456789abcdef"), (5<<20)/16)
	path := filepath.Join(t.TempDir(), "episode.mp3")
	if err := os.WriteFile(path, want, 0o644); err != nil {
		t.Fatal(err)
	}
	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	rec := httptest.NewRecorder()
	below := &handedFrom{ResponseWriter: rec}
	counter := &sharePlayCounter{ResponseWriter: (&Server{}).boundWrites(below, nil)}
	size := int64(len(want)) - 100
	if n, err := io.CopyN(counter, f, size); n != size || err != nil {
		t.Fatalf("copied %d, %v; want %d", n, err, size)
	}
	if !bytes.Equal(rec.Body.Bytes(), want[:size]) {
		t.Error("the bytes that arrived are not the file's")
	}
	if len(below.handed) < 2 {
		t.Fatalf("the file went below in %d stretches, want it in short ones", len(below.handed))
	}
	for i, src := range below.handed {
		lr, ok := src.(*io.LimitedReader)
		if !ok || lr.R != f {
			t.Errorf("stretch %d went below as %T, want a limit over the file", i, src)
		} else if below.limits[i] > 32<<10 {
			t.Errorf("stretch %d is %d bytes, more than a slow listener drains inside the bound", i, below.limits[i])
		}
	}
}

// writeSizes is a writer that notes the size of every write it is given.
type writeSizes struct {
	http.ResponseWriter
	sizes []int
}

func (w *writeSizes) Write(b []byte) (int, error) {
	w.sizes = append(w.sizes, len(b))
	return w.ResponseWriter.Write(b)
}

// A large write goes below in short ones, each under a deadline of its
// own, so a writer above that hands over a big buffer at once holds a
// slow listener to no more than a stretch either.
func TestABoundStreamSplitsALargeWrite(t *testing.T) {
	t.Parallel()
	rec := httptest.NewRecorder()
	below := &writeSizes{ResponseWriter: rec}
	big := bytes.Repeat([]byte{0xff}, 1<<20)
	if n, err := (&Server{}).boundWrites(below, nil).Write(big); n != len(big) || err != nil {
		t.Fatalf("wrote %d, %v; want %d", n, err, len(big))
	}
	if !bytes.Equal(rec.Body.Bytes(), big) {
		t.Error("the bytes that arrived are not the ones written")
	}
	for i, size := range below.sizes {
		if size > 32<<10 {
			t.Errorf("write %d went below as %d bytes, more than a slow listener drains inside the bound", i, size)
		}
	}
}

// An expiry that lands before a write, or between two, fails the next one
// as a bound that ran out would, though no write was blocked when it
// landed. The recorder takes no deadline, so only the expiry can fail it.
func TestAnExpiredBoundFailsTheNextWrite(t *testing.T) {
	t.Parallel()
	early := (&Server{relayWriteStall: time.Hour}).boundWrites(httptest.NewRecorder(), nil)
	early.expire()
	if _, err := early.Write([]byte("audio")); !errors.Is(err, os.ErrDeadlineExceeded) {
		t.Errorf("the first write after an expiry = %v, want os.ErrDeadlineExceeded", err)
	}
	between := (&Server{relayWriteStall: time.Hour}).boundWrites(httptest.NewRecorder(), nil)
	if _, err := between.Write([]byte("audio")); err != nil {
		t.Fatalf("a write before the expiry: %v", err)
	}
	between.expire()
	if _, err := between.Write([]byte("audio")); !errors.Is(err, os.ErrDeadlineExceeded) {
		t.Errorf("a write after an expiry between two = %v, want os.ErrDeadlineExceeded", err)
	}
}

// A stream with a liveness check stops at the first write after the
// check says no, and stays stopped without asking again.
func TestABoundStreamStopsWhenItsLinkEnds(t *testing.T) {
	t.Parallel()
	asked, live := 0, true
	w := (&Server{}).boundWrites(httptest.NewRecorder(), func() bool { asked++; return live })
	if _, err := w.Write([]byte("audio")); err != nil {
		t.Fatalf("a write while the link serves: %v", err)
	}
	live = false
	for range 2 {
		if _, err := w.Write([]byte("audio")); !errors.Is(err, errStreamEnded) {
			t.Fatalf("a write after the link ended: %v, want errStreamEnded", err)
		}
	}
	if asked != 2 {
		t.Errorf("the link was checked %d times, want 2", asked)
	}
}

// The stall bound is the short one only for a response the player can
// resume by range, which its headers say: byte ranges offered, or a ranged
// answer. A response that says none, or nothing, or answered a ranged
// request with the whole file, waits the longer bound, chosen when the
// status goes out or at the first write.
func TestTheStallBoundWaitsLongerWhereThePlayerCannotResume(t *testing.T) {
	t.Parallel()
	s := &Server{relayWriteStall: time.Second, relayWriteStallNoRange: time.Hour}
	for _, c := range []struct {
		name       string
		header     map[string]string
		rangeAsked bool
		status     int
		want       time.Duration
	}{
		{"a file that takes ranges", map[string]string{"Accept-Ranges": "bytes"}, false, http.StatusOK, time.Second},
		{"a ranged answer", nil, true, http.StatusPartialContent, time.Second},
		{"a live encode", map[string]string{"Accept-Ranges": "none"}, false, http.StatusOK, time.Hour},
		{"an answer that says nothing of ranges", nil, false, http.StatusOK, time.Hour},
		{"a host that offers ranges and ignored one", map[string]string{"Accept-Ranges": "bytes"}, true, http.StatusOK, time.Hour},
	} {
		for _, explicit := range []bool{true, false} {
			rec := httptest.NewRecorder()
			w := s.boundWrites(rec, nil)
			w.rangeAsked = c.rangeAsked
			for k, v := range c.header {
				w.Header().Set(k, v)
			}
			if explicit {
				w.WriteHeader(c.status)
			}
			if _, err := w.Write([]byte("audio")); err != nil {
				t.Fatal(err)
			}
			want := c.want
			if !explicit && c.status != http.StatusOK {
				want = time.Hour // an unannounced status is a 200
			}
			if w.stall != want {
				t.Errorf("%s (status announced: %v): stall = %v, want %v", c.name, explicit, w.stall, want)
			}
		}
	}
}

// deadlineRecorder is a response writer that notes the write deadlines set
// on its connection.
type deadlineRecorder struct {
	http.ResponseWriter
	deadlines []time.Time
}

func (d *deadlineRecorder) SetWriteDeadline(t time.Time) error {
	d.deadlines = append(d.deadlines, t)
	return nil
}

// A transfer is ended while it is being served and not after: the write
// deadline is the connection's, which the server hands to the next request
// once the handler has returned.
func TestAnEndedTransferLeavesTheConnectionAlone(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name     string
		over     bool
		deadline int
	}{
		{"while it is served", false, 1},
		{"once it is over", true, 0},
	} {
		rec := &deadlineRecorder{ResponseWriter: httptest.NewRecorder()}
		cancelled := false
		tr := &shareTransfer{w: (&Server{}).boundWrites(rec, nil), cancel: func() { cancelled = true }}
		if c.over {
			tr.finish()
			cancelled = false
		}
		tr.end()
		if len(rec.deadlines) != c.deadline || cancelled != !c.over {
			t.Errorf("ended %s: %d deadlines set and cancelled = %v, want %d and %v",
				c.name, len(rec.deadlines), cancelled, c.deadline, !c.over)
		}
	}
}

// serving is the answer of a link that still serves.
func serving() bool { return true }

// A transfer is registered before its link is asked about, and ended if
// the link no longer serves: a revoke that committed before the
// registration found nothing of the transfer to end, so the ask has to
// follow the registration to see it, and one that commits after the
// registration finds the transfer.
func TestAShareTransferIsRegisteredBeforeItsLinkIsAsked(t *testing.T) {
	t.Parallel()
	const link = "01JZX5N8QW3F4V9T2B7KDEXAMP"
	for _, linkServes := range []bool{true, false} {
		var transfers shareTransfers
		ended := false
		tr := &shareTransfer{w: (&Server{}).boundWrites(httptest.NewRecorder(), nil), cancel: func() { ended = true }}
		registered := false
		transfers.add(link, tr, time.Time{}, func() bool {
			transfers.mu.Lock()
			defer transfers.mu.Unlock()
			_, registered = transfers.live[shareKey(link)][tr]
			return linkServes
		})
		if !registered {
			t.Errorf("link serving = %v: the transfer was not registered when its link was asked about", linkServes)
		}
		if ended == linkServes {
			t.Errorf("link serving = %v: transfer ended = %v", linkServes, ended)
		}
	}
}

// The registry keeps a transfer only while it runs, and ends only the
// transfers of the share asked about.
func TestShareTransfersAreEndedPerShareAndForgottenWhenOver(t *testing.T) {
	t.Parallel()
	var transfers shareTransfers
	ended := map[string]bool{}
	start := func(share string) func() {
		tr := &shareTransfer{w: (&Server{}).boundWrites(httptest.NewRecorder(), nil), cancel: func() { ended[share] = true }}
		return transfers.add(share, tr, time.Time{}, serving)
	}
	removeA, removeB := start("a"), start("b")
	transfers.end("a")
	if !ended["a"] || ended["b"] {
		t.Errorf("ending a share ended %v", ended)
	}
	transfers.end("unknown")
	removeA()
	removeB()
	if len(transfers.live) != 0 {
		t.Errorf("transfers that are over are still held: %v", transfers.live)
	}
}

// A share is one registry key whatever case a caller spells its pid in:
// Crockford's alphabet reads either, and the stored spelling is upper.
func TestShareTransfersAreKeyedWhateverTheCaseOfThePid(t *testing.T) {
	t.Parallel()
	var transfers shareTransfers
	ended := false
	tr := &shareTransfer{w: (&Server{}).boundWrites(httptest.NewRecorder(), nil), cancel: func() { ended = true }}
	remove := transfers.add("01JZX5N8QW3F4V9T2B7KDEXAMP", tr, time.Time{}, serving)
	transfers.end("01jzx5n8qw3f4v9t2b7kdexamp")
	if !ended {
		t.Error("ending a share by its lower-case pid left its transfer running")
	}
	remove()
	if len(transfers.live) != 0 {
		t.Errorf("the transfer is still held after it was over: %v", transfers.live)
	}
}
