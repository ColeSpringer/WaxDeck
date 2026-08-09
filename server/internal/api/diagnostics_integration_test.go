package api

import (
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// TestFileDiagnosticsDashboard drives the diagnostics query and summary
// surface: scanning a file the parser cannot read records an
// unsupported-format diagnostic the query returns and the summary counts; a
// code filter narrows the result; a non-admin is refused; and a bad cursor
// and unknown library are rejected.
func TestFileDiagnosticsDashboard(t *testing.T) {
	t.Parallel()
	broken := t.TempDir()
	if _, err := fixtures.Generate(broken,
		fixtures.Spec{
			Name: "garbage", Codec: fixtures.CodecMP3, Duration: 2 * time.Second,
			Corrupt: fixtures.CorruptGarbage,
			Tags:    map[string]string{"TITLE": "Garbage", "ARTIST": "Static", "ALBUM": "Static"},
		},
	); err != nil {
		t.Fatalf("generating corrupt fixture: %v", err)
	}
	h := newHarness(t, service.Root{Name: "broken", Path: broken})

	// The scan recorded at least one unsupported-format diagnostic.
	resp := get(t, h.ts, "/api/v1/library/diagnostics", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("diagnostics status = %d, want 200", resp.StatusCode)
	}
	page := decode[FileDiagnosticPage](t, resp)
	var found *FileDiagnostic
	for i := range page.Diagnostics {
		if page.Diagnostics[i].Code == "unsupported_format" {
			found = &page.Diagnostics[i]
		}
	}
	if found == nil {
		t.Fatalf("no unsupported-format diagnostic after scanning garbage: %+v", page.Diagnostics)
	}
	if found.Origin != "scan" || found.Path == "" || found.SeenAt.IsZero() {
		t.Fatalf("unsupported diagnostic = %+v", *found)
	}

	// The summary counts it.
	sum := decode[DiagnosticSummary](
		t, get(t, h.ts, "/api/v1/library/diagnostics/summary", h.token))
	var count int
	for _, c := range sum.Counts {
		if c.Code == "unsupported_format" {
			count += c.Count
		}
	}
	if count < 1 {
		t.Fatalf("summary unsupported-format count = %d, want >= 1", count)
	}

	// A code filter narrows: filtering to an unrecorded code drops the row,
	// and filtering to the recorded one keeps it.
	empty := decode[FileDiagnosticPage](
		t, get(t, h.ts, "/api/v1/library/diagnostics?code=legacy_only_tags", h.token))
	for _, d := range empty.Diagnostics {
		if d.Code == "unsupported_format" {
			t.Fatal("legacy-only filter leaked an unsupported-format row")
		}
	}
	kept := decode[FileDiagnosticPage](
		t, get(t, h.ts, "/api/v1/library/diagnostics?code=unsupported_format&origin=scan", h.token))
	if len(kept.Diagnostics) < 1 {
		t.Fatal("code+origin filter dropped the matching row")
	}

	// A bad cursor is rejected up front.
	resp = get(t, h.ts, "/api/v1/library/diagnostics?cursor=not+base64", h.token)
	wantStatus(t, resp, 400, "bad cursor")

	// A well-formed but unknown library is a clean 404.
	resp = get(t, h.ts,
		"/api/v1/library/diagnostics?library=lb-01JZX5N8QW3F4V9T2B7KD3M9R6", h.token)
	wantStatus(t, resp, 404, "unknown library")

	// A non-admin cannot read diagnostics.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "listener", "password": "long-enough-pw",
	})
	wantStatus(t, resp, 201, "create non-admin user")
	userToken := loginAs(t, h.ts, "listener", "long-enough-pw").Token
	resp = get(t, h.ts, "/api/v1/library/diagnostics", userToken)
	wantStatus(t, resp, 403, "non-admin diagnostics")
}
