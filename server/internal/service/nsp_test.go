package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"slices"
	"strings"
	"testing"

	"github.com/colespringer/waxbin/playlist"
	"github.com/colespringer/waxbin/query"
)

func parseQuery(t *testing.T, doc string) query.Query {
	t.Helper()
	var q query.Query
	if err := json.Unmarshal([]byte(doc), &q); err != nil {
		t.Fatalf("parse %s: %v", doc, err)
	}
	return q
}

func TestRuleHashIgnoresKeyOrder(t *testing.T) {
	t.Parallel()

	a := parseQuery(t, `{"entity":"items","where":{"type":"and","nodes":[{"type":"cond","field":"genre","op":"is","value":"Rock"}]},"limit":25}`)
	b := parseQuery(t, `{"limit":25,"where":{"nodes":[{"value":"Rock","op":"is","field":"genre","type":"cond"}],"type":"and"},"entity":"items"}`)
	changed := parseQuery(t, `{"entity":"items","where":{"type":"and","nodes":[{"type":"cond","field":"genre","op":"is","value":"Jazz"}]},"limit":25}`)

	ha, hb := ruleHash(a), ruleHash(b)
	if ha != hb {
		t.Fatalf("one rule hashed two ways: %q vs %q", ha, hb)
	}
	if len(ha) != 16 {
		t.Fatalf("hash %q is not 16 hex characters", ha)
	}
	if ruleHash(changed) == ha {
		t.Fatalf("a changed value kept the hash %q", ha)
	}
}

// Only the exact keys `name` and `public` describe the playlist, as the
// converter reads every key exactly; a refusal names what was wrong.
func TestSplitNSPReadsExactKeysAndNamesTheFault(t *testing.T) {
	t.Parallel()
	meta, rule, err := splitNSP([]byte(`{"NAME":"x","Public":true,"all":[]}`))
	if err != nil {
		t.Fatal(err)
	}
	if meta.Name != "" || meta.Public {
		t.Errorf("meta = %+v, want the case variants left to the converter", meta)
	}
	if !strings.Contains(string(rule), `"Public"`) || !strings.Contains(string(rule), `"NAME"`) {
		t.Errorf("rule = %s, want the case variants kept for the converter to report", rule)
	}
	for doc, want := range map[string]string{
		`[1]`:               "not a JSON object",
		`"x"`:               "not a JSON object",
		`42`:                "not a JSON object",
		`null`:              "not a JSON object",
		`{"all": [}`:        "not valid JSON",
		`{"name": 5}`:       "`name`",
		`{"public": "yes"}`: "`public`",
	} {
		if _, _, err := splitNSP([]byte(doc)); err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("%s: err = %v, want one saying %q", doc, err, want)
		}
	}
}

// nspGapRow is the part of a gap a client words: the catalog's code and
// what it names.
type nspGapRow struct{ code, field, op string }

func nspGapRows(gaps []NSPGap) []nspGapRow {
	rows := make([]nspGapRow, 0, len(gaps))
	for _, g := range gaps {
		rows = append(rows, nspGapRow{g.Code, g.Field, g.Op})
	}
	return rows
}

// Every gap carries the catalog's code, so a client words it itself, and
// an export names its field as the rule does, never as the engine does.
func TestNSPExportGapsCarryTheCatalogsCodeInTheRuleVocabulary(t *testing.T) {
	t.Parallel()

	q := query.Query{
		Entity: query.EntityItems,
		Where: query.And{Nodes: []query.Node{
			query.Cond{Field: "kind", Op: query.OpIs, Value: "track"},
			query.Cond{Field: "track_no", Op: query.OpIsMissing},
			query.Cond{Field: "duration_ms", Op: query.OpGt, Value: 180000.5},
			query.Cond{Field: "genre", Op: query.OpIs, Value: "Rock"},
		}},
		Sorts: []query.Sort{{Field: "published"}, {Field: "track_no", Desc: true}},
	}
	rep := nspReport(playlist.CheckNSPExport(q))
	rows := nspGapRows(rep.Gaps)
	for _, want := range []nspGapRow{
		{"unsupported_field", "mediaType", ""},
		{"presence_operator", "trackNumber", "isMissing"},
		{"duration_not_whole_ms", "durationMs", "gt"},
		{"unsupported_sort_field", "publishedAt", ""},
		{"extra_sort_term", "trackNumber", ""},
	} {
		if !slices.Contains(rows, want) {
			t.Errorf("gaps %v lack %v", rows, want)
		}
	}
	for _, g := range rep.Gaps {
		// The sentence is the converter's, kept for a code a client
		// does not know yet.
		if g.Reason == "" {
			t.Errorf("gap %+v carries no sentence", g)
		}
		switch g.Code {
		case "extra_sort_term":
			// The term a sort gap drops is the rule's, not the engine's.
			want := map[string]any{"field": "trackNumber", "desc": true}
			if !reflect.DeepEqual(g.Value, want) {
				t.Errorf("dropped sort term = %#v, want %v", g.Value, want)
			}
		case "duration_not_whole_ms":
			if g.Value != 180000.5 {
				t.Errorf("duration gap value = %#v, want 180000.5", g.Value)
			}
		}
	}

	tracks := query.Query{Entity: query.EntityTracks, Where: query.And{Nodes: []query.Node{
		query.Cond{Field: "genre", Op: query.OpIs, Value: "Rock"},
	}}}
	notes := nspReport(playlist.CheckNSPExport(tracks)).Notes
	if len(notes) != 1 || notes[0].Code != "entity_widens" {
		t.Errorf("notes = %+v, want the one entity_widens note", notes)
	}
}

