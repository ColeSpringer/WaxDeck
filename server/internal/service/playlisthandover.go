package service

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Handing a deleted account's shared playlist to another account.
//
// A static playlist moves as it stands. A smart one moves as it stands
// when its rule reads only the catalog, because that rule means the same
// thing to every account. When the rule reads the owner's own state (what
// they starred, rated or played) it does not: a shared smart playlist is
// evaluated against its owner, so the new owner's state would replace the
// old one's and every reader would see a different list under the same
// name. That playlist is handed over as a fixed list of the tracks it
// held for its owner instead, and every account's pin of it follows to the
// new one. The public share links the account made are not handed over:
// a link is served under the reach of the account that made it, so it ends
// with that account like the rest of what it shared.

// userStateFields are the engine's names for the fields that read the
// evaluating user's own state. The engine marks them in a field table its
// store keeps to itself and offers no way to ask which a rule reads
// (docs/upstream-requests.md asks for one), so this is a copy of it: the
// rule vocabulary's user-state fields, plus the two the engine has and the
// vocabulary does not offer, which a rule from another tool can still
// name. TestUserStateFieldsMatchTheEngine reads the engine's table from
// the module in use and fails when the two differ.
var userStateFields = map[string]bool{
	"starred": true, "starred_at": true, "rating": true, "play_count": true,
	"played": true, "finished": true, "last_played": true,
	"position_ms": true, "last_progress": true,
}

// anyCond reports whether any condition in a rule's tree satisfies
// pred, at any depth and polarity. Its arms must cover every node type
// ruleNodeToEngine can emit, as ruleNamesState's do: a type missed here
// reads as a rule that never mentions the field.
func anyCond(n query.Node, pred func(query.Cond) bool) bool {
	switch t := n.(type) {
	case query.Cond:
		return pred(t)
	case query.And:
		return slices.ContainsFunc(t.Nodes, func(c query.Node) bool { return anyCond(c, pred) })
	case query.Or:
		return slices.ContainsFunc(t.Nodes, func(c query.Node) bool { return anyCond(c, pred) })
	case query.Not:
		return anyCond(t.Node, pred)
	default:
		return false
	}
}

// ruleReadsUserState reports whether a rule's membership depends on whose
// state it is evaluated against: a condition on one of the per-user
// fields, or a sort on one, which decides what a limit keeps.
func ruleReadsUserState(q query.Query) bool {
	for _, s := range q.Sorts {
		if userStateFields[model.CanonicalQueryField(s.Field)] {
			return true
		}
	}
	return anyCond(q.Where, func(c query.Cond) bool {
		return userStateFields[model.CanonicalQueryField(c.Field)]
	})
}

// ruleNamesPlaylistIn reports whether a rule has a condition on one of
// the given playlists.
func ruleNamesPlaylistIn(q query.Query, pids map[model.PID]bool) bool {
	if len(pids) == 0 {
		return false
	}
	named := func(v any) bool {
		return pids[model.PID(strings.ToUpper(fmt.Sprint(v)))]
	}
	return anyCond(q.Where, func(c query.Cond) bool {
		if model.CanonicalQueryField(c.Field) != "playlist_pid" {
			return false
		}
		return named(c.Value) || slices.ContainsFunc(c.Values, named)
	})
}

// handoverStep gives a test the chance to fail one step of a handover.
func (l *Library) handoverStep(stage string, pl *model.Playlist) error {
	if l.handoverHook == nil {
		return nil
	}
	return l.handoverHook(stage, pl)
}

// handOverPlaylist gives one shared playlist of a deleted account to
// taker. leaving holds the account's playlists that are deleted instead: a
// rule that names one of them would match nothing once it is gone. The
// answer is the pid of the fixed list that stands in for the playlist, or
// empty when the playlist itself changed hands.
func (l *Library) handOverPlaylist(ctx context.Context, victim, taker *wdb.User, pl *model.Playlist, leaving map[model.PID]bool) (model.PID, error) {
	if err := l.handoverStep("start", pl); err != nil {
		return "", err
	}
	if pl.Kind == model.PlaylistSmart && pl.Rule != nil &&
		(ruleReadsUserState(*pl.Rule) || ruleNamesPlaylistIn(*pl.Rule, leaving)) {
		return l.handOverAsFixedList(ctx, victim, taker, pl)
	}
	if err := l.lib.Playlists().SetOwner(ctx, pl.PID, model.PID(l.catalogPID(taker))); err != nil {
		return "", classify(err)
	}
	return "", nil
}

