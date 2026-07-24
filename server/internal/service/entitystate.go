package service

import (
	"context"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/read"
)

// Per-user stars and ratings scoped to a catalog entity: the artist and
// album twin of the item playback surface in playback.go. An entity
// star is its own fact, not a rollup of its members: starring an album
// does not star its tracks, and a client that wants both writes both.
//
// The catalog orders these writes by recorded time exactly as it orders
// item writes, so the replay handling here is the same asOfNS
// projection and nothing more.

// EntityPlayState is the calling user's star and rating for one catalog
// entity. Entities carry no resume position or play count of their own;
// their items keep those.
type EntityPlayState struct {
	PID       string
	Starred   bool
	StarredAt time.Time
	Rating    *int
	UpdatedAt time.Time
}

// StarredEntities is the caller's starred entities grouped by kind,
// most recently starred first within each group.
type StarredEntities struct {
	Artists []SearchHit
	Albums  []SearchHit
}

// mergeEntityForPrefix maps an API entity prefix to the catalog's merge
// entity, which is what the star and rating writes are scoped by.
func mergeEntityForPrefix(prefix string) (model.MergeEntity, bool) {
	switch prefix {
	case PrefixArtist:
		return model.MergeArtist, true
	case PrefixAlbum:
		return model.MergeAlbum, true
	default:
		return "", false
	}
}

// resolveEntity splits an API entity pid and authorizes the caller for
// it. Restricted callers are gated exactly as entity search hits are:
// an entity is visible when a library holding one of its member items
// is granted. A pid naming no entity is a plain not-found, so probing
// cannot distinguish "no such entity" from "not yours".
func (l *Library) resolveEntity(ctx context.Context, uc *UserCtx, apiEntityPID string) (model.MergeEntity, model.PID, error) {
	prefix, pid, ok := parseAPIPID(apiEntityPID)
	if !ok {
		return "", "", errNotFound("no such entity " + apiEntityPID)
	}
	kind, ok := mergeEntityForPrefix(prefix)
	if !ok {
		return "", "", errNotFound("no such entity " + apiEntityPID)
	}
	if uc.AllLibraries {
		return kind, pid, nil
	}
	readKind, ok := entityKindForPrefix(prefix)
	if !ok {
		return "", "", errNotFound("no such entity " + apiEntityPID)
	}
	info, err := l.lib.EntityByPID(ctx, readKind, pid)
	if err != nil {
		// Only the lookup's own verdict is a not-found. Folding a real
		// failure in here would answer "no such entity" while the
		// catalog is suspended for maintenance, where the caller needs
		// the retry-shortly the maintenance kind renders.
		return "", "", classify(err)
	}
	if !l.entityInLibraries(info, uc) {
		return "", "", errNotFound("no such entity " + apiEntityPID)
	}
	return kind, pid, nil
}

// entityPlayStateDTO projects a catalog entity state onto the API DTO.
// A nil state (the user has never touched the entity) yields the zero
// state, which is what an unstarred, unrated entity is.
func entityPlayStateDTO(apiEntityPID string, st *model.EntityPlayState) EntityPlayState {
	out := EntityPlayState{PID: apiEntityPID}
	if st == nil {
		return out
	}
	out.Starred = st.Starred
	if st.HasRating {
		r := st.Rating
		out.Rating = &r
	}
	if st.StarredAt > 0 {
		out.StarredAt = time.Unix(0, st.StarredAt).UTC()
	}
	if st.UpdatedAt > 0 {
		out.UpdatedAt = time.Unix(0, st.UpdatedAt).UTC()
	}
	return out
}

// EntityPlayStateFor returns the caller's star and rating for one
// artist or album. An entity never starred or rated reads back zero.
func (l *Library) EntityPlayStateFor(ctx context.Context, uc *UserCtx, apiEntityPID string) (EntityPlayState, error) {
	kind, pid, err := l.resolveEntity(ctx, uc, apiEntityPID)
	if err != nil {
		return EntityPlayState{}, err
	}
	return l.entityStateFor(ctx, uc, apiEntityPID, kind, pid)
}

