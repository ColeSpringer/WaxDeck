package service

import (
	"archive/zip"
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/oklog/ulid/v2"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The backup subsystem: full-fidelity archives of both databases, an
// import door for archives from another host, and a staged restore the
// boot path (internal/restore) applies before anything opens. The
// archive is a zip holding waxbin.db (catalog snapshot), waxdeck.db
// (VACUUM INTO snapshot), and manifest.json.

const (
	backupsDirName    = "backups"
	restoreMarkerName = "restore-staged.json"

	archiveEntryWaxbin   = "waxbin.db"
	archiveEntryWaxdeck  = "waxdeck.db"
	archiveEntryManifest = "manifest.json"

	backupStateRunning = "running"
	backupStateDone    = "done"
	backupStateFailed  = "failed"

	originManual    = "manual"
	originScheduled = "scheduled"
	originImported  = "imported"

	backupFormatVersion = 1

	// backupStaleWarnAge is how old an archive gets before staging it
	// warns that current data is likely much newer.
	backupStaleWarnAge = 30 * 24 * time.Hour
)

// backupCatalog is the one catalog capability backups need: a
// consistent byte copy of waxbin.db written to a path. *waxbin.Library
// satisfies it; tests substitute a fake.
type backupCatalog interface {
	Backup(ctx context.Context, dest string, redact bool) error
}

// backupAuditor records backup and restore actions; *Library satisfies
// it.
type backupAuditor interface {
	Audit(ctx context.Context, actor *UserCtx, action string, target AuditTarget, detail map[string]any)
}

// SealedCasualty is one sealed credential a restore onto a different
// key cannot recover (an app password, a private feed's password, a
// scrobble connection). Kind names the credential class, Name the
// affected row for the operator.
type SealedCasualty struct {
	Kind string `json:"kind"`
	Name string `json:"name"`
}

// KeyProber inspects an archive's extracted waxdeck.db and reports
// whether this host holds a key file, whether that key decrypts the
// archive's sealed rows, and which sealed credentials would be lost on
// mismatch. The real implementation lives with the sealer wiring; a nil
// prober downgrades the preflight to a warning.
type KeyProber func(ctx context.Context, waxdeckDBPath string) (present, matches bool, casualties []SealedCasualty)

// RestorePlan is the staged-restore preflight: what applying the named
// backup at next boot would mean.
type RestorePlan struct {
	BackupID         string
	StagedAtNS       int64
	KeyfilePresent   bool
	KeyfileMatches   bool
	SealedCasualties []SealedCasualty
	Warnings         []string
}

// RestoreReportLike carries what the boot-time apply did, for the
// post-open sweep. It mirrors internal/restore's Report without
// importing it, plus the sealed casualties recorded at staging time.
type RestoreReportLike struct {
	BackupID   string
	FileName   string
	SetAside   []string
	Casualties []SealedCasualty
}

// backupManifest is the archive's self-description.
type backupManifest struct {
	FormatVersion int      `json:"formatVersion"`
	CreatedAt     string   `json:"createdAt"`
	WaxdeckSchema int      `json:"waxdeckSchema"`
	FileNames     []string `json:"fileNames"`
}

// stagedMarker is the restore-staged.json shape. internal/restore reads
// backupId and fileName; the rest replays the plan to the admin UI.
type stagedMarker struct {
	BackupID         string           `json:"backupId"`
	FileName         string           `json:"fileName"`
	StagedAtNS       int64            `json:"stagedAtNS"`
	KeyfilePresent   bool             `json:"keyfilePresent"`
	KeyfileMatches   bool             `json:"keyfileMatches"`
	SealedCasualties []SealedCasualty `json:"sealedCasualties,omitempty"`
	Warnings         []string         `json:"warnings,omitempty"`
}

// Backups is the backup and staged-restore service. It is constructed
// beside the Library service (which does not hold the data dir) and
// works through narrow seams so tests need no catalog.
type Backups struct {
	db      *wdb.DB
	catalog backupCatalog
	audit   backupAuditor
	log     *slog.Logger
	dataDir string
	prober  KeyProber
	// now is the clock, injectable so tests control file names and
	// retention ordering.
	now func() time.Time
	// inflight guards Run against concurrent execution of the same
	// backup: the runner's orphan sweep and the scheduler both call
	// Run, and a slow archive must not be built twice over the same
	// id-keyed temp paths.
	inflightMu sync.Mutex
	inflight   map[string]bool
}

// NewBackups builds the backup service over the library service's
// database, catalog, and audit trail. dataDir is the server data
// directory (archives live in its backups folder, the staged-restore
// marker at its top level). prober may be nil until the key preflight
// is wired; staging then reports the gap as a warning.
func NewBackups(l *Library, dataDir string, prober KeyProber) *Backups {
	return newBackups(l.db, l.lib, l, l.log, dataDir, prober)
}

func newBackups(store *wdb.DB, catalog backupCatalog, audit backupAuditor, log *slog.Logger, dataDir string, prober KeyProber) *Backups {
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	return &Backups{
		db:      store,
		catalog: catalog,
		audit:   audit,
		log:     log,
		dataDir: dataDir,
		prober:  prober,
		now:     time.Now,
	}
}

func (b *Backups) backupsDir() string { return filepath.Join(b.dataDir, backupsDirName) }
func (b *Backups) markerPath() string { return filepath.Join(b.dataDir, restoreMarkerName) }
func (b *Backups) archivePath(fileName string) string {
	return filepath.Join(b.backupsDir(), fileName)
}

// Create claims the single running-backup slot and returns the running
// row. The caller's worker loop performs the actual archive write by
// invoking Run with the returned id; Create itself does no file work.
func (b *Backups) Create(ctx context.Context, actor *UserCtx, origin string) (wdb.Backup, error) {
	if origin != originManual && origin != originScheduled {
		return wdb.Backup{}, errInvalid("backup origin must be manual or scheduled")
	}
	if err := os.MkdirAll(b.backupsDir(), 0o700); err != nil {
		return wdb.Backup{}, &Error{Kind: KindInternal, Err: err}
	}
	now := b.now().UTC()
	row := wdb.Backup{
		ID:          PrefixBackup + "-" + ulid.Make().String(),
		State:       backupStateRunning,
		Origin:      origin,
		FileName:    b.uniqueBackupFileName(now),
		CreatedAtNS: now.UnixNano(),
	}
	if err := b.db.ClaimBackupSlot(ctx, row); err != nil {
		if errors.Is(err, wdb.ErrConflict) {
			return wdb.Backup{}, &Error{Kind: KindConflict, Msg: "a backup is already running"}
		}
		return wdb.Backup{}, &Error{Kind: KindInternal, Err: err}
	}
	b.audit.Audit(ctx, actor, "backup.create",
		AuditTarget{Kind: "backup", PID: row.ID, Name: row.FileName},
		map[string]any{"origin": origin})
	return row, nil
}

// uniqueBackupFileName renders the timestamped archive name, stepping a
// numeric suffix when a same-second archive already exists on disk.
func (b *Backups) uniqueBackupFileName(now time.Time) string {
	base := "waxdeck-backup-" + now.Format("20060102-150405")
	name := base + ".zip"
	for i := 2; ; i++ {
		// Any stat error ends the search: not-exist means the name is
		// free, and anything else (permissions, a clobbered directory)
		// will surface properly from the write that follows — looping
		// on it would spin forever.
		if _, err := os.Lstat(b.archivePath(name)); err != nil {
			return name
		}
		name = fmt.Sprintf("%s-%d.zip", base, i)
	}
}

// Run performs the archive write for a claimed backup: snapshot both
// databases, zip them with a manifest, land the file atomically, mark
// the row done or failed, and apply retention. It runs synchronously on
// the caller's worker loop; the creating actor is gone by now, so its
// audit entries carry the origin instead.
func (b *Backups) Run(ctx context.Context, id string) error {
	b.inflightMu.Lock()
	if b.inflight == nil {
		b.inflight = map[string]bool{}
	}
	if b.inflight[id] {
		// Someone is already building this archive (the sweep racing
		// the scheduler); one builder is success, not conflict.
		b.inflightMu.Unlock()
		return nil
	}
	b.inflight[id] = true
	b.inflightMu.Unlock()
	defer func() {
		b.inflightMu.Lock()
		delete(b.inflight, id)
		b.inflightMu.Unlock()
	}()

	row, err := b.db.BackupByID(ctx, id)
	if errors.Is(err, wdb.ErrNotFound) {
		return errNotFound("no backup with id " + id)
	}
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if row.State != backupStateRunning {
		return &Error{Kind: KindConflict, Msg: "the backup is not running"}
	}

	size, buildErr := b.buildArchive(ctx, row)
	row.FinishedAtNS = b.now().UnixNano()
	if buildErr != nil {
		row.State = backupStateFailed
		row.Error = buildErr.Error()
	} else {
		row.State = backupStateDone
		row.SizeBytes = size
	}
	if err := b.db.UpdateBackup(ctx, row); err != nil {
		b.log.Warn("recording backup outcome", "backup", row.ID, "err", err)
	}
	b.audit.Audit(ctx, nil, "backup.finish",
		AuditTarget{Kind: "backup", PID: row.ID, Name: row.FileName},
		map[string]any{"origin": row.Origin, "state": row.State,
			"sizeBytes": row.SizeBytes, "error": row.Error})
	if buildErr != nil {
		return &Error{Kind: KindInternal, Err: buildErr}
	}
	if err := b.applyRetention(ctx); err != nil {
		// Retention failing must not fail the backup that just landed.
		b.log.Warn("applying backup retention", "err", err)
	}
	return nil
}

// buildArchive writes the zip beside its final name and renames it in,
// returning the landed size. Every intermediate lives in the backups
// dir so the final rename stays on one filesystem.
func (b *Backups) buildArchive(ctx context.Context, row wdb.Backup) (int64, error) {
	dir := b.backupsDir()
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return 0, err
	}

	catTmp := filepath.Join(dir, ".waxbin-"+row.ID+".tmp")
	defer os.Remove(catTmp)
	if err := b.catalog.Backup(ctx, catTmp, false); err != nil {
		return 0, fmt.Errorf("catalog snapshot: %w", err)
	}

	wdTmp := filepath.Join(dir, ".waxdeck-"+row.ID+".tmp")
	defer os.Remove(wdTmp)
	// VACUUM INTO produces a consistent single-file snapshot of the
	// live database. The statement cannot take the path as a bind
	// parameter, so it is inlined; the path is server-built, and the
	// quoting below is belt and braces.
	stmt := fmt.Sprintf("VACUUM INTO '%s'", strings.ReplaceAll(wdTmp, "'", "''"))
	if _, err := b.db.Writer().ExecContext(ctx, stmt); err != nil {
		return 0, fmt.Errorf("waxdeck snapshot: %w", err)
	}

	schema, err := b.liveSchemaVersion(ctx)
	if err != nil {
		return 0, fmt.Errorf("reading schema version: %w", err)
	}
	manifest := backupManifest{
		FormatVersion: backupFormatVersion,
		CreatedAt:     b.now().UTC().Format(time.RFC3339),
		WaxdeckSchema: schema,
		FileNames:     []string{archiveEntryWaxbin, archiveEntryWaxdeck},
	}

	zf, err := os.CreateTemp(dir, "."+row.FileName+".tmp-*")
	if err != nil {
		return 0, err
	}
	tmpName := zf.Name()
	defer os.Remove(tmpName)
	if err := writeArchive(zf, manifest, catTmp, wdTmp); err != nil {
		zf.Close()
		return 0, err
	}
	if err := zf.Sync(); err != nil {
		zf.Close()
		return 0, err
	}
	if err := zf.Close(); err != nil {
		return 0, err
	}
	// Verify before landing: the archive must read back as a valid
	// backup, or the row must fail instead of pointing at garbage.
	if _, err := readArchiveManifest(tmpName); err != nil {
		return 0, fmt.Errorf("verifying archive: %w", err)
	}
	final := b.archivePath(row.FileName)
	if err := os.Rename(tmpName, final); err != nil {
		return 0, err
	}
	backupFsyncDir(dir)
	st, err := os.Stat(final)
	if err != nil {
		return 0, err
	}
	return st.Size(), nil
}

