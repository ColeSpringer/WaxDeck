package service

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/read"
	"github.com/oklog/ulid/v2"

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
	SeriesPID       string
	SeriesSequence  string
	Publisher       string
	ASIN            string
	ISBN            string
	Edition         string
	Abridged        *bool
	DescriptionHTML string
	DurationMS      int64
	// ArtSource is where the cover this book answers came from, for the
	// mark under it. Zero when the book has no artwork.
	ArtSource ArtSourceDTO
	Chapters  []ChapterMark
	Parts     []BookPart
	Settings  *BookSettings
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
		SeriesPID:       entityAPIPID(PrefixSeries, bd.SeriesPID),
		SeriesSequence:  bd.SeriesSeq,
		Publisher:       bd.Publisher,
		ASIN:            bd.ASIN,
		ISBN:            bd.ISBN,
		Edition:         bd.Edition,
		Abridged:        bd.Abridged,
		DescriptionHTML: sanitizeShowNotes(bd.Description),
		DurationMS:      bd.TotalDurationMS,
	}
	out.ArtSource = l.artSourceForRef(ctx, model.EntityRef{Type: model.ArtTrack, PID: bd.Item.PID})
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

// Bookmark is one place a listener marked in a book, on the book
// timeline.
type Bookmark struct {
	ID          string
	PositionMS  int64
	Note        string
	CreatedAtNS int64
}

// bookmarkNoteMax bounds a note, matching the contract's maxLength. A
// note is a reminder of what a passage was, not a document.
const bookmarkNoteMax = 500

// BookmarksFor lists the caller's marks in one book, in timeline order.
func (l *Library) BookmarksFor(ctx context.Context, uc *UserCtx, apiBookPID string) ([]Bookmark, error) {
	bd, err := l.getBookDetail(ctx, uc, apiBookPID)
	if err != nil {
		return nil, err
	}
	rows, err := l.db.BookmarksFor(ctx, uc.ID, string(bd.Item.PID))
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	out := make([]Bookmark, 0, len(rows))
	for _, r := range rows {
		out = append(out, Bookmark{
			ID:          apiPID(PrefixBookmark, model.PID(r.ID)),
			PositionMS:  r.PositionMS,
			Note:        r.Note,
			CreatedAtNS: r.CreatedAtNS,
		})
	}
	return out, nil
}

// CreateBookmark records a mark at a book-timeline position.
//
// The position is checked against the book's own length rather than
// taken on trust: a bookmark past the end is one nothing can seek to,
// and the two ways to get one - a stale client and an arithmetic slip
// on a multi-part book - both produce a mark that silently does
// nothing.
func (l *Library) CreateBookmark(ctx context.Context, uc *UserCtx, apiBookPID string, positionMS int64, note string) (Bookmark, error) {
	bd, err := l.getBookDetail(ctx, uc, apiBookPID)
	if err != nil {
		return Bookmark{}, err
	}
	if positionMS < 0 {
		return Bookmark{}, errInvalid("positionMs must not be negative")
	}
	if total := bd.TotalDurationMS; total > 0 && positionMS > total {
		return Bookmark{}, errInvalid("positionMs is past the end of the book")
	}
	note = strings.TrimSpace(note)
	if len([]rune(note)) > bookmarkNoteMax {
		return Bookmark{}, errInvalid("note is too long")
	}
	row := wdb.Bookmark{
		ID:          ulid.Make().String(),
		UserID:      uc.ID,
		BookPID:     string(bd.Item.PID),
		PositionMS:  positionMS,
		Note:        note,
		CreatedAtNS: time.Now().UnixNano(),
	}
	if err := l.db.CreateBookmark(ctx, row); err != nil {
		if errors.Is(err, wdb.ErrConflict) {
			return Bookmark{}, &Error{Kind: KindConflict, Msg: "this book already holds as many bookmarks as it can"}
		}
		return Bookmark{}, &Error{Kind: KindInternal, Err: err}
	}
	return Bookmark{
		ID:          apiPID(PrefixBookmark, model.PID(row.ID)),
		PositionMS:  row.PositionMS,
		Note:        row.Note,
		CreatedAtNS: row.CreatedAtNS,
	}, nil
}

