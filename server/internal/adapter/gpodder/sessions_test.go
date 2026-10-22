package gpodder

import (
	"net/http"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/db"
)

// sessionCookieOf is the session cookie a response sets, nil for none.
func sessionCookieOf(resp *http.Response) *http.Cookie {
	for _, c := range resp.Cookies() {
		if c.Name == "sessionid" && c.Value != "" {
			return c
		}
	}
	return nil
}

// A request signed with Basic credentials is answered a session cookie, as
// a login is, which carries the account from then on; a request the cookie
// carries opens nothing more, signed too or not. However many signed
// requests open sessions, the logins of the same app password stay signed
// in, and revoking the app password ends both kinds.
func TestASignedRequestOpensASession(t *testing.T) {
	e := newEnv(t)
	phone := e.login("alice", e.secret)
	var opened *http.Cookie
	for range 25 {
		resp, raw := e.call("GET", "/api/2/devices/alice.json", "", true)
		mustStatus(t, resp, raw, 200)
		if opened = sessionCookieOf(resp); opened == nil {
			t.Fatal("a signed request set no session cookie")
		}
	}
	req, _ := http.NewRequest("GET", e.ts.URL+"/api/2/devices/alice.json", nil)
	req.AddCookie(opened)
	req.SetBasicAuth("alice", e.secret)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 200 || sessionCookieOf(resp) != nil {
		t.Errorf("a request the signed session's cookie carries = %d, cookie %v; want 200 and no new session",
			resp.StatusCode, sessionCookieOf(resp))
	}
	if got := e.withCookie(phone, "GET", "/api/2/devices/alice.json", ""); got != 200 {
		t.Errorf("the login after 25 signed requests = %d, want 200", got)
	}
	if err := e.svc.RevokeAppPassword(e.ctx, e.uc, e.apID); err != nil {
		t.Fatal(err)
	}
	for name, c := range map[string]*http.Cookie{"login": phone, "signed request": opened} {
		if got := e.withCookie(c, "GET", "/api/2/devices/alice.json", ""); got != 401 {
			t.Errorf("the %s's cookie after the revoke = %d, want 401", name, got)
		}
	}
}

// agedSession stores a session of the app password opened age ago, as a
// signed request or a login opens one, answering its cookie.
func (e *env) agedSession(age time.Duration, basic bool) *http.Cookie {
	e.t.Helper()
	token, hash, err := auth.NewOpaqueToken()
	if err != nil {
		e.t.Fatal(err)
	}
	passwords, err := e.store.AppPasswordsByUser(e.ctx, e.uc.ID)
	if err != nil || len(passwords) != 1 {
		e.t.Fatalf("app passwords = %+v (%v), want the one", passwords, err)
	}
	opened := time.Now().Add(-age)
	if err := e.store.InsertGpodderSession(e.ctx, db.GpodderSession{
		ID: "gs-" + token[:8], UserID: e.uc.ID, AppPasswordID: passwords[0].ID, TokenHash: hash,
		CreatedAtNS: opened.UnixNano(), ExpiresAtNS: opened.Add(14 * 24 * time.Hour).UnixNano(), Basic: basic,
	}, 20); err != nil {
		e.t.Fatal(err)
	}
	return &http.Cookie{Name: "sessionid", Value: token}
}

