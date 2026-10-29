package service

// Entity folds: the names a merge, or an entity rename that locks, folded
// into an entity, so a file still spelled that way files under it. They
// are listed for administrators and released by key, all or none.

import (
	"context"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/colespringer/waxbin/identity"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
)

// maxUnfoldKeys is the most fold keys one unfold names, as the API
// bounds them.
const maxUnfoldKeys = 100

// foldTypes are the mergeable entity types in the order the listing
// pages them, which is their API spelling's.
var foldTypes = []model.MergeEntity{
	model.MergeAlbum, model.MergeArtist, model.MergeGenre, model.MergeReleaseGroup, model.MergeSeries,
}

// EntityFoldDTO is one name folded into an entity. EntityType is spelled
// as the duplicates listing spells it, Key is the catalog's own (the
// handle an unfold takes), and EntityPID is the form the app opens.
// Facet, Folder and Library are what tell apart folds that spell alike: a
// genre's facet, an album's folder within the library holding it, read off
// a file of the album that sits in it. CreatedAt still tells apart album
// folds no such file places.
type EntityFoldDTO struct {
	EntityType string
	Key        string
	Spelling   string
	Facet      string
	Folder     string
	Library    string
	EntityPID  string
	EntityName string
	CreatedAt  time.Time
}

// foldReader reads one type's folds, by key.
type foldReader func(context.Context, model.MergeEntity) ([]model.EntityFold, error)

