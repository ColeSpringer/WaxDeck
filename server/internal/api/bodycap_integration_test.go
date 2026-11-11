package api

import (
	"bytes"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/bodylimit/bodylimittest"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// letters streams as many letters as it is asked for: the inside of one
// JSON string that never ends, which a decoder reads to the end.
type letters struct{}

func (letters) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = 'a'
	}
	return len(p), nil
}

// countedBody is a JSON body far past the cap that counts what was read
// of it, so a test can tell a refusal that stopped reading from one that
// read the lot first.
type countedBody struct {
	r    io.Reader
	read int64
}

func newCountedBody(head string, n int64) *countedBody {
	return &countedBody{r: io.MultiReader(strings.NewReader(head), io.LimitReader(letters{}, n))}
}

func (b *countedBody) Read(p []byte) (int, error) {
	n, err := b.r.Read(p)
	b.read += int64(n)
	return n, err
}

func (b *countedBody) Close() error { return nil }

// serveBody sends a body to a server in-process, declared or not, and
// answers the response and how much of the body the server read.
func serveBody(t *testing.T, server http.Handler, method, path, token string, declared bool) (*httptest.ResponseRecorder, int64) {
	t.Helper()
	body := newCountedBody(`{"username":"`, jsonBodyMaxBytes+4<<20)
	req := httptest.NewRequest(method, path, body)
	req.ContentLength = -1
	if declared {
		req.ContentLength = int64(len(`{"username":"`)) + jsonBodyMaxBytes + 4<<20
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	server.ServeHTTP(rec, req)
	return rec, body.read
}

// A JSON body past the cap is refused as invalid-request whether the
// caller is signed in, holds the worker token, or neither: on what it
// declares, before any of it is read, and otherwise as soon as the read
// passes the cap.
func TestJSONBodiesPastTheCapAreRefusedUnread(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	worker := newWorkerTestServer(t).Config.Handler
	for _, c := range []struct {
		what, method, path, token string
		server                    http.Handler
		declared                  bool
	}{
		{"anonymous sign-in, declared", "POST", "/api/v1/auth/login", "", h.ts.Config.Handler, true},
		{"anonymous sign-in, streamed", "POST", "/api/v1/auth/login", "", h.ts.Config.Handler, false},
		{"signed-in preview, declared", "POST", "/api/v1/playlists/m3u/preview", h.token, h.ts.Config.Handler, true},
		{"signed-in preview, streamed", "POST", "/api/v1/playlists/m3u/preview", h.token, h.ts.Config.Handler, false},
		{"worker report, declared", "POST", "/api/v1/similarity/embeddings", testWorkerToken, worker, true},
		{"worker report, streamed", "POST", "/api/v1/similarity/embeddings", testWorkerToken, worker, false},
	} {
		rec, read := serveBody(t, c.server, c.method, c.path, c.token, c.declared)
		if rec.Code != 400 || !strings.Contains(rec.Body.String(), `"invalid-request"`) ||
			!strings.Contains(rec.Body.String(), "at most") {
			t.Errorf("%s = %d %s, want 400 invalid-request naming the bound", c.what, rec.Code, rec.Body.String())
		}
		limit := int64(jsonBodyMaxBytes + 1)
		if c.declared {
			limit = 0
		}
		if read > limit {
			t.Errorf("%s read %d bytes of the body, want at most %d", c.what, read, limit)
		}
	}
}

// A streamed body past the cap is refused where the cap falls. Only a
// real connection shows it: the server stops reading when its own writer
// is told, and the API answers through writers that wrap that one.
func TestAStreamedBodyPastTheCapIsNotReadOn(t *testing.T) {
	t.Parallel()
	srv := NewServer("test", Options{})
	over := bodylimittest.Overrun(t, srv.Handler(), jsonBodyMaxBytes, func(url string, filler io.Reader) *http.Request {
		body := io.MultiReader(strings.NewReader(`{"username":"`), filler)
		req, err := http.NewRequest("POST", url+"/api/v1/auth/login", body)
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Content-Type", "application/json")
		return req
	})
	if over > bodylimittest.Tolerated {
		t.Errorf("the server had read %d bytes past the cap when it answered, want at most %d", over, bodylimittest.Tolerated)
	}
}

// The largest bodies the contract's own field limits allow pass the cap:
// a genre tree at its limits, and an M3U document at the character bound
// in the costliest escape JSON has.
func TestBodiesAtTheContractsLimitsPass(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	pad := func(s string, n int) string { return s + strings.Repeat("x", n-len(s)) }
	genres := make([]map[string]any, 0, 2000)
	for i := range 2000 {
		aliases := make([]string, 64)
		for j := range aliases {
			aliases[j] = pad(fmt.Sprintf("alias %04d %02d ", i, j), 128)
		}
		g := map[string]any{"name": pad(fmt.Sprintf("genre %04d ", i), 128), "aliases": aliases}
		if i >= 1000 {
			g["parent"] = pad(fmt.Sprintf("genre %04d ", i-1000), 128)
		}
		genres = append(genres, g)
	}
	resp := h.putJSON(t, "/api/v1/admin/genre-tree", map[string]any{"genres": genres})
	wantStatus(t, resp, 200, "a genre tree at its limits")

	// A surrogate pair per character: twelve bytes of JSON for each.
	line := strings.Repeat(`\ud83c\udfb5`, 262143)
	doc := `{"content":"` + line + `\n` + line + `\n` + line + `\n` + line + `"}`
	if len(doc) < 12_500_000 {
		t.Fatalf("the escaped document is %d bytes, want about 12.6 MB", len(doc))
	}
	req, _ := http.NewRequest("POST", h.ts.URL+"/api/v1/playlists/m3u/preview", strings.NewReader(doc))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if got := decodeStatus[M3uPreview](t, resp, 200, "an escaped document at the bound"); got.Unmatched != 4 {
		t.Fatalf("the escaped document = %+v, want four unmatched lines", got)
	}

	// A worker's embedding report at its own limits: a hundred vectors of
	// 4096 numbers, each written out at full precision.
	var report strings.Builder
	report.WriteString(`{"model":"bound-test","dims":4096,"embeddings":[`)
	for i := range 100 {
		if i > 0 {
			report.WriteByte(',')
		}
		fmt.Fprintf(&report, `{"pid":"tr-01JZX5N8QW3F4V9T2B7KD3M%03d","essence":"e%d","vector":[`, i, i)
		for j := range 4096 {
			if j > 0 {
				report.WriteByte(',')
			}
			report.WriteString("-1.2345678901234567e-123")
		}
		report.WriteString("]}")
	}
	report.WriteString("]}")
	if report.Len() < 10_000_000 {
		t.Fatalf("the report is %d bytes, want about 10 MB", report.Len())
	}
	worker := newWorkerTestServer(t)
	req, _ = http.NewRequest("POST", worker.URL+"/api/v1/similarity/embeddings", strings.NewReader(report.String()))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+testWorkerToken)
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if body, _ := io.ReadAll(resp.Body); bytes.Contains(body, []byte("too large")) {
		t.Fatalf("a report at its limits = %d %s, want it past the cap", resp.StatusCode, body)
	}
}

