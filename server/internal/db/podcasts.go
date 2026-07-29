package db

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
)

// Subscription is one user's subscription to one globally cataloged
// show. Nullable settings columns distinguish "explicitly set" from
// "server default": a NULL always means the default applies.
type Subscription struct {
	UserID        string
	ShowPID       string
	Folder        string
	Private       bool
	RetentionKeep *int64
	AutoDownload  bool
	Speed         *float64
	TrimSilence   *bool
	VoiceBoost    *bool
	SkipIntroSec  *int64
	SkipOutroSec  *int64
	// AutoDLInclude and AutoDLExclude are the auto-download keyword
	// filter's title terms; nil or empty include admits everything.
	AutoDLInclude []string
	AutoDLExclude []string
	CreatedAtNS   int64
	UpdatedAtNS   int64
}

const subscriptionCols = `user_id, show_pid, folder, private, retention_keep,
	auto_download, speed, trim_silence, voice_boost, skip_intro_secs,
	skip_outro_secs, auto_dl_include, auto_dl_exclude,
	created_at_ns, updated_at_ns`

func scanSubscription(row interface{ Scan(...any) error }) (Subscription, error) {
	var s Subscription
	var private, autoDownload int64
	var trim, boost sql.NullInt64
	var include, exclude sql.NullString
	err := row.Scan(&s.UserID, &s.ShowPID, &s.Folder, &private, &s.RetentionKeep,
		&autoDownload, &s.Speed, &trim, &boost, &s.SkipIntroSec,
		&s.SkipOutroSec, &include, &exclude, &s.CreatedAtNS, &s.UpdatedAtNS)
	if err != nil {
		return Subscription{}, err
	}
	s.Private = private != 0
	s.AutoDownload = autoDownload != 0
	if trim.Valid {
		v := trim.Int64 != 0
		s.TrimSilence = &v
	}
	if boost.Valid {
		v := boost.Int64 != 0
		s.VoiceBoost = &v
	}
	s.AutoDLInclude = decodeTerms(include)
	s.AutoDLExclude = decodeTerms(exclude)
	return s, nil
}

