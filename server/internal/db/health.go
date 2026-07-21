package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// HealthRow is one item's outstanding health issues. Rules is a JSON
// array of rule names; only failing items keep rows, so the table stays
// proportional to the problems, not the library.
type HealthRow struct {
	ItemPID   string
	MediaType string
	Title     string
	Artist    string
	Rules     string
	RuleCount int
	SweptAtNS int64
}

// UpsertHealthRow stores an item's current issues, replacing its row.
func (d *DB) UpsertHealthRow(ctx context.Context, r HealthRow) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO health_index (item_pid, media_type, title, artist, rules, rule_count, swept_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (item_pid) DO UPDATE SET media_type = excluded.media_type,
			title = excluded.title, artist = excluded.artist, rules = excluded.rules,
			rule_count = excluded.rule_count, swept_at_ns = excluded.swept_at_ns`,
		r.ItemPID, r.MediaType, r.Title, r.Artist, r.Rules, r.RuleCount, r.SweptAtNS)
	if err != nil {
		return fmt.Errorf("db: upserting health row: %w", err)
	}
	return nil
}

// DeleteHealthRow removes an item that now passes everything.
func (d *DB) DeleteHealthRow(ctx context.Context, itemPID string) error {
	if _, err := d.w.ExecContext(ctx, `DELETE FROM health_index WHERE item_pid = ?`, itemPID); err != nil {
		return fmt.Errorf("db: deleting health row: %w", err)
	}
	return nil
}

// PruneHealthRows removes rows the latest full sweep did not touch
// (deleted or newly exempt items).
func (d *DB) PruneHealthRows(ctx context.Context, sweptBeforeNS int64) (int64, error) {
	res, err := d.w.ExecContext(ctx, `DELETE FROM health_index WHERE swept_at_ns < ?`, sweptBeforeNS)
	if err != nil {
		return 0, fmt.Errorf("db: pruning health rows: %w", err)
	}
	return res.RowsAffected()
}

// HealthRowByItem fetches one item's issues; ErrNotFound when clean.
func (d *DB) HealthRowByItem(ctx context.Context, itemPID string) (HealthRow, error) {
	var r HealthRow
	err := d.r.QueryRowContext(ctx, `
		SELECT item_pid, media_type, title, artist, rules, rule_count, swept_at_ns
		FROM health_index WHERE item_pid = ?`, itemPID).Scan(
		&r.ItemPID, &r.MediaType, &r.Title, &r.Artist, &r.Rules, &r.RuleCount, &r.SweptAtNS)
	if errors.Is(err, sql.ErrNoRows) {
		return HealthRow{}, ErrNotFound
	}
	if err != nil {
		return HealthRow{}, fmt.Errorf("db: reading health row: %w", err)
	}
	return r, nil
}

// ListHealthRows pages failing items worst first (most failed rules,
// then title, then pid), optionally restricted to rows whose JSON rule
// list contains the named rule. The cursor is the previous page's last
// (rule_count, title, item_pid).
func (d *DB) ListHealthRows(ctx context.Context, rule string, afterCount int, afterTitle, afterPID string, limit int) ([]HealthRow, error) {
	q := `SELECT item_pid, media_type, title, artist, rules, rule_count, swept_at_ns
		FROM health_index WHERE 1=1`
	args := []any{}
	if rule != "" {
		q += ` AND EXISTS (SELECT 1 FROM json_each(rules) WHERE json_each.value = ?)`
		args = append(args, rule)
	}
	if afterPID != "" {
		q += ` AND (rule_count < ? OR (rule_count = ? AND (title > ? OR (title = ? AND item_pid > ?))))`
		args = append(args, afterCount, afterCount, afterTitle, afterTitle, afterPID)
	}
	q += ` ORDER BY rule_count DESC, title, item_pid LIMIT ?`
	args = append(args, limit)
	rows, err := d.r.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("db: listing health rows: %w", err)
	}
	defer rows.Close()
	var out []HealthRow
	for rows.Next() {
		var r HealthRow
		if err := rows.Scan(&r.ItemPID, &r.MediaType, &r.Title, &r.Artist, &r.Rules, &r.RuleCount, &r.SweptAtNS); err != nil {
			return nil, fmt.Errorf("db: scanning health row: %w", err)
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// HealthRuleCounts aggregates failing item counts per rule.
func (d *DB) HealthRuleCounts(ctx context.Context) (map[string]int, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT json_each.value, COUNT(*)
		FROM health_index, json_each(rules)
		GROUP BY json_each.value`)
	if err != nil {
		return nil, fmt.Errorf("db: counting health rules: %w", err)
	}
	defer rows.Close()
	out := map[string]int{}
	for rows.Next() {
		var rule string
		var n int
		if err := rows.Scan(&rule, &n); err != nil {
			return nil, fmt.Errorf("db: scanning health rule count: %w", err)
		}
		out[rule] = n
	}
	return out, rows.Err()
}