// ListEntityFolds pages every type's folds, by type, then key. A
// non-positive limit lists them all. Administrators only.
func (l *Library) ListEntityFolds(ctx context.Context, uc *UserCtx, cursor string, limit int) ([]EntityFoldDTO, string, error) {
	if !uc.Admin {
		return nil, "", &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	return foldsPage(ctx, l.lib.EntityFolds, l.placeAlbumFolds, cursor, limit)
}

// placer places a page's album folds by key; one it cannot place is absent.
type placer func(context.Context, []model.EntityFold) (map[string]placement, error)

// foldsPage pages the folds read reads and places the album ones with
// place, when given.
func foldsPage(ctx context.Context, read foldReader, place placer, cursor string, limit int) ([]EntityFoldDTO, string, error) {
	page, next, err := foldsAfter(ctx, read, cursor, limit)
	if err != nil {
		return nil, "", err
	}
	var placed map[string]placement
	if place != nil {
		if placed, err = place(ctx, page); err != nil {
			return nil, "", err
		}
	}
	out := make([]EntityFoldDTO, 0, len(page))
	for _, f := range page {
		out = append(out, foldDTO(f, placed))
	}
	return out, next, nil
}

// foldsAfter reads the page after cursor, reading a type only while the
// page has room. A page that fills at the end of a type ends there, its
// cursor naming the next type, so the page after it can be empty.
func foldsAfter(ctx context.Context, read foldReader, cursor string, limit int) ([]model.EntityFold, string, error) {
	afterType, afterKey, ok := decodeFoldCursor(cursor)
	if !ok {
		return nil, "", errInvalid("bad cursor")
	}
	var page []model.EntityFold
	for i, et := range foldTypes {
		entityType := foldEntityType(et)
		if entityType < afterType {
			continue
		}
		folds, err := read(ctx, et)
		if err != nil {
			return nil, "", classify(err)
		}
		for _, f := range folds {
			if entityType == afterType && f.Key <= afterKey {
				continue
			}
			if limit > 0 && len(page) == limit {
				last := page[len(page)-1]
				return page, encodeFoldCursor(foldEntityType(last.EntityType), last.Key), nil
			}
			page = append(page, f)
		}
		if limit > 0 && len(page) == limit && i+1 < len(foldTypes) {
			return page, encodeFoldCursor(foldEntityType(foldTypes[i+1]), ""), nil
		}
	}
	return page, "", nil
}

// UnfoldEntities forgets folds of one entity type, all of them or none:
// a key no fold holds is not found, naming it. Nothing moves: a file
// spelled an unfolded way is filed under its own name once it is added,
// moved, replaced or retagged, and the files the entity holds stay with
// it until they change or move; a rescan, forced or not, leaves an
// unchanged file where it is. Administrators only.
func (l *Library) UnfoldEntities(ctx context.Context, uc *UserCtx, entityType string, keys []string) error {
	if !uc.Admin {
		return &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	et, ok := mergeEntityForType(entityType)
	if !ok {
		return errInvalid("unknown entity type " + entityType)
	}
	if len(keys) == 0 || len(keys) > maxUnfoldKeys {
		return errInvalid("an unfold names 1 to 100 keys")
	}
	if err := l.lib.UnfoldEntity(ctx, et, keys...); err != nil {
		return classify(err)
	}
	l.Audit(ctx, uc, "entity.unfold", AuditTarget{Kind: entityType}, map[string]any{"keys": keys})
	return nil
}

func foldDTO(f model.EntityFold, placed map[string]placement) EntityFoldDTO {
	out := EntityFoldDTO{
		EntityType: foldEntityType(f.EntityType), Key: f.Key, EntityPID: foldEntityPID(f.EntityType, f.EntityPID),
		EntityName: f.EntityName,
	}
	r := readFoldKey(f.EntityType, f.Key)
	out.Spelling, out.Facet = r.spelling, r.facet
	if at, ok := placed[f.Key]; ok {
		out.Folder, out.Library = at.folder, at.library
	}
	if f.CreatedAt > 0 {
		out.CreatedAt = time.Unix(0, f.CreatedAt).UTC()
	}
	return out
}

// A placement is where an album fold's folder sits: the library holding
// it, and the path within that library, empty for its top.
type placement struct{ library, folder string }

// albumPlaces is, for each album, the places each folder key its files
// are in comes from.
type albumPlaces map[model.PID]map[string]map[placement]bool

// at answers the one place an album's folder key comes from. A key no
// file of the album sits under any longer is placed nowhere, and so is
// one two places fold to alike, which the key alone cannot tell apart.
func (p albumPlaces) at(album model.PID, key string) (placement, bool) {
	if places := p[album][key]; len(places) == 1 {
		for at := range places {
			return at, true
		}
	}
	return placement{}, false
}

// folderPlaces reads where the albums' files sit, keyed as an album key
// holds a folder: the match key of the folder the catalog files a file's
// album under (its directory, or the one above a disc folder) within the
// raw root of the library holding it, from which every file path is built.
func folderPlaces(libs []*model.Library, names map[model.PID]string, items []*model.ItemView) albumPlaces {
	roots := make(map[model.PID]string, len(libs))
	for _, lib := range libs {
		roots[lib.PID] = string(lib.Root)
	}
	out := albumPlaces{}
	for _, it := range items {
		root, ok := roots[it.LibraryPID]
		if !ok || len(it.Path) == 0 {
			continue
		}
		dir := identity.AlbumFolder(root, string(it.Path))
		rel, err := filepath.Rel(root, dir)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			continue
		}
		if rel == "." {
			rel = ""
		}
		key := identity.MatchKey(dir)
		if out[it.AlbumPID] == nil {
			out[it.AlbumPID] = map[string]map[placement]bool{}
		}
		if out[it.AlbumPID][key] == nil {
			out[it.AlbumPID][key] = map[placement]bool{}
		}
		out[it.AlbumPID][key][placement{library: names[it.LibraryPID], folder: filepath.ToSlash(rel)}] = true
	}
	return out
}

// placeAlbumFolds places album folds by the files of the albums they
// name: a folder a key holds is one the album's files sit in, and such a
// file, present at the last scan, says which library and where in it.
func (l *Library) placeAlbumFolds(ctx context.Context, folds []model.EntityFold) (map[string]placement, error) {
	var albums []string
	for _, f := range folds {
		if f.EntityType == model.MergeAlbum && readFoldKey(f.EntityType, f.Key).folder != "" &&
			!slices.Contains(albums, string(f.EntityPID)) {
			albums = append(albums, string(f.EntityPID))
		}
	}
	if len(albums) == 0 {
		return nil, nil
	}
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return nil, classify(err)
	}
	names := make(map[model.PID]string, len(libs))
	for _, lib := range libs {
		names[lib.PID] = l.libraryInfo(lib).Name
	}
	var items []*model.ItemView
	for chunk := range slices.Chunk(albums, catalogSetCap) {
		// Present files alone: one missing since the last scan keeps its path.
		got, err := l.lib.Query(ctx, visibleItems().Where("state", query.OpIs, string(model.StatePresent)).
			WhereValues("album_pid", query.OpIn, query.Values(chunk)...).Build(), "")
		if err != nil {
			return nil, classify(err)
		}
		items = append(items, got...)
	}
	places := folderPlaces(libs, names, items)
	out := map[string]placement{}
	for _, f := range folds {
		if f.EntityType != model.MergeAlbum {
			continue
		}
		if at, ok := places.at(f.EntityPID, readFoldKey(f.EntityType, f.Key).folder); ok {
			out[f.Key] = at
		}
	}
	return out, nil
}

