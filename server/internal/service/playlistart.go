package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"slices"
	"strconv"
	"sync"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	"github.com/colespringer/waxdeck/server/internal/art"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Playlist covers. A playlist shows a user's upload when it has one,
// else a mosaic of the first four member covers that differ, else the
// single first member's cover, else nothing.
//
// The generated cover is stored through the catalog rather than cached
// beside it, so it rides the same blob store, thumbnail cache, and ETag
// as every other cover and needs no second serving path. The cost of
// that is provenance: the catalog cannot tell a mosaic from an upload,
// since both are a front-role art row that sets HasArt. playlist_cover
// carries the difference, plus the fingerprint that says when a mosaic
// has gone stale.

// coverMosaicSize is the stored mosaic's edge in pixels. The catalog
// derives every thumbnail from it, so it is sized for the largest
// surface that shows a playlist cover full width rather than for a
// grid tile. A ladder rung ([ArtSizeMosaic]): a stored source that sits
// on one is served whole at that rung instead of being re-encoded down
// to the rung just below its own edge.
const coverMosaicSize = ArtSizeMosaic

// coverScanDepth bounds how many members are resolved looking for four
// distinct covers. A playlist whose first few dozen tracks share one
// album cover shows that cover; walking thousands of members to find a
// fourth distinct one would cost more than the tiling is worth.
const coverScanDepth = 64

// playlistCoverFingerprint hashes the ordered member pids a generated
// cover was built from, scoped by the artwork-write epoch. The playlist
// read has the member list in hand already, so this costs nothing per
// read and catches every membership change and reorder; the epoch
// catches the other way a mosaic goes stale, a member replacing its own
// cover in place, which moves no member pid. Neither term needs an art
// resolve, which is what keeps this off the per-read cost.
func playlistCoverFingerprint(items []*model.ItemView, artEpoch int64) string {
	h := sha256.New()
	for i, it := range items {
		if i == coverScanDepth {
			break
		}
		h.Write([]byte(it.PID))
		h.Write([]byte{0})
	}
	return strconv.FormatInt(artEpoch, 10) + "-" + hex.EncodeToString(h.Sum(nil)[:16])
}

// reshufflesEveryRead reports whether a smart playlist draws a
// different member list on each evaluation. An unseeded random limit
// does, and regenerating a mosaic per read would mean four art resolves
// and a stored blob write every time anyone opened it. Those get a
// cover once and keep it.
func reshufflesEveryRead(pl *model.Playlist) bool {
	return pl.Rule != nil && pl.Rule.LimitMode == query.LimitRandom && pl.Rule.LimitSeed == 0
}

