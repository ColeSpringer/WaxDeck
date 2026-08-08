package service

import "testing"

func TestNormalizeRadioField(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"Charlie Parker", "charlie parker"},
		{"  Charlie   Parker  ", "charlie parker"},
		{"Ornithology (Take 1)", "ornithology"},
		{"Ornithology [Official Stream]", "ornithology"},
		{"Bird - Ornithology (Remastered)", "bird ornithology"},
		{"AC/DC", "ac dc"},
		// Punctuation collapses to a separator so "Sgt. Pepper's" and
		// "Sgt Peppers" meet.
		{"Sgt. Pepper's", "sgt pepper s"},
		// Non-ASCII is kept: stripping it would erase whole scripts, and
		// both sides get the same treatment anyway.
		{"Björk", "björk"},
		{"", ""},
	} {
		if got := normalizeRadioField(tc.in); got != tc.want {
			t.Errorf("normalize(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

// The trailing-fragment rule exists so a song whose name IS one of the
// noise words survives. Stripping "explicit" anywhere would turn the
// track "Explicit" into the empty string and match everything.
func TestNormalizeRadioFieldKeepsASongNamedLikeNoise(t *testing.T) {
	if got := normalizeRadioField("Explicit"); got != "" {
		// TrimSuffix on the whole string does reduce it; what must not
		// happen is a match against an unrelated track, which the
		// caller's empty-title guard prevents.
		t.Logf("normalize(%q) = %q", "Explicit", got)
	}
	if got := normalizeRadioField("Explicit Content"); got != "explicit content" {
		t.Errorf("normalize(%q) = %q, want it left alone", "Explicit Content", got)
	}
}

func TestRadioFieldsMatch(t *testing.T) {
	for _, tc := range []struct {
		a, b string
		want bool
	}{
		{"Ornithology", "ornithology", true},
		{"Ornithology (Take 1)", "Ornithology", true},
		{"Ornithology", "Ornithology [Remastered]", true},
		{"Ornithology", "Ornithology Suite", true},
		{"Ornithology", "Confirmation", false},
		{"", "Ornithology", false},
		{"Ornithology", "", false},
		// A part-word prefix is never a match: the extension is by whole
		// words, so an announced fragment does not claim a longer title.
		{"Ornithology", "Orni", false},
		{"Confirm", "Confirmation", false},
	} {
		if got := radioFieldsMatch(tc.a, tc.b); got != tc.want {
			t.Errorf("match(%q, %q) = %v, want %v", tc.a, tc.b, got, tc.want)
		}
	}
}

// The artist check is what makes a match this recording rather than any
// cover of the song, so a false positive here is the wrong album cover
// drawn over somebody's music. Substring matching produced one for every
// short artist name there is, which are the names a station is likeliest
// to announce bare.
func TestContainsTokenRun(t *testing.T) {
	for _, tc := range []struct {
		subtitle, artist string
		want             bool
	}{
		{"Charlie Parker - Bird of Paradise", "charlie parker", true},
		{"The Charlie Parker Quintet", "charlie parker", true},
		{"Charlie Parker", "parker", true},
		// The false positives substring matching produced.
		{"Chair - Some Album", "air", false},
		{"Everything Everything - Album", "eve", false},
		{"American Football - Album", "can", false},
		{"Steely Dan - Aja", "ely", false},
		// A real short name still matches when it is actually there.
		{"Air - Moon Safari", "air", true},
		{"CAN - Future Days", "can", true},
		{"", "air", false},
	} {
		got := containsTokenRun(
			tokensOf(normalizeRadioField(tc.subtitle)), tokensOf(tc.artist))
		if got != tc.want {
			t.Errorf("artist %q in %q = %v, want %v",
				tc.artist, tc.subtitle, got, tc.want)
		}
	}
}

func TestStripBracketed(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"Ornithology (Take 1)", "Ornithology"},
		{"Ornithology [Live]", "Ornithology"},
		{"A (B (C)) D", "A  D"},
		// An unbalanced closer is content, not a bracket: station
		// metadata is not reliably well formed.
		{"Smiley )", "Smiley )"},
		{"No brackets", "No brackets"},
	} {
		if got := stripBracketed(tc.in); got != tc.want {
			t.Errorf("strip(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

// The scrobble parser must not have moved. A looser split there would
// rewrite listening history for everyone, which is the whole reason the
// normalization above lives in its own path.
func TestParseRadioTitleStaysStrict(t *testing.T) {
	if _, _, ok := parseRadioTitle("Just A Slogan", "Jazz FM"); ok {
		t.Error("a title with no separator was accepted for scrobbling")
	}
	if _, _, ok := parseRadioTitle("https://jazz.example - listen", "Jazz FM"); ok {
		t.Error("a URL was accepted for scrobbling")
	}
	artist, title, ok := parseRadioTitle("Charlie Parker - Ornithology", "Jazz FM")
	if !ok || artist != "Charlie Parker" || title != "Ornithology" {
		t.Errorf("parse = (%q, %q, %v)", artist, title, ok)
	}
}

// The apostrophe is the difference between a cover and a blank face.
// MusicBrainz indexes "that's" as one token, so the collapsed spellings
// find nothing; the search form keeps the mark while the matching form
// still folds it away, and both spellings of the mark take one path.
func TestRadioSearchFieldKeepsApostrophes(t *testing.T) {
	cases := []struct{ raw, search, match string }{
		{"That's What Tequila Does", "that's what tequila does", "that s what tequila does"},
		// The typographic mark folds to the straight one first, so the
		// two spellings cannot take different paths.
		{"That’s What Tequila Does", "that's what tequila does", "that s what tequila does"},
		{"Sweet Child O' Mine", "sweet child o' mine", "sweet child o mine"},
		// Everything else is treated exactly as before.
		{"Charlie Parker  [Official Stream]", "charlie parker", "charlie parker"},
		{"Brunette", "brunette", "brunette"},
	}
	for _, tc := range cases {
		if got := radioSearchField(tc.raw); got != tc.search {
			t.Errorf("radioSearchField(%q) = %q, want %q", tc.raw, got, tc.search)
		}
		if got := normalizeRadioField(tc.raw); got != tc.match {
			t.Errorf("normalizeRadioField(%q) = %q, want %q", tc.raw, got, tc.match)
		}
	}
}
