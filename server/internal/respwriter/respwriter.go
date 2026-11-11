// Package respwriter is the response writer the server's wrappers are
// built on. A writer put in front of net/http's own has to stay what
// that one is, and each of these wrappers used to carry its own copy of
// how, which drifted:
//
//   - Flush, claimed outright. The generated event-stream writer asserts
//     `w.(http.Flusher)` rather than asking a ResponseController, and
//     silently falls back to an io.Copy that buffers progress frames
//     instead of delivering them per event. Claiming it costs nothing
//     where no writer below can flush, since the fallback those callers
//     take does not flush either. The flush itself goes through a
//     ResponseController, so it reaches the real writer whatever else
//     stands between.
//   - ReadFrom. net/http's writer copies a file to the socket with
//     sendfile, which http.ServeContent and io.Copy reach for; a wrapper
//     without ReadFrom drops every media byte back to a userspace loop.
//     Every wrapper on the way needs it: an inner one's ReadFrom resolves
//     against the one outside it.
//   - Unwrap, for the callers that look through wrappers properly: a
//     ResponseController (how httputil.ReverseProxy flushes audio as it
//     arrives, and how deadlines are set), the WebSocket upgrade's hijack,
//     and Server here.
//
// What a wrapper adds, it adds at one moment: as the answer starts, the
// point after which its status is committed and its headers are gone.
// Four calls can be that moment, and Writer finds it on all of them.
package respwriter

import (
	"io"
	"net/http"
)

// Writer wraps the writer below it and notes the answer starting. It
// serves as it stands, where knowing that is all that is wanted
// (Started), and inside a wrapper that does something then (Before).
//
// The answer starts on the first of: a WriteHeader with a final status,
// which is the status it starts with; a Write, even of nothing, with 200;
// the first byte of a ReadFrom, with 200; and a Flush that a writer below
// can make, with 200. An informational status starts nothing, and nor
// does a copy that brings no byte or a flush nothing can make: after
// those a status can still be chosen.
type Writer struct {
	http.ResponseWriter
	// Before runs once, with the status the answer starts with, ahead of
	// anything reaching the writer below: the last moment the headers
	// are still the answer's. Nil for none.
	Before  func(status int)
	started bool
}

// Started reports whether the answer is under way.
func (w *Writer) Started() bool { return w.started }

// Start is the answer starting with status, for a wrapper whose own Write
// or ReadFrom goes to the writer below without passing through these. It
// does nothing once the answer has started.
func (w *Writer) Start(status int) {
	if w.started {
		return
	}
	w.started = true
	if w.Before != nil {
		w.Before(status)
	}
}

func (w *Writer) WriteHeader(status int) {
	// Informational answers are not the response starting.
	if status >= http.StatusOK {
		w.Start(status)
	}
	w.ResponseWriter.WriteHeader(status)
}

func (w *Writer) Write(b []byte) (int, error) {
	w.Start(http.StatusOK)
	return w.ResponseWriter.Write(b)
}

// ReadFrom hands src to the writer below as it came. When the copy is
// what starts the answer, its first piece is read here, so that Before
// runs ahead of it and a source that gives nothing starts nothing, and
// the rest is handed down.
func (w *Writer) ReadFrom(src io.Reader) (int64, error) {
	var first int64
	if !w.started {
		buf := make([]byte, 512)
		var n int
		var err error
		for n == 0 && err == nil {
			n, err = src.Read(buf)
		}
		if n == 0 {
			if err == io.EOF {
				err = nil
			}
			return 0, err
		}
		w.Start(http.StatusOK)
		wrote, werr := w.ResponseWriter.Write(buf[:n])
		first = int64(wrote)
		switch {
		case werr != nil:
			return first, werr
		case wrote < n:
			return first, io.ErrShortWrite
		case err == io.EOF:
			return first, nil
		case err != nil:
			return first, err
		}
	}
	var rest int64
	var err error
	if rf, ok := w.ResponseWriter.(io.ReaderFrom); ok {
		rest, err = rf.ReadFrom(src)
	} else {
		rest, err = io.Copy(w.ResponseWriter, src)
	}
	return first + rest, err
}

// Flush flushes the writer below. With nothing sent yet it sends the
// headers, so it starts the answer as a write does; where nothing below
// can flush it does nothing at all.
func (w *Writer) Flush() {
	if !w.started {
		if !w.flushes() {
			return
		}
		w.Start(http.StatusOK)
	}
	_ = http.NewResponseController(w.ResponseWriter).Flush()
}

func (w *Writer) Unwrap() http.ResponseWriter { return w.ResponseWriter }

// flushes reports whether a flush from here reaches a writer that makes
// one, found as a ResponseController finds it. One of these on the way
// is asked in turn, since it claims Flush whatever stands below it.
func (w *Writer) flushes() bool {
	below := w.ResponseWriter
	for {
		switch v := below.(type) {
		case interface{ flushes() bool }:
			return v.flushes()
		case interface{ FlushError() error }, http.Flusher:
			return true
		case unwrapper:
			below = v.Unwrap()
		default:
			return false
		}
	}
}

type unwrapper interface{ Unwrap() http.ResponseWriter }

// Started reports whether the answer on w is under way, as the nearest
// Writer in front of it has it: w itself, or one it wraps. With none it
// answers false.
func Started(w http.ResponseWriter) bool {
	for {
		switch v := w.(type) {
		case interface{ Started() bool }:
			return v.Started()
		case unwrapper:
			w = v.Unwrap()
		default:
			return false
		}
	}
}

// Server is the writer under every wrapper on w: net/http's own, unless
// one of them hides it by having no Unwrap.
func Server(w http.ResponseWriter) http.ResponseWriter {
	for {
		u, ok := w.(unwrapper)
		if !ok {
			return w
		}
		w = u.Unwrap()
	}
}
