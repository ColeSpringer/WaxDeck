package service

import (
	"context"
	"errors"
	"sort"
	"strconv"
	"time"
	"unicode/utf8"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The Subsonic surface's own state over WaxDeck's tables: music folders
// with ids clients can keep, and the protocol's bookmarks.

// MusicFolder is one music library as a Subsonic client lists it.
type MusicFolder struct {
	ID         int64
	LibraryPID string
	Name       string
}

// subsonicMusicMedia are the library media a client can browse as music:
// a mixed root holds music too, while an audiobook root's files are books
// and the podcast library is episodes.
var subsonicMusicMedia = map[string]bool{"music": true, "mixed": true}

// MusicFolders lists the caller's music libraries, each under the folder
// id it was given the first time it was listed.
func (l *Library) MusicFolders(ctx context.Context, uc *UserCtx) ([]MusicFolder, error) {
	libs, err := l.musicLibraries(ctx, uc)
	if err != nil {
		return nil, err
	}
	pids := make([]string, len(libs))
	for i, lib := range libs {
		pids[i] = lib.PID
	}
	ids, err := l.db.MusicFolderIDs(ctx, pids)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	out := make([]MusicFolder, 0, len(libs))
	for _, lib := range libs {
		out = append(out, MusicFolder{ID: ids[lib.PID], LibraryPID: lib.PID, Name: lib.Name})
	}
	return out, nil
}

// MusicFolderLibrary answers the library a folder id names (lb-...). An
// id never assigned, a library removed since, one the caller is not
// granted, and one that is not music are all the same not-found.
func (l *Library) MusicFolderLibrary(ctx context.Context, uc *UserCtx, id int64) (string, error) {
	missing := errNotFound("no music folder " + strconv.FormatInt(id, 10))
	pid, ok, err := l.db.MusicFolderLibrary(ctx, id)
	if err != nil {
		return "", &Error{Kind: KindInternal, Err: err}
	}
	if !ok {
		return "", missing
	}
	libs, err := l.musicLibraries(ctx, uc)
	if err != nil {
		return "", err
	}
	for _, lib := range libs {
		if lib.PID == pid {
			return pid, nil
		}
	}
	return "", missing
}

// musicLibraries is the catalog's libraries narrowed to the caller's
// grants and to music.
func (l *Library) musicLibraries(ctx context.Context, uc *UserCtx) ([]LibraryInfo, error) {
	libs, err := l.Libraries(ctx)
	if err != nil {
		return nil, err
	}
	out := libs[:0]
	for _, lib := range libs {
		if !subsonicMusicMedia[lib.Media] {
			continue
		}
		if !uc.AllLibraries {
			_, bare, ok := parseAPIPID(lib.PID)
			if !ok || !uc.Libraries[string(bare)] {
				continue
			}
		}
		out = append(out, lib)
	}
	return out, nil
}

// SubsonicItems answers the items the caller can be offered - visible,
// allowed by their rules, out of the trash, an episode's show followed -
// among the API pids named, as summaries keyed by the pid asked for:
// the song entries the Subsonic index does not hold, a book's or a
// session's. One batch read; a pid naming nothing it may offer is absent.
func (l *Library) SubsonicItems(ctx context.Context, uc *UserCtx, apiItemPIDs []string) (map[string]ItemSummary, error) {
	asked := make(map[model.PID][]string, len(apiItemPIDs))
	pids := make([]model.PID, 0, len(apiItemPIDs))
	for _, api := range apiItemPIDs {
		prefix, pid, ok := parseAPIPID(api)
		if !ok || !itemPrefix(prefix) {
			continue
		}
		if _, held := asked[pid]; !held {
			pids = append(pids, pid)
		}
		asked[pid] = append(asked[pid], api)
	}
	out := make(map[string]ItemSummary, len(pids))
	if len(pids) == 0 {
		return out, nil
	}
	views, err := l.lib.GetMany(ctx, pids)
	if err != nil {
		return nil, classify(err)
	}
	verdicts, err := l.tagVerdicts(ctx, uc, views)
	if err != nil {
		return nil, err
	}
	subs := l.newSubscriptionFilter(uc)
	for _, it := range views {
		if !l.offersWith(ctx, uc, verdicts, it) || !subs.allowsItem(ctx, l, it) {
			continue
		}
		for _, api := range asked[it.PID] {
			if prefix, _, _ := parseAPIPID(api); prefixFitsKind(prefix, it.Kind) {
				out[api] = summary(it)
			}
		}
	}
	return out, nil
}

// SubsonicBookmark is one protocol bookmark as getBookmarks lists it.
type SubsonicBookmark struct {
	Item       ItemSummary
	PositionMS int64
	Comment    string
	CreatedAt  time.Time
	ChangedAt  time.Time
}

// subsonicCommentMax bounds a bookmark's comment, in characters.
const subsonicCommentMax = 1000

// bookmarkIsResume reports whether an item's bookmark is its resume
// position: a book's or an episode's.
func bookmarkIsResume(k model.Kind) bool {
	return k == model.KindEpisode || k == model.KindBook
}

// SubsonicBookmarkPositions answers where the caller's bookmark on each
// named item stands, in ms, for the items that have one, as the bookmark
// listing places them: resume holds the resume positions the caller has
// already read, by API pid, and the caller's rows are read here once.
func (l *Library) SubsonicBookmarkPositions(ctx context.Context, uc *UserCtx, apiItemPIDs []string, resume map[string]int64) (map[string]int64, error) {
	rows, err := l.db.SubsonicBookmarks(ctx, uc.ID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	saved := make(map[string]int64, len(rows))
	for _, row := range rows {
		if _, held := saved[row.ItemPID]; !held {
			saved[row.ItemPID] = row.PositionMS
		}
	}
	out := make(map[string]int64)
	for _, api := range apiItemPIDs {
		prefix, _, ok := parseAPIPID(api)
		if ok && (prefix == PrefixBook || prefix == PrefixEpisode) && resume[api] > 0 {
			out[api] = resume[api]
		} else if pos, held := saved[api]; held {
			out[api] = pos
		}
	}
	return out, nil
}

// SaveSubsonicBookmark creates or replaces the caller's bookmark on a
// visible item. A book's or an episode's bookmark is its resume
// position, so this checkpoints it, with the comment kept beside it when
// there is one; a finished one has no resume point, so its bookmark past
// the start is also a row of its own; any other item's is a row of its
// own, which leaves the item's resume position alone.
func (l *Library) SaveSubsonicBookmark(ctx context.Context, uc *UserCtx, apiItemPID string, positionMS int64, comment string) error {
	if positionMS < 0 {
		return errInvalid("position must not be negative")
	}
	if utf8.RuneCountInString(comment) > subsonicCommentMax {
		return errInvalid("comment must be at most " + strconv.Itoa(subsonicCommentMax) + " characters")
	}
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return err
	}
	pid := itemAPIPID(it)
	resume := bookmarkIsResume(it.Kind)
	keepRow := !resume || comment != ""
	if !keepRow && positionMS > 0 {
		st, err := l.lib.Playback().State(ctx, model.PID(uc.CatalogPID), it.PID)
		if err != nil {
			return classify(err)
		}
		keepRow = st != nil && st.Finished
	}
	// The row first, so a refusal at the cap changes nothing.
	if !keepRow {
		err = l.db.DeleteSubsonicBookmarks(ctx, uc.ID, pid)
	} else {
		now := time.Now().UnixNano()
		row := wdb.SubsonicBookmark{
			UserID: uc.ID, ItemPID: pid, PositionMS: positionMS, Comment: comment,
			CreatedAtNS: now, UpdatedAtNS: now,
		}
		err = l.db.PutSubsonicBookmark(ctx, row)
		if errors.Is(err, wdb.ErrSubsonicBookmarksFull) {
			// At the cap by the raw count. The rows the listing cannot
			// show do not count, so the count is taken again without them.
			_, hidden, rerr := l.listableBookmarkRows(ctx, uc)
			if rerr != nil {
				return rerr
			}
			err = l.db.PutSubsonicBookmark(ctx, row, hidden...)
		}
	}
	if errors.Is(err, wdb.ErrSubsonicBookmarksFull) {
		return &Error{Kind: KindConflict, Msg: "this account already holds the most bookmarks it can; delete one first"}
	}
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if resume {
		if _, err := l.Checkpoint(ctx, uc, pid, positionMS, nil); err != nil {
			return err
		}
	}
	return nil
}

// DeleteSubsonicBookmark removes the caller's bookmark on a visible item,
// and for a book or an episode clears the resume position it is.
func (l *Library) DeleteSubsonicBookmark(ctx context.Context, uc *UserCtx, apiItemPID string) error {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return err
	}
	pid := itemAPIPID(it)
	if err := l.db.DeleteSubsonicBookmarks(ctx, uc.ID, pid, apiItemPID); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if bookmarkIsResume(it.Kind) {
		if _, err := l.Checkpoint(ctx, uc, pid, 0, nil); err != nil {
			return err
		}
	}
	return nil
}

