package db

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// KindMoves is what a kind change asks of WaxDeck's own rows: Absorbed
// maps each bare item pid folded away to the bare pid of the item that
// took it in, Kinds gives each item that changed kind, or took others
// in, the media type it has now (music or audiobook), Created maps
// each part a book split minted to the item it was split from, and
// Grants each minted part to the account granted it directly.
type KindMoves struct {
	Absorbed map[string]string
	Kinds    map[string]string
	Created  map[string]string
	Grants   map[string]string
}

// remapTables are the map tables a remap fills. They live and die inside
// its transaction: a run drops them before it commits, and one that fails
// rolls their creation back with the rest, so none is left for the next.
// kind_media carries each pid's prefixed form for its kind now.
// kind_listeners holds every account in the listen log, found by seeking
// its item index once per account, so the listen updates seek it per
// account and item rather than walk the largest table here.
var remapTables = []string{
	`CREATE TEMP TABLE kind_absorbed (old_pid TEXT PRIMARY KEY, new_pid TEXT NOT NULL, media_type TEXT) WITHOUT ROWID`,
	`CREATE TEMP TABLE kind_media (pid TEXT PRIMARY KEY, media_type TEXT NOT NULL, prefixed TEXT NOT NULL) WITHOUT ROWID`,
	`CREATE TEMP TABLE kind_listeners (user_id TEXT PRIMARY KEY) WITHOUT ROWID`,
}

// kindPrefixes is the pid prefix of each media type a kind change gives.
var kindPrefixes = map[string]string{"music": "tr-", "audiobook": "bk-"}

const (
	// Matched on the target's own form, either prefix, so the target
	// index finds the entries; the kind change records its target so.
	remapAuditTargets = `UPDATE audit_log SET
			target_pid = (SELECT prefixed FROM kind_media WHERE pid = substr(audit_log.target_pid, 4))
			WHERE target_pid IN (SELECT 'tr-' || pid FROM kind_media UNION ALL SELECT 'bk-' || pid FROM kind_media)`
	remapListeners = `WITH RECURSIVE u(id) AS (
			SELECT MIN(user_id) FROM listen_sessions
			UNION ALL
			SELECT (SELECT MIN(user_id) FROM listen_sessions WHERE user_id > u.id) FROM u WHERE u.id IS NOT NULL)
		INSERT INTO kind_listeners (user_id) SELECT id FROM u WHERE id IS NOT NULL`
	remapAbsorbedListens = `UPDATE listen_sessions SET
		item_pid = (SELECT new_pid FROM kind_absorbed WHERE old_pid = listen_sessions.item_pid),
		media_type = COALESCE((SELECT media_type FROM kind_absorbed WHERE old_pid = listen_sessions.item_pid), media_type)
		WHERE user_id IN (SELECT user_id FROM kind_listeners) AND item_pid IN (SELECT old_pid FROM kind_absorbed)
		AND media_type <> 'radio'`
	remapKindListens = `UPDATE listen_sessions SET
		media_type = (SELECT media_type FROM kind_media WHERE pid = listen_sessions.item_pid)
		WHERE user_id IN (SELECT user_id FROM kind_listeners) AND item_pid IN (SELECT pid FROM kind_media)
		AND media_type <> 'radio' AND media_type <> (SELECT media_type FROM kind_media WHERE pid = listen_sessions.item_pid)`
)

