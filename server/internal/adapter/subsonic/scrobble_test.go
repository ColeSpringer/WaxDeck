package subsonic

import (
	"strconv"
	"testing"
	"time"
)

// The protocol says milliseconds and clients send seconds, microseconds
// and nanoseconds too; the magnitude says which, and a time outside
// 2000 to a day ahead is no time at all.
func TestScrobbleTime(t *testing.T) {
	now := time.Date(2026, 10, 16, 12, 0, 0, 0, time.UTC)
	at := time.Date(2025, 10, 9, 8, 53, 20, 0, time.UTC) // 1.76e9 seconds
	for _, tc := range []struct {
		name, raw string
		want      time.Time
		ok        bool
	}{
		{"seconds", "1760000000", at, true},
		{"milliseconds", strconv.FormatInt(at.UnixMilli(), 10), at, true},
		{"microseconds", strconv.FormatInt(at.UnixMicro(), 10), at, true},
		{"nanoseconds", strconv.FormatInt(at.UnixNano(), 10), at, true},
		{"an hour ago in seconds", strconv.FormatInt(now.Add(-time.Hour).Unix(), 10), now.Add(-time.Hour), true},
		{"within the day ahead", strconv.FormatInt(now.Add(23*time.Hour).UnixMilli(), 10), now.Add(23 * time.Hour), true},
		{"past the day ahead", strconv.FormatInt(now.Add(25*time.Hour).UnixMilli(), 10), time.Time{}, false},
		{"before 2000", strconv.FormatInt(time.Date(1999, 12, 31, 23, 59, 59, 0, time.UTC).Unix(), 10), time.Time{}, false},
		{"seconds read as milliseconds would be 1970", "1760000", time.Time{}, false},
		{"zero", "0", time.Time{}, false},
		{"negative", "-5", time.Time{}, false},
		{"empty", "", time.Time{}, false},
		{"garbage", "yesterday", time.Time{}, false},
		{"a fraction", "1760000000.5", time.Time{}, false},
	} {
		got, ok := scrobbleTime(tc.raw, now)
		if ok != tc.ok || !got.Equal(tc.want) {
			t.Errorf("%s: scrobbleTime(%q) = %v %v, want %v %v", tc.name, tc.raw, got, ok, tc.want, tc.ok)
		}
	}
}

// An untimed submission's id holds for the item's length, clamped to ten
// seconds to ten minutes, so a client retrying one it timed out on records
// one listen; another client, another item or the next window is another.
func TestUntimedScrobbleIDWindow(t *testing.T) {
	now := time.Date(2026, 10, 16, 12, 0, 0, 0, time.UTC)
	const minute = int64(60_000)
	id := untimedScrobbleID("us-1", "DSub", "tr-1", 0, now, 3*minute)
	if again := untimedScrobbleID("us-1", "DSub", "tr-1", 0, now.Add(2*time.Minute), 3*minute); again != id {
		t.Error("a retry inside the item's length minted a second listen")
	}
	if next := untimedScrobbleID("us-1", "DSub", "tr-1", 0, now.Add(3*time.Minute), 3*minute); next == id {
		t.Error("a listen one length later reused the id")
	}
	for name, other := range map[string]string{
		"another client":  untimedScrobbleID("us-1", "Feishin", "tr-1", 0, now, 3*minute),
		"another item":    untimedScrobbleID("us-1", "DSub", "tr-2", 0, now, 3*minute),
		"another account": untimedScrobbleID("us-2", "DSub", "tr-1", 0, now, 3*minute),
		"a second entry":  untimedScrobbleID("us-1", "DSub", "tr-1", 1, now, 3*minute),
	} {
		if other == id {
			t.Errorf("%s reused the id", name)
		}
	}
	// A two-second track still dedupes a retry ten seconds wide, and a
	// two-hour set is not one listen all afternoon.
	short := untimedScrobbleID("us-1", "DSub", "tr-1", 0, now, 2000)
	if untimedScrobbleID("us-1", "DSub", "tr-1", 0, now.Add(9*time.Second), 2000) != short {
		t.Error("the window is shorter than ten seconds")
	}
	long := untimedScrobbleID("us-1", "DSub", "tr-1", 0, now, 120*minute)
	if untimedScrobbleID("us-1", "DSub", "tr-1", 0, now.Add(10*time.Minute), 120*minute) == long {
		t.Error("the window is longer than ten minutes")
	}
}
