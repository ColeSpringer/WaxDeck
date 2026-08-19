//go:build linux || darwin

package diskspace

import "golang.org/x/sys/unix"

// Free reports the bytes this process may still write to the volume
// holding path, and whether the platform could answer.
func Free(path string) (int64, bool) {
	var st unix.Statfs_t
	if err := unix.Statfs(path, &st); err != nil {
		return 0, false
	}
	// A block size of zero is no answer at all, and some filesystems
	// give one - rclone and sshfs mounts, a few container overlays,
	// which report f_bsize as zero or as an I/O hint. Multiplying it
	// out would hand back a confident zero, and a confident zero here
	// refuses every upload on the server as though the disk were full.
	if st.Bsize <= 0 {
		return 0, false
	}
	// Bavail rather than Bfree: the blocks a filesystem reserves for
	// root are not room a server running as anyone else can use.
	return clamp(uint64(st.Bavail) * uint64(st.Bsize)), true
}
