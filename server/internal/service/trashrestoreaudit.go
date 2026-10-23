package service

import (
	"context"
	"path/filepath"

	"github.com/colespringer/waxbin/model"
)

// trashRestoreAudit describes the journal entry a restore is about to
// bring back: the file by name, and where it was, why it went and how big
// it is. Read before the restore, since the entry is no longer active
// after it. An entry the journal no longer lists is described by its id
// alone.
func (l *Library) trashRestoreAudit(ctx context.Context, apiTrashID string, pid model.PID) (AuditTarget, map[string]any) {
	target := AuditTarget{Kind: "trash", PID: apiTrashID}
	entries, err := l.lib.Trash(ctx, false, 0)
	if err != nil {
		return target, nil
	}
	for _, e := range entries {
		if e.PID != pid {
			continue
		}
		// Named as the trash lists it: within its library.
		name := l.trashEntryName(e)
		target.Name = filepath.Base(name)
		detail := map[string]any{"path": name, "reason": e.Reason, "sizeBytes": e.Size}
		if e.LibraryPID != "" {
			if name := l.libraryName(ctx, e.LibraryPID); name != "" {
				detail["library"] = name
			}
		}
		return target, detail
	}
	return target, nil
}
