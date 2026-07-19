package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// FeedState is the refresh scheduler's per-feed accounting. The catalog
// keeps validators (ETag, Last-Modified) but no failure state; this row
// is what auto-disable reads.
type FeedState struct {
	ShowPID             string
	ConsecutiveFailures int
	Disabled            bool
	LastError           string
	LastAttemptNS       int64
	LastSyncedNS        int64
}

// FeedStateFor reads one show's refresh state; a zero row when the show
// was never synced by the scheduler.
func (d *DB) FeedStateFor(ctx context.Context, showPID string) (FeedState, error) {
	var st FeedState
	var disabled int64
	err := d.r.QueryRowContext(ctx, `
		SELECT show_pid, consecutive_failures, disabled, last_error, last_attempt_ns, last_synced_ns
		FROM feed_state WHERE show_pid = ?`, showPID).
		Scan(&st.ShowPID, &st.ConsecutiveFailures, &disabled, &st.LastError, &st.LastAttemptNS, &st.LastSyncedNS)
	if errors.Is(err, sql.ErrNoRows) {
		return FeedState{ShowPID: showPID}, nil
	}
	if err != nil {
		return FeedState{}, fmt.Errorf("db: reading feed state: %w", err)
	}
	st.Disabled = disabled != 0
	return st, nil
}

// RecordFeedSuccess resets failure accounting after a sync that worked
// (which also re-enables a disabled feed; a successful manual refresh
// is the recovery path).
func (d *DB) RecordFeedSuccess(ctx context.Context, showPID string, ns int64) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO feed_state (show_pid, consecutive_failures, disabled, last_error, last_attempt_ns, last_synced_ns)
		VALUES (?, 0, 0, '', ?, ?)
		ON CONFLICT (show_pid) DO UPDATE SET
			consecutive_failures = 0,
			disabled = 0,
			last_error = '',
			last_attempt_ns = excluded.last_attempt_ns,
			last_synced_ns = excluded.last_synced_ns`,
		showPID, ns, ns)
	if err != nil {
		return fmt.Errorf("db: recording feed success: %w", err)
	}
	return nil
}

// RecordFeedFailure bumps the failure counter and disables the feed
// once it reaches disableAfter. Returns the updated state.
func (d *DB) RecordFeedFailure(ctx context.Context, showPID, msg string, ns int64, disableAfter int) (FeedState, error) {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO feed_state (show_pid, consecutive_failures, disabled, last_error, last_attempt_ns, last_synced_ns)
		VALUES (?, 1, CASE WHEN 1 >= ? THEN 1 ELSE 0 END, ?, ?, 0)
		ON CONFLICT (show_pid) DO UPDATE SET
			consecutive_failures = feed_state.consecutive_failures + 1,
			disabled = CASE WHEN feed_state.consecutive_failures + 1 >= ? THEN 1 ELSE feed_state.disabled END,
			last_error = excluded.last_error,
			last_attempt_ns = excluded.last_attempt_ns`,
		showPID, disableAfter, msg, ns, disableAfter)
	if err != nil {
		return FeedState{}, fmt.Errorf("db: recording feed failure: %w", err)
	}
	return d.feedStateWrite(ctx, showPID)
}

// feedStateWrite reads through the write connection, so a state written
// a statement ago is visible regardless of read-pool snapshot timing.
func (d *DB) feedStateWrite(ctx context.Context, showPID string) (FeedState, error) {
	var st FeedState
	var disabled int64
	err := d.w.QueryRowContext(ctx, `
		SELECT show_pid, consecutive_failures, disabled, last_error, last_attempt_ns, last_synced_ns
		FROM feed_state WHERE show_pid = ?`, showPID).
		Scan(&st.ShowPID, &st.ConsecutiveFailures, &disabled, &st.LastError, &st.LastAttemptNS, &st.LastSyncedNS)
	if err != nil {
		return FeedState{}, fmt.Errorf("db: reading feed state: %w", err)
	}
	st.Disabled = disabled != 0
	return st, nil
}

// QueueRow is one leased unit of background work.
type QueueRow struct {
	Key      string
	ItemPID  string
	Attempts int
}

// EnqueueAnalysis queues silence and loudness analysis for one audio
// essence; queuing an already queued essence is a no-op.
func (d *DB) EnqueueAnalysis(ctx context.Context, essenceHash, itemPID string, ns int64) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO analysis_queue (essence_hash, item_pid, enqueued_at_ns)
		VALUES (?, ?, ?)
		ON CONFLICT (essence_hash) DO NOTHING`,
		essenceHash, itemPID, ns)
	if err != nil {
		return fmt.Errorf("db: queuing analysis: %w", err)
	}
	return nil
}

// LeaseAnalysis claims the oldest lease-free analysis row for leaseNS
// nanoseconds; ErrNotFound when the queue is idle. Rows past
// maxAttempts are skipped (and swept by FailAnalysis callers).
func (d *DB) LeaseAnalysis(ctx context.Context, nowNS, leaseNS int64, maxAttempts int) (QueueRow, error) {
	return d.leaseQueue(ctx, "analysis_queue", "essence_hash", nowNS, leaseNS, maxAttempts)
}

// CompleteAnalysis removes a finished analysis row.
func (d *DB) CompleteAnalysis(ctx context.Context, essenceHash string) error {
	_, err := d.w.ExecContext(ctx, `DELETE FROM analysis_queue WHERE essence_hash = ?`, essenceHash)
	if err != nil {
		return fmt.Errorf("db: completing analysis: %w", err)
	}
	return nil
}

// FailAnalysis records a failed attempt; the row stays leased until
// retryAtNS, which is what makes the caller's backoff real (a zero
// lease would hand the oldest, just-failed row straight back to the
// next drain pass).
func (d *DB) FailAnalysis(ctx context.Context, essenceHash, msg string, retryAtNS int64) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE analysis_queue SET attempts = attempts + 1, lease_until_ns = ?, last_error = ?
		WHERE essence_hash = ?`, retryAtNS, msg, essenceHash)
	if err != nil {
		return fmt.Errorf("db: failing analysis: %w", err)
	}
	return nil
}

