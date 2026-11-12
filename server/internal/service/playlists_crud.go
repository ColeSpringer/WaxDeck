package service

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/waxerr"
)

// resolvePlaylist fetches a playlist the caller may read: their own, or
// any shared one. Anything else reads as absent.
func (l *Playlists) resolvePlaylist(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (*model.Playlist, error) {
	prefix, pid, ok := parseAPIPID(apiPlaylistPID)
	if !ok || prefix != PrefixPlaylist {
		return nil, errNotFound("no playlist " + apiPlaylistPID)
	}
	pl, err := l.lib.Playlists().Get(ctx, pid)
	if err != nil {
		if KindOf(classify(err)) == KindNotFound {
			return nil, errNotFound("no playlist " + apiPlaylistPID)
		}
		return nil, classify(err)
	}
	if string(pl.OwnerPID) != uc.CatalogPID && pl.Visibility != model.VisibilityShared {
		return nil, errNotFound("no playlist " + apiPlaylistPID)
	}
	return pl, nil
}

// resolveOwnedPlaylist fetches a playlist the caller may edit.
func (l *Playlists) resolveOwnedPlaylist(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (*model.Playlist, error) {
	pl, err := l.resolvePlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return nil, err
	}
	if string(pl.OwnerPID) != uc.CatalogPID {
		return nil, &Error{Kind: KindForbidden, Msg: "only the owner may edit a playlist"}
	}
	return pl, nil
}

// List pages the caller's own playlists plus every shared one,
// ordered by name then pid. containsItem restricts to static playlists
// holding that item.
func (l *Playlists) List(ctx context.Context, uc *UserCtx, containsItem, cursor string, limit int) (PlaylistPage, error) {
	all, err := l.lib.Playlists().List(ctx, model.PID(uc.CatalogPID))
	if err != nil {
		return PlaylistPage{}, classify(err)
	}
	sort.SliceStable(all, func(i, j int) bool {
		ni, nj := strings.ToLower(all[i].Name), strings.ToLower(all[j].Name)
		if ni != nj {
			return ni < nj
		}
		return all[i].PID < all[j].PID
	})
	if containsItem != "" {
		filtered, err := l.filterPlaylistsByMember(ctx, uc, all, containsItem)
		if err != nil {
			return PlaylistPage{}, err
		}
		all = filtered
	}
	off, err := decodeOffsetCursor(cursor)
	if err != nil {
		return PlaylistPage{}, err
	}
	out := PlaylistPage{Playlists: []Playlist{}}
	// Once for the page: the node depends only on the caller, and every
	// static row's count rides it.
	narrow := l.staticMemberNarrow(ctx, uc)
	for i := off; i < len(all); i++ {
		if len(out.Playlists) == limit {
			out.Next = encodeOffsetCursor(i)
			break
		}
		out.Playlists = append(out.Playlists, l.dto(ctx, uc, all[i], false, narrow))
	}
	return out, nil
}

// filterPlaylistsByMember keeps static playlists whose stored members
// include the item. Membership scans each candidate's stored list;
// playlist libraries are small and the filter is an interactive
// add-to-playlist affordance, not a hot path. An item the caller cannot
// see is in none of them, the answer an unknown pid gets.
func (l *Playlists) filterPlaylistsByMember(ctx context.Context, uc *UserCtx, all []*model.Playlist, apiItemPID string) ([]*model.Playlist, error) {
	prefix, itemPID, ok := parseAPIPID(apiItemPID)
	if !ok || !itemPrefix(prefix) {
		return nil, errInvalid("containsItem must be an item pid")
	}
	if _, err := l.Grants.getVisibleItem(ctx, uc, apiItemPID); err != nil {
		if KindOf(err) == KindNotFound {
			return nil, nil
		}
		return nil, err
	}
	var out []*model.Playlist
	for _, pl := range all {
		if pl.Kind != model.PlaylistStatic {
			continue
		}
		items, err := l.lib.Playlists().Items(ctx, pl.PID, pl.OwnerPID)
		if err != nil {
			return nil, classify(err)
		}
		for _, it := range items {
			if it.PID == itemPID {
				out = append(out, pl)
				break
			}
		}
	}
	return out, nil
}

// ByPID returns one playlist with a computed count for smart
// lists.
func (l *Playlists) ByPID(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (Playlist, error) {
	pl, err := l.resolvePlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return Playlist{}, err
	}
	return l.dto(ctx, uc, pl, true, nil), nil
}

// CreatePlaylist creates a static or smart playlist owned by the
// caller.
func (l *Playlists) CreatePlaylist(ctx context.Context, uc *UserCtx, req PlaylistCreate) (Playlist, error) {
	name := strings.TrimSpace(req.Name)
	if name == "" {
		return Playlist{}, errInvalid("a playlist needs a name")
	}
	if err := checkPlaylistName(name); err != nil {
		return Playlist{}, err
	}
	vis, err := playlistVisibility(req.Visibility)
	if err != nil {
		return Playlist{}, err
	}
	owner := model.PID(uc.CatalogPID)
	var pid model.PID
	switch req.Kind {
	case string(model.PlaylistStatic):
		if req.Rule != nil {
			return Playlist{}, errInvalid("a static playlist does not take a rule")
		}
		items, err := l.resolveItemPIDs(ctx, uc, req.ItemPIDs)
		if err != nil {
			return Playlist{}, err
		}
		if pid, err = l.createStaticWith(ctx, name, owner, vis, items); err != nil {
			return Playlist{}, err
		}
	case string(model.PlaylistSmart):
		if req.Rule == nil {
			return Playlist{}, errInvalid("a smart playlist needs a rule")
		}
		if len(req.ItemPIDs) > 0 {
			return Playlist{}, errInvalid("a smart playlist does not take members")
		}
		q, err := ruleToQuery(*req.Rule)
		if err != nil {
			return Playlist{}, err
		}
		return l.createSmartFromQuery(ctx, uc, name, vis, q)
	default:
		return Playlist{}, errInvalid("kind must be static or smart")
	}
	pl, err := l.lib.Playlists().Get(ctx, pid)
	if err != nil {
		return Playlist{}, classify(err)
	}
	// Cover the playlist now rather than on its first open, so a list
	// created from a selection is not a blank tile on the grid it lands
	// back on.
	l.refreshPlaylistCover(ctx, pl)
	l.emitPlaylistEvent(ctx, uc, pl.Visibility == model.VisibilityShared, string(pid))
	return l.dto(ctx, uc, pl, true, nil), nil
}

// createSmartFromQuery stores one smart playlist from an engine query
// already in hand, and is the single smart-create path: the wire rule
// converts to a query and lands here, and so does an NSP document,
// which WaxBin's importer hands over as a query directly.
//
// Taking a query rather than a wire rule is what lets the NSP import
// skip a round trip through the wire vocabulary. That round trip is not
// merely wasted: the engine accepts field aliases the wire table does
// not list (`albumartist` beside `album_artist`), so a query WaxBin
// built correctly can fail a conversion back to a rule the editor would
// render.
func (l *Playlists) createSmartFromQuery(
	ctx context.Context,
	uc *UserCtx,
	name string,
	vis model.PlaylistVisibility,
	q query.Query,
) (Playlist, error) {
	owner := model.PID(uc.CatalogPID)
	// A dry-run evaluation surfaces engine-level rejections (a bad tag
	// key, an unsortable sort) at write time, per the contract.
	if _, err := l.lib.Count(ctx, q, owner); err != nil {
		return Playlist{}, classify(err)
	}
	pid, err := l.lib.Playlists().CreateSmart(ctx, name, owner, vis, q)
	if err != nil {
		return Playlist{}, classify(err)
	}
	pl, err := l.lib.Playlists().Get(ctx, pid)
	if err != nil {
		return Playlist{}, classify(err)
	}
	// Cover the playlist now rather than on its first open, so a list
	// created from a selection is not a blank tile on the grid it lands
	// back on.
	l.refreshPlaylistCover(ctx, pl)
	l.emitPlaylistEvent(ctx, uc, pl.Visibility == model.VisibilityShared, string(pid))
	return l.dto(ctx, uc, pl, true, nil), nil
}

// UpdatePlaylist applies a partial update: a rename, a visibility
// change, or a smart playlist's rule, in any combination. Each applies
// in place under a stable pid - the rule setter lets the rule change
// without reissuing - so one server event carries the result.
func (l *Playlists) UpdatePlaylist(ctx context.Context, uc *UserCtx, apiPlaylistPID string, req PlaylistUpdate) (Playlist, error) {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return Playlist{}, err
	}
	wasShared := pl.Visibility == model.VisibilityShared

	name := pl.Name
	if req.Name != nil {
		name = strings.TrimSpace(*req.Name)
		if name == "" {
			return Playlist{}, errInvalid("a playlist needs a name")
		}
		if err := checkPlaylistName(name); err != nil {
			return Playlist{}, err
		}
	}
	vis := pl.Visibility
	if req.Visibility != nil {
		vis, err = playlistVisibility(*req.Visibility)
		if err != nil {
			return Playlist{}, err
		}
	}

	// Validate the rule before any mutation, so a bad rule (a static
	// playlist, an unknown field, an invalid limit mode) fails the whole
	// PATCH with nothing changed. The dry-run Count surfaces engine-level
	// rejections at write time, per the contract.
	var newRule *query.Query
	if req.Rule != nil {
		if pl.Kind != model.PlaylistSmart {
			return Playlist{}, errInvalid("a static playlist does not take a rule")
		}
		q, err := ruleToQuery(*req.Rule)
		if err != nil {
			return Playlist{}, err
		}
		if _, err := l.lib.Count(ctx, q, pl.OwnerPID); err != nil {
			return Playlist{}, classify(err)
		}
		newRule = &q
	}

	// Apply the changes. The engine facade has no cross-call transaction,
	// so a multi-field PATCH interrupted by a transient engine fault can
	// apply some fields and not others. Two things bound that: every
	// validation is front-loaded above (name, visibility, and the rule
	// dry-run all run before the first mutation), so only an I/O fault
	// can interrupt here; and each setter is idempotent, so the caller's
	// retry converges. The cheap metadata applies first and the rule
	// last, so a metadata fault never leaves a changed rule behind.
	if req.Name != nil && name != pl.Name {
		if err := l.lib.Playlists().Rename(ctx, pl.PID, name); err != nil {
			return Playlist{}, classify(err)
		}
	}
	if req.Visibility != nil && vis != pl.Visibility {
		if err := l.lib.Playlists().SetVisibility(ctx, pl.PID, vis); err != nil {
			return Playlist{}, classify(err)
		}
	}
	if newRule != nil {
		if err := l.lib.Playlists().SetRule(ctx, pl.PID, *newRule); err != nil {
			return Playlist{}, classify(err)
		}
	}
	// A visibility flip in either direction changes who can see the
	// playlist, so fan out to everyone when it is (or was) shared.
	l.emitPlaylistEvent(ctx, uc, wasShared || vis == model.VisibilityShared, string(pl.PID))
	got, err := l.lib.Playlists().Get(ctx, pl.PID)
	if err != nil {
		return Playlist{}, classify(err)
	}
	if newRule != nil {
		// A new rule is a new member list, so the cover built from the old
		// one is stale. This is a one-shot edit, not a gesture like the
		// reorder, and the caller often lands back on the playlist grid,
		// which loads no members of its own.
		l.refreshPlaylistCover(ctx, got)
	}
	return l.dto(ctx, uc, got, true, nil), nil
}

