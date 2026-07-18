// Command testidp is a minimal OIDC identity provider for the
// end-to-end harness: discovery, JWKS, an interactive login form on
// the authorization endpoint, and a token endpoint that enforces PKCE
// (S256) and single-use codes. It exists so browser-driven single
// sign-on tests run against a real HTTP identity provider without
// pulling a container stack into the bare-binary harness. It holds no
// state beyond process memory and must never face a real network.
package main

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"flag"
	"fmt"
	"html/template"
	"log"
	"math/big"
	"net/http"
	"net/url"
	"os"
	"sync"
	"time"
)

type issuedCode struct {
	redirectURI string
	challenge   string // PKCE S256 code challenge
	expires     time.Time
}

type idp struct {
	issuer   string
	key      *rsa.PrivateKey
	clientID string
	username string
	password string
	email    string
	groups   []string

	mu    sync.Mutex
	codes map[string]issuedCode
}

func main() {
	var (
		addr     = flag.String("addr", envOr("TESTIDP_ADDR", "127.0.0.1:4419"), "listen address")
		issuer   = flag.String("issuer", envOr("TESTIDP_ISSUER", ""), "issuer URL (defaults to http://<addr>)")
		clientID = flag.String("client-id", envOr("TESTIDP_CLIENT_ID", "waxdeck-e2e"), "accepted client id")
		username = flag.String("username", envOr("TESTIDP_USERNAME", "gandalf"), "the one accepted username")
		password = flag.String("password", envOr("TESTIDP_PASSWORD", "mithrandir-e2e"), "the one accepted password")
		email    = flag.String("email", envOr("TESTIDP_EMAIL", "gandalf@e2e.invalid"), "email claim")
		groups   = flag.String("groups", envOr("TESTIDP_GROUPS", ""), "comma-separated groups claim")
	)
	flag.Parse()

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		log.Fatal(err)
	}
	iss := *issuer
	if iss == "" {
		iss = "http://" + *addr
	}
	p := &idp{
		issuer:   iss,
		key:      key,
		clientID: *clientID,
		username: *username,
		password: *password,
		email:    *email,
		codes:    map[string]issuedCode{},
	}
	if *groups != "" {
		for _, g := range splitComma(*groups) {
			p.groups = append(p.groups, g)
		}
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /.well-known/openid-configuration", p.discovery)
	mux.HandleFunc("GET /keys", p.jwks)
	mux.HandleFunc("GET /authorize", p.loginForm)
	mux.HandleFunc("POST /authorize", p.login)
	mux.HandleFunc("POST /token", p.token)

	log.Printf("testidp listening on %s (issuer %s)", *addr, iss)
	srv := &http.Server{Addr: *addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	log.Fatal(srv.ListenAndServe())
}

func (p *idp) discovery(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, map[string]any{
		"issuer":                                p.issuer,
		"authorization_endpoint":                p.issuer + "/authorize",
		"token_endpoint":                        p.issuer + "/token",
		"jwks_uri":                              p.issuer + "/keys",
		"id_token_signing_alg_values_supported": []string{"RS256"},
		"response_types_supported":              []string{"code"},
		"subject_types_supported":               []string{"public"},
		"code_challenge_methods_supported":      []string{"S256"},
	})
}

func (p *idp) jwks(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, map[string]any{
		"keys": []map[string]any{{
			"kty": "RSA", "alg": "RS256", "use": "sig", "kid": "testidp",
			"n": base64.RawURLEncoding.EncodeToString(p.key.N.Bytes()),
			"e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(p.key.E)).Bytes()),
		}},
	})
}

var formTmpl = template.Must(template.New("form").Parse(`<!doctype html>
<title>Test IdP</title>
<h1>Test identity provider</h1>
<form method="post" action="/authorize">
{{range $k, $v := .Params}}<input type="hidden" name="{{$k}}" value="{{$v}}">
{{end}}<label>Username <input name="idp_username" autocomplete="username"></label>
<label>Password <input name="idp_password" type="password" autocomplete="current-password"></label>
<button type="submit">Sign in</button>
</form>`))

