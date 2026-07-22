package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// Backup is one backup archive's record; the file itself lives in the
// data directory's backups folder. Origin says what produced it
// (manual, scheduled, imported).
type Backup struct {
	ID           string
	State        string
	Origin       string
	FileName     string
	SizeBytes    int64
	Error        string
	CreatedAtNS  int64
	FinishedAtNS int64
}

const backupCols = `id, state, origin, file_name, size_bytes, error, created_at_ns, finished_at_ns`

func scanBackup(row interface{ Scan(...any) error }) (Backup, error) {
	var b Backup
	err := row.Scan(&b.ID, &b.State, &b.Origin, &b.FileName, &b.SizeBytes,
		&b.Error, &b.CreatedAtNS, &b.FinishedAtNS)
	return b, err
}

// InsertBackup stores a new backup record.
func (d *DB) InsertBackup(ctx context.Context, b Backup) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO backups (`+backupCols+`)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		b.ID, b.State, b.Origin, b.FileName, b.SizeBytes, b.Error, b.CreatedAtNS, b.FinishedAtNS)
	if err != nil {
		return fmt.Errorf("db: inserting backup: %w", err)
	}
	return nil
}

// UpdateBackup rewrites a backup's mutable fields (same id).
func (d *DB) UpdateBackup(ctx context.Context, b Backup) error {
	res, err := d.w.ExecContext(ctx, `
		UPDATE backups SET state = ?, size_bytes = ?, error = ?, finished_at_ns = ?
		WHERE id = ?`,
		b.State, b.SizeBytes, b.Error, b.FinishedAtNS, b.ID)
	if err != nil {
		return fmt.Errorf("db: updating backup: %w", err)
	}
	return requireRow(res)
}

// BackupByID fetches one backup.
func (d *DB) BackupByID(ctx context.Context, id string) (Backup, error) {
	b, err := scanBackup(d.r.QueryRowContext(ctx,
		`SELECT `+backupCols+` FROM backups WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return Backup{}, ErrNotFound
	}
	if err != nil {
		return Backup{}, fmt.Errorf("db: reading backup: %w", err)
	}
	return b, nil
}

// ListBackups returns every backup, newest first.
func (d *DB) ListBackups(ctx context.Context) ([]Backup, error) {
	rows, err := d.r.QueryContext(ctx,
		`SELECT `+backupCols+` FROM backups ORDER BY created_at_ns DESC, id DESC`)
	if err != nil {
		return nil, fmt.Errorf("db: listing backups: %w", err)
	}
	defer rows.Close()
	var out []Backup
	for rows.Next() {
		b, err := scanBackup(rows)
		if err != nil {
			return nil, fmt.Errorf("db: scanning backup: %w", err)
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

// DeleteBackup removes the record; ErrNotFound when absent. The caller
// removes the archive file.
func (d *DB) DeleteBackup(ctx context.Context, id string) error {
	res, err := d.w.ExecContext(ctx, `DELETE FROM backups WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("db: deleting backup: %w", err)
	}
	return requireRow(res)
}

// ClaimBackupSlot inserts the running backup record only while no other
// backup is running, in one guarded statement (two concurrent create
// calls cannot both start).
func (d *DB) ClaimBackupSlot(ctx context.Context, b Backup) error {
	res, err := d.w.ExecContext(ctx, `
		INSERT INTO backups (`+backupCols+`)
		SELECT ?, ?, ?, ?, ?, ?, ?, ?
		WHERE NOT EXISTS (SELECT 1 FROM backups WHERE state = 'running')`,
		b.ID, b.State, b.Origin, b.FileName, b.SizeBytes, b.Error, b.CreatedAtNS, b.FinishedAtNS)
	if err != nil {
		return fmt.Errorf("db: claiming backup slot: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrConflict
	}
	return nil
}

// FailStaleRunningBackups marks running rows failed; called once at
// startup, where a running row can only be a crash leftover (and would
// otherwise hold the single backup slot forever).
func (d *DB) FailStaleRunningBackups(ctx context.Context, nowNS int64) (int64, error) {
	res, err := d.w.ExecContext(ctx, `
		UPDATE backups SET state = 'failed', error = 'interrupted by a server restart', finished_at_ns = ?
		WHERE state = 'running'`, nowNS)
	if err != nil {
		return 0, fmt.Errorf("db: failing stale backups: %w", err)
	}
	return res.RowsAffected()
}