// DeletePlaylist deletes a playlist its owner made, or any shared one for
// an administrator: that is how a shared playlist whose owner is gone is
// cleared. Editing stays the owner's.
func (l *Playlists) DeletePlaylist(ctx context.Context, uc *UserCtx, apiPlaylistPID string) error {
	pl, err := l.resolvePlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return err
	}
	owned := string(pl.OwnerPID) == uc.CatalogPID
	if !owned && !uc.Admin {
		return &Error{Kind: KindForbidden, Msg: "only the owner or an administrator may delete a playlist"}
	}
	wasShared := pl.Visibility == model.VisibilityShared
	if err := l.removePlaylist(ctx, pl); err != nil {
		return err
	}
	// A deleted starter stays deleted: without this the boot reconcile
	// would find it missing from the catalog and seed it again. The REST
	// and Subsonic deletes both come through here; an account's deletion
	// does not, and needs no dismissal, since its starter rows go with
	// it. The catalog names an owner by account id, and it is the owner's
	// starter.
	l.dismissStarterPlaylist(ctx, pl.OwnerName, pl.PID)
	l.emitPlaylistEvent(ctx, uc, wasShared, string(pl.PID))
	detail := map[string]any{"shared": wasShared}
	if !owned {
		detail["owner"] = l.Audit.usernameOf(ctx, pl.OwnerName)
	}
	l.Audit.Record(ctx, uc, "playlist.delete",
		AuditTarget{Kind: "playlist", PID: apiPID(PrefixPlaylist, pl.PID), Name: pl.Name}, detail)
	return nil
}

