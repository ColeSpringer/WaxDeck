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
// (title, pid) order. The cursor is WaxBin's opaque keyset token,
// passed through untouched.
func (l *Library) Items(ctx context.Context, mediaType string, cursor string, limit int) (Page, error) {
	b := query.New(query.EntityItems).OrderBy("title", false)
	if mediaType != "" {
		kind, ok := kindForMediaType(mediaType)
		if !ok {
			return Page{}, errInvalid("unknown mediaType " + mediaType)
		}
		b = b.Where("kind", query.OpIs, string(kind))
	}
	page, err := l.lib.QueryPage(ctx, b.Build(), read.Cursor(cursor), limit, false, "")
	if err != nil {
		return Page{}, classify(err)
	}
	return pageDTO(page), nil
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

// Browse pages one discovery list. Play-derived lists use the default
// user until real accounts land.
func (l *Library) Browse(ctx context.Context, list string, seed int64, cursor string, limit int) (Page, error) {
	dl, ok := browseLists[list]
	if !ok {
		return Page{}, errInvalid("unknown list " + list)
	}
	page, err := l.lib.Browse(ctx, dl, read.BrowseOptions{
		Seed:   seed,
		Cursor: read.Cursor(cursor),
		Limit:  limit,
	})
	if err != nil {
		return Page{}, classify(err)
	}
	return pageDTO(page), nil
}

func pageDTO(p *read.Page) Page {
	out := Page{Items: make([]ItemSummary, 0, len(p.Items))}
	for _, it := range p.Items {
		out.Items = append(out.Items, summary(it))
	}
	if p.HasMore {
		out.Next = string(p.Next)
	}
	return out
}

// Search runs grouped full-text search.
func (l *Library) Search(ctx context.Context, q string, limit int) (SearchResults, error) {
	res, err := l.lib.Search(ctx, q, read.SearchOptions{Limit: limit})
	if err != nil {
		return SearchResults{}, classify(err)
	}
	conv := func(hits []read.SearchHit, prefix string) []SearchHit {
		out := make([]SearchHit, 0, len(hits))
		for _, h := range hits {
			out = append(out, SearchHit{
				PID:      apiPID(prefix, h.PID),
				Kind:     h.Kind,
				Title:    h.Title,
				Subtitle: h.Subtitle,
			})
		}
		return out
	}
	return SearchResults{
		Query:     res.Query,
		Artists:   conv(res.Artists, PrefixArtist),
		Albums:    conv(res.Albums, PrefixAlbum),
		Tracks:    conv(res.Tracks, PrefixTrack),
		Books:     conv(res.Books, PrefixBook),
		Episodes:  conv(res.Episodes, PrefixEpisode),
		Truncated: res.Truncated,
	}, nil
}

// Item returns full detail for one item.
func (l *Library) Item(ctx context.Context, apiItemPID string) (ItemDetail, error) {
	it, err := l.getItem(ctx, apiItemPID)
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
func (l *Library) Art(ctx context.Context, apiPID string, size int) (ArtBlob, error) {
	prefix, pid, ok := parseAPIPID(apiPID)
	if !ok {
		return ArtBlob{}, errNotFound("no artwork for pid " + apiPID)
	}
	var ref model.EntityRef
	switch {
	case prefix == PrefixAlbum:
		ref = model.EntityRef{Type: model.ArtAlbum, PID: pid}
	case prefix == PrefixArtist:
		ref = model.EntityRef{Type: model.ArtArtist, PID: pid}
	case itemPrefix(prefix):
		it, err := l.getItem(ctx, apiPID)
		if err != nil {
			return ArtBlob{}, err
		}
		entity := model.ArtTrack
		if it.Kind == model.KindEpisode {
			entity = model.ArtEpisode
		}
		ref = model.EntityRef{Type: entity, PID: it.PID}
	default:
		return ArtBlob{}, errNotFound("no artwork for pid " + apiPID)
	}
	blob, err := l.lib.ResolveArt(ctx, ref, size)
	if err != nil {
		return ArtBlob{}, classify(err)
	}
	mime := artMimes[strings.TrimPrefix(blob.Format, "image/")]
	if mime == "" {
		mime = "image/jpeg"
	}
	return ArtBlob{Bytes: blob.Bytes, MimeType: mime, SourceHash: blob.SourceHash}, nil
}

// ItemLyrics returns the item's lyrics; not-found when it has none.
func (l *Library) ItemLyrics(ctx context.Context, apiItemPID string) (Lyrics, error) {
	it, err := l.getItem(ctx, apiItemPID)
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
