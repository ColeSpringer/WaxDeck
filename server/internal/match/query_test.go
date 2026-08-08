package match

import "testing"

func TestRecordingQuery(t *testing.T) {
	cases := []struct {
		name       string
		tags       map[string]string
		wantArtist string
		wantTitle  string
		wantOK     bool
	}{
		{
			name:       "acquired video: channel artist, Artist - Track title with alias",
			tags:       map[string]string{"ARTIST": "Mixtapes best", "TITLE": "Amir Obe (Phreshy Duzit) - Drugs & Cam'ron"},
			wantArtist: "Amir Obe",
			wantTitle:  "Drugs & Cam'ron",
			wantOK:     true,
		},
		{
			name:       "official video suffix stripped after the split",
			tags:       map[string]string{"ARTIST": "Some Channel", "TITLE": "Daft Punk - Get Lucky (Official Video)"},
			wantArtist: "Daft Punk",
			wantTitle:  "Get Lucky",
			wantOK:     true,
		},
		{
			name:       "well tagged track keeps its tags",
			tags:       map[string]string{"ARTIST": "Radiohead", "TITLE": "Paranoid Android"},
			wantArtist: "Radiohead",
			wantTitle:  "Paranoid Android",
			wantOK:     true,
		},
		{
			name:       "youtube topic channel suffix stripped from the artist",
			tags:       map[string]string{"ARTIST": "Juvenile - Topic", "TITLE": "Back That Azz Up"},
			wantArtist: "Juvenile",
			wantTitle:  "Back That Azz Up",
			wantOK:     true,
		},
		{
			name:       "content group is preserved",
			tags:       map[string]string{"ARTIST": "X", "TITLE": "Song Name (Live)"},
			wantArtist: "X",
			wantTitle:  "Song Name (Live)",
			wantOK:     true,
		},
		{
			name:       "albumartist fills in a missing artist",
			tags:       map[string]string{"ALBUMARTIST": "The Band", "TITLE": "A Song"},
			wantArtist: "The Band",
			wantTitle:  "A Song",
			wantOK:     true,
		},
		{
			name:   "no title is unusable",
			tags:   map[string]string{"ARTIST": "X"},
			wantOK: false,
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			artist, title, ok := recordingQuery(Track{Tags: c.tags})
			if ok != c.wantOK {
				t.Fatalf("ok = %v, want %v", ok, c.wantOK)
			}
			if !ok {
				return
			}
			if artist != c.wantArtist || title != c.wantTitle {
				t.Fatalf("got (%q, %q), want (%q, %q)", artist, title, c.wantArtist, c.wantTitle)
			}
		})
	}
}

func TestSplitArtistTitle(t *testing.T) {
	cases := []struct {
		in            string
		artist, track string
		ok            bool
	}{
		{"Amir Obe - Drugs & Cam'ron", "Amir Obe", "Drugs & Cam'ron", true},
		{"Daft Punk – Get Lucky", "Daft Punk", "Get Lucky", true}, // en dash
		{"Artist — Track", "Artist", "Track", true},               // em dash
		{"Twenty-One Pilots", "", "", false},                      // hyphenated word, no spaces
		{"No separator here", "", "", false},
		{" - leading", "", "", false},  // empty left side
		{"trailing - ", "", "", false}, // empty right side
	}
	for _, c := range cases {
		a, tr, ok := splitArtistTitle(c.in)
		if ok != c.ok || a != c.artist || tr != c.track {
			t.Errorf("splitArtistTitle(%q) = (%q, %q, %v), want (%q, %q, %v)", c.in, a, tr, ok, c.artist, c.track, c.ok)
		}
	}
}