// removePlaylist deletes a playlist and what WaxDeck keeps beside it.
func (l *Playlists) removePlaylist(ctx context.Context, pl *model.Playlist) error {
	if err := l.lib.Playlists().Delete(ctx, pl.PID); err != nil {
		return classify(err)
	}
	// The catalog drops the art rows with the playlist; this drops the
	// provenance beside them, so a later playlist minted with the same
	// pid does not inherit a custom origin over an empty slot.
	if err := l.db.DeletePlaylistCover(ctx, string(pl.PID)); err != nil {
		l.log.Warn("clearing playlist cover state", "playlist", pl.PID, "err", err)
	}
	// A source binding without its playlist is an orphan the sweeper
	// would trip over forever.
	if err := l.db.DeletePlaylistSource(ctx, string(pl.PID)); err != nil {
		l.log.Warn("clearing playlist source binding", "playlist", pl.PID, "err", err)
	}
	return nil
}

// Items pages a playlist's members. A smart playlist evaluates
// against its owner's user state (the contract for shared lists); the
// caller's own library visibility still filters what they see.
func (l *Playlists) Items(ctx context.Context, uc *UserCtx, apiPlaylistPID, cursor string, limit int) (PlaylistItemsPage, error) {
	pl, err := l.resolvePlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return PlaylistItemsPage{}, err
	}
	items, err := l.members(ctx, pl)
	if err != nil {
		return PlaylistItemsPage{}, err
	}
	off, err := decodeOffsetCursor(cursor)
	if err != nil {
		return PlaylistItemsPage{}, err
	}
	// The members are loaded here anyway, so this is where a generated
	// cover catches up with them: a smart playlist whose computed
	// membership drifted refreshes the next time anyone opens it, without
	// costing an art request a resolve. It runs after the cursor check, so
	// a malformed cursor answers 400 without doing the work. The full
	// member list is used, not the caller's filtered view -- the cover
	// belongs to the playlist, like its name, not to whoever is reading it.
	// For a smart list "full" now means the rule's own evaluation with
	// the state predicate inside it, so a trashed member stops
	// contributing cover art; that is a deliberate consequence of moving
	// the predicate into the query rather than a second policy.
	l.syncPlaylistCover(ctx, pl, items)
	// A static list's members are stored rows and are filtered here; a
	// smart list's already left the query filtered. Positions count off
	// the full stored list, members the caller cannot see included, so a
	// restore lands where it was; only the owner removes by position, and
	// anyone else would read in their gaps where the hidden members sit.
	// The cursor counts the entries the caller was shown for the same
	// reason, and a page says there is more only when another one follows.
	positioned := pl.Kind == model.PlaylistStatic && string(pl.OwnerPID) == uc.CatalogPID
	f, err := l.withTagVerdicts(ctx, l.newMemberFilter(uc, pl), items)
	if err != nil {
		return PlaylistItemsPage{}, err
	}
	out := PlaylistItemsPage{Entries: []PlaylistEntry{}}
	shown := 0
	for i, it := range items {
		if !l.memberVisible(ctx, f, it) {
			continue
		}
		shown++
		if shown <= off {
			continue
		}
		if len(out.Entries) == limit {
			out.Next = encodeOffsetCursor(off + limit)
			break
		}
		entry := PlaylistEntry{Item: summary(it)}
		if positioned {
			pos := i
			entry.Position = &pos
		}
		out.Entries = append(out.Entries, entry)
	}
	return out, nil
}

