package service

import (
	"context"
	"errors"
	"time"

	"github.com/colespringer/waxbin"
	waxart "github.com/colespringer/waxbin/art"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/read"

	"github.com/colespringer/waxdeck/server/internal/providers"
)

// The artist portrait sweep, for the artists the catalog's own pass
// cannot reach. Upstream fills artist art now - fanart.tv and Deezer
// both answer the artist target through the enrichment port - but its
// backfill queue selects on `artist.mbid`, which the identity phase
// fills only for artists MusicBrainz matched. An artist that never
// matched is never asked about, and those are exactly the artists most
// likely to be missing a picture.
//
// So this covers what that pass leaves, which is decided by whether the
// pass runs at all. Enrichment needs a contact and is off without one
// (Config.EnrichmentContact), and a library tagged by Picard or beets
// carries artist mbids straight off the files - so on a stock install
// every artist has an id and nothing enriches them. Handing those to a
// pass that is not running is how the flag ends up reporting on while
// no portrait is ever fetched. With a contact set, the mbid-carrying
// artists are the catalog's and this walks the remainder; without one,
// this walks the lot.
//
// Fills are fill-when-empty, pin-respecting, provenance-stamped, and
// stored at `front`, the slot both the artist screen and the index
// tiles resolve. Auxiliary roles are the port's and are not attempted
// here.
//
// This whole file retires when the name-keyed artist walk in
// docs/upstream-requests.md lands, at which point the catalog pass
// covers the unmatched artists too - and covers them whether or not a
// contact is configured, which is the other half of what retires it.

// ArtistArtProvider answers a portrait for one artist; nil disables the
// sweep. The narrow interface keeps the service free of the upstream
// vocabularies, the same shape RadioArtResolver takes, and it
// distinguishes its two failures the same way: ErrNoArtistImage is
// answered-and-empty, anything else is "could not ask".
type ArtistArtProvider interface {
	ArtistImage(ctx context.Context, name, mbid string) (providers.TitleCoverResult, error)
}

const (
	// artistArtPageSize is the entity-page stride the sweep walks in.
	artistArtPageSize = 200
	// artistArtRetryAfter is how long a recorded miss holds. Finite
	// because providers gain images; long because a library's set of
	// unfindable artists is stable and every retry is a network ask.
	// A miss recorded under a different MBID than the artist now
	// carries is disregarded regardless of age.
	artistArtRetryAfter = 30 * 24 * time.Hour
)

// ArtistArtSweepResult counts what one pass did, for the log line.
type ArtistArtSweepResult struct {
	Scanned int
	Filled  int
	Misses  int
}

// ArtistArtWake signals that an enrichment run was started, so the
// sweep loop runs a pass alongside it instead of waiting out its tick.
func (l *Library) ArtistArtWake() <-chan struct{} { return l.artistArtWake }

