package api

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

const testPassword = "hunter2-hunter2"

// newAuthTestServer wires the strict handler exactly like cmd/waxdeck
// does, over a real (empty) catalog and store in temp dirs: the auth
// surface now spans both databases. Catalog-backed listing behavior is
// covered by the integration tests.
func newAuthTestServer(t *testing.T) *httptest.Server {
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
		Service:  svc,
		Sessions: auth.NewSessions(store),
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

func decode[T any](t *testing.T, resp *http.Response) T {
	t.Helper()
	defer resp.Body.Close()
	var v T
	if err := json.NewDecoder(resp.Body).Decode(&v); err != nil {
		t.Fatalf("decode: %v", err)
	}
	return v
}

func postJSON(t *testing.T, url, token, body string) *http.Response {
	t.Helper()
	req, _ := http.NewRequest("POST", url, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

// bootstrap creates the first admin and returns its login. Callers on
// an already-bootstrapped server fall back to a normal login.
func bootstrap(t *testing.T, ts *httptest.Server) LoginResponse {
	t.Helper()
	resp := postJSON(t, ts.URL+"/api/v1/auth/bootstrap", "",
		`{"username":"admin","password":"`+testPassword+`"}`)
	if resp.StatusCode == 409 {
		resp.Body.Close()
		return loginAs(t, ts, "admin", testPassword)
	}
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("bootstrap status = %d, want 200 (body: %s)", resp.StatusCode, body)
	}
	if sc := resp.Header.Get("Set-Cookie"); !strings.Contains(sc, "waxdeck_session=") {
		t.Fatalf("bootstrap Set-Cookie = %q, want waxdeck_session", sc)
	}
	return decode[LoginResponse](t, resp)
}

func loginAs(t *testing.T, ts *httptest.Server, username, password string) LoginResponse {
	t.Helper()
	resp := postJSON(t, ts.URL+"/api/v1/auth/login", "",
		`{"username":"`+username+`","password":"`+password+`"}`)
	if resp.StatusCode != 200 {
		t.Fatalf("login status = %d, want 200", resp.StatusCode)
	}
	if sc := resp.Header.Get("Set-Cookie"); !strings.Contains(sc, "waxdeck_session=") {
		t.Fatalf("login Set-Cookie = %q, want waxdeck_session", sc)
	}
	return decode[LoginResponse](t, resp)
}

// login bootstraps (or logs into) the built-in test admin and returns
// its bearer token; the shared helper the integration harness uses.
func login(t *testing.T, ts *httptest.Server) string {
	t.Helper()
	return bootstrap(t, ts).Token
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

func TestBootstrapFlow(t *testing.T) {
	ts := newAuthTestServer(t)

	// A fresh server wants an administrator.
	resp := get(t, ts, "/api/v1/auth/bootstrap", "")
	if st := decode[BootstrapStatus](t, resp); !st.Required {
		t.Fatal("fresh server should require bootstrap")
	}

	// A weak password is rejected before any account exists.
	weak := postJSON(t, ts.URL+"/api/v1/auth/bootstrap", "", `{"username":"admin","password":"short"}`)
	if weak.StatusCode != 400 {
		t.Fatalf("weak-password bootstrap status = %d, want 400", weak.StatusCode)
	}
	weak.Body.Close()

	lr := bootstrap(t, ts)
	if len(lr.User.Roles) == 0 || lr.User.Roles[0] != "admin" {
		t.Fatalf("bootstrap roles = %v, want [admin]", lr.User.Roles)
	}
	if lr.CsrfToken == "" {
		t.Fatal("bootstrap returned no CSRF token")
	}

	// The door is closed forever.
	resp = get(t, ts, "/api/v1/auth/bootstrap", "")
	if st := decode[BootstrapStatus](t, resp); st.Required {
		t.Fatal("bootstrap still required after first admin")
	}
	again := postJSON(t, ts.URL+"/api/v1/auth/bootstrap", "", `{"username":"admin2","password":"`+testPassword+`"}`)
	if again.StatusCode != 409 {
		t.Fatalf("second bootstrap status = %d, want 409", again.StatusCode)
	}
	again.Body.Close()

	// Wrong password now fails; the stub's accept-anything era is over.
	bad := postJSON(t, ts.URL+"/api/v1/auth/login", "", `{"username":"admin","password":"wrong-wrong-wrong"}`)
	if bad.StatusCode != 401 {
		t.Fatalf("wrong-password login status = %d, want 401", bad.StatusCode)
	}
	bad.Body.Close()
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
	badResp := postJSON(t, ts.URL+"/api/v1/auth/login", "", `{"username":"","password":""}`)
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
	if s.CsrfToken == nil || *s.CsrfToken == "" {
		t.Fatal("authenticated session carries no CSRF token")
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

func TestCSRFEnforcedForCookieMutations(t *testing.T) {
	ts := newAuthTestServer(t)
	lr := bootstrap(t, ts)

	// A cookie-authenticated mutation without the CSRF header is refused.
	req, _ := http.NewRequest("PUT", ts.URL+"/api/v1/users/me/prefs", strings.NewReader(`{}`))
	req.Header.Set("Content-Type", "application/json")
	req.AddCookie(&http.Cookie{Name: "waxdeck_session", Value: lr.Token})
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 403 {
		t.Fatalf("cookie mutation without CSRF = %d, want 403", resp.StatusCode)
	}
	resp.Body.Close()

	// With the header it goes through.
	req, _ = http.NewRequest("PUT", ts.URL+"/api/v1/users/me/prefs", strings.NewReader(`{}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Csrf-Token", lr.CsrfToken)
	req.AddCookie(&http.Cookie{Name: "waxdeck_session", Value: lr.Token})
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("cookie mutation with CSRF = %d, want 200", resp.StatusCode)
	}
	resp.Body.Close()

	// Bearer-authenticated mutations never need it.
	req, _ = http.NewRequest("PUT", ts.URL+"/api/v1/users/me/prefs", strings.NewReader(`{}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+lr.Token)
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("bearer mutation without CSRF = %d, want 200", resp.StatusCode)
	}
	resp.Body.Close()

	// Cookie GETs stay free of it.
	req, _ = http.NewRequest("GET", ts.URL+"/api/v1/users/me/prefs", nil)
	req.AddCookie(&http.Cookie{Name: "waxdeck_session", Value: lr.Token})
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("cookie GET = %d, want 200", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestSessionRevocationKillsDevice(t *testing.T) {
	ts := newAuthTestServer(t)
	admin := bootstrap(t, ts)

	// A second login registers as a named device.
	phone := postJSON(t, ts.URL+"/api/v1/auth/login", "",
		`{"username":"admin","password":"`+testPassword+`","deviceName":"Test Phone"}`)
	phoneLR := decode[LoginResponse](t, phone)

	// Both sessions appear in the device list; find the phone.
	resp := get(t, ts, "/api/v1/auth/sessions", admin.Token)
	list := decode[SessionList](t, resp)
	if len(list.Sessions) != 2 {
		t.Fatalf("session count = %d, want 2", len(list.Sessions))
	}
	var phoneID string
	for _, s := range list.Sessions {
		if s.DeviceName != nil && *s.DeviceName == "Test Phone" {
			phoneID = s.Id
			if s.Kind != "device" {
				t.Fatalf("phone session kind = %q, want device", s.Kind)
			}
			if s.Current {
				t.Fatal("phone session must not be current for the admin token")
			}
		}
	}
	if phoneID == "" {
		t.Fatal("phone session not in device list")
	}

	// The phone works, then the other session revokes it, then it is dead.
	resp = get(t, ts, "/api/v1/auth/session", phoneLR.Token)
	if s := decode[SessionInfo](t, resp); !s.Authenticated {
		t.Fatal("phone token should authenticate before revocation")
	}
	req, _ := http.NewRequest("DELETE", ts.URL+"/api/v1/auth/sessions/"+phoneID, nil)
	req.Header.Set("Authorization", "Bearer "+admin.Token)
	rev, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if rev.StatusCode != 204 {
		t.Fatalf("revoke status = %d, want 204", rev.StatusCode)
	}
	rev.Body.Close()

	resp = get(t, ts, "/api/v1/library/items", phoneLR.Token)
	if resp.StatusCode != 401 {
		t.Fatalf("revoked device status = %d, want 401", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestTokenRefreshRotates(t *testing.T) {
	ts := newAuthTestServer(t)
	bootstrap(t, ts)
	lr := decode[LoginResponse](t, postJSON(t, ts.URL+"/api/v1/auth/login", "",
		`{"username":"admin","password":"`+testPassword+`","deviceName":"Rotator"}`))

	resp := postJSON(t, ts.URL+"/api/v1/auth/refresh", lr.Token, "")
	if resp.StatusCode != 200 {
		t.Fatalf("refresh status = %d, want 200", resp.StatusCode)
	}
	rotated := decode[LoginResponse](t, resp)
	if rotated.Token == lr.Token {
		t.Fatal("refresh returned the same token")
	}

	// The new token authenticates; the old one still works inside the
	// overlap window (in-flight requests must not fail).
	if resp := get(t, ts, "/api/v1/auth/session", rotated.Token); !decode[SessionInfo](t, resp).Authenticated {
		t.Fatal("rotated token does not authenticate")
	}
	if resp := get(t, ts, "/api/v1/auth/session", lr.Token); !decode[SessionInfo](t, resp).Authenticated {
		t.Fatal("pre-rotation token should authenticate inside the overlap window")
	}

	// The device list still shows one session for the device.
	list := decode[SessionList](t, get(t, ts, "/api/v1/auth/sessions", rotated.Token))
	names := 0
	for _, s := range list.Sessions {
		if s.DeviceName != nil && *s.DeviceName == "Rotator" {
			names++
		}
	}
	if names != 1 {
		t.Fatalf("rotator sessions = %d, want 1", names)
	}
}

func TestLoginRateLimiting(t *testing.T) {
	ts := newAuthTestServer(t)
	bootstrap(t, ts)

	status := 0
	for range 12 {
		resp := postJSON(t, ts.URL+"/api/v1/auth/login", "",
			`{"username":"admin","password":"wrong-wrong-wrong"}`)
		status = resp.StatusCode
		resp.Body.Close()
		if status == 429 {
			break
		}
	}
	if status != 429 {
		t.Fatalf("hammering wrong passwords never rate-limited (last status %d)", status)
	}
}

func TestUserAdminLifecycle(t *testing.T) {
	ts := newAuthTestServer(t)
	admin := bootstrap(t, ts)

	// Create a second user.
	resp := postJSON(t, ts.URL+"/api/v1/users", admin.Token,
		`{"username":"frodo","password":"`+testPassword+`","displayName":"Frodo"}`)
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d, want 201", resp.StatusCode)
	}
	frodo := decode[UserAccount](t, resp)
	if frodo.Username != "frodo" || frodo.Disabled {
		t.Fatalf("created = %+v", frodo)
	}

	// Case-insensitive duplicate conflicts.
	dup := postJSON(t, ts.URL+"/api/v1/users", admin.Token,
		`{"username":"FRODO","password":"`+testPassword+`"}`)
	if dup.StatusCode != 409 {
		t.Fatalf("duplicate username status = %d, want 409", dup.StatusCode)
	}
	dup.Body.Close()

	// The new user can log in and sees itself, but not the admin surface.
	frodoLR := loginAs(t, ts, "frodo", testPassword)
	if resp := get(t, ts, "/api/v1/users", frodoLR.Token); resp.StatusCode != 403 {
		t.Fatalf("non-admin user list status = %d, want 403", resp.StatusCode)
	}
	if resp := get(t, ts, "/api/v1/users/"+frodo.Id, frodoLR.Token); resp.StatusCode != 200 {
		t.Fatalf("self view status = %d, want 200", resp.StatusCode)
	}
	if resp := get(t, ts, "/api/v1/users/"+admin.User.Id, frodoLR.Token); resp.StatusCode != 403 {
		t.Fatalf("cross-user view status = %d, want 403", resp.StatusCode)
	}

	// Non-admin cannot grant roles, not even to itself.
	esc, _ := http.NewRequest("PATCH", ts.URL+"/api/v1/users/"+frodo.Id, strings.NewReader(`{"roles":["admin"]}`))
	esc.Header.Set("Content-Type", "application/json")
	esc.Header.Set("Authorization", "Bearer "+frodoLR.Token)
	escResp, err := http.DefaultClient.Do(esc)
	if err != nil {
		t.Fatal(err)
	}
	if escResp.StatusCode != 403 {
		t.Fatalf("self role escalation status = %d, want 403", escResp.StatusCode)
	}
	escResp.Body.Close()

	// The last enabled admin cannot demote itself.
	demote, _ := http.NewRequest("PATCH", ts.URL+"/api/v1/users/"+admin.User.Id, strings.NewReader(`{"roles":["user"]}`))
	demote.Header.Set("Content-Type", "application/json")
	demote.Header.Set("Authorization", "Bearer "+admin.Token)
	demoteResp, err := http.DefaultClient.Do(demote)
	if err != nil {
		t.Fatal(err)
	}
	if demoteResp.StatusCode != 409 {
		t.Fatalf("last-admin demotion status = %d, want 409", demoteResp.StatusCode)
	}
	demoteResp.Body.Close()

	// Deleting the account revokes its access.
	del, _ := http.NewRequest("DELETE", ts.URL+"/api/v1/users/"+frodo.Id, nil)
	del.Header.Set("Authorization", "Bearer "+admin.Token)
	delResp, err := http.DefaultClient.Do(del)
	if err != nil {
		t.Fatal(err)
	}
	if delResp.StatusCode != 204 {
		t.Fatalf("delete user status = %d, want 204", delResp.StatusCode)
	}
	delResp.Body.Close()
	if resp := get(t, ts, "/api/v1/auth/session", frodoLR.Token); decode[SessionInfo](t, resp).Authenticated {
		t.Fatal("deleted user's token still authenticates")
	}
}

func TestPasswordChangeRevokesOtherSessions(t *testing.T) {
	ts := newAuthTestServer(t)
	admin := bootstrap(t, ts)
	other := loginAs(t, ts, "admin", testPassword)

	// Wrong current password is refused.
	bad, _ := http.NewRequest("PUT", ts.URL+"/api/v1/users/"+admin.User.Id+"/password",
		strings.NewReader(`{"currentPassword":"nope-nope-nope","newPassword":"`+testPassword+`x"}`))
	bad.Header.Set("Content-Type", "application/json")
	bad.Header.Set("Authorization", "Bearer "+admin.Token)
	badResp, err := http.DefaultClient.Do(bad)
	if err != nil {
		t.Fatal(err)
	}
	if badResp.StatusCode != 403 {
		t.Fatalf("wrong current password status = %d, want 403", badResp.StatusCode)
	}
	badResp.Body.Close()

	// Correct change keeps this session, kills the other.
	ok, _ := http.NewRequest("PUT", ts.URL+"/api/v1/users/"+admin.User.Id+"/password",
		strings.NewReader(`{"currentPassword":"`+testPassword+`","newPassword":"`+testPassword+`x"}`))
	ok.Header.Set("Content-Type", "application/json")
	ok.Header.Set("Authorization", "Bearer "+admin.Token)
	okResp, err := http.DefaultClient.Do(ok)
	if err != nil {
		t.Fatal(err)
	}
	if okResp.StatusCode != 204 {
		t.Fatalf("password change status = %d, want 204", okResp.StatusCode)
	}
	okResp.Body.Close()

	if resp := get(t, ts, "/api/v1/auth/session", admin.Token); !decode[SessionInfo](t, resp).Authenticated {
		t.Fatal("changing session should survive its own password change")
	}
	if resp := get(t, ts, "/api/v1/auth/session", other.Token); decode[SessionInfo](t, resp).Authenticated {
		t.Fatal("other session should be revoked by the password change")
	}
	if lr := loginAs(t, ts, "admin", testPassword+"x"); lr.Token == "" {
		t.Fatal("new password does not log in")
	}
}

func TestPrefsRoundTrip(t *testing.T) {
	ts := newAuthTestServer(t)
	lr := bootstrap(t, ts)

	// Empty at first.
	p := decode[Prefs](t, get(t, ts, "/api/v1/users/me/prefs", lr.Token))
	if p.Timezone != nil || p.Theme != nil {
		t.Fatalf("fresh prefs = %+v, want empty", p)
	}

	// Store, read back.
	req, _ := http.NewRequest("PUT", ts.URL+"/api/v1/users/me/prefs",
		strings.NewReader(`{"timezone":"America/Denver","theme":"oled"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+lr.Token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	stored := decode[Prefs](t, resp)
	if stored.Timezone == nil || *stored.Timezone != "America/Denver" {
		t.Fatalf("stored prefs = %+v", stored)
	}
	p = decode[Prefs](t, get(t, ts, "/api/v1/users/me/prefs", lr.Token))
	if p.Theme == nil || *p.Theme != "oled" {
		t.Fatalf("read-back prefs = %+v", p)
	}

	// A bogus timezone is rejected.
	req, _ = http.NewRequest("PUT", ts.URL+"/api/v1/users/me/prefs",
		strings.NewReader(`{"timezone":"Middle/Earth"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+lr.Token)
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 400 {
		t.Fatalf("bad timezone status = %d, want 400", resp.StatusCode)
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
