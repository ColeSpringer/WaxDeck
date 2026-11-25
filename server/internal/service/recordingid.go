package service

import (
	"context"
	"maps"
	"slices"
	"strings"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"
)

// recordingIDField is a track's recording id. The catalog keys a track
// by the recording id its file carries, so one written into a file
// re-mints the item on the next read of it, leaving its pid behind;
// every writer keeps it in the catalog, and no file is owed it.
const recordingIDField = "mbid"

// splitRecordingIDs takes the recording ids out of a field batch, into a
// batch of their own for the catalog alone. Neither batch shares a map
// with the one it came from.
func splitRecordingIDs(batch []model.ItemFieldEdit) (rest, ids []model.ItemFieldEdit) {
	rest = make([]model.ItemFieldEdit, 0, len(batch))
	for _, e := range batch {
		fields := maps.Clone(e.Fields)
		if v, ok := fields[recordingIDField]; ok {
			delete(fields, recordingIDField)
			ids = append(ids, model.ItemFieldEdit{ItemPID: e.ItemPID, Fields: map[string]string{recordingIDField: v}})
		}
		if len(fields) > 0 {
			rest = append(rest, model.ItemFieldEdit{ItemPID: e.ItemPID, Fields: fields})
		}
	}
	return rest, ids
}

// recordingIDLocked reports whether an item's recording id is locked.
func (l *Editor) recordingIDLocked(ctx context.Context, pid model.PID) (bool, error) {
	prov, err := l.lib.Provenance(ctx, pid)
	if err != nil {
		return false, err
	}
	return slices.ContainsFunc(prov, func(p model.FieldProvenance) bool {
		return p.Field == recordingIDField && p.Locked
	}), nil
}

// recordRecordingIDs records recording ids split off an edit whose other
// fields have committed, in the catalog alone. The request's end cannot
// cancel it, so the edit never stands without them; hook stands in for
// its failure in a test.
func recordRecordingIDs(ctx context.Context, lib *waxbin.Library, hook func() error, ids []model.ItemFieldEdit, opts waxbin.EditOptions) (*waxbin.BatchEditResult, error) {
	if hook != nil {
		if err := hook(); err != nil {
			return nil, err
		}
	}
	opts.WriteBack = false
	return lib.EditItemsFields(context.WithoutCancel(ctx), ids, opts)
}

// editTrackFields is EditFields for a track with its recording id kept
// in the catalog, locked when the file lacks it (lacksRecordingID). The
// other fields go first, so a lock on one of them refuses the edit before
// the id moves; a locked id, unless forced, refuses the whole edit up
// front.
func (l *Editor) editTrackFields(ctx context.Context, pid model.PID, fields map[string]string, opts waxbin.EditOptions) error {
	id, ok := fields[recordingIDField]
	if !ok {
		return l.lib.EditFields(ctx, pid, fields, opts)
	}
	idOpts := opts
	idOpts.WriteBack = false
	if opts.Lock != model.LockOn && lacksRecordingID(ctx, l.lib, pid, id) {
		idOpts.Lock = model.LockOn
	}
	if !opts.WriteBack && idOpts.Lock == opts.Lock {
		return l.lib.EditFields(ctx, pid, fields, opts)
	}
	if len(fields) == 1 {
		return l.lib.EditFields(ctx, pid, fields, idOpts)
	}
	if !opts.Force {
		locked, err := l.recordingIDLocked(ctx, pid)
		if err != nil {
			return err
		}
		if locked {
			refuse := opts
			refuse.WriteBack = false
			return l.lib.EditFields(ctx, pid, fields, refuse)
		}
	}
	rest := maps.Clone(fields)
	delete(rest, recordingIDField)
	// A batch of one, whose result says the catalog committed even when
	// its write pass then failed or was cancelled.
	res, err := l.lib.EditManyFields(ctx, []model.PID{pid}, rest, opts)
	if res == nil {
		return err
	}
	ids := []model.ItemFieldEdit{{ItemPID: pid, Fields: map[string]string{recordingIDField: id}}}
	if _, idErr := recordRecordingIDs(ctx, l.lib, l.recordingIDsHook, ids, idOpts); idErr != nil {
		return idErr
	}
	if err != nil {
		return err
	}
	if wbe := res.WriteBackErrors[pid]; wbe != nil {
		return wbe
	}
	return nil
}