// foldEntityType is an entity type in the API's spelling.
func foldEntityType(et model.MergeEntity) string {
	return strings.ReplaceAll(string(et), "_", "-")
}

// foldEntityPID is the pid of the entity a fold names, in the form the
// app opens it by: a genre has no prefix, and its listing takes it bare.
func foldEntityPID(et model.MergeEntity, pid model.PID) string {
	switch et {
	case model.MergeArtist:
		return apiPID(PrefixArtist, pid)
	case model.MergeAlbum:
		return apiPID(PrefixAlbum, pid)
	case model.MergeReleaseGroup:
		return apiPID(PrefixReleaseGroup, pid)
	case model.MergeSeries:
		return apiPID(PrefixSeries, pid)
	default:
		return string(pid)
	}
}

// foldReading is a fold's key as a person reads it, and what tells it
// apart from another fold that reads alike.
type foldReading struct {
	spelling, facet, folder string
}

// readFoldKey reads a fold's key. The key is the catalog's match key: the
// name lower-cased with accents and punctuation folded away, behind a
// prefix naming its kind, except an artist's (a genre's prefix is its
// facet). A release group's holds its artist and title apart, and an
// album's leads with its release group's, then two segments the catalog
// leaves empty (a year and a disc count) and its folder's match key.
func readFoldKey(et model.MergeEntity, key string) foldReading {
	switch et {
	case model.MergeGenre:
		if facet, name, ok := strings.Cut(key, ":"); ok {
			return foldReading{spelling: name, facet: facet}
		}
	case model.MergeSeries:
		return foldReading{spelling: groupSpelling(strings.TrimPrefix(key, "series:"))}
	case model.MergeAlbum:
		if rest, ok := strings.CutPrefix(key, "al:"); ok {
			head := 1
			if strings.HasPrefix(rest, "rg:") {
				head = 2
			}
			if parts := strings.Split(rest, "\x1f"); len(parts) == head+3 {
				return foldReading{spelling: groupSpelling(strings.Join(parts[:head], "\x1f")), folder: parts[head+2]}
			}
		}
	}
	return foldReading{spelling: groupSpelling(key)}
}

// groupSpelling reads a MusicBrainz-keyed fold by its id and a release
// group's by its artist and title; any other key reads as it stands.
func groupSpelling(key string) string {
	if id, ok := strings.CutPrefix(key, "mbid:"); ok {
		return "MusicBrainz " + id
	}
	if rest, ok := strings.CutPrefix(key, "rg:"); ok {
		parts := strings.SplitN(rest, "\x1f", 3)
		named := slices.DeleteFunc(parts[:min(2, len(parts))], func(s string) bool { return s == "" })
		return strings.Join(named, " - ")
	}
	return strings.ReplaceAll(key, "\x1f", " - ")
}

// A fold cursor is the type and key the next page starts after; an empty
// key starts at the type's first fold.
func encodeFoldCursor(entityType, key string) string {
	return encodeOpaqueCursor("f1|" + entityType + "|" + key)
}

// decodeFoldCursor answers where the page after cursor starts; an empty
// cursor starts at the first fold.
func decodeFoldCursor(cursor string) (entityType, key string, ok bool) {
	if cursor == "" {
		return "", "", true
	}
	raw, ok := decodeOpaqueCursor(cursor)
	if !ok {
		return "", "", false
	}
	parts := strings.SplitN(raw, "|", 3)
	if len(parts) != 3 || parts[0] != "f1" {
		return "", "", false
	}
	if _, known := mergeEntityForType(parts[1]); !known {
		return "", "", false
	}
	return parts[1], parts[2], true
}
