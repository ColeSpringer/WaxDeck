package service

import (
	"context"
	"crypto/md5"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"strings"
	"sync"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/server/internal/auth"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// App passwords are the per-client credentials the compatibility APIs
// authenticate with. The Subsonic token scheme is md5(password+salt)
// with a client-random salt per request, which forces the server to
// hold the password itself: secrets are sealed at rest with the server
// key and unsealed through a short-TTL in-memory cache, so a polling
// Subsonic client costs one MD5 per request, not a decryption.

// appPasswordCap bounds how many app passwords one account can hold.
const appPasswordCap = 50

// appSecretTTL is how long an unsealed secret stays cached. Expiry and
// revocation both drop the entry; Go's GC gives no zeroization
// guarantee, so the short TTL is the real bound.
const appSecretTTL = 5 * time.Minute

// AppPassword is one credential without its secret.
type AppPassword struct {
	ID         string
	Label      string
	CreatedAt  time.Time
	LastUsedAt time.Time
}

// AppPasswordSecret is a freshly created credential, secret included
// (the only time it is ever visible).
type AppPasswordSecret struct {
	AppPassword
	Secret string
}

// appSecretCache is the unsealed-secret TTL cache.
type appSecretCache struct {
	mu      sync.Mutex
	entries map[string]appSecretEntry // by app password id
}

type appSecretEntry struct {
	secret  string
	userID  string
	expires time.Time
	touched time.Time
}

// AppPasswords lists the caller's app passwords, newest first.
func (l *Library) AppPasswords(ctx context.Context, uc *UserCtx) ([]AppPassword, error) {
	rows, err := l.db.AppPasswordsByUser(ctx, uc.ID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	out := make([]AppPassword, 0, len(rows))
	for _, ap := range rows {
		out = append(out, AppPassword{
			ID: apiPID(PrefixAppPassword, model.PID(ap.ID)), Label: ap.Label,
			CreatedAt: ap.CreatedAt, LastUsedAt: ap.LastUsedAt,
		})
	}
	return out, nil
}

// CreateAppPassword mints and stores a new app password for the
// caller, returning the secret exactly once.
func (l *Library) CreateAppPassword(ctx context.Context, uc *UserCtx, label string) (AppPasswordSecret, error) {
	label = strings.TrimSpace(label)
	if label == "" {
		return AppPasswordSecret{}, errInvalid("label is required")
	}
	if len(label) > 128 {
		return AppPasswordSecret{}, errInvalid("label must be at most 128 characters")
	}
	if l.sealer == nil {
		return AppPasswordSecret{}, &Error{Kind: KindInternal, Msg: "no sealing key is configured"}
	}
	secret, err := auth.NewAppPasswordSecret()
	if err != nil {
		return AppPasswordSecret{}, &Error{Kind: KindInternal, Err: err}
	}
	sealed, err := l.sealer.Seal([]byte(secret))
	if err != nil {
		return AppPasswordSecret{}, &Error{Kind: KindInternal, Err: err}
	}
	hash := sha256.Sum256([]byte(secret))
	ap := &wdb.AppPassword{
		ID:         ulid.Make().String(),
		UserID:     uc.ID,
		Label:      label,
		SecretEnc:  sealed,
		SecretHash: hash[:],
	}
	ok, err := l.db.InsertAppPassword(ctx, ap, appPasswordCap)
	if err != nil {
		return AppPasswordSecret{}, &Error{Kind: KindInternal, Err: err}
	}
	if !ok {
		return AppPasswordSecret{}, &Error{Kind: KindConflict, Msg: "app password limit reached; revoke one first"}
	}
	stored, err := l.db.AppPasswordsByUser(ctx, uc.ID)
	if err != nil {
		return AppPasswordSecret{}, &Error{Kind: KindInternal, Err: err}
	}
	out := AppPasswordSecret{Secret: secret}
	for _, row := range stored {
		if row.ID == ap.ID {
			out.AppPassword = AppPassword{
				ID: apiPID(PrefixAppPassword, model.PID(row.ID)), Label: row.Label,
				CreatedAt: row.CreatedAt,
			}
			break
		}
	}
	return out, nil
}

// RevokeAppPassword deletes one of the caller's app passwords and drops
// any cached unsealed secret, so the next compatibility request fails
// immediately.
func (l *Library) RevokeAppPassword(ctx context.Context, uc *UserCtx, apiID string) error {
	prefix, pid, ok := parseAPIPID(apiID)
	if !ok || prefix != PrefixAppPassword {
		return errNotFound("no app password with id " + apiID)
	}
	deleted, err := l.db.DeleteAppPassword(ctx, uc.ID, string(pid))
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if !deleted {
		return errNotFound("no app password with id " + apiID)
	}
	l.appSecrets.mu.Lock()
	delete(l.appSecrets.entries, string(pid))
	l.appSecrets.mu.Unlock()
	return nil
}

// VerifyAppPasswordToken authenticates the Subsonic token scheme:
// username plus md5(secret+salt). It returns the account, or nil on any
// failure (unknown user, disabled account, no matching password), never
// distinguishing them.
func (l *Library) VerifyAppPasswordToken(ctx context.Context, username, token, salt string) (*wdb.User, error) {
	u, err := l.db.UserByUsername(ctx, username)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, nil
		}
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if u.Disabled {
		return nil, nil
	}
	want := strings.ToLower(token)
	for _, entry := range l.userAppSecrets(ctx, u.ID) {
		sum := md5.Sum([]byte(entry.secret + salt))
		if subtle.ConstantTimeCompare([]byte(hex.EncodeToString(sum[:])), []byte(want)) == 1 {
			l.touchAppPassword(ctx, entry)
			return u, nil
		}
	}
	return nil, nil
}

// VerifyAppPasswordKey authenticates the OpenSubsonic apiKey scheme:
// the app password secret presented directly.
func (l *Library) VerifyAppPasswordKey(ctx context.Context, apiKey string) (*wdb.User, error) {
	hash := sha256.Sum256([]byte(apiKey))
	ap, err := l.db.AppPasswordBySecretHash(ctx, hash[:])
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if ap == nil {
		return nil, nil
	}
	u, err := l.db.UserByID(ctx, ap.UserID)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, nil
		}
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if u.Disabled {
		return nil, nil
	}
	l.touchAppPassword(ctx, appSecretIdentity{id: ap.ID})
	return u, nil
}