// createStaticWith creates a static playlist holding items, taking the
// list back when its members cannot be added: two writes behind one
// call, so a failure leaves nothing for a retry to duplicate.
func (l *Playlists) createStaticWith(ctx context.Context, name string, owner model.PID, vis model.PlaylistVisibility, items []model.PID) (model.PID, error) {
	pid, err := l.lib.Playlists().CreateStatic(ctx, name, owner, vis)
	if err != nil {
		return "", classify(err)
	}
	if len(items) > 0 {
		if err := l.lib.Playlists().Add(ctx, pid, items...); err != nil {
			if derr := l.lib.Playlists().Delete(ctx, pid); derr != nil {
				l.log.Warn("removing a half-made playlist", "playlist", pid, "err", derr)
			}
			return "", classify(err)
		}
	}
	return pid, nil
}

// ReplacePlaylistItems replaces a static playlist's full member list;
// this is the reorder primitive.
func (l *Playlists) ReplacePlaylistItems(ctx context.Context, uc *UserCtx, apiPlaylistPID string, itemPIDs []string, baseUpdatedAt *time.Time) error {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return err
	}
	if pl.Kind != model.PlaylistStatic {
		return errInvalid("a smart playlist's membership is its rule")
	}
	// Clients echo the timestamp through their own date-time types
	// (Dart keeps microseconds, JavaScript milliseconds), so the
	// lost-update guard compares at millisecond grain; nanosecond
	// identity would refuse every honest reorder from a client that
	// cannot represent the stored precision.
	if baseUpdatedAt != nil {
		stored := time.Unix(0, pl.UpdatedAt).UTC().Truncate(time.Millisecond)
		if !baseUpdatedAt.Truncate(time.Millisecond).Equal(stored) {
			return &Error{Kind: KindConflict, Msg: "the playlist changed since this member list was built; refetch and retry"}
		}
	}
	// A replace built by an owner who cannot currently see every stored
	// member would silently drop the hidden ones; refuse instead. The
	// member list hides on four dimensions - library visibility,
	// unsubscribed shows' episodes, trashed members, and content rules -
	// so the guard covers all four, and the middle two apply to
	// full-visibility users too. This path is static-only (refused
	// above), so pl.Rule is nil and no state-naming rule exempts the
	// archived arm.
	stored, err := l.lib.Playlists().Items(ctx, pl.PID, pl.OwnerPID)
	if err != nil {
		return classify(err)
	}
	subs := l.Podcasts.newSubscriptionFilter(uc)
	for _, it := range stored {
		if archived(it) {
			return &Error{Kind: KindConflict, Msg: "the playlist holds members that are in the trash; a replace would drop them permanently"}
		}
		if !uc.AllLibraries && !l.Grants.viewVisible(ctx, uc, it) {
			return &Error{Kind: KindConflict, Msg: "the playlist holds members outside your current library visibility; a replace would drop them"}
		}
		if !subs.allowsItem(ctx, l.Podcasts, it) {
			return &Error{Kind: KindConflict, Msg: "the playlist holds episodes of shows you are not subscribed to; a replace would drop them"}
		}
		if !l.Grants.allowedByContent(ctx, uc, it) {
			return &Error{Kind: KindConflict, Msg: "the playlist holds members your content settings hide; a replace would drop them"}
		}
	}
	items, err := l.resolveItemPIDs(ctx, uc, itemPIDs)
	if err != nil {
		return err
	}
	if err := l.lib.Playlists().Set(ctx, pl.PID, items); err != nil {
		return classify(err)
	}
	// No eager cover rebuild here. This is the reorder primitive, so it
	// runs on every drag, and rebuilding a mosaic is four art resolves
	// and a composite; the caller is looking at the member list and
	// re-reads it immediately, where the read-path sync catches up.
	l.emitPlaylistEvent(ctx, uc, pl.Visibility == model.VisibilityShared, string(pl.PID))
	return nil
}

