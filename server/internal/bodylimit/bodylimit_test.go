package bodylimit_test

import (
	"errors"
	"io"
	"net/http"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/bodylimit"
	"github.com/colespringer/waxdeck/server/internal/bodylimit/bodylimittest"
)

// opaque is a writer that hides the one below it.
type opaque struct{ w http.ResponseWriter }

func (o opaque) Header() http.Header         { return o.w.Header() }
func (o opaque) Write(b []byte) (int, error) { return o.w.Write(b) }
func (o opaque) WriteHeader(code int)        { o.w.WriteHeader(code) }

const limit = 64 << 10

// reading reads its body under the limit and answers 413 when the limit
// cut it.
var reading = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
	_, err := io.Copy(io.Discard, bodylimit.Reader(w, r.Body, limit))
	var tooBig *http.MaxBytesError
	if errors.As(err, &tooBig) {
		w.WriteHeader(http.StatusRequestEntityTooLarge)
	}
})

func overrun(t *testing.T, handler http.Handler) int64 {
	t.Helper()
	return bodylimittest.Overrun(t, handler, limit, func(url string, filler io.Reader) *http.Request {
		req, err := http.NewRequest("POST", url, filler)
		if err != nil {
			t.Fatal(err)
		}
		return req
	})
}

// A body past its limit is cut where the limit falls, whatever writers
// stand in front of the server's own. The server is told through that one
// alone; told nothing, it reads on before it answers.
func TestABodyPastItsLimitIsCutBehindWrappers(t *testing.T) {
	t.Parallel()
	bare := overrun(t, reading)
	if bare > bodylimittest.Tolerated {
		t.Fatalf("with no wrapper the server read %d bytes past the limit, more than the %d this test tolerates", bare, bodylimittest.Tolerated)
	}
	behind := overrun(t, bodylimittest.Behind(bodylimittest.Behind(reading)))
	if behind > bodylimittest.Tolerated {
		t.Errorf("behind two wrappers the server read %d bytes past the limit, want at most %d (%d with none)", behind, bodylimittest.Tolerated, bare)
	}
}

// A writer that hides the one below it still bounds the body: the read
// fails at the limit, and what is lost is the server being told, so it
// reads on for net/http's 256 KB and a byte before it answers.
func TestAnOpaqueWriterStillBoundsTheBody(t *testing.T) {
	t.Parallel()
	const readOn = 256<<10 + 1
	hidden := overrun(t, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reading.ServeHTTP(opaque{w}, r)
	}))
	if hidden > readOn+bodylimittest.Tolerated {
		t.Errorf("behind an opaque writer the server read %d bytes past the limit, want at most %d", hidden, readOn+bodylimittest.Tolerated)
	}
}
