package service

import (
	"context"
	"strings"
	"sync"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// starterMostPlayed names the one starter list WaxDeck seeds: the
// account's own music, most played first. The kind is what the
// starter_playlists row is keyed by, so a second starter is a second
// constant and nothing else moves.
const starterMostPlayed = "most-played"

// starterMostPlayedName is the seeded playlist's name. Server-side
// strings are not localized, and this one is a starting point rather
// than a label: the account owns the list from the moment it exists and
// renames it like any other.
const starterMostPlayedName = "Most played"

// starterSeedRetries is how many times the reconcile re-asks for a page
// of accounts before giving up on the sweep. The pass runs beside the
// startup scan and the sort-key refresh against one SQLite file, so a
// busy database is the failure it actually meets, and abandoning the
// remaining pages over one would leave those accounts unseeded until
// somebody restarts the server.
const starterSeedRetries = 3

// starterMostPlayedRule is what the seeded list evaluates: music the
// account has actually finished, most played first, ties broken by
// recency so a shelf of ones still reads as a history. Capped at fifty,
// which is a playlist somebody scrolls rather than a second library.
func starterMostPlayedRule() SmartRule {
	return SmartRule{
		Root: RuleNode{Type: "all", Nodes: []RuleNode{
			{Type: "condition", Field: "mediaType", Op: "is", Value: "music"},
			{Type: "condition", Field: "playCount", Op: "gt", Value: "0"},
		}},
		Sorts: []RuleSort{
			{Field: "playCount", Desc: true},
			{Field: "lastPlayedAt", Desc: true},
		},
		Limit:     50,
		LimitMode: "count",
	}
}

// starterSeedMu serializes seeding across the whole process.
//
// The check and the create have to be one step: the boot reconcile
// sweeps accounts while requests are served, so without this an account
// created in the first seconds of a boot can be read as unseeded by
// both paths at once and end up holding two starters. Seeding happens
// on account creation and once per account at boot, so one mutex for
// all of it costs nothing and is easier to be sure of than a stripe.
var starterSeedMu sync.Mutex

// seedStartersFor gives one account the starters it should hold, if it
// is an account that should hold any.
//
// The whole seeding predicate lives here rather than at the three call
// sites: an account is seeded when it is created, when a pending signup
// is approved, and at boot, and those must agree about what a seedable
// account is or a disabled one gets a starter down whichever path
// forgot. Never fatal to its caller - an account with no starter is a
// working account, and the next boot offers it again.
func (l *Library) seedStartersFor(ctx context.Context, u *wdb.User) {
	if !seedableAccount(u) {
		return
	}
	uc, err := l.UserCtx(ctx, u)
	if err == nil {
		err = l.seedStarterPlaylists(ctx, uc)
	}
	if err != nil {
		l.log.Warn("seeding starter playlists", "user", u.ID, "err", err)
	}
}

// seedStarterPlaylists gives one account the starter lists it has not
// been offered yet.
//
// Never called from a read: creating a playlist renders a cover, runs a
// dry-run evaluation and emits a server event, none of which belongs on
// the path of somebody opening their playlists. The two moments are
// account creation and the boot reconcile.
func (l *Library) seedStarterPlaylists(ctx context.Context, uc *UserCtx) error {
	starterSeedMu.Lock()
	defer starterSeedMu.Unlock()
	row, ok, err := l.db.StarterPlaylist(ctx, uc.ID, starterMostPlayed)
	if err != nil {
		return err
	}
	// Dismissal is final, and checked before existence: an account that
	// threw the starter away is not offered it again, whatever became
	// of the playlist afterwards.
	if ok && (row.Dismissed || l.playlistExists(ctx, uc, model.PID(row.PlaylistPID))) {
		return nil
	}
	q, err := ruleToQuery(starterMostPlayedRule())
	if err != nil {
		return err
	}
	pl, err := l.createSmartFromQuery(ctx, uc, starterMostPlayedName, model.VisibilityPrivate, q)
	if err != nil {
		return err
	}
	// The catalog pid, bare, as the playlist cover and source side
	// tables beside this one store it.
	_, catalogPID, _ := parseAPIPID(pl.PID)
	return l.db.PutStarterPlaylist(ctx, uc.ID, starterMostPlayed, string(catalogPID), time.Now().UnixNano())
}

// playlistExists reports whether the account still owns the playlist
// this pid names.
//
// A point read rather than a listing: the reconcile asks this once per
// account per boot, and the catalog's own listing scans every playlist
// the account can see to answer a question about one of them.
//
// Absent answers false, which is what re-offers the starter to an
// account whose catalog was rebuilt under the WaxDeck database. Any
// other failure answers true, because seeding on an unreadable catalog
// would mint a duplicate on every boot.
func (l *Library) playlistExists(ctx context.Context, uc *UserCtx, playlistPID model.PID) bool {
	pl, err := l.lib.Playlists().Get(ctx, playlistPID)
	switch {
	case err == nil:
		return string(pl.OwnerPID) == uc.CatalogPID
	case KindOf(classify(err)) == KindNotFound:
		return false
	default:
		l.log.Warn("reading the starter playlist", "user", uc.ID, "playlist", playlistPID, "err", err)
		return true
	}
}

// dismissStarterPlaylist records that the account threw its starter
// away, so the boot reconcile leaves it deleted. Every delete path runs
// through DeletePlaylist, which is where this is called; a pid that is
// nobody's starter matches no row.
func (l *Library) dismissStarterPlaylist(ctx context.Context, uc *UserCtx, playlistPID model.PID) {
	if err := l.db.DismissStarterPlaylist(ctx, uc.ID, string(playlistPID)); err != nil {
		l.log.Warn("dismissing starter playlist", "user", uc.ID, "playlist", playlistPID, "err", err)
	}
}

// reconcileStarterPlaylists offers every enabled account the starters
// it is missing, at boot.
//
// This is what covers the accounts account creation cannot: ones that
// predate the table, ones whose seeding failed at the time, and ones
// whose playlist has since gone missing from the catalog. Those only
// change at a start, so a boot pass is the whole schedule. A failure is
// logged per account and never stops the others or the server.
func (l *Library) reconcileStarterPlaylists(ctx context.Context) error {
	const page = 100
	cursor := ""
	for {
		users, err := l.listUsersRetrying(ctx, cursor, page)
		if err != nil {
			return err
		}
		if len(users) == 0 {
			return nil
		}
		for _, u := range users {
			if err := ctx.Err(); err != nil {
				return err
			}
			l.seedStartersFor(ctx, u)
		}
		if len(users) < page {
			return nil
		}
		cursor = strings.ToLower(users[len(users)-1].Username)
	}
}

// listUsersRetrying reads one page of accounts, re-asking a few times
// before giving up. The cursor is the previous page's last username, so
// a page that cannot be read is not a page that can be stepped over:
// the sweep either gets it or ends there.
func (l *Library) listUsersRetrying(ctx context.Context, cursor string, limit int) ([]*wdb.User, error) {
	var err error
	for attempt := range starterSeedRetries {
		var users []*wdb.User
		if users, err = l.db.ListUsers(ctx, cursor, limit); err == nil {
			return users, nil
		}
		l.log.Warn("listing accounts for the starter reconcile", "after", cursor, "err", err)
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(time.Duration(attempt+1) * 250 * time.Millisecond):
		}
	}
	return nil, err
}

// seedableAccount reports whether an account should hold starters: a
// disabled or still-pending one gets them when it becomes a real
// account, not before.
func seedableAccount(u *wdb.User) bool { return !u.Disabled && !u.Pending }
