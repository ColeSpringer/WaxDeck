package service

import "testing"

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

func TestDuplicateNamesFromMessage(t *testing.T) {
	t.Parallel()
	msg := "duplicate artist (same collation key): Beatles / The Beatles; merge with `waxbin merge`"
	names := duplicateNamesFromMessage(msg, 2)
	if len(names) != 2 || names[0] != "Beatles" || names[1] != "The Beatles" {
		t.Fatalf("names = %v", names)
	}

	// A member-count mismatch leaves every name empty rather than
	// misattributing one.
	names = duplicateNamesFromMessage(msg, 3)
	if len(names) != 3 || names[0] != "" || names[1] != "" || names[2] != "" {
		t.Fatalf("mismatched names = %v, want empties", names)
	}

	// An unrecognized message shape parses to empties too.
	names = duplicateNamesFromMessage("something else entirely", 2)
	if len(names) != 2 || names[0] != "" || names[1] != "" {
		t.Fatalf("unparsed names = %v, want empties", names)
	}
}

func TestHealthFixableRulesAreImplemented(t *testing.T) {
	t.Parallel()
	implemented := map[string]bool{}
	for _, r := range healthRules {
		implemented[r] = true
	}
	for r := range healthFixable {
		if !implemented[r] {
			t.Fatalf("fixable rule %q is not in the implemented rule set", r)
		}
	}
	for _, r := range []string{ruleCorruptAudio, ruleLegacyTags, ruleSmallArt, ruleMissingYear} {
		if healthFixable[r] {
			t.Fatalf("rule %q must not be fixable", r)
		}
	}
}
