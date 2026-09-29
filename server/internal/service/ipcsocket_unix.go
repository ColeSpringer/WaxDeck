//go:build unix

package service

import (
	"io/fs"
	"os"
	"syscall"
)

// ownedPrivately reports a directory this user owns and no one else can
// enter.
func ownedPrivately(fi fs.FileInfo) bool {
	st, ok := fi.Sys().(*syscall.Stat_t)
	return ok && int(st.Uid) == os.Getuid() && fi.Mode().Perm() == 0o700
}
