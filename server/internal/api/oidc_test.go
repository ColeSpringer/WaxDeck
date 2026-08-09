package api

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"io"
	"log/slog"
	"math/big"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// fakeIdP is a minimal OIDC provider: discovery, JWKS, and a token
// endpoint that signs whatever claims the test asked for.
type fakeIdP struct {
	ts     *httptest.Server
	key    *rsa.PrivateKey
	claims map[string]any // extra claims for the next token
}

func newFakeIdP(t *testing.T) *fakeIdP {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	idp := &fakeIdP{key: key, claims: map[string]any{}}
	mux := http.NewServeMux()
	mux.HandleFunc("/.well-known/openid-configuration", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"issuer":                                idp.ts.URL,
			"authorization_endpoint":                idp.ts.URL + "/authorize",
			"token_endpoint":                        idp.ts.URL + "/token",
			"jwks_uri":                              idp.ts.URL + "/keys",
			"id_token_signing_alg_values_supported": []string{"RS256"},
			"response_types_supported":              []string{"code"},
			"subject_types_supported":               []string{"public"},
		})
	})
	mux.HandleFunc("/keys", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"keys": []map[string]any{{
				"kty": "RSA", "alg": "RS256", "use": "sig", "kid": "test",
				"n": base64.RawURLEncoding.EncodeToString(key.N.Bytes()),
				"e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(key.E)).Bytes()),
			}},
		})
	})
	mux.HandleFunc("/token", func(w http.ResponseWriter, r *http.Request) {
		claims := map[string]any{
			"iss": idp.ts.URL,
			"aud": "waxdeck-test",
			"sub": "subject-1",
			"iat": time.Now().Unix(),
			"exp": time.Now().Add(time.Hour).Unix(),
		}
		for k, v := range idp.claims {
			claims[k] = v
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"access_token": "fake-access",
			"token_type":   "Bearer",
			"id_token":     idp.signJWT(t, claims),
		})
	})
	idp.ts = httptest.NewServer(mux)
	t.Cleanup(idp.ts.Close)
	return idp
}

func (idp *fakeIdP) signJWT(t *testing.T, claims map[string]any) string {
	t.Helper()
	header, _ := json.Marshal(map[string]string{"alg": "RS256", "kid": "test", "typ": "JWT"})
	payload, _ := json.Marshal(claims)
	signing := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(payload)
	sum := sha256.Sum256([]byte(signing))
	sig, err := rsa.SignPKCS1v15(rand.Reader, idp.key, crypto.SHA256, sum[:])
	if err != nil {
		t.Fatal(err)
	}
	return signing + "." + base64.RawURLEncoding.EncodeToString(sig)
}

// newOidcTestServer wires a server with the fake IdP configured.
func newOidcTestServer(t *testing.T, idp *fakeIdP) *httptest.Server {
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

	oidc, err := auth.NewOIDC(ctx, auth.OIDCConfig{
		ID:          "dex",
		DisplayName: "Test SSO",
		Issuer:      idp.ts.URL,
		ClientID:    "waxdeck-test",
		GroupsClaim: "groups",
		AdminGroup:  "waxdeck-admins",
	}, store)
	if err != nil {
		t.Fatal(err)
	}

	var ts *httptest.Server
	srv := NewServer("test", Options{
		Service:  svc,
		Sessions: auth.NewSessions(store),
		OIDC:     oidc,
		// PublicBase is stamped after the listener exists.
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
	ts = httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	srv.publicBase = ts.URL
	return ts
}

// noRedirect returns a client that surfaces 302s instead of following
// them (the assertions need the Location values).
func noRedirect() *http.Client {
	return &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}}
}

