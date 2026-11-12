package service

import (
	"context"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
)

// dto converts one catalog playlist for a caller.
// narrow is the caller-scope node for static counts; a loop over many
// rows builds it once with staticMemberNarrow (it costs a subscription
// read), a single conversion passes nil and pays for its own.
func (l *Playlists) dto(ctx context.Context, uc *UserCtx, pl *model.Playlist, withCount bool, narrow query.Node) Playlist {
	out := Playlist{
		PID:        apiPID(PrefixPlaylist, pl.PID),
		Name:       pl.Name,
		Kind:       string(pl.Kind),
		Visibility: string(pl.Visibility),
		OwnerName:  pl.OwnerName,
		IsOwner:    string(pl.OwnerPID) == uc.CatalogPID,
		HasArt:     pl.HasArt,
		CreatedAt:  time.Unix(0, pl.CreatedAt).UTC(),
		UpdatedAt:  time.Unix(0, pl.UpdatedAt).UTC(),
	}
	// The catalog names users by their account id; show the human name.
	if u, err := l.db.UserByID(ctx, pl.OwnerName); err == nil {
		if u.DisplayName != "" {
			out.OwnerName = u.DisplayName
		} else {
			out.OwnerName = u.Username
		}
	}
	if pl.Rule != nil {
		r := queryToRule(*pl.Rule)
		out.Rule = &r
	}
	// Counted off the same membership the listing hands back, for both
	// kinds. The static branch used to report pl.ItemCount, the catalog's
	// stored member count, so a list with one trashed member answered 10
	// here and 9 from /items indefinitely; the smart branch counted the
	// rule but not the caller's own visibility.
	//
	// A static row always counts, live, whether or not the caller asked:
	// membership is a query dimension, so the answer is one indexed
	// COUNT and a listing row can afford the truth. withCount still gates
	// the smart kind, for the reason it always did - evaluating every
	// stored rule to draw a grid of tiles is the work the flag exists to
	// skip - so a smart list still reports no count on a listing, which
	// clients already treat as absent.
	if withCount || pl.Kind == model.PlaylistStatic {
		if n, err := l.visibleMemberCount(ctx, uc, pl, narrow); err == nil {
			out.ItemCount = &n
		} else {
			l.log.Warn("counting playlist members", "playlist", pl.PID, "err", err)
		}
	}
	return out
}