// ArtistArtSweep fills missing artist portraits through the entity
// artwork surface: fill-when-empty, pin-respecting, provenance-stamped,
// like the enrichment writes it rides beside. Misses are recorded in
// waxdeck.db so artists with no findable image are not refetched every
// pass; a transient provider failure is not recorded and retries on the
// next one. A throttled provider ends the pass early rather than
// hammering on.
func (l *Library) ArtistArtSweep(ctx context.Context) (ArtistArtSweepResult, error) {
	var res ArtistArtSweepResult
	if l.artistArt == nil {
		return res, nil
	}
	var cursor read.Cursor
	for {
		page, err := l.lib.EntityPage(ctx, read.EntityArtist, cursor, artistArtPageSize)
		if err != nil {
			return res, classify(err)
		}
		pids := make([]string, 0, len(page.Entities))
		for _, ent := range page.Entities {
			pids = append(pids, string(ent.PID))
		}
		misses, err := l.db.ArtistArtMisses(ctx, pids)
		if err != nil {
			return res, &Error{Kind: KindInternal, Err: err}
		}
		for _, ent := range page.Entities {
			if err := ctx.Err(); err != nil {
				return res, err
			}
			// An artist MusicBrainz matched belongs to the catalog's
			// own artist-art pass, which asks by mbid on the
			// enrichment port; asking again here would put a
			// name-matched face beside an identity-matched one and
			// race it for the slot. Only when that pass is actually
			// running, though - without a contact it is not, and
			// skipping these would leave them with no pass at all.
			if ent.MBID != "" && l.enrichmentConfigured {
				continue
			}
			res.Scanned++
			// Cheapest guards first: a placeholder name is never one
			// artist (a portrait for "Various Artists" is somebody
			// else's face on every compilation), and the miss map is
			// already in memory.
			if providers.ArtistNamePlaceholder(ent.Name) {
				continue
			}
			if m, ok := misses[string(ent.PID)]; ok && m.MBID == ent.MBID &&
				time.Since(time.Unix(0, m.AttemptedAtNS)) < artistArtRetryAfter {
				continue
			}
			// An artist already holding a portrait - swept, hand-set, or
			// embedded - is left alone. Only a clean not-found means the
			// slot is empty; any other failure must not read as "empty"
			// and be painted over.
			ref := model.EntityRef{Type: model.ArtArtist, PID: ent.PID}
			if _, err := l.lib.ArtProvenance(ctx, ref, model.ArtRoleFront); err == nil {
				continue
			} else if KindOf(classify(err)) != KindNotFound {
				l.log.Warn("artist art: reading provenance", "artist", ent.Name, "err", err)
				continue
			}
			// A standing pin on an empty slot is a person's "do not
			// refill this", the same intent every enrichment write
			// respects - and a failed read must not read as "unpinned",
			// because this check is the only thing between that intent
			// and a write.
			locked, err := l.lib.ArtLocked(ctx, model.ArtArtist, ent.PID, model.ArtRoleFront)
			if err != nil {
				l.log.Warn("artist art: reading pin", "artist", ent.Name, "err", err)
				continue
			}
			if locked {
				continue
			}
			img, err := l.artistArt.ArtistImage(ctx, ent.Name, ent.MBID)
			switch {
			case errors.Is(err, providers.ErrNoArtistImage):
				l.recordArtistArtMiss(ctx, ent)
				res.Misses++
				continue
			case err != nil:
				if errors.Is(err, providers.ErrThrottled) {
					return res, err
				}
				l.log.Warn("artist art: lookup", "artist", ent.Name, "err", err)
				continue
			}
			// An unusable image is a durable fact about what the provider
			// holds, so it is remembered as a miss rather than refetched.
			if err := validateArtworkBytes(img.Data); err != nil {
				l.log.Warn("artist art: unusable image", "artist", ent.Name, "provider", img.Provider, "err", err)
				l.recordArtistArtMiss(ctx, ent)
				res.Misses++
				continue
			}
			// No pin: the sweep forms no pin intent, so a person can
			// still replace or clear what it stored, and the next pass
			// leaves the replacement alone because the slot resolves.
			if err := l.lib.SetEntityArt(ctx, model.ArtArtist, ent.PID, model.ArtRoleFront, img.Data, waxbin.ArtEditOptions{
				Source: model.SourceEnrichment, Provider: img.Provider, SourceURL: img.SourceURL,
				Format: waxart.NormalizeFormat(img.MIME), Lock: model.LockUnchanged,
			}); err != nil {
				l.log.Warn("artist art: store", "artist", ent.Name, "provider", img.Provider, "err", err)
				continue
			}
			// A stale miss row must not block a refill if this portrait
			// is later cleared.
			if _, had := misses[string(ent.PID)]; had {
				if err := l.db.ClearArtistArtMiss(ctx, string(ent.PID)); err != nil {
					l.log.Warn("artist art: clearing miss row", "artist", ent.Name, "err", err)
				}
			}
			res.Filled++
		}
		if !page.HasMore {
			break
		}
		cursor = page.Next
	}
	// Rows past the retry window are inert (the sweep re-asks and
	// re-records), so pruning them is free hygiene - and what keeps rows
	// for merged-away artists from accumulating forever.
	if _, err := l.db.PruneArtistArtMisses(ctx, time.Now().Add(-artistArtRetryAfter).UnixNano()); err != nil {
		l.log.Warn("artist art: pruning miss memory", "err", err)
	}
	if res.Filled > 0 {
		// Portraits feed generated playlist mosaics through the entity
		// chain, and the epoch is what tells those covers to rebuild.
		l.noteArtworkChanged(ctx)
	}
	return res, nil
}

// recordArtistArtMiss writes the miss row; a failure to remember costs
// one repeat lookup, not the sweep.
func (l *Library) recordArtistArtMiss(ctx context.Context, ent *read.EntityInfo) {
	if err := l.db.RecordArtistArtMiss(ctx, string(ent.PID), ent.MBID, time.Now().UnixNano()); err != nil {
		l.log.Warn("artist art: recording miss", "artist", ent.Name, "err", err)
	}
}
