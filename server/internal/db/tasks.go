package db

import (
	"context"
	"database/sql"
	"encoding/json"
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
	ItemTitle   string
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
	// LockKey is what the task holds while it is live (a book, a rip);
	// empty holds nothing. See InsertLockedToolTask.
	LockKey string
	// Resumable is set once the task's run must be finished whatever its
	// attempts say. See MarkToolTaskResumable.
	Resumable bool
	// LeaseUntilNS is when the task's lease runs out; written by the lease
	// calls, never by InsertToolTask's caller.
	LeaseUntilNS int64
	// WaitReason says why a running task waits to try again, at
	// LeaseUntilNS; empty when it does not. See DeferToolTask.
	WaitReason string
}

const taskCols = `id, type, state, item_pid, item_title, user_id, params, progress_pct,
	error, result_pids, summary, attempts, created_at_ns, finished_at_ns, lock_key, resumable, lease_until_ns, wait_reason`

func scanTask(row interface{ Scan(...any) error }) (ToolTask, error) {
	var t ToolTask
	err := row.Scan(&t.ID, &t.Type, &t.State, &t.ItemPID, &t.ItemTitle, &t.UserID, &t.Params,
		&t.ProgressPct, &t.Error, &t.ResultPIDs, &t.Summary, &t.Attempts, &t.CreatedAtNS, &t.FinishedAtNS,
		&t.LockKey, &t.Resumable, &t.LeaseUntilNS, &t.WaitReason)
	return t, err
}

// taskValues are a task's columns in taskCols order.
func taskValues(t ToolTask) []any {
	return []any{t.ID, t.Type, t.State, t.ItemPID, t.ItemTitle, t.UserID, t.Params, t.ProgressPct,
		t.Error, t.ResultPIDs, t.Summary, t.Attempts, t.CreatedAtNS, t.FinishedAtNS, t.LockKey, t.Resumable, t.LeaseUntilNS,
		t.WaitReason}
}