// AddPlaylistItems appends members to a static playlist.
func (l *Playlists) AddPlaylistItems(ctx context.Context, uc *UserCtx, apiPlaylistPID string, itemPIDs []string) error {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return err
	}
	if pl.Kind != model.PlaylistStatic {
		return errInvalid("a smart playlist's membership is its rule")
	}
	items, err := l.resolveItemPIDs(ctx, uc, itemPIDs)
	if err != nil {
		return err
	}
	if len(items) == 0 {
		return errInvalid("no items to add")
	}
	if err := l.lib.Playlists().Add(ctx, pl.PID, items...); err != nil {
		return classify(err)
	}
	// Unlike the reorder and remove above, nothing reads the members
	// after this: adding happens from the player, and the next thing to
	// show the playlist is a grid tile. Cover it now.
	l.refreshPlaylistCover(ctx, pl)
	l.emitPlaylistEvent(ctx, uc, pl.Visibility == model.VisibilityShared, string(pl.PID))
	return nil
}

// RemovePlaylistItemAt removes the member at one listing position.
// expectAPIPID is the item the caller saw there; empty removes unguarded.
func (l *Playlists) RemovePlaylistItemAt(ctx context.Context, uc *UserCtx, apiPlaylistPID string, position int, expectAPIPID string) error {
	return l.RemovePlaylistItemsAt(ctx, uc, apiPlaylistPID, []int{position}, []string{expectAPIPID})
}