// SubsonicBookmarks lists the caller's bookmarks, one per item, most
// recently changed first and at most wdb.SubsonicBookmarkCap of them: the
// rows saved for tracks, and every book and episode in progress, carrying
// the comment saved with it. A finished book or episode has no resume
// point and is no bookmark of itself; one with a row and no resume
// position lists at the position its row holds, as a track's bookmark
// does once the track becomes a book.
func (l *Library) SubsonicBookmarks(ctx context.Context, uc *UserCtx) ([]SubsonicBookmark, error) {
	rows, _, err := l.listableBookmarkRows(ctx, uc)
	if err != nil {
		return nil, err
	}
	positioned, err := l.positionedSpoken(ctx, uc, wdb.SubsonicBookmarkCap, 500)
	if err != nil {
		return nil, err
	}
	var spoken []string
	for _, br := range rows {
		if bookmarkIsResume(br.item.Kind) {
			spoken = append(spoken, itemAPIPID(br.item))
		}
	}
	for _, it := range positioned {
		spoken = append(spoken, it.PID)
	}
	states, err := l.resumePositions(ctx, uc, spoken)
	if err != nil {
		return nil, err
	}
	out := make([]SubsonicBookmark, 0, len(rows)+len(positioned))
	for _, br := range rows {
		b := SubsonicBookmark{
			Item:       summary(br.item),
			PositionMS: br.row.PositionMS,
			Comment:    br.row.Comment,
			CreatedAt:  time.Unix(0, br.row.CreatedAtNS).UTC(),
			ChangedAt:  time.Unix(0, br.row.UpdatedAtNS).UTC(),
		}
		if st := states[b.Item.PID]; bookmarkIsResume(br.item.Kind) && st.positionMS > 0 {
			b.PositionMS, b.ChangedAt = st.positionMS, st.changed
		}
		out = append(out, b)
	}
	for _, it := range positioned {
		_, pid, _ := parseAPIPID(it.PID)
		st := states[it.PID]
		if _, saved := rows[pid]; saved || st.positionMS <= 0 {
			continue
		}
		out = append(out, SubsonicBookmark{Item: it, PositionMS: st.positionMS, CreatedAt: st.changed, ChangedAt: st.changed})
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].ChangedAt.After(out[j].ChangedAt) })
	return out[:min(len(out), wdb.SubsonicBookmarkCap)], nil
}