// entityStateFor reads the state for an already-authorized entity.
func (l *Library) entityStateFor(ctx context.Context, uc *UserCtx, apiEntityPID string, kind model.MergeEntity, pid model.PID) (EntityPlayState, error) {
	st, err := l.lib.EntityPlayState(ctx, model.PID(uc.CatalogPID), kind, pid)
	if err != nil {
		return EntityPlayState{}, classify(err)
	}
	return entityPlayStateDTO(apiEntityPID, st), nil
}

// SetEntityStar stars or unstars an artist or album for the acting user
// and returns the resulting state. A replayed offline toggle carries its
// recorded time to the catalog, which drops it when the star changed
// more recently; see SetStar.
func (l *Library) SetEntityStar(ctx context.Context, uc *UserCtx, apiEntityPID string, starred bool, recordedAt *time.Time) (EntityPlayState, error) {
	kind, pid, err := l.resolveEntity(ctx, uc, apiEntityPID)
	if err != nil {
		return EntityPlayState{}, err
	}
	if err := l.lib.SetEntityStar(ctx, model.PID(uc.CatalogPID), kind, pid, starred, asOfNS(recordedAt)); err != nil {
		return EntityPlayState{}, classify(err)
	}
	l.emitUserEvent(ctx, uc.ID, eventEntityState, apiEntityPID)
	return l.entityStateFor(ctx, uc, apiEntityPID, kind, pid)
}

// SetEntityRating sets (0..100) or clears (nil) the acting user's
// rating for an artist or album and returns the resulting state.
func (l *Library) SetEntityRating(ctx context.Context, uc *UserCtx, apiEntityPID string, rating *int, recordedAt *time.Time) (EntityPlayState, error) {
	if rating != nil && (*rating < 0 || *rating > 100) {
		return EntityPlayState{}, errInvalid("rating must be between 0 and 100")
	}
	kind, pid, err := l.resolveEntity(ctx, uc, apiEntityPID)
	if err != nil {
		return EntityPlayState{}, err
	}
	if err := l.lib.SetEntityRating(ctx, model.PID(uc.CatalogPID), kind, pid, rating, asOfNS(recordedAt)); err != nil {
		return EntityPlayState{}, classify(err)
	}
	l.emitUserEvent(ctx, uc.ID, eventEntityState, apiEntityPID)
	return l.entityStateFor(ctx, uc, apiEntityPID, kind, pid)
}

// StarredEntities lists the caller's starred artists and albums, most
// recently starred first within each group. Names are hydrated in one
// batch per kind, which doubles as the visibility filter for restricted
// callers: an entity whose members all sit outside the caller's grant
// is dropped rather than handed out as a pid they cannot follow.
func (l *Library) StarredEntities(ctx context.Context, uc *UserCtx) (StarredEntities, error) {
	out := StarredEntities{Artists: []SearchHit{}, Albums: []SearchHit{}}
	kinds := []struct {
		merge  model.MergeEntity
		read   read.EntityKind
		prefix string
		hits   *[]SearchHit
	}{
		{model.MergeArtist, read.EntityArtist, PrefixArtist, &out.Artists},
		{model.MergeAlbum, read.EntityAlbum, PrefixAlbum, &out.Albums},
	}
	for _, k := range kinds {
		states, err := l.lib.StarredEntities(ctx, model.PID(uc.CatalogPID), k.merge)
		if err != nil {
			return StarredEntities{}, classify(err)
		}
		if len(states) == 0 {
			continue
		}
		pids := make([]model.PID, 0, len(states))
		for _, st := range states {
			pids = append(pids, st.EntityPID)
		}
		infos, err := l.lib.EntityByPIDs(ctx, k.read, pids)
		if err != nil {
			return StarredEntities{}, classify(err)
		}
		for _, st := range states {
			info := infos[st.EntityPID]
			if info == nil {
				// The entity went away between the two reads.
				continue
			}
			if !uc.AllLibraries && !l.entityInLibraries(info, uc) {
				continue
			}
			*k.hits = append(*k.hits, SearchHit{
				PID:   apiPID(k.prefix, st.EntityPID),
				Kind:  string(k.read),
				Title: info.Name,
			})
		}
	}
	return out, nil
}
