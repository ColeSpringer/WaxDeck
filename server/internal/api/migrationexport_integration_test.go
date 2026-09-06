package api

import (
	"archive/zip"
	"bytes"
	"io"
	"net/http"
	"strings"
	"testing"
)

// The staged-export surface over HTTP: an account data export is
// uploaded, recognised, addressable by the id an import then names, and
// discardable. The refusals the service decides (a body over the cap, a
// volume with no room) are asserted where they are decided; what this
// covers is the wiring, the admin gate and the shapes.
func TestMigrationExportEndpoints(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	post := func(t *testing.T, token string, body []byte) *http.Response {
		t.Helper()
		req, _ := http.NewRequest("POST", h.ts.URL+"/api/v1/admin/migrations/exports",
			bytes.NewReader(body))
		req.Header.Set("Content-Type", "application/octet-stream")
		if token != "" {
			req.Header.Set("Authorization", "Bearer "+token)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		return resp
	}

	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, err := zw.Create("Spotify Account Data/StreamingHistory_music_0.json")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := io.WriteString(w, `[{"endTime":"2026-01-02 03:04","artistName":"A","trackName":"B","msPlayed":1000}]`); err != nil {
		t.Fatal(err)
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}

	if resp := post(t, "", buf.Bytes()); resp.StatusCode != http.StatusUnauthorized {
		resp.Body.Close()
		t.Fatalf("uploading without a token: status = %d, want 401", resp.StatusCode)
	}

	resp := post(t, h.token, []byte("not a zip at all"))
	if resp.StatusCode != http.StatusBadRequest {
		resp.Body.Close()
		t.Fatalf("uploading a non-zip: status = %d, want 400", resp.StatusCode)
	}
	if code := decode[Error](t, resp).Code; code != "invalid-request" {
		t.Fatalf("non-zip code = %q", code)
	}

	resp = post(t, h.token, buf.Bytes())
	if resp.StatusCode != http.StatusCreated {
		resp.Body.Close()
		t.Fatalf("uploading an export: status = %d, want 201", resp.StatusCode)
	}
	staged := decode[MigrationExport](t, resp)
	if !strings.HasPrefix(staged.Pid, "mx-") || staged.Source != "spotify" {
		t.Fatalf("staged = %+v", staged)
	}
	if len(staged.Files) != 1 || staged.SizeBytes != int64(buf.Len()) || staged.ExpiresAt.IsZero() {
		t.Fatalf("staged = %+v", staged)
	}

	// The id it answered is the one an import names, and the migration
	// entry accepts it.
	if resp := h.postJSON(t, "/api/v1/admin/migrations", map[string]any{
		"source": "spotify", "exportId": staged.Pid, "dryRun": true,
	}); resp.StatusCode != http.StatusAccepted {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("starting a spotify import: status = %d: %s", resp.StatusCode, body)
	}

	discard := func(t *testing.T, pid string) int {
		t.Helper()
		req, _ := http.NewRequest("DELETE", h.ts.URL+"/api/v1/admin/migrations/exports/"+pid, nil)
		req.Header.Set("Authorization", "Bearer "+h.token)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		return resp.StatusCode
	}
	if got := discard(t, staged.Pid); got != http.StatusNoContent {
		t.Fatalf("discarding: status = %d, want 204", got)
	}
	if got := discard(t, staged.Pid); got != http.StatusNotFound {
		t.Fatalf("discarding twice: status = %d, want 404", got)
	}
}