// InsertToolTask stores a new task.
func (d *DB) InsertToolTask(ctx context.Context, t ToolTask) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO tool_tasks (`+taskCols+`)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`, taskValues(t)...)
	if err != nil {
		return fmt.Errorf("db: inserting tool task: %w", err)
	}
	return nil
}

// InsertLockedToolTask stores a new task unless a queued, running or
// parked one holds its lock key, in one statement, so two requests cannot
// both find the key free. It answers the id of the task holding the key, or "" when
// this one was stored.
func (d *DB) InsertLockedToolTask(ctx context.Context, t ToolTask) (string, error) {
	res, err := d.w.ExecContext(ctx, `
		INSERT INTO tool_tasks (`+taskCols+`)
		SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
		WHERE NOT EXISTS (
			SELECT 1 FROM tool_tasks
			WHERE lock_key = ? AND lock_key <> '' AND state IN ('queued', 'running', 'parked')
		)`, append(taskValues(t), t.LockKey)...)
	if err != nil {
		return "", fmt.Errorf("db: inserting tool task: %w", err)
	}
	if n, _ := res.RowsAffected(); n > 0 {
		return "", nil
	}
	held, err := d.ToolTaskHolding(ctx, t.LockKey)
	if err == nil && held == "" {
		// The holder ended between the two statements; the caller may
		// queue again.
		err = fmt.Errorf("the task holding %s ended as this one was refused", t.LockKey)
	}
	if err != nil {
		return "", fmt.Errorf("db: inserting tool task: %w", err)
	}
	return held, nil
}

// ToolTaskHolding answers the id of the queued, running or parked task
// holding lockKey, or "" for none.
func (d *DB) ToolTaskHolding(ctx context.Context, lockKey string) (string, error) {
	if lockKey == "" {
		return "", nil
	}
	var held string
	err := d.w.QueryRowContext(ctx, `
		SELECT id FROM tool_tasks
		WHERE lock_key = ? AND state IN ('queued', 'running', 'parked')
		ORDER BY created_at_ns LIMIT 1`, lockKey).Scan(&held)
	if errors.Is(err, sql.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("db: reading the task holding %s: %w", lockKey, err)
	}
	return held, nil
}

// InsertHealthFixTask inserts a health-fix task unless its rule is being
// fixed already, by a queued or running task or by a pass whose origin
// stands, and reports whether it did. One statement, so two requests
// cannot both find the rule free.
func (d *DB) InsertHealthFixTask(ctx context.Context, t ToolTask, rule string) (bool, error) {
	res, err := d.w.ExecContext(ctx, `
		INSERT INTO tool_tasks (`+taskCols+`)
		SELECT ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
		WHERE NOT EXISTS (
			SELECT 1 FROM tool_tasks WHERE type = ? AND state IN ('queued', 'running')
				AND json_extract(params, '$.rule') = ?)
		AND NOT EXISTS (SELECT 1 FROM job_origins WHERE rule = ?)`,
		append(taskValues(t), t.Type, rule, rule)...)
	if err != nil {
		return false, fmt.Errorf("db: inserting health fix task: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("db: inserting health fix task: %w", err)
	}
	return n == 1, nil
}

// ActiveToolTask finds a queued or running task of one type over one
// item; ErrNotFound when none is in flight. It is the dedupe read that
// keeps a sync-now and the sweeper from queuing the same run twice.
func (d *DB) ActiveToolTask(ctx context.Context, typ, itemPID string) (ToolTask, error) {
	t, err := scanTask(d.r.QueryRowContext(ctx, `
		SELECT `+taskCols+` FROM tool_tasks
		WHERE type = ? AND item_pid = ? AND state IN ('queued', 'running')
		ORDER BY created_at_ns LIMIT 1`, typ, itemPID))
	if errors.Is(err, sql.ErrNoRows) {
		return ToolTask{}, ErrNotFound
	}
	if err != nil {
		return ToolTask{}, fmt.Errorf("db: reading active tool task: %w", err)
	}
	return t, nil
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

// TaskTypes narrows a lease to one task type, or to every type but one,
// so a worker can keep to its own share of the queue.
type TaskTypes struct {
	Only, Except string
}

// LeaseToolTask claims the oldest queued task of types; ErrNotFound when
// idle. A crashed worker's lease expires and the task re-runs, so task
// execution must tolerate a duplicate attempt. A resumable task is
// claimed whatever its attempts.
func (d *DB) LeaseToolTask(ctx context.Context, nowNS, leaseNS int64, maxAttempts int, types TaskTypes) (ToolTask, error) {
	row := d.w.QueryRowContext(ctx, `
		UPDATE tool_tasks SET lease_until_ns = ? + ?, attempts = attempts + 1, state = 'running',
			error = '', wait_reason = ''
		WHERE id = (
			SELECT id FROM tool_tasks
			WHERE state IN ('queued', 'running') AND lease_until_ns < ? AND (attempts < ? OR resumable = 1)
				AND (? = '' OR type = ?) AND (? = '' OR type <> ?)
			ORDER BY created_at_ns, id LIMIT 1
		)
		RETURNING `+taskCols,
		nowNS, leaseNS, nowNS, maxAttempts, types.Only, types.Only, types.Except, types.Except)
	t, err := scanTask(row)
	if errors.Is(err, sql.ErrNoRows) {
		return ToolTask{}, ErrNotFound
	}
	if err != nil {
		return ToolTask{}, fmt.Errorf("db: leasing tool task: %w", err)
	}
	return t, nil
}

// ActiveToolTaskRules lists the `rule` param of every queued or running
// task of type typ: the rules a health-fix task is fixing.
func (d *DB) ActiveToolTaskRules(ctx context.Context, typ string) ([]string, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT DISTINCT json_extract(params, '$.rule') FROM tool_tasks
		WHERE type = ? AND state IN ('queued', 'running')
			AND json_extract(params, '$.rule') IS NOT NULL`, typ)
	if err != nil {
		return nil, fmt.Errorf("db: listing active task rules: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var rule string
		if err := rows.Scan(&rule); err != nil {
			return nil, fmt.Errorf("db: scanning active task rule: %w", err)
		}
		out = append(out, rule)
	}
	return out, rows.Err()
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
// returns their ids for event fan-out. It leaves a resumable task, and
// every task in held: those a run in this process is working, whatever
// their leases say.
func (d *DB) FailExhaustedToolTasks(ctx context.Context, nowNS int64, maxAttempts int, held []string) ([]string, error) {
	heldJSON, err := json.Marshal(append([]string{}, held...))
	if err != nil {
		return nil, fmt.Errorf("db: failing exhausted tool tasks: %w", err)
	}
	rows, err := d.w.QueryContext(ctx, `
		UPDATE tool_tasks SET state = 'failed', error = 'gave up after repeated attempts', finished_at_ns = ?
		WHERE state IN ('queued', 'running') AND lease_until_ns < ? AND attempts >= ? AND resumable = 0
			AND id NOT IN (SELECT value FROM json_each(?))
		RETURNING id`, nowNS, nowNS, maxAttempts, string(heldJSON))
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

// DeleteToolTask removes one task, but only in a terminal state: the
// guard lives in the statement so a worker leasing the row between a
// caller's read and this delete cannot lose it mid-run. ownerID scopes
// the delete to that user's rows; empty deletes anyone's
// (administrators), the same convention ListToolTasks uses. In the
// statement rather than left to the caller's visibility check, so a
// future call site that skips the check still cannot delete another
// account's row. False when nothing went - no such row, not terminal,
// or not the owner's.
func (d *DB) DeleteToolTask(ctx context.Context, id, ownerID string) (bool, error) {
	q := `DELETE FROM tool_tasks WHERE id = ? AND state IN ('done', 'failed', 'parked')`
	args := []any{id}
	if ownerID != "" {
		q += ` AND user_id = ?`
		args = append(args, ownerID)
	}
	res, err := d.w.ExecContext(ctx, q, args...)
	if err != nil {
		return false, fmt.Errorf("db: deleting tool task: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("db: deleting tool task: %w", err)
	}
	return n > 0, nil
}

// FinishedToolTasks answers the terminal tasks a user owns, or every
// account's when everyone is set, and with finishedBeforeNS set only those
// that finished before it. An empty userID without everyone answers
// nothing, so a caller that lost the id cannot sweep the table.
func (d *DB) FinishedToolTasks(ctx context.Context, userID string, everyone bool, finishedBeforeNS int64) ([]ToolTask, error) {
	q := `SELECT ` + taskCols + ` FROM tool_tasks WHERE state IN ('done', 'failed', 'parked')`
	args := []any{}
	switch {
	case everyone:
	case userID != "":
		q += ` AND user_id = ?`
		args = append(args, userID)
	default:
		return nil, nil
	}
	if finishedBeforeNS > 0 {
		q += ` AND finished_at_ns < ?`
		args = append(args, finishedBeforeNS)
	}
	rows, err := d.w.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("db: listing finished tool tasks: %w", err)
	}
	defer rows.Close()
	var out []ToolTask
	for rows.Next() {
		t, err := scanTask(rows)
		if err != nil {
			return nil, fmt.Errorf("db: listing finished tool tasks: %w", err)
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// DeleteToolTasksByID removes the named tasks that are terminal, in one
// statement, so all go or none do, and reports how many went.
func (d *DB) DeleteToolTasksByID(ctx context.Context, ids []string) (int, error) {
	if len(ids) == 0 {
		return 0, nil
	}
	idsJSON, err := json.Marshal(ids)
	if err != nil {
		return 0, fmt.Errorf("db: clearing finished tool tasks: %w", err)
	}
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM tool_tasks
		WHERE id IN (SELECT value FROM json_each(?)) AND state IN ('done', 'failed', 'parked')`, string(idsJSON))
	if err != nil {
		return 0, fmt.Errorf("db: clearing finished tool tasks: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return 0, fmt.Errorf("db: clearing finished tool tasks: %w", err)
	}
	return int(n), nil
}

// MarkToolTaskResumable records that a task's run must be finished
// whatever its attempts: the lease takes it past the cap and the retire
// pass leaves it.
func (d *DB) MarkToolTaskResumable(ctx context.Context, id string) error {
	if _, err := d.w.ExecContext(ctx, `UPDATE tool_tasks SET resumable = 1 WHERE id = ?`, id); err != nil {
		return fmt.Errorf("db: marking tool task resumable: %w", err)
	}
	return nil
}

// DeferToolTask hands a running task back until untilNS without counting
// the attempt that deferred it, saying why in its error and, by a reason
// a client words, in its wait reason. The next lease clears both.
func (d *DB) DeferToolTask(ctx context.Context, id string, untilNS int64, why, reason string) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE tool_tasks SET lease_until_ns = ?, attempts = MAX(attempts - 1, 0), error = ?, wait_reason = ?
		WHERE id = ? AND state = 'running'`, untilNS, why, reason, id)
	if err != nil {
		return fmt.Errorf("db: deferring tool task: %w", err)
	}
	return nil
}

// ParkToolTask stops a running task for good, finished at atNS: it is
// not leased again, says why in its error, and keeps its lock until it is
// cleared as any finished task is (deleted, swept, or pruned).
func (d *DB) ParkToolTask(ctx context.Context, id, why string, atNS int64) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE tool_tasks SET state = 'parked', error = ?, wait_reason = '', finished_at_ns = ?
		WHERE id = ? AND state = 'running'`, why, atNS, id)
	if err != nil {
		return fmt.Errorf("db: parking tool task: %w", err)
	}
	return nil
}

// HoldFinishedToolTask turns a failed task into a parked one, which holds
// its lock until it is cleared: a task whose clear could not settle what
// it left in the library.
func (d *DB) HoldFinishedToolTask(ctx context.Context, id string) error {
	if _, err := d.w.ExecContext(ctx, `UPDATE tool_tasks SET state = 'parked' WHERE id = ? AND state = 'failed'`, id); err != nil {
		return fmt.Errorf("db: holding a finished tool task: %w", err)
	}
	return nil
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
