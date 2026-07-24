package service

import (
	"context"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
)

// Items pages the whole library (optionally one media type) in stable
// (title, pid) order for the acting user. The cursor is WaxBin's opaque
// keyset token, passed through untouched.
func (l *Library) Items(ctx context.Context, uc *UserCtx, mediaType string, cursor string, limit int) (Page, error) {
	b := query.New(query.EntityItems).OrderBy("title", false)
	if mediaType != "" {
		kind, ok := kindForMediaType(mediaType)
		if !ok {
			return Page{}, errInvalid("unknown mediaType " + mediaType)
		}
		b = b.Where("kind", query.OpIs, string(kind))
	}
	page, err := l.lib.QueryPage(ctx, b.Build(), read.Cursor(cursor), limit, false, model.PID(uc.CatalogPID))
	if err != nil {
		return Page{}, classify(err)
	}
	return l.pageDTO(ctx, uc, page), nil
}

// browseLists maps API discovery-list names onto WaxBin's. The names
// match one-to-one for the lists the API exposes.
var browseLists = map[string]read.DiscoveryList{
	"newest":          read.ListNewest,
	"recently-added":  read.ListRecentlyAdded,
	"most-played":     read.ListMostPlayed,
	"recently-played": read.ListRecentlyPlayed,
	"random":          read.ListRandom,
	"starred":         read.ListStarred,
	"alphabetical":    read.ListAlphabetical,
}

// Browse pages one discovery list; play-derived lists reflect the
// acting user's own state.
func (l *Library) Browse(ctx context.Context, uc *UserCtx, list string, seed int64, cursor string, limit int) (Page, error) {
	dl, ok := browseLists[list]
	if !ok {
		return Page{}, errInvalid("unknown list " + list)
	}
	page, err := l.lib.Browse(ctx, dl, read.BrowseOptions{
		UserPID: model.PID(uc.CatalogPID),
		Seed:    seed,
		Cursor:  read.Cursor(cursor),
		Limit:   limit,
	})
	if err != nil {
		return Page{}, classify(err)
	}
	return l.pageDTO(ctx, uc, page), nil
}

// pageDTO converts a catalog page, dropping items outside the caller's
// visible libraries and podcast episodes of shows the caller does not
// subscribe to (subscriptions are per-user views; unsubscribing removes
// a show's episodes from your listings while the catalog keeps
// everything). Restricted callers may get short pages that still carry
// a cursor; the contract documents that.
func (l *Library) pageDTO(ctx context.Context, uc *UserCtx, p *read.Page) Page {
	subs := l.newSubscriptionFilter(uc)
	out := Page{Items: make([]ItemSummary, 0, len(p.Items))}
	for _, it := range p.Items {
		if !uc.AllLibraries && !l.itemVisible(ctx, uc, it.PID) {
			continue
		}
		if !subs.allowsItem(ctx, l, it) {
			continue
		}
		if !l.allowedByContent(ctx, uc, it) {
			continue
		}
		out.Items = append(out.Items, summary(it))
	}
	if p.HasMore {
		out.Next = string(p.Next)
	}
	return out
}

// searchMaxCandidates bounds how many full-text matches are ranked
// before the per-group limit is applied. A common term on a large corpus
// can match most of it, and ranking every match is the hundreds-of-
// milliseconds worst case the cap exists to avoid; the newest matches win
// the pool and SearchResults.Truncated reports when it filled.
const searchMaxCandidates = 5000