func TestOidcWebFlow(t *testing.T) {
	t.Parallel()
	idp := newFakeIdP(t)
	idp.claims["preferred_username"] = "gandalf"
	idp.claims["name"] = "Gandalf the Grey"
	idp.claims["groups"] = []string{"waxdeck-admins"}
	ts := newOidcTestServer(t, idp)
	client := noRedirect()

	// Providers listing names the flow's start URL.
	resp, err := http.Get(ts.URL + "/api/v1/auth/oidc/providers")
	if err != nil {
		t.Fatal(err)
	}
	provs := decode[OidcProviders](t, resp)
	if len(provs.Providers) != 1 || provs.Providers[0].Id != "dex" {
		t.Fatalf("providers = %+v", provs)
	}

	// Start redirects to the IdP with state and PKCE.
	resp, err = client.Get(ts.URL + "/api/v1/auth/oidc/start?provider=dex&redirect=%2Flibrary")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 302 {
		t.Fatalf("start status = %d, want 302", resp.StatusCode)
	}
	authURL, err := url.Parse(resp.Header.Get("Location"))
	if err != nil {
		t.Fatal(err)
	}
	state := authURL.Query().Get("state")
	if state == "" || authURL.Query().Get("code_challenge") == "" {
		t.Fatalf("authorization URL missing state or PKCE: %s", authURL)
	}

	// The provider redirects back; the callback logs in and lands in the SPA.
	resp, err = client.Get(ts.URL + "/api/v1/auth/oidc/callback?code=fake-code&state=" + url.QueryEscape(state))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 302 {
		t.Fatalf("callback status = %d, want 302", resp.StatusCode)
	}
	if loc := resp.Header.Get("Location"); loc != "/library" {
		t.Fatalf("callback Location = %q, want /library", loc)
	}
	var sessionToken string
	for _, c := range resp.Cookies() {
		if c.Name == "waxdeck_session" {
			sessionToken = c.Value
		}
	}
	if sessionToken == "" {
		t.Fatal("callback set no session cookie")
	}

	// The JIT-provisioned account carries the group-mapped admin role.
	req, _ := http.NewRequest("GET", ts.URL+"/api/v1/auth/session", nil)
	req.AddCookie(&http.Cookie{Name: "waxdeck_session", Value: sessionToken})
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	s := decode[SessionInfo](t, resp)
	if !s.Authenticated || s.User == nil {
		t.Fatalf("session = %+v", s)
	}
	if s.User.Username != "gandalf" {
		t.Fatalf("username = %q, want gandalf", s.User.Username)
	}
	admin := false
	for _, r := range s.User.Roles {
		admin = admin || r == "admin"
	}
	if !admin {
		t.Fatalf("roles = %v, want admin via group claim", s.User.Roles)
	}

	// A replayed state is single-use.
	resp, err = client.Get(ts.URL + "/api/v1/auth/oidc/callback?code=fake-code&state=" + url.QueryEscape(state))
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || !strings.Contains(string(body), "Sign-on failed") {
		t.Fatalf("replayed state: status %d body %.80s", resp.StatusCode, body)
	}

	// A second login maps onto the same account, not a duplicate.
	resp, err = client.Get(ts.URL + "/api/v1/auth/oidc/start?provider=dex")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	state2 := mustQueryParam(t, resp.Header.Get("Location"), "state")
	resp, err = client.Get(ts.URL + "/api/v1/auth/oidc/callback?code=fake-code&state=" + url.QueryEscape(state2))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	var secondToken string
	for _, c := range resp.Cookies() {
		if c.Name == "waxdeck_session" {
			secondToken = c.Value
		}
	}
	req, _ = http.NewRequest("GET", ts.URL+"/api/v1/auth/session", nil)
	req.AddCookie(&http.Cookie{Name: "waxdeck_session", Value: secondToken})
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	s2 := decode[SessionInfo](t, resp)
	if s2.User == nil || s2.User.Id != s.User.Id {
		t.Fatalf("second login user = %+v, want same account %s", s2.User, s.User.Id)
	}
}

func TestOidcLoginBeforeBootstrapKeepsSetupOpen(t *testing.T) {
	t.Parallel()
	idp := newFakeIdP(t)
	idp.claims["preferred_username"] = "pippin"
	ts := newOidcTestServer(t, idp)
	client := noRedirect()

	// An SSO user signs in before any local setup happened. The fake
	// IdP maps no admin group, so the account is a plain user.
	resp, err := client.Get(ts.URL + "/api/v1/auth/oidc/start?provider=dex")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	state := mustQueryParam(t, resp.Header.Get("Location"), "state")
	resp, err = client.Get(ts.URL + "/api/v1/auth/oidc/callback?code=fake-code&state=" + url.QueryEscape(state))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 302 {
		t.Fatalf("callback status = %d, want 302", resp.StatusCode)
	}

	// The setup door must still be open: the server has no administrator.
	resp = get(t, ts, "/api/v1/auth/bootstrap", "")
	if st := decode[BootstrapStatus](t, resp); !st.Required {
		t.Fatal("an adminless server closed the setup door")
	}
	lr := bootstrap(t, ts)
	if len(lr.User.Roles) == 0 || lr.User.Roles[0] != "admin" {
		t.Fatalf("bootstrap roles = %v", lr.User.Roles)
	}

	// Now it is closed.
	resp = get(t, ts, "/api/v1/auth/bootstrap", "")
	if st := decode[BootstrapStatus](t, resp); st.Required {
		t.Fatal("setup door still open after an administrator exists")
	}
}

