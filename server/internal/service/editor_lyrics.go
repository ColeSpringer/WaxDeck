package service

import (
	"bytes"
	"cmp"
	"context"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	waxlabel "github.com/colespringer/waxlabel"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/scan"
)

// SetItemLyrics stores replacement lyrics (parsed LRC and/or a plain
// block) with user provenance. With writeBack the .lrc sidecar is
// written next to the backing file with crash-safe discipline. Embedded
// tag write-back is deliberately skipped here: the catalog row plus the
// sidecar carry the contract, and embedded lyrics follow along on the
// next tag write (MP4 and Matroska refuse embedded synced lyrics
// upstream anyway, so the sidecar is the durable form).
func (l *Editor) SetItemLyrics(ctx context.Context, uc *UserCtx, apiPID, lrc, plain string, p MetadataEditParams) (EditOutcomeDTO, error) {
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if len(lrc) > 200000 || len(plain) > 200000 {
		return EditOutcomeDTO{}, errInvalid("lyrics are limited to 200000 characters per block")
	}
	if p.WriteBack && it.Kind == model.KindEpisode {
		return EditOutcomeDTO{}, errInvalid("podcast episodes never write back to files; edits are database-only by upstream design")
	}
	var warnings []string
	var synced []model.SyncedLine
	if lrc != "" {
		lines, dropped := waxlabel.ParseLRCReportFull(lrc)
		for _, n := range dropped {
			warnings = append(warnings, "lrc line "+strconv.Itoa(n)+": no timed lyric, skipped")
		}
		synced = make([]model.SyncedLine, 0, len(lines))
		for _, ln := range lines {
			synced = append(synced, model.SyncedLine{TimeMS: ln.Time.Milliseconds(), Text: ln.Text})
		}
	}
	ly := &model.Lyrics{Source: model.SourceUser, Synced: synced, Unsynced: plain}
	if !ly.HasContent() {
		return EditOutcomeDTO{}, errInvalid("lyrics must carry timed lines or plain text")
	}
	if p.WriteBack {
		if err := l.Settings.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	if err := l.lib.SetLyrics(ctx, it.PID, ly, model.LockOf(p.Lock), p.Force); err != nil {
		return EditOutcomeDTO{}, classify(err)
	}
	out := EditOutcomeDTO{Warnings: warnings}
	if p.WriteBack {
		if fail := l.writeLyricsSidecar(ctx, it, synced, plain); fail != nil {
			out.Failures = append(out.Failures, *fail)
		}
	}
	return out, nil
}

// writeLyricsSidecar writes the .lrc sidecar next to the item's backing
// file. The catalog edit has already committed, so any refusal or
// failure is reported as a write-back failure, never an error. A carved
// track's would be the whole rip's, which a scan reads into none of its
// tracks.
func (l *Editor) writeLyricsSidecar(ctx context.Context, it *model.ItemView, synced []model.SyncedLine, plain string) *WriteBackFailureDTO {
	if it.Virtual {
		return sidecarFailure(it, it.DisplayPath, "the backing file is shared by several items; sidecar write-back is refused")
	}
	path, sidecar, fail := l.lyricsSidecarFor(ctx, it)
	if fail != nil {
		return fail
	}
	content := plain
	if len(synced) > 0 {
		content = syncedLRC(synced)
	}
	if !strings.HasSuffix(content, "\n") {
		content += "\n"
	}
	if err := writeFileCrashSafe(sidecar, []byte(content), sidecarMode(sidecar, path)); err != nil {
		return sidecarFailure(it, sidecar, "sidecar write failed: "+err.Error())
	}
	return nil
}

// lyricsSidecarFor is what writing and removing an item's .lrc share:
// the audio file it sits beside and the sidecar, or the failure that
// leaves it alone. A sidecar another audio file of that name reads is
// that file's too, and one in a folder that cannot be listed may be.
func (l *Editor) lyricsSidecarFor(ctx context.Context, it *model.ItemView) (audio, sidecar string, fail *WriteBackFailureDTO) {
	audio = cmp.Or(string(it.Path), it.DisplayPath)
	if audio == "" {
		return "", "", sidecarFailure(it, "", "no backing file path is known")
	}
	sidecar = lyricsSidecar(audio)
	switch shared, err := l.sidecarShared(ctx, it.PID, audio); {
	case err != nil:
		return "", "", sidecarFailure(it, sidecar, "whether another audio file of this name reads the sidecar could not be checked, so it stayed: "+err.Error())
	case shared:
		return "", "", sidecarFailure(it, sidecar, "another audio file of this name reads the sidecar too, so it stayed")
	}
	return audio, sidecar, nil
}

// sidecarFailure is a sidecar write-back failure on the item's file.
func sidecarFailure(it *model.ItemView, path, reason string) *WriteBackFailureDTO {
	return &WriteBackFailureDTO{FilePID: string(it.FilePID), Path: path, Reason: reason}
}

// lyricsSidecar is the .lrc beside an audio file.
func lyricsSidecar(audio string) string {
	return strings.TrimSuffix(audio, filepath.Ext(audio)) + ".lrc"
}

// sidecarMode is the mode a file written beside another takes: the mode
// of the file it replaces, else fileModeBeside's. A temp file is created
// 0600, which would leave lyrics a player reading the library as another
// user cannot open.
func sidecarMode(target, beside string) os.FileMode {
	if st, err := os.Stat(target); err == nil {
		return st.Mode().Perm()
	}
	return fileModeBeside(beside)
}

// fileModeBeside is the mode of a new file made from or beside another:
// the other's less any execute bit, else 0644.
func fileModeBeside(other string) os.FileMode {
	if st, err := os.Stat(other); err == nil {
		return st.Mode().Perm() &^ 0o111
	}
	return 0o644
}

// chmodTempFile sets a crash-safe write's temp file mode; a test stands a
// mount that refuses it in. Nothing in the server sets it.
var chmodTempFile = (*os.File).Chmod

// writeFileCrashSafe writes bytes with the repo's durability rule:
// temp file in the target directory, verify the written bytes, fsync,
// atomic rename, fsync the directory. The file takes perm where the
// mount keeps modes.
func writeFileCrashSafe(path string, data []byte, perm os.FileMode) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".tmp*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	// A temp file is created 0600. The mode is best effort, as the tag
	// writer's is: a mount that refuses it still takes the sidecar.
	_ = chmodTempFile(tmp, perm)
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	written, err := os.ReadFile(tmpName)
	if err != nil {
		return err
	}
	if !bytes.Equal(written, data) {
		return errors.New("verification re-read does not match the written bytes")
	}
	if err := os.Rename(tmpName, path); err != nil {
		return err
	}
	if d, err := os.Open(dir); err == nil {
		_ = d.Sync()
		d.Close()
	}
	return nil
}

