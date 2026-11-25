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
			name:       "a parenthesized remaster note is dropped from the search",
			tags:       map[string]string{"ARTIST": "Marrow and Pine", "TITLE": "Driftwood (2020 Remaster)"},
			wantArtist: "Marrow and Pine",
			wantTitle:  "Driftwood",
			wantOK:     true,
		},
		{
			name:       "a remastered note behind an upload note",
			tags:       map[string]string{"ARTIST": "Some Channel", "TITLE": "Marrow and Pine - Cartographer (Remastered 2011) (Official Audio)"},
			wantArtist: "Marrow and Pine",
			wantTitle:  "Cartographer",
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
			name:       "a group naming the recording is not searched for",
			tags:       map[string]string{"ARTIST": "X", "TITLE": "Song Name (Live)"},
			wantArtist: "X",
			wantTitle:  "Song Name",
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
			name:       "topic channel with a version tail keeps the channel's artist",
			tags:       map[string]string{"ARTIST": "Queen - Topic", "TITLE": "Bohemian Rhapsody - Remastered 2011"},
			wantArtist: "Queen",
			wantTitle:  "Bohemian Rhapsody",
			wantOK:     true,
		},
		{
			name:       "a from-the-film tail is not a track name",
			tags:       map[string]string{"ARTIST": "Idina Menzel - Topic", "TITLE": "Let It Go - From \"Frozen\"/Soundtrack Version"},
			wantArtist: "Idina Menzel",
			wantTitle:  "Let It Go",
			wantOK:     true,
		},
		{
			name:       "a vevo uploader always splits, version-like or not",
			tags:       map[string]string{"ARTIST": "OasisVEVO", "TITLE": "Oasis - Live Forever (Official Video)"},
			wantArtist: "Oasis",
			wantTitle:  "Live Forever",
			wantOK:     true,
		},
		{
			name:       "a vevo uploader's split drops a version tail from the track",
			tags:       map[string]string{"ARTIST": "adelevevo", "TITLE": "Adele - Hello - Live at the BBC"},
			wantArtist: "Adele",
			wantTitle:  "Hello",
			wantOK:     true,
		},
		{
			name:       "an ordinary artist - track title still splits",
			tags:       map[string]string{"ARTIST": "Some Channel", "TITLE": "Hozier - From Eden"},
			wantArtist: "Hozier",
			wantTitle:  "From Eden",
			wantOK:     true,
		},
		{
			name:       "must split: Oasis - Live Forever",
			tags:       map[string]string{"ARTIST": "Some Channel", "TITLE": "Oasis - Live Forever"},
			wantArtist: "Oasis",
			wantTitle:  "Live Forever",
			wantOK:     true,
		},
		{
			name:       "must split: Smashing Pumpkins - 1979",
			tags:       map[string]string{"ARTIST": "Some Channel", "TITLE": "Smashing Pumpkins - 1979"},
			wantArtist: "Smashing Pumpkins",
			wantTitle:  "1979",
			wantOK:     true,
		},
		{
			name:       "must split: Imagine Dragons - Demons",
			tags:       map[string]string{"ARTIST": "Some Channel", "TITLE": "Imagine Dragons - Demons"},
			wantArtist: "Imagine Dragons",
			wantTitle:  "Demons",
			wantOK:     true,
		},
		{
			name:       "must split: Some Artist - Remix the World",
			tags:       map[string]string{"ARTIST": "Some Channel", "TITLE": "Some Artist - Remix the World"},
			wantArtist: "Some Artist",
			wantTitle:  "Remix the World",
			wantOK:     true,
		},
		{
			name:       "must split: Some Artist - Demo Love Song",
			tags:       map[string]string{"ARTIST": "Some Channel", "TITLE": "Some Artist - Demo Love Song"},
			wantArtist: "Some Artist",
			wantTitle:  "Demo Love Song",
			wantOK:     true,
		},
		{
			name:       "must split: Some Artist - Version of Me",
			tags:       map[string]string{"ARTIST": "Some Channel", "TITLE": "Some Artist - Version of Me"},
			wantArtist: "Some Artist",
			wantTitle:  "Version of Me",
			wantOK:     true,
		},
		{
			name:       "a live-at tail is not a track name",
			tags:       map[string]string{"ARTIST": "Queen", "TITLE": "Song - Live at Wembley Stadium"},
			wantArtist: "Queen",
			wantTitle:  "Song",
			wantOK:     true,
		},
		{
			name:       "a vevo uploader splits even when the right side is a version tail",
			tags:       map[string]string{"ARTIST": "QueenVEVO", "TITLE": "Queen - Live at Wembley Stadium"},
			wantArtist: "Queen",
			wantTitle:  "Live at Wembley Stadium",
			wantOK:     true,
		},
		{
			name:       "a radio edit tail is not a track name",
			tags:       map[string]string{"ARTIST": "Queen", "TITLE": "Song - Radio Edit"},
			wantArtist: "Queen",
			wantTitle:  "Song",
			wantOK:     true,
		},
		{
			name:       "a word holding a noise word is not noise",
			tags:       map[string]string{"ARTIST": "X", "TITLE": "Song (Prodigal)"},
			wantArtist: "X",
			wantTitle:  "Song (Prodigal)",
			wantOK:     true,
		},
		{
			name:       "unofficial is not official",
			tags:       map[string]string{"ARTIST": "X", "TITLE": "Song (Unofficial)"},
			wantArtist: "X",
			wantTitle:  "Song (Unofficial)",
			wantOK:     true,
		},
		{
			name:       "videotape is not video",
			tags:       map[string]string{"ARTIST": "X", "TITLE": "Song (Videotape)"},
			wantArtist: "X",
			wantTitle:  "Song (Videotape)",
			wantOK:     true,
		},
		{
			name:       "official video goes",
			tags:       map[string]string{"ARTIST": "X", "TITLE": "Song (Official Video)"},
			wantArtist: "X",
			wantTitle:  "Song",
			wantOK:     true,
		},
		{
			name:       "a word holding a content word does not keep a noise group",
			tags:       map[string]string{"ARTIST": "X", "TITLE": "Song (Delivered Audio)"},
			wantArtist: "X",
			wantTitle:  "Song",
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
			artist, title, _, ok := recordingQuery(Track{Tags: c.tags})
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

// A typed query is never split into an artist: the derivation is there to
// rescue titles a machine wrote. Its title is still searched as the song
// alone, as a derived one is, since a note, a cut mark or a live group
// (often pre-filled from the suggestion) only keeps the search from
// finding the song.
func TestRecordingQueryKeepsATypedQueryUnsplit(t *testing.T) {
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
			name:       "a typed upload note is dropped from the search",
			tags:       map[string]string{"TITLE": "whatever"},
			query:      &TrackQuery{Artist: "Portishead", Title: "Roads (Official Video)"},
			wantArtist: "Portishead",
			wantTitle:  "Roads",
			wantOK:     true,
		},
		{
			name:       "a typed cut mark is dropped from the search",
			tags:       map[string]string{"TITLE": "whatever"},
			query:      &TrackQuery{Artist: "Band", Title: "Song (Clean)"},
			wantArtist: "Band",
			wantTitle:  "Song",
			wantOK:     true,
		},
		{
			name:       "a typed group naming another recording is dropped from the search",
			tags:       map[string]string{"TITLE": "whatever"},
			query:      &TrackQuery{Artist: "Band", Title: "Song (Live)"},
			wantArtist: "Band",
			wantTitle:  "Song",
			wantOK:     true,
		},
		{
			name:       "a typed version tail is dropped from the search",
			tags:       map[string]string{"TITLE": "whatever"},
			query:      &TrackQuery{Artist: "Band", Title: "Song - Live at the BBC"},
			wantArtist: "Band",
			wantTitle:  "Song",
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
			wantTitle:  "Get Lucky",
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
			artist, title, _, ok := recordingQuery(Track{Tags: c.tags, Query: c.query})
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

func TestJudgedTrack(t *testing.T) {
	cases := []struct {
		name, artist, title   string
		wantArtist, wantTitle string
		wantChanged           bool
	}{
		{"plain", "Band", "Song", "Band", "Song", false},
		{"artist and title", "Band", "Band - Song", "Band", "Song", true},
		{"vevo", "BandVEVO", "Band - Song", "Band", "Song", true},
		{"remaster tail dropped", "Band", "Song - Remastered 2011", "Band", "Song", true},
		{"live tail kept", "Band", "Song - Live at the BBC", "Band", "Song (Live at the BBC)", true},
		{"both tails, only the remaster dropped", "Band", "Band - Song - Radio Edit - 2015 Remaster", "Band", "Song (Radio Edit)", true},
		{"topic channel", "Band - Topic", "Song", "Band", "Song", true},
		{"a clean cut stays", "Band", "Song (Clean)", "Band", "Song (Clean)", false},
		{"an 8d cut stays after the split", "Band", "Band - Song (8D Audio)", "Band", "Song (8D Audio)", true},
		{"upload notes go, the cut stays", "Band", "Song (Official Video) (Explicit)", "Band", "Song (Explicit)", true},
		{"a parenthesized remaster goes", "Band", "Song (2020 Remaster)", "Band", "Song", true},
		{"a kept tail is cleaned", "Band", "Song - Live (Official Video)", "Band", "Song (Live)", true},
		{"a vevo split of a tailed title keeps no tail twice", "BandVEVO", "Song - Live", "Song", "Live", true},
		{"a cut after a remaster tail stays", "The Band", "The Band - Song - 2015 Remaster (Clean)", "The Band", "Song (Clean)", true},
		{"a cut after a remastered tail stays", "The Band - Topic", "Song - Remastered 2011 (Explicit)", "The Band", "Song (Explicit)", true},
		{"a cut after a bonus track tail stays", "The Band", "Song - Bonus Track (Clean)", "The Band", "Song (Clean)", true},
		{"a cut after a kept tail stays", "Band", "Song - Radio Edit - 2015 Remaster (Clean)", "Band", "Song (Radio Edit) (Clean)", true},
		{"a cut on a kept tail is not nested", "Band", "Song - Live (Clean)", "Band", "Song (Live) (Clean)", true},
		{"a cut on a kept edit tail is not nested", "Band", "Song - Radio Edit (Clean)", "Band", "Song (Radio Edit) (Clean)", true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			in := Track{Tags: map[string]string{"ARTIST": c.artist, "TITLE": c.title}}
			got, changed := judgedTrack(in)
			if changed != c.wantChanged || got.Tags["ARTIST"] != c.wantArtist || got.Tags["TITLE"] != c.wantTitle {
				t.Fatalf("judgedTrack = %q / %q (changed %v), want %q / %q (%v)",
					got.Tags["ARTIST"], got.Tags["TITLE"], changed, c.wantArtist, c.wantTitle, c.wantChanged)
			}
			if in.Tags["TITLE"] != c.title {
				t.Fatal("judgedTrack wrote through to the track's own tags")
			}
		})
	}
}

// The suggestion is what accept-best judges, so accepting it files the cut
// the upload names; the search keeps its wider cleaning to find the song.
func TestSuggestionIsTheJudgedForm(t *testing.T) {
	cases := []struct {
		name, artist, title       string
		wantArtist, wantTitle     string
		searchArtist, searchTitle string
	}{
		{"a clean cut", "Band", "Song (Clean)", "Band", "Song (Clean)", "Band", "Song"},
		{"a live tail", "Band", "Song - Live at the BBC", "Band", "Song (Live at the BBC)", "Band", "Song"},
		{"an official video", "Some Channel", "Artist - Song (Official Video)", "Artist", "Song", "Artist", "Song"},
		{"a remaster tail", "Band - Topic", "Song - Remastered 2011", "Band", "Song", "Band", "Song"},
		{"a remaster group beside a cut", "Band", "Song (2020 Remaster) (Explicit)", "Band", "Song (Explicit)", "Band", "Song"},
		{"a live group", "Band", "Song (Live at Sin-\u00e9)", "Band", "Song (Live at Sin-\u00e9)", "Band", "Song"},
		{"a remix group", "Band", "Song (X Remix)", "Band", "Song (X Remix)", "Band", "Song"},
		{"a cut on a live tail", "Band", "Song - Live (Clean)", "Band", "Song (Live) (Clean)", "Band", "Song"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			tr := Track{Tags: map[string]string{"ARTIST": c.artist, "TITLE": c.title}}
			artist, title, ok := SuggestedQuery(tr)
			if !ok || artist != c.wantArtist || title != c.wantTitle {
				t.Errorf("suggested (%q, %q, %v), want (%q, %q)", artist, title, ok, c.wantArtist, c.wantTitle)
			}
			artist, title = DerivedQuery(tr)
			if artist != c.searchArtist || title != c.searchTitle {
				t.Errorf("searched (%q, %q), want (%q, %q)", artist, title, c.searchArtist, c.searchTitle)
			}
		})
	}
}