// RemapItems moves WaxDeck's rows after a kind change, in one
// transaction, matching each row by its bare pid whatever prefix it
// stored. The job's pids go into temporary map tables first, so each
// table is read once per job rather than once per pid, and the listen
// log is sought per account and item rather than walked: this holds the
// only write connection. What only a fold moves is skipped when nothing
// folded.
//
// A converted item's prefixed rows - its links, its tool tasks and the
// lists of what they made, its audit entries and Subsonic bookmarks -
// take its new prefix, a link its new kind too, and a bookmark held
// under both forms keeps the newer; its listens and health row take its
// media type. A folded-away item's listens, play-state stamp and
// playlist-source entries move to the item that took it in; its health
// row goes, for the next sweep to rebuild. A share of a folded-away
// item, or a track share of the book that took it in, is revoked rather
// than widened into the whole book. A folded-away item's tool tasks,
// audit entries and bookmarks stay where they were: what was done to it,
// and a place inside it, mean nothing on the item that took it in. A
// split's new parts are granted to whoever could edit the book they came
// from. An upload's own grant never moves: folding an uploader's item
// into someone else's must not hand them that one. Run twice it finds
// nothing left to move.
func (d *DB) RemapItems(ctx context.Context, m KindMoves) error {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: remapping items: %w", err)
	}
	defer tx.Rollback()
	exec := func(what, q string, args ...any) error {
		if _, err := tx.ExecContext(ctx, q, args...); err != nil {
			return fmt.Errorf("db: remapping %s: %w", what, err)
		}
		return nil
	}
	for _, q := range remapTables {
		if err := exec("its map", q); err != nil {
			return err
		}
	}
	for from, to := range m.Absorbed {
		var media any
		if v, ok := m.Kinds[to]; ok {
			media = v
		}
		if err := exec("its map", `INSERT INTO kind_absorbed (old_pid, new_pid, media_type) VALUES (upper(?), upper(?), ?)`,
			from, to, media); err != nil {
			return err
		}
	}
	forms := map[string]string{}
	for pid, media := range m.Kinds {
		prefix, ok := kindPrefixes[media]
		if !ok {
			continue
		}
		pid = strings.ToUpper(pid)
		forms[pid] = prefix + pid
		if err := exec("its map", `INSERT INTO kind_media (pid, media_type, prefixed) VALUES (?, ?, ?)`, pid, media, forms[pid]); err != nil {
			return err
		}
	}
	if err := exec("its map", remapListeners); err != nil {
		return err
	}

	// A statement that folds has work only when something folded.
	folded := len(m.Absorbed) > 0
	for _, s := range []struct {
		what, q string
		folds   bool
	}{
		// A folded-away item's links, and the track links of a survivor
		// that is not a track now, which would serve every part. One whose
		// kind is unknown counts as a book.
		{"shares", `UPDATE shares SET revoked = 1
			WHERE revoked = 0 AND target_kind IN ('track', 'book')
			AND upper(substr(target_pid, 4)) IN (SELECT old_pid FROM kind_absorbed)`, true},
		{"shares", `UPDATE shares SET revoked = 1
			WHERE revoked = 0 AND target_kind = 'track'
			AND upper(substr(target_pid, 4)) IN (SELECT new_pid FROM kind_absorbed WHERE media_type IS NOT 'music')`, true},
		{"shares", `UPDATE shares SET
			target_pid = (SELECT CASE media_type WHEN 'audiobook' THEN 'bk' ELSE 'tr' END
				FROM kind_media WHERE pid = upper(substr(shares.target_pid, 4))) || '-' || upper(substr(target_pid, 4)),
			target_kind = (SELECT CASE media_type WHEN 'audiobook' THEN 'book' ELSE 'track' END
				FROM kind_media WHERE pid = upper(substr(shares.target_pid, 4)))
			WHERE target_kind IN ('track', 'book') AND upper(substr(target_pid, 4)) IN (SELECT pid FROM kind_media)`, false},
		{"listens", remapAbsorbedListens, true},
		{"listens", remapKindListens, false},
		// The newest observation wins: a stamp is when the position last moved.
		{"play-state stamps", `INSERT INTO play_state_stamps (user_id, item_pid, position_ns)
			SELECT s.user_id, a.new_pid, s.position_ns
			FROM play_state_stamps s JOIN kind_absorbed a ON a.old_pid = s.item_pid WHERE true
			ON CONFLICT (user_id, item_pid) DO UPDATE
			SET position_ns = MAX(play_state_stamps.position_ns, excluded.position_ns)`, true},
		{"play-state stamps", `DELETE FROM play_state_stamps WHERE item_pid IN (SELECT old_pid FROM kind_absorbed)`, true},
		{"playlist sources", `UPDATE playlist_source_map SET
			item_pid = (SELECT new_pid FROM kind_absorbed WHERE old_pid = playlist_source_map.item_pid)
			WHERE item_pid IN (SELECT old_pid FROM kind_absorbed)`, true},
		{"health", `DELETE FROM health_index WHERE item_pid IN (SELECT old_pid FROM kind_absorbed)`, true},
		{"health", `UPDATE health_index SET
			media_type = (SELECT media_type FROM kind_media WHERE pid = health_index.item_pid)
			WHERE item_pid IN (SELECT pid FROM kind_media)`, false},
		{"tool tasks", `UPDATE tool_tasks SET
			item_pid = (SELECT prefixed FROM kind_media WHERE pid = upper(substr(tool_tasks.item_pid, 4)))
			WHERE substr(item_pid, 1, 3) IN ('tr-', 'bk-') AND upper(substr(item_pid, 4)) IN (SELECT pid FROM kind_media)`, false},
		{"audit entries", remapAuditTargets, false},
		// A bookmark held under both forms keeps the newer.
		{"subsonic bookmarks", `INSERT INTO subsonic_bookmarks (user_id, item_pid, position_ms, comment, created_at_ns, updated_at_ns)
			SELECT b.user_id, m.prefixed, b.position_ms, b.comment, b.created_at_ns, b.updated_at_ns
			FROM subsonic_bookmarks b JOIN kind_media m ON m.pid = upper(substr(b.item_pid, 4))
			WHERE substr(b.item_pid, 1, 3) IN ('tr-', 'bk-') AND b.item_pid <> m.prefixed
			ON CONFLICT (user_id, item_pid) DO UPDATE
			SET position_ms = excluded.position_ms, comment = excluded.comment, updated_at_ns = excluded.updated_at_ns
			WHERE excluded.updated_at_ns > subsonic_bookmarks.updated_at_ns`, false},
		{"subsonic bookmarks", `DELETE FROM subsonic_bookmarks WHERE substr(item_pid, 1, 3) IN ('tr-', 'bk-')
			AND item_pid <> (SELECT prefixed FROM kind_media WHERE pid = upper(substr(subsonic_bookmarks.item_pid, 4)))`, false},
	} {
		if s.folds && !folded {
			continue
		}
		if err := exec(s.what, s.q); err != nil {
			return err
		}
	}
	if err := remapResultLists(ctx, tx, forms); err != nil {
		return err
	}
	now := time.Now().UnixNano()
	// An account deleted since the change has nothing to be granted.
	for part, user := range m.Grants {
		if err := exec("grants", `INSERT OR IGNORE INTO item_grants (user_id, item_pid, created_at_ns)
			SELECT id, upper(?), ? FROM users WHERE id = ?`, part, now, user); err != nil {
			return err
		}
	}
	for part, from := range m.Created {
		if err := exec("grants", `INSERT OR IGNORE INTO item_grants (user_id, item_pid, created_at_ns)
			SELECT user_id, upper(?), ? FROM uploads WHERE item_pid = upper(?)
			UNION
			SELECT user_id, upper(?), ? FROM item_grants WHERE item_pid = upper(?)`,
			part, now, from, part, now, from); err != nil {
			return err
		}
	}
	for _, q := range []string{`DROP TABLE kind_absorbed`, `DROP TABLE kind_media`, `DROP TABLE kind_listeners`} {
		if err := exec("its map", q); err != nil {
			return err
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("db: remapping items: %w", err)
	}
	return nil
}

