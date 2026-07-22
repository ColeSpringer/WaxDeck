package restore

import (
	"archive/zip"
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const (
	newWaxdeck = "NEW-WAXDECK-BYTES"
	newWaxbin  = "NEW-WAXBIN-BYTES"
)

// stage builds a data dir holding a backup archive and a staged-restore
// marker pointing at it.
func stage(t *testing.T) string {
	t.Helper()
	dataDir := t.TempDir()
	backups := filepath.Join(dataDir, backupsDirName)
	if err := os.MkdirAll(backups, 0o700); err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for name, content := range map[string]string{
		entryWaxdeck:    newWaxdeck,
		entryWaxbin:     newWaxbin,
		"manifest.json": `{"formatVersion":1}`,
	} {
		w, err := zw.Create(name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := w.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(backups, "a.zip"), buf.Bytes(), 0o600); err != nil {
		t.Fatal(err)
	}
	writeMarker(t, dataDir)
	return dataDir
}

func writeMarker(t *testing.T, dataDir string) {
	t.Helper()
	m := `{"backupId":"bu-01TESTBACKUP","fileName":"a.zip","stagedAtNS":1}`
	if err := os.WriteFile(filepath.Join(dataDir, markerFileName), []byte(m), 0o600); err != nil {
		t.Fatal(err)
	}
}

func markerPresent(t *testing.T, dataDir string) bool {
	t.Helper()
	_, err := os.Stat(filepath.Join(dataDir, markerFileName))
	if err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
	return err == nil
}

func readLive(t *testing.T, dataDir, name string) string {
	t.Helper()
	raw, err := os.ReadFile(filepath.Join(dataDir, name))
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

func TestRestoreApplyRoundTrip(t *testing.T) {
	dataDir := stage(t)
	// A live pair with a WAL sibling, all of which must be set aside.
	for name, content := range map[string]string{
		"waxdeck.db":     "OLD-WAXDECK",
		"waxdeck.db-wal": "OLD-WAL",
		"waxbin.db":      "OLD-WAXBIN",
	} {
		if err := os.WriteFile(filepath.Join(dataDir, name), []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}

	applied, rep, err := Apply(dataDir, nil)
	if err != nil {
		t.Fatalf("Apply: %v", err)
	}
	if !applied {
		t.Fatal("Apply reported nothing staged")
	}
	if rep.BackupID != "bu-01TESTBACKUP" || rep.FileName != "a.zip" {
		t.Fatalf("report = %+v", rep)
	}
	if got := readLive(t, dataDir, "waxdeck.db"); got != newWaxdeck {
		t.Fatalf("waxdeck.db = %q, want %q", got, newWaxdeck)
	}
	if got := readLive(t, dataDir, "waxbin.db"); got != newWaxbin {
		t.Fatalf("waxbin.db = %q, want %q", got, newWaxbin)
	}
	if len(rep.SetAside) != 3 {
		t.Fatalf("SetAside = %v, want 3 entries", rep.SetAside)
	}
	for _, base := range rep.SetAside {
		if !strings.Contains(base, ".pre-restore-") {
			t.Fatalf("set-aside name %q lacks the pre-restore tag", base)
		}
		if _, err := os.Stat(filepath.Join(dataDir, base)); err != nil {
			t.Fatalf("set-aside file %s: %v", base, err)
		}
	}
	// The stale WAL must not sit beside the restored database.
	if _, err := os.Stat(filepath.Join(dataDir, "waxdeck.db-wal")); !os.IsNotExist(err) {
		t.Fatalf("waxdeck.db-wal still present: %v", err)
	}
	if markerPresent(t, dataDir) {
		t.Fatal("marker survived a successful Apply")
	}
	// Nothing staged now: the next boot is a no-op.
	applied, rep, err = Apply(dataDir, nil)
	if err != nil || applied || rep != nil {
		t.Fatalf("second Apply = (%v, %v, %v), want (false, nil, nil)", applied, rep, err)
	}
}

func TestRestoreApplyNewHost(t *testing.T) {
	dataDir := stage(t)
	applied, rep, err := Apply(dataDir, nil)
	if err != nil || !applied {
		t.Fatalf("Apply = (%v, %v)", applied, err)
	}
	if len(rep.SetAside) != 0 {
		t.Fatalf("SetAside = %v, want none on a fresh host", rep.SetAside)
	}
	if got := readLive(t, dataDir, "waxdeck.db"); got != newWaxdeck {
		t.Fatalf("waxdeck.db = %q", got)
	}
}

func TestRestoreApplyNoMarker(t *testing.T) {
	applied, rep, err := Apply(t.TempDir(), nil)
	if err != nil || applied || rep != nil {
		t.Fatalf("Apply = (%v, %v, %v), want (false, nil, nil)", applied, rep, err)
	}
}

func TestRestoreApplyMissingArchiveKeepsMarker(t *testing.T) {
	dataDir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dataDir, backupsDirName), 0o700); err != nil {
		t.Fatal(err)
	}
	writeMarker(t, dataDir)
	applied, _, err := Apply(dataDir, nil)
	if err == nil || applied {
		t.Fatalf("Apply with a missing archive = (%v, %v), want an error", applied, err)
	}
	if !markerPresent(t, dataDir) {
		t.Fatal("marker was removed on failure; a failed restore must stay staged")
	}
}

func TestRestoreApplyBadMarkerFileName(t *testing.T) {
	dataDir := t.TempDir()
	m := `{"backupId":"bu-X","fileName":"../../etc/evil.zip"}`
	if err := os.WriteFile(filepath.Join(dataDir, markerFileName), []byte(m), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, _, err := Apply(dataDir, nil); err == nil {
		t.Fatal("Apply accepted a path-traversing archive name")
	}
}

// TestRestoreCrashOrdering walks the steps Apply composes and checks
// the marker outlives every point before the final removal, so a crash
// anywhere mid-restore retries at the next boot.
func TestRestoreCrashOrdering(t *testing.T) {
	dataDir := stage(t)
	if err := os.WriteFile(filepath.Join(dataDir, "waxdeck.db"), []byte("OLD"), 0o600); err != nil {
		t.Fatal(err)
	}
	m, err := readMarker(dataDir)
	if err != nil {
		t.Fatal(err)
	}
	archive := filepath.Join(dataDir, backupsDirName, m.FileName)

	tmps, err := extractArchive(archive, dataDir)
	if err != nil {
		t.Fatal(err)
	}
	if !markerPresent(t, dataDir) {
		t.Fatal("marker gone after extract; a crash here would lose the staged restore")
	}

	if _, err := swapIn(dataDir, tmps, "20260101-000000"); err != nil {
		t.Fatal(err)
	}
	if !markerPresent(t, dataDir) {
		t.Fatal("marker gone after swap; a crash here must still re-run at next boot")
	}

	// The re-run a post-swap crash would trigger: Apply extracts the
	// same archive again, sets the already-restored files aside, swaps
	// in identical bytes, and only then removes the marker.
	applied, _, err := Apply(dataDir, nil)
	if err != nil || !applied {
		t.Fatalf("re-run Apply = (%v, %v)", applied, err)
	}
	if markerPresent(t, dataDir) {
		t.Fatal("marker survived the completed re-run")
	}
	if got := readLive(t, dataDir, "waxdeck.db"); got != newWaxdeck {
		t.Fatalf("waxdeck.db = %q after re-run", got)
	}
}
