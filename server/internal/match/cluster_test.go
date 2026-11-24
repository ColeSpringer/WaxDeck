package match

import (
	"slices"
	"strings"
	"testing"
)

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
		{"3", 3}, {"3/12", 3}, {"3 of 12", 3}, {"03.", 3}, {" 07 ", 7}, {"", 0}, {"x", 0}, {"-1", 0},
	}
	for _, c := range cases {
		if got := ParseOrdinal(c.in); got != c.want {
			t.Errorf("ParseOrdinal(%q) = %d, want %d", c.in, got, c.want)
		}
	}
}

func TestClusterByFolderIgnoresTags(t *testing.T) {
	units := ClusterByFolder([]Track{
		{PID: "2", Path: "Book/Disc 2/01.mp3", Tags: map[string]string{"ALBUM": "Book, Part Two", "DISCNUMBER": "2"}},
		{PID: "1", Path: "Book/Disc 1/01.mp3", Tags: map[string]string{"ALBUM": "Book", "DISCNUMBER": "1"}},
		{PID: "3", Path: "Other/01.mp3", Tags: map[string]string{"ALBUM": "Book"}},
		{PID: "4", Path: "loose.mp3"},
		{PID: "5", Path: "also-loose.mp3", Tags: map[string]string{"ALBUM": "Elsewhere"}},
	})
	if len(units) != 3 {
		t.Fatalf("units = %d, want one per folder", len(units))
	}
	var got [][]string
	for _, u := range units {
		var ids []string
		for _, tr := range u.Tracks {
			ids = append(ids, tr.PID)
		}
		got = append(got, ids)
	}
	want := [][]string{{"1", "2"}, {"3"}, {"5", "4"}}
	for _, w := range want {
		found := false
		for _, g := range got {
			if strings.Join(g, ",") == strings.Join(w, ",") {
				found = true
			}
		}
		if !found {
			t.Errorf("units = %v, want %v among them", got, w)
		}
	}
}

// bookSubfolders are the folder names the book fold reads as a disc or
// part of the folder above. The same list pins the client's rule
// (app/app/test/upload_kind_detect_test.dart), so the dialog's default
// grouping and the server's agree.
var bookSubfolders = map[string]bool{
	"CD1": true, "cd 2": true, "Disc 1": true, "disc_2": true, "Disk-3": true,
	"DISC.4": true, "Part 1": true, "part 12": true, "Part_3": true, "Part1": true,
	"Bonus": false, "Disc": false, "Part One": false, "Pt 1": false, "Side A": false,
	"Vol 1": false, "CD1 Extras": false, "Discography 2": false, "Partita 2": false,
	"Part\u00a01": true, "Part\u20031": false,
}

func TestFoldBookDirFoldsDiscAndPartFolders(t *testing.T) {
	for name, folds := range bookSubfolders {
		dir := "Author/Book/" + name
		want := dir
		if folds {
			want = "Author/Book"
		}
		if got := FoldBookDir(dir); got != want {
			t.Errorf("FoldBookDir(%q) = %q, want %q", dir, got, want)
		}
	}
}

// A book split into part folders is one unit, in folder then track
// order. A sent path is a slash path whatever the server's OS.
func TestClusterByFolderFoldsPartFolders(t *testing.T) {
	units := ClusterByFolder([]Track{
		{PID: "p2-01", Sent: true, Path: "Author/Book/Part 2/01.mp3", Tags: map[string]string{"TRACKNUMBER": "1"}},
		{PID: "p1-02", Sent: true, Path: "Author/Book/Part 1/02.mp3", Tags: map[string]string{"TRACKNUMBER": "2"}},
		{PID: "p1-01", Sent: true, Path: "Author/Book/Part 1/01.mp3", Tags: map[string]string{"TRACKNUMBER": "1"}},
		{PID: "other", Sent: true, Path: "Author/Other/01.mp3", Tags: map[string]string{"TRACKNUMBER": "1"}},
	})
	if len(units) != 2 {
		t.Fatalf("units = %d, want the book and the other folder", len(units))
	}
	var got []string
	for _, tr := range units[0].Tracks {
		got = append(got, tr.PID)
	}
	if want := "p1-01,p1-02,p2-01"; strings.Join(got, ",") != want {
		t.Errorf("order = %v, want %s", got, want)
	}
	if got := BookFolder(units[0].Tracks[2]); got != "Author/Book" {
		t.Errorf("BookFolder = %q, want %q", got, "Author/Book")
	}
}

