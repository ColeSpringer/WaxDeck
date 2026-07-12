package api

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// newTestServer wires the strict handler exactly like cmd/waxdeck does.
func newTestServer(t *testing.T) *httptest.Server {
	t.Helper()
	srv := NewServer("test")
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
	ts := newTestServer(t)
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
	ts := newTestServer(t)

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

func TestListItemsPagination(t *testing.T) {
	ts := newTestServer(t)
	token := login(t, ts)

	// Page through the dev catalog one item at a time; cursors must neither
	// skip nor duplicate.
	var seen []string
	cursor := ""
	for range 10 {
		path := "/api/v1/library/items?limit=1"
		if cursor != "" {
			path += "&cursor=" + cursor
		}
		resp := get(t, ts, path, token)
		if resp.StatusCode != 200 {
			t.Fatalf("status = %d", resp.StatusCode)
		}
		page := decode[ItemPage](t, resp)
		for _, it := range page.Items {
			seen = append(seen, it.Pid)
		}
		if page.NextCursor == nil {
			break
		}
		cursor = *page.NextCursor
	}
	if len(seen) != 3 {
		t.Fatalf("paged pids = %v, want 3 distinct", seen)
	}
	uniq := map[string]bool{}
	for _, pid := range seen {
		uniq[pid] = true
	}
	if len(uniq) != 3 {
		t.Fatalf("duplicate pids across pages: %v", seen)
	}

	// Media-type filter.
	resp := get(t, ts, "/api/v1/library/items?mediaType=audiobook", token)
	page := decode[ItemPage](t, resp)
	if len(page.Items) != 1 || page.Items[0].MediaType != Audiobook {
		t.Fatalf("filtered page = %+v", page)
	}

	// Bad cursor is a structured 400.
	resp = get(t, ts, "/api/v1/library/items?cursor=%21%21not-base64%21%21", token)
	if resp.StatusCode != 400 {
		t.Fatalf("bad-cursor status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "invalid-request" {
		t.Fatalf("bad-cursor code = %q", e.Code)
	}

	// Bad enum value is caught by generated binding.
	resp = get(t, ts, "/api/v1/library/items?mediaType=video", token)
	if resp.StatusCode != 400 {
		t.Fatalf("bad-mediaType status = %d, want 400", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestBearerSchemeCaseInsensitive(t *testing.T) {
	ts := newTestServer(t)
	token := login(t, ts)

	// The Authorization scheme name is case-insensitive; all of these must
	// authenticate the same token.
	for _, scheme := range []string{"Bearer", "bearer", "BEARER", "BeArEr"} {
		req, _ := http.NewRequest("GET", ts.URL+"/api/v1/library/items", nil)
		req.Header.Set("Authorization", scheme+" "+token)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != 200 {
			t.Fatalf("scheme %q: status = %d, want 200", scheme, resp.StatusCode)
		}
	}
}

func TestListItemsLimitValidation(t *testing.T) {
	ts := newTestServer(t)
	token := login(t, ts)

	// Out-of-range limits are rejected as 400. Without validation, limit=0 and
	// negative limits panic on invalid slice bounds (a dropped connection here
	// would surface as a request error, not a 400).
	for _, bad := range []string{"0", "-1", "501", "99999"} {
		resp := get(t, ts, "/api/v1/library/items?limit="+bad, token)
		if resp.StatusCode != 400 {
			t.Fatalf("limit=%s: status = %d, want 400", bad, resp.StatusCode)
		}
		if e := decode[Error](t, resp); e.Code != "invalid-request" {
			t.Fatalf("limit=%s: code = %q", bad, e.Code)
		}
	}

	// In-range limits (including the spec's boundaries) succeed.
	for _, ok := range []string{"1", "100", "500"} {
		resp := get(t, ts, "/api/v1/library/items?limit="+ok, token)
		if resp.StatusCode != 200 {
			t.Fatalf("limit=%s: status = %d, want 200", ok, resp.StatusCode)
		}
		resp.Body.Close()
	}
}

func TestBearerDoesNotShadowCookie(t *testing.T) {
	ts := newTestServer(t)
	token := login(t, ts)

	// A stale/garbage bearer header must not stop a valid session cookie from
	// authenticating the request.
	req, _ := http.NewRequest("GET", ts.URL+"/api/v1/library/items", nil)
	req.Header.Set("Authorization", "Bearer not-a-real-token")
	req.AddCookie(&http.Cookie{Name: "waxdeck_session", Value: token})
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("garbage bearer + valid cookie: status = %d, want 200", resp.StatusCode)
	}

	// A valid bearer still authenticates even alongside a garbage cookie.
	req, _ = http.NewRequest("GET", ts.URL+"/api/v1/library/items", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	req.AddCookie(&http.Cookie{Name: "waxdeck_session", Value: "garbage"})
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("valid bearer + garbage cookie: status = %d, want 200", resp.StatusCode)
	}
}

func TestCursorRoundTrip(t *testing.T) {
	// Length-prefixing must survive any title content, including the null
	// bytes a fixed delimiter would split on.
	cases := []struct{ title, pid string }{
		{"Prancing Pony Blues", "tr-01JZWAXDECKDEVTRACK000000A"},
		{"", "tr-00000000000000000000000A"},
		{"title\x00with\x00nulls", "tr-00000000000000000000001A"},
		{"emoji 🎧 unicode ☕", "tr-00000000000000000000002A"},
		{"trailing\x00", "bk-00000000000000000000003A"},
	}
	for _, c := range cases {
		title, pid, err := decodeCursor(encodeCursor(c.title, c.pid))
		if err != nil {
			t.Fatalf("round-trip %q: unexpected error %v", c.title, err)
		}
		if title != c.title || pid != c.pid {
			t.Fatalf("round-trip: got (%q,%q), want (%q,%q)", title, pid, c.title, c.pid)
		}
	}

	// Malformed cursors are rejected cleanly (no panic, no giant allocation).
	bad := []string{
		"!!!not-base64!!!",
		base64.RawURLEncoding.EncodeToString(nil),                    // empty
		base64.RawURLEncoding.EncodeToString([]byte{0x05, 'a', 'b'}), // claims len 5, has 2
	}
	for _, c := range bad {
		if _, _, err := decodeCursor(c); err == nil {
			t.Fatalf("decodeCursor(%q) = nil error, want error", c)
		}
	}
}

func TestItemAndPlayInfo(t *testing.T) {
	ts := newTestServer(t)
	token := login(t, ts)

	resp := get(t, ts, "/api/v1/library/items?mediaType=music", token)
	page := decode[ItemPage](t, resp)
	if len(page.Items) == 0 {
		t.Fatal("empty music page")
	}
	pid := page.Items[0].Pid

	resp = get(t, ts, "/api/v1/items/"+pid, token)
	if resp.StatusCode != 200 {
		t.Fatalf("item status = %d", resp.StatusCode)
	}
	item := decode[Item](t, resp)
	if item.Pid != pid || item.AddedAt == nil {
		t.Fatalf("item = %+v", item)
	}

	resp = get(t, ts, "/api/v1/items/"+pid+"/play-info", token)
	if resp.StatusCode != 200 {
		t.Fatalf("play-info status = %d", resp.StatusCode)
	}
	pi := decode[PlayInfo](t, resp)
	if !strings.HasPrefix(pi.Url, "/media/stream?pid="+pid) {
		t.Fatalf("play-info url = %q", pi.Url)
	}
	if pi.MimeType == "" || pi.DurationMs != item.DurationMs {
		t.Fatalf("play-info = %+v", pi)
	}

	// Unknown but well-formed PID gives a structured 404.
	resp = get(t, ts, "/api/v1/items/tr-01JZX5N8QW3F4V9T2B7KDEAD00", token)
	if resp.StatusCode != 404 {
		t.Fatalf("missing-item status = %d, want 404", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "not-found" {
		t.Fatalf("missing-item code = %q", e.Code)
	}
}
