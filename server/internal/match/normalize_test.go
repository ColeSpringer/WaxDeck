package match

import "testing"

func TestNormalize(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Hello, World!", "hello world"},
		{"  Sigur  Rós ", "sigur ros"},
		{"AC/DC", "ac dc"},
		{"Motörhead", "motorhead"},
		{"Simon & Garfunkel", "simon and garfunkel"},
		{"Björk", "bjork"},
		{"L'étranger", "l etranger"},
		{"東京事変", "東京事変"},
		{"", ""},
	}
	for _, c := range cases {
		if got := normalize(c.in); got != c.want {
			t.Errorf("normalize(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestStripFeat(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Song feat. Someone", "song"},
		{"Song featuring Someone Else", "song"},
		{"Song ft. Someone", "song"},
		{"Band feat. Guest & Other", "band"},
		{"Dancing with Myself", "dancing with myself"},
		{"Feat first word stays", "feat first word stays"},
		{"Plain Title", "plain title"},
		{"Song (feat. Guest)", "song"},
		{"Song [ft. Guest]", "song"},
		{"Song (feat. Guest", "song"},
		{"Song (feat. A) [feat. B]", "song"},
		// Only the guest clause goes: what follows its group or clause names
		// the recording.
		{"Song (feat. Guest) (Live)", "song live"},
		{"Song (feat. Guest) (X Remix)", "song x remix"},
		{"Song (feat. Guest) (Demo)", "song demo"},
		{"Song (feat. Guest) (Acoustic)", "song acoustic"},
		{"Song (feat. Guest) (Clean)", "song clean"},
		{"Song (feat. Guest) - Live at X", "song live at x"},
		{"Song (feat. Guest (UK)) (Live)", "song live"},
		{"Song (Live) (feat. Guest)", "song live"},
		{"Song feat. Guest (Live)", "song live"},
		{"Song feat. Guest [Demo]", "song demo"},
		{"Song feat. Guest - Live at X", "song live at x"},
		{"Song feat. Guest \u2013 Live at X", "song live at x"},
		{"Song (X Remix feat. Guest)", "song x remix"},
		{"Song (X Remix feat. Guest) (Clean)", "song x remix clean"},
		{"Twenty-One feat. Jay-Z", "twenty one"},
	}
	for _, c := range cases {
		if got := normalize(stripFeat(c.in)); got != c.want {
			t.Errorf("stripFeat(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestStripEdition(t *testing.T) {
	cases := []struct{ in, want string }{
		{"album deluxe edition", "album"},
		{"album remastered 2011", "album"},
		{"album 20th anniversary edition", "album 20th"},
		{"deluxe", "deluxe"},
		{"plain album", "plain album"},
	}
	for _, c := range cases {
		if got := stripEdition(c.in); got != c.want {
			t.Errorf("stripEdition(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestStringDist(t *testing.T) {
	if d := stringDist("Hello", "hello!"); d != 0 {
		t.Errorf("case and punctuation should be free, got %v", d)
	}
	if d := stringDist("", ""); d != 0 {
		t.Errorf("two empties are identical, got %v", d)
	}
	if d := stringDist("something", ""); d != 1 {
		t.Errorf("one empty side is maximal, got %v", d)
	}
	if d := stringDist("abcd", "abce"); d != 0.25 {
		t.Errorf("one edit in four runes = 0.25, got %v", d)
	}
	if a, b := stringDist("The Wall", "The Walls"), stringDist("The Wall", "Animals"); a >= b {
		t.Errorf("near miss (%v) should beat different title (%v)", a, b)
	}
}

func TestTitleDistForgivesFeat(t *testing.T) {
	for _, c := range [][2]string{
		{"Song Title (feat. Guest)", "Song Title"},
		{"Song Title feat. Guest", "Song Title"},
		{"Song Title [ft. Guest]", "Song Title (featuring Guest)"},
		{"Band feat. Guest", "Band"},
		{"Song Title (feat. Guest) (Live)", "Song Title (Live)"},
		{"Song Title (feat. Guest) - Live at X", "Song Title (Live at X)"},
	} {
		if d := titleDist(c[0], c[1]); d != 0 {
			t.Errorf("titleDist(%q, %q) = %v, want the guest clause free", c[0], c[1], d)
		}
	}
}

// A guest credit forgives itself only: the group or tail after it names
// another recording and still counts.
func TestTitleDistKeepsWhatFollowsAGuest(t *testing.T) {
	for _, title := range []string{
		"Song Title (feat. Guest) (Live)",
		"Song Title (feat. Guest) (X Remix)",
		"Song Title (feat. Guest) (Demo)",
		"Song Title (feat. Guest) (Acoustic)",
		"Song Title (feat. Guest) (Clean)",
		"Song Title (feat. Guest) - Live at X",
		"Song Title feat. Guest (Live)",
	} {
		for _, studio := range []string{"Song Title (feat. Guest)", "Song Title"} {
			// At least what the group costs a title with no guest on it.
			want := stringDist("Song Title (Demo)", "Song Title")
			if d := titleDist(title, studio); d < want {
				t.Errorf("titleDist(%q, %q) = %.3f, want what follows the guest counted (%.3f or more)", title, studio, d, want)
			}
			if d := titleDist(studio, title); d < want {
				t.Errorf("titleDist(%q, %q) = %.3f, want what follows the guest counted (%.3f or more)", studio, title, d, want)
			}
		}
	}
}

func TestAlbumDistForgivesEdition(t *testing.T) {
	d := albumDist("Great Album (Deluxe Edition)", "Great Album")
	if d == 0 || d > 0.1 {
		t.Errorf("edition suffix should cost the small penalty only, got %v", d)
	}
	if plain := albumDist("Great Album", "Great Album"); plain != 0 {
		t.Errorf("identical albums must be free, got %v", plain)
	}
}

func TestLevenshtein(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"", "", 0},
		{"a", "", 1},
		{"kitten", "sitting", 3},
		{"flaw", "lawn", 2},
	}
	for _, c := range cases {
		if got := levenshtein(c.a, c.b); got != c.want {
			t.Errorf("levenshtein(%q, %q) = %d, want %d", c.a, c.b, got, c.want)
		}
	}
}

func TestCleanStem(t *testing.T) {
	cases := []struct{ in, want string }{
		{"01 - Song Name", "Song Name"},
		{"1_Song", "Song"},
		{"03.Song", "Song"},
		{"12 Song", "Song"},
		{"Song Without Number", "Song Without Number"},
		{"1999", "1999"},
		{"07", "07"},
	}
	for _, c := range cases {
		if got := cleanStem(c.in); got != c.want {
			t.Errorf("cleanStem(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
