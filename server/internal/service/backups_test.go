package service

import (
	"archive/zip"
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/port"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// testCatalog is the narrow catalog seam: it writes an empty database
// stamped like a catalog where the real facade would write a waxbin.db
// snapshot, or raw when set, and keeps the options it was asked for.
type testCatalog struct {
	fail bool
	raw  []byte
	opts *port.BackupOptions
}

// testCatalogStamp is the fake catalog's baseline stamp, and the live
// catalog's for newTestBackups.
const testCatalogStamp uint32 = 0x7e57ca7a

func (c testCatalog) Backup(ctx context.Context, dest string, opts port.BackupOptions) error {
	if c.opts != nil {
		*c.opts = opts
	}
	if c.fail {
		return errors.New("catalog snapshot exploded")
	}
	if c.raw != nil {
		return os.WriteFile(dest, c.raw, 0o600)
	}
	db, err := sql.Open("sqlite", "file:"+dest)
	if err != nil {
		return err
	}
	defer db.Close()
	_, err = db.ExecContext(ctx, fmt.Sprintf("PRAGMA user_version = %d", int32(testCatalogStamp)))
	return err
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
	b.catalogStamp = func(context.Context) (uint32, error) { return testCatalogStamp, nil }
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
	if stamp, err := sqliteHeaderVersion(bytes.NewReader(entries["waxbin.db"])); err != nil || stamp != testCatalogStamp {
		t.Fatalf("waxbin.db entry stamp = (%x, %v), want the catalog's snapshot", stamp, err)
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

// The catalog copy is one VACUUM INTO: a trim would rewrite the whole
// copy again, with scratch space its size outside the data volume.
func TestBackupCopiesTheCatalogInOnePass(t *testing.T) {
	t.Parallel()
	b, _, _ := newTestBackups(t)
	got := port.BackupOptions{OmitThumbnails: true}
	b.catalog = testCatalog{opts: &got}
	createAndRun(t, b)
	if got != (port.BackupOptions{}) {
		t.Errorf("backup options = %+v, want a whole copy", got)
	}
}

// Staging reads the live catalog's stamp from the file the server has
// open, so a backup this server just took stages.
func TestABackupStagesUnderTheLiveCatalogsStamp(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	b := NewBackups(svc, t.TempDir(), nil)
	row, err := b.Create(ctx, nil, "manual")
	if err != nil {
		t.Fatal(err)
	}
	if err := b.Run(ctx, row.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := b.StageRestore(ctx, nil, row.ID); err != nil {
		t.Fatalf("staging this server's own backup: %v", err)
	}
}

// An archive whose catalog another baseline made would leave a server
// that refuses to start, or with the reset flag one that discards what
// was restored, so staging refuses it.
func TestStageRefusesACatalogFromAnotherBaseline(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	current := filepath.Join(t.TempDir(), "current.db")
	if err := openBareCatalog(t, waxbin.Options{}).Backup(ctx, current, port.BackupOptions{}); err != nil {
		t.Fatal(err)
	}
	healthy, err := os.ReadFile(current)
	if err != nil {
		t.Fatal(err)
	}
	execCatalog(t, current, "PRAGMA user_version = 1")
	stale, err := os.ReadFile(current)
	if err != nil {
		t.Fatal(err)
	}

	b, _, dataDir := newTestBackups(t)
	b.catalogStamp = func(ctx context.Context) (uint32, error) {
		return catalogFileStamp(ctx, filepath.Join(t.TempDir(), "absent.db"))
	}
	b.catalog = testCatalog{raw: healthy}
	healthyRow := createAndRun(t, b)
	_, err = b.StageRestore(ctx, nil, healthyRow.ID)
	wantKind(t, err, KindInternal)
	live := filepath.Join(t.TempDir(), "live.db")
	if err := os.WriteFile(live, healthy, 0o600); err != nil {
		t.Fatal(err)
	}
	b.catalogStamp = func(ctx context.Context) (uint32, error) { return catalogFileStamp(ctx, live) }
	b.catalog = testCatalog{raw: stale}
	_, err = b.StageRestore(ctx, nil, createAndRun(t, b).ID)
	wantKind(t, err, KindInvalid)
	if !errors.Is(err, ErrArchiveSchema) || !strings.Contains(err.Error(), "version it was taken with") {
		t.Errorf("the refusal does not say what to do: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dataDir, "restore-staged.json")); !os.IsNotExist(err) {
		t.Fatal("a refused archive was staged anyway")
	}

	if _, err := b.StageRestore(ctx, nil, healthyRow.ID); err != nil {
		t.Fatalf("staging an archive of this baseline: %v", err)
	}
}

// The server database half has a baseline of its own: an archive whose
// waxdeck.db another baseline made would leave a server that refuses to
// start, so staging refuses it too.
func TestStageRefusesAServerDatabaseFromAnotherBaseline(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	b, d, dataDir := newTestBackups(t)
	var live string
	if err := d.Reader().QueryRowContext(ctx,
		"SELECT value FROM sync_state WHERE key = 'schema.baseline'").Scan(&live); err != nil {
		t.Fatal(err)
	}
	setBaseline := func(v string) {
		t.Helper()
		if _, err := d.Writer().ExecContext(ctx,
			"UPDATE sync_state SET value = ? WHERE key = 'schema.baseline'", v); err != nil {
			t.Fatal(err)
		}
	}
	setBaseline("an-older-baseline")
	stale := createAndRun(t, b)
	setBaseline(live)

	_, err := b.StageRestore(ctx, nil, stale.ID)
	wantKind(t, err, KindInvalid)
	if !errors.Is(err, ErrArchiveSchema) {
		t.Errorf("refusal = %v, want the schema one", err)
	}
	if _, err := os.Stat(filepath.Join(dataDir, "restore-staged.json")); !os.IsNotExist(err) {
		t.Fatal("a refused archive was staged anyway")
	}
	if _, err := b.StageRestore(ctx, nil, createAndRun(t, b).ID); err != nil {
		t.Fatalf("staging an archive of this baseline: %v", err)
	}
}

// What staging cannot read it refuses, and a request gone before the
// verdict stages nothing.
func TestStageFailsClosed(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	b, _, dataDir := newTestBackups(t)
	marker := filepath.Join(dataDir, "restore-staged.json")
	noMarker := func(name string) {
		t.Helper()
		if _, err := os.Stat(marker); !os.IsNotExist(err) {
			t.Fatalf("%s: staged anyway", name)
		}
	}

	b.catalog = testCatalog{raw: []byte("not a database")}
	_, err := b.StageRestore(ctx, nil, createAndRun(t, b).ID)
	wantKind(t, err, KindInvalid)
	noMarker("a catalog that is not one")

	b.catalog = testCatalog{}
	row := createAndRun(t, b)
	archive := b.archivePath(row.FileName)
	rewriteEntry(t, archive, archiveEntryWaxdeck, []byte("not a database either"))
	_, err = b.StageRestore(ctx, nil, row.ID)
	wantKind(t, err, KindInvalid)
	noMarker("a server database that is not one")

	gone, cancel := context.WithCancel(ctx)
	b.prober = func(context.Context, string) (bool, bool, []SealedCasualty) {
		cancel()
		return true, true, nil
	}
	if _, err := b.StageRestore(gone, nil, createAndRun(t, b).ID); err == nil {
		t.Fatal("staged for a request that was gone")
	}
	noMarker("a request gone")
}

// rewriteEntry swaps one entry of a zip archive for body.
func rewriteEntry(t *testing.T, archive, name string, body []byte) {
	t.Helper()
	zr, err := zip.OpenReader(archive)
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	for _, f := range zr.File {
		w, err := zw.Create(f.Name)
		if err != nil {
			t.Fatal(err)
		}
		if f.Name == name {
			if _, err := w.Write(body); err != nil {
				t.Fatal(err)
			}
			continue
		}
		rc, err := f.Open()
		if err != nil {
			t.Fatal(err)
		}
		if _, err := io.Copy(w, rc); err != nil {
			t.Fatal(err)
		}
		rc.Close()
	}
	zr.Close()
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(archive, buf.Bytes(), 0o600); err != nil {
		t.Fatal(err)
	}
}

// The boot-time apply asks the same of the extracted files, so a restore
// staged before an upgrade cannot set the live databases aside for ones
// this build refuses.
func TestVetRestoreRefusesWhatThisBuildWouldNotOpen(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	dir := t.TempDir()
	catalog := filepath.Join(dir, "waxbin.db")
	if err := openBareCatalog(t, waxbin.Options{}).Backup(ctx, catalog, port.BackupOptions{}); err != nil {
		t.Fatal(err)
	}
	server := filepath.Join(dir, "waxdeck.db")
	d, err := wdb.Open(ctx, server)
	if err != nil {
		t.Fatal(err)
	}
	if err := d.Close(); err != nil {
		t.Fatal(err)
	}
	if err := VetRestore(server, catalog); err != nil {
		t.Fatalf("vetting databases this build made: %v", err)
	}
	stale := filepath.Join(dir, "stale.db")
	raw, err := os.ReadFile(catalog)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(stale, raw, 0o600); err != nil {
		t.Fatal(err)
	}
	execCatalog(t, stale, "PRAGMA user_version = 1")
	// The reason is about the archive: advice to delete or read a file
	// would point the operator at the live database or a temp copy.
	refused := func(name string, err error) {
		t.Helper()
		if err == nil {
			t.Errorf("vetted a %s another baseline made", name)
		} else if msg := err.Error(); strings.Contains(msg, "delete") || strings.Contains(msg, dir) {
			t.Errorf("the %s refusal advises the wrong file: %s", name, msg)
		}
	}
	refused("catalog", VetRestore(server, stale))
	execCatalog(t, server, "UPDATE sync_state SET value = 'elsewhere' WHERE key = 'schema.baseline'")
	refused("server database", VetRestore(server, catalog))
}
