package match

import "testing"

func release(artist, title string, year int, titles ...string) *Release {
	r := &Release{MBID: "rel-" + title, Title: title, Artist: artist, Year: year}
	for i, t := range titles {
		r.Tracks = append(r.Tracks, ReleaseTrack{
			RecordingMBID: "rec-" + t,
			Title:         t,
			Disc:          1,
			Position:      i + 1,
			DurationSec:   180 + float64(i),
		})
	}
	return r
}

func unitFor(artist, album string, titles ...string) Unit {
	var tracks []Track
	for i, title := range titles {
		tracks = append(tracks, Track{
			PID:  "t" + title,
			Path: "/lib/x/" + title + ".flac",
			Tags: map[string]string{
				"ARTIST": artist, "ALBUM": album, "TITLE": title,
				"TRACKNUMBER": itoa(i + 1),
			},
			DurationSec: 180 + float64(i),
		})
	}
	return Unit{Tracks: tracks}
}

func itoa(n int) string {
	if n < 10 {
		return string(rune('0' + n))
	}
	return string(rune('0'+n/10)) + string(rune('0'+n%10))
}

func TestScorePerfectMatch(t *testing.T) {
	u := unitFor("Artist", "Album", "One", "Two", "Three")
	r := release("Artist", "Album", 0, "One", "Two", "Three")
	m := Score(u, r, Weights{})
	if m.Distance != 0 {
		t.Fatalf("perfect match should be zero distance, got %v (components %+v)", m.Distance, m.Components)
	}
	if len(m.Pairings) != 3 || len(m.MissingIndexes) != 0 || len(m.ExtraIndexes) != 0 {
		t.Fatalf("pairing shape wrong: %+v", m)
	}
	for i, p := range m.Pairings {
		if p.TrackIndex != i || p.ReleaseIndex != i {
			t.Fatalf("pairing %d not identity: %+v", i, p)
		}
	}
}

func TestScoreReorderedFilesStillPair(t *testing.T) {
	u := unitFor("Artist", "Album", "Three", "One", "Two")
	// Track numbers now lie (they say 1,2,3 for Three,One,Two), but the
	// titles and assignment should still pair correctly.
	r := release("Artist", "Album", 0, "One", "Two", "Three")
	m := Score(u, r, Weights{})
	byTitle := map[string]string{}
	for _, p := range m.Pairings {
		byTitle[u.Tracks[p.TrackIndex].Tags["TITLE"]] = r.Tracks[p.ReleaseIndex].Title
	}
	for _, title := range []string{"One", "Two", "Three"} {
		if byTitle[title] != title {
			t.Fatalf("title %q paired to %q", title, byTitle[title])
		}
	}
	if m.Distance >= 0.3 {
		t.Fatalf("reordered files should stay a plausible match, got %v", m.Distance)
	}
}

func TestScoreMissingTrackPenalized(t *testing.T) {
	full := unitFor("Artist", "Album", "One", "Two", "Three")
	short := Unit{Tracks: full.Tracks[:2]}
	r := release("Artist", "Album", 0, "One", "Two", "Three")
	mFull := Score(full, r, Weights{})
	mShort := Score(short, r, Weights{})
	if mShort.Distance <= mFull.Distance {
		t.Fatalf("missing track must cost something: full %v, short %v", mFull.Distance, mShort.Distance)
	}
	if len(mShort.MissingIndexes) != 1 || mShort.MissingIndexes[0] != 2 {
		t.Fatalf("missing index wrong: %v", mShort.MissingIndexes)
	}
}

func TestScoreExtraTrackPenalized(t *testing.T) {
	u := unitFor("Artist", "Album", "One", "Two", "Three", "Bonus Demo")
	r := release("Artist", "Album", 0, "One", "Two", "Three")
	m := Score(u, r, Weights{})
	if len(m.ExtraIndexes) != 1 {
		t.Fatalf("want one extra track, got %v", m.ExtraIndexes)
	}
	if u.Tracks[m.ExtraIndexes[0]].Tags["TITLE"] != "Bonus Demo" {
		t.Fatalf("wrong track marked extra: %v", m.ExtraIndexes)
	}
}