// writeArchive streams the two snapshots and the manifest into zw's
// file.
func writeArchive(zf *os.File, manifest backupManifest, catPath, wdPath string) error {
	zw := zip.NewWriter(zf)
	for _, e := range []struct{ name, path string }{
		{archiveEntryWaxbin, catPath},
		{archiveEntryWaxdeck, wdPath},
	} {
		w, err := zw.CreateHeader(&zip.FileHeader{Name: e.name, Method: zip.Deflate})
		if err != nil {
			return err
		}
		src, err := os.Open(e.path)
		if err != nil {
			return err
		}
		_, err = io.Copy(w, src)
		src.Close()
		if err != nil {
			return err
		}
	}
	mw, err := zw.CreateHeader(&zip.FileHeader{Name: archiveEntryManifest, Method: zip.Deflate})
	if err != nil {
		return err
	}
	raw, err := json.Marshal(manifest)
	if err != nil {
		return err
	}
	if _, err := mw.Write(raw); err != nil {
		return err
	}
	return zw.Close()
}

// readArchiveManifest validates that path is a WaxDeck backup archive
// (both database entries plus a version-1 manifest) and returns the
// manifest.
func readArchiveManifest(path string) (backupManifest, error) {
	zr, err := zip.OpenReader(path)
	if err != nil {
		return backupManifest{}, errors.New("not a zip archive")
	}
	defer zr.Close()
	entries := map[string]*zip.File{}
	for _, f := range zr.File {
		entries[f.Name] = f
	}
	for _, want := range []string{archiveEntryWaxbin, archiveEntryWaxdeck, archiveEntryManifest} {
		if entries[want] == nil {
			return backupManifest{}, fmt.Errorf("missing %s", want)
		}
	}
	rc, err := entries[archiveEntryManifest].Open()
	if err != nil {
		return backupManifest{}, err
	}
	defer rc.Close()
	var m backupManifest
	if err := json.NewDecoder(io.LimitReader(rc, 1<<20)).Decode(&m); err != nil {
		return backupManifest{}, errors.New("unreadable manifest")
	}
	if m.FormatVersion != backupFormatVersion {
		return backupManifest{}, fmt.Errorf("unsupported format version %d", m.FormatVersion)
	}
	return m, nil
}

