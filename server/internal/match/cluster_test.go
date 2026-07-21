package match

import "testing"

func TestClusterByTags(t *testing.T) {
	tracks := []Track{
		{PID: "a2", Path: "/x/2.flac", Tags: map[string]string{"ARTIST": "Artist", "ALBUM": "Album", "TRACKNUMBER": "2"}},
		{PID: "b1", Path: "/y/1.flac", Tags: map[string]string{"ARTIST": "Other", "ALBUM": "Second", "TRACKNUMBER": "1"}},
		{PID: "a1", Path: "/x/1.flac", Tags: map[string]string{"ARTIST": "Artist", "ALBUM": "Album", "TRACKNUMBER": "1"}},
	}
	units := Cluster(tracks)
	if len(units) != 2 {
		t.Fatalf("want 2 units, got %d", len(units))
	}
	var album *Unit
	for i := range units {
		if len(units[i].Tracks) == 2 {
			album = &units[i]
		}
	}
	if album == nil {
		t.Fatalf("no two track unit found: %+v", units)
	}
	if album.Tracks[0].PID != "a1" || album.Tracks[1].PID != "a2" {
		t.Fatalf("tracks not ordered by number: %v, %v", album.Tracks[0].PID, album.Tracks[1].PID)
	}
}

func TestClusterCaseAndPunctuationInsensitive(t *testing.T) {
	tracks := []Track{
		{PID: "1", Path: "/a/1.flac", Tags: map[string]string{"ARTIST": "The Band", "ALBUM": "Great Album"}},
		{PID: "2", Path: "/a/2.flac", Tags: map[string]string{"ARTIST": "the band", "ALBUM": "Great  Album!"}},
	}
	units := Cluster(tracks)
	if len(units) != 1 {
		t.Fatalf("tag variants should cluster together, got %d units", len(units))
	}
}

func TestClusterDirectoryFallback(t *testing.T) {
	tracks := []Track{
		{PID: "1", Path: "/lib/Some Album/01.flac"},
		{PID: "2", Path: "/lib/Some Album/02.flac"},
		{PID: "3", Path: "/lib/Other Album/01.flac"},
	}
	units := Cluster(tracks)
	if len(units) != 2 {
		t.Fatalf("directory fallback should split by parent, got %d units", len(units))
	}
}

func TestClusterDiscSubdirsFoldTogether(t *testing.T) {
	tracks := []Track{
		{PID: "1", Path: "/lib/Big Album/CD1/01.flac"},
		{PID: "2", Path: "/lib/Big Album/CD2/01.flac"},
		{PID: "3", Path: "/lib/Big Album/Disc 2/02.flac"},
	}
	units := Cluster(tracks)
	if len(units) != 1 {
		t.Fatalf("disc subdirectories should fold into one unit, got %d", len(units))
	}
}

func TestClusterMultiDiscByTags(t *testing.T) {
	tracks := []Track{
		{PID: "d2t1", Path: "/l/d2/01.flac", Tags: map[string]string{"ARTIST": "A", "ALBUM": "X", "DISCNUMBER": "2", "TRACKNUMBER": "1"}},
		{PID: "d1t2", Path: "/l/d1/02.flac", Tags: map[string]string{"ARTIST": "A", "ALBUM": "X", "DISCNUMBER": "1", "TRACKNUMBER": "2"}},
		{PID: "d1t1", Path: "/l/d1/01.flac", Tags: map[string]string{"ARTIST": "A", "ALBUM": "X", "DISCNUMBER": "1", "TRACKNUMBER": "1"}},
	}
	units := Cluster(tracks)
	if len(units) != 1 {
		t.Fatalf("want one unit, got %d", len(units))
	}
	got := []string{units[0].Tracks[0].PID, units[0].Tracks[1].PID, units[0].Tracks[2].PID}
	want := []string{"d1t1", "d1t2", "d2t1"}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("order %v, want %v", got, want)
		}
	}
}

func TestClusterCompilationSharedAlbum(t *testing.T) {
	tracks := []Track{
		{PID: "1", Path: "/c/01.mp3", Tags: map[string]string{"ARTIST": "One", "ALBUM": "Now That Is Music"}},
		{PID: "2", Path: "/c/02.mp3", Tags: map[string]string{"ARTIST": "Two", "ALBUM": "Now That Is Music"}},
		{PID: "3", Path: "/c/03.mp3", Tags: map[string]string{"ARTIST": "Three", "ALBUM": "Now That Is Music"}},
	}
	units := Cluster(tracks)
	if len(units) != 1 {
		t.Fatalf("same album in the same directory should merge into one unit, got %d", len(units))
	}
	if len(units[0].Tracks) != 3 {
		t.Fatalf("merged unit should hold all three tracks, got %d", len(units[0].Tracks))
	}
}

func TestClusterCompilationAcrossDiscDirs(t *testing.T) {
	tracks := []Track{
		{PID: "1", Path: "/c/CD1/01.mp3", Tags: map[string]string{"ARTIST": "One", "ALBUM": "Hits"}},
		{PID: "2", Path: "/c/CD2/01.mp3", Tags: map[string]string{"ARTIST": "Two", "ALBUM": "Hits"}},
	}
	units := Cluster(tracks)
	if len(units) != 1 {
		t.Fatalf("compilation across disc subdirectories should be one unit, got %d", len(units))
	}
}

func TestClusterSameAlbumNameDifferentDirsStaysSplit(t *testing.T) {
	tracks := []Track{
		{PID: "1", Path: "/lib/One/Greatest Hits/01.mp3", Tags: map[string]string{"ARTIST": "One", "ALBUM": "Greatest Hits"}},
		{PID: "2", Path: "/lib/Two/Greatest Hits/01.mp3", Tags: map[string]string{"ARTIST": "Two", "ALBUM": "Greatest Hits"}},
	}
	units := Cluster(tracks)
	if len(units) != 2 {
		t.Fatalf("same album title by different artists in different directories must not merge, got %d", len(units))
	}
}

func TestParseOrdinal(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{"3", 3}, {"3/12", 3}, {" 07 ", 7}, {"", 0}, {"x", 0}, {"-1", 0},
	}
	for _, c := range cases {
		if got := parseOrdinal(c.in); got != c.want {
			t.Errorf("parseOrdinal(%q) = %d, want %d", c.in, got, c.want)
		}
	}
}