// syncPlaylistCover brings a playlist's generated cover up to date with
// its members. It runs where the members are already loaded (a playlist
// read, a membership write), never per art request, so a smart
// playlist whose computed membership has drifted refreshes the next
// time anyone looks at it.
//
// Failures are logged, not returned: a playlist that cannot be
// decorated still lists.
func (l *Library) syncPlaylistCover(ctx context.Context, pl *model.Playlist, items []*model.ItemView) {
	rec, err := l.db.PlaylistCoverFor(ctx, string(pl.PID))
	switch {
	case err == nil:
	case errors.Is(err, wdb.ErrNotFound):
		rec = wdb.PlaylistCover{PlaylistPID: string(pl.PID)}
	default:
		l.log.Warn("reading playlist cover state", "playlist", pl.PID, "err", err)
		return
	}
	// A user's upload wins and is never regenerated. Clearing it is what
	// hands the slot back (ClearEntityArtwork flips the origin). A
	// synced playlist's source thumbnail holds the slot the same way,
	// except the sync reconciler is what refreshes it.
	if rec.Origin == wdb.CoverCustom || rec.Origin == wdb.CoverSource {
		return
	}
	generated := rec.Origin == wdb.CoverGenerated
	if generated && reshufflesEveryRead(pl) {
		return
	}
	epoch, err := l.db.ArtEpoch(ctx)
	if err != nil {
		l.log.Warn("reading the art epoch", "playlist", pl.PID, "err", err)
		return
	}
	// The fingerprint alone decides, deliberately: a playlist whose
	// members carry no art generates nothing, and cross-checking HasArt
	// here would read that empty result as a missing cover and re-resolve
	// every member on every read forever.
	fp := playlistCoverFingerprint(items, epoch)
	if generated && rec.Fingerprint == fp {
		return
	}
	// One generation per playlist at a time. A shared playlist opened by
	// several people right after a member repaint would otherwise have
	// each reader resolve four covers and composite the same image.
	if !l.claimCoverSync(pl.PID) {
		return
	}
	defer l.releaseCoverSync(pl.PID)

	covers := l.playlistCoverSources(ctx, items)
	raw, drawn, err := composePlaylistCover(covers)
	if err != nil {
		// Record the fingerprint anyway. The remaining failure modes are
		// deterministic in the member set (a source no decoder here reads),
		// so retrying would resolve every member again on every read for as
		// long as the membership held. The stored image is the one before,
		// and so are the members it was drawn from.
		l.log.Warn("composing playlist cover", "playlist", pl.PID, "err", err)
		l.recordGeneratedCover(ctx, pl.PID, fp, rec.Sources)
		return
	}
	// The recorded sources vouch for the stored image, so they are
	// forgotten before another is stored: an image whose own sources then
	// fail to be recorded goes to no reader who cannot see every member.
	if err := l.db.ForgetPlaylistCoverSources(ctx, string(pl.PID)); err != nil {
		l.log.Warn("forgetting playlist cover sources", "playlist", pl.PID, "err", err)
		return
	}
	// Empty bytes clear the slot: a playlist whose members all lost their
	// art should lose the mosaic built from it, not keep a stale one.
	//
	// Stamped as generated, which is what it is: nobody chose this
	// picture, it was drawn here from the members' covers. Without the
	// source the store's default records `user`, and the byte endpoint's
	// X-Art-Source then tells another client a hand picked it. No provider
	// and no source URL, which is what the pairing rule requires.
	if err := l.lib.SetEntityArt(ctx, model.ArtPlaylist, pl.PID, model.ArtRoleFront, raw, waxbin.ArtEditOptions{
		Lock: model.LockOff, Force: true, Source: model.SourceGenerated,
	}); err != nil {
		l.log.Warn("storing playlist cover", "playlist", pl.PID, "err", err)
		return
	}
	pl.HasArt = len(raw) > 0
	l.recordGeneratedCover(ctx, pl.PID, fp, drawn)
}

// recordGeneratedCover stamps the member set and art epoch a generated
// cover was built at, so the next read knows it is current, and the
// members its tiles came from (nil where that is not known).
func (l *Library) recordGeneratedCover(ctx context.Context, playlistPID model.PID, fingerprint string, sources []string) {
	if l.coverRecordHook != nil {
		if err := l.coverRecordHook(); err != nil {
			l.log.Warn("recording playlist cover state", "playlist", playlistPID, "err", err)
			return
		}
	}
	if err := l.db.PutPlaylistCover(ctx, wdb.PlaylistCover{
		PlaylistPID: string(playlistPID),
		Origin:      wdb.CoverGenerated,
		Fingerprint: fingerprint,
		UpdatedAtNS: time.Now().UnixNano(),
		Sources:     sources,
	}); err != nil {
		l.log.Warn("recording playlist cover state", "playlist", playlistPID, "err", err)
	}
}

// claimCoverSync reserves one playlist's cover generation, reporting
// false when another is already running. Losing the race is not an
// error: the winner produces the same image, and the loser's read serves
// whatever is stored, which is at worst one refresh behind.
func (l *Library) claimCoverSync(playlistPID model.PID) bool {
	l.coverSyncMu.Lock()
	defer l.coverSyncMu.Unlock()
	if l.coverSyncing == nil {
		l.coverSyncing = map[model.PID]bool{}
	}
	if l.coverSyncing[playlistPID] {
		return false
	}
	l.coverSyncing[playlistPID] = true
	return true
}