// extractArchiveEntry copies one named entry out of the archive into a
// temp file in dir, fsynced; the caller removes it.
func extractArchiveEntry(archivePath, entryName, dir, tmpPattern string) (string, error) {
	zr, err := zip.OpenReader(archivePath)
	if err != nil {
		return "", err
	}
	defer zr.Close()
	for _, f := range zr.File {
		if f.Name != entryName {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return "", err
		}
		defer rc.Close()
		out, err := os.CreateTemp(dir, tmpPattern)
		if err != nil {
			return "", err
		}
		if _, err := io.Copy(out, rc); err != nil {
			out.Close()
			os.Remove(out.Name())
			return "", err
		}
		if err := out.Sync(); err != nil {
			out.Close()
			os.Remove(out.Name())
			return "", err
		}
		if err := out.Close(); err != nil {
			os.Remove(out.Name())
			return "", err
		}
		return out.Name(), nil
	}
	return "", fmt.Errorf("archive has no %s", entryName)
}

// liveSchemaVersion reads the running waxdeck.db schema version.
func (b *Backups) liveSchemaVersion(ctx context.Context) (int, error) {
	var v int
	err := b.db.Reader().QueryRowContext(ctx, "PRAGMA user_version").Scan(&v)
	return v, err
}

// sqliteUserVersion reads an at-rest database file's schema version
// straight from the header (offset 60, big endian). The files backups
// carry come from Backup and VACUUM INTO, so they have no WAL and the
// header is authoritative; this avoids opening a second connection.
func sqliteUserVersion(path string) (int, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	var hdr [100]byte
	if _, err := io.ReadFull(f, hdr[:]); err != nil {
		return 0, errors.New("file too small for an sqlite database")
	}
	if string(hdr[:16]) != "SQLite format 3\x00" {
		return 0, errors.New("not an sqlite database")
	}
	return int(binary.BigEndian.Uint32(hdr[60:64])), nil
}

