package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// RecordAcquiredArt records the front picture a download landed with on
// its item, replacing what an earlier landing recorded.
func (d *DB) RecordAcquiredArt(ctx context.Context, itemPID, artHash, sourceType string) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO acquired_art (item_pid, art_hash, source_type) VALUES (?, ?, ?)
		ON CONFLICT (item_pid) DO UPDATE SET art_hash = excluded.art_hash, source_type = excluded.source_type`,
		itemPID, artHash, sourceType)
	if err != nil {
		return fmt.Errorf("db: recording acquired art: %w", err)
	}
	return nil
}

// AcquiredArt answers the picture hash and source type recorded for an
// item; ErrNotFound when none is.
func (d *DB) AcquiredArt(ctx context.Context, itemPID string) (artHash, sourceType string, err error) {
	err = d.r.QueryRowContext(ctx, `
		SELECT art_hash, source_type FROM acquired_art WHERE item_pid = ?`, itemPID).Scan(&artHash, &sourceType)
	if errors.Is(err, sql.ErrNoRows) {
		return "", "", ErrNotFound
	}
	if err != nil {
		return "", "", fmt.Errorf("db: reading acquired art: %w", err)
	}
	return artHash, sourceType, nil
}

// AcquiredArtRow is one item's recorded download picture.
type AcquiredArtRow struct {
	ItemPID    string
	SourceType string
}

// AcquiredArtByHash lists the items whose download arrived with the
// picture of this hash.
func (d *DB) AcquiredArtByHash(ctx context.Context, artHash string) ([]AcquiredArtRow, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT item_pid, source_type FROM acquired_art WHERE art_hash = ? ORDER BY item_pid`, artHash)
	if err != nil {
		return nil, fmt.Errorf("db: reading acquired art by hash: %w", err)
	}
	defer rows.Close()
	var out []AcquiredArtRow
	for rows.Next() {
		var r AcquiredArtRow
		if err := rows.Scan(&r.ItemPID, &r.SourceType); err != nil {
			return nil, fmt.Errorf("db: reading acquired art by hash: %w", err)
		}
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("db: reading acquired art by hash: %w", err)
	}
	return out, nil
}

// RecordApprovalArt records the front an approval wrote on an item,
// replacing what an earlier approval recorded.
func (d *DB) RecordApprovalArt(ctx context.Context, itemPID, artHash string) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO approval_art (item_pid, art_hash) VALUES (?, ?)
		ON CONFLICT (item_pid) DO UPDATE SET art_hash = excluded.art_hash`,
		itemPID, artHash)
	if err != nil {
		return fmt.Errorf("db: recording approval art: %w", err)
	}
	return nil
}

// ApprovalArt answers the hash of the front an approval wrote on an
// item; ErrNotFound when none is recorded.
func (d *DB) ApprovalArt(ctx context.Context, itemPID string) (string, error) {
	var hash string
	err := d.r.QueryRowContext(ctx, `SELECT art_hash FROM approval_art WHERE item_pid = ?`, itemPID).Scan(&hash)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNotFound
	}
	if err != nil {
		return "", fmt.Errorf("db: reading approval art: %w", err)
	}
	return hash, nil
}

// DropApprovalArt forgets an approval's front on an item, if the record
// still names that front.
func (d *DB) DropApprovalArt(ctx context.Context, itemPID, artHash string) error {
	if _, err := d.w.ExecContext(ctx, `DELETE FROM approval_art WHERE item_pid = ? AND art_hash = ?`, itemPID, artHash); err != nil {
		return fmt.Errorf("db: dropping approval art: %w", err)
	}
	return nil
}

// ForgetApprovalArt forgets whatever approval front is recorded on an
// item.
func (d *DB) ForgetApprovalArt(ctx context.Context, itemPID string) error {
	if _, err := d.w.ExecContext(ctx, `DELETE FROM approval_art WHERE item_pid = ?`, itemPID); err != nil {
		return fmt.Errorf("db: forgetting approval art: %w", err)
	}
	return nil
}
