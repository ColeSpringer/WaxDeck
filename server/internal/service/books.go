package service

import (
	"context"
	"path/filepath"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// BookPart is one backing file in reading order. Index is the join key
// across play-info, skip maps, and download-info.
type BookPart struct {
	Index       int
	StartMS     int64
	DurationMS  int64
	DisplayName string
}

// BookSettings are the caller's per-book playback settings; nil means
// the server default.
type BookSettings struct {
	Speed       *float64
	VoiceBoost  *bool
	TrimSilence *bool
}

// BookDetail is the full audiobook view. Every position is a
// book-timeline millisecond spanning all parts.
type BookDetail struct {
	PID             string
	Title           string
	Subtitle        string
	Authors         []string
	Narrators       []string
	Series          string
	SeriesSequence  string
	Publisher       string
	ASIN            string
	ISBN            string
	Edition         string
	Abridged        *bool
	DescriptionHTML string
	DurationMS      int64
	Chapters        []ChapterMark
	Parts           []BookPart
	Settings        *BookSettings
}

// BookResumePoint is the caller's chapter-aware resume answer.
type BookResumePoint struct {
	PositionMS  int64
	Chapter     *ChapterMark
	UpdatedAtNS int64
}

// BookDetailFor returns one audiobook with the caller's settings.
func (l *Library) BookDetailFor(ctx context.Context, uc *UserCtx, apiBookPID string) (BookDetail, error) {
	bd, err := l.getBookDetail(ctx, uc, apiBookPID)
	if err != nil {
		return BookDetail{}, err
	}
	out := BookDetail{
		PID:             apiPID(PrefixBook, bd.Item.PID),
		Title:           bd.Item.Title,
		Subtitle:        bd.Subtitle,
		Authors:         bd.Authors,
		Narrators:       bd.Narrators,
		Series:          bd.Series,
		SeriesSequence:  bd.SeriesSeq,
		Publisher:       bd.Publisher,
		ASIN:            bd.ASIN,
		ISBN:            bd.ISBN,
		Edition:         bd.Edition,
		Abridged:        bd.Abridged,
		DescriptionHTML: sanitizeShowNotes(bd.Description),
		DurationMS:      bd.TotalDurationMS,
	}
	if out.Authors == nil {
		out.Authors = []string{}
	}
	if out.Narrators == nil {
		out.Narrators = []string{}
	}
	for i, ch := range bd.Chapters {
		out.Chapters = append(out.Chapters, ChapterMark{
			Index: i, Title: ch.Title, StartMS: ch.StartMS, EndMS: ch.EndMS,
		})
	}
	out.Parts = bookParts(bd)
	row, err := l.db.BookSettingsFor(ctx, uc.ID, string(bd.Item.PID))
	if err != nil {
		return BookDetail{}, &Error{Kind: KindInternal, Err: err}
	}
	if row.Speed != nil || row.VoiceBoost != nil || row.TrimSilence != nil {
		bs := bookSettingsDTO(row)
		out.Settings = &bs
	}
	return out, nil
}

// bookParts derives the reading-order part table. A single-file book
// (no upstream parts list) is one part spanning the whole timeline.
func bookParts(bd *model.BookDetail) []BookPart {
	if len(bd.Files) == 0 {
		return []BookPart{{Index: 0, StartMS: 0, DurationMS: bd.TotalDurationMS}}
	}
	parts := make([]BookPart, 0, len(bd.Files))
	var offset int64
	for i, f := range bd.Files {
		parts = append(parts, BookPart{
			Index:       i,
			StartMS:     offset,
			DurationMS:  f.DurationMS,
			DisplayName: filepath.Base(f.DisplayPath),
		})
		offset += f.DurationMS
	}
	return parts
}

// BookResumeFor returns where the caller left off, with the containing
// chapter.
func (l *Library) BookResumeFor(ctx context.Context, uc *UserCtx, apiBookPID string) (BookResumePoint, error) {
	if _, err := l.getBookDetail(ctx, uc, apiBookPID); err != nil {
		return BookResumePoint{}, err
	}
	_, pid, _ := parseAPIPID(apiBookPID)
	st, ch, err := l.lib.BookResume(ctx, model.PID(uc.CatalogPID), pid)
	if err != nil {
		return BookResumePoint{}, classify(err)
	}
	out := BookResumePoint{}
	if st != nil {
		out.PositionMS = st.PositionMS
		out.UpdatedAtNS = st.UpdatedAt
	}
	if ch != nil {
		out.Chapter = &ChapterMark{
			Index: ch.Position, Title: ch.Title, StartMS: ch.StartMS, EndMS: ch.EndMS,
		}
	}
	return out, nil
}

// PutBookSettings fully replaces the caller's settings for one book.
func (l *Library) PutBookSettings(ctx context.Context, uc *UserCtx, apiBookPID string, s BookSettings) (BookSettings, error) {
	bd, err := l.getBookDetail(ctx, uc, apiBookPID)
	if err != nil {
		return BookSettings{}, err
	}
	if s.Speed != nil && (*s.Speed < 0.5 || *s.Speed > 3.5) {
		return BookSettings{}, errInvalid("speed must be between 0.5 and 3.5")
	}
	row := wdb.BookSettings{
		UserID: uc.ID, BookPID: string(bd.Item.PID),
		Speed: s.Speed, VoiceBoost: s.VoiceBoost, TrimSilence: s.TrimSilence,
		UpdatedAtNS: time.Now().UnixNano(),
	}
	if err := l.db.PutBookSettings(ctx, row); err != nil {
		return BookSettings{}, &Error{Kind: KindInternal, Err: err}
	}
	l.emitUserEvent(ctx, uc.ID, eventBookSettings, string(bd.Item.PID))
	return s, nil
}

// getBookDetail resolves an API book PID with the visibility check.
func (l *Library) getBookDetail(ctx context.Context, uc *UserCtx, apiBookPID string) (*model.BookDetail, error) {
	prefix, pid, ok := parseAPIPID(apiBookPID)
	if !ok || prefix != PrefixBook {
		return nil, errNotFound("no book with pid " + apiBookPID)
	}
	bd, err := l.lib.Book(ctx, pid)
	if err != nil {
		return nil, classify(err)
	}
	if !l.itemVisible(ctx, uc, pid) {
		return nil, errNotFound("no book with pid " + apiBookPID)
	}
	return bd, nil
}

func bookSettingsDTO(row wdb.BookSettings) BookSettings {
	return BookSettings{
		Speed:       row.Speed,
		VoiceBoost:  row.VoiceBoost,
		TrimSilence: row.TrimSilence,
	}
}
