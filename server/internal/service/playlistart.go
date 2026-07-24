package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strconv"
	"time"

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
// grid tile.
const coverMosaicSize = 1000

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
	// hands the slot back (ClearEntityArtwork flips the origin).
	if rec.Origin == wdb.CoverCustom {
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
	raw, err := composePlaylistCover(covers)
	if err != nil {
		// Record the fingerprint anyway. The remaining failure modes are
		// deterministic in the member set (a source no decoder here reads),
		// so retrying would resolve every member again on every read for as
		// long as the membership held.
		l.log.Warn("composing playlist cover", "playlist", pl.PID, "err", err)
		l.recordGeneratedCover(ctx, pl.PID, fp)
		return
	}
	// Empty bytes clear the slot: a playlist whose members all lost their
	// art should lose the mosaic built from it, not keep a stale one.
	if err := l.lib.SetEntityArt(ctx, model.ArtPlaylist, pl.PID, model.ArtRoleFront, raw, false); err != nil {
		l.log.Warn("storing playlist cover", "playlist", pl.PID, "err", err)
		return
	}
	pl.HasArt = len(raw) > 0
	l.recordGeneratedCover(ctx, pl.PID, fp)
}

// recordGeneratedCover stamps the member set and art epoch a generated
// cover was built at, so the next read knows it is current.
func (l *Library) recordGeneratedCover(ctx context.Context, playlistPID model.PID, fingerprint string) {
	if err := l.db.PutPlaylistCover(ctx, wdb.PlaylistCover{
		PlaylistPID: string(playlistPID),
		Origin:      wdb.CoverGenerated,
		Fingerprint: fingerprint,
		UpdatedAtNS: time.Now().UnixNano(),
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

// playlistCoverSources resolves member covers in order, keeping the
// first few that differ. Deduplication is by the catalog's own source
// hash, so a playlist drawn from one album tiles that album's cover
// once rather than four times -- a track resolves its album's art when
// it carries none of its own, which is exactly when the four would
// collide.
func (l *Library) playlistCoverSources(ctx context.Context, items []*model.ItemView) [][]byte {
	seen := make(map[string]bool, art.MosaicTiles)
	out := make([][]byte, 0, art.MosaicTiles)
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
		out = append(out, blob.Bytes)
	}
	return out
}

// composePlaylistCover turns resolved member covers into the stored
// image: a mosaic at four, the first cover alone below that, nothing at
// zero. Three distinct covers is a tile with a hole in it, so it shows
// one.
func composePlaylistCover(covers [][]byte) ([]byte, error) {
	switch {
	case len(covers) >= art.MosaicTiles:
		return art.Mosaic(covers[:art.MosaicTiles], coverMosaicSize)
	case len(covers) > 0:
		return covers[0], nil
	default:
		return nil, nil
	}
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