// decodeTerms reads a JSON string array column. A row that somehow
// holds something else reads as unset rather than failing the whole
// subscription: a filter nobody can parse must not make a show
// unreadable.
func decodeTerms(col sql.NullString) []string {
	if !col.Valid || col.String == "" {
		return nil
	}
	var out []string
	if err := json.Unmarshal([]byte(col.String), &out); err != nil {
		return nil
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

// encodeTerms renders a term list for storage; empty stores NULL, so
// "no filter" is one representation rather than two.
func encodeTerms(terms []string) any {
	if len(terms) == 0 {
		return nil
	}
	raw, err := json.Marshal(terms)
	if err != nil {
		return nil
	}
	return string(raw)
}

func nullBool(b *bool) any {
	if b == nil {
		return nil
	}
	if *b {
		return int64(1)
	}
	return int64(0)
}

// UpsertSubscription creates or fully replaces one subscription row,
// preserving created_at_ns on replace.
func (d *DB) UpsertSubscription(ctx context.Context, s Subscription) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO podcast_subscriptions (`+subscriptionCols+`)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (user_id, show_pid) DO UPDATE SET
			folder = excluded.folder,
			private = excluded.private,
			retention_keep = excluded.retention_keep,
			auto_download = excluded.auto_download,
			speed = excluded.speed,
			trim_silence = excluded.trim_silence,
			voice_boost = excluded.voice_boost,
			skip_intro_secs = excluded.skip_intro_secs,
			skip_outro_secs = excluded.skip_outro_secs,
			auto_dl_include = excluded.auto_dl_include,
			auto_dl_exclude = excluded.auto_dl_exclude,
			updated_at_ns = excluded.updated_at_ns`,
		s.UserID, s.ShowPID, s.Folder, boolInt(s.Private), s.RetentionKeep,
		boolInt(s.AutoDownload), s.Speed, nullBool(s.TrimSilence),
		nullBool(s.VoiceBoost), s.SkipIntroSec, s.SkipOutroSec,
		encodeTerms(s.AutoDLInclude), encodeTerms(s.AutoDLExclude),
		s.CreatedAtNS, s.UpdatedAtNS)
	if err != nil {
		return fmt.Errorf("db: upserting subscription: %w", err)
	}
	return nil
}

// SubscriptionFor reads one (user, show) subscription; ErrNotFound when
// the user does not follow the show.
func (d *DB) SubscriptionFor(ctx context.Context, userID, showPID string) (Subscription, error) {
	row := d.r.QueryRowContext(ctx, `
		SELECT `+subscriptionCols+` FROM podcast_subscriptions
		WHERE user_id = ? AND show_pid = ?`, userID, showPID)
	s, err := scanSubscription(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Subscription{}, ErrNotFound
	}
	if err != nil {
		return Subscription{}, fmt.Errorf("db: reading subscription: %w", err)
	}
	return s, nil
}

// SubscriptionsByUser returns every subscription of one user. Ordering
// is by show PID; display ordering (show title) is the service's job,
// which holds the titles.
func (d *DB) SubscriptionsByUser(ctx context.Context, userID string) ([]Subscription, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT `+subscriptionCols+` FROM podcast_subscriptions
		WHERE user_id = ? ORDER BY show_pid`, userID)
	if err != nil {
		return nil, fmt.Errorf("db: listing subscriptions: %w", err)
	}
	defer rows.Close()
	var out []Subscription
	for rows.Next() {
		s, err := scanSubscription(rows)
		if err != nil {
			return nil, fmt.Errorf("db: scanning subscription: %w", err)
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// SubscribersByShow returns every user's subscription to one show (the
// retention union reads these).
func (d *DB) SubscribersByShow(ctx context.Context, showPID string) ([]Subscription, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT `+subscriptionCols+` FROM podcast_subscriptions
		WHERE show_pid = ? ORDER BY user_id`, showPID)
	if err != nil {
		return nil, fmt.Errorf("db: listing subscribers: %w", err)
	}
	defer rows.Close()
	var out []Subscription
	for rows.Next() {
		s, err := scanSubscription(rows)
		if err != nil {
			return nil, fmt.Errorf("db: scanning subscriber: %w", err)
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// DeleteSubscription removes one subscription; reports whether a row
// existed.
func (d *DB) DeleteSubscription(ctx context.Context, userID, showPID string) (bool, error) {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM podcast_subscriptions WHERE user_id = ? AND show_pid = ?`,
		userID, showPID)
	if err != nil {
		return false, fmt.Errorf("db: deleting subscription: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return false, fmt.Errorf("db: deleting subscription: %w", err)
	}
	return n > 0, nil
}

// SubscribedShowPIDs returns the distinct shows any user follows: the
// refresh scheduler's work list.
func (d *DB) SubscribedShowPIDs(ctx context.Context) ([]string, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT DISTINCT show_pid FROM podcast_subscriptions ORDER BY show_pid`)
	if err != nil {
		return nil, fmt.Errorf("db: listing subscribed shows: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var pid string
		if err := rows.Scan(&pid); err != nil {
			return nil, fmt.Errorf("db: scanning show pid: %w", err)
		}
		out = append(out, pid)
	}
	return out, rows.Err()
}

// BookSettings are one user's playback settings for one book; NULL
// means the server default.
type BookSettings struct {
	UserID      string
	BookPID     string
	Speed       *float64
	VoiceBoost  *bool
	TrimSilence *bool
	UpdatedAtNS int64
}

// PutBookSettings fully replaces one user's settings for one book.
func (d *DB) PutBookSettings(ctx context.Context, s BookSettings) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO book_settings (user_id, book_pid, speed, voice_boost, trim_silence, updated_at_ns)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT (user_id, book_pid) DO UPDATE SET
			speed = excluded.speed,
			voice_boost = excluded.voice_boost,
			trim_silence = excluded.trim_silence,
			updated_at_ns = excluded.updated_at_ns`,
		s.UserID, s.BookPID, s.Speed, nullBool(s.VoiceBoost),
		nullBool(s.TrimSilence), s.UpdatedAtNS)
	if err != nil {
		return fmt.Errorf("db: writing book settings: %w", err)
	}
	return nil
}

// BookSettingsFor reads one user's settings for one book; a zero row
// (all defaults) when never set.
func (d *DB) BookSettingsFor(ctx context.Context, userID, bookPID string) (BookSettings, error) {
	var s BookSettings
	var boost, trim sql.NullInt64
	err := d.r.QueryRowContext(ctx, `
		SELECT user_id, book_pid, speed, voice_boost, trim_silence, updated_at_ns
		FROM book_settings WHERE user_id = ? AND book_pid = ?`,
		userID, bookPID).Scan(&s.UserID, &s.BookPID, &s.Speed, &boost, &trim, &s.UpdatedAtNS)
	if errors.Is(err, sql.ErrNoRows) {
		return BookSettings{UserID: userID, BookPID: bookPID}, nil
	}
	if err != nil {
		return BookSettings{}, fmt.Errorf("db: reading book settings: %w", err)
	}
	if boost.Valid {
		v := boost.Int64 != 0
		s.VoiceBoost = &v
	}
	if trim.Valid {
		v := trim.Int64 != 0
		s.TrimSilence = &v
	}
	return s, nil
}
