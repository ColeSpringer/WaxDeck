// Package db owns waxdeck.db: WaxDeck's own state beside (never inside)
// the WaxBin catalog. One dedicated write connection and a small read
// pool, WAL with synchronous=NORMAL, and a busy timeout as
// belt-and-braces; intra-process SQLITE_BUSY is structurally avoided
// rather than retried.
package db

import (
	"context"
	"database/sql"
	"fmt"

	_ "modernc.org/sqlite"
)

// DB is the open database pair: w serializes every write, r serves
// concurrent reads.
type DB struct {
	w *sql.DB
	r *sql.DB
}

// migrations are applied in order; user_version tracks the last applied
// index + 1. Migrations are append-only.
var migrations = []string{
	`CREATE TABLE listen_sessions (
		id            INTEGER PRIMARY KEY,
		user_id       TEXT    NOT NULL,
		session_id    TEXT    NOT NULL,
		item_pid      TEXT    NOT NULL,
		media_type    TEXT    NOT NULL,
		started_at_ns INTEGER NOT NULL,
		ms_played     INTEGER NOT NULL,
		finished      INTEGER NOT NULL DEFAULT 0,
		client        TEXT    NOT NULL DEFAULT '',
		source        TEXT    NOT NULL DEFAULT 'live',
		received_at_ns INTEGER NOT NULL,
		UNIQUE (user_id, session_id)
	);
	CREATE INDEX listen_sessions_by_item ON listen_sessions (user_id, item_pid, started_at_ns);`,

	// Accounts, sessions, and per-user server state. The catalog user
	// (waxbin_user_pid) is created at provisioning; WaxDeck is the sole
	// identity authority and WaxBin stores no credentials. username_ci
	// carries the case-insensitive uniqueness the login path matches on.
	`CREATE TABLE users (
		id             TEXT    PRIMARY KEY,
		username       TEXT    NOT NULL,
		username_ci    TEXT    NOT NULL UNIQUE,
		display_name   TEXT    NOT NULL DEFAULT '',
		password_hash  TEXT    NOT NULL DEFAULT '',
		roles          TEXT    NOT NULL DEFAULT 'user',
		disabled       INTEGER NOT NULL DEFAULT 0,
		library_access TEXT    NOT NULL DEFAULT 'all',
		waxbin_user_pid TEXT   NOT NULL,
		created_at_ns  INTEGER NOT NULL,
		updated_at_ns  INTEGER NOT NULL
	);
	CREATE TABLE identities (
		id            INTEGER PRIMARY KEY,
		user_id       TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		provider      TEXT    NOT NULL,
		subject       TEXT    NOT NULL,
		email         TEXT    NOT NULL DEFAULT '',
		created_at_ns INTEGER NOT NULL,
		UNIQUE (provider, subject)
	);
	CREATE INDEX identities_by_user ON identities (user_id);
	CREATE TABLE sessions (
		id              TEXT    PRIMARY KEY,
		user_id         TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		kind            TEXT    NOT NULL,
		token_hash      BLOB    NOT NULL UNIQUE,
		prev_token_hash BLOB,
		rotated_at_ns   INTEGER NOT NULL DEFAULT 0,
		csrf_token      TEXT    NOT NULL,
		device_name     TEXT    NOT NULL DEFAULT '',
		client          TEXT    NOT NULL DEFAULT '',
		created_at_ns   INTEGER NOT NULL,
		last_seen_ns    INTEGER NOT NULL,
		expires_at_ns   INTEGER NOT NULL
	);
	CREATE INDEX sessions_by_user ON sessions (user_id, created_at_ns);
	CREATE INDEX sessions_by_prev ON sessions (prev_token_hash) WHERE prev_token_hash IS NOT NULL;
	CREATE TABLE library_grants (
		user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		library_pid TEXT NOT NULL,
		PRIMARY KEY (user_id, library_pid)
	);
	CREATE TABLE prefs (
		user_id       TEXT    PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
		json          TEXT    NOT NULL,
		updated_at_ns INTEGER NOT NULL
	);
	CREATE TABLE oauth_state (
		state         TEXT    PRIMARY KEY,
		provider      TEXT    NOT NULL,
		mode          TEXT    NOT NULL,
		code_verifier TEXT    NOT NULL,
		redirect_uri  TEXT    NOT NULL,
		redirect_to   TEXT    NOT NULL DEFAULT '',
		challenge     TEXT    NOT NULL DEFAULT '',
		loopback_port INTEGER NOT NULL DEFAULT 0,
		created_at_ns INTEGER NOT NULL,
		expires_at_ns INTEGER NOT NULL
	);
	CREATE TABLE oidc_codes (
		code_hash     BLOB    PRIMARY KEY,
		user_id       TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		challenge     TEXT    NOT NULL DEFAULT '',
		created_at_ns INTEGER NOT NULL,
		expires_at_ns INTEGER NOT NULL
	);`,

	// Sync and compatibility-API state. event_log is the server change
	// stream (the serverSeq cursor): one row per user-scoped state
	// change, written by the sole writer (the service) at mutation time.
	// play_state_stamps carry the per-field change times offline replay
	// reconciliation compares against; WaxBin's play_state row has only
	// one UpdatedAt, which position checkpoints bump constantly.
	// sync_state is a small key-value table for stream generations,
	// floors, cursors, and per-user grant epochs. app_passwords hold the
	// recoverable per-client secrets the Subsonic scheme demands,
	// sealed with the server key; secret_hash serves apiKey lookup.
	`CREATE TABLE event_log (
		id            INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id       TEXT    NOT NULL,
		kind          TEXT    NOT NULL,
		item_pid      TEXT    NOT NULL DEFAULT '',
		created_at_ns INTEGER NOT NULL
	);
	CREATE INDEX event_log_by_user ON event_log (user_id, id);
	CREATE TABLE play_state_stamps (
		user_id     TEXT    NOT NULL,
		item_pid    TEXT    NOT NULL,
		position_ns INTEGER NOT NULL DEFAULT 0,
		star_ns     INTEGER NOT NULL DEFAULT 0,
		rating_ns   INTEGER NOT NULL DEFAULT 0,
		PRIMARY KEY (user_id, item_pid)
	);
	CREATE TABLE sync_state (
		key   TEXT PRIMARY KEY,
		value TEXT NOT NULL
	);
	CREATE TABLE app_passwords (
		id            TEXT    PRIMARY KEY,
		user_id       TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		label         TEXT    NOT NULL,
		secret_enc    BLOB    NOT NULL,
		secret_hash   BLOB    NOT NULL UNIQUE,
		created_at_ns INTEGER NOT NULL,
		last_used_ns  INTEGER NOT NULL DEFAULT 0
	);
	CREATE INDEX app_passwords_by_user ON app_passwords (user_id, created_at_ns);`,

	// Podcasts and audiobooks. Shows, episodes, and files are cataloged
	// globally in waxbin.db; everything per user lives here. NULL in a
	// settings column always means "server default", which is distinct
	// from an explicit 0 or false. Retention resolves across a show's
	// subscribers as the most generous union, so sweeps read
	// podcast_subscriptions by show. feed_state carries the refresh
	// scheduler's per-feed failure accounting (the catalog keeps none).
	// silence_maps cache the streaming sidecar's silence analysis keyed
	// by audio essence, so retags and moves never invalidate a map but a
	// re-encode or a detector revision does. The three queue tables are
	// durable work queues drained by supervised workers with row leases;
	// the gpodder tables serve the compatibility adapter, whose protocol
	// speaks feed URLs and epoch seconds.
	`CREATE TABLE podcast_subscriptions (
		user_id          TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		show_pid         TEXT    NOT NULL,
		folder           TEXT    NOT NULL DEFAULT '',
		private          INTEGER NOT NULL DEFAULT 0,
		retention_keep   INTEGER,
		auto_download    INTEGER NOT NULL DEFAULT 0,
		speed            REAL,
		trim_silence     INTEGER,
		voice_boost      INTEGER,
		skip_intro_secs  INTEGER,
		skip_outro_secs  INTEGER,
		created_at_ns    INTEGER NOT NULL,
		updated_at_ns    INTEGER NOT NULL,
		PRIMARY KEY (user_id, show_pid)
	);
	CREATE INDEX podcast_subscriptions_by_show ON podcast_subscriptions (show_pid);
	CREATE TABLE book_settings (
		user_id       TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		book_pid      TEXT    NOT NULL,
		speed         REAL,
		voice_boost   INTEGER,
		trim_silence  INTEGER,
		updated_at_ns INTEGER NOT NULL,
		PRIMARY KEY (user_id, book_pid)
	);
	CREATE TABLE feed_state (
		show_pid             TEXT    PRIMARY KEY,
		consecutive_failures INTEGER NOT NULL DEFAULT 0,
		disabled             INTEGER NOT NULL DEFAULT 0,
		last_error           TEXT    NOT NULL DEFAULT '',
		last_attempt_ns      INTEGER NOT NULL DEFAULT 0,
		last_synced_ns       INTEGER NOT NULL DEFAULT 0
	);
	CREATE TABLE silence_maps (
		essence_hash     TEXT    PRIMARY KEY,
		detector_version TEXT    NOT NULL,
		threshold_db     REAL    NOT NULL,
		min_seconds      REAL    NOT NULL,
		spans            TEXT    NOT NULL,
		duration_ms      INTEGER NOT NULL DEFAULT 0,
		integrated_lufs  REAL,
		true_peak_db     REAL,
		created_at_ns    INTEGER NOT NULL
	);
	CREATE TABLE analysis_queue (
		essence_hash   TEXT    PRIMARY KEY,
		item_pid       TEXT    NOT NULL,
		enqueued_at_ns INTEGER NOT NULL,
		attempts       INTEGER NOT NULL DEFAULT 0,
		lease_until_ns INTEGER NOT NULL DEFAULT 0,
		last_error     TEXT    NOT NULL DEFAULT ''
	);
	CREATE TABLE fetch_queue (
		episode_pid    TEXT    PRIMARY KEY,
		requested_by   TEXT    NOT NULL DEFAULT '',
		enqueued_at_ns INTEGER NOT NULL,
		attempts       INTEGER NOT NULL DEFAULT 0,
		lease_until_ns INTEGER NOT NULL DEFAULT 0,
		last_error     TEXT    NOT NULL DEFAULT ''
	);
	CREATE TABLE retention_queue (
		show_pid       TEXT    PRIMARY KEY,
		enqueued_at_ns INTEGER NOT NULL
	);
	CREATE TABLE transcript_cache (
		episode_pid   TEXT    PRIMARY KEY,
		format        TEXT    NOT NULL DEFAULT '',
		cues          TEXT    NOT NULL DEFAULT '',
		negative      INTEGER NOT NULL DEFAULT 0,
		fetched_at_ns INTEGER NOT NULL
	);
	CREATE TABLE gpodder_devices (
		user_id       TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		device_id     TEXT    NOT NULL,
		caption       TEXT    NOT NULL DEFAULT '',
		type          TEXT    NOT NULL DEFAULT 'other',
		created_at_ns INTEGER NOT NULL,
		updated_at_ns INTEGER NOT NULL,
		PRIMARY KEY (user_id, device_id)
	);
	CREATE TABLE gpodder_sub_events (
		id        INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id   TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		feed_url  TEXT    NOT NULL,
		action    TEXT    NOT NULL,
		device_id TEXT    NOT NULL DEFAULT '',
		ts_sec    INTEGER NOT NULL
	);
	CREATE INDEX gpodder_sub_events_by_user ON gpodder_sub_events (user_id, id);
	CREATE TABLE gpodder_actions (
		id           INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id      TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		podcast_url  TEXT    NOT NULL,
		episode_url  TEXT    NOT NULL,
		device_id    TEXT    NOT NULL DEFAULT '',
		action       TEXT    NOT NULL,
		action_ts    TEXT    NOT NULL DEFAULT '',
		started_sec  INTEGER,
		position_sec INTEGER,
		total_sec    INTEGER,
		uploaded_sec INTEGER NOT NULL
	);
	CREATE INDEX gpodder_actions_by_user ON gpodder_actions (user_id, id);`,

	// 5: internet radio stations, scrobbling connections and their durable
	// delivery queue, the notification outbox, UnifiedPush registrations,
	// and a small settings store for runtime-editable server configuration.
	`CREATE TABLE radio_stations (
		id            TEXT    PRIMARY KEY,
		name          TEXT    NOT NULL,
		stream_url    TEXT    NOT NULL UNIQUE,
		homepage_url  TEXT    NOT NULL DEFAULT '',
		logo_url      TEXT    NOT NULL DEFAULT '',
		created_by    TEXT    NOT NULL DEFAULT '',
		created_at_ns INTEGER NOT NULL
	);
	CREATE TABLE scrobble_connections (
		user_id            TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		service            TEXT    NOT NULL,
		sealed_secret      BLOB    NOT NULL,
		username           TEXT    NOT NULL DEFAULT '',
		api_url            TEXT    NOT NULL DEFAULT '',
		created_at_ns      INTEGER NOT NULL,
		updated_at_ns      INTEGER NOT NULL,
		last_success_at_ns INTEGER NOT NULL DEFAULT 0,
		last_error         TEXT    NOT NULL DEFAULT '',
		last_error_at_ns   INTEGER NOT NULL DEFAULT 0,
		PRIMARY KEY (user_id, service)
	);
	CREATE TABLE scrobble_outbox (
		id             INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id        TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		service        TEXT    NOT NULL,
		item_pid       TEXT    NOT NULL,
		artist         TEXT    NOT NULL DEFAULT '',
		title          TEXT    NOT NULL DEFAULT '',
		album          TEXT    NOT NULL DEFAULT '',
		duration_ms    INTEGER NOT NULL DEFAULT 0,
		listened_at_ns INTEGER NOT NULL,
		enqueued_at_ns INTEGER NOT NULL,
		attempts       INTEGER NOT NULL DEFAULT 0,
		lease_until_ns INTEGER NOT NULL DEFAULT 0,
		last_error     TEXT    NOT NULL DEFAULT ''
	);
	CREATE INDEX scrobble_outbox_ready ON scrobble_outbox (lease_until_ns, enqueued_at_ns);
	CREATE TABLE notify_outbox (
		id             INTEGER PRIMARY KEY AUTOINCREMENT,
		kind           TEXT    NOT NULL,
		event          TEXT    NOT NULL,
		target         TEXT    NOT NULL DEFAULT '',
		title          TEXT    NOT NULL DEFAULT '',
		body           TEXT    NOT NULL DEFAULT '',
		enqueued_at_ns INTEGER NOT NULL,
		attempts       INTEGER NOT NULL DEFAULT 0,
		lease_until_ns INTEGER NOT NULL DEFAULT 0,
		last_error     TEXT    NOT NULL DEFAULT ''
	);
	CREATE INDEX notify_outbox_ready ON notify_outbox (lease_until_ns, enqueued_at_ns);
	CREATE TABLE push_registrations (
		id            TEXT    PRIMARY KEY,
		user_id       TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		endpoint      TEXT    NOT NULL,
		label         TEXT    NOT NULL DEFAULT '',
		created_at_ns INTEGER NOT NULL,
		UNIQUE (user_id, endpoint)
	);
	CREATE TABLE settings (
		key        TEXT PRIMARY KEY,
		value      TEXT NOT NULL,
		updated_at_ns INTEGER NOT NULL
	);`,

	// Player endpoints and playback sessions. Device endpoints (cast,
	// DLNA, jukebox) persist across discovery sweeps under a stable
	// per-device key; client endpoints live only as long as their
	// WebSocket and are never written here. Session rows are the crash
	// and restore record of the in-memory session manager: the live
	// truth is in memory, rows carry the last checkpointed state, and
	// ended sessions keep their final row as queue-restore history
	// until pruned.
	`CREATE TABLE player_endpoints (
		id            TEXT    PRIMARY KEY,
		kind          TEXT    NOT NULL,
		device_key    TEXT    NOT NULL,
		name          TEXT    NOT NULL,
		address       TEXT    NOT NULL DEFAULT '',
		details       TEXT    NOT NULL DEFAULT '',
		shared        INTEGER NOT NULL DEFAULT 1,
		last_seen_ns  INTEGER NOT NULL DEFAULT 0,
		created_at_ns INTEGER NOT NULL,
		UNIQUE (kind, device_key)
	);
	CREATE TABLE playback_sessions (
		id            TEXT    NOT NULL PRIMARY KEY,
		user_id       TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		endpoint_id   TEXT    NOT NULL,
		authority     TEXT    NOT NULL,
		state         TEXT    NOT NULL,
		active        INTEGER NOT NULL DEFAULT 1,
		created_at_ns INTEGER NOT NULL,
		updated_at_ns INTEGER NOT NULL
	);
	CREATE INDEX playback_sessions_user ON playback_sessions (user_id, active, updated_at_ns);`,

	// The curation surface: the matching review queue with its durable
	// identify work queue, resumable uploads, tool tasks (book merge and
	// split, cue splits), the health sweep index, and the fix dispatch
	// queue. Review payloads (tracks, candidates, the pre-apply snapshot
	// for revert) are JSON documents: they are read and written whole,
	// never queried into, and their shape belongs to the service layer.
	// Upload rights live on the user row; quota use derives from live
	// upload rows.
	`ALTER TABLE users ADD COLUMN upload_enabled INTEGER NOT NULL DEFAULT 0;
	ALTER TABLE users ADD COLUMN upload_quota_bytes INTEGER NOT NULL DEFAULT 0;
	CREATE TABLE review_entries (
		id             TEXT    PRIMARY KEY,
		kind           TEXT    NOT NULL,
		status         TEXT    NOT NULL,
		media_type     TEXT    NOT NULL,
		origin         TEXT    NOT NULL,
		library_pid    TEXT    NOT NULL DEFAULT '',
		uploaded_by    TEXT    NOT NULL DEFAULT '',
		title          TEXT    NOT NULL DEFAULT '',
		artist         TEXT    NOT NULL DEFAULT '',
		track_count    INTEGER NOT NULL DEFAULT 0,
		identifying    INTEGER NOT NULL DEFAULT 1,
		best_mbid      TEXT    NOT NULL DEFAULT '',
		best_title     TEXT    NOT NULL DEFAULT '',
		best_artist    TEXT    NOT NULL DEFAULT '',
		best_year      INTEGER NOT NULL DEFAULT 0,
		best_similarity REAL   NOT NULL DEFAULT 0,
		applied_mbid   TEXT    NOT NULL DEFAULT '',
		auto           INTEGER NOT NULL DEFAULT 0,
		payload        TEXT    NOT NULL DEFAULT '{}',
		snapshot       TEXT    NOT NULL DEFAULT '',
		created_at_ns  INTEGER NOT NULL,
		decided_at_ns  INTEGER NOT NULL DEFAULT 0,
		decided_by     TEXT    NOT NULL DEFAULT ''
	);
	CREATE INDEX review_entries_status ON review_entries (status, created_at_ns DESC, id);
	CREATE INDEX review_entries_uploader ON review_entries (uploaded_by, created_at_ns DESC, id);
	CREATE TABLE match_queue (
		id             INTEGER PRIMARY KEY,
		entry_id       TEXT    NOT NULL UNIQUE,
		attempts       INTEGER NOT NULL DEFAULT 0,
		lease_until_ns INTEGER NOT NULL DEFAULT 0,
		next_at_ns     INTEGER NOT NULL DEFAULT 0,
		last_error     TEXT    NOT NULL DEFAULT ''
	);
	CREATE TABLE uploads (
		id             TEXT    PRIMARY KEY,
		user_id        TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		file_name      TEXT    NOT NULL,
		size_bytes     INTEGER NOT NULL,
		received_bytes INTEGER NOT NULL DEFAULT 0,
		media_type     TEXT    NOT NULL,
		library_pid    TEXT    NOT NULL DEFAULT '',
		sha256         TEXT    NOT NULL DEFAULT '',
		state          TEXT    NOT NULL DEFAULT 'receiving',
		staging_path   TEXT    NOT NULL DEFAULT '',
		review_entry_id TEXT   NOT NULL DEFAULT '',
		duplicate_pid  TEXT    NOT NULL DEFAULT '',
		duplicate_kind TEXT    NOT NULL DEFAULT '',
		item_pid       TEXT    NOT NULL DEFAULT '',
		created_at_ns  INTEGER NOT NULL,
		expires_at_ns  INTEGER NOT NULL DEFAULT 0
	);
	CREATE INDEX uploads_user ON uploads (user_id, created_at_ns DESC, id);
	CREATE INDEX uploads_item ON uploads (item_pid, user_id);
	CREATE TABLE tool_tasks (
		id             TEXT    PRIMARY KEY,
		type           TEXT    NOT NULL,
		state          TEXT    NOT NULL DEFAULT 'queued',
		item_pid       TEXT    NOT NULL,
		user_id        TEXT    NOT NULL DEFAULT '',
		params         TEXT    NOT NULL DEFAULT '{}',
		progress_pct   REAL    NOT NULL DEFAULT 0,
		error          TEXT    NOT NULL DEFAULT '',
		result_pids    TEXT    NOT NULL DEFAULT '[]',
		attempts       INTEGER NOT NULL DEFAULT 0,
		lease_until_ns INTEGER NOT NULL DEFAULT 0,
		created_at_ns  INTEGER NOT NULL,
		finished_at_ns INTEGER NOT NULL DEFAULT 0
	);
	CREATE INDEX tool_tasks_user ON tool_tasks (user_id, created_at_ns DESC, id);
	CREATE INDEX tool_tasks_state ON tool_tasks (state, lease_until_ns);
	CREATE TABLE health_index (
		item_pid    TEXT    PRIMARY KEY,
		media_type  TEXT    NOT NULL,
		title       TEXT    NOT NULL DEFAULT '',
		artist      TEXT    NOT NULL DEFAULT '',
		rules       TEXT    NOT NULL DEFAULT '[]',
		rule_count  INTEGER NOT NULL DEFAULT 0,
		swept_at_ns INTEGER NOT NULL
	);
	CREATE INDEX health_index_worst ON health_index (rule_count DESC, title, item_pid);
	CREATE TABLE fix_queue (
		id             INTEGER PRIMARY KEY,
		item_pid       TEXT    NOT NULL,
		rule           TEXT    NOT NULL,
		attempts       INTEGER NOT NULL DEFAULT 0,
		lease_until_ns INTEGER NOT NULL DEFAULT 0,
		next_at_ns     INTEGER NOT NULL DEFAULT 0,
		last_error     TEXT    NOT NULL DEFAULT '',
		UNIQUE (item_pid, rule)
	);`,
}

