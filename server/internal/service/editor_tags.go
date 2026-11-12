package service

import (
	"context"
	"strings"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// kindTagRefusal refuses the custom tags that read as what an item is,
// before the catalog does: its own sentence sends a person to an edit
// surface a track does not have.
func kindTagRefusal(kind model.Kind, key string) error {
	switch strings.ToUpper(strings.TrimSpace(key)) {
	case "MEDIATYPE":
		return errInvalid("MEDIATYPE is not a custom tag; an item becomes an audiobook or music by changing its kind")
	case "NARRATOR":
		if kind == model.KindTrack {
			return errInvalid("NARRATOR is not a custom tag; a track becomes an audiobook by changing its kind, and then takes narrator credits")
		}
		return errInvalid("NARRATOR is not a custom tag; edit the narrator credits instead")
	}
	return nil
}

// SetItemTag replaces one custom tag's ordered values. The catalog
// canonicalizes the key and rejects reserved keys it owns through
// another surface.
func (l *Editor) SetItemTag(ctx context.Context, uc *UserCtx, apiPID, key string, values []string, p MetadataEditParams) (TagEditOutcomeDTO, error) {
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return TagEditOutcomeDTO{}, err
	}
	if err := kindTagRefusal(it.Kind, key); err != nil {
		return TagEditOutcomeDTO{}, err
	}
	if len(values) > 100 {
		return TagEditOutcomeDTO{}, errInvalid("at most 100 values per tag")
	}
	if p.WriteBack {
		if err := l.Settings.checkPathWritable(ctx, string(it.Path)); err != nil {
			return TagEditOutcomeDTO{}, err
		}
	}
	canon, stored, err := l.lib.SetItemTag(ctx, it.PID, key, values, waxbin.TagEditOptions{
		Lock: model.LockOf(p.Lock), Force: p.Force, WriteBack: p.WriteBack,
	})
	// A file that could not take the values leaves the edit standing.
	outcome, err := editOutcomeFromWriteBack(err)
	if err != nil {
		return TagEditOutcomeDTO{}, err
	}
	return TagEditOutcomeDTO{Key: canon, Stored: stored, Failures: outcome.Failures}, nil
}

// ClearItemTag removes the tag and its lock, from the files too with
// writeBack; the files it could not reach are answered for the commit
// to report, the edit standing either way.
func (l *Editor) ClearItemTag(ctx context.Context, uc *UserCtx, apiPID, key string, p MetadataEditParams) (EditOutcomeDTO, error) {
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if p.WriteBack {
		if err := l.Settings.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	_, _, err = l.lib.SetItemTag(ctx, it.PID, key, nil, waxbin.TagEditOptions{
		Lock: model.LockOff, Force: true, WriteBack: p.WriteBack,
	})
	return editOutcomeFromWriteBack(err)
}
