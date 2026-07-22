package service

import (
	"context"
	"encoding/base64"
	"time"

	"github.com/colespringer/waxdeck/server/internal/scrobble"
)

// Last.fm's server API credentials identify this install as a Last.fm
// application (per-user accounts link separately, through the browser
// authorization each user runs). The pair can come from the
// environment or be set at runtime through the admin surface; a
// runtime-set pair wins, and the secret is sealed at rest.
const (
	settingLastfmAPIKey = "scrobble:lastfm-api-key"
	settingLastfmSecret = "scrobble:lastfm-secret"

	lastfmSourceNone     = "none"
	lastfmSourceEnv      = "environment"
	lastfmSourceSettings = "settings"
)

// LastfmServerConfig is the admin view of the server credential state;
// the shared secret itself is never read back.
type LastfmServerConfig struct {
	Configured bool
	Source     string
	APIKey     string
	SecretSet  bool
}

// loadLastfmClient builds (or clears) the Last.fm client from the
// stored credentials, falling back to the environment pair. Called at
// Open and after every credential change.
func (l *Library) loadLastfmClient(ctx context.Context) {
	key, secret, _ := l.lastfmCredentials(ctx)
	if key == "" || secret == "" {
		l.lastfmPtr.Store(&lastfmSlot{})
		return
	}
	l.lastfmPtr.Store(&lastfmSlot{client: scrobble.NewLastfm(key, secret)})
}

// lastfmSlot wraps the client so an atomic pointer can also represent
// "no credentials" without a nil-interface dance.
type lastfmSlot struct{ client *scrobble.Lastfm }

// lastfmClient returns the live client, nil when unconfigured.
func (l *Library) lastfmClient() *scrobble.Lastfm {
	if slot, ok := l.lastfmPtr.Load().(*lastfmSlot); ok && slot != nil {
		return slot.client
	}
	return nil
}

// lastfmCredentials resolves the effective pair and its source.
func (l *Library) lastfmCredentials(ctx context.Context) (key, secret, source string) {
	storedKey, keyErr := l.db.SettingGet(ctx, settingLastfmAPIKey)
	storedSecret, secErr := l.db.SettingGet(ctx, settingLastfmSecret)
	if keyErr == nil && secErr == nil && storedKey != "" {
		sealed, err := base64.StdEncoding.DecodeString(storedSecret)
		if err == nil {
			if plain, err := l.sealer.Open(sealed); err == nil {
				return storedKey, string(plain), lastfmSourceSettings
			}
		}
		l.log.Warn("stored Last.fm secret cannot be unsealed; falling back to environment credentials")
	}
	if l.envLastfmKey != "" && l.envLastfmSecret != "" {
		return l.envLastfmKey, l.envLastfmSecret, lastfmSourceEnv
	}
	return "", "", lastfmSourceNone
}

// LastfmConfigGet reports the credential state for the admin surface.
func (l *Library) LastfmConfigGet(ctx context.Context) LastfmServerConfig {
	key, secret, source := l.lastfmCredentials(ctx)
	return LastfmServerConfig{
		Configured: key != "" && secret != "",
		Source:     source,
		APIKey:     key,
		SecretSet:  secret != "",
	}
}

// LastfmConfigPut sets or clears the runtime credential pair. Both
// values set stores them (secret sealed); both empty clears the stored
// pair, falling back to the environment one when present. A half-set
// pair is invalid. Changing the API key invalidates users' existing
// Last.fm connections (session keys bind to the application that
// minted them); their delivery rows surface it and reconnecting fixes
// it, so the change is allowed, not refused.
func (l *Library) LastfmConfigPut(ctx context.Context, actor *UserCtx, apiKey, secret string) (LastfmServerConfig, error) {
	switch {
	case apiKey == "" && secret == "":
		if err := l.db.SettingDelete(ctx, settingLastfmAPIKey); err != nil {
			return LastfmServerConfig{}, &Error{Kind: KindInternal, Err: err}
		}
		if err := l.db.SettingDelete(ctx, settingLastfmSecret); err != nil {
			return LastfmServerConfig{}, &Error{Kind: KindInternal, Err: err}
		}
	case apiKey == "" || secret == "":
		return LastfmServerConfig{}, errInvalid("set both the API key and the shared secret, or clear both")
	default:
		if len(apiKey) > 128 || len(secret) > 128 {
			return LastfmServerConfig{}, errInvalid("credentials must be at most 128 characters")
		}
		if l.sealer == nil {
			return LastfmServerConfig{}, &Error{Kind: KindInternal, Msg: "no sealer is configured"}
		}
		sealed, err := l.sealer.Seal([]byte(secret))
		if err != nil {
			return LastfmServerConfig{}, &Error{Kind: KindInternal, Err: err}
		}
		now := time.Now().UnixNano()
		if err := l.db.SettingSet(ctx, settingLastfmAPIKey, apiKey, now); err != nil {
			return LastfmServerConfig{}, &Error{Kind: KindInternal, Err: err}
		}
		if err := l.db.SettingSet(ctx, settingLastfmSecret,
			base64.StdEncoding.EncodeToString(sealed), now); err != nil {
			return LastfmServerConfig{}, &Error{Kind: KindInternal, Err: err}
		}
	}
	l.loadLastfmClient(ctx)
	out := l.LastfmConfigGet(ctx)
	l.Audit(ctx, actor, "scrobbling.lastfm-config", AuditTarget{Kind: "settings"},
		map[string]any{"configured": out.Configured, "source": out.Source})
	return out, nil
}
