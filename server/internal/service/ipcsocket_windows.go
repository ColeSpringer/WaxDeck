//go:build windows

package service

import "io/fs"

// ownedPrivately has nothing to check: the temp dir a Windows account gets
// is its own, and Go reports no owner or Unix mode for it.
func ownedPrivately(fs.FileInfo) bool { return true }