func TestCleanDescriptiveTitle(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Get Lucky (Official Video)", "Get Lucky"},
		{"Song [Official Audio]", "Song"},
		{"Song (Official Music Video) (HD)", "Song"}, // peel multiple
		{"Track (Prod. by Metro Boomin)", "Track"},   // producer note
		{"Song (Lyrics)", "Song"},
		{"Song (Live)", "Song (Live)"},               // content: kept
		{"Song (Remix)", "Song (Remix)"},             // content: kept
		{"Song (feat. Drake)", "Song (feat. Drake)"}, // feature: kept
		{"Song (Radio Edit)", "Song (Radio Edit)"},   // distinct recording: kept
		{"(Official Video)", "(Official Video)"},     // whole-string group: kept
		{"Plain Title", "Plain Title"},
	}
	for _, c := range cases {
		if got := cleanDescriptiveTitle(c.in); got != c.want {
			t.Errorf("cleanDescriptiveTitle(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestStripTopicSuffix(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Juvenile - Topic", "Juvenile"},
		{"Juvenile - topic", "Juvenile"},  // case-insensitive
		{"Juvenile - Topic ", "Juvenile"}, // trailing space
		{"Tyler, The Creator - Topic", "Tyler, The Creator"},
		{"Radiohead", "Radiohead"},       // no suffix
		{"Topic", "Topic"},               // bare word, not the channel suffix
		{"Topic - Band", "Topic - Band"}, // suffix is elsewhere, untouched
	}
	for _, c := range cases {
		if got := stripTopicSuffix(c.in); got != c.want {
			t.Errorf("stripTopicSuffix(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestStripTrailingParenthetical(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Amir Obe (Phreshy Duzit)", "Amir Obe"},
		{"Artist [alias]", "Artist"},
		{"Beyoncé", "Beyoncé"},
		{"(only)", "(only)"}, // whole-string group: kept
	}
	for _, c := range cases {
		if got := stripTrailingParenthetical(c.in); got != c.want {
			t.Errorf("stripTrailingParenthetical(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// A typed query is taken verbatim: the derivation is there to rescue
// titles a machine wrote, and a hand-typed one needs no rescuing. Every
// case here is the derivation doing exactly its job and being wrong for
// it.
func TestRecordingQueryTakesATypedQueryVerbatim(t *testing.T) {
	cases := []struct {
		name       string
		tags       map[string]string
		query      *TrackQuery
		wantArtist string
		wantTitle  string
		wantOK     bool
	}{
		{
			name:       "a typed title containing the separator is not re-split",
			tags:       map[string]string{"ARTIST": "Some Channel", "TITLE": "whatever"},
			query:      &TrackQuery{Artist: "Benny Goodman", Title: "Sing - Sing - Sing"},
			wantArtist: "Benny Goodman",
			wantTitle:  "Sing - Sing - Sing",
			wantOK:     true,
		},
		{
			name:       "a typed parenthetical is not peeled",
			tags:       map[string]string{"TITLE": "whatever"},
			query:      &TrackQuery{Artist: "Portishead", Title: "Roads (Official Video)"},
			wantArtist: "Portishead",
			wantTitle:  "Roads (Official Video)",
			wantOK:     true,
		},
		{
			name:       "a typed artist survives a descriptive title that would replace it",
			tags:       map[string]string{"ARTIST": "Chan", "TITLE": "Daft Punk - Get Lucky"},
			query:      &TrackQuery{Artist: "Pharrell Williams"},
			wantArtist: "Pharrell Williams",
			wantTitle:  "Get Lucky",
			wantOK:     true,
		},
		{
			name:       "an empty field falls back to the derivation",
			tags:       map[string]string{"ARTIST": "Some Channel", "TITLE": "Daft Punk - Get Lucky (Official Video)"},
			query:      &TrackQuery{Title: "Get Lucky (Radio Edit)"},
			wantArtist: "Daft Punk",
			wantTitle:  "Get Lucky (Radio Edit)",
			wantOK:     true,
		},
		{
			name:   "an all-blank query changes nothing and an untitled track is still unsearchable",
			tags:   map[string]string{"ARTIST": "Some Channel"},
			query:  &TrackQuery{},
			wantOK: false,
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			artist, title, ok := recordingQuery(Track{Tags: c.tags, Query: c.query})
			if ok != c.wantOK {
				t.Fatalf("ok = %v, want %v", ok, c.wantOK)
			}
			if !ok {
				return
			}
			if artist != c.wantArtist || title != c.wantTitle {
				t.Fatalf("got (%q, %q), want (%q, %q)", artist, title, c.wantArtist, c.wantTitle)
			}
		})
	}
}

// SuggestedQuery is the derivation, and stays it: a suggestion is what
// the matcher read out of a source title, so a query somebody typed has
// no business changing what is suggested.
func TestSuggestedQueryIgnoresATypedQuery(t *testing.T) {
	artist, title, ok := SuggestedQuery(Track{
		Tags:  map[string]string{"ARTIST": "Some Channel", "TITLE": "Daft Punk - Get Lucky (Official Video)"},
		Query: &TrackQuery{Artist: "Nobody", Title: "Nothing"},
	})
	if !ok || artist != "Daft Punk" || title != "Get Lucky" {
		t.Fatalf("got (%q, %q, %v), want the derivation", artist, title, ok)
	}
}
