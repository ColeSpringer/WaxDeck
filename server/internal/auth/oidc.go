package auth

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"time"

	gooidc "github.com/coreos/go-oidc/v3/oidc"
	"golang.org/x/oauth2"

	"github.com/colespringer/waxdeck/server/internal/db"
)

// OIDCConfig is one provider's configuration, from the deployment.
type OIDCConfig struct {
	ID           string // stable provider id ("dex", "authentik", ...)
	DisplayName  string
	Issuer       string
	ClientID     string
	ClientSecret string
	Scopes       []string // beyond openid; default profile+email
	// GroupsClaim names the ID-token claim holding group membership;
	// empty disables group-based role mapping.
	GroupsClaim string
	// AdminGroup grants the admin role to members when GroupsClaim is
	// set; every login re-applies the mapping, so the IdP is
	// authoritative over the admin role for OIDC accounts.
	AdminGroup string
}

// oauthStateTTL bounds an in-flight authorization; oidcCodeTTL bounds
// the one-time completion code an app/loopback/code flow hands back.
const (
	oauthStateTTL = 10 * time.Minute
	oidcCodeTTL   = 5 * time.Minute
)

// OIDC is the server-mediated OIDC broker for one provider: it builds
// authorization URLs, handles the callback exchange, verifies ID
// tokens, and resolves them to accounts.
type OIDC struct {
	cfg      OIDCConfig
	store    *db.DB
	provider *gooidc.Provider
	verifier *gooidc.IDTokenVerifier
}

// NewOIDC discovers the provider and builds the broker. Discovery
// happens at startup so a bad issuer fails fast, not at first login.
func NewOIDC(ctx context.Context, cfg OIDCConfig, store *db.DB) (*OIDC, error) {
	if cfg.ID == "" || cfg.Issuer == "" || cfg.ClientID == "" {
		return nil, errors.New("auth: oidc needs id, issuer, and client id")
	}
	if cfg.DisplayName == "" {
		cfg.DisplayName = cfg.ID
	}
	provider, err := gooidc.NewProvider(ctx, cfg.Issuer)
	if err != nil {
		return nil, fmt.Errorf("auth: discovering oidc issuer %s: %w", cfg.Issuer, err)
	}
	return &OIDC{
		cfg:      cfg,
		store:    store,
		provider: provider,
		verifier: provider.Verifier(&gooidc.Config{ClientID: cfg.ClientID}),
	}, nil
}

// Config returns the provider configuration.
func (o *OIDC) Config() OIDCConfig { return o.cfg }

// StartFlow stores the flow state and returns the provider
// authorization URL to redirect the browser to. redirectURI is this
// server's callback URL as the client will reach it; challenge is the
// optional proof-of-possession hash bound to the eventual one-time
// code.
func (o *OIDC) StartFlow(ctx context.Context, mode, redirectURI, redirectTo, challenge string, loopbackPort int) (string, error) {
	state, err := randomToken()
	if err != nil {
		return "", err
	}
	verifier := oauth2.GenerateVerifier()
	st := db.OAuthState{
		State:        state,
		Provider:     o.cfg.ID,
		Mode:         mode,
		CodeVerifier: verifier,
		RedirectURI:  redirectURI,
		RedirectTo:   redirectTo,
		Challenge:    challenge,
		LoopbackPort: loopbackPort,
		ExpiresAt:    time.Now().Add(oauthStateTTL),
	}
	if err := o.store.PutOAuthState(ctx, st); err != nil {
		return "", fmt.Errorf("auth: storing oauth state: %w", err)
	}
	return o.oauth2Config(redirectURI).AuthCodeURL(state, oauth2.S256ChallengeOption(verifier)), nil
}

// Identity is a verified provider identity with its mapped roles.
type Identity struct {
	Provider string
	Subject  string
	Email    string
	Username string   // preferred username hint, may be empty
	Name     string   // display name hint, may be empty
	Roles    []string // nil when the provider carries no group mapping
}

// Completed is a finished callback: the verified identity plus the
// flow's completion parameters.
type Completed struct {
	Identity     Identity
	Mode         string
	RedirectTo   string
	Challenge    string
	LoopbackPort int
}