// editManyKeepingRecordingID is EditManyFields with the tracks' recording
// ids kept in the catalog, as editTrackFields; a bulk edit locks every
// field it edits, so a held id needs no lock of its own. A track whose id
// is locked is skipped with SkipLocked and refuses the batch without it,
// unless forced. Every other item, a book's id included, is edited as
// asked.
func (l *Editor) editManyKeepingRecordingID(ctx context.Context, pids []model.PID, tracks map[model.PID]bool, fields map[string]string, opts waxbin.EditOptions) (*waxbin.BatchEditResult, error) {
	id, ok := fields[recordingIDField]
	if !ok || len(tracks) == 0 || !opts.WriteBack {
		return l.lib.EditManyFields(ctx, pids, fields, opts)
	}
	idOpts := opts
	idOpts.WriteBack = false
	var held []model.PID
	if !opts.Force {
		for _, pid := range pids {
			if !tracks[pid] {
				continue
			}
			locked, err := l.recordingIDLocked(ctx, pid)
			if err != nil {
				return nil, err
			}
			if locked {
				held = append(held, pid)
			}
		}
		if len(held) > 0 && !opts.SkipLocked {
			refuse := opts
			refuse.WriteBack = false
			return l.lib.EditManyFields(ctx, pids, fields, refuse)
		}
	}
	rest := maps.Clone(fields)
	delete(rest, recordingIDField)
	var batch []model.ItemFieldEdit
	var idOnly []model.PID
	for _, pid := range pids {
		switch {
		case slices.Contains(held, pid):
		case !tracks[pid]:
			batch = append(batch, model.ItemFieldEdit{ItemPID: pid, Fields: fields})
		case len(rest) > 0:
			batch = append(batch, model.ItemFieldEdit{ItemPID: pid, Fields: rest})
		default:
			idOnly = append(idOnly, pid)
		}
	}
	res := &waxbin.BatchEditResult{}
	var err error
	if len(batch) > 0 {
		if res, err = l.lib.EditItemsFields(ctx, batch, opts); res == nil {
			return nil, err
		}
	}
	idPIDs := idOnly
	for _, pid := range res.Edited {
		if tracks[pid] {
			idPIDs = append(idPIDs, pid)
		}
	}
	if len(idPIDs) > 0 {
		ids := make([]model.ItemFieldEdit, 0, len(idPIDs))
		for _, pid := range idPIDs {
			ids = append(ids, model.ItemFieldEdit{ItemPID: pid, Fields: map[string]string{recordingIDField: id}})
		}
		got, idErr := recordRecordingIDs(ctx, l.lib, l.recordingIDsHook, ids, idOpts)
		if idErr != nil {
			return res, idErr
		}
		// A track named for its id alone was edited, or skipped, here.
		for _, pid := range got.Edited {
			if slices.Contains(idOnly, pid) {
				res.Edited = append(res.Edited, pid)
			}
		}
		res.Skipped = append(res.Skipped, got.Skipped...)
	}
	res.Skipped = append(res.Skipped, held...)
	return res, err
}

// fileRecordingID is the recording id an item's primary file states;
// empty when it states none or cannot be read.
func fileRecordingID(ctx context.Context, lib *waxbin.Library, pid model.PID) string {
	refs, err := lib.ItemFiles(ctx, pid)
	if err != nil {
		return ""
	}
	for _, r := range refs {
		if r.Role != fileRolePrimary {
			continue
		}
		doc, err := waxlabel.ParseFile(ctx, string(r.Path))
		if err != nil {
			return ""
		}
		if vals, _ := doc.Get(tag.MBRecordingID); len(vals) > 0 {
			return strings.TrimSpace(vals[0])
		}
		return ""
	}
	return ""
}

// lacksRecordingID reports whether id is a recording id the item's file
// does not carry. The catalog alone then holds it, so it stays locked:
// unlocked, the next read of the file would put the file's back.
func lacksRecordingID(ctx context.Context, lib *waxbin.Library, pid model.PID, id string) bool {
	return id != "" && !strings.EqualFold(fileRecordingID(ctx, lib, pid), id)
}

// errRecordingIDHeld refuses to unlock a track's recording id when its
// file carries none: the next read of the file would clear it.
func errRecordingIDHeld() error {
	return &Error{
		Kind:   KindInvalid,
		Msg:    "a track's recording id stays locked while its file carries none, or the next scan would clear it",
		Params: map[string]string{"reason": "recording-id-held"},
	}
}
