package service

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
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

func TestNSPExportReasonsSpeakTheRuleVocabulary(t *testing.T) {
	t.Parallel()

	q := query.Query{
		Entity: query.EntityItems,
		Where:  query.And{Nodes: []query.Node{query.Cond{Field: "kind", Op: query.OpIs, Value: "track"}}},
		Sorts:  []query.Sort{{Field: "published"}, {Field: "track_no", Desc: true}},
	}
	var reasons []string
	for _, g := range nspReport(playlist.CheckNSPExport(q)).Gaps {
		reasons = append(reasons, g.Reason)
		// The term a sort gap drops is the rule's, not the engine's.
		if g.Kind == string(playlist.NSPGapSort) && g.Value != nil {
			want := map[string]any{"field": "trackNumber", "desc": true}
			if !reflect.DeepEqual(g.Value, want) {
				t.Errorf("dropped sort term = %#v, want %v", g.Value, want)
			}
		}
	}
	for _, want := range []string{
		"nsp: unsupported field: mediaType",
		"nsp: unsupported sort field: publishedAt",
		"nsp: .nsp holds a single sort term, so the sort term trackNumber desc has no .nsp representation",
	} {
		if !slices.Contains(reasons, want) {
			t.Errorf("reasons %q lack %q", reasons, want)
		}
	}

	// A field a sentence names mid-way is respelled the same.
	mid := query.Query{
		Entity: query.EntityItems,
		Where: query.And{Nodes: []query.Node{
			query.Cond{Field: "track_no", Op: query.OpIsMissing},
			query.Cond{Field: "duration_ms", Op: query.OpGt, Value: 180000.5},
			query.Cond{Field: "genre", Op: query.OpIs, Value: "Rock"},
		}},
	}
	reasons = nil
	for _, g := range nspReport(playlist.CheckNSPExport(mid)).Gaps {
		reasons = append(reasons, g.Reason)
	}
	for _, want := range []string{
		"nsp: isMissing on trackNumber has no .nsp form, since Navidrome allows it only on a field that can be empty",
		"nsp: gt on durationMs needs a whole number of milliseconds to export, got 180000.5",
	} {
		if !slices.Contains(reasons, want) {
			t.Errorf("reasons %q lack %q", reasons, want)
		}
	}

	// An English "kind" in a sentence is not a field name.
	tracks := query.Query{Entity: query.EntityTracks, Where: query.And{Nodes: []query.Node{
		query.Cond{Field: "genre", Op: query.OpIs, Value: "Rock"},
	}}}
	for _, n := range nspReport(playlist.CheckNSPExport(tracks)).Notes {
		if n.Reason != "nsp: .nsp has no track/book distinction, so this rule re-imports as one over every kind of item" {
			t.Errorf("note rewritten: %q", n.Reason)
		}
	}
}

// Every date a rule can hold is named in the rule's words when the file
// cannot carry it, whichever spelling the catalog's sentence ends on, so
// a catalog that renames one fails here rather than in the dialog.
func TestAnNSPDateReasonNamesTheRuleField(t *testing.T) {
	t.Parallel()
	for _, spec := range ruleFieldSpecs {
		if spec.kind != ruleKindDate {
			continue
		}
		q := query.Query{
			Entity: query.EntityItems,
			Where: query.And{Nodes: []query.Node{
				query.Cond{Field: spec.engine, Op: query.OpAfter, Value: "2024-01-01"},
				query.Cond{Field: "genre", Op: query.OpIs, Value: "Rock"},
			}},
		}
		var reasons []string
		for _, g := range nspReport(playlist.CheckNSPExport(q)).Gaps {
			reasons = append(reasons, g.Reason)
		}
		if !slices.ContainsFunc(reasons, func(r string) bool { return strings.HasSuffix(r, " "+spec.api) }) {
			t.Errorf("%s: reasons %q, want one naming %s", spec.engine, reasons, spec.api)
		}
	}
}

// The export's description names every rule field the file cannot carry.
func TestTheNSPExportDescriptionNamesEveryFieldItCannotCarry(t *testing.T) {
	t.Parallel()
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "api", "spec", "playlists.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	spec := string(raw)
	start := strings.Index(spec, "operationId: exportPlaylistNsp")
	if start < 0 {
		t.Fatal("no exportPlaylistNsp operation")
	}
	desc := spec[start:]
	desc = desc[:strings.Index(desc, "parameters:")]
	exportable := playlist.NSPExportableFields()
	for engine, spec := range ruleFieldsByEngine {
		if slices.Contains(exportable, engine) || spec.api == "playlist" {
			continue
		}
		if !strings.Contains(desc, "`"+spec.api+"`") {
			t.Errorf("the description does not name %s, which NSP cannot carry", spec.api)
		}
	}
}