// handoverMarker is what a fixed copy carries at the end of its name from
// the moment it exists, which is how a handover that stopped finds it again
// whatever has changed since: the pid of the playlist it copies, which no
// other list's name holds. The copy gets its own name once the record names
// it.
func handoverMarker(source model.PID) string { return " [handover " + string(source) + "]" }

// handOverAsFixedList evaluates a smart playlist for its owner and makes
// taker a static playlist of the same name and visibility holding what it
// returned, then moves the pins of the old playlist to it and deletes the
// old one.
//
// It can stop anywhere and be run again. The copy is on record, in
// waxdeck.db and keyed by the playlist it copies, before the playlist is
// touched, and carries a marker in its name until the record names it, so a
// run that finds the record takes up the copy it names, or the one a run
// that stopped before naming it made, rather than making another, and
// brings it up to what the playlist evaluates to now. A run that fails
// takes its copy back while the catalog lets it, and when the catalog does
// not, leaves the record for the next run.
func (l *Library) handOverAsFixedList(ctx context.Context, victim, taker *wdb.User, pl *model.Playlist) (model.PID, error) {
	members, err := l.playlistMembers(ctx, pl)
	if err != nil {
		return "", err
	}
	pids := make([]model.PID, 0, len(members))
	for _, it := range members {
		pids = append(pids, it.PID)
	}
	fixed, err := l.fixedCopyOf(ctx, victim, taker, pl, pids)
	if err != nil {
		return "", err
	}
	if err := l.nameCopy(ctx, fixed, pl); err != nil {
		return "", l.takeBackCopy(ctx, pl, fixed.PID, err)
	}
	l.carryPlaylistCover(ctx, pl.PID, fixed.PID)
	if err := l.repointPins(ctx, pl.PID, fixed.PID); err != nil {
		return "", l.takeBackCopy(ctx, pl, fixed.PID, err)
	}
	err = l.handoverStep("swap", pl)
	if err == nil {
		err = l.removePlaylist(ctx, pl)
	}
	if err != nil {
		return "", l.takeBackCopy(ctx, pl, fixed.PID, err)
	}
	l.forgetHandover(ctx, pl.PID)
	return fixed.PID, nil
}

// fixedCopyOf answers the fixed list that stands in for a smart playlist,
// held by taker and holding pids: the one an earlier run left, when there
// is one to take up, else a new one under the marker's name. The new one's
// intent is recorded before it is made, and the record names it as soon as
// it exists.
func (l *Library) fixedCopyOf(ctx context.Context, victim, taker *wdb.User, pl *model.Playlist, pids []model.PID) (*model.Playlist, error) {
	takerPID := model.PID(l.catalogPID(taker))
	rec, err := l.db.PlaylistHandoverFor(ctx, string(pl.PID))
	switch {
	case err == nil:
		fixed, err := l.earlierCopy(ctx, rec, pl, takerPID, pids)
		if err != nil {
			return nil, err
		}
		if fixed != nil {
			rec.CopyPID, rec.TakerID = string(fixed.PID), taker.ID
			if err := l.db.PutPlaylistHandover(ctx, rec); err != nil {
				return nil, &Error{Kind: KindInternal, Err: err}
			}
			return fixed, nil
		}
	case !errors.Is(err, wdb.ErrNotFound):
		return nil, &Error{Kind: KindInternal, Err: err}
	}

	rec = wdb.PlaylistHandover{SourcePID: string(pl.PID), UserID: victim.ID, TakerID: taker.ID}
	if err := l.db.PutPlaylistHandover(ctx, rec); err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	// The intent stays on record when this fails: the catalog may have made
	// the list and failed to take it back, and the next run looks for it.
	name := pl.Name + handoverMarker(pl.PID)
	made, err := l.createStaticWith(ctx, name, takerPID, pl.Visibility, pids)
	if err != nil {
		return nil, err
	}
	fixed := &model.Playlist{PID: made, Name: name, Kind: model.PlaylistStatic, Visibility: pl.Visibility, OwnerPID: takerPID}
	// A test's stand-in for a stop between making the copy and naming it.
	if err := l.handoverStep("created", pl); err != nil {
		return nil, err
	}
	rec.CopyPID = string(made)
	err = l.handoverStep("record", pl)
	if err == nil {
		err = l.db.PutPlaylistHandover(ctx, rec)
	}
	if err != nil {
		cause := error(&Error{Kind: KindInternal, Err: err})
		if derr := l.discardCopy(context.WithoutCancel(ctx), made); derr != nil {
			l.log.Warn("a fixed copy that could not be recorded could not be removed",
				"playlist", pl.PID, "copy", made, "cause", err, "err", derr)
			return nil, copyLeft(cause, made)
		}
		return nil, cause
	}
	return fixed, nil
}

