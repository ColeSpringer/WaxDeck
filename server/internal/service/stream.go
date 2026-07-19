package service

import (
	"context"
	"errors"

	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// StreamSource resolves an API item PID to everything the WaxFlow
// bridge needs: the backing file's path and identity pin, the
// virtual-track window when the item is a CUE-backed span, the source
// codec facts the format policy reads, and the spoken-word loudness
// facts voice boost derives its gain from. It re-resolves on every
// call, which is what makes organize-moves invisible to streaming.
// filePID selects one part of a multi-file book; empty means the
// item's own backing file.
func (l *Library) StreamSource(ctx context.Context, apiItemPID, filePID string) (flow.Source, error) {
	it, err := l.getItem(ctx, apiItemPID)
	if err != nil {
		return flow.Source{}, err
	}

	// A podcast episode without its audio cannot stream; the typed
	// conflict tells clients to queue a fetch and retry.
	if it.Kind == model.KindEpisode && it.State != model.StatePresent {
		return flow.Source{}, &Error{Kind: KindConflict,
			Msg: "episode audio is not fetched to the server yet; queue it with the fetch endpoint"}
	}

	src := flow.Source{
		Codec:      it.Codec,
		Container:  it.Container,
		DurationMS: it.DurationMS,
		SpokenWord: it.Kind == model.KindEpisode || it.Kind == model.KindBook,
	}

	var f *model.File
	if it.Kind == model.KindBook && filePID != "" {
		// Multi-file books stream one named part; the part must belong
		// to this book or the request resolves nothing.
		bd, err := l.lib.Book(ctx, it.PID)
		if err != nil {
			return flow.Source{}, classify(err)
		}
		part, ok := bookPartByFile(bd, filePID)
		if !ok {
			return flow.Source{}, errNotFound("no such part for book " + apiItemPID)
		}
		f, err = l.fileByPID(ctx, model.PID(filePID))
		if err != nil {
			return flow.Source{}, err
		}
		src.Path = string(f.Path)
		src.DurationMS = part.DurationMS
	} else {
		loc, err := l.paths.Locate(ctx, it.PID)
		if err != nil {
			return flow.Source{}, classify(err)
		}
		from, to, err := loc.Span()
		if err != nil {
			return flow.Source{}, classify(err)
		}
		src.Path = loc.Path
		src.Virtual = loc.Virtual
		src.FromSample = from
		src.ToSample = to
		f, err = l.fileByPID(ctx, loc.FilePID)
		if err != nil {
			return flow.Source{}, err
		}
	}
	src.Size = f.Size
	src.MTimeNS = f.MTimeNS

	if src.SpokenWord && f.EssenceHash != "" {
		if m, err := l.db.SilenceMapFor(ctx, f.EssenceHash); err == nil {
			src.IntegratedLUFS = m.IntegratedLUFS
		} else if !errors.Is(err, wdb.ErrNotFound) {
			l.log.Warn("reading loudness cache", "err", err)
		}
	}
	return src, nil
}

// fileByPID reads one file row, classified.
func (l *Library) fileByPID(ctx context.Context, pid model.PID) (*model.File, error) {
	f, err := l.lib.File(ctx, pid)
	if err != nil {
		return nil, classify(err)
	}
	return f, nil
}

// bookPartByFile finds a book's part by backing file PID.
func bookPartByFile(bd *model.BookDetail, filePID string) (model.BookPart, bool) {
	for _, p := range bd.Files {
		if string(p.FilePID) == filePID {
			return p, true
		}
	}
	return model.BookPart{}, false
}

// PlayPart is play-info's part resolution for multi-file books.
type PlayPart struct {
	FilePID   string
	Index     int
	Count     int
	StartMS   int64
	MultiPart bool
}

// ResolvePlayPart maps a book-timeline position to the backing part.
// Single-file items (and every non-book) resolve to a zero PlayPart
// with MultiPart false.
func (l *Library) ResolvePlayPart(ctx context.Context, uc *UserCtx, apiItemPID string, positionMS int64) (PlayPart, error) {
	prefix, pid, ok := parseAPIPID(apiItemPID)
	if !ok || prefix != PrefixBook {
		return PlayPart{}, nil
	}
	bd, err := l.lib.Book(ctx, pid)
	if err != nil {
		// Not a resolvable book (or not a book at all): stream the item
		// as itself.
		return PlayPart{}, nil
	}
	if len(bd.Files) < 2 {
		return PlayPart{}, nil
	}
	// The part whose half-open window holds the position; anything at
	// or past the end resolves to the last part.
	var offset int64
	chosen := -1
	var chosenStart int64
	for i, part := range bd.Files {
		if positionMS < offset+part.DurationMS {
			chosen = i
			chosenStart = offset
			break
		}
		offset += part.DurationMS
	}
	if chosen < 0 {
		chosen = len(bd.Files) - 1
		chosenStart = offset - bd.Files[chosen].DurationMS
	}
	return PlayPart{
		FilePID:   string(bd.Files[chosen].FilePID),
		Index:     chosen,
		Count:     len(bd.Files),
		StartMS:   chosenStart,
		MultiPart: true,
	}, nil
}

// EffectiveVoiceBoost resolves the caller's stored voice-boost setting
// for an item: the subscription setting for a podcast episode, the
// book settings for an audiobook, false elsewhere.
func (l *Library) EffectiveVoiceBoost(ctx context.Context, uc *UserCtx, apiItemPID string) bool {
	prefix, pid, ok := parseAPIPID(apiItemPID)
	if !ok {
		return false
	}
	switch prefix {
	case PrefixEpisode:
		det, err := l.lib.Podcasts().Episode(ctx, pid)
		if err != nil {
			return false
		}
		sub, err := l.db.SubscriptionFor(ctx, uc.ID, string(det.Episode.PodcastPID))
		if err != nil {
			return false
		}
		return sub.VoiceBoost != nil && *sub.VoiceBoost
	case PrefixBook:
		bs, err := l.db.BookSettingsFor(ctx, uc.ID, string(pid))
		if err != nil {
			return false
		}
		return bs.VoiceBoost != nil && *bs.VoiceBoost
	}
	return false
}
