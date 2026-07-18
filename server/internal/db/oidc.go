package db

import (
	"context"
	"database/sql"
	"errors"
	"time"
)

// OAuthState is one in-flight OIDC authorization: the PKCE verifier and
// the completion mode, keyed by the opaque state parameter. Single use:
// the callback consumes it.
type OAuthState struct {
	State        string
	Provider     string
	Mode         string // "web", "app", "loopback", or "code"
	CodeVerifier string
	RedirectURI  string // the exact redirect_uri sent to the provider
	RedirectTo   string // web mode: SPA path to land on
	Challenge    string // proof-of-possession hash for the one-time code
	LoopbackPort int    // loopback mode: the client's listener port
	ExpiresAt    time.Time
}

// PutOAuthState stores an in-flight authorization.
func (d *DB) PutOAuthState(ctx context.Context, s OAuthState) error {
	_, err := d.w.ExecContext(ctx,
		`INSERT INTO oauth_state (state, provider, mode, code_verifier, redirect_uri, redirect_to, challenge, loopback_port, created_at_ns, expires_at_ns)
		 VALUES (?,?,?,?,?,?,?,?,?,?)`,
		s.State, s.Provider, s.Mode, s.CodeVerifier, s.RedirectURI, s.RedirectTo,
		s.Challenge, s.LoopbackPort, time.Now().UnixNano(), s.ExpiresAt.UnixNano())
	return err
}

// TakeOAuthState consumes an in-flight authorization: it is returned at
// most once, and never after expiry. A replayed or unknown state
// returns ErrNotFound.
func (d *DB) TakeOAuthState(ctx context.Context, state string) (*OAuthState, error) {
	var s OAuthState
	var expires int64
	err := d.w.QueryRowContext(ctx,
		`DELETE FROM oauth_state WHERE state = ? AND expires_at_ns > ?
		 RETURNING state, provider, mode, code_verifier, redirect_uri, redirect_to, challenge, loopback_port, expires_at_ns`,
		state, time.Now().UnixNano()).
		Scan(&s.State, &s.Provider, &s.Mode, &s.CodeVerifier, &s.RedirectURI, &s.RedirectTo, &s.Challenge, &s.LoopbackPort, &expires)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	s.ExpiresAt = time.Unix(0, expires).UTC()
	return &s, nil
}

// PutOidcCode stores a hashed one-time completion code for the account,
// with its optional proof-of-possession challenge.
func (d *DB) PutOidcCode(ctx context.Context, codeHash []byte, userID, challenge string, expiresAt time.Time) error {
	_, err := d.w.ExecContext(ctx,
		`INSERT INTO oidc_codes (code_hash, user_id, challenge, created_at_ns, expires_at_ns) VALUES (?,?,?,?,?)`,
		codeHash, userID, challenge, time.Now().UnixNano(), expiresAt.UnixNano())
	return err
}

// TakeOidcCode consumes a one-time completion code, returning the
// account it grants and the challenge it is bound to ("" when
// unbound). Single use, never after expiry.
func (d *DB) TakeOidcCode(ctx context.Context, codeHash []byte) (userID, challenge string, err error) {
	err = d.w.QueryRowContext(ctx,
		`DELETE FROM oidc_codes WHERE code_hash = ? AND expires_at_ns > ? RETURNING user_id, challenge`,
		codeHash, time.Now().UnixNano()).Scan(&userID, &challenge)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", "", ErrNotFound
		}
		return "", "", err
	}
	return userID, challenge, nil
}
