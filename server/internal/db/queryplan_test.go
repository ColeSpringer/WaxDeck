package db

import (
	"context"
	"database/sql"
	"strings"
	"testing"
)

// queryPlan answers SQLite's plan for q, its rows joined one per line,
// read on the transaction holding any temporary tables q names.
func queryPlan(t *testing.T, on interface {
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
}, q string, args ...any) string {
	t.Helper()
	rows, err := on.QueryContext(context.Background(), "EXPLAIN QUERY PLAN "+q, args...)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var lines []string
	for rows.Next() {
		var id, parent, unused int
		var detail string
		if err := rows.Scan(&id, &parent, &unused, &detail); err != nil {
			t.Fatal(err)
		}
		lines = append(lines, detail)
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	return strings.Join(lines, "\n")
}

// A kind change's listen updates seek the listen log through its item
// index, one account at a time, rather than walking the whole log on
// the only write connection.
func TestRemapItemsSeeksTheListenLog(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	for _, q := range remapTables {
		if _, err := tx.ExecContext(ctx, q); err != nil {
			t.Fatal(err)
		}
	}
	for name, q := range map[string]string{"listeners": remapListeners, "absorbed": remapAbsorbedListens, "kinds": remapKindListens} {
		plan := queryPlan(t, tx, q)
		seeks := strings.Contains(plan, "SEARCH listen_sessions")
		if name != "listeners" {
			seeks = strings.Contains(plan, "listen_sessions_by_item (user_id=? AND item_pid=?)")
		}
		if strings.Contains(plan, "SCAN listen_sessions") || !seeks {
			t.Errorf("%s plan:\n%s\nwant listen_sessions searched, never scanned", name, plan)
		}
	}
}

// The review queue reads an entry's sessions, and every page counts the
// flagged ones, through the index on the entry rather than a walk of
// every upload ever made.
func TestEntryUploadReadsUseTheEntryIndex(t *testing.T) {
	d := openTest(t)
	for name, q := range map[string]string{
		"an entry's sessions": uploadsOfEntry,
		"duplicate counts":    duplicateCountsQuery(3),
	} {
		args := []any{"rv-1", "rv-2", "rv-3"}
		if name == "an entry's sessions" {
			args = args[:1]
		}
		if plan := queryPlan(t, d.r, q, args...); !strings.Contains(plan, "USING INDEX uploads_entry") {
			t.Errorf("%s plan:\n%s\nwant a search of uploads_entry", name, plan)
		}
	}
}

// A kind change gives an item's audit entries its new prefix by seeking
// the target index, not by reading the whole log.
func TestRemapItemsSeeksTheAuditLog(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback()
	for _, q := range remapTables {
		if _, err := tx.ExecContext(ctx, q); err != nil {
			t.Fatal(err)
		}
	}
	if plan := queryPlan(t, tx, remapAuditTargets); strings.Contains(plan, "SCAN audit_log") || !strings.Contains(plan, "audit_log_target") {
		t.Errorf("plan:\n%s\nwant audit_log searched by its target, never scanned", plan)
	}
}