// remapResultLists gives each converted pid in a tool task's list of
// results its new prefix where it stands, forms mapping each converted
// bare pid to its prefixed form. Only the tasks naming one are read; a
// list that does not read as one is left as it is.
func remapResultLists(ctx context.Context, tx *sql.Tx, forms map[string]string) error {
	if len(forms) == 0 {
		return nil
	}
	rows, err := tx.QueryContext(ctx, `SELECT DISTINCT t.id, t.result_pids FROM tool_tasks t
		JOIN kind_media m ON instr(upper(t.result_pids), '-' || m.pid || '"') > 0`)
	if err != nil {
		return fmt.Errorf("db: remapping task results: %w", err)
	}
	type list struct{ id, raw string }
	var named []list
	for rows.Next() {
		var l list
		if err := rows.Scan(&l.id, &l.raw); err != nil {
			rows.Close()
			return fmt.Errorf("db: remapping task results: %w", err)
		}
		named = append(named, l)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return fmt.Errorf("db: remapping task results: %w", err)
	}
	for _, l := range named {
		var pids []string
		if json.Unmarshal([]byte(l.raw), &pids) != nil {
			continue
		}
		moved := false
		for i, p := range pids {
			if !strings.HasPrefix(p, "tr-") && !strings.HasPrefix(p, "bk-") {
				continue
			}
			if form, ok := forms[strings.ToUpper(p[3:])]; ok && form != p {
				pids[i], moved = form, true
			}
		}
		if !moved {
			continue
		}
		raw, err := json.Marshal(pids)
		if err != nil {
			return fmt.Errorf("db: remapping task results: %w", err)
		}
		if _, err := tx.ExecContext(ctx, `UPDATE tool_tasks SET result_pids = ? WHERE id = ?`, string(raw), l.id); err != nil {
			return fmt.Errorf("db: remapping task results: %w", err)
		}
	}
	return nil
}
