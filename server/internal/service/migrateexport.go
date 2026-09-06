package service

import (
	"archive/zip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"

	"github.com/oklog/ulid/v2"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Staged account data exports. A streaming service hands its users a zip
// rather than an API, so the import reads a file: it is uploaded here,
// recognised, and held under the staging directory until the import that
// reads it finishes or the expiry sweep runs. Nothing here writes into
// the library, and the archive is never unpacked to disk - only read.

const (
	// migrateExportTTL is how long a staged export waits for the import
	// that reads it. Long enough to survive a distraction, short enough
	// that a household's listening history is not sitting on the server
	// indefinitely.
	migrateExportTTL = 24 * time.Hour
	// migrateExportOrphanGrace is how long the orphan sweep leaves a
	// freshly written archive alone. A stage places the file and then
	// inserts the row that names it, and between the two the file looks
	// exactly like an orphan; the window is milliseconds, so anything
	// this side of it belongs to a stage that is still running.
	migrateExportOrphanGrace = 15 * time.Minute
)

// migrateExportMaxBytes bounds one upload. A decade of Spotify history
// is a few tens of megabytes; half a gigabyte is generous against an
// archive somebody uploaded by mistake. A variable rather than a
// constant for the same reason the free-space probe is a field: the
// refusal is worth a test, and half a gigabyte of test upload is not.
var migrateExportMaxBytes int64 = 512 << 20

// MigrationExportDTO is one staged export as the API reports it.
type MigrationExportDTO struct {
	PID       string
	Source    string
	Files     []string
	SizeBytes int64
	ExpiresAt time.Time
}

// migrationExportsDir is where staged archives live: under staging,
// beside uploads, on the volume checkStagingRoom probes.
func (l *Library) migrationExportsDir() string {
	return filepath.Join(l.stagingDir, "migrations")
}

func (l *Library) migrationExportPath(fileName string) string {
	return filepath.Join(l.migrationExportsDir(), fileName)
}

// StageMigrationExport stores one uploaded archive and reports what was
// recognised in it. `declared` is the request's content length when it
// gave one, so a body too large for the volume is refused before it is
// read rather than after.
func (l *Library) StageMigrationExport(ctx context.Context, uc *UserCtx, r io.Reader, declared int64) (MigrationExportDTO, error) {
	if !uc.Admin {
		return MigrationExportDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	if declared > migrateExportMaxBytes {
		return MigrationExportDTO{}, &Error{Kind: KindQuota,
			Msg: fmt.Sprintf("the export exceeds the %d byte upload limit", migrateExportMaxBytes)}
	}
	if declared > 0 {
		if err := l.checkStagingRoom(ctx, declared); err != nil {
			return MigrationExportDTO{}, err
		}
	}
	dir := l.migrationExportsDir()
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return MigrationExportDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	id := PrefixMigrationExport + "-" + ulid.Make().String()
	fileName := id + ".zip"
	// Temp file in the target directory, fsynced, then read back as a
	// zip before the atomic rename: the archive import beside this one
	// verifies the same way, and parsing what landed proves more than
	// a byte comparison would.
	tmp, err := os.CreateTemp(dir, "."+fileName+".tmp*")
	if err != nil {
		return MigrationExportDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	n, err := io.Copy(tmp, io.LimitReader(r, migrateExportMaxBytes+1))
	if err != nil {
		tmp.Close()
		if errors.Is(err, syscall.ENOSPC) {
			// The volume filled under the write. A client that declared
			// its length was refused before a byte of it was read; one
			// that did not is refused here, and with the same code, so
			// the answer does not depend on how the body was framed.
			return MigrationExportDTO{}, &Error{Kind: KindStorageFull,
				Msg: "the server has no room to stage this upload"}
		}
		return MigrationExportDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	if n > migrateExportMaxBytes {
		tmp.Close()
		return MigrationExportDTO{}, &Error{Kind: KindQuota,
			Msg: fmt.Sprintf("the export exceeds the %d byte upload limit", migrateExportMaxBytes)}
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return MigrationExportDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	if err := tmp.Close(); err != nil {
		return MigrationExportDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	source, files, err := recogniseMigrationExport(tmpName)
	if err != nil {
		return MigrationExportDTO{}, err
	}
	target := l.migrationExportPath(fileName)
	if err := os.Rename(tmpName, target); err != nil {
		return MigrationExportDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	// The file is on the volume before the row that names it, so every
	// way out from here removes it: the sweep would eventually, but not
	// before a day of half a gigabyte nothing can reach.
	placed := false
	defer func() {
		if !placed {
			os.Remove(target)
		}
	}()
	if d, err := os.Open(dir); err == nil {
		_ = d.Sync()
		d.Close()
	}

	now := time.Now()
	expires := now.Add(migrateExportTTL)
	row := wdb.MigrationExport{
		ID: id, UserID: uc.ID, FileName: fileName, SizeBytes: n,
		Source: source, FilesJSON: marshalJSON(files),
		CreatedAtNS: now.UnixNano(), ExpiresAtNS: expires.UnixNano(),
	}
	if err := l.db.InsertMigrationExport(ctx, row); err != nil {
		return MigrationExportDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	placed = true
	l.Audit(ctx, uc, "migration.export.stage", AuditTarget{Kind: "migration-export", PID: id, Name: source}, map[string]any{
		"source": source, "files": len(files), "sizeBytes": n,
	})
	return MigrationExportDTO{PID: id, Source: source, Files: files, SizeBytes: n, ExpiresAt: expires}, nil
}

// DiscardMigrationExport deletes one staged export and its file.
func (l *Library) DiscardMigrationExport(ctx context.Context, uc *UserCtx, id string) error {
	if !uc.Admin {
		return &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	row, err := l.ownedMigrationExport(ctx, uc, id)
	if err != nil {
		return err
	}
	// Answered rather than warned about. A discard that failed leaves
	// half a gigabyte of somebody's listening history on the volume the
	// catalog databases share, and the screen that asked has already
	// let go of the only handle on it.
	return l.dropMigrationExport(ctx, row)
}

// ownedMigrationExport resolves a staged export for the administrator
// who uploaded it, and only for them.
//
// Administrators are not interchangeable here. The archive is one
// person's listening history, uploaded for one import: reading it from
// another account's order would hand that history over, and the import
// deletes the file when it finishes, so it would take the upload with
// it. An expired row is refused for the reason it is swept - the upload
// was abandoned - rather than waiting for the hourly pass to say so.
func (l *Library) ownedMigrationExport(ctx context.Context, uc *UserCtx, id string) (wdb.MigrationExport, error) {
	row, err := l.db.MigrationExportByID(ctx, id)
	if err != nil && !errors.Is(err, wdb.ErrNotFound) {
		// A read that failed is not an export that is absent. Answering
		// 404 to it would hide a database in trouble behind a sentence
		// about the upload, and nothing would ever page anyone.
		return wdb.MigrationExport{}, &Error{Kind: KindInternal, Err: err}
	}
	if err != nil || row.UserID != uc.ID {
		return wdb.MigrationExport{}, errNotFound("no staged export with id " + id)
	}
	if time.Now().UnixNano() >= row.ExpiresAtNS {
		return wdb.MigrationExport{}, errNotFound("that staged export has expired; upload it again")
	}
	return row, nil
}

// exportIsBeingRead reports whether a live tool task holds this upload.
// A claim left behind by a task that is over says nothing: that is the
// stale claim the next import replaces.
func (l *Library) exportIsBeingRead(ctx context.Context, row wdb.MigrationExport) bool {
	if row.ClaimedBy == "" {
		return false
	}
	t, err := l.db.ToolTaskByID(ctx, row.ClaimedBy)
	if err != nil {
		return false
	}
	return t.State != taskStateDone && t.State != taskStateFailed
}

// dropMigrationExport removes an export's file and then its row. File
// first: a row without a file is a 404 the caller can act on, while a
// file without a row is bytes nothing will ever delete.
func (l *Library) dropMigrationExport(ctx context.Context, row wdb.MigrationExport) error {
	if err := os.Remove(l.migrationExportPath(row.FileName)); err != nil && !os.IsNotExist(err) {
		l.log.Warn("deleting a staged export", "export", row.ID, "err", err)
		return &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.DeleteMigrationExport(ctx, row.ID); err != nil {
		l.log.Warn("deleting a staged export row", "export", row.ID, "err", err)
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// SweepMigrationExports deletes the staged exports that expired, and
// the archives no row names any more. Runs on the janitor's ticker
// beside the other prunes.
func (l *Library) SweepMigrationExports(ctx context.Context) {
	rows, err := l.db.ExpiredMigrationExports(ctx, time.Now().UnixNano())
	if err != nil {
		l.log.Warn("sweeping staged exports", "err", err)
		return
	}
	for _, row := range rows {
		if l.exportIsBeingRead(ctx, row) {
			// Its day is up, but an import is walking it right now: the
			// expiry is fixed at upload and nothing extends it, so an
			// order placed near the end of the window lands here mid-run.
			// Taking the file out from under that run would fail the
			// import over a deadline nobody can see. The next pass gets
			// it, and the import that holds it deletes it first anyway.
			continue
		}
		// Already logged when it fails, and the row stays for the next
		// pass rather than the sweep giving up on it.
		_ = l.dropMigrationExport(ctx, row)
	}
	l.sweepOrphanExports(ctx)
}

// sweepOrphanExports removes archives with no row behind them. The
// upload writes the file and then the row, so a crash between the two
// leaves up to half a gigabyte on the volume that staging shares with
// the databases, addressable by nothing. Named by their own id, so the
// check is one point read each.
func (l *Library) sweepOrphanExports(ctx context.Context) {
	dir := l.migrationExportsDir()
	entries, err := os.ReadDir(dir)
	if err != nil {
		if !os.IsNotExist(err) {
			l.log.Warn("reading the staged export directory", "err", err)
		}
		return
	}
	for _, e := range entries {
		name := e.Name()
		if e.IsDir() || !strings.HasSuffix(name, ".zip") {
			// A temp file from an upload in flight keeps its dot prefix
			// and no suffix of ours; leaving those alone is the point.
			continue
		}
		id := strings.TrimSuffix(name, ".zip")
		_, err := l.db.MigrationExportByID(ctx, id)
		if err == nil {
			continue
		}
		if !errors.Is(err, wdb.ErrNotFound) {
			// Only a row that is definitely absent orphans a file. A
			// cancelled context or a busy database is not an answer,
			// and deleting on one would empty this directory during a
			// shutdown while every row survived.
			l.log.Warn("reading a staged export row", "export", id, "err", err)
			continue
		}
		// A stage puts the file on the volume before the row that names
		// it, so a file younger than the grace window may be one of
		// those rather than an orphan. Older than that and the stage
		// that would have inserted the row is long over.
		if info, err := e.Info(); err == nil && time.Since(info.ModTime()) < migrateExportOrphanGrace {
			continue
		}
		if err := os.Remove(filepath.Join(dir, name)); err != nil && !os.IsNotExist(err) {
			l.log.Warn("deleting an orphaned export archive", "file", name, "err", err)
			continue
		}
		l.log.Info("deleted an orphaned export archive", "file", name)
	}
}

// migrationExportFile resolves a staged export for the import that
// reads it: the row, and the path its archive lives at.
func (l *Library) migrationExportFile(ctx context.Context, id string) (wdb.MigrationExport, string, error) {
	row, err := l.db.MigrationExportByID(ctx, id)
	if errors.Is(err, wdb.ErrNotFound) {
		return wdb.MigrationExport{}, "", fmt.Errorf("%w: the uploaded export is gone", errToolPermanent)
	}
	if err != nil {
		// Retryable on purpose: the row and the archive are both still
		// there, and retiring a leased import over a read that failed
		// would lose an upload nothing can produce again.
		return wdb.MigrationExport{}, "", err
	}
	return row, l.migrationExportPath(row.FileName), nil
}

// spotifyExportFile reports whether one archive entry is a file the
// Spotify import reads: the two shapes of streaming history, and the
// library file the loved tracks come from. Matched anywhere in the tree,
// because the account export nests them under a folder whose name
// carries the account holder's own name.
//
// The podcast and audiobook history files are deliberately not read:
// they are siblings of the music one with the same prefix, and nothing
// in them resolves against a music catalog.
func spotifyExportFile(name string) bool {
	base := path.Base(name)
	if base == "YourLibrary.json" {
		return true
	}
	if !strings.HasSuffix(base, ".json") {
		return false
	}
	lower := strings.ToLower(base)
	// The spoken-word and video siblings sit beside the music history
	// under the same naming, and nothing in them resolves against a
	// music catalog.
	if strings.Contains(lower, "podcast") || strings.Contains(lower, "audiobook") ||
		strings.Contains(lower, "video") {
		return false
	}
	return spotifyExtendedHistory(base) || spotifyBasicHistory(base)
}

// spotifyExtendedHistory reports whether one entry is a file of the
// extended streaming history. Two namings, because the package has been
// renamed since: an export requested before that answered with
// `endsong_0.json`, and the rows inside are the shape this import
// already reads.
func spotifyExtendedHistory(base string) bool {
	return strings.HasPrefix(base, "Streaming_History_Audio_") ||
		strings.HasPrefix(base, "endsong_")
}

// spotifyBasicHistory is the same for the account-data package, whose
// older naming leaves the medium out of the middle:
// `StreamingHistory0.json` beside `StreamingHistory_music_0.json`.
func spotifyBasicHistory(base string) bool {
	return strings.HasPrefix(base, "StreamingHistory")
}

// recogniseMigrationExport opens an uploaded archive and says which
// service it came from and which of its files will be read. An archive
// that is not a zip, or holds nothing readable, is refused here: staging
// it would only defer the same refusal to a task report nobody is
// watching.
func recogniseMigrationExport(archive string) (string, []string, error) {
	zr, err := zip.OpenReader(archive)
	if err != nil {
		return "", nil, &Error{Kind: KindInvalid, Msg: "that is not a zip archive"}
	}
	defer zr.Close()
	var files, basic []string
	extended := false
	for _, f := range zr.File {
		if f.FileInfo().IsDir() {
			continue
		}
		if !spotifyExportFile(f.Name) {
			continue
		}
		base := path.Base(f.Name)
		switch {
		case spotifyExtendedHistory(base):
			extended = true
			files = append(files, f.Name)
		case spotifyBasicHistory(base):
			basic = append(basic, f.Name)
		default:
			files = append(files, f.Name)
		}
	}
	// The two history packages cover the same listening, and neither
	// records a play the other could be matched against: the basic one
	// stamps the minute a play ended, the extended one the second. So
	// an archive holding both is read as the extended one alone -
	// reading both would count every overlapping year twice, and the
	// deterministic ids cannot fold two different times together.
	if !extended {
		files = append(files, basic...)
	}
	if len(files) == 0 {
		return "", nil, &Error{Kind: KindInvalid,
			Msg: "nothing in that archive is an account export this server can read"}
	}
	sort.Strings(files)
	return migrateSourceSpotify, files, nil
}

// exportFiles decodes the recognised file list stored with a row.
func exportFiles(row wdb.MigrationExport) []string {
	var out []string
	_ = json.Unmarshal([]byte(row.FilesJSON), &out)
	return out
}