// ClearItemLyrics removes the stored lyrics and their lock. Force is
// implied: the caller explicitly chose the clear, which also unlocks.
// With writeBack the .lrc sidecar a write-back set wrote goes too, so a
// rescan cannot read the lyrics back from it; lyrics embedded in the
// audio stay. A sidecar that could not go is a write-back failure beside
// the standing clear. A carved track has none to remove.
func (l *Editor) ClearItemLyrics(ctx context.Context, uc *UserCtx, apiPID string, p MetadataEditParams) (EditOutcomeDTO, error) {
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if p.WriteBack {
		if err := l.Settings.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	if err := l.lib.SetLyrics(ctx, it.PID, nil, model.LockOff, true); err != nil {
		return EditOutcomeDTO{}, classify(err)
	}
	if !p.WriteBack {
		return EditOutcomeDTO{}, nil
	}
	if fail := l.removeLyricsSidecar(ctx, it); fail != nil {
		return EditOutcomeDTO{Failures: []WriteBackFailureDTO{*fail}}, nil
	}
	return EditOutcomeDTO{}, nil
}

// removeLyricsSidecar deletes the .lrc beside the item's file, as the
// sidecar write-back's undo; one that is not there is already gone. A
// carved track has none: a scan reads no sidecar into one, and the rip's
// is no track's to remove.
func (l *Editor) removeLyricsSidecar(ctx context.Context, it *model.ItemView) *WriteBackFailureDTO {
	if it.Virtual {
		return nil
	}
	_, sidecar, fail := l.lyricsSidecarFor(ctx, it)
	if fail != nil {
		return fail
	}
	if err := os.Remove(sidecar); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return sidecarFailure(it, sidecar, "sidecar removal failed: "+err.Error())
	}
	if d, err := os.Open(filepath.Dir(sidecar)); err == nil {
		_ = d.Sync()
		d.Close()
	}
	return nil
}

// sidecarShared reports whether an audio file beside path shares its
// name, so reads path's sidecar, other than the item's own files: its
// other encodings read the item's lyrics. Names compare without case, as
// a case-insensitive filesystem would give either file the sidecar. What
// it cannot read, the item's files or the folder, is an error, never a no.
func (l *Editor) sidecarShared(ctx context.Context, item model.PID, path string) (bool, error) {
	dir := filepath.Dir(path)
	own := map[string]bool{filepath.Base(path): true}
	refs, err := l.lib.ItemFiles(ctx, item)
	if err != nil {
		return false, err
	}
	for _, ref := range refs {
		if p := cmp.Or(string(ref.Path), ref.DisplayPath); filepath.Dir(p) == dir {
			own[filepath.Base(p)] = true
		}
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return false, err
	}
	stem := func(name string) string { return strings.ToLower(strings.TrimSuffix(name, filepath.Ext(name))) }
	for _, e := range entries {
		if !own[e.Name()] && e.Type().IsRegular() && scan.IsAudio(e.Name()) && stem(e.Name()) == stem(filepath.Base(path)) {
			return true, nil
		}
	}
	return false, nil
}