// FailingItems returns up to limit item pids currently failing one rule.
func (d *DB) FailingItems(ctx context.Context, rule string, limit int) ([]string, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT item_pid FROM health_index
		WHERE EXISTS (SELECT 1 FROM json_each(rules) WHERE json_each.value = ?)
		ORDER BY item_pid LIMIT ?`, rule, limit)
	if err != nil {
		return nil, fmt.Errorf("db: listing failing items: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var pid string
		if err := rows.Scan(&pid); err != nil {
			return nil, fmt.Errorf("db: scanning failing item: %w", err)
		}
		out = append(out, pid)
	}
	return out, rows.Err()
}

// EnqueueFix queues one item for one rule's fixer; re-queueing is a
// no-op.
func (d *DB) EnqueueFix(ctx context.Context, itemPID, rule string) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO fix_queue (item_pid, rule) VALUES (?, ?)
		ON CONFLICT (item_pid, rule) DO NOTHING`, itemPID, rule)
	if err != nil {
		return fmt.Errorf("db: queuing fix: %w", err)
	}
	return nil
}

// FixQueueRow is one queued fix.
type FixQueueRow struct {
	ID       int64
	ItemPID  string
	Rule     string
	Attempts int
}

// LeaseFix claims the oldest lease-free fix; ErrNotFound when idle.
func (d *DB) LeaseFix(ctx context.Context, nowNS, leaseNS int64, maxAttempts int) (FixQueueRow, error) {
	row := d.w.QueryRowContext(ctx, `
		UPDATE fix_queue SET lease_until_ns = ? + ?
		WHERE id = (
			SELECT id FROM fix_queue
			WHERE lease_until_ns < ? AND next_at_ns <= ? AND attempts < ?
			ORDER BY id LIMIT 1
		)
		RETURNING id, item_pid, rule, attempts`,
		nowNS, leaseNS, nowNS, nowNS, maxAttempts)
	var r FixQueueRow
	if err := row.Scan(&r.ID, &r.ItemPID, &r.Rule, &r.Attempts); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return FixQueueRow{}, ErrNotFound
		}
		return FixQueueRow{}, fmt.Errorf("db: leasing fix: %w", err)
	}
	return r, nil
}

// CompleteFix removes a finished fix.
func (d *DB) CompleteFix(ctx context.Context, id int64) error {
	if _, err := d.w.ExecContext(ctx, `DELETE FROM fix_queue WHERE id = ?`, id); err != nil {
		return fmt.Errorf("db: completing fix: %w", err)
	}
	return nil
}

// FailFix records a failed attempt and holds the row until retryAtNS.
func (d *DB) FailFix(ctx context.Context, id int64, msg string, retryAtNS int64) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE fix_queue SET attempts = attempts + 1, lease_until_ns = ?, next_at_ns = ?, last_error = ?
		WHERE id = ?`, retryAtNS, retryAtNS, msg, id)
	if err != nil {
		return fmt.Errorf("db: failing fix: %w", err)
	}
	return nil
}

// PruneFixQueue drops fixes out of attempts.
func (d *DB) PruneFixQueue(ctx context.Context, maxAttempts int) (int64, error) {
	res, err := d.w.ExecContext(ctx, `DELETE FROM fix_queue WHERE attempts >= ?`, maxAttempts)
	if err != nil {
		return 0, fmt.Errorf("db: pruning fix queue: %w", err)
	}
	return res.RowsAffected()
}