// Two gaps the converter words alike stay two when they name different
// fields, and the strict refusal says their shared sentence once.
func TestNSPGapsDedupeByWhatTheyName(t *testing.T) {
	t.Parallel()
	q := query.Query{
		Entity: query.EntityItems,
		Where: query.And{Nodes: []query.Node{
			query.Cond{Field: "year", Op: query.OpGte, Value: 2000},
			query.Cond{Field: "rating", Op: query.OpGte, Value: 80},
			query.Cond{Field: "year", Op: query.OpGte, Value: 1990},
			query.Cond{Field: "genre", Op: query.OpIs, Value: "Rock"},
		}},
	}
	rows := nspGapRows(nspReport(playlist.CheckNSPExport(q)).Gaps)
	want := []nspGapRow{{"unsupported_operator", "year", "gte"}, {"unsupported_operator", "rating", "gte"}}
	if !slices.Equal(rows, want) {
		t.Errorf("gaps = %v, want %v", rows, want)
	}
	// The refusal names each in the rule's words, as its sentence does not.
	msg := nspExportRefusal(q, errors.New("strict"))
	for _, want := range []string{"gte (year)", "gte (rating)"} {
		if strings.Count(msg, want) != 1 {
			t.Errorf("refusal = %q, want %q once", msg, want)
		}
	}
	if msg := nspExportRefusal(query.Query{Entity: query.EntityItems, Where: query.And{Nodes: []query.Node{
		query.Cond{Field: "kind", Op: query.OpIs, Value: "track"},
	}}}, errors.New("strict")); !strings.Contains(msg, "(mediaType)") {
		t.Errorf("refusal = %q, want the field in the rule's words", msg)
	}

	// A string and a number that print alike are two values.
	typed := query.Query{Entity: query.EntityItems, Where: query.And{Nodes: []query.Node{
		query.Cond{Field: "starred", Op: query.OpIs, Value: "5"},
		query.Cond{Field: "starred", Op: query.OpIs, Value: 5},
		query.Cond{Field: "genre", Op: query.OpIs, Value: "Rock"},
	}}}
	if gaps := nspReport(playlist.CheckNSPExport(typed)).Gaps; len(gaps) != 2 {
		t.Errorf("gaps = %+v, want the string and the number apart", gaps)
	}
}

// A report stopped at the cap says there is more than it lists.
func TestNSPReportSaysWhenItStoppedAtTheCap(t *testing.T) {
	t.Parallel()
	nodes := make([]string, 0, 15)
	for i := range 15 {
		nodes = append(nodes, fmt.Sprintf(`{"is":{"field%d":1}}`, i))
	}
	many, err := playlist.CheckNSPImport([]byte(`{"all":[` + strings.Join(nodes, ",") + `]}`))
	if err != nil {
		t.Fatal(err)
	}
	if rep := nspReport(many); len(rep.Gaps) != maxNSPGaps || !rep.Truncated {
		t.Errorf("report = %d gaps, truncated %v; want %d and truncated", len(rep.Gaps), rep.Truncated, maxNSPGaps)
	}
	few, _ := playlist.CheckNSPImport([]byte(`{"all":[` + strings.Join(nodes[:3], ",") + `]}`))
	if rep := nspReport(few); rep.Truncated {
		t.Errorf("a report of %d gaps says it is truncated", len(rep.Gaps))
	}
}

// Every date a rule can hold is named in the rule's words when the file
// cannot carry it, so a catalog that renames one fails here rather than
// in the dialog.
func TestAnNSPDateGapNamesTheRuleField(t *testing.T) {
	t.Parallel()
	want := map[string]nspGapRow{
		"added":       {"date_operator", "addedAt", "after"},
		"starred_at":  {"date_operator", "starredAt", "after"},
		"last_played": {"date_operator", "lastPlayedAt", "after"},
		"published":   {"unsupported_field", "publishedAt", ""},
		"updated_at":  {"unsupported_field", "updatedAt", ""},
	}
	for _, spec := range ruleFieldSpecs {
		if spec.kind != ruleKindDate {
			continue
		}
		row, ok := want[spec.engine]
		if !ok {
			t.Errorf("date field %s has no expectation here", spec.api)
			continue
		}
		q := query.Query{
			Entity: query.EntityItems,
			Where: query.And{Nodes: []query.Node{
				query.Cond{Field: spec.engine, Op: query.OpAfter, Value: "2024-01-01"},
				query.Cond{Field: "genre", Op: query.OpIs, Value: "Rock"},
			}},
		}
		rows := nspGapRows(nspReport(playlist.CheckNSPExport(q)).Gaps)
		if !slices.Contains(rows, row) {
			t.Errorf("%s: gaps %v, want %v", spec.engine, rows, row)
		}
	}
}

