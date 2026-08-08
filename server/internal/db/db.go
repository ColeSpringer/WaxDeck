// Package db owns waxdeck.db: WaxDeck's own state beside (never inside)
// the WaxBin catalog. One dedicated write connection and a small read
// pool, WAL with synchronous=NORMAL, and a busy timeout as
// belt-and-braces; intra-process SQLITE_BUSY is structurally avoided
// rather than retried.
package db

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"errors"
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
// index + 1.
//
// Pre-release policy: the schema ships as the single baseline script
// below, and every schema change edits that script in place.
// user_version stays 1, the change's PR notes "delete
// data/waxdeck.db", and the fingerprint guard in migrate turns a stale
// dev database into a clear boot-time refusal instead of a latent "no
// such column" error. testdata/schema.golden mirrors the baseline as a
// normalized dump so each edit shows up as a reviewable semantic diff
// (regenerate with UPDATE_GOLDEN=1). At first release the baseline
// freezes and append-only migrations resume from index 1.
var migrations = []string{baselineSchema}

const baselineSchema = `
	-- Listen sessions: WaxDeck's listening record and the stats
	-- source. skipped_ms carries the client-reported silence-trim and
	-- speed-up savings behind the time-saved counter, and the time
	-- index serves the stats range scans.
	CREATE TABLE listen_sessions (
		id            INTEGER PRIMARY KEY,
		user_id       TEXT    NOT NULL,
		session_id    TEXT    NOT NULL,
		item_pid      TEXT    NOT NULL,
		media_type    TEXT    NOT NULL,
		started_at_ns INTEGER NOT NULL,
		ms_played     INTEGER NOT NULL,
		skipped_ms    INTEGER NOT NULL DEFAULT 0,
		finished      INTEGER NOT NULL DEFAULT 0,
		client        TEXT    NOT NULL DEFAULT '',
		source        TEXT    NOT NULL DEFAULT 'live',
		received_at_ns INTEGER NOT NULL,
		UNIQUE (user_id, session_id)
	);
	CREATE INDEX listen_sessions_by_item ON listen_sessions (user_id, item_pid, started_at_ns);
	CREATE INDEX listen_sessions_by_time ON listen_sessions (user_id, started_at_ns, id);

	-- Accounts, sessions, and per-user server state. The catalog user
	-- (waxbin_user_pid) is created at provisioning; WaxDeck is the sole
	-- identity authority and WaxBin stores no credentials. username_ci
	-- carries the case-insensitive uniqueness the login path matches
	-- on. pending marks signup-awaiting-approval accounts; the perm_
	-- block is the granular permission set; upload rights live on the
	-- user row (quota use derives from live upload rows); tag_rules is
	-- a JSON {allow, deny} document read whole, like prefs.
	CREATE TABLE users (
		id                 TEXT    PRIMARY KEY,
		username           TEXT    NOT NULL,
		username_ci        TEXT    NOT NULL UNIQUE,
		display_name       TEXT    NOT NULL DEFAULT '',
		password_hash      TEXT    NOT NULL DEFAULT '',
		roles              TEXT    NOT NULL DEFAULT 'user',
		disabled           INTEGER NOT NULL DEFAULT 0,
		pending            INTEGER NOT NULL DEFAULT 0,
		library_access     TEXT    NOT NULL DEFAULT 'all',
		perm_download      INTEGER NOT NULL DEFAULT 1,
		perm_delete        INTEGER NOT NULL DEFAULT 0,
		perm_explicit      INTEGER NOT NULL DEFAULT 1,
		perm_shared_outputs INTEGER NOT NULL DEFAULT 1,
		perm_podcasts      INTEGER NOT NULL DEFAULT 1,
		max_transcode_kbps INTEGER NOT NULL DEFAULT 0,
		upload_enabled     INTEGER NOT NULL DEFAULT 0,
		upload_quota_bytes INTEGER NOT NULL DEFAULT 0,
		tag_rules          TEXT    NOT NULL DEFAULT '',
		waxbin_user_pid    TEXT    NOT NULL,
		created_at_ns      INTEGER NOT NULL,
		updated_at_ns      INTEGER NOT NULL
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
	);

	-- Sync and compatibility-API state. event_log is the server change
	-- stream (the serverSeq cursor): one row per user-scoped state
	-- change, written by the sole writer (the service) at mutation
	-- time. play_state_stamps is the resume shelf: when each user last
	-- moved an item's position, which orders an offline position replay
	-- against the observation it competes with and feeds the in-progress
	-- list. WaxBin's play_state row has only one UpdatedAt, which
	-- position checkpoints bump constantly. Star and rating stamps used
	-- to live here too; the catalog orders those itself now, by the
	-- recorded time its writes carry. sync_state is a small key-value
	-- table for stream generations, floors, cursors, per-user grant
	-- epochs, and the schema baseline fingerprint. app_passwords hold
	-- the recoverable per-client secrets the Subsonic scheme demands,
	-- sealed with the server key; secret_hash serves apiKey lookup.
	CREATE TABLE event_log (
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
	CREATE INDEX app_passwords_by_user ON app_passwords (user_id, created_at_ns);

	-- Podcasts and audiobooks. Shows, episodes, and files are
	-- cataloged globally in waxbin.db; everything per user lives here.
	-- NULL in a settings column always means "server default", which
	-- is distinct from an explicit 0 or false. Retention resolves
	-- across a show's subscribers as the most generous union, so
	-- sweeps read podcast_subscriptions by show. feed_state carries
	-- the refresh scheduler's per-feed failure accounting (the catalog
	-- keeps none). silence_maps cache the streaming sidecar's silence
	-- analysis keyed by audio essence, so retags and moves never
	-- invalidate a map but a re-encode or a detector revision does.
	-- The three queue tables are durable work queues drained by
	-- supervised workers with row leases; the gpodder tables serve the
	-- compatibility adapter, whose protocol speaks feed URLs and epoch
	-- seconds.
	CREATE TABLE podcast_subscriptions (
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
		-- The auto-download keyword filter, as JSON string arrays of
		-- title terms. NULL means unset, which admits everything.
		auto_dl_include  TEXT,
		auto_dl_exclude  TEXT,
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
	-- Places a listener marked in a book on purpose, which is a
	-- different thing from the resume point in play_state: a book has
	-- one position and any number of bookmarks, and nothing here moves
	-- as playback does. The index is the read: every query is one
	-- user's marks in one book, in timeline order.
	CREATE TABLE book_bookmarks (
		id            TEXT    PRIMARY KEY,
		user_id       TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		book_pid      TEXT    NOT NULL,
		position_ms   INTEGER NOT NULL,
		note          TEXT    NOT NULL DEFAULT '',
		created_at_ns INTEGER NOT NULL
	);
	CREATE INDEX book_bookmarks_by_book ON book_bookmarks (user_id, book_pid, position_ms, id);
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
	CREATE INDEX gpodder_actions_by_user ON gpodder_actions (user_id, id);

	-- Internet radio stations, scrobbling connections and their
	-- durable delivery queue, notification targets with their outbox,
	-- and a small settings store for runtime-editable server
	-- configuration. A notification target is one delivery
	-- destination: scope server rows (user_id NULL) are
	-- administrator-managed and receive server-operations events,
	-- scope user rows belong to their creator; config is sealed with
	-- the server key, enabled_events is a JSON name array, and the
	-- health triple mirrors scrobble_connections. UnifiedPush
	-- registrations are kind unifiedpush rows deduped per owner on
	-- the endpoint via dedupe_key (NULL for every other kind, so the
	-- partial unique index sees only them; user_id COALESCEs to ''
	-- inside it because UNIQUE treats NULLs as always distinct, which
	-- would exempt server-scope rows). Outbox rows reference
	-- their target; config is read at delivery time so edits and
	-- revocations win, and deleting a target cascades its queue away.
	CREATE TABLE radio_stations (
		id            TEXT    PRIMARY KEY,
		name          TEXT    NOT NULL,
		stream_url    TEXT    NOT NULL UNIQUE,
		homepage_url  TEXT    NOT NULL DEFAULT '',
		logo_url      TEXT    NOT NULL DEFAULT '',
		created_by    TEXT    NOT NULL DEFAULT '',
		created_at_ns INTEGER NOT NULL
	);
	-- Songs a listener caught on the air and means to hunt down.
	-- Deliberately not items: nothing here is in the library, so
	-- nothing here plays, and the rows exist to be acquired and
	-- crossed off. identity_key is what makes the heart idempotent
	-- and what one indexed read per play-info poll asks for; the
	-- station and the announced line are snapshots, so a row outlives
	-- the station being renamed or removed. The cover is a snapshot
	-- too: whatever the artwork ladder held at save time, copied into
	-- the row so the list never turns into a pile of lookups against
	-- a rung an operator may have switched off. It is excluded from
	-- every listing SELECT, so only the art endpoint pays for it.
	CREATE TABLE radio_saved_songs (
		id            TEXT    PRIMARY KEY,
		user_id       TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		identity_key  TEXT    NOT NULL,
		raw_line      TEXT    NOT NULL,
		artist        TEXT    NOT NULL DEFAULT '',
		title         TEXT    NOT NULL DEFAULT '',
		station_pid   TEXT    NOT NULL DEFAULT '',
		station_name  TEXT    NOT NULL DEFAULT '',
		art           BLOB,
		art_mime      TEXT    NOT NULL DEFAULT '',
		art_etag      TEXT    NOT NULL DEFAULT '',
		created_at_ns INTEGER NOT NULL,
		UNIQUE (user_id, identity_key)
	);
	CREATE INDEX radio_saved_songs_by_user ON radio_saved_songs (user_id, id DESC);
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
	CREATE TABLE notification_targets (
		id                 TEXT    PRIMARY KEY,
		kind               TEXT    NOT NULL,
		scope              TEXT    NOT NULL,
		user_id            TEXT    REFERENCES users(id) ON DELETE CASCADE,
		label              TEXT    NOT NULL DEFAULT '',
		sealed_config      BLOB    NOT NULL,
		enabled_events     TEXT    NOT NULL DEFAULT '[]',
		dedupe_key         TEXT,
		last_success_at_ns INTEGER NOT NULL DEFAULT 0,
		last_error         TEXT    NOT NULL DEFAULT '',
		last_error_at_ns   INTEGER NOT NULL DEFAULT 0,
		created_at_ns      INTEGER NOT NULL
	);
	CREATE INDEX notification_targets_owner ON notification_targets (user_id, created_at_ns DESC, id);
	CREATE UNIQUE INDEX notification_targets_dedupe ON notification_targets (COALESCE(user_id, ''), kind, dedupe_key) WHERE dedupe_key IS NOT NULL;
	CREATE TABLE notify_outbox (
		id             INTEGER PRIMARY KEY AUTOINCREMENT,
		target_id      TEXT    NOT NULL REFERENCES notification_targets(id) ON DELETE CASCADE,
		event          TEXT    NOT NULL,
		title          TEXT    NOT NULL DEFAULT '',
		body           TEXT    NOT NULL DEFAULT '',
		enqueued_at_ns INTEGER NOT NULL,
		attempts       INTEGER NOT NULL DEFAULT 0,
		lease_until_ns INTEGER NOT NULL DEFAULT 0,
		last_error     TEXT    NOT NULL DEFAULT ''
	);
	CREATE INDEX notify_outbox_ready ON notify_outbox (lease_until_ns, enqueued_at_ns);
	CREATE TABLE settings (
		key        TEXT PRIMARY KEY,
		value      TEXT NOT NULL,
		updated_at_ns INTEGER NOT NULL
	);

	-- Player endpoints and playback sessions. Device endpoints (cast,
	-- DLNA, jukebox) persist across discovery sweeps under a stable
	-- per-device key; client endpoints live only as long as their
	-- WebSocket and are never written here. Session rows are the crash
	-- and restore record of the in-memory session manager: the live
	-- truth is in memory, rows carry the last checkpointed state, and
	-- ended sessions keep their final row as queue-restore history
	-- until pruned.
	CREATE TABLE player_endpoints (
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
	CREATE INDEX playback_sessions_user ON playback_sessions (user_id, active, updated_at_ns);

	-- Minted gapless timelines. The HLS proxy reconstructs the signed
	-- upstream master URL for a digest a client presents; without a row
	-- here every live timeline URL dies with the process. Rows are swept
	-- by expiry on load as well as on each mint, so a server that was
	-- down past every stored expiry does not carry dead rows until the
	-- next mint happens to sweep them.
	CREATE TABLE timeline_stash (
		digest        TEXT    PRIMARY KEY,
		signed_master TEXT    NOT NULL,
		expires_at_ns INTEGER NOT NULL
	);
	CREATE INDEX timeline_stash_expiry ON timeline_stash (expires_at_ns);

	-- The curation surface: the matching review queue with its durable
	-- identify work queue, resumable uploads, tool tasks (book merge
	-- and split, cue splits), the health sweep index, and the fix
	-- dispatch queue. Review payloads (tracks, candidates, the
	-- pre-apply snapshot for revert) are JSON documents: they are read
	-- and written whole, never queried into, and their shape belongs
	-- to the service layer.
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
		batch_id       TEXT    NOT NULL DEFAULT '',
		batch_path     TEXT    NOT NULL DEFAULT '',
		sha256         TEXT    NOT NULL DEFAULT '',
		state          TEXT    NOT NULL DEFAULT 'receiving',
		staging_path   TEXT    NOT NULL DEFAULT '',
		review_entry_id TEXT   NOT NULL DEFAULT '',
		track_doc      TEXT    NOT NULL DEFAULT '',
		duplicate_pid  TEXT    NOT NULL DEFAULT '',
		duplicate_kind TEXT    NOT NULL DEFAULT '',
		item_pid       TEXT    NOT NULL DEFAULT '',
		created_at_ns  INTEGER NOT NULL,
		expires_at_ns  INTEGER NOT NULL DEFAULT 0
	);
	CREATE INDEX uploads_user ON uploads (user_id, created_at_ns DESC, id);
	CREATE INDEX uploads_item ON uploads (item_pid, user_id);
	CREATE INDEX uploads_batch ON uploads (batch_id) WHERE batch_id != '';
	CREATE INDEX uploads_entry ON uploads (review_entry_id) WHERE review_entry_id != '';
	-- The pending-upload sum, over exactly the rows it charges. Partial
	-- rather than (user_id, state): the predicate is a negated set, so a
	-- state column could not be seeked on anyway, and the population
	-- this indexes is bounded by retention while the table it lives in
	-- is not. An account that imports steadily accumulates imported rows
	-- for good - they stopped being charged, which is the point - and
	-- summing over uploads_user would make every new session's quota
	-- check walk all of them.
	CREATE INDEX uploads_staged ON uploads (user_id, size_bytes)
		WHERE state NOT IN ('discarded', 'imported');

	-- Upload batches group several sessions into review units by a
	-- declared grouping intent (one album, separate tracks, or
	-- auto-clustering over tags and batch-relative paths). A member's
	-- parsed track document waits in uploads.track_doc until the batch
	-- finalizes; review_entry_ids records what finalization opened.
	CREATE TABLE upload_batches (
		id               TEXT    PRIMARY KEY,
		user_id          TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		grouping         TEXT    NOT NULL,
		media_type       TEXT    NOT NULL,
		library_pid      TEXT    NOT NULL DEFAULT '',
		state            TEXT    NOT NULL DEFAULT 'open',
		review_entry_ids TEXT    NOT NULL DEFAULT '[]',
		created_at_ns    INTEGER NOT NULL,
		expires_at_ns    INTEGER NOT NULL
	);
	CREATE INDEX upload_batches_state ON upload_batches (state, expires_at_ns);
	CREATE TABLE tool_tasks (
		id             TEXT    PRIMARY KEY,
		type           TEXT    NOT NULL,
		state          TEXT    NOT NULL DEFAULT 'queued',
		item_pid       TEXT    NOT NULL,
		user_id        TEXT    NOT NULL DEFAULT '',
		params         TEXT    NOT NULL DEFAULT '{}',
		progress_pct   REAL    NOT NULL DEFAULT 0,
		summary        TEXT    NOT NULL DEFAULT '',
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
	);

	-- The administration surface. Invites store only a token hash (the
	-- token itself is shown once, at creation) plus the account shape
	-- they admit. audit_log is the admin-action record: actor and
	-- target names are denormalized at write time so entries outlive
	-- renames and deletions, and it is deliberately separate from
	-- event_log (which is the per-user sync stream; admin actions must
	-- never leak into client sync deltas). backups catalogs the archive
	-- files in the data directory's backups/ folder ("origin" because
	-- "trigger" is an SQL keyword).
	CREATE TABLE invites (
		id                 TEXT    PRIMARY KEY,
		token_hash         BLOB    NOT NULL UNIQUE,
		note               TEXT    NOT NULL DEFAULT '',
		roles              TEXT    NOT NULL DEFAULT 'user',
		library_access     TEXT    NOT NULL DEFAULT 'all',
		library_grants     TEXT    NOT NULL DEFAULT '[]',
		perms              TEXT    NOT NULL DEFAULT '',
		upload_enabled     INTEGER NOT NULL DEFAULT 0,
		upload_quota_bytes INTEGER NOT NULL DEFAULT 0,
		max_uses           INTEGER NOT NULL DEFAULT 1,
		used_count         INTEGER NOT NULL DEFAULT 0,
		revoked            INTEGER NOT NULL DEFAULT 0,
		expires_at_ns      INTEGER NOT NULL DEFAULT 0,
		created_by         TEXT    NOT NULL DEFAULT '',
		created_at_ns      INTEGER NOT NULL
	);
	CREATE TABLE audit_log (
		id            INTEGER PRIMARY KEY AUTOINCREMENT,
		actor_id      TEXT    NOT NULL DEFAULT '',
		actor_name    TEXT    NOT NULL DEFAULT '',
		action        TEXT    NOT NULL,
		target_kind   TEXT    NOT NULL DEFAULT '',
		target_pid    TEXT    NOT NULL DEFAULT '',
		target_name   TEXT    NOT NULL DEFAULT '',
		detail        TEXT    NOT NULL DEFAULT '{}',
		created_at_ns INTEGER NOT NULL
	);
	CREATE INDEX audit_log_actor ON audit_log (actor_id, id);
	CREATE INDEX audit_log_action ON audit_log (action, id);
	CREATE INDEX audit_log_target ON audit_log (target_pid, id);
	CREATE TABLE backups (
		id             TEXT    PRIMARY KEY,
		state          TEXT    NOT NULL DEFAULT 'running',
		origin         TEXT    NOT NULL DEFAULT 'manual',
		file_name      TEXT    NOT NULL,
		size_bytes     INTEGER NOT NULL DEFAULT 0,
		error          TEXT    NOT NULL DEFAULT '',
		created_at_ns  INTEGER NOT NULL,
		finished_at_ns INTEGER NOT NULL DEFAULT 0
	);

	-- Sonic similarity and public shares. Embeddings and the neighbor
	-- graph are keyed by audio essence (tag-stable, identical across
	-- re-rips of the same bytes), so a retag or a move never
	-- re-analyzes; item_pid is a convenience pointer for joins and
	-- display, refreshed at ingest. similarity_queue is the analysis
	-- work queue on the standard lease shape; similarity_backfill
	-- names graph nodes that lost neighbor edges to a deletion and
	-- await the lazy repair sweep. shares hold no secret at rest: the
	-- capability token is derived from the share id with the server
	-- key, so the owner's list can always show full URLs, revocation
	-- is row state, and a leaked database exposes no share URLs.
	CREATE TABLE embeddings (
		essence       TEXT    PRIMARY KEY,
		item_pid      TEXT    NOT NULL,
		model         TEXT    NOT NULL,
		dims          INTEGER NOT NULL,
		vector        BLOB    NOT NULL,
		created_at_ns INTEGER NOT NULL
	);
	CREATE INDEX embeddings_item ON embeddings (item_pid);
	CREATE TABLE similarity_graph (
		essence  TEXT    NOT NULL,
		rank     INTEGER NOT NULL,
		neighbor TEXT    NOT NULL,
		distance REAL    NOT NULL,
		PRIMARY KEY (essence, rank)
	);
	CREATE INDEX similarity_graph_neighbor ON similarity_graph (neighbor);
	CREATE TABLE similarity_queue (
		essence        TEXT    PRIMARY KEY,
		item_pid       TEXT    NOT NULL,
		enqueued_at_ns INTEGER NOT NULL,
		attempts       INTEGER NOT NULL DEFAULT 0,
		lease_until_ns INTEGER NOT NULL DEFAULT 0,
		last_error     TEXT    NOT NULL DEFAULT ''
	);
	CREATE INDEX similarity_queue_ready ON similarity_queue (lease_until_ns, enqueued_at_ns);
	CREATE TABLE similarity_backfill (
		essence TEXT PRIMARY KEY
	);
	CREATE TABLE shares (
		id             TEXT    PRIMARY KEY,
		user_id        TEXT    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		target_pid     TEXT    NOT NULL,
		target_kind    TEXT    NOT NULL,
		allow_download INTEGER NOT NULL DEFAULT 0,
		position_ms    INTEGER NOT NULL DEFAULT 0,
		plays          INTEGER NOT NULL DEFAULT 0,
		created_at_ns  INTEGER NOT NULL,
		expires_at_ns  INTEGER NOT NULL DEFAULT 0,
		revoked        INTEGER NOT NULL DEFAULT 0
	);
	CREATE INDEX shares_user ON shares (user_id, created_at_ns DESC, id);

	-- Playlist covers. The catalog stores the image and cannot tell a
	-- user's upload from a generated mosaic: both are a front-role art
	-- row on the playlist entity, and both set HasArt. This table is
	-- the provenance the catalog has no place for. origin says which
	-- one it is, so clearing a custom cover falls back to the mosaic
	-- instead of leaving the playlist bare; fingerprint is over the
	-- member list the mosaic was built from plus the artwork-write epoch
	-- in sync_state, so a membership change or a member repainting its
	-- own cover regenerates it and an unrelated read does not.
	CREATE TABLE playlist_cover (
		playlist_pid  TEXT    PRIMARY KEY,
		origin        TEXT    NOT NULL,
		fingerprint   TEXT    NOT NULL DEFAULT '',
		updated_at_ns INTEGER NOT NULL DEFAULT 0
	);

	-- The canonical genre vocabulary, when this instance replaced the
	-- shipped default. Empty is the normal state and means "use the
	-- embedded tree", so a default that improves keeps reaching
	-- instances that never took ownership of their own; the admin edit
	-- writes the whole document at once and clearing every row goes back
	-- to the default. name is the canonical display spelling, parent
	-- groups it under a top-level genre ('' for one of those), and
	-- aliases is a JSON string array of the synonyms that resolve to it
	-- (read whole, never queried into, like prefs and tag_rules).
	CREATE TABLE genre_tree (
		name    TEXT PRIMARY KEY,
		parent  TEXT NOT NULL DEFAULT '',
		aliases TEXT NOT NULL DEFAULT '[]'
	);
`

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
		// While the whole schema is one in-place-edited baseline, no
		// build ever stamps a version above 1, so a higher version is
		// a database from the old pre-squash migration chain, not a
		// newer build's; steer it to the same delete-and-restart
		// answer as a fingerprint mismatch. Once appended migrations
		// resume (post-release, len > 1), the newer-build reading
		// becomes the true one again.
		if len(migrations) == 1 {
			return errStaleBaseline
		}
		return fmt.Errorf("db: schema version %d is newer than this build understands (%d); refusing to open", version, len(migrations))
	}
	baselineHash := fmt.Sprintf("%x", sha256.Sum256([]byte(migrations[0])))
	if version >= 1 {
		if err := d.checkBaselineFingerprint(ctx, baselineHash); err != nil {
			return err
		}
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
		if i == 0 {
			// The fingerprint commits with the baseline: there is no
			// state where user_version is 1 but the hash is missing.
			if _, err := tx.ExecContext(ctx,
				"INSERT OR REPLACE INTO sync_state (key, value) VALUES (?, ?)",
				baselineFingerprintKey, baselineHash); err != nil {
				tx.Rollback()
				return fmt.Errorf("db: migration %d: %w", i+1, err)
			}
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

// baselineFingerprintKey is the sync_state row holding the sha256 of
// the baseline script that created this database. Pre-release the
// baseline is edited in place with user_version pinned at 1, so the
// version alone cannot tell a current schema from a stale one; the
// hash can. The guard goes away at first release, when the baseline
// freezes.
const baselineFingerprintKey = "schema.baseline"

// errStaleBaseline is the delete-and-restart refusal every stale
// pre-release database lands on, whatever gave it away (a version
// from the old migration chain, a missing sync_state table, or a
// fingerprint from a different baseline script).
var errStaleBaseline = errors.New("db: this database was created by a different pre-release schema baseline; delete the waxdeck.db file (with its -wal and -shm siblings) and restart to recreate it")

// checkBaselineFingerprint refuses to run against a database created
// by a different baseline script. A missing hash row on an otherwise
// plausible database is adopted rather than refused, so the guard
// cannot brick a database it has simply never seen before.
func (d *DB) checkBaselineFingerprint(ctx context.Context, want string) error {
	var n int
	if err := d.w.QueryRowContext(ctx,
		"SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'sync_state'").Scan(&n); err != nil {
		return fmt.Errorf("db: checking baseline fingerprint: %w", err)
	}
	if n == 0 {
		// Old enough that sync_state does not exist: certainly stale.
		return errStaleBaseline
	}
	var stored string
	err := d.w.QueryRowContext(ctx,
		"SELECT value FROM sync_state WHERE key = ?", baselineFingerprintKey).Scan(&stored)
	switch {
	case errors.Is(err, sql.ErrNoRows):
		_, err := d.w.ExecContext(ctx,
			"INSERT INTO sync_state (key, value) VALUES (?, ?)", baselineFingerprintKey, want)
		if err != nil {
			return fmt.Errorf("db: storing baseline fingerprint: %w", err)
		}
	case err != nil:
		return fmt.Errorf("db: checking baseline fingerprint: %w", err)
	case stored != want:
		return errStaleBaseline
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