// applyRetention prunes finished non-imported backups: newest-first
// keep-count, then oldest-first size sweep against keep-bytes. Zero
// means unlimited for each. The newest surviving backup is never
// deleted by the size sweep, so a fresh backup outlives a keep-bytes
// setting smaller than one archive.
func (b *Backups) applyRetention(ctx context.Context) error {
	keepCount, keepBytes := b.retentionPolicy(ctx)
	if keepCount <= 0 && keepBytes <= 0 {
		return nil
	}
	rows, err := b.db.ListBackups(ctx)
	if err != nil {
		return err
	}
	var candidates []wdb.Backup // newest first, per ListBackups
	for _, r := range rows {
		if r.State == backupStateDone && r.Origin != originImported {
			candidates = append(candidates, r)
		}
	}
	var deleted []wdb.Backup
	if keepCount > 0 && len(candidates) > keepCount {
		for _, victim := range candidates[keepCount:] {
			if err := b.removeBackup(ctx, victim); err != nil {
				return err
			}
			deleted = append(deleted, victim)
		}
		candidates = candidates[:keepCount]
	}
	if keepBytes > 0 {
		var total int64
		for _, r := range candidates {
			total += r.SizeBytes
		}
		for total > keepBytes && len(candidates) > 1 {
			victim := candidates[len(candidates)-1]
			if err := b.removeBackup(ctx, victim); err != nil {
				return err
			}
			deleted = append(deleted, victim)
			total -= victim.SizeBytes
			candidates = candidates[:len(candidates)-1]
		}
	}
	if len(deleted) > 0 {
		names := make([]string, 0, len(deleted))
		ids := make([]string, 0, len(deleted))
		for _, d := range deleted {
			names = append(names, d.FileName)
			ids = append(ids, d.ID)
		}
		b.audit.Audit(ctx, nil, "backup.retention", AuditTarget{Kind: "backup"},
			map[string]any{"deleted": ids, "fileNames": names,
				"keepCount": keepCount, "keepBytes": keepBytes})
	}
	return nil
}