func TestClusterOrdersDiscFoldersBeforeTrackNumbers(t *testing.T) {
	units := ClusterByFolder([]Track{
		{PID: "cd2-01", Sent: true, Path: "Book/CD2/01.mp3", Tags: map[string]string{"TRACKNUMBER": "1"}},
		{PID: "cd1-02", Sent: true, Path: "Book/CD1/02.mp3", Tags: map[string]string{"TRACKNUMBER": "2"}},
		{PID: "cd1-01", Sent: true, Path: "Book/CD1/01.mp3", Tags: map[string]string{"TRACKNUMBER": "1"}},
	})
	if len(units) != 1 {
		t.Fatalf("units = %d, want the disc folders folded into one", len(units))
	}
	var got []string
	for _, tr := range units[0].Tracks {
		got = append(got, tr.PID)
	}
	if want := "cd1-01,cd1-02,cd2-01"; strings.Join(got, ",") != want {
		t.Errorf("order = %v, want %s", got, want)
	}
}

// Folders a batch sent order a unit by their numbers before its track
// numbers: files staged one folder each keep their track order.
func TestClusterOrdersSentFoldersByTheirNumber(t *testing.T) {
	for name, tc := range map[string]struct {
		cluster func([]Track) []Unit
		tracks  []Track
		want    string
	}{
		"disc folders past nine": {ClusterByFolder, []Track{
			{PID: "cd10-01", Sent: true, Path: "Book/CD10/01.mp3", Tags: map[string]string{"TRACKNUMBER": "1"}},
			{PID: "cd2-02", Sent: true, Path: "Book/CD2/02.mp3", Tags: map[string]string{"TRACKNUMBER": "2"}},
			{PID: "cd2-01", Sent: true, Path: "Book/CD2/01.mp3", Tags: map[string]string{"TRACKNUMBER": "1"}},
		}, "cd2-01,cd2-02,cd10-01"},
		"files staged one folder each": {Cluster, []Track{
			{PID: "second", Path: "/staging/up-01A/b.mp3", Tags: map[string]string{"ALBUM": "Fetched", "ARTIST": "Band", "TRACKNUMBER": "2"}},
			{PID: "first", Path: "/staging/up-01B/a.mp3", Tags: map[string]string{"ALBUM": "Fetched", "ARTIST": "Band", "TRACKNUMBER": "1"}},
		}, "first,second"},
	} {
		units := tc.cluster(tc.tracks)
		if len(units) != 1 {
			t.Fatalf("%s: units = %d, want one", name, len(units))
		}
		var got []string
		for _, tr := range units[0].Tracks {
			got = append(got, tr.PID)
		}
		if strings.Join(got, ",") != tc.want {
			t.Errorf("%s: order = %v, want %s", name, got, tc.want)
		}
	}
}

// Files that came with no batch folder (an acquisition's staged files,
// a library album) order by disc and track number, whatever folders
// hold them.
func TestClusterOrdersFilesSentFromNoFolderByDiscAndTrack(t *testing.T) {
	units := Cluster([]Track{
		{PID: "cd1-02", Path: "/library/Band/Album/CD1/02.mp3", Tags: map[string]string{"ALBUM": "Album", "ARTIST": "Band", "TRACKNUMBER": "2"}},
		{PID: "d2-01", Path: "/library/Band/Album/CD2/01.mp3", Tags: map[string]string{"ALBUM": "Album", "ARTIST": "Band", "TRACKNUMBER": "1", "DISCNUMBER": "2"}},
		{PID: "cd2-01", Path: "/library/Band/Album/CD2/01b.mp3", Tags: map[string]string{"ALBUM": "Album", "ARTIST": "Band", "TRACKNUMBER": "1"}},
	})
	if len(units) != 1 {
		t.Fatalf("units = %d, want one", len(units))
	}
	var got []string
	for _, tr := range units[0].Tracks {
		got = append(got, tr.PID)
	}
	if want := "cd2-01,cd1-02,d2-01"; strings.Join(got, ",") != want {
		t.Errorf("order = %v, want %s", got, want)
	}
}

// Batch folders order segment by segment, each name naturally: its runs
// of digits by their number, the text between them as text.
func TestCompareFoldersBySegmentNumbers(t *testing.T) {
	in := []string{"Book/Part 10/CD1", "Book/Part 2/CD10", "Book/Part 2/CD2", "Book", "Book/Part 2/CD1",
		"Record/Side B", "Record/Side A", "Book/Part 1/CD1", "Vol 1 Part 10", "Vol 1 Part 2",
		"Saga/Book 3 - CD 10", "Saga/Book 3 - CD 2", "Saga/Book 10 - CD 1"}
	slices.SortFunc(in, CompareFolders)
	want := []string{"Book", "Book/Part 1/CD1", "Book/Part 2/CD1", "Book/Part 2/CD2", "Book/Part 2/CD10",
		"Book/Part 10/CD1", "Record/Side A", "Record/Side B", "Saga/Book 3 - CD 2", "Saga/Book 3 - CD 10",
		"Saga/Book 10 - CD 1", "Vol 1 Part 2", "Vol 1 Part 10"}
	if !slices.Equal(in, want) {
		t.Errorf("order = %q, want %q", in, want)
	}
}