// RemovePlaylistItemsAt removes the members at several positions in one
// write, each naming the listing as it stood before any of them went and
// guarded by the item it must still hold ("" skips that check), so a
// listing gone stale removes nothing.
func (l *Playlists) RemovePlaylistItemsAt(ctx context.Context, uc *UserCtx, apiPlaylistPID string, positions []int, expectAPIPIDs []string) error {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return err
	}
	if pl.Kind != model.PlaylistStatic {
		return errInvalid("a smart playlist's membership is its rule")
	}
	for _, p := range positions {
		if p < 0 {
			return errInvalid("a position is 0 or more")
		}
	}
	expect := make([]model.PID, len(expectAPIPIDs))
	for i, raw := range expectAPIPIDs {
		if raw == "" {
			continue
		}
		prefix, pid, ok := parseAPIPID(raw)
		if !ok || !itemPrefix(prefix) {
			return errInvalid("itemPid is not an item pid")
		}
		expect[i] = pid
	}
	if err := l.lib.Playlists().RemoveAtMany(ctx, pl.PID, positions, expect); err != nil {
		switch {
		case waxerr.Is(err, waxerr.CodeConflict):
			return &Error{Kind: KindConflict, Msg: "the playlist changed since its members were read; refetch and retry", Err: err}
		case waxerr.Is(err, waxerr.CodeNotFound) && len(positions) == 1:
			return &Error{Kind: KindNotFound, Msg: fmt.Sprintf("no member at position %d", positions[0]), Err: err}
		}
		return classify(err)
	}
	// Same as the reorder: the caller is in the member list and re-reads
	// it, so the cover catches up there rather than on this request.
	l.emitPlaylistEvent(ctx, uc, pl.Visibility == model.VisibilityShared, string(pl.PID))
	return nil
}

// PreviewRule evaluates a rule statelessly for the caller.
func (l *Playlists) PreviewRule(ctx context.Context, uc *UserCtx, rule SmartRule, limit int) (PlaylistPreview, error) {
	q, err := ruleToQuery(rule)
	if err != nil {
		return PlaylistPreview{}, err
	}
	// The preview has to evaluate what the saved playlist would, or a
	// rule looks right in the editor and comes back shorter once saved.
	q = evaluableRule(q)
	user := model.PID(uc.CatalogPID)
	// Total is the condition-match count, ignoring the rule's own limit.
	// A random or budget mode rejects a zero limit, so count as a plain
	// match count rather than reusing the rule's mode. It counts only
	// what the caller may be offered, or the number would report matches
	// in libraries and under rules that hide them.
	qc := q
	qc.Limit = 0
	qc.LimitMode = query.LimitCount
	qc.LimitSeed = 0
	qc.Sorts = nil
	qc.Where = l.readerNarrow(ctx, uc)
	if q.Where != nil {
		qc.Where = query.And{Nodes: []query.Node{q.Where, qc.Where}}
	}
	total, err := l.lib.Count(ctx, qc, user)
	if err != nil {
		return PlaylistPreview{}, classify(err)
	}
	// The items evaluate the real rule. A plain count limit can be
	// narrowed to the preview page for efficiency; a random or budget
	// limit must evaluate as written (its limit is a draw size or a
	// budget, not a row cap) and is capped for display in the loop.
	qi := q
	if qi.LimitMode == query.LimitCount && (qi.Limit == 0 || qi.Limit > limit) {
		qi.Limit = limit
	}
	items, err := l.lib.Query(ctx, qi, user)
	if err != nil {
		return PlaylistPreview{}, classify(err)
	}
	// The page is the rule as a saved list evaluates it, limit first,
	// then filtered as that list's listing filters it.
	f, err := l.withTagVerdicts(ctx, memberFilter{uc: uc, subs: l.Podcasts.newSubscriptionFilter(uc), keepArchived: ruleNamesState(q.Where)}, items)
	if err != nil {
		return PlaylistPreview{}, err
	}
	out := PlaylistPreview{Items: []ItemSummary{}, Total: total}
	for _, it := range items {
		if len(out.Items) >= limit {
			break
		}
		if !l.memberVisible(ctx, f, it) {
			continue
		}
		out.Items = append(out.Items, summary(it))
	}
	return out, nil
}