// The search asks for the song alone, derived or typed, and carries the
// title that names the recording beside it for picking among the hits.
func TestRecordingQuerySearchesTheSong(t *testing.T) {
	cases := []struct{ title, wantNamed string }{
		{"Song (Live at X)", "Song (Live at X)"},
		{"Song - Live at X", "Song (Live at X)"},
		{"Song (X Remix)", "Song (X Remix)"},
		{"Song (Clean)", "Song (Clean)"},
		{"Song - Radio Edit (Official Video)", "Song (Radio Edit)"},
		{"Song", ""},
	}
	for _, c := range cases {
		derived := Track{Tags: map[string]string{"ARTIST": "Band", "TITLE": c.title}}
		typed := Track{
			Tags:  map[string]string{"ARTIST": "Some Channel", "TITLE": "whatever"},
			Query: &TrackQuery{Artist: "Band", Title: c.title},
		}
		for name, tr := range map[string]Track{"derived": derived, "typed": typed} {
			artist, title, named, ok := recordingQuery(tr)
			if !ok || artist != "Band" || title != "Song" || named != c.wantNamed {
				t.Errorf("%s %q: searched (%q, %q) named %q, want (Band, Song) named %q",
					name, c.title, artist, title, named, c.wantNamed)
			}
		}
	}
}
