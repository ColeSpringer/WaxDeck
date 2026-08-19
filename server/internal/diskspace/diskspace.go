// Package diskspace reports the room left on the volume holding a path.
//
// An upload declares its size before a byte moves, which is the one
// moment the server can refuse one it has nowhere to put - and the only
// thing that can answer "is there room" is the filesystem itself. A
// platform with no way to ask reports ok false, and the caller skips the
// check rather than guessing at a number.
package diskspace

import "math"

// clamp keeps a filesystem's unsigned answer inside int64. No real
// volume is anywhere near 8 EiB, but the arithmetic below it is signed
// and a wrapped negative would read as "full" on the largest disks.
func clamp(bytes uint64) int64 {
	if bytes > math.MaxInt64 {
		return math.MaxInt64
	}
	return int64(bytes)
}
