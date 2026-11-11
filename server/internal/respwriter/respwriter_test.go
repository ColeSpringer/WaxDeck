package respwriter

import (
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"
)

// plain is a writer with nothing but the three methods: it cannot flush,
// takes no file, and hides nothing.
type plain struct {
	header   http.Header
	statuses []int
	body     strings.Builder
}

func newPlain() *plain { return &plain{header: http.Header{}} }

func (p *plain) Header() http.Header         { return p.header }
func (p *plain) WriteHeader(status int)      { p.statuses = append(p.statuses, status) }
func (p *plain) Write(b []byte) (int, error) { return p.body.Write(b) }

// unwrapOnly is a middleware writer that claims nothing but Unwrap.
type unwrapOnly struct{ w http.ResponseWriter }

func (u unwrapOnly) Header() http.Header         { return u.w.Header() }
func (u unwrapOnly) Write(b []byte) (int, error) { return u.w.Write(b) }
func (u unwrapOnly) WriteHeader(status int)      { u.w.WriteHeader(status) }
func (u unwrapOnly) Unwrap() http.ResponseWriter { return u.w }

// handedFrom notes what its ReadFrom was handed, and what had been
// written to it by then.
type handedFrom struct {
	*httptest.ResponseRecorder
	handed  []io.Reader
	written []int
}

func (h *handedFrom) ReadFrom(src io.Reader) (int64, error) {
	h.handed = append(h.handed, src)
	h.written = append(h.written, h.Body.Len())
	return io.Copy(h.ResponseRecorder, src)
}

// noted is a writer over below whose Before notes each status it is
// given and how much had reached below by then.
func noted(below http.ResponseWriter, sent func() int) (w *Writer, starts *[]int, sentBefore *[]int) {
	starts, sentBefore = new([]int), new([]int)
	w = &Writer{ResponseWriter: below}
	w.Before = func(status int) {
		*starts = append(*starts, status)
		*sentBefore = append(*sentBefore, sent())
	}
	return w, starts, sentBefore
}

// The answer starts once, on whichever call commits its status, and
// Before hears that status ahead of anything reaching the writer below.
func TestBeforeRunsOnceAsTheAnswerStarts(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name  string
		write func(w *Writer)
		want  int
	}{
		{"a status", func(w *Writer) { w.WriteHeader(404); w.Write([]byte("no")) }, 404},
		{"a write", func(w *Writer) { w.Write([]byte("x")); w.Write([]byte("y")); w.WriteHeader(500) }, 200},
		{"an empty write", func(w *Writer) { w.Write(nil); w.WriteHeader(500) }, 200},
		{"a copy", func(w *Writer) { io.Copy(w, struct{ io.Reader }{strings.NewReader("audio")}) }, 200},
		{"a flush", func(w *Writer) { w.Flush(); w.Write([]byte("x")) }, 200},
		{"early hints first", func(w *Writer) { w.WriteHeader(103); w.WriteHeader(206) }, 206},
	} {
		rec := httptest.NewRecorder()
		w, starts, sentBefore := noted(rec, func() int {
			if rec.Flushed {
				return -1
			}
			return rec.Body.Len()
		})
		if w.Started() {
			t.Errorf("%s: started before anything was written", c.name)
		}
		c.write(w)
		if !slices.Equal(*starts, []int{c.want}) {
			t.Errorf("%s: Before heard %v, want %d once", c.name, *starts, c.want)
		}
		if !slices.Equal(*sentBefore, []int{0}) {
			t.Errorf("%s: Before ran with the answer already going out", c.name)
		}
		if !w.Started() {
			t.Errorf("%s: not started after it", c.name)
		}
	}
}

// What Before does to the headers goes out with the answer, which is
// what a writer that corrects them at the last moment relies on.
func TestBeforeStillOwnsTheHeaders(t *testing.T) {
	t.Parallel()
	rec := httptest.NewRecorder()
	w := &Writer{ResponseWriter: rec}
	w.Before = func(int) { w.Header().Add("Vary", "Origin") }
	w.Header().Set("Vary", "Accept-Language")
	w.Write([]byte("x"))
	if got := rec.Result().Header.Values("Vary"); !slices.Equal(got, []string{"Accept-Language", "Origin"}) {
		t.Errorf("Vary = %v, want both values", got)
	}
}

// A copy that brings nothing, and a flush nothing below can make, start
// nothing: no status is committed, so one can still be chosen.
func TestWhatSendsNothingStartsNothing(t *testing.T) {
	t.Parallel()
	broke := errors.New("the source broke")
	for _, c := range []struct {
		name  string
		below http.ResponseWriter
		try   func(w *Writer) error
		err   error
	}{
		{"an empty copy", &handedFrom{ResponseRecorder: httptest.NewRecorder()}, func(w *Writer) error {
			_, err := w.ReadFrom(strings.NewReader(""))
			return err
		}, nil},
		{"a copy whose source breaks at once", httptest.NewRecorder(), func(w *Writer) error {
			_, err := w.ReadFrom(iotest(broke))
			return err
		}, broke},
		{"a flush with no flusher below", newPlain(), func(w *Writer) error { w.Flush(); return nil }, nil},
		{"a flush through another of these", &Writer{ResponseWriter: unwrapOnly{newPlain()}}, func(w *Writer) error {
			w.Flush()
			return nil
		}, nil},
	} {
		w, starts, _ := noted(c.below, func() int { return 0 })
		if err := c.try(w); !errors.Is(err, c.err) {
			t.Errorf("%s: err = %v, want %v", c.name, err, c.err)
		}
		if w.Started() || len(*starts) != 0 {
			t.Errorf("%s: the answer reads as started (Before heard %v)", c.name, *starts)
		}
		w.WriteHeader(http.StatusBadGateway)
		if !slices.Equal(*starts, []int{http.StatusBadGateway}) {
			t.Errorf("%s: a status chosen afterwards was heard as %v", c.name, *starts)
		}
	}
}

