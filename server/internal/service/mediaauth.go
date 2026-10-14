package service

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// AuthorizeMedia re-runs, on a fetch of a media token, the check its
// mint made: the account can still sign in, the credential the mint ran
// under is still live, and the account may still have what the token
// names. One rule rather than a revocation list, so it cannot drift from
// the mint's: a disable, a deleted account, a revoked session or app
// password, a narrowed grant and a new tag rule all stop new opens (and
// Range requests) of URLs minted before them. A refusal of the account
// or credential wraps auth.ErrMediaRevoked; any other is about the item.
func (l *Library) AuthorizeMedia(ctx context.Context, c auth.MediaClaims) error {
	_, err := l.AuthorizeMediaFor(ctx, c)
	return err
}

// AuthorizeMediaFor is AuthorizeMedia answering the account context the
// check built, for a route that reads on as that account and would
// otherwise read it a second time.
func (l *Library) AuthorizeMediaFor(ctx context.Context, c auth.MediaClaims) (*UserCtx, error) {
	uc, err := l.userCtxByID(ctx, c.User)
	if err != nil {
		if KindOf(err) == KindNotFound {
			return nil, fmt.Errorf("%w: the account cannot sign in", auth.ErrMediaRevoked)
		}
		return nil, err
	}
	if err := l.credentialAlive(ctx, c.User, c.Cred); err != nil {
		return nil, err
	}
	switch c.Purpose {
	case auth.PurposeStream, auth.PurposeArt, auth.PurposeEnclosure:
		return uc, l.VisibleItem(ctx, uc, c.PID)
	case auth.PurposeDownload:
		if !uc.Admin && !uc.Download {
			return nil, &Error{Kind: KindForbidden, Msg: "this account cannot download originals"}
		}
		return uc, l.VisibleItem(ctx, uc, c.PID)
	case auth.PurposeRadio:
		_, err := l.RadioStationByPID(ctx, c.PID)
		return uc, err
	case auth.PurposeProbe, auth.PurposeHLS:
		// A probe opens nothing in the library, and a timeline's items
		// were checked at its mint and are bound by its reach credential.
		return uc, nil
	}
	return nil, &Error{Kind: KindForbidden, Msg: "a media token for an unknown purpose"}
}

// credentialAlive checks the credentials a media token was minted under
// (auth.MediaClaims.Cred): every one it names has to hold.
func (l *Library) credentialAlive(ctx context.Context, userID, cred string) error {
	if cred == "" {
		return nil
	}
	for part := range strings.SplitSeq(cred, ",") {
		if err := l.credentialHolds(ctx, userID, part); err != nil {
			return err
		}
	}
	return nil
}

func (l *Library) credentialHolds(ctx context.Context, userID, cred string) error {
	revoked := func(why string) error { return fmt.Errorf("%w: %s", auth.ErrMediaRevoked, why) }
	kind, id, _ := strings.Cut(cred, ":")
	switch kind {
	case "se":
		s, err := l.db.SessionByID(ctx, id)
		if err != nil && !errors.Is(err, wdb.ErrNotFound) {
			return &Error{Kind: KindInternal, Err: err}
		}
		if s == nil || s.UserID != userID || !time.Now().Before(s.ExpiresAt) {
			return revoked("the session that minted it has ended")
		}
		return nil
	case "ap":
		held, err := l.db.AppPasswordHeld(ctx, userID, id)
		if err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
		if !held {
			return revoked("the app password that minted it is revoked")
		}
		return nil
	case "re":
		epoch, err := l.reachEpoch(ctx, userID)
		if err != nil {
			return err
		}
		if strconv.FormatInt(epoch, 10) != id {
			return revoked("what the account may see has changed since it was minted")
		}
		return nil
	}
	return revoked("an unknown credential")
}

// syncKeyReachEpoch counts changes to what one account may see (library
// grants, content rules), so a timeline minted under one reach can tell
// it no longer holds. Not the grant epoch: that one also moves on every
// subscription change, which must not cut a gapless queue.
const syncKeyReachEpoch = "reach_epoch:" // + user id

// TimelineReach answers the credential a timeline's token runs under,
// the account's reach when it was minted, and the rules to check the
// queue against, read in that order: an administrator narrowing the
// account between the two reads moves the epoch past the credential, so
// the timeline ends at its first fetch instead of playing what the new
// rules hide.
func (l *Library) TimelineReach(ctx context.Context, userID string) (string, *UserCtx, error) {
	epoch, err := l.reachEpoch(ctx, userID)
	if err != nil {
		return "", nil, err
	}
	uc, err := l.userCtxByID(ctx, userID)
	if err != nil {
		return "", nil, err
	}
	return "re:" + strconv.FormatInt(epoch, 10), uc, nil
}

func (l *Library) reachEpoch(ctx context.Context, userID string) (int64, error) {
	return l.epoch(ctx, syncKeyReachEpoch+userID)
}

// bumpReachEpoch ends every timeline minted under the account's current
// reach.
func (l *Library) bumpReachEpoch(ctx context.Context, userID string) {
	l.bumpEpoch(ctx, syncKeyReachEpoch+userID)
}

// epoch reads a per-account counter kept in sync_state: 0 before its
// first bump, and an error, never a number, when the stored value does
// not read back as one, so damage cannot make an old token or cursor
// match again.
func (l *Library) epoch(ctx context.Context, key string) (int64, error) {
	v, err := l.db.SyncStateGet(ctx, key)
	if err != nil {
		return 0, &Error{Kind: KindInternal, Err: err}
	}
	if v == "" {
		return 0, nil
	}
	n, err := strconv.ParseInt(v, 10, 64)
	if err != nil {
		return 0, &Error{Kind: KindInternal, Err: fmt.Errorf("sync state %s holds %q, not a counter", key, v)}
	}
	return n, nil
}

// bumpEpoch moves a counter on in one statement, so two bumps racing
// each other both count.
func (l *Library) bumpEpoch(ctx context.Context, key string) {
	if _, err := l.db.SyncStateIncrement(ctx, key); err != nil {
		l.log.Warn("bumping an epoch", "key", key, "err", err)
	}
}
