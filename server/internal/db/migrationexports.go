package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// MigrationExport is one uploaded account data export, staged for the
// import that reads it. The archive itself lives on disk under the
// staging directory; this row is what an import addresses it by, and
// what the expiry sweep walks.
type MigrationExport struct {
	ID          string
	UserID      string
	FileName    string
	SizeBytes   int64
	Source      string
	FilesJSON   string
	CreatedAtNS int64
	ExpiresAtNS int64
	// ClaimedBy is the tool task reading this upload right now, empty
	// for one nobody holds.
	ClaimedBy string
}

// InsertMigrationExport records one staged upload.
func (d *DB) InsertMigrationExport(ctx context.Context, e MigrationExport) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO migration_exports
			(id, user_id, file_name, size_bytes, source, files_json, created_at_ns, expires_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		e.ID, e.UserID, e.FileName, e.SizeBytes, e.Source, e.FilesJSON, e.CreatedAtNS, e.ExpiresAtNS)
	if err != nil {
		return fmt.Errorf("db: recording a staged export: %w", err)
	}
	return nil
}

// MigrationExportByID reads one staged export; ErrNotFound when the id
// names nothing.
func (d *DB) MigrationExportByID(ctx context.Context, id string) (MigrationExport, error) {
	var e MigrationExport
	err := d.r.QueryRowContext(ctx, `
		SELECT id, user_id, file_name, size_bytes, source, files_json,
		       created_at_ns, expires_at_ns, claimed_by
		FROM migration_exports WHERE id = ?`, id).
		Scan(&e.ID, &e.UserID, &e.FileName, &e.SizeBytes, &e.Source, &e.FilesJSON,
			&e.CreatedAtNS, &e.ExpiresAtNS, &e.ClaimedBy)
	if errors.Is(err, sql.ErrNoRows) {
		return MigrationExport{}, ErrNotFound
	}
	if err != nil {
		return MigrationExport{}, fmt.Errorf("db: reading a staged export: %w", err)
	}
	return e, nil
}

// DeleteMigrationExport drops one row, for an import that finished with
// it or an upload somebody discarded.
func (d *DB) DeleteMigrationExport(ctx context.Context, id string) error {
	if _, err := d.w.ExecContext(ctx, `DELETE FROM migration_exports WHERE id = ?`, id); err != nil {
		return fmt.Errorf("db: deleting a staged export: %w", err)
	}
	return nil
}

// ExpiredMigrationExports lists the rows the sweep should delete, so the
// caller can remove each file before the row that names it.
func (d *DB) ExpiredMigrationExports(ctx context.Context, nowNS int64) ([]MigrationExport, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT id, user_id, file_name, size_bytes, source, files_json,
		       created_at_ns, expires_at_ns, claimed_by
		FROM migration_exports WHERE expires_at_ns <= ?`, nowNS)
	if err != nil {
		return nil, fmt.Errorf("db: listing expired exports: %w", err)
	}
	defer rows.Close()
	var out []MigrationExport
	for rows.Next() {
		var e MigrationExport
		if err := rows.Scan(&e.ID, &e.UserID, &e.FileName, &e.SizeBytes, &e.Source,
			&e.FilesJSON, &e.CreatedAtNS, &e.ExpiresAtNS, &e.ClaimedBy); err != nil {
			return nil, fmt.Errorf("db: listing expired exports: %w", err)
		}
		out = append(out, e)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("db: listing expired exports: %w", err)
	}
	return out, nil
}

// ClaimMigrationExport marks an upload as the one task's to read, and
// reports whether the claim was taken. The same task re-claiming is
// always allowed, which is what makes a retried attempt work.
//
// A claim held by a task that is no longer live is stale: the run that
// took it finished, failed, or died with the process, and nothing is
// reading the archive any more. Replacing it here rather than waiting
// for the day-long expiry is what keeps a crashed import re-runnable.
func (d *DB) ClaimMigrationExport(ctx context.Context, id, taskID string) (bool, error) {
	res, err := d.w.ExecContext(ctx, `
		UPDATE migration_exports SET claimed_by = ?
		WHERE id = ?
		  AND (claimed_by = '' OR claimed_by = ? OR NOT EXISTS (
		        SELECT 1 FROM tool_tasks
		        WHERE tool_tasks.id = migration_exports.claimed_by
		          AND tool_tasks.state IN ('queued', 'running')))`,
		taskID, id, taskID)
	if err != nil {
		return false, fmt.Errorf("db: claiming a staged export: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("db: claiming a staged export: %w", err)
	}
	return n > 0, nil
}

// ReleaseMigrationExport drops one task's claim, leaving the upload for
// whoever asks next. Nothing happens when the claim has already moved
// on, which is the state a stale claim was replaced from.
func (d *DB) ReleaseMigrationExport(ctx context.Context, id, taskID string) error {
	_, err := d.w.ExecContext(ctx,
		`UPDATE migration_exports SET claimed_by = '' WHERE id = ? AND claimed_by = ?`,
		id, taskID)
	if err != nil {
		return fmt.Errorf("db: releasing a staged export: %w", err)
	}
	return nil
}
