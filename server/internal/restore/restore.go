// Package restore applies a staged database restore at boot, before
// anything opens either database. The service layer stages a restore by
// writing restore-staged.json beside the databases; main calls Apply
// first thing, and only afterwards opens waxdeck.db and the catalog.
//
// Crash safety is ordering: the archive is extracted fully to temp
// files first, then the live databases are set aside and the extracted
// copies renamed in, and the marker is removed last. A crash anywhere
// before marker removal leaves the marker in place, so the next boot
// re-runs the same restore from the same archive; re-extracting over an
// already-applied restore just replaces the databases with identical
// bytes, so the retry is idempotent.
package restore

import (
	"archive/zip"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"time"
)

const (
	markerFileName = "restore-staged.json"
	backupsDirName = "backups"

	entryWaxdeck = "waxdeck.db"
	entryWaxbin  = "waxbin.db"
)

// restoreEntries are the database files a restore swaps in, in swap
// order.
var restoreEntries = []string{entryWaxdeck, entryWaxbin}

// marker is the subset of restore-staged.json this package acts on;
// the service layer owns the full shape.
type marker struct {
	BackupID string `json:"backupId"`
	FileName string `json:"fileName"`
}

// Report says what Apply did, for the caller to log and audit once the
// server is open.
type Report struct {
	BackupID string
	FileName string
	// SetAside are the base names the previous databases (and their
	// WAL and shm siblings) were renamed to.
	SetAside []string
}

// Apply performs the staged restore if one is marked. It returns
// (false, nil, nil) when nothing is staged. On error the marker is left
// in place: the boot that failed to restore must not quietly come up on
// the old data while the operator believes the restore happened; they
// remove restore-staged.json to boot without it.
func Apply(dataDir string, log *slog.Logger) (applied bool, report *Report, err error) {
	if log == nil {
		log = slog.New(slog.DiscardHandler)
	}
	m, err := readMarker(dataDir)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil, nil
	}
	if err != nil {
		return false, nil, err
	}
	log.Info("applying staged restore", "backup", m.BackupID, "archive", m.FileName)

	archive := filepath.Join(dataDir, backupsDirName, m.FileName)
	if _, err := os.Stat(archive); err != nil {
		return false, nil, fmt.Errorf(
			"restore: staged archive %s is missing; remove %s to boot without restoring: %w",
			archive, filepath.Join(dataDir, markerFileName), err)
	}

	tmps, err := extractArchive(archive, dataDir)
	if err != nil {
		removeTemps(tmps)
		return false, nil, fmt.Errorf("restore: extracting %s: %w", m.FileName, err)
	}

	ts := time.Now().UTC().Format("20060102-150405")
	setAside, err := swapIn(dataDir, tmps, ts)
	if err != nil {
		removeTemps(tmps)
		return false, nil, fmt.Errorf("restore: swapping in %s: %w", m.FileName, err)
	}

	// Marker removal is last: everything before this point retries at
	// the next boot. If removal itself fails, the restore has still
	// happened; the next boot redoes it harmlessly.
	if err := removeMarker(dataDir); err != nil {
		log.Warn("restore applied but the marker could not be removed; the next boot will re-apply it", "err", err)
	}
	log.Info("staged restore applied", "backup", m.BackupID, "setAside", setAside)
	return true, &Report{BackupID: m.BackupID, FileName: m.FileName, SetAside: setAside}, nil
}

// readMarker loads and validates restore-staged.json. A missing file
// surfaces as os.ErrNotExist.
func readMarker(dataDir string) (marker, error) {
	raw, err := os.ReadFile(filepath.Join(dataDir, markerFileName))
	if err != nil {
		return marker{}, err
	}
	var m marker
	if err := json.Unmarshal(raw, &m); err != nil {
		return marker{}, fmt.Errorf("restore: corrupt %s: %w", markerFileName, err)
	}
	if m.FileName == "" || m.FileName != filepath.Base(m.FileName) {
		return marker{}, fmt.Errorf("restore: %s names an invalid archive %q", markerFileName, m.FileName)
	}
	return m, nil
}

// extractArchive copies the two database entries out of the archive
// into fsynced temp files in dataDir, keyed by entry name. On error the
// caller removes whatever was created.
func extractArchive(archivePath, dataDir string) (map[string]string, error) {
	zr, err := zip.OpenReader(archivePath)
	if err != nil {
		return nil, err
	}
	defer zr.Close()
	byName := map[string]*zip.File{}
	for _, f := range zr.File {
		byName[f.Name] = f
	}
	tmps := map[string]string{}
	for _, name := range restoreEntries {
		f := byName[name]
		if f == nil {
			return tmps, fmt.Errorf("the archive has no %s", name)
		}
		tmp, err := extractOne(f, dataDir, ".restore-"+name+"-*")
		if err != nil {
			return tmps, err
		}
		tmps[name] = tmp
	}
	return tmps, nil
}

func extractOne(f *zip.File, dir, pattern string) (string, error) {
	rc, err := f.Open()
	if err != nil {
		return "", err
	}
	defer rc.Close()
	out, err := os.CreateTemp(dir, pattern)
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

// swapIn sets the current databases aside and renames the extracted
// copies into place. Missing current files are fine (a new host). The
// WAL and shm siblings move with their database so the restored file
// cannot be recovered against a stale journal.
func swapIn(dataDir string, tmps map[string]string, ts string) ([]string, error) {
	var setAside []string
	for _, name := range restoreEntries {
		live := filepath.Join(dataDir, name)
		for _, suffix := range []string{"", "-wal", "-shm"} {
			p := live + suffix
			if _, err := os.Lstat(p); err != nil {
				continue
			}
			aside := p + ".pre-restore-" + ts
			if err := os.Rename(p, aside); err != nil {
				return setAside, err
			}
			setAside = append(setAside, filepath.Base(aside))
		}
		if err := os.Rename(tmps[name], live); err != nil {
			return setAside, err
		}
	}
	fsyncDir(dataDir)
	return setAside, nil
}

// removeMarker deletes restore-staged.json and makes the removal
// durable.
func removeMarker(dataDir string) error {
	if err := os.Remove(filepath.Join(dataDir, markerFileName)); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	fsyncDir(dataDir)
	return nil
}

func removeTemps(tmps map[string]string) {
	for _, p := range tmps {
		os.Remove(p)
	}
}

// fsyncDir makes directory-entry changes durable where the filesystem
// supports it; failures are not actionable here.
func fsyncDir(dir string) {
	if d, err := os.Open(dir); err == nil {
		_ = d.Sync()
		d.Close()
	}
}
