//go:build unix

package service

import (
	"os"
	"syscall"
)

// inodeOf is the file's inode.
func inodeOf(fi os.FileInfo) uint64 {
	if st, ok := fi.Sys().(*syscall.Stat_t); ok {
		return uint64(st.Ino)
	}
	return 0
}
