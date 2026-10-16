package mp3join

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// copyPart copies src as one part of a joined response to r and says
// whether the response was broken off, and what was logged as lost.
func copyPart(r *http.Request, src []byte, lengthMS, cutMS int64) (rec *httptest.ResponseRecorder, aborted bool, lost []string) {
	rec = httptest.NewRecorder()
	out := NewResponse(rec, r, Shape{}, func(part string, _ error) { lost = append(lost, part) })
	func() {
		defer func() {
			if v := recover(); v != nil {
				if v != http.ErrAbortHandler {
					panic(v)
				}
				aborted = true
			}
		}()
		out.CopyPart("p1", bytes.NewReader(src), lengthMS, cutMS)
	}()
	return rec, aborted, lost
}

// A part that holds no frame is lost whatever its length says, a part of
// a second or of no known length included, which a length's slack would
// let through; only a part whose head a cut took may hold none. Both
// joins answer through this, so they hold every part to one rule.
func TestResponseBreaksOffAtAPartHoldingNoFrame(t *testing.T) {
	part := rendered(t, "part", time.Second, 44100, 2)
	for _, c := range []struct {
		name            string
		src             []byte
		lengthMS, cutMS int64
		broken          bool
	}{
		{"a whole part", part, 1000, 0, false},
		{"no frame in a part of a second", part[:100], 1000, 0, true},
		{"no frame in a part of no known length", part[:100], 0, 0, true},
		{"no frame past a cut", part[:100], 1000, 999, false},
	} {
		_, aborted, lost := copyPart(httptest.NewRequest("GET", "/", nil), c.src, c.lengthMS, c.cutMS)
		if aborted != c.broken || (len(lost) == 1) != c.broken {
			t.Errorf("%s: aborted %v, logged %v; want broken off %v", c.name, aborted, lost, c.broken)
		}
	}
}

// A request cancelled under the stream (a server shutting down) tears it
// down, as a listener leaving does, and logs no part as lost.
func TestResponseTearsDownACancelledRequest(t *testing.T) {
	part := rendered(t, "part", time.Second, 44100, 2)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, aborted, lost := copyPart(httptest.NewRequest("GET", "/", nil).WithContext(ctx), part, 1000, 0)
	if !aborted || len(lost) != 0 {
		t.Fatalf("a cancelled request: aborted %v, logged %v; want torn down unlogged", aborted, lost)
	}
	gone := NewResponse(failingResponse{httptest.NewRecorder()}, httptest.NewRequest("GET", "/", nil), Shape{}, func(string, error) {
		t.Error("a listener gone was logged as a lost part")
	})
	func() {
		defer func() {
			if v := recover(); v != http.ErrAbortHandler {
				t.Errorf("a listener gone = %v, want the transfer torn down", v)
			}
		}()
		gone.CopyPart("p1", bytes.NewReader(part), 1000, 0)
	}()
}

// failingResponse is a listener that has hung up.
type failingResponse struct{ *httptest.ResponseRecorder }

func (failingResponse) Write([]byte) (int, error) { return 0, errors.New("the listener hung up") }

// Only a range from the start is the whole stream; HEAD asks for none.
func TestRangeRefused(t *testing.T) {
	for _, c := range []struct {
		method, rng string
		refused     bool
	}{
		{"GET", "", false},
		{"GET", "bytes=0-", false},
		{"GET", " bytes=0- ", false},
		{"GET", "bytes=100-", true},
		{"GET", "bytes=0-99", true},
		{"HEAD", "bytes=100-", false},
	} {
		r := httptest.NewRequest(c.method, "/", nil)
		if c.rng != "" {
			r.Header.Set("Range", c.rng)
		}
		if got := RangeRefused(r); got != c.refused {
			t.Errorf("%s %q refused %v, want %v", c.method, c.rng, got, c.refused)
		}
	}
}