// A gap about a document key or a budget's unit carries it, so a client
// can name it without reading the sentence.
func TestNSPGapsCarryTheirKeyAndMode(t *testing.T) {
	t.Parallel()

	imp, err := playlist.CheckNSPImport([]byte(`{"all":[{"is":{"genre":"Rock"}}],"limitPercent":10}`))
	if err != nil {
		t.Fatal(err)
	}
	gaps := nspReport(imp).Gaps
	if len(gaps) != 1 || gaps[0].Code != "unsupported_key" || gaps[0].Key != "limitPercent" {
		t.Errorf("import gaps = %+v, want unsupported_key on limitPercent", gaps)
	}

	exp := nspReport(playlist.CheckNSPExport(query.Query{
		Entity:    query.EntityItems,
		Where:     query.And{Nodes: []query.Node{query.Cond{Field: "genre", Op: query.OpIs, Value: "Rock"}}},
		LimitMode: query.LimitMinutes,
		Limit:     60,
	}))
	var budget *NSPGap
	for i, g := range exp.Gaps {
		if g.Code == "limit_budget" {
			budget = &exp.Gaps[i]
		}
	}
	if budget == nil {
		t.Fatalf("export gaps = %+v, want a limit_budget gap", exp.Gaps)
	}
	if budget.Mode != "minutes" || budget.Value != 60 {
		t.Errorf("budget gap = %+v, want mode minutes and value 60", *budget)
	}
}

// The contract lists the catalog's codes, so a client can word each one;
// a catalog that adds one fails here before any client falls back to
// English.
func TestTheNSPGapCodesAreTheCatalogs(t *testing.T) {
	t.Parallel()
	desc := nspSpecText(t, "    NspGap:", "The catalog's codes are", ".")
	var listed []string
	for _, m := range regexp.MustCompile("`([a-z_]+)`").FindAllStringSubmatch(desc, -1) {
		listed = append(listed, m[1])
	}
	var codes []string
	for _, c := range playlist.NSPReasons() {
		codes = append(codes, string(c))
	}
	slices.Sort(listed)
	slices.Sort(codes)
	if !slices.Equal(listed, codes) {
		t.Errorf("the code description lists %v, the catalog has %v", listed, codes)
	}
}

// The export's description names exactly the rule fields the file cannot
// carry: every one, and none it can.
func TestTheNSPExportDescriptionNamesExactlyWhatItCannotCarry(t *testing.T) {
	t.Parallel()
	desc := nspSpecText(t, "operationId: exportPlaylistNsp", "Nor the fields", "\n\n")
	var named []string
	for _, m := range regexp.MustCompile("`([^`]+)`").FindAllStringSubmatch(desc, -1) {
		named = append(named, m[1])
	}
	want := []string{"tag.KEY"}
	exportable := playlist.NSPExportableFields()
	for _, spec := range ruleFieldSpecs {
		if !slices.Contains(exportable, spec.engine) {
			want = append(want, spec.api)
		}
	}
	slices.Sort(named)
	slices.Sort(want)
	if !slices.Equal(named, want) {
		t.Errorf("the description names %v as fields NSP cannot carry, want %v", named, want)
	}
}

// The import's description names every field the converter reads.
func TestTheNSPImportDescriptionNamesEveryFieldItReads(t *testing.T) {
	t.Parallel()
	desc := strings.ToLower(nspSpecText(t, "operationId: importPlaylistNsp", "Fields map onto", "\n\n"))
	for _, field := range playlist.NSPImportableFields() {
		if !strings.Contains(desc, "`"+field+"`") {
			t.Errorf("the import description does not name %s, which the converter reads", field)
		}
	}
}

// nspSpecText is the playlists fragment from the first from after anchor
// up to the end that follows it.
func nspSpecText(t *testing.T, anchor, from, end string) string {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "api", "spec", "playlists.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	spec := string(raw)
	start := strings.Index(spec, anchor)
	if start < 0 {
		t.Fatalf("no %q in the playlists fragment", anchor)
	}
	at := strings.Index(spec[start:], from)
	if at < 0 {
		t.Fatalf("no %q after %q", from, anchor)
	}
	text := spec[start+at:]
	stop := strings.Index(text, end)
	if stop < 0 {
		t.Fatalf("no %q ends the text from %q", end, from)
	}
	return text[:stop]
}
