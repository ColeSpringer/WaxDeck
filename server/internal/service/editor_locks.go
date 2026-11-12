package service

import (
	"context"
	"sort"

	"github.com/colespringer/waxbin/model"
)

// SetItemLocks locks or unlocks the named fields (scalar names plus the
// namespaced lyrics/chapters/art, credit.ROLE, and tag.KEY artifacts)
// and returns every field locked afterward.
func (l *Editor) SetItemLocks(ctx context.Context, uc *UserCtx, apiPID string, fields []string, locked bool) ([]string, error) {
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return nil, err
	}
	if len(fields) == 0 {
		return nil, errInvalid("at least one field is required")
	}
	if len(fields) > 100 {
		return nil, errInvalid("at most 100 fields per request")
	}
	canonical := make([]string, 0, len(fields))
	for _, f := range fields {
		// Tag lock names canonicalize with the tag keys themselves.
		if key, ok := model.CutTagPrefix(f); ok {
			canon, valid := model.CanonicalTagKey(key)
			if !valid {
				return nil, errInvalid("field " + f + " is not lockable")
			}
			f = model.TagLockField(canon)
		}
		if !model.IsCuratableField(f) {
			return nil, errInvalid("field " + f + " is not lockable")
		}
		canonical = append(canonical, f)
	}
	if locked {
		err = l.lib.Lock(ctx, it.PID, canonical...)
	} else {
		err = l.lib.Unlock(ctx, it.PID, canonical...)
	}
	if err != nil {
		return nil, classify(err)
	}
	return l.lockedFieldsFor(ctx, it.PID)
}

// lockedFieldsFor lists every currently locked field, sorted for a
// stable response.
func (l *Editor) lockedFieldsFor(ctx context.Context, pid model.PID) ([]string, error) {
	rows, err := l.lib.Provenance(ctx, pid)
	if err != nil {
		return nil, classify(err)
	}
	out := []string{}
	for _, r := range rows {
		if r.Locked {
			out = append(out, r.Field)
		}
	}
	sort.Strings(out)
	return out, nil
}