// Open opens (creating if needed) the database at path and applies
// pending migrations.
func Open(ctx context.Context, path string) (*DB, error) {
	dsn := "file:" + path +
		"?_pragma=journal_mode(WAL)" +
		"&_pragma=synchronous(NORMAL)" +
		"&_pragma=busy_timeout(10000)" +
		"&_pragma=foreign_keys(ON)"

	w, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("db: opening %s: %w", path, err)
	}
	w.SetMaxOpenConns(1)

	r, err := sql.Open("sqlite", dsn)
	if err != nil {
		w.Close()
		return nil, fmt.Errorf("db: opening read pool: %w", err)
	}
	r.SetMaxOpenConns(8)

	d := &DB{w: w, r: r}
	if err := d.migrate(ctx); err != nil {
		d.Close()
		return nil, err
	}
	return d, nil
}

func (d *DB) migrate(ctx context.Context) error {
	var version int
	if err := d.w.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil {
		return fmt.Errorf("db: reading schema version: %w", err)
	}
	if version > len(migrations) {
		return fmt.Errorf("db: schema version %d is newer than this build understands (%d); refusing to open", version, len(migrations))
	}
	for i := version; i < len(migrations); i++ {
		tx, err := d.w.BeginTx(ctx, nil)
		if err != nil {
			return fmt.Errorf("db: migration %d: %w", i+1, err)
		}
		if _, err := tx.ExecContext(ctx, migrations[i]); err != nil {
			tx.Rollback()
			return fmt.Errorf("db: migration %d: %w", i+1, err)
		}
		// PRAGMA cannot be parameterized; the value is a trusted integer.
		if _, err := tx.ExecContext(ctx, fmt.Sprintf("PRAGMA user_version = %d", i+1)); err != nil {
			tx.Rollback()
			return fmt.Errorf("db: migration %d: %w", i+1, err)
		}
		if err := tx.Commit(); err != nil {
			return fmt.Errorf("db: migration %d: %w", i+1, err)
		}
	}
	return nil
}

// Writer returns the single-connection write handle.
func (d *DB) Writer() *sql.DB { return d.w }

// Reader returns the read pool.
func (d *DB) Reader() *sql.DB { return d.r }

// Close closes both handles.
func (d *DB) Close() error {
	rerr := d.r.Close()
	werr := d.w.Close()
	if werr != nil {
		return werr
	}
	return rerr
}