// Search runs grouped full-text search. Restricted callers get item
// hits filtered by library visibility, and artist and album groups
// filtered by entity library attribution: an entity survives when one
// of the libraries holding its members is granted to the caller.
func (l *Library) Search(ctx context.Context, uc *UserCtx, q string, limit int) (SearchResults, error) {
	// A restricted caller with no granted libraries can see nothing: every
	// item hit fails the visibility check below and entity groups are
	// omitted, so skip the FTS ranking entirely rather than rank a whole
	// corpus and then discard all of it.
	if !uc.AllLibraries && len(uc.Libraries) == 0 {
		return SearchResults{Query: q}, nil
	}
	opts := read.SearchOptions{Limit: limit, MaxCandidates: searchMaxCandidates}
	// A restricted caller's item hits are filtered by library visibility
	// below; scoping the FTS pool to the same libraries up front shrinks
	// the worst-case ranking set and drops fileless items, which fail
	// closed for these callers anyway. Full-visibility callers scan
	// unscoped. An empty grant leaves the scope open and the post-filter
	// drops everything, the same empty answer a scoped scan would give.
	if !uc.AllLibraries && len(uc.Libraries) > 0 {
		opts.Libraries = make([]model.PID, 0, len(uc.Libraries))
		for lib := range uc.Libraries {
			opts.Libraries = append(opts.Libraries, model.PID(lib))
		}
	}
	res, err := l.lib.Search(ctx, q, opts)
	if err != nil {
		return SearchResults{}, classify(err)
	}
	convEntity := func(hits []read.SearchHit, prefix string, kind read.EntityKind) ([]SearchHit, error) {
		// Entities carry no stored library column, so a restricted caller's
		// hits are attributed through the libraries holding their member
		// items, in one batched lookup per kind. Full-visibility callers
		// see every entity and skip it entirely.
		var infos map[model.PID]*read.EntityInfo
		if !uc.AllLibraries && len(hits) > 0 {
			pids := make([]model.PID, 0, len(hits))
			for _, h := range hits {
				pids = append(pids, h.PID)
			}
			var err error
			if infos, err = l.lib.EntityByPIDs(ctx, kind, pids); err != nil {
				// The batch is the gate, so a failure can neither hand the
				// caller entities it may not see nor pass as an honest
				// empty group: it fails the search.
				return nil, classify(err)
			}
		}
		out := make([]SearchHit, 0, len(hits))
		for _, h := range hits {
			if !uc.AllLibraries && !l.entityInLibraries(infos[h.PID], uc) {
				continue
			}
			out = append(out, SearchHit{
				PID:      apiPID(prefix, h.PID),
				Kind:     h.Kind,
				Title:    h.Title,
				Subtitle: h.Subtitle,
			})
		}
		return out, nil
	}
	subs := l.newSubscriptionFilter(uc)
	convItem := func(hits []read.SearchHit, prefix string) []SearchHit {
		out := make([]SearchHit, 0, len(hits))
		for _, h := range hits {
			if !uc.AllLibraries && !l.itemVisible(ctx, uc, h.PID) {
				continue
			}
			// Episode hits (title and transcript matches alike) scope to
			// the caller's subscriptions, like every list surface.
			if prefix == PrefixEpisode && !subs.allowsEpisode(ctx, l, h.PID) {
				continue
			}
			if !l.contentAllowsPID(ctx, uc, h.PID) {
				continue
			}
			out = append(out, SearchHit{
				PID:      apiPID(prefix, h.PID),
				Kind:     h.Kind,
				Title:    h.Title,
				Subtitle: h.Subtitle,
			})
		}
		return out
	}
	artists, err := convEntity(res.Artists, PrefixArtist, read.EntityArtist)
	if err != nil {
		return SearchResults{}, err
	}
	albums, err := convEntity(res.Albums, PrefixAlbum, read.EntityAlbum)
	if err != nil {
		return SearchResults{}, err
	}
	return SearchResults{
		Query:     res.Query,
		Artists:   artists,
		Albums:    albums,
		Tracks:    convItem(res.Tracks, PrefixTrack),
		Books:     convItem(res.Books, PrefixBook),
		Episodes:  convItem(res.Episodes, PrefixEpisode),
		Truncated: res.Truncated,
	}, nil
}

