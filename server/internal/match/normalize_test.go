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
		{"song feat someone", "song"},
		{"song featuring someone else", "song"},
		{"song ft someone", "song"},
		{"dancing with myself", "dancing with myself"},
		{"feat first word stays", "feat first word stays"},
		{"plain title", "plain title"},
	}
	for _, c := range cases {
		if got := stripFeat(c.in); got != c.want {
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
	if d := titleDist("Song Title (feat. Guest)", "Song Title"); d != 0 {
		t.Errorf("featured suffix should be free, got %v", d)
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