func (l *Library) releaseCoverSync(playlistPID model.PID) {
	l.coverSyncMu.Lock()
	defer l.coverSyncMu.Unlock()
	delete(l.coverSyncing, playlistPID)
}

// coverTile is one member's cover a generated playlist cover may draw.
type coverTile struct {
	member model.PID
	bytes  []byte
}

// playlistCoverSources resolves member covers in order, keeping the
// first few that differ. Deduplication is by the catalog's own source
// hash, so a playlist drawn from one album tiles that album's cover
// once rather than four times -- a track resolves its album's art when
// it carries none of its own, which is exactly when the four would
// collide.
func (l *Library) playlistCoverSources(ctx context.Context, items []*model.ItemView) []coverTile {
	seen := make(map[string]bool, art.MosaicTiles)
	out := make([]coverTile, 0, art.MosaicTiles)
	for i, it := range items {
		if i == coverScanDepth || len(out) == art.MosaicTiles {
			break
		}
		entity := model.ArtTrack
		if it.Kind == model.KindEpisode {
			entity = model.ArtEpisode
		}
		// Ask for the mosaic's own edge rather than the original. Every
		// tile is scaled into a quadrant half that wide, so a full-size
		// original would be decoded and thrown away; the catalog serves the
		// source untouched when it is already within the box, which most
		// covers are, and the single-cover fallback below then stores a
		// sensibly sized image rather than a multi-megabyte scan.
		blob, err := l.lib.ResolveArt(ctx, model.EntityRef{Type: entity, PID: it.PID},
			model.ArtRoleFront, coverMosaicSize)
		if err != nil || blob == nil || len(blob.Bytes) == 0 {
			continue
		}
		// A blob with no source hash cannot be compared, so it counts as
		// its own art rather than being folded into whatever came before.
		if blob.SourceHash != "" {
			if seen[blob.SourceHash] {
				continue
			}
			seen[blob.SourceHash] = true
		}
		// Filter here rather than letting the composite fail: one stored
		// cover no decoder here reads, or one claiming more pixels than the
		// budget allows, should cost a tile and not the whole mosaic.
		if !art.Usable(blob.Bytes) {
			continue
		}
		out = append(out, coverTile{member: it.PID, bytes: blob.Bytes})
	}
	return out
}