func (b *Backups) retentionPolicy(ctx context.Context) (keepCount int, keepBytes int64) {
	if v, err := b.db.SettingGet(ctx, settingBackupKeep); err == nil {
		keepCount, _ = strconv.Atoi(v)
	}
	if v, err := b.db.SettingGet(ctx, settingBackupKeepBytes); err == nil {
		keepBytes, _ = strconv.ParseInt(v, 10, 64)
	}
	return keepCount, keepBytes
}

// removeBackup deletes the archive file then the row, in that order: a
// crash between the two leaves a row whose download 404s, never an
// orphaned archive retention cannot see.
func (b *Backups) removeBackup(ctx context.Context, row wdb.Backup) error {
	p := b.archivePath(row.FileName)
	if err := os.Remove(p); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	backupFsyncDir(b.backupsDir())
	if err := b.db.DeleteBackup(ctx, row.ID); err != nil && !errors.Is(err, wdb.ErrNotFound) {
		return err
	}
	return nil
}

// List returns every backup row, newest first.
func (b *Backups) List(ctx context.Context) ([]wdb.Backup, error) {
	rows, err := b.db.ListBackups(ctx)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	return rows, nil
}

// Get returns one backup row.
func (b *Backups) Get(ctx context.Context, id string) (wdb.Backup, error) {
	row, err := b.db.BackupByID(ctx, id)
	if errors.Is(err, wdb.ErrNotFound) {
		return wdb.Backup{}, errNotFound("no backup with id " + id)
	}
	if err != nil {
		return wdb.Backup{}, &Error{Kind: KindInternal, Err: err}
	}
	return row, nil
}

