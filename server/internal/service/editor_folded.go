package service

import (
	"context"
	"maps"
	"slices"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
)

// maxFoldMembers bounds the members a fold read takes: a write naming
// more answers no folds rather than reading them all.
const maxFoldMembers = 5000

// releasePlaces is where the members of an entity sat before a write that
// can merge: each album and release group with one member on it. The
// engine's report names the survivor of the entity written, not the other
// releases the write dissolved, so they are read around it.
type releasePlaces struct {
	named          model.PID
	albums, groups map[model.PID]model.PID
}

// membersNode selects the entity's members whose release the write can
// move: those it names on a field that keys a release. An artist credited
// only as a contributor (a producer, a composer) keys none, so the albums
// of those credits are never read.
func membersNode(et model.MergeEntity, pid model.PID) query.Node {
	is := func(field string) query.Node {
		return query.Cond{Field: field, Op: query.OpIs, Value: string(pid)}
	}
	switch et {
	case model.MergeArtist:
		return query.Or{Nodes: []query.Node{is("artist_pid"), is("album_artist_pid")}}
	case model.MergeAlbum:
		return is("album_pid")
	case model.MergeReleaseGroup:
		return is("release_group_pid")
	}
	return nil
}

// placesBefore reads where the entity's visible members sit, in one
// read. For a rename those are all of them: the catalog refuses one with
// a member in the trash. An mbid clear repoints trashed members with the
// rest, and a release holding only those is never re-keyed apart from
// its group, so none can fold unseen. Nil where the entity has no
// releases to fold, the read fails, or it names more members than
// maxFoldMembers.
func (l *Editor) placesBefore(ctx context.Context, et model.MergeEntity, pid model.PID) *releasePlaces {
	node := membersNode(et, pid)
	if node == nil {
		return nil
	}
	views, err := l.lib.Query(ctx, visibleItems().WhereNode(node).Limit(maxFoldMembers+1).Build(), "")
	if err != nil {
		l.log.Warn("reading the releases a write may fold", "err", err)
		return nil
	}
	if len(views) > maxFoldMembers {
		return nil
	}
	p := &releasePlaces{
		named:  pid,
		albums: map[model.PID]model.PID{}, groups: map[model.PID]model.PID{},
	}
	for _, v := range views {
		if v.AlbumPID != "" && p.albums[v.AlbumPID] == "" {
			p.albums[v.AlbumPID] = v.PID
		}
		if v.ReleaseGroupPID != "" && p.groups[v.ReleaseGroupPID] == "" {
			p.groups[v.ReleaseGroupPID] = v.PID
		}
	}
	return p
}

// folded reads where one member of each release sits after the write,
// in one read, and answers each album and release group that member left
// whose row is gone with the one it moved to. Whether the row is gone is
// asked of the releases left alone, by pid, which is what their pages
// answer from: a release kept by a trashed item, or by nothing yet
// collected, still answers. The entity the write named is left out: the
// report's survivor answers for it. Nil when a read fails.
func (l *Editor) folded(ctx context.Context, p *releasePlaces) []FoldedDTO {
	if p == nil || (len(p.albums) == 0 && len(p.groups) == 0) {
		return nil
	}
	var members []model.PID
	seen := map[model.PID]bool{}
	for _, m := range [2]map[model.PID]model.PID{p.albums, p.groups} {
		for _, item := range m {
			if !seen[item] {
				seen[item] = true
				members = append(members, item)
			}
		}
	}
	views, err := l.lib.GetMany(ctx, members)
	if err != nil {
		l.log.Warn("reading the releases a write folded", "err", err)
		return nil
	}
	now := make(map[model.PID]*model.ItemView, len(views))
	for _, v := range views {
		now[v.PID] = v
	}
	var out []FoldedDTO
	pairs := func(prefix string, kind read.EntityKind, before map[model.PID]model.PID, at func(*model.ItemView) model.PID) error {
		left := map[model.PID]model.PID{}
		for from, item := range before {
			if v := now[item]; from != p.named && v != nil && at(v) != "" && at(v) != from {
				left[from] = at(v)
			}
		}
		if len(left) == 0 {
			return nil
		}
		still, err := l.lib.EntityByPIDs(ctx, kind, slices.Collect(maps.Keys(left)))
		if err != nil {
			return err
		}
		for _, from := range slices.Sorted(maps.Keys(left)) {
			if still[from] == nil {
				out = append(out, FoldedDTO{PID: apiPID(prefix, from), Into: apiPID(prefix, left[from])})
			}
		}
		return nil
	}
	if err := pairs(PrefixAlbum, read.EntityAlbum, p.albums, func(v *model.ItemView) model.PID { return v.AlbumPID }); err != nil {
		l.log.Warn("reading the releases a write folded", "err", err)
		return nil
	}
	if err := pairs(PrefixReleaseGroup, read.EntityReleaseGroup, p.groups, func(v *model.ItemView) model.PID { return v.ReleaseGroupPID }); err != nil {
		l.log.Warn("reading the releases a write folded", "err", err)
		return nil
	}
	return out
}
