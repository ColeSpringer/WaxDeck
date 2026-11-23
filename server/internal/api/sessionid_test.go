package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// currentSession is the id the device list marks current for token.
func currentSession(t *testing.T, ts *httptest.Server, token string) string {
	t.Helper()
	list := decode[SessionList](t, get(t, ts, "/api/v1/auth/sessions", token))
	for _, s := range list.Sessions {
		if s.Current {
			return s.Id
		}
	}
	t.Fatal("no current session in the device list")
	return ""
}

func wantSessionID(t *testing.T, road string, got *string, want string) {
	t.Helper()
	if got == nil {
		t.Fatalf("%s: no sessionId, want %q", road, want)
	}
	if *got != want {
		t.Fatalf("%s: sessionId = %q, want %q", road, *got, want)
	}
}

func TestBootstrapAndLoginAnswersNameTheirSession(t *testing.T) {
	t.Parallel()
	ts := newAuthTestServer(t)

	first := bootstrap(t, ts)
	wantSessionID(t, "bootstrap", &first.SessionId, currentSession(t, ts, first.Token))

	again := loginAs(t, ts, "admin", testPassword)
	wantSessionID(t, "login", &again.SessionId, currentSession(t, ts, again.Token))
	if again.SessionId == first.SessionId {
		t.Fatal("a second sign-in named the first one's session")
	}
}

func TestSessionReadNamesTheSessionServingIt(t *testing.T) {
	t.Parallel()
	ts := newAuthTestServer(t)
	lr := bootstrap(t, ts)
	want := currentSession(t, ts, lr.Token)

	byBearer := decode[SessionInfo](t, get(t, ts, "/api/v1/auth/session", lr.Token))
	wantSessionID(t, "bearer", byBearer.SessionId, want)

	req, _ := http.NewRequest("GET", ts.URL+"/api/v1/auth/session", nil)
	req.AddCookie(&http.Cookie{Name: "waxdeck_session", Value: lr.Token})
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	byCookie := decode[SessionInfo](t, resp)
	wantSessionID(t, "cookie", byCookie.SessionId, want)

	nobody := decode[SessionInfo](t, get(t, ts, "/api/v1/auth/session", ""))
	if nobody.Authenticated || nobody.SessionId != nil {
		t.Fatalf("unauthenticated read = %+v, want no session id", nobody)
	}
}

func TestRefreshAnswerNamesTheSessionItRotated(t *testing.T) {
	t.Parallel()
	ts := newAuthTestServer(t)
	bootstrap(t, ts)
	lr := decode[LoginResponse](t, postJSON(t, ts.URL+"/api/v1/auth/login", "",
		`{"username":"admin","password":"`+testPassword+`","deviceName":"Rotator"}`))

	resp := postJSON(t, ts.URL+"/api/v1/auth/refresh", lr.Token, "")
	if resp.StatusCode != 200 {
		t.Fatalf("refresh status = %d, want 200", resp.StatusCode)
	}
	rotated := decode[LoginResponse](t, resp)
	session := currentSession(t, ts, rotated.Token)
	wantSessionID(t, "refresh", &rotated.SessionId, session)
	wantSessionID(t, "the login before it", &lr.SessionId, session)
}
