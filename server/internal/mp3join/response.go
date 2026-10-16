package mp3join

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// A book's parts joined into one response: the shell the streaming
// engine's join and the engine-less one share. It answers as a live
// encode does, with no length and no range but the whole stream, so the
// transfer's end is the only end a client learns of. A part lost once
// audio has gone out therefore breaks the transfer off rather than ending
// it: a well-formed end would read as the book's end, and a client that
// keeps what it fetched would keep it as the whole book.

// RangeRefused reports whether r asks for a range a joined stream cannot
// serve: any but the whole stream from its start. HEAD asks for none.
func RangeRefused(r *http.Request) bool {
	rng := r.Header.Get("Range")
	return r.Method != http.MethodHead && rng != "" && strings.TrimSpace(rng) != "bytes=0-"
}

// Response writes one joined stream.
type Response struct {
	w     http.ResponseWriter
	ctx   context.Context
	head  bool
	shape Shape
	flush func()
	lost  func(part string, err error)
}

// NewResponse answers r through w as a joined stream whose every part is
// shape. lost logs a part the stream is broken off at.
func NewResponse(w http.ResponseWriter, r *http.Request, shape Shape, lost func(part string, err error)) *Response {
	rc := http.NewResponseController(w)
	return &Response{
		w: w, ctx: r.Context(), head: r.Method == http.MethodHead, shape: shape,
		flush: func() { rc.Flush() }, lost: lost,
	}
}

// Open writes the stream's headers: MP3 of no length and no range, never
// stored and never held back by a proxy. It reports whether parts follow,
// false for HEAD.
func (j *Response) Open() bool {
	h := j.w.Header()
	h.Set("Content-Type", "audio/mpeg")
	h.Set("Accept-Ranges", "none")
	h.Set("Cache-Control", "no-store")
	h.Set("X-Accel-Buffering", "no")
	j.w.WriteHeader(http.StatusOK)
	return !j.head
}

// CopyPart copies one part, src read to its end, lengthMS its length as
// known elsewhere (zero when unknown) and cutMS what a cut took off its
// head. The stream is broken off at a part that broke, held no frame, or
// ended short of its length (Stream.Shortfall); only the opening part of a
// cut stream may hold none, its cut landing past its last frame. A
// listener gone, or a request cancelled under it (a server shutting
// down), tears the transfer down as well.
func (j *Response) CopyPart(part string, src io.Reader, lengthMS, cutMS int64) {
	got, readErr, writeErr := Copy(j.w, src, j.shape, j.flush)
	if writeErr != nil || j.ctx.Err() != nil {
		panic(http.ErrAbortHandler)
	}
	if readErr == nil && got.Frames == 0 && cutMS == 0 {
		readErr = errors.New("the part holds no frame")
	}
	if readErr == nil {
		if short := got.Shortfall(lengthMS, cutMS); short > 0 {
			readErr = fmt.Errorf("the part ended %.1f s short", short)
		}
	}
	if readErr != nil {
		j.BreakOff(part, readErr)
	}
}

// BreakOff breaks the stream off at part, which was lost for err, or
// tears it down unlogged where the request itself is gone.
func (j *Response) BreakOff(part string, err error) {
	if j.ctx.Err() == nil {
		j.lost(part, err)
	}
	panic(http.ErrAbortHandler)
}
