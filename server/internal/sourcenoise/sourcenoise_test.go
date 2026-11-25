package sourcenoise

import (
	"strings"
	"testing"
)

func TestSplitArtistTitle(t *testing.T) {
	cases := []struct {
		in            string
		artist, track string
		ok            bool
	}{
		{"Amir Obe - Drugs & Cam'ron", "Amir Obe", "Drugs & Cam'ron", true},
		{"Daft Punk \u2013 Get Lucky", "Daft Punk", "Get Lucky", true}, // en dash
		{"Artist \u2014 Track", "Artist", "Track", true},               // em dash
		{"Twenty-One Pilots", "", "", false},                           // hyphenated word, no spaces
		{"No separator here", "", "", false},
		{" - leading", "", "", false},  // empty left side
		{"trailing - ", "", "", false}, // empty right side
	}
	for _, c := range cases {
		a, tr, ok := SplitArtistTitle(c.in)
		if ok != c.ok || a != c.artist || tr != c.track {
			t.Errorf("SplitArtistTitle(%q) = (%q, %q, %v), want (%q, %q, %v)", c.in, a, tr, ok, c.artist, c.track, c.ok)
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
		{"Song (Prodigal) (Official Video)", "Song (Prodigal)"},
		{"Plain Title", "Plain Title"},
	}
	for _, c := range cases {
		if got := CleanDescriptiveTitle(c.in); got != c.want {
			t.Errorf("CleanDescriptiveTitle(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestIsNoiseGroup(t *testing.T) {
	cases := []struct {
		in   string
		want bool
	}{
		// Upload notes.
		{"Official Video", true},
		{"Official Music Video", true},
		{"Official Audio", true},
		{"Lyrics", true}, // plural of a listed word
		{"Lyric", true},
		{"Lyric Video", true},
		{"Visualizer", true},
		{"HD", true},
		{"4K", true},
		{"Audio", true},
		{"M/V", true},
		{"Prod. by Metro Boomin", true},
		{"Produced by X", true},
		{"Out Now", true},
		{"Color Coded Lyrics", true},
		{"Music Video", true},
		{"Color Coded", true},
		{"Delivered Audio", true}, // no "live" inside "Delivered"
		// Words that merely contain a listed word.
		{"Prodigal", false},
		{"Unofficial", false},
		{"Videotape", false},
		{"Audiomachine", false},
		{"Cleaner", false},
		{"Now", false}, // half of a phrase
		{"Music", false},
		// Recordings, kept whatever else the group says.
		{"Live", false},
		{"Remix", false},
		{"feat. X", false},
		{"ft. X", false},
		{"Acoustic", false},
		{"Slowed", false},
		{"Remastered", false}, // inflection of a listed word
		{"Remixes", false},
		{"Sped Up Audio", false},
		{"Official Live Video", false},
		{"Bass Boosted", false},
		// Neither list.
		{"", false},
		{"Interlude Two", false},
		{"Bonus", false},
	}
	for _, c := range cases {
		if got := IsNoiseGroup(c.in); got != c.want {
			t.Errorf("IsNoiseGroup(%q) = %v, want %v", c.in, got, c.want)
		}
	}
}

func TestIsVersionTail(t *testing.T) {
	cases := []struct {
		in   string
		want bool
	}{
		{"Remastered 2011", true},
		{"2011 Remaster", true},
		{"Remaster", true},
		{"Live", true},
		{"Live at Wembley", true},
		{"Radio Edit", true},
		{"Single Version", true},
		{"Album Version", true},
		{"Bonus Track", true},
		{"Mono", true},
		{"2009 Mix", true},
		{"From \"Frozen\"", true},
		{"From 'Top Gun'", true},
		{"From \u201cBarbie\u201d", true},
		{"From The Motion Picture Soundtrack", true},
		{"From \"Frozen\"/Soundtrack Version", true},
		// Track names.
		{"From The Motion Picture", true},
		{"From the Video Game Halo", true},
		{"From Eden", false},
		{"From the Game", false},
		{"From The Original Motion Picture Soundtrack", true},
		{"From the Netflix Series", false},
		{"From Russia With Love The Film", false},
		{"Bohemian Rhapsody", false},
		{"Delivered", false},
		{"Prodigal Son", false},
		{"Live Forever", false},
		{"Live and Let Die", false},
		{"Remix the World", false},
		{"Demo Love Song", false},
		{"Version of Me", false},
		{"Demons", false},
		{"Back to 1985", false},
		{"Acoustic Guitar Song", false},
		{"Mix Tape", false},
		{"Live 1977", true},
		{"Live in Paris", true},
		{"Remastered Version", true},
		{"2015 Remastered Version", true},
		{"Extended Mix", true},
		{"Acoustic Version", true},
		{"Acoustic", true},
		{"Instrumental", true},
		{"Demo", true},
		{"Stereo", true},
		{"Remastered 2011 (Official Audio)", true},
		{"1979", false}, // a bare year is a title as often as a note
		{"Edith", false},
		{"", false},
	}
	for _, c := range cases {
		if got := IsVersionTail(c.in); got != c.want {
			t.Errorf("IsVersionTail(%q) = %v, want %v", c.in, got, c.want)
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
		if got := StripTopicSuffix(c.in); got != c.want {
			t.Errorf("StripTopicSuffix(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestStripTrailingParenthetical(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Amir Obe (Phreshy Duzit)", "Amir Obe"},
		{"Artist [alias]", "Artist"},
		{"Beyonc\u00e9", "Beyonc\u00e9"},
		{"(only)", "(only)"}, // whole-string group: kept
	}
	for _, c := range cases {
		if got := StripTrailingParenthetical(c.in); got != c.want {
			t.Errorf("StripTrailingParenthetical(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestTrailingGroup(t *testing.T) {
	cases := []struct {
		in    string
		start int
		inner string
		ok    bool
	}{
		{"Song (Live)", 5, "Live", true},
		{"Song [HD] ", 5, "HD", true},
		{"Song (a (b))", 5, "a (b)", true},
		{"Song", 0, "", false},
		{"Song b)", 0, "", false},
		{"", 0, "", false},
	}
	for _, c := range cases {
		start, inner, ok := TrailingGroup(c.in)
		if start != c.start || inner != c.inner || ok != c.ok {
			t.Errorf("TrailingGroup(%q) = (%d, %q, %v), want (%d, %q, %v)", c.in, start, inner, ok, c.start, c.inner, c.ok)
		}
	}
}

func TestStripVersionTail(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Bohemian Rhapsody - Remastered 2011", "Bohemian Rhapsody"},
		{"Adele - Hello - Live at the BBC", "Adele - Hello"},
		{"Song - Radio Edit - 2015 Remaster", "Song"},
		{"Song \u2013 Mono", "Song"},
		{"Hozier - From Eden", "Hozier - From Eden"},
		{"Live - Lightning Crashes", "Live - Lightning Crashes"},
		{"Live", "Live"}, // one segment is never dropped
		{"Plain Title", "Plain Title"},
	}
	for _, c := range cases {
		if got := StripVersionTail(c.in); got != c.want {
			t.Errorf("StripVersionTail(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestVersionTailsKeepWhatTheyDrop(t *testing.T) {
	head, tails := VersionTails("Song - Radio Edit - 2015 Remaster")
	if head != "Song" || len(tails) != 2 || tails[0] != "2015 Remaster" || tails[1] != "Radio Edit" {
		t.Fatalf("VersionTails = %q %q, want Song and the tails last first", head, tails)
	}
}

func TestSameRecordingTail(t *testing.T) {
	cases := []struct {
		in   string
		want bool
	}{
		{"Remastered 2011", true},
		{"2011 Remaster", true},
		{"Bonus Track", true},
		{"From \"Frozen\"", true},
		{"From The Motion Picture Soundtrack", true},
		{"Live", false},
		{"Live at the BBC", false},
		{"Radio Edit", false},
		{"Extended Mix", false},
		{"Demo", false},
		{"Mono", false},
		{"Bonus Track (2015 Remaster)", true},
		{"Remastered 2011 (Official Audio)", true},
		// A cut beside a remaster form, "Bonus Track" or a source names
		// another cut, so the tail is not the recording as it was.
		{"2015 Remaster (Clean)", false},
		{"Remastered 2011 (Explicit)", false},
		{"Bonus Track (Clean)", false},
		{"From \"Frozen\" [8D Audio]", false},
	}
	for _, c := range cases {
		if got := SameRecordingTail(c.in); got != c.want {
			t.Errorf("SameRecordingTail(%q) = %v, want %v", c.in, got, c.want)
		}
	}
}

func TestSplitCutGroups(t *testing.T) {
	cases := []struct{ in, rest, cuts string }{
		{"2015 Remaster (Clean)", "2015 Remaster", "(Clean)"},
		{"Song (Official Video) (Explicit)", "Song", "(Explicit)"},
		{"Song (Explicit) (2020 Remaster) [8D Audio]", "Song", "(Explicit) [8D Audio]"},
		{"Bonus Track", "Bonus Track", ""},
		{"Song (Live) (Clean)", "Song (Live)", "(Clean)"},
	}
	for _, c := range cases {
		rest, cuts := SplitCutGroups(c.in)
		if rest != c.rest || cuts != c.cuts {
			t.Errorf("SplitCutGroups(%q) = %q, %q; want %q, %q", c.in, rest, cuts, c.rest, c.cuts)
		}
		if joined := strings.TrimSpace(rest + " " + cuts); joined != CleanCutTitle(c.in) {
			t.Errorf("SplitCutGroups(%q) joins to %q, CleanCutTitle says %q", c.in, joined, CleanCutTitle(c.in))
		}
	}
}

func TestSameTitle(t *testing.T) {
	cases := []struct {
		a, b string
		want bool
	}{
		{"Hello, World!", "hello world", true},
		{"Under Pressure", "Under Pressure", true},
		{"Song Title (feat. Guest)", "song title feat guest", true},
		{"Under Pressure", "Under Pressure (Official Video)", false},
		{"Track", "Track 2", false},
		{"", "", false},
		{"!!", "", false},
	}
	for _, c := range cases {
		if got := SameTitle(c.a, c.b); got != c.want {
			t.Errorf("SameTitle(%q, %q) = %v, want %v", c.a, c.b, got, c.want)
		}
	}
}

// The tag pass writes titles, so it keeps a group that marks a different cut
// of the song even where the search drops it.
func TestCleanUploadNotes(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Song (Official Video)", "Song"},
		{"Song [Lyrics]", "Song"},
		{"Song (Visualizer)", "Song"},
		{"Song (Audio)", "Song"},
		{"Song (Official Music Video) (HD)", "Song"},
		{"Song (Clean)", "Song (Clean)"},
		{"Song (8D Audio)", "Song (8D Audio)"},
		{"Song (Teaser)", "Song (Teaser)"},
		{"Song (Trailer)", "Song (Trailer)"},
		{"Song (Explicit)", "Song (Explicit)"},
		{"Song (Clean) (Official Audio)", "Song (Clean)"},
		{"Song (Official Audio) (Explicit)", "Song (Explicit)"},
		{"Song (Official Video) [Explicit]", "Song [Explicit]"},
		{"Song (Official Audio) (Explicit Official Video)", "Song (Explicit Official Video)"},
		{"Song (Live) (Official Audio) (Explicit)", "Song (Live) (Explicit)"},
		{"Song (Live)", "Song (Live)"},
		{"(Official Video)", "(Official Video)"},
	}
	for _, c := range cases {
		if got := CleanUploadNotes(c.in); got != c.want {
			t.Errorf("CleanUploadNotes(%q) = %q, want %q", c.in, got, c.want)
		}
	}
	for _, in := range []string{"Song (Clean)", "Song (8D Audio)", "Song (Teaser)", "Song (Trailer)"} {
		if got := CleanDescriptiveTitle(in); got != "Song" {
			t.Errorf("CleanDescriptiveTitle(%q) = %q, want the search to drop it", in, got)
		}
	}
}

func TestCleanCutTitle(t *testing.T) {
	cases := []struct{ in, rest, cut string }{
		{"Driftwood (2020 Remaster)", "Driftwood", "Driftwood"},
		{"Song [Remastered 2011] (Official Audio)", "Song", "Song"},
		{"Song (Clean)", "Song", "Song (Clean)"},
		{"Song (8D Audio)", "Song", "Song (8D Audio)"},
		{"Song (Official Video) (Explicit)", "Song", "Song (Explicit)"},
		{"Song (2020 Remaster) (Clean)", "Song", "Song (Clean)"},
		{"Song (Live)", "Song (Live)", "Song (Live)"},
		{"Song (Remastered Live Version)", "Song (Remastered Live Version)", "Song (Remastered Live Version)"},
	}
	for _, c := range cases {
		if got, _ := SplitCutGroups(c.in); got != c.rest {
			t.Errorf("SplitCutGroups(%q) = %q, want %q", c.in, got, c.rest)
		}
		if got := CleanCutTitle(c.in); got != c.cut {
			t.Errorf("CleanCutTitle(%q) = %q, want %q", c.in, got, c.cut)
		}
	}
}

// A search asks for the song alone: MusicBrainz titles a live take or an
// alternate by the song, so a phrase holding more finds nothing.
func TestCoreTitle(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Song (Live at Sin-\u00e9)", "Song"},
		{"Song - Live at Sin-\u00e9", "Song"},
		{"Song (X Remix)", "Song"},
		{"Song (Clean)", "Song"},
		{"Song (Club Mix)", "Song"},
		{"Song (Shep Pettibone Mix)", "Song"},
		{"Song (Demo)", "Song"},
		{"Song [Acoustic]", "Song"},
		{"Song (Taylor's Version)", "Song"},
		{"Song (Bonus Track)", "Song"},
		{"Song (Radio Edit) [Official Video]", "Song"},
		{"Song (Live) - Remastered 2011", "Song"},
		{"Song - Radio Edit (Clean)", "Song"},
		{"Song (2020 Remaster) (Live at the BBC)", "Song"},
		{"Song (Part 2) (Live)", "Song (Part 2)"},
		// A guest names no recording, and the scorer forgives one.
		{"Song (feat. Guest)", "Song (feat. Guest)"},
		{"Song (feat. Guest) (Live)", "Song (feat. Guest)"},
		// Not version notes: these are the title.
		{"Song (Part 2)", "Song (Part 2)"},
		{"Sweet Dreams (Are Made of This)", "Sweet Dreams (Are Made of This)"},
		{"Song (Mixed Emotions)", "Song (Mixed Emotions)"},
		{"Song (Prodigal)", "Song (Prodigal)"},
		{"Sing - Sing - Sing", "Sing - Sing - Sing"},
		{"Live Forever", "Live Forever"},
		{"Remix the World", "Remix the World"},
		{"(Live)", "(Live)"},
		{"Live", "Live"},
		{"", ""},
	}
	for _, c := range cases {
		if got := CoreTitle(c.in); got != c.want {
			t.Errorf("CoreTitle(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
