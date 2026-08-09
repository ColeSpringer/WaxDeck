package service

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// testCatalog is the narrow catalog seam: it writes known bytes where
// the real facade would write a waxbin.db snapshot.
type testCatalog struct{ fail bool }

const testCatalogBytes = "FAKE-WAXBIN-SNAPSHOT"

func (c testCatalog) Backup(ctx context.Context, dest string, redact bool) error {
	if c.fail {
		return errors.New("catalog snapshot exploded")
	}
	return os.WriteFile(dest, []byte(testCatalogBytes), 0o600)
}

// newTestBackups builds a Backups over a real waxdeck.db in a temp dir,
// a fake catalog, and a bare Library for the audit trail. The clock is
// stepped a minute per read so archive names never collide.
func newTestBackups(t *testing.T) (*Backups, *wdb.DB, string) {
	t.Helper()
	root := t.TempDir()
	d, err := wdb.Open(context.Background(), filepath.Join(root, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { d.Close() })
	dataDir := filepath.Join(root, "data")
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		t.Fatal(err)
	}
	l := &Library{db: d, log: slog.New(slog.DiscardHandler)}
	b := newBackups(d, testCatalog{}, l, l, l.log, dataDir, nil)
	clk := time.Date(2026, 1, 2, 3, 4, 5, 0, time.UTC)
	b.now = func() time.Time {
		clk = clk.Add(time.Minute)
		return clk
	}
	return b, d, dataDir
}

func wantKind(t *testing.T, err error, kind ErrorKind) {
	t.Helper()
	if KindOf(err) != kind {
		t.Fatalf("err = %v (kind %q), want kind %q", err, KindOf(err), kind)
	}
}

// createAndRun makes one finished backup and returns its row.
func createAndRun(t *testing.T, b *Backups) wdb.Backup {
	t.Helper()
	ctx := context.Background()
	row, err := b.Create(ctx, nil, "manual")
	if err != nil {
		t.Fatal(err)
	}
	if err := b.Run(ctx, row.ID); err != nil {
		t.Fatal(err)
	}
	got, err := b.Get(ctx, row.ID)
	if err != nil {
		t.Fatal(err)
	}
	return got
}

func TestBackupCreateClaimsConflict(t *testing.T) {
	t.Parallel()
	b, _, _ := newTestBackups(t)
	ctx := context.Background()

	if _, err := b.Create(ctx, nil, "sideways"); KindOf(err) != KindInvalid {
		t.Fatalf("bad origin err = %v, want invalid", err)
	}

	row, err := b.Create(ctx, nil, "manual")
	if err != nil {
		t.Fatal(err)
	}
	if row.State != "running" || !strings.HasPrefix(row.ID, PrefixBackup+"-") {
		t.Fatalf("claimed row = %+v", row)
	}
	_, err = b.Create(ctx, nil, "scheduled")
	wantKind(t, err, KindConflict)

	if err := b.Run(ctx, row.ID); err != nil {
		t.Fatal(err)
	}
	// The slot frees once the run finishes.
	if _, err := b.Create(ctx, nil, "scheduled"); err != nil {
		t.Fatalf("create after finish: %v", err)
	}
}

func TestBackupRunProducesArchive(t *testing.T) {
	t.Parallel()
	b, _, dataDir := newTestBackups(t)
	row := createAndRun(t, b)
	if row.State != "done" || row.SizeBytes <= 0 || row.FinishedAtNS == 0 {
		t.Fatalf("finished row = %+v", row)
	}

	path, err := b.ArchivePath(context.Background(), row.ID)
	if err != nil {
		t.Fatal(err)
	}
	if filepath.Dir(path) != filepath.Join(dataDir, "backups") {
		t.Fatalf("archive path = %s", path)
	}
	zr, err := zip.OpenReader(path)
	if err != nil {
		t.Fatal(err)
	}
	defer zr.Close()
	entries := map[string][]byte{}
	for _, f := range zr.File {
		rc, err := f.Open()
		if err != nil {
			t.Fatal(err)
		}
		var buf bytes.Buffer
		if _, err := buf.ReadFrom(rc); err != nil {
			t.Fatal(err)
		}
		rc.Close()
		entries[f.Name] = buf.Bytes()
	}
	if string(entries["waxbin.db"]) != testCatalogBytes {
		t.Fatalf("waxbin.db entry = %q", entries["waxbin.db"])
	}
	if !bytes.HasPrefix(entries["waxdeck.db"], []byte("SQLite format 3\x00")) {
		t.Fatal("waxdeck.db entry is not an sqlite snapshot")
	}
	var m backupManifest
	if err := json.Unmarshal(entries["manifest.json"], &m); err != nil {
		t.Fatal(err)
	}
	if m.FormatVersion != 1 || m.WaxdeckSchema <= 0 || m.CreatedAt == "" {
		t.Fatalf("manifest = %+v", m)
	}
	// No temp litter beside the archive.
	names, err := os.ReadDir(filepath.Join(dataDir, "backups"))
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range names {
		if strings.Contains(e.Name(), ".tmp") {
			t.Fatalf("temp file %s left behind", e.Name())
		}
	}
}