// Delete removes a backup's archive and row. It refuses while the
// backup is running or while a staged restore references it.
func (b *Backups) Delete(ctx context.Context, actor *UserCtx, id string) error {
	row, err := b.Get(ctx, id)
	if err != nil {
		return err
	}
	if row.State == backupStateRunning {
		return &Error{Kind: KindConflict, Msg: "the backup is still running"}
	}
	if m, ok, err := b.readStagedMarker(); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	} else if ok && m.BackupID == id {
		return &Error{Kind: KindConflict, Msg: "a staged restore references this backup; cancel it first"}
	}
	if err := b.removeBackup(ctx, row); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	b.audit.Audit(ctx, actor, "backup.delete",
		AuditTarget{Kind: "backup", PID: row.ID, Name: row.FileName},
		map[string]any{"origin": row.Origin, "sizeBytes": row.SizeBytes})
	return nil
}

// ArchivePath resolves a finished backup's archive file for the
// download handler.
func (b *Backups) ArchivePath(ctx context.Context, id string) (string, error) {
	row, err := b.Get(ctx, id)
	if err != nil {
		return "", err
	}
	if row.State != backupStateDone {
		return "", &Error{Kind: KindConflict, Msg: "the backup has no downloadable archive"}
	}
	p := b.archivePath(row.FileName)
	if _, err := os.Stat(p); err != nil {
		return "", errNotFound("the backup archive file is missing")
	}
	return p, nil
}

// Import lands an uploaded archive: stream to a temp file, validate it
// is a WaxDeck backup, rename it in, and record the row. maxBytes
// bounds the stream when positive.
func (b *Backups) Import(ctx context.Context, actor *UserCtx, r io.Reader, maxBytes int64) (wdb.Backup, error) {
	dir := b.backupsDir()
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return wdb.Backup{}, &Error{Kind: KindInternal, Err: err}
	}
	tmp, err := os.CreateTemp(dir, ".import-*.tmp")
	if err != nil {
		return wdb.Backup{}, &Error{Kind: KindInternal, Err: err}
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	src := r
	if maxBytes > 0 {
		src = io.LimitReader(r, maxBytes+1)
	}
	n, err := io.Copy(tmp, src)
	if err != nil {
		tmp.Close()
		return wdb.Backup{}, &Error{Kind: KindInternal, Err: err}
	}
	if maxBytes > 0 && n > maxBytes {
		tmp.Close()
		return wdb.Backup{}, &Error{Kind: KindQuota,
			Msg: fmt.Sprintf("the archive exceeds the %d byte import limit", maxBytes)}
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return wdb.Backup{}, &Error{Kind: KindInternal, Err: err}
	}
	if err := tmp.Close(); err != nil {
		return wdb.Backup{}, &Error{Kind: KindInternal, Err: err}
	}
	if _, err := readArchiveManifest(tmpName); err != nil {
		return wdb.Backup{}, &Error{Kind: KindInvalid,
			Msg: "not a WaxDeck backup archive: " + err.Error()}
	}

	now := b.now().UTC()
	base := "waxdeck-backup-imported-" + now.Format("20060102-150405")
	fileName := base + ".zip"
	for i := 2; ; i++ {
		if _, err := os.Lstat(b.archivePath(fileName)); err != nil {
			break // free name, or a failure the rename below will surface
		}
		fileName = fmt.Sprintf("%s-%d.zip", base, i)
	}
	if err := os.Rename(tmpName, b.archivePath(fileName)); err != nil {
		return wdb.Backup{}, &Error{Kind: KindInternal, Err: err}
	}
	backupFsyncDir(dir)

	row := wdb.Backup{
		ID:           PrefixBackup + "-" + ulid.Make().String(),
		State:        backupStateDone,
		Origin:       originImported,
		FileName:     fileName,
		SizeBytes:    n,
		CreatedAtNS:  now.UnixNano(),
		FinishedAtNS: now.UnixNano(),
	}
	if err := b.db.InsertBackup(ctx, row); err != nil {
		return wdb.Backup{}, &Error{Kind: KindInternal, Err: err}
	}
	b.audit.Audit(ctx, actor, "backup.import",
		AuditTarget{Kind: "backup", PID: row.ID, Name: row.FileName},
		map[string]any{"sizeBytes": n})
	return row, nil
}

