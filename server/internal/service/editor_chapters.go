package service

import (
	"context"

	"github.com/colespringer/waxbin/model"
)

// SetBookChapters replaces an audiobook's chapter list; an empty list
// restores the embedded chapters. Chapters are addressed on the book
// timeline (StartMS/EndMS spanning all parts, symmetric with the read);
// the facade splits them across a multi-file book's parts internally, so
// the same flat list works for single- and multi-file books alike.
func (l *Editor) SetBookChapters(ctx context.Context, uc *UserCtx, apiPID string, chapters []ChapterMark, lock, force bool) (EditOutcomeDTO, error) {
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		if KindOf(err) == KindNotFound {
			return EditOutcomeDTO{}, errNotFound("no book with pid " + apiPID)
		}
		return EditOutcomeDTO{}, err
	}
	if it.Kind != model.KindBook {
		return EditOutcomeDTO{}, errInvalid("chapters are only editable on audiobooks")
	}
	if err := validateChapterList(chapters); err != nil {
		return EditOutcomeDTO{}, err
	}
	// Book-timeline offsets go to the facade, which resolves each chapter
	// to the part that backs it and stores per-part file offsets. An edit
	// arrives on the timeline the marks were read on (bookMarks), the
	// parts' own, so catalogMarks maps it onto the catalog's first.
	stored := make([]model.Chapter, 0, len(chapters))
	for i, ch := range chapters {
		stored = append(stored, model.Chapter{
			Position: i, Title: ch.Title, StartMS: ch.StartMS, EndMS: ch.EndMS,
		})
	}
	bd, err := l.lib.Book(ctx, it.PID)
	if err != nil {
		return EditOutcomeDTO{}, classify(err)
	}
	stored = catalogMarks(bd, stored)
	if err := l.lib.SetChapters(ctx, it.PID, stored, model.LockOf(lock), force); err != nil {
		return EditOutcomeDTO{}, classify(err)
	}
	return EditOutcomeDTO{}, nil
}

// validateChapterList enforces ordered, non-overlapping chapters with
// sequential indexes; only the final chapter may be open-ended.
func validateChapterList(chapters []ChapterMark) error {
	if len(chapters) > 2000 {
		return errInvalid("at most 2000 chapters")
	}
	for i, ch := range chapters {
		if ch.Index != i {
			return errInvalid("chapter indexes must run sequentially from 0")
		}
		if ch.StartMS < 0 {
			return errInvalid("chapter start must not be negative")
		}
		if ch.EndMS != 0 && ch.EndMS <= ch.StartMS {
			return errInvalid("chapter end must be after its start")
		}
		if ch.EndMS == 0 && i != len(chapters)-1 {
			return errInvalid("only the final chapter may be open-ended")
		}
		if i > 0 {
			prev := chapters[i-1]
			if ch.StartMS < prev.EndMS || ch.StartMS <= prev.StartMS {
				return errInvalid("chapters must be ordered and non-overlapping")
			}
		}
	}
	return nil
}
