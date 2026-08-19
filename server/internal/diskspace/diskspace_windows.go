//go:build windows

package diskspace

import "golang.org/x/sys/windows"

// Free reports the bytes this process may still write to the volume
// holding path, and whether the platform could answer.
func Free(path string) (int64, bool) {
	p, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return 0, false
	}
	// The caller-available figure, not the volume total: a per-user disk
	// quota is exactly the kind of ceiling this check exists to respect.
	var available, total, free uint64
	if err := windows.GetDiskFreeSpaceEx(p, &available, &total, &free); err != nil {
		return 0, false
	}
	return clamp(available), true
}
