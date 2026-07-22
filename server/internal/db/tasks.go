package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// ToolTask is one background file-tooling task (book merge, chapter
// split, cue split). Params and ResultPIDs are JSON documents owned by
// the service layer.
type ToolTask struct {
	ID          string
	Type        string
	State       string
	ItemPID     string
	UserID      string
	Params      string
	ProgressPct float64
	Error       string
	ResultPIDs  string
	// Summary is a task-type-specific result document (JSON object) once
	// the task finishes; empty until then.
	Summary      string
	Attempts     int
	CreatedAtNS  int64
	FinishedAtNS int64
}

const taskCols = `id, type, state, item_pid, user_id, params, progress_pct,
	error, result_pids, summary, attempts, created_at_ns, finished_at_ns`

func scanTask(row interface{ Scan(...any) error }) (ToolTask, error) {
	var t ToolTask
	err := row.Scan(&t.ID, &t.Type, &t.State, &t.ItemPID, &t.UserID, &t.Params,
		&t.ProgressPct, &t.Error, &t.ResultPIDs, &t.Summary, &t.Attempts, &t.CreatedAtNS, &t.FinishedAtNS)
	return t, err
}

// InsertToolTask stores a new task.
func (d *DB) InsertToolTask(ctx context.Context, t ToolTask) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO tool_tasks (`+taskCols+`)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		t.ID, t.Type, t.State, t.ItemPID, t.UserID, t.Params, t.ProgressPct,
		t.Error, t.ResultPIDs, t.Summary, t.Attempts, t.CreatedAtNS, t.FinishedAtNS)
	if err != nil {
		return fmt.Errorf("db: inserting tool task: %w", err)
	}
	return nil
}

// ToolTaskByID fetches one task.
func (d *DB) ToolTaskByID(ctx context.Context, id string) (ToolTask, error) {
	t, err := scanTask(d.r.QueryRowContext(ctx,
		`SELECT `+taskCols+` FROM tool_tasks WHERE id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return ToolTask{}, ErrNotFound
	}
	if err != nil {
		return ToolTask{}, fmt.Errorf("db: reading tool task: %w", err)
	}
	return t, nil
}

// UpdateToolTask rewrites a task's mutable fields (same id).
func (d *DB) UpdateToolTask(ctx context.Context, t ToolTask) error {
	res, err := d.w.ExecContext(ctx, `
		UPDATE tool_tasks SET state = ?, progress_pct = ?, error = ?, result_pids = ?,
			summary = ?, finished_at_ns = ?
		WHERE id = ?`,
		t.State, t.ProgressPct, t.Error, t.ResultPIDs, t.Summary, t.FinishedAtNS, t.ID)
	if err != nil {
		return fmt.Errorf("db: updating tool task: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// ListToolTasks pages tasks newest first; userID empty lists everyone
// (administrators).
func (d *DB) ListToolTasks(ctx context.Context, userID string, beforeNS int64, beforeID string, limit int) ([]ToolTask, error) {
	q := `SELECT ` + taskCols + ` FROM tool_tasks WHERE 1=1`
	args := []any{}
	if userID != "" {
		q += ` AND user_id = ?`
		args = append(args, userID)
	}
	if beforeID != "" {
		q += ` AND (created_at_ns < ? OR (created_at_ns = ? AND id < ?))`
		args = append(args, beforeNS, beforeNS, beforeID)
	}
	q += ` ORDER BY created_at_ns DESC, id DESC LIMIT ?`
	args = append(args, limit)
	rows, err := d.r.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("db: listing tool tasks: %w", err)
	}
	defer rows.Close()
	var out []ToolTask
	for rows.Next() {
		t, err := scanTask(rows)
		if err != nil {
			return nil, fmt.Errorf("db: scanning tool task: %w", err)
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// LeaseToolTask claims the oldest queued task; ErrNotFound when idle.
// A crashed worker's lease expires and the task re-runs, so task
// execution must tolerate a duplicate attempt.
func (d *DB) LeaseToolTask(ctx context.Context, nowNS, leaseNS int64, maxAttempts int) (ToolTask, error) {
	row := d.w.QueryRowContext(ctx, `
		UPDATE tool_tasks SET lease_until_ns = ? + ?, attempts = attempts + 1, state = 'running'
		WHERE id = (
			SELECT id FROM tool_tasks
			WHERE state IN ('queued', 'running') AND lease_until_ns < ? AND attempts < ?
			ORDER BY created_at_ns, id LIMIT 1
		)
		RETURNING `+taskCols,
		nowNS, leaseNS, nowNS, maxAttempts)
	t, err := scanTask(row)
	if errors.Is(err, sql.ErrNoRows) {
		return ToolTask{}, ErrNotFound
	}
	if err != nil {
		return ToolTask{}, fmt.Errorf("db: leasing tool task: %w", err)
	}
	return t, nil
}

// RenewToolTaskLease extends a running task's lease while long engine
// jobs poll.
func (d *DB) RenewToolTaskLease(ctx context.Context, id string, untilNS int64) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE tool_tasks SET lease_until_ns = ? WHERE id = ?`, untilNS, id)
	if err != nil {
		return fmt.Errorf("db: renewing tool task lease: %w", err)
	}
	return nil
}

// FailExhaustedToolTasks marks tasks out of attempts as failed and
// returns their ids for event fan-out.
func (d *DB) FailExhaustedToolTasks(ctx context.Context, nowNS int64, maxAttempts int) ([]string, error) {
	rows, err := d.w.QueryContext(ctx, `
		UPDATE tool_tasks SET state = 'failed', error = 'gave up after repeated attempts', finished_at_ns = ?
		WHERE state IN ('queued', 'running') AND lease_until_ns < ? AND attempts >= ?
		RETURNING id`, nowNS, nowNS, maxAttempts)
	if err != nil {
		return nil, fmt.Errorf("db: failing exhausted tool tasks: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("db: scanning exhausted tool task: %w", err)
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

// UpdateToolTaskParams rewrites a task's params document (credential
// scrubbing after a terminal state).
func (d *DB) UpdateToolTaskParams(ctx context.Context, id, params string) error {
	_, err := d.w.ExecContext(ctx, `UPDATE tool_tasks SET params = ? WHERE id = ?`, params, id)
	if err != nil {
		return fmt.Errorf("db: updating tool task params: %w", err)
	}
	return nil
}
