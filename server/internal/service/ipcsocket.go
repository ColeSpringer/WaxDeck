package service

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"syscall"
)

// maxSocketPath is the longest unix socket path this platform binds or
// dials: sun_path less its NUL, the limit the catalog's proxy checks.
const maxSocketPath = len(syscall.RawSockaddrUnix{}.Path) - 1

// ipcSocket is where the CLI's proxy socket goes: beside the catalog when
// that path fits a unix socket, else in a directory named for the data dir
// under the user's runtime dir or the temp dir, private to this user,
// either made now (made) or left by a run that never got to remove it. The
// catalog advertises the path in its lockfile, which is how the CLI finds
// it either way. Where nothing fits, the path beside the catalog stands and
// the serve worker's refusal says why.
func ipcSocket(dataDir string) (socket, dir string, made bool) {
	socket = filepath.Join(dataDir, SocketFileName)
	if len(socket) <= maxSocketPath {
		return socket, "", false
	}
	name := socketDirName(dataDir)
	for _, base := range []string{os.Getenv("XDG_RUNTIME_DIR"), os.TempDir()} {
		if base == "" {
			continue
		}
		d := filepath.Join(base, name)
		s := filepath.Join(d, SocketFileName)
		if len(s) > maxSocketPath {
			continue
		}
		err := os.Mkdir(d, 0o700)
		if err == nil {
			return s, d, true
		}
		if errors.Is(err, fs.ErrExist) && privateDir(d) {
			return s, d, false
		}
	}
	return socket, "", false
}

// socketDirName names the socket's directory after the data dir, so a
// restart finds the one it made and a crash leaves at most one behind.
func socketDirName(dataDir string) string {
	if abs, err := filepath.Abs(dataDir); err == nil {
		dataDir = abs
	}
	sum := sha256.Sum256([]byte(dataDir))
	return "waxdeck-" + hex.EncodeToString(sum[:8])
}

// privateDir reports whether dir is a directory, not a link to one, that
// only this user can use: one another user made under a shared temp dir
// could swap the socket for their own.
func privateDir(dir string) bool {
	fi, err := os.Lstat(dir)
	return err == nil && fi.IsDir() && ownedPrivately(fi)
}
