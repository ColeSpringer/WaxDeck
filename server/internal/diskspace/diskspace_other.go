//go:build !linux && !darwin && !windows

package diskspace

// Free reports the bytes this process may still write to the volume
// holding path, and whether the platform could answer - which here it
// cannot, so every caller's check is skipped rather than guessed.
func Free(string) (int64, bool) { return 0, false }
