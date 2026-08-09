package api

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"testing"
)

// TestBackupArchiveServesRanges drives the archive download through the
// real mux, which is where the interesting part is: the exact pattern
// has to win over the generated router's /api/v1/ prefix, or the strict
// stub answers instead and nothing is ranged.
func TestBackupArchiveServesRanges(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()

	row, err := h.backups.Create(ctx, nil, "manual")
	if err != nil {
		t.Fatal(err)
	}
	if err := h.backups.Run(ctx, row.ID); err != nil {
		t.Fatal(err)
	}
	done, err := h.backups.Get(ctx, row.ID)
	if err != nil {
		t.Fatal(err)
	}
	if done.State != "done" || done.SizeBytes <= 32 {
		t.Fatalf("finished backup = %+v", done)
	}
	path := "/api/v1/admin/backups/" + row.ID + "/archive"

	whole := get(t, h.ts, path, h.token)
	defer whole.Body.Close()
	if whole.StatusCode != 200 {
		t.Fatalf("archive status = %d", whole.StatusCode)
	}
	if ct := whole.Header.Get("Content-Type"); ct != "application/zip" {
		t.Fatalf("content type = %q", ct)
	}
	if whole.Header.Get("Accept-Ranges") != "bytes" {
		t.Fatalf("archive does not advertise ranges: %v", whole.Header)
	}
	body, err := io.ReadAll(whole.Body)
	if err != nil {
		t.Fatal(err)
	}
	if int64(len(body)) != done.SizeBytes {
		t.Fatalf("whole body = %d bytes, want %d", len(body), done.SizeBytes)
	}

	// The resume case: a range answers 206, the declared span, and the
	// same bytes the whole download carried at that offset.
	req, _ := http.NewRequest("GET", h.ts.URL+path, nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	req.Header.Set("Range", "bytes=8-23")
	partial, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer partial.Body.Close()
	if partial.StatusCode != http.StatusPartialContent {
		t.Fatalf("ranged status = %d, want 206", partial.StatusCode)
	}
	want := fmt.Sprintf("bytes 8-23/%d", done.SizeBytes)
	if got := partial.Header.Get("Content-Range"); got != want {
		t.Fatalf("content range = %q, want %q", got, want)
	}
	chunk, err := io.ReadAll(partial.Body)
	if err != nil {
		t.Fatal(err)
	}
	if string(chunk) != string(body[8:24]) {
		t.Fatalf("ranged bytes do not match the whole download at that offset")
	}

	// The refusals are the raw handler's, not the strict stub's: an
	// unknown id is a coded not-found rather than an internal error.
	missing := get(t, h.ts, "/api/v1/admin/backups/bk-01JZX5N8QW3F4V9T2B7KD3M9R6/archive", h.token)
	defer missing.Body.Close()
	if missing.StatusCode != http.StatusNotFound {
		t.Fatalf("missing backup status = %d, want 404", missing.StatusCode)
	}
	if e := decode[Error](t, missing); e.Code != "not-found" {
		t.Fatalf("missing backup code = %q, want not-found", e.Code)
	}

	// A running backup has no archive yet, and the spec declares that as
	// a conflict.
	running, err := h.backups.Create(ctx, nil, "manual")
	if err != nil {
		t.Fatal(err)
	}
	unfinished := get(t, h.ts, "/api/v1/admin/backups/"+running.ID+"/archive", h.token)
	defer unfinished.Body.Close()
	if unfinished.StatusCode != http.StatusConflict {
		t.Fatalf("running backup status = %d, want 409", unfinished.StatusCode)
	}
	if e := decode[Error](t, unfinished); e.Code != "conflict" {
		t.Fatalf("running backup code = %q, want conflict", e.Code)
	}
}
