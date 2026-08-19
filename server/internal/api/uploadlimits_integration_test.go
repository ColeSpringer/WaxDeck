package api

import (
	"io"
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// The three bounds the upload surface gained: a ceiling on what one
// session may declare, a ceiling on what one request may carry, and a
// pace for how fast one account may ask at all.

// zeroes streams as many bytes of nothing as it is asked for, so a
// 32 MiB request body costs this suite no memory.
type zeroes struct{}

func (zeroes) Read(p []byte) (int, error) {
	clear(p)
	return len(p), nil
}

// putChunk sends n bytes at offset without ever holding them.
func putChunk(t *testing.T, h *harness, uploadID string, offset, n int64) *http.Response {
	t.Helper()
	req, _ := http.NewRequest("PUT",
		h.ts.URL+"/api/v1/uploads/"+uploadID+"/data?offset="+strconv.FormatInt(offset, 10),
		io.LimitReader(zeroes{}, n))
	req.ContentLength = n
	req.Header.Set("Content-Type", "application/octet-stream")
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func TestUploadSessionCeiling(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	resp := h.postJSON(t, "/api/v1/uploads", map[string]any{
		"fileName": "leviathan.flac", "mediaType": "music",
		"sizeBytes": service.MaxUploadSize + 1,
	})
	if resp.StatusCode != 400 {
		t.Fatalf("over-ceiling session status = %d, want 400", resp.StatusCode)
	}
	refusal := decode[Error](t, resp)
	// invalid-request rather than quota-exceeded: no allowance anybody
	// can change admits this, and the client renders a refused value's
	// own sentence only for this code.
	if refusal.Code != "invalid-request" {
		t.Fatalf("over-ceiling session code = %q, want invalid-request", refusal.Code)
	}
	// The caller's own allowance is not what refused, and the message
	// has to say so or the only remedy it suggests is the wrong one.
	if !strings.Contains(refusal.Message, "at most") {
		t.Fatalf("over-ceiling message does not name the ceiling: %q", refusal.Message)
	}
}

func TestUploadChunkCap(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	// A session with more left than one chunk may carry, so the chunk
	// cap is what binds rather than the declared size.
	resp := h.postJSON(t, "/api/v1/uploads", map[string]any{
		"fileName": "long.flac", "mediaType": "music",
		"sizeBytes": 2 * service.MaxUploadChunk,
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create status = %d, want 201", resp.StatusCode)
	}
	up := decode[Upload](t, resp)

	over := putChunk(t, h, up.Id, 0, service.MaxUploadChunk+1)
	if over.StatusCode != 400 {
		t.Fatalf("over-cap chunk status = %d, want 400", over.StatusCode)
	}
	if e := decode[Error](t, over); e.Code != "invalid-request" ||
		!strings.Contains(e.Message, "at most") {
		t.Fatalf("over-cap chunk error = %+v", e)
	}

	// A body far past the cap is refused on what it declared, without
	// reading it: the answer has to arrive while the client is still
	// listening, and a chunk's worth of write-then-discard on the
	// staging volume is exactly what the room check exists to protect.
	// Sent as a declared length the server can see up front, which is
	// what any real client sends.
	huge := putChunk(t, h, up.Id, 0, 200<<20)
	if huge.StatusCode != 400 {
		t.Fatalf("far-over-cap chunk status = %d, want 400", huge.StatusCode)
	}
	if e := decode[Error](t, huge); e.Code != "invalid-request" ||
		!strings.Contains(e.Message, "declares") {
		t.Fatalf("far-over-cap chunk error = %+v", e)
	}

	// Nothing of the refused chunk is kept, so the client resumes from
	// the same offset rather than from a truncated half-write.
	after := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+up.Id, h.token))
	if after.ReceivedBytes != 0 {
		t.Fatalf("receivedBytes after a refused chunk = %d, want 0", after.ReceivedBytes)
	}

	// A chunk of exactly the documented size is legal: the cap the
	// contract promises is the one the server keeps, not one under it.
	atCap := putChunk(t, h, up.Id, 0, service.MaxUploadChunk)
	if atCap.StatusCode != 200 {
		t.Fatalf("at-cap chunk status = %d, want 200", atCap.StatusCode)
	}
	if got := decode[Upload](t, atCap).ReceivedBytes; got != service.MaxUploadChunk {
		t.Fatalf("receivedBytes after a full chunk = %d, want %d", got, service.MaxUploadChunk)
	}
}

func TestUploadSurfaceIsPaced(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	// The clock stands still, so the burst is spent by requests alone
	// and the assertion does not race the refill.
	frozen := time.Now()
	h.srv.uploads.now = func() time.Time { return frozen }

	// Opened before anything is spent, because opening is one of the
	// paced calls and this session is what the unpaced ones act on.
	up := decode[Upload](t, h.postJSON(t, "/api/v1/uploads", map[string]any{
		"fileName": "paced.flac", "mediaType": "music", "sizeBytes": 8,
	}))
	if up.Id == "" {
		t.Fatal("no session to drive the unpaced calls against")
	}

	// A session id that is well formed and belongs to nobody: the pacer
	// runs before the lookup, so each of these is a cheap 404 that
	// still spends a token.
	const ghost = "/api/v1/uploads/up-01JZX5N8QW3F4V9T2B7KD3M9R6/complete"
	for i := range uploadBurst {
		code := h.postJSON(t, ghost, nil).StatusCode
		if code == 429 {
			// One token went on the session above.
			break
		}
		if code != 404 {
			t.Fatalf("request %d of the burst answered %d, want 404", i+1, code)
		}
	}
	resp := h.postJSON(t, ghost, nil)
	if resp.StatusCode != 429 {
		t.Fatalf("the request past the burst answered %d, want 429", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "rate-limited" {
		t.Fatalf("paced request code = %q, want rate-limited", e.Code)
	}

	// Reads stay outside the pacer: the uploads screen refetches its
	// listing while a transfer runs, and a bound that counted those
	// would spend the transfer's own budget on watching it.
	if code := get(t, h.ts, "/api/v1/uploads", h.token).StatusCode; code != 200 {
		t.Fatalf("listing during a paced-out burst answered %d, want 200", code)
	}

	// And so do the two that would turn this into a throughput ceiling
	// rather than a pace: a transfer is many chunks, and the discard is
	// what gives the staging back. A client that spent its bucket
	// opening sessions has to be able to feed them and to throw them
	// away.
	if code := putChunk(t, h, up.Id, 0, 8).StatusCode; code != 200 {
		t.Fatalf("a chunk during a paced-out burst answered %d, want 200", code)
	}
	req, _ := http.NewRequest("DELETE", h.ts.URL+"/api/v1/uploads/"+up.Id, nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	del, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer del.Body.Close()
	if del.StatusCode != 204 {
		t.Fatalf("a discard during a paced-out burst answered %d, want 204", del.StatusCode)
	}

	// A second's wait buys a second's worth of requests back.
	frozen = frozen.Add(time.Second)
	if code := h.postJSON(t, ghost, nil).StatusCode; code != 404 {
		t.Fatalf("the request after the refill answered %d, want 404", code)
	}
}
