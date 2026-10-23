//go:build !unix

package service

import "os"

// inodeOf is zero where the platform gives no inode: size and time alone
// identify the file.
func inodeOf(os.FileInfo) uint64 { return 0 }