// readerPlaylistCover answers the member whose cover stands in for the
// stored generated one when somebody other than the owner reads a shared
// playlist without seeing everything: the stored cover is drawn from
// members the reader may not see, so it goes to the reader only when the
// reader is offered every member it was drawn from, and otherwise the
// reader is shown the first member it is offered that has a cover. Nil
// keeps the stored cover: for the owner, a reader who sees everything,
// a cover somebody chose, and a reader its members are all shown to.
func (l *Library) readerPlaylistCover(ctx context.Context, uc *UserCtx, pl *model.Playlist) (*model.EntityRef, error) {
	if string(pl.OwnerPID) == uc.CatalogPID || seesEverything(uc) {
		return nil, nil
	}
	rec, err := l.db.PlaylistCoverFor(ctx, string(pl.PID))
	switch {
	case err == nil:
		if rec.Origin == wdb.CoverCustom || rec.Origin == wdb.CoverSource {
			return nil, nil
		}
	case !errors.Is(err, wdb.ErrNotFound):
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if rec.Sources != nil {
		shown, err := l.coverSourcesShown(ctx, uc, pl, rec.Sources)
		if err != nil || shown {
			return nil, err
		}
	}
	return l.readerMemberCover(ctx, uc, pl)
}

// coverSourcesShown reports whether the reader is offered every member a
// generated cover was drawn from, a read of those few alone. A member the
// catalog no longer holds is not offered.
func (l *Library) coverSourcesShown(ctx context.Context, uc *UserCtx, pl *model.Playlist, sources []string) (bool, error) {
	pids := make([]model.PID, 0, len(sources))
	for _, s := range sources {
		if !slices.Contains(pids, model.PID(s)) {
			pids = append(pids, model.PID(s))
		}
	}
	if len(pids) == 0 {
		return true, nil
	}
	views, err := l.lib.GetMany(ctx, pids)
	if err != nil {
		return false, classify(err)
	}
	if len(views) != len(pids) {
		return false, nil
	}
	f, err := l.withTagVerdicts(ctx, l.newMemberFilter(uc, pl), views)
	if err != nil {
		return false, err
	}
	for _, v := range views {
		if !l.memberVisible(ctx, f, v) {
			return false, nil
		}
	}
	return true, nil
}

// readerMemberCover is the cover a reader is shown in place of a stored
// one drawn from a member it cannot see: the first member it is offered,
// among the first coverScanDepth, that has a cover. It takes a read of the
// whole membership, a rule evaluation for a smart list, so the answer is
// kept for the reader while the catalog, its artwork and the playlist
// hold still, and for a minute at most: who follows which show, which
// decides the episodes it is offered, is no catalog change.
func (l *Library) readerMemberCover(ctx context.Context, uc *UserCtx, pl *model.Playlist) (*model.EntityRef, error) {
	head, err := l.lib.LatestChangeSeq(ctx)
	if err != nil {
		return nil, classify(err)
	}
	epoch, err := l.db.ArtEpoch(ctx)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	key := readerCoverKey{playlist: pl.PID, user: uc.ID, scope: uc.ScopeKey()}
	stamp := readerCoverStamp{generation: l.catalogGeneration(), head: head, art: epoch, updated: pl.UpdatedAt}
	ref, held := l.readerCovers.get(key, stamp)
	if !held {
		if ref, err = l.firstShownCover(ctx, uc, pl); err != nil {
			return nil, err
		}
		l.readerCovers.put(key, stamp, ref)
	}
	if ref == nil {
		return nil, errNotFound("no artwork for pid " + apiPID(PrefixPlaylist, pl.PID))
	}
	return ref, nil
}

// firstShownCover reads the playlist's members and answers the cover of
// the first, among the first coverScanDepth, that the reader is offered
// and that has one; nil for none.
func (l *Library) firstShownCover(ctx context.Context, uc *UserCtx, pl *model.Playlist) (*model.EntityRef, error) {
	items, err := l.playlistMembers(ctx, pl)
	if err != nil {
		return nil, err
	}
	items = items[:min(len(items), coverScanDepth)]
	f, err := l.withTagVerdicts(ctx, l.newMemberFilter(uc, pl), items)
	if err != nil {
		return nil, err
	}
	for _, it := range items {
		if !l.memberVisible(ctx, f, it) {
			continue
		}
		ref := itemArtRef(it)
		if _, err := l.lib.ArtProvenance(ctx, ref, model.ArtRoleFront); err == nil {
			return &ref, nil
		}
	}
	return nil, nil
}

// readerCoverCache keeps the member cover each reader was last shown for a
// shared playlist in place of its stored cover.
type readerCoverCache struct {
	mu      sync.Mutex
	entries map[readerCoverKey]readerCoverEntry
}

type readerCoverKey struct {
	playlist    model.PID
	user, scope string
}

// readerCoverStamp is what a kept answer stands on: the catalog's
// generation and change-log head, the artwork epoch, and the playlist's
// own last change.
type readerCoverStamp struct {
	generation, head, art, updated int64
}

type readerCoverEntry struct {
	stamp readerCoverStamp
	at    time.Time
	ref   *model.EntityRef
}

// readerCoverCap bounds the kept answers; readerCoverTTL is how long one
// is kept whatever its stamp says.
const (
	readerCoverCap = 1024
	readerCoverTTL = time.Minute
)

func (c *readerCoverCache) get(key readerCoverKey, stamp readerCoverStamp) (*model.EntityRef, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e, ok := c.entries[key]
	if !ok || e.stamp != stamp || time.Since(e.at) > readerCoverTTL {
		return nil, false
	}
	return e.ref, true
}

func (c *readerCoverCache) put(key readerCoverKey, stamp readerCoverStamp, ref *model.EntityRef) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.entries == nil || len(c.entries) >= readerCoverCap {
		c.entries = make(map[readerCoverKey]readerCoverEntry)
	}
	c.entries[key] = readerCoverEntry{stamp: stamp, at: time.Now(), ref: ref}
}