// bookmarkRow is one of the caller's rows the listing can show, and the
// item it names.
type bookmarkRow struct {
	row  wdb.SubsonicBookmark
	item *model.ItemView
}

// hiddenBookmarkCeiling bounds the rows kept for items out of the
// caller's sight for now: as many as the account can list, so a whole
// set hidden at once survives.
const hiddenBookmarkCeiling = wdb.SubsonicBookmarkCap

// listableBookmarkRows answers the caller's rows the listing can show, by
// the bare pid of the item each names, and the ones it cannot show but
// keeps, the item being out of the caller's sight for now, the newest
// hiddenBookmarkCeiling of them. A row naming nothing the catalog holds,
// or nothing at all, is deleted on the way, as is an older row for an
// item a newer row names and a hidden row past the ceiling, unless a read
// sorting the rows fell back: that hides what it could not judge.
func (l *Library) listableBookmarkRows(ctx context.Context, uc *UserCtx) (map[model.PID]bookmarkRow, []string, error) {
	rows, err := l.db.SubsonicBookmarks(ctx, uc.ID)
	if err != nil {
		return nil, nil, &Error{Kind: KindInternal, Err: err}
	}
	newest := make(map[model.PID]wdb.SubsonicBookmark, len(rows))
	pids := make([]model.PID, 0, len(rows))
	age := make(map[string]int, len(rows))
	var gone []string
	for i, row := range rows {
		age[row.ItemPID] = i
		_, pid, ok := parseAPIPID(row.ItemPID)
		if _, held := newest[pid]; !ok || held {
			gone = append(gone, row.ItemPID)
			continue
		}
		newest[pid] = row
		pids = append(pids, pid)
	}
	listed := make(map[model.PID]bookmarkRow, len(pids))
	var hidden []string
	sortCtx, degraded := WatchDegraded(ctx)
	if len(pids) > 0 {
		views, err := l.lib.GetMany(ctx, pids)
		if err != nil {
			return nil, nil, classify(err)
		}
		verdicts, err := l.tagVerdicts(sortCtx, uc, views)
		if err != nil {
			return nil, nil, err
		}
		subs := l.newSubscriptionFilter(uc)
		for _, it := range views {
			row := newest[it.PID]
			delete(newest, it.PID)
			if !l.offersWith(sortCtx, uc, verdicts, it) || !subs.allowsItem(sortCtx, l, it) {
				hidden = append(hidden, row.ItemPID)
				continue
			}
			listed[it.PID] = bookmarkRow{row: row, item: it}
		}
		for _, row := range newest {
			gone = append(gone, row.ItemPID)
		}
	}
	if len(hidden) > hiddenBookmarkCeiling && !degraded() {
		// The rows came newest first.
		sort.Slice(hidden, func(i, j int) bool { return age[hidden[i]] < age[hidden[j]] })
		gone = append(gone, hidden[hiddenBookmarkCeiling:]...)
		hidden = hidden[:hiddenBookmarkCeiling]
	}
	if err := l.db.DeleteSubsonicBookmarks(ctx, uc.ID, gone...); err != nil {
		l.log.Warn("pruning subsonic bookmarks", "err", err)
	}
	return listed, hidden, nil
}

