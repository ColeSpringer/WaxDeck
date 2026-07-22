package db

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// TestSchemaBaselineGolden compares a normalized dump of the live
// schema against testdata/schema.golden. The baseline is edited in
// place pre-release (see the migrations comment), so this golden is
// what turns a baseline edit into a reviewable semantic schema diff:
// regenerate with
//
//	UPDATE_GOLDEN=1 go test -run TestSchemaBaselineGolden ./internal/db/
//
// and review the git diff of the golden alongside the SQL change.
func TestSchemaBaselineGolden(t *testing.T) {
	d := openTest(t)
	dump := dumpSchema(t, d)
	path := filepath.Join("testdata", "schema.golden")
	if os.Getenv("UPDATE_GOLDEN") != "" {
		if err := os.MkdirAll("testdata", 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(dump), 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}
	want, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("missing golden %s (regenerate with UPDATE_GOLDEN=1): %v", path, err)
	}
	if dump != string(want) {
		t.Errorf("schema drifted from its golden (regenerate with UPDATE_GOLDEN=1 and review the git diff):\n%s",
			firstDumpDiff(string(want), dump))
	}
}

// dumpSchema renders every user table as sorted, normalized facts:
// columns from table_info with cid stripped (so a deliberate column
// reorder vanishes from the diff) sorted by name, foreign keys, named
// indexes with per-column collation order, and constraint auto-indexes
// compared by covered columns with the sqlite_autoindex_<table>_<N>
// name stripped (the counter tracks constraint declaration order, which
// a column reorder may renumber).
func dumpSchema(t *testing.T, d *DB) string {
	t.Helper()
	ctx := context.Background()
	r := d.Reader()

	var tables []string
	rows, err := r.QueryContext(ctx,
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
	if err != nil {
		t.Fatal(err)
	}
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatal(err)
		}
		tables = append(tables, name)
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}

	var b strings.Builder
	for _, table := range tables {
		fmt.Fprintf(&b, "table %s\n", table)
		for _, line := range dumpColumns(t, d, table) {
			fmt.Fprintf(&b, "  %s\n", line)
		}
		for _, line := range dumpForeignKeys(t, d, table) {
			fmt.Fprintf(&b, "  %s\n", line)
		}
		for _, line := range dumpIndexes(t, d, table) {
			fmt.Fprintf(&b, "  %s\n", line)
		}
	}
	return b.String()
}

func dumpColumns(t *testing.T, d *DB, table string) []string {
	t.Helper()
	rows, err := d.Reader().QueryContext(context.Background(),
		fmt.Sprintf("PRAGMA table_info(%q)", table))
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var cid, notnull, pk int
		var name, typ string
		var dflt *string
		if err := rows.Scan(&cid, &name, &typ, &notnull, &dflt, &pk); err != nil {
			t.Fatal(err)
		}
		dv := "<none>"
		if dflt != nil {
			dv = *dflt
		}
		out = append(out, fmt.Sprintf("column %s|%s|notnull=%d|default=%s|pk=%d", name, typ, notnull, dv, pk))
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	sort.Strings(out)
	return out
}

func dumpForeignKeys(t *testing.T, d *DB, table string) []string {
	t.Helper()
	rows, err := d.Reader().QueryContext(context.Background(),
		fmt.Sprintf("PRAGMA foreign_key_list(%q)", table))
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id, seq int
		var ref, from, onUpdate, onDelete, match string
		var to *string // NULL when the FK references an implicit primary key
		if err := rows.Scan(&id, &seq, &ref, &from, &to, &onUpdate, &onDelete, &match); err != nil {
			t.Fatal(err)
		}
		tv := "<pk>"
		if to != nil {
			tv = *to
		}
		out = append(out, fmt.Sprintf("fk %s->%s.%s|on_update=%s|on_delete=%s|match=%s", from, ref, tv, onUpdate, onDelete, match))
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	sort.Strings(out)
	return out
}

func dumpIndexes(t *testing.T, d *DB, table string) []string {
	t.Helper()
	ctx := context.Background()
	rows, err := d.Reader().QueryContext(ctx, fmt.Sprintf("PRAGMA index_list(%q)", table))
	if err != nil {
		t.Fatal(err)
	}
	type idx struct {
		name    string
		unique  int
		origin  string
		partial int
	}
	var list []idx
	for rows.Next() {
		var seq int
		var it idx
		if err := rows.Scan(&seq, &it.name, &it.unique, &it.origin, &it.partial); err != nil {
			rows.Close()
			t.Fatal(err)
		}
		list = append(list, it)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		t.Fatal(err)
	}
	rows.Close()

	var out []string
	for _, it := range list {
		cols := indexKeyColumns(t, d, it.name)
		if it.origin == "c" {
			out = append(out, fmt.Sprintf("index %s|unique=%d|partial=%d|(%s)", it.name, it.unique, it.partial, strings.Join(cols, ",")))
			continue
		}
		// Constraint auto-indexes (origin u/pk): name stripped, compared
		// by origin and covered columns only.
		out = append(out, fmt.Sprintf("autoindex %s|unique=%d|(%s)", it.origin, it.unique, strings.Join(cols, ",")))
	}
	sort.Strings(out)
	return out
}

// indexKeyColumns reads an index's key columns in position order via
// index_xinfo, which unlike index_info reports the per-column sort
// direction (a silently dropped DESC would otherwise be invisible).
func indexKeyColumns(t *testing.T, d *DB, index string) []string {
	t.Helper()
	rows, err := d.Reader().QueryContext(context.Background(),
		fmt.Sprintf("PRAGMA index_xinfo(%q)", index))
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var cols []string
	for rows.Next() {
		var seqno, cid, desc, key int
		var name *string // NULL for the rowid auxiliary column
		var coll string
		if err := rows.Scan(&seqno, &cid, &name, &desc, &coll, &key); err != nil {
			t.Fatal(err)
		}
		if key != 1 {
			continue
		}
		n := "<expr>"
		if name != nil {
			n = *name
		}
		if desc == 1 {
			n += " DESC"
		}
		cols = append(cols, n)
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	return cols
}

// firstDumpDiff reports the first line-level divergence between two
// dumps; the full semantic diff is what git shows on the regenerated
// golden.
func firstDumpDiff(want, got string) string {
	wl := strings.Split(want, "\n")
	gl := strings.Split(got, "\n")
	for i := 0; i < len(wl) || i < len(gl); i++ {
		var w, g string
		if i < len(wl) {
			w = wl[i]
		}
		if i < len(gl) {
			g = gl[i]
		}
		if w != g {
			return fmt.Sprintf("line %d:\n golden: %s\n    got: %s", i+1, w, g)
		}
	}
	return "dumps differ only in length"
}