// HandleCallback consumes the state, exchanges the code, and verifies
// the ID token. It does not touch accounts; the caller resolves the
// identity to a user.
func (o *OIDC) HandleCallback(ctx context.Context, state, code string) (*Completed, error) {
	st, err := o.store.TakeOAuthState(ctx, state)
	if err != nil {
		if errors.Is(err, db.ErrNotFound) {
			return nil, errors.New("unknown or expired state")
		}
		return nil, err
	}
	tok, err := o.oauth2Config(st.RedirectURI).Exchange(ctx, code, oauth2.VerifierOption(st.CodeVerifier))
	if err != nil {
		return nil, fmt.Errorf("code exchange failed: %w", err)
	}
	rawID, ok := tok.Extra("id_token").(string)
	if !ok || rawID == "" {
		return nil, errors.New("provider returned no id token")
	}
	idTok, err := o.verifier.Verify(ctx, rawID)
	if err != nil {
		return nil, fmt.Errorf("id token verification failed: %w", err)
	}
	// email_verified is deliberately not decoded: the email is display
	// data only (identity records, username hints), never a linking key
	// (resolution is by issuer and subject alone), and many providers
	// omit the claim entirely, which would read as unverified and
	// degrade every hint for no security gain.
	var claims struct {
		Email             string   `json:"email"`
		PreferredUsername string   `json:"preferred_username"`
		Name              string   `json:"name"`
		Groups            []string `json:"groups"`
	}
	// Group claims under a custom name need a second decode into a map.
	if err := idTok.Claims(&claims); err != nil {
		return nil, fmt.Errorf("reading claims: %w", err)
	}
	ident := Identity{
		Provider: o.cfg.ID,
		Subject:  idTok.Subject,
		Email:    claims.Email,
		Username: claims.PreferredUsername,
		Name:     claims.Name,
	}
	if o.cfg.GroupsClaim != "" {
		groups := claims.Groups
		if o.cfg.GroupsClaim != "groups" {
			var m map[string]any
			if err := idTok.Claims(&m); err == nil {
				groups = stringSlice(m[o.cfg.GroupsClaim])
			}
		}
		roles := []string{"user"}
		for _, g := range groups {
			if o.cfg.AdminGroup != "" && g == o.cfg.AdminGroup {
				roles = []string{"admin", "user"}
				break
			}
		}
		ident.Roles = roles
	}
	return &Completed{
		Identity:     ident,
		Mode:         st.Mode,
		RedirectTo:   st.RedirectTo,
		Challenge:    st.Challenge,
		LoopbackPort: st.LoopbackPort,
	}, nil
}

// MintCode stores a one-time completion code for the account, bound to
// the flow's challenge when one was given.
func (o *OIDC) MintCode(ctx context.Context, userID, challenge string) (string, error) {
	code, hash, err := NewOpaqueToken()
	if err != nil {
		return "", err
	}
	if err := o.store.PutOidcCode(ctx, hash, userID, challenge, time.Now().Add(oidcCodeTTL)); err != nil {
		return "", fmt.Errorf("auth: storing one-time code: %w", err)
	}
	return code, nil
}

// RedeemCode consumes a one-time code, enforcing the
// proof-of-possession verifier when the flow was bound to one.
func (o *OIDC) RedeemCode(ctx context.Context, code, verifier string) (userID string, err error) {
	userID, challenge, err := o.store.TakeOidcCode(ctx, TokenHash(code))
	if err != nil {
		if errors.Is(err, db.ErrNotFound) {
			return "", errors.New("unknown, expired, or already redeemed code")
		}
		return "", err
	}
	if challenge != "" && (verifier == "" || s256(verifier) != challenge) {
		return "", errors.New("missing or wrong verifier")
	}
	return userID, nil
}

func (o *OIDC) oauth2Config(redirectURI string) *oauth2.Config {
	scopes := append([]string{gooidc.ScopeOpenID, "profile", "email"}, o.cfg.Scopes...)
	return &oauth2.Config{
		ClientID:     o.cfg.ClientID,
		ClientSecret: o.cfg.ClientSecret,
		Endpoint:     o.provider.Endpoint(),
		RedirectURL:  redirectURI,
		Scopes:       scopes,
	}
}

func randomToken() (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("auth: reading entropy: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

// s256 is the challenge derivation: base64url(SHA-256(verifier)),
// exactly PKCE's S256.
func s256(verifier string) string {
	sum := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

// stringSlice reads a claim that providers ship in two shapes: a JSON
// array (which decodes as []any) or, from some IdPs when a user has
// exactly one group, a bare string.
func stringSlice(v any) []string {
	switch t := v.(type) {
	case []any:
		out := make([]string, 0, len(t))
		for _, it := range t {
			if s, ok := it.(string); ok {
				out = append(out, s)
			}
		}
		return out
	case string:
		if t == "" {
			return nil
		}
		return []string{t}
	}
	return nil
}
