package subsonic

import (
	"context"
	"fmt"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// albumListIndex is four albums over the shapes the list types tell
// apart: years 0, 1999, 2010 and 2024, two albums by one artist, and one
// album whose tracks carry two genres.
func albumListIndex() *index {
	return buildIndex([]track{
		{PID: "tr-o1", Title: "Old One", AlbumArtist: "Zed Band", Album: "Old Record", Year: 1999, Genre: "Rock", TrackNo: 1},
		{PID: "tr-o2", Title: "Old Two", AlbumArtist: "Zed Band", Album: "Old Record", Year: 1999, Genre: "Jazz", TrackNo: 2},
		{PID: "tr-m1", Title: "Mid One", AlbumArtist: "Alpha Band", Album: "Mid Record", Year: 2010, Genre: "Pop"},
		{PID: "tr-n1", Title: "New One", AlbumArtist: "Mid Band", Album: "New Record", Year: 2024, Genre: "Pop"},
		{PID: "tr-u1", Title: "Undated One", AlbumArtist: "Alpha Band", Album: "Undated"},
	}, nil)
}

func listQueryFor(t *testing.T, query string) (listQuery, *refusal) {
	t.Helper()
	r := httptest.NewRequest("GET", "/rest/getAlbumList2?"+query, nil)
	if err := r.ParseForm(); err != nil {
		t.Fatal(err)
	}
	return parseListQuery(r)
}

func albumNames(albums []*album) string {
	names := make([]string, len(albums))
	for i, al := range albums {
		names[i] = al.name
	}
	return strings.Join(names, ", ")
}

func TestAlbumListOrdersFromTheIndex(t *testing.T) {
	idx := albumListIndex()
	for _, tc := range []struct{ query, want string }{
		{"type=alphabeticalByName", "Mid Record, New Record, Old Record, Undated"},
		{"type=alphabeticalByArtist", "Mid Record, Undated, New Record, Old Record"},
		{"type=byYear&fromYear=2010&toYear=2015", "Mid Record"},
		{"type=byYear&fromYear=2015&toYear=2010", "Mid Record"},
		{"type=byYear&fromYear=1990&toYear=2030", "Old Record, Mid Record, New Record"},
		{"type=byYear&fromYear=2030&toYear=1990", "New Record, Mid Record, Old Record"},
		// Feishin's "Recently released": newest first, the year-less last.
		{"type=byYear&fromYear=2026&toYear=0", "New Record, Mid Record, Old Record, Undated"},
		{"type=byYear&fromYear=0&toYear=2000", "Undated, Old Record"},
		{"type=byYear&fromYear=0&toYear=0", "Undated"},
		{"type=byGenre&genre=Jazz", "Old Record"},
		{"type=byGenre&genre=Pop", "Mid Record, New Record"},
		{"type=byGenre&genre=Nope", ""},
		{"type=alphabeticalByName&size=2&offset=1", "New Record, Old Record"},
		{"type=alphabeticalByName&offset=-5&size=1", "Mid Record"},
		{"type=alphabeticalByName&offset=9", ""},
	} {
		q, ref := listQueryFor(t, tc.query)
		if ref != nil {
			t.Errorf("%s refused: %+v", tc.query, ref)
			continue
		}
		ordered, ok := indexOrder(idx, q)
		if !ok {
			t.Errorf("%s needs more than the index", tc.query)
			continue
		}
		if got := albumNames(pageAlbums(ordered, q.offset, q.size)); got != tc.want {
			t.Errorf("%s = [%s], want [%s]", tc.query, got, tc.want)
		}
	}
	q, _ := listQueryFor(t, "type=random")
	if shuffled, ok := indexOrder(idx, q); !ok || len(shuffled) != 4 {
		t.Errorf("random = %d albums (%v), want all four", len(shuffled), ok)
	}
}

func TestAlbumListRefusesWhatItCannotAnswer(t *testing.T) {
	for _, query := range []string{
		"", "size=5", "type=mostPopular", "type=byYear", "type=byYear&fromYear=2000",
		"type=byYear&toYear=2000", "type=byYear&fromYear=then&toYear=2000", "type=byGenre",
	} {
		if _, ref := listQueryFor(t, query); ref == nil || ref.code != 10 {
			t.Errorf("%q = %+v, want error 10", query, ref)
		}
	}
	for query, want := range map[string]int{"type=random&size=0": 10, "type=random&size=9999": 500, "type=random": 10} {
		if q, ref := listQueryFor(t, query); ref != nil || q.size != want {
			t.Errorf("%q size = %d (%+v), want %d", query, q.size, ref, want)
		}
	}
	for _, typ := range []string{"newest", "recent", "frequent", "highest", "starred"} {
		q, ref := listQueryFor(t, "type="+typ)
		if ref != nil {
			t.Fatalf("%s refused: %+v", typ, ref)
		}
		if _, ok := indexOrder(albumListIndex(), q); ok {
			t.Errorf("%s answered from the index alone, but it is per-user state", typ)
		}
	}
}

// The played and added lists come as tracks; an album takes the place of
// its first track, foreign tracks are skipped, and paging stops once
// enough albums are known.
func TestFoldAlbumsKeepsFirstAppearances(t *testing.T) {
	idx := buildIndex([]track{
		{PID: "t1", AlbumArtist: "X", Album: "A"}, {PID: "t2", AlbumArtist: "X", Album: "A"},
		{PID: "t1b", AlbumArtist: "X", Album: "A"}, {PID: "t3", AlbumArtist: "X", Album: "B"},
		{PID: "t4", AlbumArtist: "X", Album: "C"},
	}, nil)
	pages := [][]string{{"t1", "t2"}, {"t3", "foreign", "t1b"}, {"t4"}}
	calls := 0
	src := func(ctx context.Context, cursor string) ([]string, string, error) {
		i := calls
		calls++
		next := ""
		if i+1 < len(pages) {
			next = "more"
		}
		return pages[i], next, nil
	}
	f := fold{keepPIDs: true}
	if err := f.extend(context.Background(), idx, src, 2); err != nil || albumNames(f.albums) != "A, B" || calls != 2 {
		t.Fatalf("fold for 2 = [%s] after %d pages (%v), want [A, B] after 2", albumNames(f.albums), calls, err)
	}
	if got := strings.Join(f.pids, ","); got != "t1,t2,t3,t1b" {
		t.Fatalf("pids read = %s, want the index's tracks on the two pages read", got)
	}
	// Asked for more, the same fold carries on from where it stopped.
	if err := f.extend(context.Background(), idx, src, 3); err != nil || albumNames(f.albums) != "A, B, C" || calls != 3 {
		t.Fatalf("fold for 3 = [%s] after %d pages (%v), want [A, B, C] after 3", albumNames(f.albums), calls, err)
	}
	if got := strings.Join(f.pids, ","); got != "t1,t2,t3,t1b,t4" {
		t.Fatalf("pids read = %s, want every index track the list held", got)
	}
}

// A fold never walks further than it can find something: it stops once
// every album of the index is known, and in any case after foldPageCap
// pages.
func TestFoldAlbumsIsBounded(t *testing.T) {
	idx := buildIndex([]track{{PID: "t1", AlbumArtist: "X", Album: "A"}}, nil)
	calls := 0
	endless := func(ctx context.Context, cursor string) ([]string, string, error) {
		calls++
		if calls == 1 {
			return []string{"t1", "foreign"}, "more", nil
		}
		return []string{"foreign"}, "more", nil
	}
	var f fold
	if err := f.extend(context.Background(), idx, endless, 50); err != nil || len(f.albums) != 1 || calls != 1 {
		t.Fatalf("fold = %d albums after %d pages (%v), want the index's one album after 1", len(f.albums), calls, err)
	}
	calls = 0
	none := buildIndex([]track{{PID: "t9", AlbumArtist: "X", Album: "Z"}}, nil)
	var g fold
	if err := g.extend(context.Background(), none, endless, 50); err != nil || calls != foldPageCap {
		t.Fatalf("an endless list was read %d pages (%v), want the cap of %d", calls, err, foldPageCap)
	}
}

// A request past the end of the index reads nothing, and the pages of one
// newest crawl fold the list once between them.
func TestNewestCrawlReadsTheListOnce(t *testing.T) {
	idx := buildIndex([]track{
		{PID: "t1", AlbumArtist: "X", Album: "A"}, {PID: "t2", AlbumArtist: "X", Album: "B"},
		{PID: "t3", AlbumArtist: "X", Album: "C"}, {PID: "t4", AlbumArtist: "X", Album: "D"},
	}, nil)
	pages := [][]string{{"t4", "t3"}, {"t2", "t1"}}
	calls := 0
	h := &Handler{pages: func(uc *service.UserCtx, list, folder string) pageSource {
		return func(ctx context.Context, cursor string) ([]string, string, error) {
			i := 0
			if cursor != "" {
				i = 1
			}
			calls++
			next := ""
			if i == 0 {
				next = "p2"
			}
			return pages[i], next, nil
		}
	}}
	list := func(query string) string {
		t.Helper()
		r := httptest.NewRequest("GET", "/rest/getAlbumList2?"+query, nil)
		if err := r.ParseForm(); err != nil {
			t.Fatal(err)
		}
		albums, _, ref, err := h.albumList(context.Background(), r, &service.UserCtx{}, idx)
		if ref != nil || err != nil {
			t.Fatalf("%s refused: %+v %v", query, ref, err)
		}
		return albumNames(albums)
	}
	for _, query := range []string{"type=newest&offset=999999", "type=recent&offset=4", "type=frequent&offset=4"} {
		if got := list(query); got != "" || calls != 0 {
			t.Fatalf("%s = [%s] after %d pages, want nothing read", query, got, calls)
		}
	}
	if got := list("type=newest&size=2"); got != "D, C" || calls != 1 {
		t.Fatalf("page one = [%s] after %d pages, want [D, C] after 1", got, calls)
	}
	if got := list("type=newest&size=2&offset=2"); got != "B, A" || calls != 2 {
		t.Fatalf("page two = [%s] after %d pages, want [B, A] after 2 in all", got, calls)
	}
	if got := list("type=newest&size=4"); got != "D, C, B, A" || calls != 2 {
		t.Fatalf("the whole list again = [%s] after %d pages, want no more reads", got, calls)
	}
}

// frequent ranks albums by their tracks' plays together, not by their
// best single track: A's two tracks played three times each outrank B's
// one track played five times, where the best track would put B first.
// A tie goes to the album played more recently.
func TestRankByPlaysSumsAnAlbumsTracks(t *testing.T) {
	idx := buildIndex([]track{
		{PID: "a1", AlbumArtist: "X", Album: "A"}, {PID: "a2", AlbumArtist: "X", Album: "A"},
		{PID: "b1", AlbumArtist: "X", Album: "B"}, {PID: "c1", AlbumArtist: "X", Album: "C"},
		{PID: "d1", AlbumArtist: "X", Album: "D"},
	}, nil)
	now := time.Now()
	marks := map[string]service.ItemMark{
		"a1": {PlayCount: 3, LastPlayedAt: now.Add(-time.Hour)},
		"a2": {PlayCount: 3, LastPlayedAt: now.Add(-2 * time.Hour)},
		"b1": {PlayCount: 5, LastPlayedAt: now.Add(-3 * time.Hour)},
		"c1": {PlayCount: 5, LastPlayedAt: now},
	}
	if got := albumNames(rankByPlays(idx.albums, marks)); got != "A, C, B" {
		t.Fatalf("frequent = [%s], want [A, C, B]: summed plays, then the later play", got)
	}
}

// highest keeps the rated albums, best first, ties alphabetical.
func TestHighestKeepsRatedAlbums(t *testing.T) {
	idx := buildIndex([]track{
		{PID: "a1", AlbumArtist: "X", Album: "Alpha", AlbumPID: "al-A"},
		{PID: "b1", AlbumArtist: "X", Album: "Beta", AlbumPID: "al-B"},
		{PID: "c1", AlbumArtist: "X", Album: "Gamma", AlbumPID: "al-C"},
		{PID: "d1", AlbumArtist: "X", Album: "Delta"},
	}, nil)
	got := highestAlbums(idx.albums, map[string]int{"al-C": 80, "al-A": 40, "al-B": 80})
	if names := albumNames(got); names != "Beta, Gamma, Alpha" {
		t.Fatalf("highest = [%s], want [Beta, Gamma, Alpha]", names)
	}
}

// An album's year and genre are the album's, not whichever track a sweep
// reached first: the catalog's year where it holds the album, the
// catalog's rule over the tracks otherwise, and the genre most of its
// tracks carry.
func TestAlbumYearAndGenreAreTheAlbums(t *testing.T) {
	idx := buildIndex([]track{
		{PID: "r1", AlbumArtist: "X", Album: "Loose", Year: 2021, Genre: "Rock", TrackNo: 1},
		{PID: "r2", AlbumArtist: "X", Album: "Loose", Year: 1999, Genre: "Jazz", TrackNo: 2},
		{PID: "r3", AlbumArtist: "X", Album: "Loose", Year: 1999, Genre: "Jazz", TrackNo: 3},
		{PID: "e1", AlbumArtist: "X", Album: "Known", AlbumPID: "al-K", Year: 2010, Genre: "Pop", TrackNo: 1},
		{PID: "e2", AlbumArtist: "X", Album: "Known", AlbumPID: "al-K", Year: 2010, Genre: "Soul", TrackNo: 2},
	}, map[string]service.EntityFacts{"al-K": {Name: "Known", Year: 2005}})
	loose := idx.albumForTrack(track{PID: "r1"})
	if loose.year != 1999 || loose.genre != "Jazz" {
		t.Errorf("loose album = %d %q, want 1999 Jazz", loose.year, loose.genre)
	}
	known := idx.albumForTrack(track{PID: "e1"})
	if known.year != 2005 || known.genre != "Pop" {
		t.Errorf("cataloged album = %d %q, want the catalog's 2005 and the first of the tied genres", known.year, known.genre)
	}
	if !known.hasGenre("Soul") || known.hasGenre("Jazz") {
		t.Error("hasGenre does not answer for any member track")
	}
}

// frequent sums every played track of an album, so it reads its list to
// the end even after every album has appeared: here all three are known
// by the second page, while B's total only overtakes A's on the pages
// after.
func TestFrequentSumsTheWholePlayedList(t *testing.T) {
	var rows []track
	add := func(album string, pids ...string) {
		for _, pid := range pids {
			rows = append(rows, track{PID: pid, AlbumArtist: "X", Album: album})
		}
	}
	add("A", "a1", "a2", "a3", "a4")
	add("B", "b1", "b2", "b3", "b4", "b5", "b6", "b7", "b8")
	add("Fixture", "fx")
	idx := buildIndex(rows, nil)
	plays := map[string]int{"fx": 6, "b1": 5, "b2": 5, "a1": 4, "a2": 4, "a3": 3, "a4": 3,
		"b3": 2, "b4": 2, "b5": 2, "b6": 2, "b7": 2, "b8": 2}
	pages := [][]string{{"fx", "b1", "b2"}, {"a1", "a2", "a3"}, {"a4", "b3", "b4"}, {"b5", "b6", "b7"}, {"b8"}}
	src := func(ctx context.Context, cursor string) ([]string, string, error) {
		i := 0
		if cursor != "" {
			fmt.Sscan(cursor, &i)
		}
		next := ""
		if i+1 < len(pages) {
			next = fmt.Sprint(i + 1)
		}
		return pages[i], next, nil
	}
	marksFor := func(ctx context.Context, pids []string) (map[string]service.ItemMark, error) {
		out := map[string]service.ItemMark{}
		for _, pid := range pids {
			out[pid] = service.ItemMark{PlayCount: plays[pid]}
		}
		return out, nil
	}
	got, err := frequentAlbums(context.Background(), idx, src, marksFor)
	if err != nil {
		t.Fatal(err)
	}
	if names := albumNames(got); names != "B, A, Fixture" {
		t.Fatalf("frequent = [%s], want [B, A, Fixture]: B's 22 plays over A's 14", names)
	}
}

// A folder's newest row reads the folder's own recently added tracks, so a
// small folder whose additions sit far behind the rest of the catalog's
// still lists its albums; and the held newest fold keeps no track list.
func TestFolderNewestReadsTheFolder(t *testing.T) {
	base := buildIndex([]track{
		{PID: "v1", AlbumArtist: "X", Album: "Vinyl Days", LibraryPID: "lb-v"},
		{PID: "o1", AlbumArtist: "Y", Album: "Elsewhere", LibraryPID: "lb-o"},
	}, nil)
	cut := base.cut("lb-v")
	h := &Handler{pages: func(uc *service.UserCtx, list, folder string) pageSource {
		return func(ctx context.Context, cursor string) ([]string, string, error) {
			if folder == "lb-v" {
				return []string{"v1"}, "", nil
			}
			// The whole catalog's list: the folder's track never comes up.
			return []string{"o1"}, "more", nil
		}
	}}
	r := httptest.NewRequest("GET", "/rest/getAlbumList2?type=newest", nil)
	if err := r.ParseForm(); err != nil {
		t.Fatal(err)
	}
	albums, _, ref, err := h.albumList(context.Background(), r, &service.UserCtx{}, cut)
	if ref != nil || err != nil || albumNames(albums) != "Vinyl Days" {
		t.Fatalf("the folder's newest = [%s] (%v %v), want its own album", albumNames(albums), ref, err)
	}
	if len(cut.newest.pids) != 0 {
		t.Fatalf("the held newest fold kept %d pids it never reads", len(cut.newest.pids))
	}
}

// newest lists every album: past the recently added tracks it read, the
// albums it has not met follow in the index's order, so a crawl reaches
// the whole library whether the list ends early or runs past the pages a
// fold reads.
func TestNewestCrawlReachesEveryAlbum(t *testing.T) {
	rows := []track{
		{PID: "tA", AlbumArtist: "X", Album: "A"}, {PID: "tB", AlbumArtist: "X", Album: "B"},
		{PID: "tC", AlbumArtist: "X", Album: "C"}, {PID: "tD", AlbumArtist: "X", Album: "D"},
	}
	for name, src := range map[string]pageSource{
		"a list that ends": func(ctx context.Context, cursor string) ([]string, string, error) {
			return []string{"tC"}, "", nil
		},
		"a list past the cap": func(ctx context.Context, cursor string) ([]string, string, error) {
			if cursor == "" {
				return []string{"tC"}, "more", nil
			}
			return []string{"foreign"}, "more", nil
		},
	} {
		idx := buildIndex(append([]track(nil), rows...), nil)
		h := &Handler{pages: func(uc *service.UserCtx, list, folder string) pageSource { return src }}
		var got []string
		for _, query := range []string{"type=newest&size=2", "type=newest&size=2&offset=2", "type=newest&size=2&offset=4"} {
			r := httptest.NewRequest("GET", "/rest/getAlbumList2?"+query, nil)
			if err := r.ParseForm(); err != nil {
				t.Fatal(err)
			}
			albums, _, ref, err := h.albumList(context.Background(), r, &service.UserCtx{}, idx)
			if ref != nil || err != nil {
				t.Fatalf("%s: %s refused: %+v %v", name, query, ref, err)
			}
			got = append(got, albumNames(albums))
		}
		if strings.Join(got, " | ") != "C, A | B, D | " {
			t.Errorf("%s: the crawl = [%s], want [C, A | B, D | ]", name, strings.Join(got, " | "))
		}
	}
}

// alphabeticalByArtist is ordered once per index, not once per request.
func TestAlbumsByArtistAreOrderedOncePerIndex(t *testing.T) {
	idx := albumListIndex()
	q, _ := listQueryFor(t, "type=alphabeticalByArtist")
	first, _ := indexOrder(idx, q)
	second, _ := indexOrder(idx, q)
	if len(first) == 0 || &first[0] != &second[0] {
		t.Fatal("a second request ordered the albums again")
	}
}

// The frequent fold is read once for a caller at one plays position: the
// pages after the first read nothing, and another caller reads their own.
func TestFrequentFoldIsReadOncePerCallerAndPlays(t *testing.T) {
	h, uc := serviceHandler(t)
	settle(t, h)
	idx := buildIndex([]track{
		{PID: "tr-a1", AlbumArtist: "X", Album: "A"}, {PID: "tr-b1", AlbumArtist: "X", Album: "B"},
		{PID: "tr-c1", AlbumArtist: "X", Album: "C"},
	}, nil)
	reads := 0
	h.pages = func(uc *service.UserCtx, list, folder string) pageSource {
		return func(ctx context.Context, cursor string) ([]string, string, error) {
			reads++
			if cursor == "" {
				return []string{"tr-a1", "tr-b1"}, "p2", nil
			}
			return []string{"tr-c1"}, "", nil
		}
	}
	list := func(who *service.UserCtx, query string) {
		t.Helper()
		r := httptest.NewRequest("GET", "/rest/getAlbumList2?"+query, nil)
		if err := r.ParseForm(); err != nil {
			t.Fatal(err)
		}
		if _, _, ref, err := h.albumList(context.Background(), r, who, idx); ref != nil || err != nil {
			t.Fatalf("%s refused: %+v %v", query, ref, err)
		}
	}
	list(uc, "type=frequent&size=1")
	if reads != 2 {
		t.Fatalf("the first page read %d pages of the list, want its 2", reads)
	}
	list(uc, "type=frequent&size=1&offset=1")
	list(uc, "type=frequent&size=1&offset=2")
	if reads != 2 {
		t.Fatalf("a crawl's later pages read %d more pages of the list, want none", reads-2)
	}
	other := &service.UserCtx{ID: "someone-else", CatalogPID: uc.CatalogPID, AllLibraries: true}
	list(other, "type=frequent&size=1")
	if reads != 4 {
		t.Fatalf("another caller read %d pages, want their own 2", reads-2)
	}
}

// A caller's played folds outlast a play anywhere for up to a minute, so
// a listener checkpointing elsewhere does not drop them between the pages
// of a crawl; past the minute a moved position reads them afresh, and a
// position that has not moved keeps them.
func TestPlayedFoldsOutlastAPlayForAMinute(t *testing.T) {
	idx := buildIndex([]track{{PID: "t1", AlbumArtist: "X", Album: "A"}}, nil)
	read := time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)
	first := idx.playedFor("u", 1, read)
	if again := idx.playedFor("u", 2, read.Add(59*time.Second)); again != first {
		t.Fatal("a play anywhere dropped the caller's played folds within the minute")
	}
	if again := idx.playedFor("u", 1, read.Add(time.Hour)); again != first {
		t.Fatal("the folds were read again though the plays position stood")
	}
	fresh := idx.playedFor("u", 2, read.Add(61*time.Second))
	if fresh == first || fresh.plays != 2 {
		t.Fatal("the folds outlived a play by more than a minute")
	}
	if other := idx.playedFor("v", 2, read); other == fresh {
		t.Fatal("another caller read the first one's folds")
	}
}