// StageRestore runs the restore preflight for a finished backup and
// persists the staged-restore marker the boot path acts on. Staging
// replaces any prior staged restore.
func (b *Backups) StageRestore(ctx context.Context, actor *UserCtx, id string) (RestorePlan, error) {
	row, err := b.Get(ctx, id)
	if err != nil {
		return RestorePlan{}, err
	}
	if row.State != backupStateDone {
		return RestorePlan{}, &Error{Kind: KindConflict, Msg: "only completed backups can be staged for restore"}
	}
	archive := b.archivePath(row.FileName)
	manifest, err := readArchiveManifest(archive)
	if err != nil {
		return RestorePlan{}, &Error{Kind: KindInvalid, Msg: "the archive is unreadable: " + err.Error()}
	}
	probeDB, err := extractArchiveEntry(archive, archiveEntryWaxdeck, b.backupsDir(), ".probe-*.tmp")
	if err != nil {
		return RestorePlan{}, &Error{Kind: KindInternal, Err: err}
	}
	defer os.Remove(probeDB)

	plan := RestorePlan{BackupID: id, StagedAtNS: b.now().UnixNano()}
	if b.prober != nil {
		plan.KeyfilePresent, plan.KeyfileMatches, plan.SealedCasualties = b.prober(ctx, probeDB)
	} else {
		plan.Warnings = append(plan.Warnings,
			"no key prober is wired; sealed credentials were not checked against this host's key")
	}
	if archiveVer, err := sqliteUserVersion(probeDB); err != nil {
		plan.Warnings = append(plan.Warnings,
			"the archive's waxdeck.db could not be inspected: "+err.Error())
	} else if liveVer, err := b.liveSchemaVersion(ctx); err == nil && archiveVer > liveVer {
		plan.Warnings = append(plan.Warnings, fmt.Sprintf(
			"the archive's schema (v%d) is newer than this server understands (v%d); upgrade the server before restoring", archiveVer, liveVer))
	}
	if created, err := time.Parse(time.RFC3339, manifest.CreatedAt); err == nil {
		if age := b.now().Sub(created); age > backupStaleWarnAge {
			plan.Warnings = append(plan.Warnings, fmt.Sprintf(
				"the archive is %d days old; data written since then will be lost", int(age.Hours()/24)))
		}
	}

	marker := stagedMarker{
		BackupID:         plan.BackupID,
		FileName:         row.FileName,
		StagedAtNS:       plan.StagedAtNS,
		KeyfilePresent:   plan.KeyfilePresent,
		KeyfileMatches:   plan.KeyfileMatches,
		SealedCasualties: plan.SealedCasualties,
		Warnings:         plan.Warnings,
	}
	if err := b.writeStagedMarker(marker); err != nil {
		return RestorePlan{}, &Error{Kind: KindInternal, Err: err}
	}
	b.audit.Audit(ctx, actor, "restore.stage",
		AuditTarget{Kind: "backup", PID: id, Name: row.FileName},
		map[string]any{"keyfilePresent": plan.KeyfilePresent,
			"keyfileMatches": plan.KeyfileMatches,
			"casualties":     len(plan.SealedCasualties),
			"warnings":       plan.Warnings})
	return plan, nil
}

// StagedRestore reports the currently staged restore, if any.
func (b *Backups) StagedRestore(ctx context.Context) (RestorePlan, error) {
	m, ok, err := b.readStagedMarker()
	if err != nil {
		return RestorePlan{}, &Error{Kind: KindInternal, Err: err}
	}
	if !ok {
		return RestorePlan{}, errNotFound("no restore is staged")
	}
	return RestorePlan{
		BackupID:         m.BackupID,
		StagedAtNS:       m.StagedAtNS,
		KeyfilePresent:   m.KeyfilePresent,
		KeyfileMatches:   m.KeyfileMatches,
		SealedCasualties: m.SealedCasualties,
		Warnings:         m.Warnings,
	}, nil
}

