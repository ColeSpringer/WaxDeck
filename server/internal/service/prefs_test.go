package service

import (
	"testing"
)

// Prefs holds a slice, so it is not comparable; this is every field
// reading as unset.
func isZeroPrefs(p Prefs) bool {
	return p.Timezone == "" && p.Locale == "" && p.Theme == "" &&
		!p.SharedStatsOptOut && len(p.RadioFavorites) == 0 &&
		p.CrossfadeSeconds == 0 && !p.ReplayGain && !p.RadioScrobbleOptOut
}

// TestPrefsRoundTripsTheServerAppliedFields pins the three preferences
// the server itself acts on: a cast render reads the first two and the
// stream proxy reads the third, so a value that does not survive a
// round trip is a queue that sounds wrong rather than a field that reads
// blank.
func TestPrefsRoundTripsTheServerAppliedFields(t *testing.T) {
	ctx, svc, admin := newAdminFixture(t)

	stored, err := svc.PutPrefs(ctx, admin, Prefs{
		CrossfadeSeconds:    4.5,
		ReplayGain:          true,
		RadioScrobbleOptOut: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if stored.CrossfadeSeconds != 4.5 || !stored.ReplayGain || !stored.RadioScrobbleOptOut {
		t.Fatalf("stored = %+v", stored)
	}

	read, err := svc.Prefs(ctx, admin)
	if err != nil {
		t.Fatal(err)
	}
	if read.CrossfadeSeconds != 4.5 || !read.ReplayGain || !read.RadioScrobbleOptOut {
		t.Fatalf("read back = %+v", read)
	}

	// The by-id read is what the cast reload and the stream proxy use;
	// it has no acting caller, so it is a separate path worth pinning.
	byID := svc.PrefsForUser(ctx, admin.ID)
	if byID.CrossfadeSeconds != 4.5 || !byID.ReplayGain || !byID.RadioScrobbleOptOut {
		t.Fatalf("PrefsForUser = %+v", byID)
	}

	// Turning a crossfade back off has to stick. The document omits a
	// zero, so this is the case where "absent" and "off" have to be one
	// answer rather than "keep what was there".
	off, err := svc.PutPrefs(ctx, admin, Prefs{})
	if err != nil {
		t.Fatal(err)
	}
	if off.CrossfadeSeconds != 0 || off.ReplayGain || off.RadioScrobbleOptOut {
		t.Fatalf("cleared = %+v", off)
	}
	if again := svc.PrefsForUser(ctx, admin.ID); again.CrossfadeSeconds != 0 {
		t.Fatalf("cleared crossfade came back as %v", again.CrossfadeSeconds)
	}
}

func TestPutPrefsBoundsTheCrossfade(t *testing.T) {
	ctx, svc, admin := newAdminFixture(t)
	for _, seconds := range []float64{-1, 12.1, 3600} {
		if _, err := svc.PutPrefs(ctx, admin, Prefs{CrossfadeSeconds: seconds}); err == nil {
			t.Fatalf("crossfade %v was accepted", seconds)
		} else if KindOf(err) != KindInvalid {
			t.Fatalf("crossfade %v: kind = %v", seconds, KindOf(err))
		}
	}
	// The endpoint's own bound is 12, and this is the value that has to
	// stay legal so the two agree.
	if _, err := svc.PutPrefs(ctx, admin, Prefs{CrossfadeSeconds: 12}); err != nil {
		t.Fatalf("crossfade 12 was refused: %v", err)
	}
}

// TestPrefsSurviveACorruptDocument locks the recovery contract down.
// Both readers are on paths with something else to do - a cast reload, a
// finished radio segment - so a document that will not parse has to read
// as defaults rather than propagate an error, and the next write has to
// replace it.
func TestPrefsSurviveACorruptDocument(t *testing.T) {
	ctx, svc, admin := newAdminFixture(t)
	if err := svc.db.PutPrefsJSON(ctx, admin.ID, "{not json at all"); err != nil {
		t.Fatal(err)
	}

	read, err := svc.Prefs(ctx, admin)
	if err != nil {
		t.Fatalf("a corrupt document must not be an error: %v", err)
	}
	if !isZeroPrefs(read) {
		t.Fatalf("corrupt document read as %+v, want defaults", read)
	}
	if byID := svc.PrefsForUser(ctx, admin.ID); !isZeroPrefs(byID) {
		t.Fatalf("PrefsForUser on a corrupt document = %+v", byID)
	}

	if _, err := svc.PutPrefs(ctx, admin, Prefs{Theme: "dark"}); err != nil {
		t.Fatal(err)
	}
	if read := svc.PrefsForUser(ctx, admin.ID); read.Theme != "dark" {
		t.Fatalf("the next write did not replace the corrupt document: %+v", read)
	}
}
