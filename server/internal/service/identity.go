package service

import (
	"context"
	"sync"
	"sync/atomic"

	"github.com/colespringer/waxbin/model"
)

// Identity is accounts: users, signup, app passwords, preferences,
// per-entity stars and ratings, and media authorization.
type Identity struct {
	*core
	// catalogUsers maps an account whose stored catalog user a reset or
	// restore dropped to the one the catalog holds for it; read through
	// catalogPID.
	catalogUsers   map[string]model.PID
	catalogUsersMu sync.RWMutex
	// usersUnmapped is an account the last mapping could not place,
	// which the settle after a reopen retries.
	usersUnmapped atomic.Bool
	// appSecrets backs the app-password credential store.
	appSecrets appSecretCache
	// accountDisabledHook runs in a test the moment DeleteAccount has
	// disabled the account; nothing in the server sets it.
	accountDisabledHook func(context.Context)
	// deletingAccounts holds the ids of the accounts a DeleteAccount is
	// running for, so a second request for one is refused rather than run
	// beside the first.
	deletingAccounts sync.Map
}

func newIdentity(c *core, _ Config) *Identity { return &Identity{core: c} }

// reachChanged follows a change to what the account may see: its catalog
// cursors and its timelines end, and its server stream is told of every
// show it follows, so each device re-reads the subscription as the new
// rules have it (absent while the podcast library is out of reach, back
// once it is not) without a reset, which would drop the account marker
// the same change sends. It runs whether or not the request that made the
// change is still there: the grants are written.
func (l *Identity) reachChanged(ctx context.Context, userID string) {
	ctx = context.WithoutCancel(ctx)
	l.Grants.bumpGrantEpoch(ctx, userID)
	l.bumpReachEpoch(ctx, userID)
	shows, err := l.db.SubscribedShowPIDsByUser(ctx, userID)
	if err != nil {
		l.log.Warn("listing an account's shows for its stream", "user", userID, "err", err)
		return
	}
	for _, show := range shows {
		l.emitUserEvent(ctx, userID, eventSubscription, show)
	}
}