// CancelStagedRestore removes the staged-restore marker.
func (b *Backups) CancelStagedRestore(ctx context.Context, actor *UserCtx) error {
	m, ok, err := b.readStagedMarker()
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if !ok {
		return errNotFound("no restore is staged")
	}
	if err := os.Remove(b.markerPath()); err != nil && !errors.Is(err, os.ErrNotExist) {
		return &Error{Kind: KindInternal, Err: err}
	}
	backupFsyncDir(b.dataDir)
	b.audit.Audit(ctx, actor, "restore.cancel",
		AuditTarget{Kind: "backup", PID: m.BackupID, Name: m.FileName}, nil)
	return nil
}

// PostRestoreSweep runs after the server reopens on restored databases:
// it records what the boot-time apply did and flags the sealed
// credentials that need re-entry. The sync stream reset itself happens
// earlier and elsewhere: main clears sync_state between the boot-time
// apply and the service open, so the reopened streams mint fresh
// generations and every outstanding client cursor answers sync-reset.
func (b *Backups) PostRestoreSweep(ctx context.Context, rep RestoreReportLike) error {
	detail := map[string]any{"backupId": rep.BackupID, "fileName": rep.FileName}
	if len(rep.SetAside) > 0 {
		detail["setAside"] = rep.SetAside
	}
	b.audit.Audit(ctx, nil, "restore.apply",
		AuditTarget{Kind: "backup", PID: rep.BackupID, Name: rep.FileName}, detail)
	if len(rep.Casualties) > 0 {
		list := make([]map[string]string, 0, len(rep.Casualties))
		for _, c := range rep.Casualties {
			list = append(list, map[string]string{"kind": c.Kind, "name": c.Name})
		}
		b.audit.Audit(ctx, nil, "restore.credentials-pending",
			AuditTarget{Kind: "backup", PID: rep.BackupID, Name: rep.FileName},
			map[string]any{"casualties": list})
	}
	return nil
}

// readStagedMarker loads the marker; ok is false when none is staged.
func (b *Backups) readStagedMarker() (stagedMarker, bool, error) {
	raw, err := os.ReadFile(b.markerPath())
	if errors.Is(err, os.ErrNotExist) {
		return stagedMarker{}, false, nil
	}
	if err != nil {
		return stagedMarker{}, false, err
	}
	var m stagedMarker
	if err := json.Unmarshal(raw, &m); err != nil {
		return stagedMarker{}, false, fmt.Errorf("corrupt staged-restore marker: %w", err)
	}
	return m, true, nil
}

// writeStagedMarker lands the marker atomically in the data dir.
func (b *Backups) writeStagedMarker(m stagedMarker) error {
	raw, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(b.dataDir, "."+restoreMarkerName+".tmp-*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.Write(raw); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpName, b.markerPath()); err != nil {
		return err
	}
	backupFsyncDir(b.dataDir)
	return nil
}

// backupFsyncDir makes a directory rename durable where the
// filesystem supports it; failures are not actionable here.
func backupFsyncDir(dir string) {
	if d, err := os.Open(dir); err == nil {
		_ = d.Sync()
		d.Close()
	}
}

// SweepTempFiles removes orphaned temp files from the backups
// directory. Every intermediate this package writes is dot-prefixed
// and carries ".tmp" in its name; at startup no backup can be running,
// so any survivor is a crash leftover holding space for nothing.
func (b *Backups) SweepTempFiles() {
	entries, err := os.ReadDir(b.backupsDir())
	if err != nil {
		return // no directory yet, nothing to sweep
	}
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || !strings.HasPrefix(name, ".") || !strings.Contains(name, ".tmp") {
			continue
		}
		if err := os.Remove(filepath.Join(b.backupsDir(), name)); err != nil {
			b.log.Warn("removing orphaned backup temp file", "file", name, "err", err)
		} else {
			b.log.Info("removed orphaned backup temp file", "file", name)
		}
	}
}