// copyLeft is a failure that leaves a fixed copy of a playlist behind,
// which is the operator's to know of whatever the failure was: the copy is
// in the catalog beside the playlist until a deletion of the account takes
// it up or removes it. What the client reads is the copy and what to do;
// the cause is kept for the log, where its own words can be read, and not
// said to the client, whom they can name paths to.
func copyLeft(cause error, fixed model.PID) error {
	return &copyLeftError{
		internal: &Error{
			Kind: KindInternal,
			Msg: fmt.Sprintf("a fixed copy %s of a playlist could not be removed; repeating the deletion deals with it",
				apiPID(PrefixPlaylist, fixed)),
			Err: cause,
		},
		pid: fixed,
	}
}

// copyLeftError is an internal error that knows which copy it left, for
// the record of the failure to name it without carrying the cause's own
// words: they can hold paths.
type copyLeftError struct {
	internal *Error
	pid      model.PID
}

func (e *copyLeftError) Error() string { return e.internal.Error() }

// Unwrap is the internal error itself, so the failure reads as internal
// whatever its cause was.
func (e *copyLeftError) Unwrap() error { return e.internal }

// LeftCopy is the API pid of the copy the failure left in the catalog.
func (e *copyLeftError) LeftCopy() string { return apiPID(PrefixPlaylist, e.pid) }

// earlierCopy finds the fixed copy an earlier run made of a playlist, from
// its record: the copy it named, or, when that run stopped before naming
// one or the copy it named has since gone, the recipient's playlist that
// carries the playlist's marker. What it finds is brought up to this run:
// held by this run's recipient, and holding what the playlist evaluates to
// now (pids), which is not what it held when it was made if the catalog
// has changed since. Nil when there is none to take up.
func (l *Library) earlierCopy(ctx context.Context, rec wdb.PlaylistHandover, pl *model.Playlist, takerPID model.PID, pids []model.PID) (*model.Playlist, error) {
	var fixed *model.Playlist
	if rec.CopyPID != "" {
		got, err := l.lib.Playlists().Get(ctx, model.PID(rec.CopyPID))
		switch {
		case err == nil && got.Kind == model.PlaylistStatic:
			fixed = got
		case err == nil || KindOf(classify(err)) == KindNotFound:
			// Not there to take up: it was deleted, or is not what it was.
		default:
			return nil, classify(err)
		}
	}
	if fixed == nil {
		viewer, holders := l.handoverHolders(ctx, rec, takerPID)
		marked, err := l.markedCopy(ctx, pl.PID, viewer, holders)
		if err != nil || marked == nil {
			return nil, err
		}
		fixed = marked
	}
	if fixed.OwnerPID != takerPID {
		if err := l.lib.Playlists().SetOwner(ctx, fixed.PID, takerPID); err != nil {
			return nil, classify(err)
		}
		fixed.OwnerPID = takerPID
	}
	if err := l.lib.Playlists().Set(ctx, fixed.PID, pids); err != nil {
		return nil, classify(err)
	}
	return fixed, nil
}

// handoverHolders are the catalog users a record's copy can be held by: the
// recipient of this run, when there is one, and the recipient the record
// names, when that account is still there. The first of them is the one
// whose view of the catalog is searched: every shared list is in it, and a
// catalog user the departing member has or has not is not.
func (l *Library) handoverHolders(ctx context.Context, rec wdb.PlaylistHandover, taker model.PID) (viewer model.PID, holders map[model.PID]bool) {
	holders = map[model.PID]bool{}
	add := func(pid model.PID) {
		if pid == "" {
			return
		}
		holders[pid] = true
		if viewer == "" {
			viewer = pid
		}
	}
	add(taker)
	if earlier, err := l.db.UserByID(ctx, rec.TakerID); err == nil {
		add(model.PID(l.catalogPID(earlier)))
	}
	return viewer, holders
}

// markedCopy finds the static playlist carrying the marker of a source
// playlist that one of holders owns, as seen by viewer: the copy a run that
// stopped before naming it on record made. A handover only ever makes its
// copy for its recipient, so no other account's list is it, whatever it is
// called. The earliest is it, should there be more than one.
func (l *Library) markedCopy(ctx context.Context, source, viewer model.PID, holders map[model.PID]bool) (*model.Playlist, error) {
	if viewer == "" {
		return nil, nil
	}
	all, err := l.lib.Playlists().List(ctx, viewer)
	if err != nil {
		return nil, classify(err)
	}
	marker := handoverMarker(source)
	var found *model.Playlist
	for _, c := range all {
		if c.Kind == model.PlaylistStatic && holders[c.OwnerPID] && strings.HasSuffix(c.Name, marker) &&
			(found == nil || c.CreatedAt < found.CreatedAt) {
			found = c
		}
	}
	return found, nil
}