// positionedSpoken lists the books and episodes the caller has in
// progress, newest first, at most limit of each, read page items at a
// time: the catalog's in-progress list, which a finished item has left.
func (l *Library) positionedSpoken(ctx context.Context, uc *UserCtx, limit, page int) ([]ItemSummary, error) {
	var out []ItemSummary
	for _, media := range []string{"audiobook", "podcast"} {
		listed := 0
		for cursor := ""; listed < limit; {
			got, err := l.Browse(ctx, uc, "in-progress", ItemFilter{MediaType: media}, 0, cursor, min(page, limit-listed))
			if err != nil {
				return nil, err
			}
			out = append(out, got.Items...)
			listed += len(got.Items)
			if cursor = got.Next; cursor == "" {
				break
			}
		}
	}
	return out, nil
}

// resumeState is where an item stands for the caller as a bookmark reads
// it: its resume position, none for a finished item, and when the
// position last moved.
type resumeState struct {
	positionMS int64
	changed    time.Time
}

// resumePositions reads the caller's resume positions for the items in
// one batch, keyed by API pid.
func (l *Library) resumePositions(ctx context.Context, uc *UserCtx, apiItemPIDs []string) (map[string]resumeState, error) {
	back := make(map[model.PID]string, len(apiItemPIDs))
	pids := make([]model.PID, 0, len(apiItemPIDs))
	for _, api := range apiItemPIDs {
		if _, pid, ok := parseAPIPID(api); ok {
			back[pid] = api
			pids = append(pids, pid)
		}
	}
	out := make(map[string]resumeState, len(pids))
	if len(pids) == 0 {
		return out, nil
	}
	states, err := l.lib.PlayStatesForItems(ctx, pids)
	if err != nil {
		return nil, classify(err)
	}
	user := model.PID(uc.CatalogPID)
	for pid, rows := range states {
		st := userPlayState(rows, user)
		if st == nil || st.Finished {
			continue
		}
		changed := st.LastProgressAt
		if changed <= 0 {
			changed = st.UpdatedAt
		}
		out[back[pid]] = resumeState{positionMS: st.PositionMS, changed: time.Unix(0, changed).UTC()}
	}
	return out, nil
}
