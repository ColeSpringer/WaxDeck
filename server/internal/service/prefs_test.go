package service

import (
	"strings"
	"testing"
)

// Prefs holds a slice, so it is not comparable; this is every field
// reading as unset.
func isZeroPrefs(p Prefs) bool {
	return p.Timezone == "" && p.Locale == "" && p.Theme == "" &&
		!p.SharedStatsOptOut && len(p.RadioFavorites) == 0 && len(p.Pinned) == 0 &&
		p.CrossfadeSeconds == 0 && !p.ReplayGain && !p.RadioScrobbleOptOut &&
		p.BrowseShowUnknown == nil && len(p.BrowseSorts) == 0 && p.Autoplay == nil
}

// TestPutPrefsCanonicalizesPins covers the shared pid-list validator on
// the list that has more than one accepted prefix. The stored form is the
// contract's pattern, whatever case a write used, and it is what makes
// the duplicate check work at all: Crockford base32 parses either case,
// so two spellings of one album must not become two shelf cards.
func TestPutPrefsCanonicalizesPins(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)

	const album = "al-01JZX5N8QW3F4V9T2B7KD3M9R6"
	stored, err := svc.PutPrefs(ctx, admin, Prefs{Pinned: []string{
		strings.ToLower(album),
		"pl-01JZX5N8QW3F4V9T2B7KD3M9R7",
		"bk-01JZX5N8QW3F4V9T2B7KD3M9R8",
		"rg-01JZX5N8QW3F4V9T2B7KD3M9R9",
	}})
	if err != nil {
		t.Fatal(err)
	}
	if len(stored.Pinned) != 4 || stored.Pinned[0] != album {
		t.Fatalf("stored pins = %v", stored.Pinned)
	}

	for _, bad := range []struct {
		why  string
		pins []string
	}{
		{"a station is radio's own pin surface", []string{"rs-01JZX5N8QW3F4V9T2B7KD3M9R6"}},
		{"a track opens no surface", []string{"tr-01JZX5N8QW3F4V9T2B7KD3M9R6"}},
		{"a malformed pid", []string{"al-nope"}},
		{"the same album twice", []string{album, strings.ToLower(album)}},
	} {
		if _, err := svc.PutPrefs(ctx, admin, Prefs{Pinned: bad.pins}); err == nil {
			t.Fatalf("%s was accepted", bad.why)
		}
	}

	over := make([]string, maxPinned+1)
	for i := range over {
		over[i] = "al-01JZX5N8QW3F4V9T2B7KD3M9" + string(rune('A'+i%26))
	}
	if _, err := svc.PutPrefs(ctx, admin, Prefs{Pinned: over}); err == nil {
		t.Fatal("a list over the cap was accepted")
	}

	// Unpinning everything drops the field rather than storing an empty
	// list, so absent and empty stay one answer on the way back.
	cleared, err := svc.PutPrefs(ctx, admin, Prefs{})
	if err != nil {
		t.Fatal(err)
	}
	if len(cleared.Pinned) != 0 {
		t.Fatalf("cleared pins = %v", cleared.Pinned)
	}
}

// TestPrefsRoundTripsTheServerAppliedFields pins the three preferences
// the server itself acts on: a cast render reads the first two and the
// stream proxy reads the third, so a value that does not survive a
// round trip is a queue that sounds wrong rather than a field that reads
// blank.
func TestPrefsRoundTripsTheServerAppliedFields(t *testing.T) {
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
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

// Validated against the same two tables the browse endpoint parses with,
// so a stored default can never name something it would refuse.
func TestPutPrefsValidatesBrowseSorts(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)

	stored, err := svc.PutPrefs(ctx, admin, Prefs{
		BrowseSorts: map[string]string{
			"genre":    string(FacetSortLabel),
			"year":     string(FacetSortCount),
			"tag.MOOD": string(FacetSortLabel),
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if stored.BrowseSorts["genre"] != string(FacetSortLabel) || len(stored.BrowseSorts) != 3 {
		t.Fatalf("stored = %+v", stored.BrowseSorts)
	}

	if _, err := svc.PutPrefs(ctx, admin, Prefs{
		BrowseSorts: map[string]string{"invented": string(FacetSortLabel)},
	}); KindOf(err) != KindInvalid {
		t.Fatalf("an unknown dimension answered %v, want invalid-request", err)
	}
	if _, err := svc.PutPrefs(ctx, admin, Prefs{
		BrowseSorts: map[string]string{"genre": "sideways"},
	}); KindOf(err) != KindInvalid {
		t.Fatalf("an unknown order answered %v, want invalid-request", err)
	}
	// "" is the absent query parameter, not a storable value: stored, it
	// would answer outside the response enum and throw in the generated
	// client on every later prefs read.
	if _, err := svc.PutPrefs(ctx, admin, Prefs{
		BrowseSorts: map[string]string{"genre": ""},
	}); KindOf(err) != KindInvalid {
		t.Fatalf("an empty order answered %v, want invalid-request", err)
	}
	// A tag dimension goes through the catalog's own key rules rather
	// than a prefix check, so "tag." plus anything is refused.
	if _, err := svc.PutPrefs(ctx, admin, Prefs{
		BrowseSorts: map[string]string{"tag.": string(FacetSortLabel)},
	}); KindOf(err) != KindInvalid {
		t.Fatalf("an empty tag key answered %v, want invalid-request", err)
	}
}

// Absent is the default and false is a choice, so both have to survive a
// round trip as themselves.
func TestPrefsKeepFalseApartFromAbsent(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)

	off := false
	stored, err := svc.PutPrefs(ctx, admin, Prefs{BrowseShowUnknown: &off, Autoplay: &off})
	if err != nil {
		t.Fatal(err)
	}
	if stored.BrowseShowUnknown == nil || *stored.BrowseShowUnknown ||
		stored.Autoplay == nil || *stored.Autoplay {
		t.Fatalf("stored = %+v", stored)
	}
	read, err := svc.Prefs(ctx, admin)
	if err != nil {
		t.Fatal(err)
	}
	if read.BrowseShowUnknown == nil || *read.BrowseShowUnknown ||
		read.Autoplay == nil || *read.Autoplay {
		t.Fatalf("read back = %+v, want both stored as an explicit no", read)
	}

	// A document that never mentioned them reads as unset.
	cleared, err := svc.PutPrefs(ctx, admin, Prefs{})
	if err != nil {
		t.Fatal(err)
	}
	if cleared.BrowseShowUnknown != nil || cleared.Autoplay != nil {
		t.Fatalf("cleared = %+v", cleared)
	}
}