// EnqueueFetch queues a server-side enclosure download for one episode;
// queuing an already queued episode is a no-op.
func (d *DB) EnqueueFetch(ctx context.Context, episodePID, requestedBy string, ns int64) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO fetch_queue (episode_pid, requested_by, enqueued_at_ns)
		VALUES (?, ?, ?)
		ON CONFLICT (episode_pid) DO NOTHING`,
		episodePID, requestedBy, ns)
	if err != nil {
		return fmt.Errorf("db: queuing fetch: %w", err)
	}
	return nil
}

// LeaseFetch claims the oldest lease-free fetch row.
func (d *DB) LeaseFetch(ctx context.Context, nowNS, leaseNS int64, maxAttempts int) (QueueRow, error) {
	return d.leaseQueue(ctx, "fetch_queue", "episode_pid", nowNS, leaseNS, maxAttempts)
}

// CompleteFetch removes a finished fetch row.
func (d *DB) CompleteFetch(ctx context.Context, episodePID string) error {
	_, err := d.w.ExecContext(ctx, `DELETE FROM fetch_queue WHERE episode_pid = ?`, episodePID)
	if err != nil {
		return fmt.Errorf("db: completing fetch: %w", err)
	}
	return nil
}

// FailFetch records a failed attempt; the row stays leased until
// retryAtNS so retries never hammer a failing host back-to-back.
func (d *DB) FailFetch(ctx context.Context, episodePID, msg string, retryAtNS int64) error {
	_, err := d.w.ExecContext(ctx, `
		UPDATE fetch_queue SET attempts = attempts + 1, lease_until_ns = ?, last_error = ?
		WHERE episode_pid = ?`, retryAtNS, msg, episodePID)
	if err != nil {
		return fmt.Errorf("db: failing fetch: %w", err)
	}
	return nil
}

// leaseQueue is the shared lease step: claim the oldest claimable row
// by writing its lease in the same statement that selects it, which the
// single write connection serializes. table and keyCol are compile-time
// constants at every call site, never user input.
func (d *DB) leaseQueue(ctx context.Context, table, keyCol string, nowNS, leaseNS int64, maxAttempts int) (QueueRow, error) {
	itemCol := "item_pid"
	if table == "fetch_queue" {
		itemCol = "''"
	}
	row := d.w.QueryRowContext(ctx, `
		UPDATE `+table+` SET lease_until_ns = ? + ?
		WHERE `+keyCol+` = (
			SELECT `+keyCol+` FROM `+table+`
			WHERE lease_until_ns < ? AND attempts < ?
			ORDER BY enqueued_at_ns LIMIT 1
		)
		RETURNING `+keyCol+`, `+itemCol+`, attempts`,
		nowNS, leaseNS, nowNS, maxAttempts)
	var q QueueRow
	if err := row.Scan(&q.Key, &q.ItemPID, &q.Attempts); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return QueueRow{}, ErrNotFound
		}
		return QueueRow{}, fmt.Errorf("db: leasing from %s: %w", table, err)
	}
	return q, nil
}

// FetchQueueRow reads one episode's fetch-queue row; ErrNotFound when
// nothing is queued (the common case).
func (d *DB) FetchQueueRow(ctx context.Context, episodePID string) (attempts int, lastErr string, err error) {
	err = d.r.QueryRowContext(ctx, `
		SELECT attempts, last_error FROM fetch_queue WHERE episode_pid = ?`,
		episodePID).Scan(&attempts, &lastErr)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, "", ErrNotFound
	}
	if err != nil {
		return 0, "", fmt.Errorf("db: reading fetch queue row: %w", err)
	}
	return attempts, lastErr, nil
}

// EnqueueRetention marks one show for a retention re-evaluation.
func (d *DB) EnqueueRetention(ctx context.Context, showPID string, ns int64) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO retention_queue (show_pid, enqueued_at_ns) VALUES (?, ?)
		ON CONFLICT (show_pid) DO NOTHING`, showPID, ns)
	if err != nil {
		return fmt.Errorf("db: queuing retention: %w", err)
	}
	return nil
}

// TakeRetentionQueue drains and returns every queued show. A show whose
// sweep must defer (a file in use) is re-enqueued by the sweeper.
func (d *DB) TakeRetentionQueue(ctx context.Context) ([]string, error) {
	rows, err := d.w.QueryContext(ctx, `
		DELETE FROM retention_queue RETURNING show_pid`)
	if err != nil {
		return nil, fmt.Errorf("db: draining retention queue: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var pid string
		if err := rows.Scan(&pid); err != nil {
			return nil, fmt.Errorf("db: scanning retention row: %w", err)
		}
		out = append(out, pid)
	}
	return out, rows.Err()
}