// EntityNames resolves the catalog's display name for a batch of API
// entity pids, keyed by the pid passed in. Every pid must share one
// prefix (the catalog batches within a kind); unknown or unparseable
// pids are omitted rather than erroring, so a caller hydrating labels
// falls back to whatever it already had.
//
// This is the compatibility surface's naming primitive: once a group is
// keyed on an entity rather than on a display string, the label has to
// come from the entity too.
func (l *Library) EntityNames(ctx context.Context, apiPIDs []string) (map[string]string, error) {
	if len(apiPIDs) == 0 {
		return nil, nil
	}
	prefix, _, ok := parseAPIPID(apiPIDs[0])
	if !ok {
		return nil, errInvalid("malformed entity pid " + apiPIDs[0])
	}
	kind, ok := entityKindForPrefix(prefix)
	if !ok {
		return nil, errInvalid("no entity kind for pid " + apiPIDs[0])
	}
	pids := make([]model.PID, 0, len(apiPIDs))
	back := make(map[model.PID]string, len(apiPIDs))
	for _, api := range apiPIDs {
		p, pid, ok := parseAPIPID(api)
		if !ok || p != prefix {
			continue
		}
		pids = append(pids, pid)
		back[pid] = api
	}
	infos, err := l.lib.EntityByPIDs(ctx, kind, pids)
	if err != nil {
		return nil, classify(err)
	}
	out := make(map[string]string, len(infos))
	for pid, info := range infos {
		if info != nil && info.Name != "" {
			out[back[pid]] = info.Name
		}
	}
	return out, nil
}

// entityInLibraries reports whether any library holding the entity's
// members is in the caller's grant. Full-visibility callers never reach
// this (they see every entity). A nil info (which the facade never
// returns alongside a nil error, but the helper stays robust to)
// attributes to no library and reads as not visible.
func (l *Library) entityInLibraries(info *read.EntityInfo, uc *UserCtx) bool {
	if info == nil {
		return false
	}
	for _, lib := range info.LibraryPIDs {
		if uc.Libraries[string(lib)] {
			return true
		}
	}
	return false
}

// Item returns full detail for one item.
func (l *Library) Item(ctx context.Context, uc *UserCtx, apiItemPID string) (ItemDetail, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return ItemDetail{}, err
	}
	d := ItemDetail{
		ItemSummary: summary(it),
		Year:        it.Year,
		TrackNo:     it.TrackNo,
		DiscNo:      it.DiscNo,
		Codec:       it.Codec,
		Container:   it.Container,
		SampleRate:  it.SampleRate,
	}
	if it.Genre != "" {
		d.Genres = []string{it.Genre}
	}
	// Bitrate lives on the file row; a miss is fine (remote/missing items).
	if f, err := l.lib.File(ctx, it.FilePID); err == nil {
		d.Bitrate = f.Bitrate
		d.AddedAt = time.Unix(0, f.FirstSeen).UTC()
	}
	return d, nil
}

// artMimes maps the catalog's stored art formats to media types. An
// unknown format falls back to jpeg, the dominant case.
var artMimes = map[string]string{
	"jpeg": "image/jpeg",
	"jpg":  "image/jpeg",
	"png":  "image/png",
	"webp": "image/webp",
	"gif":  "image/gif",
}

// Art resolves artwork: original when size is 0, square-fit thumbnail
// otherwise. Besides item PIDs it accepts album and artist PIDs, so
// search hits render artwork without a second identifier scheme.
// Item artwork honors library visibility; album and artist artwork is
// served without an attribution check (entities span libraries and
// PIDs are unguessable ULIDs; restricted users never discover them
// through listings, which are filtered).
func (l *Library) Art(ctx context.Context, uc *UserCtx, apiPID, role string, size int) (ArtBlob, error) {
	art, ok := model.ParseArtRole(role)
	if !ok {
		return ArtBlob{}, errInvalid("unknown art role " + role)
	}
	ref, err := l.artRef(ctx, uc, apiPID)
	if err != nil {
		return ArtBlob{}, err
	}
	blob, err := l.lib.ResolveArt(ctx, ref, art, size)
	if err != nil {
		return ArtBlob{}, classify(err)
	}
	mime := artMimes[strings.TrimPrefix(blob.Format, "image/")]
	if mime == "" {
		mime = "image/jpeg"
	}
	return ArtBlob{Bytes: blob.Bytes, MimeType: mime, SourceHash: blob.SourceHash}, nil
}