// appSecretIdentity is the cache-independent identity of a verified
// credential, for last-used bookkeeping.
type appSecretIdentity struct {
	id     string
	secret string
}

// userAppSecrets returns the user's unsealed secrets, from cache or by
// unsealing, refreshing the cache as it goes. Unsealing happens outside
// the cache lock so a miss never serializes unrelated authentications
// behind AES; a concurrent miss unseals twice to the same value, which
// is cheaper than holding the lock.
func (l *Library) userAppSecrets(ctx context.Context, userID string) []appSecretIdentity {
	rows, err := l.db.AppPasswordsByUser(ctx, userID)
	if err != nil {
		l.log.Warn("listing app passwords", "err", err)
		return nil
	}
	if l.sealer == nil {
		return nil
	}
	now := time.Now()
	cached := make(map[string]string, len(rows))
	l.appSecrets.mu.Lock()
	if l.appSecrets.entries == nil {
		l.appSecrets.entries = make(map[string]appSecretEntry)
	}
	// Opportunistic expiry sweep; the map stays tiny (live credentials
	// for recently active users).
	for id, e := range l.appSecrets.entries {
		if now.After(e.expires) {
			delete(l.appSecrets.entries, id)
		}
	}
	for _, ap := range rows {
		if e, hit := l.appSecrets.entries[ap.ID]; hit {
			cached[ap.ID] = e.secret
		}
	}
	l.appSecrets.mu.Unlock()

	opened := make(map[string]string)
	for _, ap := range rows {
		if _, hit := cached[ap.ID]; hit {
			continue
		}
		pt, err := l.sealer.Open(ap.SecretEnc)
		if err != nil {
			l.log.Warn("unsealing app password", "id", ap.ID, "err", err)
			continue
		}
		opened[ap.ID] = string(pt)
	}
	if len(opened) > 0 {
		l.appSecrets.mu.Lock()
		for id, secret := range opened {
			// Merge over any concurrent entry so its touched time
			// survives the refresh.
			e := l.appSecrets.entries[id]
			e.secret, e.userID, e.expires = secret, userID, now.Add(appSecretTTL)
			l.appSecrets.entries[id] = e
		}
		l.appSecrets.mu.Unlock()
	}

	out := make([]appSecretIdentity, 0, len(rows))
	for _, ap := range rows {
		secret, ok := cached[ap.ID]
		if !ok {
			secret, ok = opened[ap.ID]
		}
		if ok {
			out = append(out, appSecretIdentity{id: ap.ID, secret: secret})
		}
	}
	return out
}

// touchAppPassword records a successful use, coarsely (once a minute
// per credential) so polling clients do not churn the write connection.
func (l *Library) touchAppPassword(ctx context.Context, ident appSecretIdentity) {
	l.appSecrets.mu.Lock()
	if l.appSecrets.entries == nil {
		l.appSecrets.entries = make(map[string]appSecretEntry)
	}
	e := l.appSecrets.entries[ident.id]
	recent := !e.touched.IsZero() && time.Since(e.touched) < time.Minute
	if !recent {
		e.touched = time.Now()
		l.appSecrets.entries[ident.id] = e
	}
	l.appSecrets.mu.Unlock()
	if recent {
		return
	}
	if err := l.db.TouchAppPassword(ctx, ident.id); err != nil {
		l.log.Warn("touching app password", "err", err)
	}
}
