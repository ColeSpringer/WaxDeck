// Package atomicfile writes the files the server's generators emit: a
// temp file in the target directory, verified and synced, then renamed
// over the target.
package atomicfile

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
)

// WriteIfChanged replaces path with data, leaving a file that holds data
// already untouched. The file keeps its permissions, or is 0644 when new.
// The directory is synced after the rename where the platform allows.
func WriteIfChanged(path string, data []byte) error {
	if old, err := os.ReadFile(path); err == nil && bytes.Equal(old, data) {
		return nil
	}
	mode := os.FileMode(0o644)
	if st, err := os.Stat(path); err == nil {
		mode = st.Mode().Perm()
	}
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".*.tmp")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	// A temp file is created 0600.
	if err := tmp.Chmod(mode); err != nil {
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
	written, err := os.ReadFile(tmp.Name())
	if err != nil {
		return err
	}
	if !bytes.Equal(written, data) {
		return fmt.Errorf("%s: the temp file reads back other than what was written", path)
	}
	if err := os.Rename(tmp.Name(), path); err != nil {
		return err
	}
	if d, err := os.Open(dir); err == nil {
		_ = d.Sync()
		d.Close()
	}
	return nil
}
