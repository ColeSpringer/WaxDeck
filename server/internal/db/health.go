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
	// Detail is the rules' JSON measurements, '' when they carry none.
	Detail string
}

// UpsertHealthRow stores an item's current issues, replacing its row.
func (d *DB) UpsertHealthRow(ctx context.Context, r HealthRow) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO health_index (item_pid, media_type, title, artist, rules, rule_count, swept_at_ns, detail)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (item_pid) DO UPDATE SET media_type = excluded.media_type,
			title = excluded.title, artist = excluded.artist, rules = excluded.rules,
			rule_count = excluded.rule_count, swept_at_ns = excluded.swept_at_ns,
			detail = excluded.detail`,
		r.ItemPID, r.MediaType, r.Title, r.Artist, r.Rules, r.RuleCount, r.SweptAtNS, r.Detail)
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

// DropHealthRule takes one rule off an item's row, against the row as it
// stands, and the row with it when that was its last: a sweep writing
// the row meanwhile keeps its own fields and rules.
func (d *DB) DropHealthRule(ctx context.Context, itemPID, rule string) error {
	if _, err := d.w.ExecContext(ctx, `
		UPDATE health_index SET
			rules = (SELECT json_group_array(value) FROM (
				SELECT value FROM json_each(health_index.rules) WHERE value <> ? ORDER BY key)),
			rule_count = (SELECT COUNT(*) FROM json_each(health_index.rules) WHERE value <> ?)
		WHERE item_pid = ? AND EXISTS (SELECT 1 FROM json_each(health_index.rules) WHERE value = ?)`,
		rule, rule, itemPID, rule); err != nil {
		return fmt.Errorf("db: dropping a health rule: %w", err)
	}
	if _, err := d.w.ExecContext(ctx, `
		DELETE FROM health_index WHERE item_pid = ? AND rule_count = 0`, itemPID); err != nil {
		return fmt.Errorf("db: dropping a passing health row: %w", err)
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
		SELECT item_pid, media_type, title, artist, rules, rule_count, swept_at_ns, detail
		FROM health_index WHERE item_pid = ?`, itemPID).Scan(
		&r.ItemPID, &r.MediaType, &r.Title, &r.Artist, &r.Rules, &r.RuleCount, &r.SweptAtNS, &r.Detail)
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
	q := `SELECT item_pid, media_type, title, artist, rules, rule_count, swept_at_ns, detail
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
		if err := rows.Scan(&r.ItemPID, &r.MediaType, &r.Title, &r.Artist, &r.Rules, &r.RuleCount, &r.SweptAtNS, &r.Detail); err != nil {
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
