package service

import "os"

// fileIdent is what a run records of a file it wrote, to know the file
// again before removing it: its size, its modification time and, where
// the platform gives one, its inode. A rename keeps all three.
type fileIdent struct {
	Size  int64  `json:"size"`
	ModNS int64  `json:"modNs"`
	Ino   uint64 `json:"ino,omitempty"`
}

// identOf is the identity of the regular file at path, or false when
// there is none.
func identOf(path string) (fileIdent, bool) {
	fi, err := os.Lstat(path)
	if err != nil || !fi.Mode().IsRegular() {
		return fileIdent{}, false
	}
	return fileIdent{Size: fi.Size(), ModNS: fi.ModTime().UnixNano(), Ino: inodeOf(fi)}, true
}

// identsOf is the identity of the file at each path, the zero one where
// there is none.
func identsOf(paths ...string) []fileIdent {
	out := make([]fileIdent, len(paths))
	for i, p := range paths {
		out[i], _ = identOf(p)
	}
	return out
}

// sameSizeAndTime reports whether now has the size and modification time
// recorded as was, which a rename keeps.
func sameSizeAndTime(was, now fileIdent) bool {
	return was.Size == now.Size && was.ModNS == now.ModNS
}