// artRef resolves an art read/roles pid to its entity ref. Item PIDs honor
// library visibility; album, artist, and podcast-show PIDs resolve without an
// attribution check (entities span libraries, their PIDs are unguessable
// ULIDs, and restricted users never surface them through filtered listings).
func (l *Library) artRef(ctx context.Context, uc *UserCtx, apiPID string) (model.EntityRef, error) {
	prefix, pid, ok := parseAPIPID(apiPID)
	if !ok {
		return model.EntityRef{}, errNotFound("no artwork for pid " + apiPID)
	}
	switch {
	case prefix == PrefixAlbum:
		return model.EntityRef{Type: model.ArtAlbum, PID: pid}, nil
	case prefix == PrefixArtist:
		return model.EntityRef{Type: model.ArtArtist, PID: pid}, nil
	case prefix == PrefixPodcast:
		// A podcast show is not a catalog item, so it resolves to its own art
		// level directly (its feed image), like album and artist entities.
		return model.EntityRef{Type: model.ArtPodcast, PID: pid}, nil
	case prefix == PrefixPlaylist:
		// Unlike the entity cases above, a playlist goes through its
		// visibility check. Those skip attribution because entity pids are
		// unguessable and never surface through a filtered listing; a
		// playlist has explicit user-facing visibility, and resolvePlaylist
		// is the same owner-or-shared gate every other playlist read uses.
		pl, err := l.resolvePlaylist(ctx, uc, apiPID)
		if err != nil {
			return model.EntityRef{}, err
		}
		return model.EntityRef{Type: model.ArtPlaylist, PID: pl.PID}, nil
	case itemPrefix(prefix):
		it, err := l.getVisibleItem(ctx, uc, apiPID)
		if err != nil {
			return model.EntityRef{}, err
		}
		entity := model.ArtTrack
		if it.Kind == model.KindEpisode {
			entity = model.ArtEpisode
		}
		return model.EntityRef{Type: entity, PID: it.PID}, nil
	default:
		return model.EntityRef{}, errNotFound("no artwork for pid " + apiPID)
	}
}

// ArtRoleInfoDTO is one artwork slot an entity holds at its own level.
type ArtRoleInfoDTO struct {
	Role   string
	Format string
	Width  int
	Height int
}

// ItemArtRoles lists the artwork slots an entity holds at its own level
// (not inherited from the album/artist chain), the own-versus-inherited
// signal the front-cover read cannot give. Accepts item, album, and artist
// PIDs like Art.
func (l *Library) ItemArtRoles(ctx context.Context, uc *UserCtx, apiPID string) ([]ArtRoleInfoDTO, error) {
	ref, err := l.artRef(ctx, uc, apiPID)
	if err != nil {
		return nil, err
	}
	infos, err := l.lib.ArtRoles(ctx, ref)
	if err != nil {
		return nil, classify(err)
	}
	out := make([]ArtRoleInfoDTO, 0, len(infos))
	for _, i := range infos {
		out = append(out, ArtRoleInfoDTO{
			Role:   string(i.Role),
			Format: i.Format,
			Width:  i.Width,
			Height: i.Height,
		})
	}
	return out, nil
}

// ItemLyrics returns the item's lyrics; not-found when it has none.
func (l *Library) ItemLyrics(ctx context.Context, uc *UserCtx, apiItemPID string) (Lyrics, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return Lyrics{}, err
	}
	ly, err := l.lib.Lyrics(ctx, it.PID)
	if err != nil {
		return Lyrics{}, classify(err)
	}
	out := Lyrics{PID: apiItemPID, Source: ly.Source, Unsynced: ly.Unsynced}
	for _, line := range ly.Synced {
		out.Synced = append(out.Synced, SyncedLine{TimeMS: line.TimeMS, Text: line.Text})
	}
	return out, nil
}