func TestScoreDistinguishesRightAndWrongRelease(t *testing.T) {
	u := unitFor("Artist", "Album", "One", "Two", "Three")
	right := release("Artist", "Album", 0, "One", "Two", "Three")
	wrong := release("Someone Else", "Different Record", 0, "Alpha", "Beta", "Gamma")
	dRight := Score(u, right, Weights{}).Distance
	dWrong := Score(u, wrong, Weights{}).Distance
	if dRight >= dWrong {
		t.Fatalf("right release (%v) must beat wrong release (%v)", dRight, dWrong)
	}
	if dWrong < 0.5 {
		t.Fatalf("entirely wrong release should be distant, got %v", dWrong)
	}
}

func TestScoreCompilationUsesTrackArtists(t *testing.T) {
	u := Unit{Tracks: []Track{
		{PID: "1", Path: "/c/01.mp3", Tags: map[string]string{"ARTIST": "One", "ALBUM": "Hits", "TITLE": "Song A", "TRACKNUMBER": "1"}, DurationSec: 180},
		{PID: "2", Path: "/c/02.mp3", Tags: map[string]string{"ARTIST": "Two", "ALBUM": "Hits", "TITLE": "Song B", "TRACKNUMBER": "2"}, DurationSec: 181},
	}}
	r := &Release{
		MBID: "va", Title: "Hits", Artist: "Various Artists", Compilation: true,
		Tracks: []ReleaseTrack{
			{Title: "Song A", Artist: "One", Disc: 1, Position: 1, DurationSec: 180},
			{Title: "Song B", Artist: "Two", Disc: 1, Position: 2, DurationSec: 181},
		},
	}
	m := Score(u, r, Weights{})
	if m.Distance != 0 {
		t.Fatalf("clean compilation match should be zero, got %v (components %+v)", m.Distance, m.Components)
	}
	swapped := &Release{
		MBID: "va2", Title: "Hits", Artist: "Various Artists", Compilation: true,
		Tracks: []ReleaseTrack{
			{Title: "Song A", Artist: "Two", Disc: 1, Position: 1, DurationSec: 180},
			{Title: "Song B", Artist: "One", Disc: 1, Position: 2, DurationSec: 181},
		},
	}
	if d := Score(u, swapped, Weights{}).Distance; d <= m.Distance {
		t.Fatalf("wrong per track artists should cost, got %v", d)
	}
}

func TestScoreUntaggedFilesUseFilenames(t *testing.T) {
	u := Unit{Tracks: []Track{
		{PID: "1", Path: "/rip/01 - One.flac", DurationSec: 180},
		{PID: "2", Path: "/rip/02 - Two.flac", DurationSec: 181},
		{PID: "3", Path: "/rip/03 - Three.flac", DurationSec: 182},
	}}
	r := release("Artist", "Album", 0, "One", "Two", "Three")
	m := Score(u, r, Weights{})
	for i, p := range m.Pairings {
		if p.TrackIndex != i || p.ReleaseIndex != i {
			t.Fatalf("filename evidence should pair in order, got %+v", m.Pairings)
		}
	}
	if m.Distance > 0.15 {
		t.Fatalf("filename and duration agreement should score well, got %v", m.Distance)
	}
}

func TestScoreYearGrading(t *testing.T) {
	u := unitFor("Artist", "Album", "One", "Two")
	for i := range u.Tracks {
		u.Tracks[i].Tags["DATE"] = "1994-06-01"
	}
	same := Score(u, release("Artist", "Album", 1994, "One", "Two"), Weights{}).Distance
	near := Score(u, release("Artist", "Album", 1995, "One", "Two"), Weights{}).Distance
	far := Score(u, release("Artist", "Album", 2015, "One", "Two"), Weights{}).Distance
	if !(same < near && near < far) {
		t.Fatalf("year grading should order same < near < far: %v %v %v", same, near, far)
	}
}
