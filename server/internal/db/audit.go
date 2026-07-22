package db

import (
	"context"
	"fmt"
	"strings"
)

// AuditEvent is one recorded administrative action. Actor and target
// names are denormalized at write time so entries outlive renames and
// deletions; Detail is a JSON document owned by the service layer.
type AuditEvent struct {
	ID          int64
	ActorID     string
	ActorName   string
	Action      string
	TargetKind  string
	TargetPID   string
	TargetName  string
	Detail      string
	CreatedAtNS int64
}

// AppendAudit stores one audit event.
func (d *DB) AppendAudit(ctx context.Context, e AuditEvent) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO audit_log (actor_id, actor_name, action, target_kind, target_pid, target_name, detail, created_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		e.ActorID, e.ActorName, e.Action, e.TargetKind, e.TargetPID, e.TargetName, e.Detail, e.CreatedAtNS)
	if err != nil {
		return fmt.Errorf("db: appending audit event: %w", err)
	}
	return nil
}

// AuditFilter narrows a page of audit events. Action ending in a dot
// matches as a prefix (`playlist.` selects every playlist action).
type AuditFilter struct {
	Action    string
	ActorID   string
	TargetPID string
}

// ListAudit pages audit events newest first. The cursor is the previous
// page's last id; 0 starts at the head.
func (d *DB) ListAudit(ctx context.Context, f AuditFilter, beforeID int64, limit int) ([]AuditEvent, error) {
	q := `SELECT id, actor_id, actor_name, action, target_kind, target_pid, target_name, detail, created_at_ns
	      FROM audit_log WHERE 1=1`
	args := []any{}
	if f.Action != "" {
		if strings.HasSuffix(f.Action, ".") {
			q += ` AND action >= ? AND action < ?`
			// The prefix range trick keeps the (action, id) index usable;
			// '/' is the next rune after '.'.
			args = append(args, f.Action, strings.TrimSuffix(f.Action, ".")+"/")
		} else {
			q += ` AND action = ?`
			args = append(args, f.Action)
		}
	}
	if f.ActorID != "" {
		q += ` AND actor_id = ?`
		args = append(args, f.ActorID)
	}
	if f.TargetPID != "" {
		q += ` AND target_pid = ?`
		args = append(args, f.TargetPID)
	}
	if beforeID > 0 {
		q += ` AND id < ?`
		args = append(args, beforeID)
	}
	q += ` ORDER BY id DESC LIMIT ?`
	args = append(args, limit)
	rows, err := d.r.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("db: listing audit events: %w", err)
	}
	defer rows.Close()
	var out []AuditEvent
	for rows.Next() {
		var e AuditEvent
		if err := rows.Scan(&e.ID, &e.ActorID, &e.ActorName, &e.Action, &e.TargetKind,
			&e.TargetPID, &e.TargetName, &e.Detail, &e.CreatedAtNS); err != nil {
			return nil, fmt.Errorf("db: scanning audit event: %w", err)
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// PruneAudit keeps the newest keep rows and deletes the rest.
func (d *DB) PruneAudit(ctx context.Context, keep int) (int64, error) {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM audit_log WHERE id < (
			SELECT COALESCE(MIN(id), 0) FROM (
				SELECT id FROM audit_log ORDER BY id DESC LIMIT ?))`,
		keep)
	if err != nil {
		return 0, fmt.Errorf("db: pruning audit log: %w", err)
	}
	return res.RowsAffected()
}