// iotest is a source that fails its first read.
func iotest(err error) io.Reader { return failing{err} }

type failing struct{ err error }

func (f failing) Read([]byte) (int, error) { return 0, f.err }

// A file handed over reaches the writer below as it came, the form
// sendfile takes: at once when the answer is under way, as
// http.ServeContent has it, and after its first piece when the copy is
// what starts it.
func TestACopyKeepsTheFilePath(t *testing.T) {
	t.Parallel()
	body := strings.Repeat("0123456789abcdef", 4096)

	below := &handedFrom{ResponseRecorder: httptest.NewRecorder()}
	w := &Writer{ResponseWriter: below}
	w.WriteHeader(http.StatusOK)
	src := struct{ io.Reader }{strings.NewReader(body)}
	if n, err := w.ReadFrom(src); n != int64(len(body)) || err != nil {
		t.Fatalf("copied %d, %v; want %d", n, err, len(body))
	}
	if len(below.handed) != 1 || below.handed[0] != io.Reader(src) || below.written[0] != 0 {
		t.Error("a copy into a started answer did not go below whole and untouched")
	}

	below = &handedFrom{ResponseRecorder: httptest.NewRecorder()}
	w = &Writer{ResponseWriter: below}
	src = struct{ io.Reader }{strings.NewReader(body)}
	if n, err := w.ReadFrom(src); n != int64(len(body)) || err != nil {
		t.Fatalf("copied %d, %v; want %d", n, err, len(body))
	}
	if below.Body.String() != body {
		t.Error("the bytes that arrived are not the ones copied")
	}
	if len(below.handed) != 1 || below.handed[0] != io.Reader(src) {
		t.Fatalf("the rest of a copy that starts the answer went below as %v", below.handed)
	}
	if first := below.written[0]; first == 0 || first > 512 {
		t.Errorf("%d bytes went ahead of the rest, want one small piece", first)
	}
}

// The writer flushes through whatever stands between it and one that
// can, and claims the capability outright: the generated event-stream
// writer asserts for it rather than asking a ResponseController.
func TestFlushReachesThroughWrappers(t *testing.T) {
	t.Parallel()
	var _ http.Flusher = (*Writer)(nil)
	var _ io.ReaderFrom = (*Writer)(nil)
	rec := httptest.NewRecorder()
	w := &Writer{ResponseWriter: unwrapOnly{&Writer{ResponseWriter: unwrapOnly{rec}}}}
	w.Flush()
	if !rec.Flushed {
		t.Error("the flush stopped at a wrapper")
	}
	if !w.Started() {
		t.Error("a flush that went out did not start the answer")
	}
}

// Started asks the nearest of these in front of a writer, and Server
// finds the writer under all of them.
func TestLookingThroughWrappers(t *testing.T) {
	t.Parallel()
	bottom := newPlain()
	outer := &Writer{ResponseWriter: bottom}
	inner := &Writer{ResponseWriter: unwrapOnly{outer}}
	handed := unwrapOnly{inner}

	if Started(bottom) || Started(handed) {
		t.Error("an answer nothing wrote reads as started")
	}
	// Written through the outer one alone, as a layer outside a handler
	// answers for it.
	outer.WriteHeader(http.StatusNoContent)
	if Started(handed) {
		t.Error("Started asked a writer further out than the nearest")
	}
	inner.WriteHeader(http.StatusOK)
	if !Started(handed) {
		t.Error("a started answer reads as not started through a wrapper")
	}
	if Server(handed) != http.ResponseWriter(bottom) {
		t.Error("Server stopped short of the writer under the wrappers")
	}
	if Server(bottom) != http.ResponseWriter(bottom) {
		t.Error("Server changed a writer nothing wraps")
	}
}

// embedder is a writer with a Write of its own, as the stall bound has:
// it starts the answer itself before writing below.
type embedder struct{ Writer }

func (e *embedder) Write(b []byte) (int, error) {
	e.Start(http.StatusOK)
	return e.ResponseWriter.Write(b)
}

func TestAnEmbedderWithItsOwnWriteStartsTheAnswer(t *testing.T) {
	t.Parallel()
	var starts []int
	e := &embedder{}
	e.Writer = Writer{ResponseWriter: httptest.NewRecorder(), Before: func(status int) { starts = append(starts, status) }}
	e.Write([]byte("x"))
	e.Write([]byte("y"))
	e.WriteHeader(http.StatusTeapot)
	if !slices.Equal(starts, []int{http.StatusOK}) || !Started(unwrapOnly{e}) {
		t.Errorf("Before heard %v (started %v), want the one 200", starts, e.Started())
	}
}