// A body that is not JSON keeps its own bound: an upload chunk past the
// JSON cap is taken whole.
func TestARawBodyPastTheJSONCapIsTaken(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	up := decodeStatus[Upload](t, h.postJSON(t, "/api/v1/uploads", map[string]any{
		"fileName": "long.flac", "mediaType": "music", "sizeBytes": 2 * service.MaxUploadChunk,
	}), 201, "create the upload")
	n := int64(jsonBodyMaxBytes + 1<<20)
	if got := decodeStatus[Upload](t, putChunk(t, h, up.Id, 0, n), 200, "a chunk past the JSON cap").ReceivedBytes; got != n {
		t.Fatalf("receivedBytes = %d, want %d", got, n)
	}
}

// Every operation whose body the contract declares as something other
// than JSON reads it unbounded by the JSON cap, and every other one is
// capped, so a new raw body cannot be cut short and a new JSON one cannot
// go unbounded.
func TestTheJSONCapSparesExactlyTheRawBodies(t *testing.T) {
	t.Parallel()
	spec, err := GetSpec()
	if err != nil {
		t.Fatal(err)
	}
	param := regexp.MustCompile(`\{[^}]+\}`)
	raw := 0
	for path, item := range spec.Paths.Map() {
		for method, op := range item.Operations() {
			if op.RequestBody == nil || op.RequestBody.Value == nil {
				continue
			}
			content := op.RequestBody.Value.Content
			jsonOnly := len(content) == 1 && content.Get("application/json") != nil
			req := httptest.NewRequest(method, "/api/v1"+param.ReplaceAllString(path, "x"), bytes.NewReader(nil))
			if got := rawBody(req); got == jsonOnly {
				t.Errorf("%s %s: spared from the JSON cap = %v, want %v", method, path, got, !jsonOnly)
			}
			if !jsonOnly {
				raw++
			}
		}
	}
	if raw == 0 {
		t.Fatal("the contract declares no raw body; the walk read nothing")
	}
}