// DeleteBookmark removes one of the caller's marks. Removing one that
// is already gone succeeds, so a retry after a lost answer is not an
// error.
func (l *Library) DeleteBookmark(ctx context.Context, uc *UserCtx, apiBookPID, apiBookmarkID string) error {
	bd, err := l.getBookDetail(ctx, uc, apiBookPID)
	if err != nil {
		return err
	}
	prefix, id, ok := parseAPIPID(apiBookmarkID)
	if !ok || prefix != PrefixBookmark {
		return errNotFound("no bookmark with id " + apiBookmarkID)
	}
	if err := l.db.DeleteBookmark(ctx, uc.ID, string(bd.Item.PID), string(id)); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// getBookDetail resolves an API book PID with the visibility check.
func (l *Library) getBookDetail(ctx context.Context, uc *UserCtx, apiBookPID string) (*model.BookDetail, error) {
	prefix, pid, ok := parseAPIPID(apiBookPID)
	if !ok || prefix != PrefixBook {
		return nil, errNotFound("no book with pid " + apiBookPID)
	}
	bd, err := l.lib.Book(ctx, pid)
	if err != nil {
		// A catalog miss becomes this layer's own sentence rather than
		// the store's. Every other book route constructs that message in
		// its handler and never looks at this one, so the difference has
		// never shown; a handler that answers with the error it was
		// given - which the bookmark delete does, having two things that
		// can be missing - would otherwise put "store.ItemByPID: no such
		// item" on the wire.
		if KindOf(err) == KindNotFound {
			return nil, errNotFound("no book with pid " + apiBookPID)
		}
		return nil, classify(err)
	}
	if !l.itemVisible(ctx, uc, pid) {
		return nil, errNotFound("no book with pid " + apiBookPID)
	}
	return bd, nil
}

// BookSeriesDTO is one audiobook series.
type BookSeriesDTO struct {
	PID             string
	Name            string
	BookCount       int
	TotalDurationMS int64
}

// BookSeriesPageDTO is one keyset page of series.
type BookSeriesPageDTO struct {
	Series     []BookSeriesDTO
	NextCursor string
}

// bookSeriesPageSize bounds one page of the series listing.
const bookSeriesPageSize = 100

// ListBookSeries pages the series the visible books belong to.
//
// The page can come back short, or empty with more to come: upstream
// enumerates and hydrates separately, and this drops what the caller
// cannot see on top of that. So nextCursor follows the page's own
// HasMore rather than whether anything survived the filter, which is
// what keeps a caller draining instead of stopping on a filtered-out
// window.
func (l *Library) ListBookSeries(ctx context.Context, uc *UserCtx, cursor string, limit int) (BookSeriesPageDTO, error) {
	if limit <= 0 || limit > 500 {
		limit = bookSeriesPageSize
	}
	if cursor != "" {
		if _, _, ok := read.Cursor(cursor).Decode(); !ok {
			return BookSeriesPageDTO{}, errInvalid("cursor is malformed")
		}
	}
	page, err := l.lib.EntityPage(ctx, read.EntitySeries, read.Cursor(cursor), limit)
	if err != nil {
		return BookSeriesPageDTO{}, classify(err)
	}
	out := BookSeriesPageDTO{Series: make([]BookSeriesDTO, 0, len(page.Entities))}
	for _, ent := range page.Entities {
		if ent == nil {
			continue
		}
		if !uc.AllLibraries && !l.entityInLibraries(ent, uc) {
			continue
		}
		row := BookSeriesDTO{PID: apiPID(PrefixSeries, ent.PID), Name: ent.Name}
		// The counts are catalog-wide: EntityPage takes no library
		// scope, so a series with one visible book and nine hidden ones
		// would advertise ten to an account that can open one. Answered
		// only where they are true, exactly as the album read does.
		if uc.AllLibraries {
			row.BookCount, row.TotalDurationMS = ent.ItemCount, ent.TotalDurationMS
		}
		out.Series = append(out.Series, row)
	}
	if page.HasMore {
		out.NextCursor = string(page.Next)
	}
	return out, nil
}

func bookSettingsDTO(row wdb.BookSettings) BookSettings {
	return BookSettings{
		Speed:       row.Speed,
		VoiceBoost:  row.VoiceBoost,
		TrimSilence: row.TrimSilence,
	}
}