func TestOidcCodeFlowWithChallenge(t *testing.T) {
	t.Parallel()
	idp := newFakeIdP(t)
	idp.claims["preferred_username"] = "samwise"
	ts := newOidcTestServer(t, idp)
	client := noRedirect()

	verifier := "test-verifier-of-sufficient-length"
	sum := sha256.Sum256([]byte(verifier))
	challenge := base64.RawURLEncoding.EncodeToString(sum[:])

	resp, err := client.Get(ts.URL + "/api/v1/auth/oidc/start?provider=dex&mode=code&challenge=" + url.QueryEscape(challenge))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	state := mustQueryParam(t, resp.Header.Get("Location"), "state")

	resp, err = client.Get(ts.URL + "/api/v1/auth/oidc/callback?code=fake-code&state=" + url.QueryEscape(state))
	if err != nil {
		t.Fatal(err)
	}
	page, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("code-mode callback status = %d", resp.StatusCode)
	}
	otc := extractCode(t, string(page))

	// Redeeming without the verifier fails; the code survives being
	// guessed at... no, single-use means the failed attempt burned it?
	// No: a verifier mismatch must burn the code too (an interceptor
	// must not get retries), so mint a fresh flow for the happy path.
	resp = postJSON(t, ts.URL+"/api/v1/auth/oidc/exchange", "", `{"code":"`+otc+`"}`)
	if resp.StatusCode != 401 {
		t.Fatalf("exchange without verifier = %d, want 401", resp.StatusCode)
	}
	resp.Body.Close()
	resp = postJSON(t, ts.URL+"/api/v1/auth/oidc/exchange", "", `{"code":"`+otc+`","verifier":"`+verifier+`"}`)
	if resp.StatusCode != 401 {
		t.Fatalf("burned code redeemed = %d, want 401 (single use)", resp.StatusCode)
	}
	resp.Body.Close()

	// Fresh flow, correct verifier: a device session comes back.
	resp, err = client.Get(ts.URL + "/api/v1/auth/oidc/start?provider=dex&mode=code&challenge=" + url.QueryEscape(challenge))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	state = mustQueryParam(t, resp.Header.Get("Location"), "state")
	resp, err = client.Get(ts.URL + "/api/v1/auth/oidc/callback?code=fake-code&state=" + url.QueryEscape(state))
	if err != nil {
		t.Fatal(err)
	}
	page, _ = io.ReadAll(resp.Body)
	resp.Body.Close()
	otc = extractCode(t, string(page))

	resp = postJSON(t, ts.URL+"/api/v1/auth/oidc/exchange", "",
		`{"code":"`+otc+`","verifier":"`+verifier+`","deviceName":"CLI"}`)
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("exchange with verifier = %d (body %s)", resp.StatusCode, body)
	}
	lr := decode[LoginResponse](t, resp)
	if lr.User.Username != "samwise" || lr.Token == "" {
		t.Fatalf("exchange login = %+v", lr)
	}
}

func mustQueryParam(t *testing.T, rawURL, key string) string {
	t.Helper()
	u, err := url.Parse(rawURL)
	if err != nil {
		t.Fatal(err)
	}
	v := u.Query().Get(key)
	if v == "" {
		t.Fatalf("no %q in %s", key, rawURL)
	}
	return v
}

// extractCode pulls the one-time code out of the code-mode HTML page.
func extractCode(t *testing.T, page string) string {
	t.Helper()
	_, rest, ok := strings.Cut(page, "<code>")
	if !ok {
		t.Fatalf("no <code> element in page: %.200s", page)
	}
	code, _, ok := strings.Cut(rest, "</code>")
	if !ok {
		t.Fatalf("unterminated <code> element")
	}
	return strings.TrimSpace(code)
}
