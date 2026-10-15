package service

import (
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

func TestHealthCursorRoundTrip(t *testing.T) {
	t.Parallel()
	const pid = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
	cur := encodeHealthCursor(3, "Weird.Title / With Stuff", pid)
	n, title, gotPID, ok := decodeHealthCursor(cur)
	if !ok {
		t.Fatalf("round-trip cursor %q did not parse", cur)
	}
	if n != 3 || title != "Weird.Title / With Stuff" || gotPID != pid {
		t.Fatalf("decoded (%d, %q, %q)", n, title, gotPID)
	}
}

func TestHealthCursorStrictParsing(t *testing.T) {
	t.Parallel()
	const pid = "01ARZ3NDEKTSV4RRFFQ69G5FAV"
	for _, bad := range []string{
		"",
		"garbage",
		"3.abc",            // two parts
		"3.!!!." + pid,     // not base64url
		"-1.." + pid,       // negative count
		"a.." + pid,        // non-numeric count
		"3..notaulid",      // invalid pid
		"3.." + pid + ".x", // four parts
		"3." + pid,         // missing title part
	} {
		if _, _, _, ok := decodeHealthCursor(bad); ok {
			t.Fatalf("cursor %q parsed, want rejection", bad)
		}
	}
}

// A duplicate group's why is the catalog's reason alone: its message
// also repeats the names and ends with advice for the command line.
func TestDuplicateReasonIsTheWhyAlone(t *testing.T) {
	t.Parallel()
	for msg, want := range map[string]string{
		"duplicate artist (same collation key): Beatles / The Beatles; merge with `waxbin merge`": "same collation key",
		"duplicate album (same title and album artist): Blue / Blue; if they are one release, tag their files alike; " +
			"`waxbin merge` alone joins them only until a scan or edit re-resolves them": "same title and album artist",
		"something else entirely": "",
	} {
		if got := duplicateReason(msg); got != want {
			t.Errorf("reason of %q = %q, want %q", msg, got, want)
		}
	}
}

func TestHealthFixableRulesAreImplemented(t *testing.T) {
	t.Parallel()
	implemented := map[string]bool{}
	for _, r := range healthRules {
		implemented[r] = true
	}
	for r := range healthFixWants {
		if !implemented[r] {
			t.Fatalf("fixable rule %q is not in the implemented rule set", r)
		}
		if wantPhases[healthFixWants[r]] == nil || fixBlockedSource[r] == "" {
			t.Fatalf("fixable rule %q has no per-item want or blocked code", r)
		}
	}
	for _, r := range []string{ruleCorruptAudio, ruleLegacyTags, ruleSmallArt, ruleMissingYear, ruleDurationMismatch, ruleGenreWhitelist} {
		if _, ok := healthFixWants[r]; ok || r == rulePathMismatch || r == ruleWriteUnsynced {
			t.Fatalf("rule %q must not have a fix", r)
		}
	}
}

// A member's path is read only where another of its group shares its
// codec and bitrate: there alone the file's name is what tells the two
// apart.
func TestOnlyAlikeUpgradeMembersNeedTheirPaths(t *testing.T) {
	t.Parallel()
	ms := []waxbin.UpgradeCandidate{
		{FilePID: "f-flac", Codec: "flac", Bitrate: 900, Lossless: true},
		{FilePID: "f-mp3-a", Codec: "mp3", Bitrate: 320},
		{FilePID: "f-mp3-b", Codec: "mp3", Bitrate: 320},
		{FilePID: "f-mp3-c", Codec: "mp3", Bitrate: 192},
	}
	got := alikeMembers(ms)
	for pid, want := range map[model.PID]bool{"f-flac": false, "f-mp3-a": true, "f-mp3-b": true, "f-mp3-c": false} {
		if got[pid] != want {
			t.Errorf("%s alike = %v, want %v", pid, got[pid], want)
		}
	}
}
