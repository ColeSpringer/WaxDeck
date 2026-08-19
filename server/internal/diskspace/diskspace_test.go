package diskspace

import (
	"math"
	"path/filepath"
	"runtime"
	"testing"
)

func TestFreeAnswersForARealDirectory(t *testing.T) {
	free, ok := Free(t.TempDir())
	switch runtime.GOOS {
	case "linux", "darwin", "windows":
		if !ok {
			t.Fatal("the platform should have answered for a directory that exists")
		}
		// Not a fixed number - it is somebody's real disk - but a
		// temporary directory sits on a volume with room on it, and a
		// zero here would mean the units or the field are wrong.
		if free <= 0 {
			t.Fatalf("free = %d, want a positive figure", free)
		}
	default:
		if ok {
			t.Fatal("a platform with no probe should not claim an answer")
		}
	}
}

func TestFreeDeclinesRatherThanGuessing(t *testing.T) {
	// A path that is not there is the case the upload check meets when
	// the staging volume has been unmounted underneath it: skipping the
	// check beats refusing every upload on a made-up zero.
	if _, ok := Free(filepath.Join(t.TempDir(), "no", "such", "place")); ok {
		t.Fatal("a missing path should report no answer")
	}
}

func TestClampKeepsAnImplausibleVolumeInsideInt64(t *testing.T) {
	if got := clamp(math.MaxUint64); got != math.MaxInt64 {
		t.Fatalf("clamp(MaxUint64) = %d, want MaxInt64", got)
	}
	if got := clamp(4096); got != 4096 {
		t.Fatalf("clamp(4096) = %d, want 4096", got)
	}
}