// nameCopy gives a fixed copy the name of the playlist it stands in for,
// in place of the marker's, once the record names it.
func (l *Library) nameCopy(ctx context.Context, fixed, pl *model.Playlist) error {
	if fixed.Name == pl.Name {
		return nil
	}
	if err := l.handoverStep("rename", pl); err != nil {
		return err
	}
	if err := l.lib.Playlists().Rename(ctx, fixed.PID, pl.Name); err != nil {
		return classify(err)
	}
	fixed.Name = pl.Name
	return nil
}

// takeBackCopy undoes a handover that failed with its copy made: the pins
// go back to the playlist, which is still there, and the copy is removed.
// A request that has gone away does not stop either. When the copy cannot
// be removed (the catalog that failed is the catalog to ask) it stays on
// record and the error says so, and the next deletion of the account takes
// it up or removes it.
func (l *Library) takeBackCopy(ctx context.Context, pl *model.Playlist, fixed model.PID, cause error) error {
	bg := context.WithoutCancel(ctx)
	if err := l.repointPins(bg, fixed, pl.PID); err != nil {
		l.log.Warn("putting a playlist's pins back", "playlist", pl.PID, "err", err)
	}
	if err := l.discardCopy(bg, fixed); err != nil {
		l.log.Warn("a fixed copy could not be taken back after its handover failed",
			"playlist", pl.PID, "copy", fixed, "cause", cause, "err", err)
		return copyLeft(cause, fixed)
	}
	l.forgetHandover(bg, pl.PID)
	return cause
}

// discardCopy removes a fixed copy; one that is already gone is removed.
func (l *Library) discardCopy(ctx context.Context, pid model.PID) error {
	fixed := &model.Playlist{PID: pid}
	if err := l.handoverStep("discard", fixed); err != nil {
		return err
	}
	if err := l.removePlaylist(ctx, fixed); err != nil && KindOf(err) != KindNotFound {
		return err
	}
	return nil
}

// settleHandoverLeftovers deals with what handovers that stopped left of
// playlists this deletion did not hand over: ones that were deleted since,
// by hand or with the rest, since every handover reads its own record and
// these never reach one. When the playlists are handed to taker the copy
// is what is left of the member's list, so it stays, for taker and under
// its own name; when they are not, nothing of the account's is wanted and
// the copy goes with the rest. The record goes once the copy is dealt with.
// Each copy is named in out as it is removed or kept, so the record of the
// deletion says what became of it, whether or not the deletion finishes.
func (l *Library) settleHandoverLeftovers(ctx context.Context, victim, taker *wdb.User, out *AccountDeleted) error {
	records, err := l.db.PlaylistHandoversOf(ctx, victim.ID)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	for _, rec := range records {
		copies, err := l.leftCopies(ctx, rec, taker)
		if err != nil {
			return err
		}
		for _, c := range copies {
			if taker == nil {
				if err := l.discardCopy(ctx, c.PID); err != nil {
					return err
				}
				out.FixedCopiesRemoved = append(out.FixedCopiesRemoved, apiPID(PrefixPlaylist, c.PID))
			} else {
				if err := l.keepCopy(ctx, c, model.PID(l.catalogPID(taker)), model.PID(rec.SourcePID)); err != nil {
					return err
				}
				out.FixedCopiesKept = append(out.FixedCopiesKept, apiPID(PrefixPlaylist, c.PID))
			}
			l.announcePlaylist(ctx, victim.ID, string(c.PID))
		}
		l.forgetHandover(ctx, model.PID(rec.SourcePID))
	}
	return nil
}

// leftCopies is the copies a record has left in the catalog: the one it
// names and the one carrying its playlist's marker, which are the same
// list unless the run that stopped did so between making it and naming it.
func (l *Library) leftCopies(ctx context.Context, rec wdb.PlaylistHandover, taker *wdb.User) ([]*model.Playlist, error) {
	var out []*model.Playlist
	if rec.CopyPID != "" {
		switch got, err := l.lib.Playlists().Get(ctx, model.PID(rec.CopyPID)); {
		case err == nil:
			out = append(out, got)
		case KindOf(classify(err)) != KindNotFound:
			return nil, classify(err)
		}
	}
	var takerPID model.PID
	if taker != nil {
		takerPID = model.PID(l.catalogPID(taker))
	}
	viewer, holders := l.handoverHolders(ctx, rec, takerPID)
	marked, err := l.markedCopy(ctx, model.PID(rec.SourcePID), viewer, holders)
	// A recipient the catalog has no user for sees none, and has none.
	if err != nil && KindOf(err) != KindNotFound {
		return nil, err
	}
	if marked != nil && !slices.ContainsFunc(out, func(c *model.Playlist) bool { return c.PID == marked.PID }) {
		out = append(out, marked)
	}
	return out, nil
}

