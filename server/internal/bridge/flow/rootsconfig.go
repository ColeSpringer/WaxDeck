package flow

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

// The sidecar's roots come from a JSON config file WaxDeck owns and the
// sidecar reads. Adding a library at runtime means rewriting that file
// and asking the sidecar to reconcile against it (Bridge.ReloadRoots).
//
// The file is decoded into a map rather than a struct on purpose. In a
// file-configured deployment it also carries apiKeys, signingSecret, and
// the cache settings, and WaxFlow's config package is internal/, so its
// struct cannot be imported to round-trip them. A map preserves every
// key WaxDeck does not own, including ones added by a newer sidecar.

// readRootsConfig returns the config file's bytes and mode. The mode
// travels with them because a rewrite has to put it back: the file can
// hold apiKeys and signingSecret, and the sidecar reads it as whatever
// user it runs as, so neither widening nor narrowing it is WaxDeck's
// call.
//
// A missing file is not created: the sidecar was started against this
// path, so its absence means the two are looking at different files and
// a reload would silently reconcile against something else.
func readRootsConfig(path string) ([]byte, os.FileMode, error) {
	info, err := os.Stat(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, 0, fmt.Errorf("flow: sidecar config %s does not exist; the sidecar reads it, so WaxDeck will not invent one", path)
		}
		return nil, 0, fmt.Errorf("flow: reading sidecar config: %w", err)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, 0, fmt.Errorf("flow: reading sidecar config: %w", err)
	}
	return raw, info.Mode().Perm(), nil
}

// mergeRootsConfig folds WaxDeck's root table into the config file's
// bytes, returning the document to write.
//
// Roots are merged by name, not replaced wholesale. The name is the only
// thing the two sides genuinely agree on: `path` in this file is the
// sidecar's view of the filesystem, which need not be WaxDeck's (they
// only coincide because the compose topology mounts both at the same
// place), and a root the sidecar has that WaxDeck does not know is the
// operator's business. So an entry already in the file keeps its own
// path and its position, and only a name WaxDeck knows and the file does
// not is appended -- with WaxDeck's path, the only one available, which
// the reload then validates by opening it.
func mergeRootsConfig(raw []byte, path string, roots []Root) ([]byte, error) {
	cfg := map[string]any{}
	if len(bytes.TrimSpace(raw)) > 0 {
		if err := json.Unmarshal(raw, &cfg); err != nil {
			return nil, fmt.Errorf("flow: sidecar config %s is not a JSON object: %w", path, err)
		}
	}
	existing, _ := cfg["roots"].([]any)
	named := make(map[string]bool, len(existing))
	for _, e := range existing {
		if obj, ok := e.(map[string]any); ok {
			if name, ok := obj["name"].(string); ok {
				named[name] = true
			}
		}
	}
	entries := append([]any(nil), existing...)
	for _, r := range roots {
		if named[r.Name] {
			continue
		}
		named[r.Name] = true
		entries = append(entries, map[string]any{"name": r.Name, "path": r.Path})
	}
	cfg["roots"] = entries
	out, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("flow: encoding sidecar config: %w", err)
	}
	return append(out, '\n'), nil
}

// writeRootsConfig merges WaxDeck's roots into the config file, leaving
// every other key exactly as it found it. The caller passes the bytes it
// already read, so one reload reads the file once. The write follows the
// repo's durability rule: temp file in the target directory, verify,
// fsync, atomic rename, directory fsync. It returns only once the rename
// has landed, because the sidecar re-reads this file synchronously
// inside the reload request.
func writeRootsConfig(path string, raw []byte, perm os.FileMode, roots []Root) error {
	out, err := mergeRootsConfig(raw, path, roots)
	if err != nil {
		return err
	}
	if err := writeFileCrashSafe(path, out, perm); err != nil {
		return fmt.Errorf("flow: writing sidecar config: %w", err)
	}
	return nil
}

// writeFileCrashSafe writes bytes with the repo's durability rule:
// temp file in the target directory, verify the written bytes, fsync,
// atomic rename, fsync the directory. The replacement carries the mode
// the caller read off the file it replaces: the sidecar reads this file
// too, possibly as another user, and it can hold apiKeys and
// signingSecret, so neither widening nor narrowing the operator's mode
// is WaxDeck's call.
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
	// CreateTemp makes the file 0600; restore what the operator set.
	if err := os.Chmod(tmpName, perm); err != nil {
		return err
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