// A session a signed request opened renews itself when its cookie comes
// back with less than half its two weeks left: the answer carries a fresh
// cookie and the old one ends, so a client that keeps syncing is never
// asked for its password again. A login's session is the app's to renew.
func TestASignedSessionRenewsPastHalfItsLife(t *testing.T) {
	e := newEnv(t)
	send := func(c *http.Cookie) *http.Response {
		t.Helper()
		req, _ := http.NewRequest("GET", e.ts.URL+"/api/2/devices/alice.json", nil)
		req.AddCookie(c)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		return resp
	}
	if resp := send(e.agedSession(6*24*time.Hour, true)); resp.StatusCode != 200 || sessionCookieOf(resp) != nil {
		t.Errorf("a signed session six days old = %d, cookie %v; want 200 and no renewal", resp.StatusCode, sessionCookieOf(resp))
	}
	old := e.agedSession(8*24*time.Hour, true)
	resp := send(old)
	fresh := sessionCookieOf(resp)
	if resp.StatusCode != 200 || fresh == nil || fresh.Value == old.Value {
		t.Fatalf("a signed session eight days old = %d, cookie %v; want 200 and a fresh cookie", resp.StatusCode, fresh)
	}
	if got := e.withCookie(old, "GET", "/api/2/devices/alice.json", ""); got != 401 {
		t.Errorf("the renewed session's old cookie = %d, want 401", got)
	}
	if resp := send(fresh); resp.StatusCode != 200 || sessionCookieOf(resp) != nil {
		t.Errorf("the fresh cookie = %d, cookie %v; want 200 and no renewal", resp.StatusCode, sessionCookieOf(resp))
	}
	if resp := send(e.agedSession(8*24*time.Hour, false)); resp.StatusCode != 200 || sessionCookieOf(resp) != nil {
		t.Errorf("a login eight days old = %d, cookie %v; want 200 and no renewal", resp.StatusCode, sessionCookieOf(resp))
	}
}

// Sessions whose cookies never came back go before sessions whose cookies
// did: a client that signs every request and keeps no cookie turns over
// only its own, and gPodder desktop, sharing its app password, keeps its
// session and is not challenged again.
func TestCookielessRequestsDoNotPushOutAKeptSession(t *testing.T) {
	e := newEnv(t)
	laptop := newGpodderDesktop(t, e, "laptop")
	laptop.connect()
	for range 25 {
		resp, raw := e.call("GET", "/api/2/devices/alice.json", "", true)
		mustStatus(t, resp, raw, 200)
	}
	answered := laptop.lookups
	laptop.mustOK("GET", "/api/2/devices/alice.json", "", nil)
	if laptop.lookups != answered {
		t.Errorf("the laptop was challenged again after 25 cookie-less requests (challenges answered %d -> %d)", answered, laptop.lookups)
	}
}

// The session opened last always works: with twenty of an app password's
// sessions of one kind back in use, a 21st, login or signed request, ends
// the oldest of them, never itself.
func TestTheNewestSessionOutlastsTheCap(t *testing.T) {
	e := newEnv(t)
	signed := func() *http.Cookie {
		t.Helper()
		resp, raw := e.call("GET", "/api/2/devices/alice.json", "", true)
		mustStatus(t, resp, raw, 200)
		return sessionCookieOf(resp)
	}
	for kind, open := range map[string]func() *http.Cookie{
		"login":          func() *http.Cookie { return e.login("alice", e.secret) },
		"signed request": signed,
	} {
		for range 20 {
			if got := e.withCookie(open(), "GET", "/api/2/devices/alice.json", ""); got != 200 {
				t.Fatalf("a fresh %s's cookie = %d, want 200", kind, got)
			}
		}
		if got := e.withCookie(open(), "GET", "/api/2/devices/alice.json", ""); got != 200 {
			t.Errorf("the 21st %s's cookie = %d, want 200", kind, got)
		}
	}
}

// Every answer of the surface is the account's own, so none is kept by a
// cache between the app and the server: not a renewal, whose fresh cookie
// would go to whoever asked for the same URL next, not a list, and not a
// refusal.
func TestNoAnswerIsCached(t *testing.T) {
	e := newEnv(t)
	req, _ := http.NewRequest("GET", e.ts.URL+"/api/2/devices/alice.json", nil)
	req.AddCookie(e.agedSession(8*24*time.Hour, true))
	renewal, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	renewal.Body.Close()
	if sessionCookieOf(renewal) == nil {
		t.Fatalf("a signed session eight days old = %d with no fresh cookie, want its renewal", renewal.StatusCode)
	}
	list, raw := e.call("GET", "/subscriptions/alice.json", "", true)
	mustStatus(t, list, raw, 200)
	refusal, _ := e.call("GET", "/subscriptions/alice.json", "", false)
	for name, resp := range map[string]*http.Response{"a renewal": renewal, "a list": list, "a refusal": refusal} {
		if got := resp.Header.Get("Cache-Control"); got != "no-store" {
			t.Errorf("%s answered Cache-Control %q, want no-store", name, got)
		}
	}
}
