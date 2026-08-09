package api

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

const testWorkerToken = "worker-token-for-tests"

// newWorkerTestServer is newAuthTestServer with a configured worker
// token, for the worker-path routing of AuthMiddleware.
func newWorkerTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	dataDir := t.TempDir()
	store, err := db.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := service.Open(ctx, service.Config{DataDir: dataDir, Logger: log}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})

	srv := NewServer("test", Options{
		Service:      svc,
		Sessions:     auth.NewSessions(store),
		WorkerTokens: []string{testWorkerToken},
	})
	h := HandlerWithOptions(
		NewStrictHandlerWithOptions(srv, nil, StrictHTTPServerOptions{
			RequestErrorHandlerFunc:  RequestErrorHandler,
			ResponseErrorHandlerFunc: ResponseErrorHandler,
		}),
		StdHTTPServerOptions{
			BaseURL:     "/api/v1",
			Middlewares: []MiddlewareFunc{srv.AuthMiddleware},
		},
	)
	mux := http.NewServeMux()
	mux.Handle("/api/v1/", h)
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	return ts
}

func TestWorkerTokenOpensWorkerPaths(t *testing.T) {
	t.Parallel()
	ts := newWorkerTestServer(t)

	resp := get(t, ts, "/api/v1/similarity/work", testWorkerToken)
	if resp.StatusCode != 200 {
		t.Fatalf("work pull with worker token = %d, want 200", resp.StatusCode)
	}
	page := decode[SimilarityWorkPage](t, resp)
	if len(page.Items) != 0 || page.RetryAfterSeconds <= 0 {
		t.Fatalf("empty-queue page = %+v", page)
	}

	// The embeddings route is a worker path too; an empty batch is the
	// handler's 400, proving the request got past auth.
	resp = postJSON(t, ts.URL+"/api/v1/similarity/embeddings", testWorkerToken,
		`{"model":"m1","dims":8,"embeddings":[]}`)
	if resp.StatusCode != 400 {
		t.Fatalf("empty embeddings batch = %d, want the handler's 400", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestWorkerPathsRefuseWrongCredentials(t *testing.T) {
	t.Parallel()
	ts := newWorkerTestServer(t)

	// A wrong token never opens the worker path.
	resp := get(t, ts, "/api/v1/similarity/work", "not-the-worker-token")
	if resp.StatusCode != 401 {
		t.Fatalf("wrong token = %d, want 401", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "unauthenticated" {
		t.Fatalf("error code = %q", e.Code)
	}
	// No token at all is refused the same way.
	resp = get(t, ts, "/api/v1/similarity/work", "")
	if resp.StatusCode != 401 {
		t.Fatalf("missing token = %d, want 401", resp.StatusCode)
	}
	resp.Body.Close()

	// A real user session must never reach a worker endpoint: workers
	// ignore library visibility.
	sessionToken := login(t, ts)
	resp = get(t, ts, "/api/v1/similarity/work", sessionToken)
	if resp.StatusCode != 401 {
		t.Fatalf("session bearer on worker path = %d, want 401", resp.StatusCode)
	}
	resp.Body.Close()
	// And a session cookie is just as dead there.
	req, _ := http.NewRequest("GET", ts.URL+"/api/v1/similarity/work", nil)
	req.AddCookie(&http.Cookie{Name: "waxdeck_session", Value: sessionToken})
	cookieResp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if cookieResp.StatusCode != 401 {
		t.Fatalf("session cookie on worker path = %d, want 401", cookieResp.StatusCode)
	}
	cookieResp.Body.Close()
}

func TestWorkerTokenOpensNothingElse(t *testing.T) {
	t.Parallel()
	ts := newWorkerTestServer(t)

	// The worker token is not a session: outside the worker paths it
	// authenticates nothing, the status surface included.
	for _, path := range []string{"/api/v1/similarity/status", "/api/v1/library/items"} {
		resp := get(t, ts, path, testWorkerToken)
		if resp.StatusCode != 401 {
			t.Fatalf("worker token on %s = %d, want 401", path, resp.StatusCode)
		}
		resp.Body.Close()
	}
}

func TestWorkerAuthorizedComparesTokens(t *testing.T) {
	t.Parallel()
	srv := &Server{workerTokens: []string{"tok-a", "tok-b"}}
	mk := func(header string) *http.Request {
		r := httptest.NewRequest("GET", "/api/v1/similarity/work", nil)
		if header != "" {
			r.Header.Set("Authorization", header)
		}
		return r
	}
	cases := []struct {
		name   string
		header string
		want   bool
	}{
		{"first token", "Bearer tok-a", true},
		{"second token", "Bearer tok-b", true},
		{"scheme is case-insensitive", "bearer tok-a", true},
		{"wrong token", "Bearer tok-c", false},
		{"prefix of a token", "Bearer tok-", false},
		{"token with suffix", "Bearer tok-aa", false},
		{"no header", "", false},
		{"wrong scheme", "Basic tok-a", false},
		{"bare token without scheme", "tok-a", false},
	}
	for _, c := range cases {
		if got := srv.workerAuthorized(mk(c.header)); got != c.want {
			t.Errorf("%s: workerAuthorized = %v, want %v", c.name, got, c.want)
		}
	}
	// No configured tokens disables the worker API outright.
	empty := &Server{}
	if empty.workerAuthorized(mk("Bearer tok-a")) {
		t.Error("server without worker tokens authorized a bearer")
	}
}
