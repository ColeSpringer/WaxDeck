package db

import (
	"context"
	"fmt"
)

// RecordToolTrash notes the files a run of task is about to move to the
// trash from book, by the paths they are taken from.
func (d *DB) RecordToolTrash(ctx context.Context, book, task string, paths []string) error {
	for _, p := range paths {
		if _, err := d.w.ExecContext(ctx, `
			INSERT INTO tool_trash (book_pid, orig_path, task_id) VALUES (?, ?, ?)
			ON CONFLICT (book_pid, orig_path) DO UPDATE SET task_id = excluded.task_id`, book, p, task); err != nil {
			return fmt.Errorf("db: recording a tool's trash: %w", err)
		}
	}
	return nil
}

// ToolTrashOf answers the paths runs that did not finish took from book
// to the trash.
func (d *DB) ToolTrashOf(ctx context.Context, book string) ([]string, error) {
	rows, err := d.w.QueryContext(ctx, `SELECT orig_path FROM tool_trash WHERE book_pid = ? ORDER BY orig_path`, book)
	if err != nil {
		return nil, fmt.Errorf("db: reading a tool's trash: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var p string
		if err := rows.Scan(&p); err != nil {
			return nil, fmt.Errorf("db: reading a tool's trash: %w", err)
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// SettleToolTrash forgets what task's runs took from book to the trash:
// the run finished, its new files holding them, or put them back.
func (d *DB) SettleToolTrash(ctx context.Context, book, task string) error {
	if _, err := d.w.ExecContext(ctx, `DELETE FROM tool_trash WHERE book_pid = ? AND task_id = ?`, book, task); err != nil {
		return fmt.Errorf("db: settling a tool's trash: %w", err)
	}
	return nil
}

// ForgetToolTrash forgets paths of book the trash no longer holds:
// restored, or purged.
func (d *DB) ForgetToolTrash(ctx context.Context, book string, paths []string) error {
	for _, p := range paths {
		if _, err := d.w.ExecContext(ctx, `DELETE FROM tool_trash WHERE book_pid = ? AND orig_path = ?`, book, p); err != nil {
			return fmt.Errorf("db: forgetting a tool's trash: %w", err)
		}
	}
	return nil
}
