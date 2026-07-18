package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// newAuthTestServer wires the strict handler exactly like cmd/waxdeck
// does, with no catalog behind it: these tests cover the auth surface,
// which never touches the service. Catalog-backed behavior is covered
// by the integration tests.
func newAuthTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	srv := NewServer("test", nil, nil)
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

func decode[T any](t *testing.T, resp *http.Response) T {
	t.Helper()
	defer resp.Body.Close()
	var v T
	if err := json.NewDecoder(resp.Body).Decode(&v); err != nil {
		t.Fatalf("decode: %v", err)
	}
	return v
}

func login(t *testing.T, ts *httptest.Server) string {
	t.Helper()
	resp, err := http.Post(ts.URL+"/api/v1/auth/login", "application/json",
		strings.NewReader(`{"username":"admin","password":"hunter2"}`))
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("login status = %d, want 200", resp.StatusCode)
	}
	if sc := resp.Header.Get("Set-Cookie"); !strings.Contains(sc, "waxdeck_session=") {
		t.Fatalf("login Set-Cookie = %q, want waxdeck_session", sc)
	}
	return decode[LoginResponse](t, resp).Token
}

func get(t *testing.T, ts *httptest.Server, path, token string) *http.Response {
	t.Helper()
	req, _ := http.NewRequest("GET", ts.URL+path, nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func TestHealth(t *testing.T) {
	ts := newAuthTestServer(t)
	resp := get(t, ts, "/api/v1/health", "")
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d", resp.StatusCode)
	}
	h := decode[Health](t, resp)
	if h.Status != "ok" || h.Version != "test" || h.ApiVersion != 1 {
		t.Fatalf("health = %+v", h)
	}
}

func TestAuthFlow(t *testing.T) {
	ts := newAuthTestServer(t)

	// Unauthenticated access to a protected endpoint is a structured 401.
	resp := get(t, ts, "/api/v1/library/items", "")
	if resp.StatusCode != 401 {
		t.Fatalf("unauthenticated status = %d, want 401", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "unauthenticated" {
		t.Fatalf("error code = %q", e.Code)
	}

	// Session probe never 401s.
	resp = get(t, ts, "/api/v1/auth/session", "")
	if s := decode[SessionInfo](t, resp); s.Authenticated {
		t.Fatal("expected unauthenticated session")
	}

	// Empty credentials rejected.
	badResp, err := http.Post(ts.URL+"/api/v1/auth/login", "application/json",
		strings.NewReader(`{"username":"","password":""}`))
	if err != nil {
		t.Fatal(err)
	}
	if badResp.StatusCode != 400 {
		t.Fatalf("empty-credential login status = %d, want 400", badResp.StatusCode)
	}
	badResp.Body.Close()

	token := login(t, ts)

	resp = get(t, ts, "/api/v1/auth/session", token)
	s := decode[SessionInfo](t, resp)
	if !s.Authenticated || s.User == nil || s.User.Username != "admin" {
		t.Fatalf("session = %+v", s)
	}

	// Logout revokes the token.
	req, _ := http.NewRequest("POST", ts.URL+"/api/v1/auth/logout", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	lo, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if lo.StatusCode != 204 {
		t.Fatalf("logout status = %d", lo.StatusCode)
	}
	lo.Body.Close()

	resp = get(t, ts, "/api/v1/library/items", token)
	if resp.StatusCode != 401 {
		t.Fatalf("post-logout status = %d, want 401", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestBearerSchemeCaseInsensitive(t *testing.T) {
	ts := newAuthTestServer(t)
	token := login(t, ts)

	// The Authorization scheme name is case-insensitive; all of these must
	// authenticate the same token.
	for _, scheme := range []string{"Bearer", "bearer", "BEARER", "BeArEr"} {
		req, _ := http.NewRequest("GET", ts.URL+"/api/v1/auth/session", nil)
		req.Header.Set("Authorization", scheme+" "+token)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		s := decode[SessionInfo](t, resp)
		if !s.Authenticated {
			t.Fatalf("scheme %q: not authenticated", scheme)
		}
	}
}

func TestBearerDoesNotShadowCookie(t *testing.T) {
	ts := newAuthTestServer(t)
	token := login(t, ts)

	// A stale/garbage bearer header must not stop a valid session cookie
	// from authenticating the request.
	req, _ := http.NewRequest("GET", ts.URL+"/api/v1/auth/session", nil)
	req.Header.Set("Authorization", "Bearer not-a-real-token")
	req.AddCookie(&http.Cookie{Name: "waxdeck_session", Value: token})
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if s := decode[SessionInfo](t, resp); !s.Authenticated {
		t.Fatal("garbage bearer + valid cookie: not authenticated")
	}

	// A valid bearer still authenticates even alongside a garbage cookie.
	req, _ = http.NewRequest("GET", ts.URL+"/api/v1/auth/session", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	req.AddCookie(&http.Cookie{Name: "waxdeck_session", Value: "garbage"})
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if s := decode[SessionInfo](t, resp); !s.Authenticated {
		t.Fatal("valid bearer + garbage cookie: not authenticated")
	}
}