func (p *idp) loginForm(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	if q.Get("client_id") != p.clientID {
		http.Error(w, "unknown client_id", http.StatusBadRequest)
		return
	}
	if q.Get("response_type") != "code" || q.Get("redirect_uri") == "" {
		http.Error(w, "unsupported authorization request", http.StatusBadRequest)
		return
	}
	params := map[string]string{}
	for k := range q {
		params[k] = q.Get(k)
	}
	w.Header().Set("Content-Type", "text/html")
	if err := formTmpl.Execute(w, struct{ Params map[string]string }{params}); err != nil {
		log.Printf("form render: %v", err)
	}
}

func (p *idp) login(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "bad form", http.StatusBadRequest)
		return
	}
	if r.PostForm.Get("idp_username") != p.username || r.PostForm.Get("idp_password") != p.password {
		http.Error(w, "wrong credentials", http.StatusUnauthorized)
		return
	}
	redirectURI := r.PostForm.Get("redirect_uri")
	target, err := url.Parse(redirectURI)
	if err != nil || redirectURI == "" {
		http.Error(w, "bad redirect_uri", http.StatusBadRequest)
		return
	}
	code, err := randomToken()
	if err != nil {
		http.Error(w, "entropy failure", http.StatusInternalServerError)
		return
	}
	p.mu.Lock()
	p.codes[code] = issuedCode{
		redirectURI: redirectURI,
		challenge:   r.PostForm.Get("code_challenge"),
		expires:     time.Now().Add(2 * time.Minute),
	}
	p.mu.Unlock()
	q := target.Query()
	q.Set("code", code)
	q.Set("state", r.PostForm.Get("state"))
	target.RawQuery = q.Encode()
	http.Redirect(w, r, target.String(), http.StatusFound)
}

func (p *idp) token(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "bad form", http.StatusBadRequest)
		return
	}
	code := r.PostForm.Get("code")
	p.mu.Lock()
	issued, ok := p.codes[code]
	delete(p.codes, code)
	p.mu.Unlock()
	if !ok || time.Now().After(issued.expires) {
		writeTokenError(w, "invalid_grant", "unknown, expired, or replayed code")
		return
	}
	if r.PostForm.Get("redirect_uri") != issued.redirectURI {
		writeTokenError(w, "invalid_grant", "redirect_uri mismatch")
		return
	}
	if issued.challenge != "" {
		sum := sha256.Sum256([]byte(r.PostForm.Get("code_verifier")))
		if base64.RawURLEncoding.EncodeToString(sum[:]) != issued.challenge {
			writeTokenError(w, "invalid_grant", "PKCE verification failed")
			return
		}
	}
	now := time.Now()
	claims := map[string]any{
		"iss":                p.issuer,
		"aud":                p.clientID,
		"sub":                "testidp-" + p.username,
		"iat":                now.Unix(),
		"exp":                now.Add(time.Hour).Unix(),
		"email":              p.email,
		"email_verified":     true,
		"preferred_username": p.username,
		"name":               p.username,
	}
	if len(p.groups) > 0 {
		claims["groups"] = p.groups
	}
	idToken, err := p.signJWT(claims)
	if err != nil {
		http.Error(w, "signing failure", http.StatusInternalServerError)
		return
	}
	writeJSON(w, map[string]any{
		"access_token": "testidp-access",
		"token_type":   "Bearer",
		"expires_in":   3600,
		"id_token":     idToken,
	})
}

func (p *idp) signJWT(claims map[string]any) (string, error) {
	header, _ := json.Marshal(map[string]string{"alg": "RS256", "kid": "testidp", "typ": "JWT"})
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", err
	}
	signing := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(payload)
	sum := sha256.Sum256([]byte(signing))
	sig, err := rsa.SignPKCS1v15(rand.Reader, p.key, crypto.SHA256, sum[:])
	if err != nil {
		return "", err
	}
	return signing + "." + base64.RawURLEncoding.EncodeToString(sig), nil
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("encode: %v", err)
	}
}

func writeTokenError(w http.ResponseWriter, code, desc string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusBadRequest)
	fmt.Fprintf(w, `{"error":%q,"error_description":%q}`, code, desc)
}

func randomToken() (string, error) {
	buf := make([]byte, 24)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

func splitComma(s string) []string {
	var out []string
	start := 0
	for i := 0; i <= len(s); i++ {
		if i == len(s) || s[i] == ',' {
			if part := s[start:i]; part != "" {
				out = append(out, part)
			}
			start = i + 1
		}
	}
	return out
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