func TestBackupRunFailureMarksFailed(t *testing.T) {
	t.Parallel()
	b, _, _ := newTestBackups(t)
	b.catalog = testCatalog{fail: true}
	ctx := context.Background()
	row, err := b.Create(ctx, nil, "manual")
	if err != nil {
		t.Fatal(err)
	}
	if err := b.Run(ctx, row.ID); err == nil {
		t.Fatal("Run succeeded with a failing catalog")
	}
	got, err := b.Get(ctx, row.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.State != "failed" || got.Error == "" {
		t.Fatalf("row after failed run = %+v", got)
	}
	// A failed backup has nothing to download.
	_, err = b.ArchivePath(ctx, row.ID)
	wantKind(t, err, KindConflict)
	// The slot is free again.
	if _, err := b.Create(ctx, nil, "manual"); err != nil {
		t.Fatalf("create after failure: %v", err)
	}
}

func TestRetentionKeepCount(t *testing.T) {
	t.Parallel()
	b, d, _ := newTestBackups(t)
	ctx := context.Background()
	if err := d.SettingSet(ctx, settingBackupKeep, "2", 1); err != nil {
		t.Fatal(err)
	}
	// An imported archive is exempt from retention.
	imported, err := b.Import(ctx, nil, bytes.NewReader(validArchiveBytes(t)), 0)
	if err != nil {
		t.Fatal(err)
	}

	first := createAndRun(t, b)
	second := createAndRun(t, b)
	third := createAndRun(t, b)

	rows, err := b.List(ctx)
	if err != nil {
		t.Fatal(err)
	}
	byID := map[string]bool{}
	for _, r := range rows {
		byID[r.ID] = true
	}
	if byID[first.ID] {
		t.Fatal("oldest backup survived keep-count 2")
	}
	if !byID[second.ID] || !byID[third.ID] || !byID[imported.ID] {
		t.Fatalf("surviving rows = %v", byID)
	}
	if _, err := os.Stat(b.archivePath(first.FileName)); !os.IsNotExist(err) {
		t.Fatalf("pruned archive still on disk: %v", err)
	}
	if _, err := os.Stat(b.archivePath(second.FileName)); err != nil {
		t.Fatalf("kept archive missing: %v", err)
	}
}

func TestRetentionKeepBytes(t *testing.T) {
	t.Parallel()
	b, d, _ := newTestBackups(t)
	ctx := context.Background()
	// One byte forces the sweep after every run; the newest backup must
	// still survive it.
	if err := d.SettingSet(ctx, settingBackupKeepBytes, "1", 1); err != nil {
		t.Fatal(err)
	}
	first := createAndRun(t, b)
	second := createAndRun(t, b)
	third := createAndRun(t, b)

	rows, err := b.List(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].ID != third.ID {
		t.Fatalf("rows after byte sweep = %+v", rows)
	}
	for _, gone := range []wdb.Backup{first, second} {
		if _, err := os.Stat(b.archivePath(gone.FileName)); !os.IsNotExist(err) {
			t.Fatalf("swept archive %s still on disk", gone.FileName)
		}
	}
	if _, err := os.Stat(b.archivePath(third.FileName)); err != nil {
		t.Fatalf("newest archive missing: %v", err)
	}
}

// validArchiveBytes builds a minimal well-formed backup archive.
func validArchiveBytes(t *testing.T) []byte {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for name, content := range map[string]string{
		"waxbin.db":     "imported waxbin",
		"waxdeck.db":    "imported waxdeck",
		"manifest.json": `{"formatVersion":1,"createdAt":"2026-01-01T00:00:00Z"}`,
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
	return buf.Bytes()
}

func TestImportValidation(t *testing.T) {
	t.Parallel()
	b, _, _ := newTestBackups(t)
	ctx := context.Background()

	_, err := b.Import(ctx, nil, strings.NewReader("this is not a zip"), 0)
	wantKind(t, err, KindInvalid)

	// A zip that is not a backup (missing entries) is refused too.
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, _ := zw.Create("random.txt")
	w.Write([]byte("hello"))
	zw.Close()
	_, err = b.Import(ctx, nil, bytes.NewReader(buf.Bytes()), 0)
	wantKind(t, err, KindInvalid)

	// A wrong-version manifest is refused.
	var v2 bytes.Buffer
	zw = zip.NewWriter(&v2)
	for name, content := range map[string]string{
		"waxbin.db": "x", "waxdeck.db": "x", "manifest.json": `{"formatVersion":2}`,
	} {
		w, _ := zw.Create(name)
		w.Write([]byte(content))
	}
	zw.Close()
	_, err = b.Import(ctx, nil, bytes.NewReader(v2.Bytes()), 0)
	wantKind(t, err, KindInvalid)

	// Over the byte limit is a quota refusal.
	_, err = b.Import(ctx, nil, bytes.NewReader(validArchiveBytes(t)), 10)
	wantKind(t, err, KindQuota)

	// No stray temp files survive the refusals.
	if names, err := os.ReadDir(b.backupsDir()); err == nil {
		for _, e := range names {
			t.Fatalf("unexpected file after refused imports: %s", e.Name())
		}
	}
}

func TestImportAcceptsValidArchive(t *testing.T) {
	t.Parallel()
	b, _, _ := newTestBackups(t)
	ctx := context.Background()
	raw := validArchiveBytes(t)
	row, err := b.Import(ctx, nil, bytes.NewReader(raw), int64(len(raw)))
	if err != nil {
		t.Fatal(err)
	}
	if row.State != "done" || row.Origin != "imported" || row.SizeBytes != int64(len(raw)) {
		t.Fatalf("imported row = %+v", row)
	}
	if !strings.HasPrefix(row.FileName, "waxdeck-backup-imported-") {
		t.Fatalf("imported file name = %s", row.FileName)
	}
	if _, err := b.ArchivePath(ctx, row.ID); err != nil {
		t.Fatalf("imported archive path: %v", err)
	}
}

func TestStageCancelMarkerRoundTrip(t *testing.T) {
	t.Parallel()
	b, _, dataDir := newTestBackups(t)
	ctx := context.Background()
	b.prober = func(ctx context.Context, path string) (bool, bool, []SealedCasualty) {
		raw, err := os.ReadFile(path)
		if err != nil || !bytes.HasPrefix(raw, []byte("SQLite format 3\x00")) {
			t.Errorf("prober got a non-sqlite waxdeck.db at %s", path)
		}
		return true, false, []SealedCasualty{{Kind: "app-password", Name: "alice/phone"}}
	}
	row := createAndRun(t, b)

	plan, err := b.StageRestore(ctx, nil, row.ID)
	if err != nil {
		t.Fatal(err)
	}
	if plan.BackupID != row.ID || !plan.KeyfilePresent || plan.KeyfileMatches {
		t.Fatalf("plan = %+v", plan)
	}
	if len(plan.SealedCasualties) != 1 || plan.SealedCasualties[0].Name != "alice/phone" {
		t.Fatalf("casualties = %+v", plan.SealedCasualties)
	}

	// The marker file carries the shape internal/restore reads.
	raw, err := os.ReadFile(filepath.Join(dataDir, "restore-staged.json"))
	if err != nil {
		t.Fatal(err)
	}
	var m struct {
		BackupID string `json:"backupId"`
		FileName string `json:"fileName"`
	}
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatal(err)
	}
	if m.BackupID != row.ID || m.FileName != row.FileName {
		t.Fatalf("marker = %+v", m)
	}

	got, err := b.StagedRestore(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if got.BackupID != row.ID || len(got.SealedCasualties) != 1 {
		t.Fatalf("staged plan = %+v", got)
	}

	// A staged backup cannot be deleted out from under the restore.
	err = b.Delete(ctx, nil, row.ID)
	wantKind(t, err, KindConflict)

	if err := b.CancelStagedRestore(ctx, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dataDir, "restore-staged.json")); !os.IsNotExist(err) {
		t.Fatal("marker survived cancel")
	}
	_, err = b.StagedRestore(ctx)
	wantKind(t, err, KindNotFound)
	err = b.CancelStagedRestore(ctx, nil)
	wantKind(t, err, KindNotFound)

	// With nothing staged the delete goes through, file and row.
	if err := b.Delete(ctx, nil, row.ID); err != nil {
		t.Fatal(err)
	}
	_, err = b.Get(ctx, row.ID)
	wantKind(t, err, KindNotFound)
	if _, err := os.Stat(b.archivePath(row.FileName)); !os.IsNotExist(err) {
		t.Fatalf("deleted archive still on disk: %v", err)
	}
}

func TestStageRefusesUnfinishedAndWarnsWithoutProber(t *testing.T) {
	t.Parallel()
	b, _, _ := newTestBackups(t)
	ctx := context.Background()

	running, err := b.Create(ctx, nil, "manual")
	if err != nil {
		t.Fatal(err)
	}
	_, err = b.StageRestore(ctx, nil, running.ID)
	wantKind(t, err, KindConflict)
	if err := b.Run(ctx, running.ID); err != nil {
		t.Fatal(err)
	}

	_, err = b.StageRestore(ctx, nil, "bu-01JZX5N8QW3F4V9T2B7KDEAAAA")
	wantKind(t, err, KindNotFound)

	// No prober wired: staging still works, flagged by a warning.
	plan, err := b.StageRestore(ctx, nil, running.ID)
	if err != nil {
		t.Fatal(err)
	}
	if plan.KeyfilePresent || plan.KeyfileMatches {
		t.Fatalf("plan without prober = %+v", plan)
	}
	found := false
	for _, w := range plan.Warnings {
		if strings.Contains(w, "key prober") {
			found = true
		}
	}
	if !found {
		t.Fatalf("warnings = %v, want a no-prober warning", plan.Warnings)
	}
	if err := b.CancelStagedRestore(ctx, nil); err != nil {
		t.Fatal(err)
	}
}