// itemArtRef is the art level an item's own cover sits at.
func itemArtRef(it *model.ItemView) model.EntityRef {
	if it.Kind == model.KindEpisode {
		return model.EntityRef{Type: model.ArtEpisode, PID: it.PID}
	}
	return model.EntityRef{Type: model.ArtTrack, PID: it.PID}
}

// composePlaylistCover turns resolved member covers into the stored
// image: a mosaic at four, the first cover alone below that, nothing at
// zero. Three distinct covers is a tile with a hole in it, so it shows
// one. It answers the members the image was drawn from too.
func composePlaylistCover(covers []coverTile) ([]byte, []string, error) {
	used := covers[:min(len(covers), 1)]
	if len(covers) >= art.MosaicTiles {
		used = covers[:art.MosaicTiles]
	}
	drawn := make([]string, len(used))
	for i, c := range used {
		drawn[i] = string(c.member)
	}
	switch len(used) {
	case 0:
		return nil, drawn, nil
	case 1:
		return used[0].bytes, drawn, nil
	}
	tiles := make([][]byte, len(used))
	for i, c := range used {
		tiles[i] = c.bytes
	}
	raw, err := art.Mosaic(tiles, coverMosaicSize)
	return raw, drawn, err
}

// noteArtworkChanged records that artwork somewhere in the catalog moved,
// so generated playlist covers built from it refresh on their next read.
// Failures are logged: a missed bump leaves a mosaic stale until the
// membership next changes, which is not worth failing an art edit over.
func (l *Library) noteArtworkChanged(ctx context.Context) {
	if err := l.db.BumpArtEpoch(ctx); err != nil {
		l.log.Warn("recording an artwork change", "err", err)
	}
}

// claimPlaylistCoverCustom records a user's upload as the playlist's
// cover before the image is stored, and returns what to restore if the
// store then fails. Claiming first is what keeps a concurrent playlist
// read from regenerating the mosaic over the upload between the two
// writes.
func (l *Library) claimPlaylistCoverCustom(ctx context.Context, playlistPID model.PID) (func(), error) {
	prev, err := l.db.PlaylistCoverFor(ctx, string(playlistPID))
	switch {
	case err == nil:
	case errors.Is(err, wdb.ErrNotFound):
		prev = wdb.PlaylistCover{}
	default:
		return nil, err
	}
	if err := l.db.PutPlaylistCover(ctx, wdb.PlaylistCover{
		PlaylistPID: string(playlistPID),
		Origin:      wdb.CoverCustom,
		UpdatedAtNS: time.Now().UnixNano(),
	}); err != nil {
		return nil, err
	}
	return func() {
		var rerr error
		if prev.Origin == "" {
			rerr = l.db.DeletePlaylistCover(ctx, string(playlistPID))
		} else {
			rerr = l.db.PutPlaylistCover(ctx, prev)
		}
		if rerr != nil {
			l.log.Warn("restoring playlist cover state", "playlist", playlistPID, "err", rerr)
		}
	}, nil
}

// refreshPlaylistCover loads the members itself and syncs. The read
// path passes the members it already had; this is for the write paths,
// where a membership change should show on the playlist grid without
// waiting for someone to open the playlist.
func (l *Library) refreshPlaylistCover(ctx context.Context, pl *model.Playlist) {
	items, err := l.lib.Playlists().Items(ctx, pl.PID, pl.OwnerPID)
	if err != nil {
		l.log.Warn("loading playlist members for its cover", "playlist", pl.PID, "err", err)
		return
	}
	l.syncPlaylistCover(ctx, pl, items)
}
