package db

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

// libraryJournalKey is the sync_state row holding the item library
// journal's state (LibraryJournalState).
const libraryJournalKey = "library_journal"

// ItemLibrary is one row of the item library journal: from change Seq on,
// the item sat in LibraryPID, one of several when a change places it in
// more than one, or was dropped there when LibraryPID is empty.
type ItemLibrary struct {
	ItemPID    string
	Seq        int64
	LibraryPID string
}

// ItemLibraries is what the journal says of one item around a change-log
// position: AtCursor is the libraries its newest change at or before the
// position names, Placed whether there is such a change, and Since every
// library a later change names.
type ItemLibraries struct {
	AtCursor []string
	Placed   bool
	Since    []string
}

// LibraryJournalState is where the journal stands: the change it has read
// up to and that change's time, the change it last started over at, and
// the catalog generation it was built under.
type LibraryJournalState struct {
	Through, ThroughTS, Start, Generation int64
}

// LibraryJournalStateFor reads the journal's state; false when none is
// stored, which is a journal that never finished starting over.
func (d *DB) LibraryJournalStateFor(ctx context.Context) (LibraryJournalState, bool, error) {
	raw, err := d.SyncStateGet(ctx, libraryJournalKey)
	if err != nil || raw == "" {
		return LibraryJournalState{}, false, err
	}
	parts := strings.Split(raw, "|")
	if len(parts) != 4 {
		return LibraryJournalState{}, false, nil
	}
	var n [4]int64
	for i, p := range parts {
		if n[i], err = strconv.ParseInt(p, 10, 64); err != nil {
			return LibraryJournalState{}, false, nil
		}
	}
	return LibraryJournalState{Through: n[0], ThroughTS: n[1], Start: n[2], Generation: n[3]}, true, nil
}

// LatestItemLibraries answers the libraries each item's newest journal
// change names (empty for a dropped item); an item with no row is absent.
func (d *DB) LatestItemLibraries(ctx context.Context, itemPIDs []string) (map[string][]string, error) {
	out := make(map[string][]string, len(itemPIDs))
	if len(itemPIDs) == 0 {
		return out, nil
	}
	pids, err := json.Marshal(itemPIDs)
	if err != nil {
		return nil, fmt.Errorf("db: reading item libraries: %w", err)
	}
	rows, err := d.r.QueryContext(ctx, `
		SELECT j.item_pid, j.library_pid FROM item_library_journal j
		WHERE j.item_pid IN (SELECT value FROM json_each(?))
			AND j.seq = (SELECT MAX(n.seq) FROM item_library_journal n WHERE n.item_pid = j.item_pid)
		ORDER BY j.item_pid, j.library_pid`, string(pids))
	if err != nil {
		return nil, fmt.Errorf("db: reading item libraries: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var pid, lib string
		if err := rows.Scan(&pid, &lib); err != nil {
			return nil, fmt.Errorf("db: scanning item libraries: %w", err)
		}
		out[pid] = append(out[pid], lib)
	}
	return out, rows.Err()
}

// RecordItemLibraries stores journal rows and, when state is set, where
// the journal now stands, in one transaction.
func (d *DB) RecordItemLibraries(ctx context.Context, rows []ItemLibrary, state *LibraryJournalState) error {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: recording item libraries: %w", err)
	}
	defer tx.Rollback()
	for _, r := range rows {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO item_library_journal (item_pid, seq, library_pid) VALUES (?, ?, ?)
			ON CONFLICT DO NOTHING`, r.ItemPID, r.Seq, r.LibraryPID); err != nil {
			return fmt.Errorf("db: recording item libraries: %w", err)
		}
	}
	if state != nil {
		raw := fmt.Sprintf("%d|%d|%d|%d", state.Through, state.ThroughTS, state.Start, state.Generation)
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO sync_state (key, value) VALUES (?, ?)
			ON CONFLICT (key) DO UPDATE SET value = excluded.value`, libraryJournalKey, raw); err != nil {
			return fmt.Errorf("db: storing the library journal's state: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("db: recording item libraries: %w", err)
	}
	return nil
}

// ResetItemLibraries drops every journal row and the journal's state, in
// one transaction: a journal that starts over is trusted again only once
// its walk stores a state.
func (d *DB) ResetItemLibraries(ctx context.Context) error {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: resetting item libraries: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `DELETE FROM item_library_journal`); err != nil {
		return fmt.Errorf("db: resetting item libraries: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM sync_state WHERE key = ?`, libraryJournalKey); err != nil {
		return fmt.Errorf("db: resetting item libraries: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("db: resetting item libraries: %w", err)
	}
	return nil
}

// ItemLibrariesAround answers, for each item the journal holds a row for,
// its libraries at the change-log position cursor and every library a
// later change names.
func (d *DB) ItemLibrariesAround(ctx context.Context, itemPIDs []string, cursor int64) (map[string]ItemLibraries, error) {
	out := make(map[string]ItemLibraries, len(itemPIDs))
	if len(itemPIDs) == 0 {
		return out, nil
	}
	pids, err := json.Marshal(itemPIDs)
	if err != nil {
		return nil, fmt.Errorf("db: reading item library history: %w", err)
	}
	rows, err := d.r.QueryContext(ctx, `
		SELECT j.item_pid, j.seq, j.library_pid FROM item_library_journal j
		WHERE j.item_pid IN (SELECT value FROM json_each(?))
			AND (j.seq > ? OR j.seq = (
				SELECT MAX(at.seq) FROM item_library_journal at
				WHERE at.item_pid = j.item_pid AND at.seq <= ?))
		ORDER BY j.item_pid, j.seq, j.library_pid`,
		string(pids), cursor, cursor)
	if err != nil {
		return nil, fmt.Errorf("db: reading item library history: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var pid, lib string
		var seq int64
		if err := rows.Scan(&pid, &seq, &lib); err != nil {
			return nil, fmt.Errorf("db: scanning item library history: %w", err)
		}
		h := out[pid]
		if seq <= cursor {
			h.AtCursor, h.Placed = append(h.AtCursor, lib), true
		} else {
			h.Since = append(h.Since, lib)
		}
		out[pid] = h
	}
	return out, rows.Err()
}

// PruneItemLibraries drops what no cursor at or past floor reads: the
// rows a later change at or below floor supersedes, and the rows of an
// item dropped at or below it. Each item keeps the rows placing it at
// floor.
func (d *DB) PruneItemLibraries(ctx context.Context, floor int64) (int64, error) {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM item_library_journal
		WHERE seq <= ? AND (library_pid = '' OR EXISTS (
			SELECT 1 FROM item_library_journal later
			WHERE later.item_pid = item_library_journal.item_pid
				AND later.seq > item_library_journal.seq AND later.seq <= ?))`,
		floor, floor)
	if err != nil {
		return 0, fmt.Errorf("db: pruning item libraries: %w", err)
	}
	return res.RowsAffected()
}