// keepCopy gives a copy that stays to its recipient, under the name of the
// playlist it was made from rather than under the marker's.
func (l *Library) keepCopy(ctx context.Context, fixed *model.Playlist, takerPID, source model.PID) error {
	if fixed.OwnerPID != takerPID {
		if err := l.lib.Playlists().SetOwner(ctx, fixed.PID, takerPID); err != nil {
			return classify(err)
		}
	}
	if name := strings.TrimSuffix(fixed.Name, handoverMarker(source)); name != fixed.Name {
		if err := l.lib.Playlists().Rename(ctx, fixed.PID, name); err != nil {
			return classify(err)
		}
	}
	return nil
}

// forgetHandover clears a playlist's record once its handover is done or
// undone. A record that stays is inert, since a pid is never made twice,
// and goes with the account's deletion.
func (l *Library) forgetHandover(ctx context.Context, source model.PID) {
	if err := l.db.DeletePlaylistHandover(ctx, string(source)); err != nil {
		l.log.Warn("clearing a playlist handover record", "playlist", source, "err", err)
	}
}

// repointPins moves every account's home pin of one playlist to another
// and tells the accounts whose pins changed.
func (l *Library) repointPins(ctx context.Context, from, to model.PID) error {
	pinners, err := l.db.RepointPlaylistPins(ctx, apiPID(PrefixPlaylist, from), apiPID(PrefixPlaylist, to))
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	for _, id := range pinners {
		l.emitUserEvent(ctx, id, eventPrefs, "")
	}
	return nil
}

// playlistGone reports whether the catalog no longer has a playlist.
func (l *Library) playlistGone(ctx context.Context, pid model.PID) bool {
	_, err := l.lib.Playlists().Get(ctx, pid)
	return err != nil && KindOf(classify(err)) == KindNotFound
}

// carryPlaylistCover gives the new playlist the pictures its owner chose
// for the old one. A generated cover is left to be drawn again from the
// same tracks. Failures are logged: a list without its picture is still
// the list.
func (l *Library) carryPlaylistCover(ctx context.Context, from, to model.PID) {
	custom := false
	switch rec, err := l.db.PlaylistCoverFor(ctx, string(from)); {
	case err == nil:
		custom = rec.Origin == wdb.CoverCustom
	case !errors.Is(err, wdb.ErrNotFound):
		l.log.Warn("reading playlist cover state", "playlist", from, "err", err)
		return
	}
	src := model.EntityRef{Type: model.ArtPlaylist, PID: from}
	roles, err := l.lib.ArtRoles(ctx, src)
	if err != nil {
		l.log.Warn("reading a playlist's art", "playlist", from, "err", err)
		return
	}
	for _, r := range roles {
		if r.SourceHash == "" || (r.Role == model.ArtRoleFront && !custom) {
			continue
		}
		blob, err := l.lib.ResolveArt(ctx, src, r.Role, 0)
		if err != nil || blob == nil {
			l.log.Warn("reading a playlist's art", "playlist", from, "role", r.Role, "err", err)
			continue
		}
		var undo func()
		if r.Role == model.ArtRoleFront {
			if undo, err = l.claimPlaylistCoverCustom(ctx, to); err != nil {
				l.log.Warn("recording a playlist's cover", "playlist", to, "err", err)
				continue
			}
		}
		if err := l.lib.SetEntityArt(ctx, model.ArtPlaylist, to, r.Role, blob.Bytes, waxbin.ArtEditOptions{
			Lock: model.LockOff, Force: true,
		}); err != nil {
			l.log.Warn("storing a playlist's art", "playlist", to, "role", r.Role, "err", err)
			if undo != nil {
				undo()
			}
		}
	}
}

// hasCatalogUser reports whether the catalog knows the user an account
// acts as, which is what owning a playlist there takes.
func (l *Library) hasCatalogUser(ctx context.Context, u *wdb.User) (bool, error) {
	pid := l.catalogPID(u)
	if pid == "" {
		return false, nil
	}
	users, err := l.lib.Users(ctx)
	if err != nil {
		return false, classify(err)
	}
	return slices.ContainsFunc(users, func(cu *model.User) bool { return string(cu.PID) == pid }), nil
}
