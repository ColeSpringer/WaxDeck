package service

import (
	"context"
	"encoding/base64"
	"fmt"
	"html"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/read"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

func TestDayNumberConsecutiveAcrossDST(t *testing.T) {
	t.Parallel()
	denver, err := time.LoadLocation("America/Denver")
	if err != nil {
		t.Fatal(err)
	}
	// Spring forward (2026-03-08) and fall back (2026-11-01): the civil
	// dates around each transition must still differ by exactly one,
	// even though the days are 23 and 25 hours long.
	for _, span := range []struct {
		year  int
		month time.Month
		days  []int
	}{
		{2026, time.March, []int{7, 8, 9}},
		{2026, time.October, []int{31}},
	} {
		prev := dayNumber(time.Date(span.year, span.month, span.days[0], 12, 0, 0, 0, denver))
		for _, d := range span.days[1:] {
			cur := dayNumber(time.Date(span.year, span.month, d, 12, 0, 0, 0, denver))
			if cur != prev+1 {
				t.Fatalf("%d %s %d: dayNumber = %d, want %d", span.year, span.month, d, cur, prev+1)
			}
			prev = cur
		}
	}
	oct31 := dayNumber(time.Date(2026, time.October, 31, 12, 0, 0, 0, denver))
	nov1 := dayNumber(time.Date(2026, time.November, 1, 12, 0, 0, 0, denver))
	nov2 := dayNumber(time.Date(2026, time.November, 2, 12, 0, 0, 0, denver))
	if nov1 != oct31+1 || nov2 != nov1+1 {
		t.Fatalf("fall-back run = %d, %d, %d, want consecutive", oct31, nov1, nov2)
	}
}

func TestDayNumberYearBoundaryAndAnchor(t *testing.T) {
	t.Parallel()
	dec31 := dayNumber(time.Date(2025, time.December, 31, 23, 59, 0, 0, time.UTC))
	jan1 := dayNumber(time.Date(2026, time.January, 1, 0, 1, 0, 0, time.UTC))
	if jan1 != dec31+1 {
		t.Fatalf("year boundary: %d then %d, want consecutive", dec31, jan1)
	}
	if n := dayNumber(time.Date(1970, time.January, 1, 0, 0, 0, 0, time.UTC)); n != 0 {
		t.Fatalf("epoch dayNumber = %d, want 0", n)
	}
	// Only the civil date matters, never the zone offset.
	tokyo, err := time.LoadLocation("Asia/Tokyo")
	if err != nil {
		t.Fatal(err)
	}
	utc := dayNumber(time.Date(2026, time.July, 21, 1, 0, 0, 0, time.UTC))
	jst := dayNumber(time.Date(2026, time.July, 21, 23, 0, 0, 0, tokyo))
	if utc != jst {
		t.Fatalf("same civil date, different zones: %d vs %d", utc, jst)
	}
}

func TestBucketStart(t *testing.T) {
	t.Parallel()
	loc, err := time.LoadLocation("America/Denver")
	if err != nil {
		t.Fatal(err)
	}
	at := func(y int, m time.Month, d int) time.Time {
		return time.Date(y, m, d, 14, 30, 45, 0, loc)
	}
	midnight := func(y int, m time.Month, d int) time.Time {
		return time.Date(y, m, d, 0, 0, 0, 0, loc)
	}
	cases := []struct {
		name   string
		in     time.Time
		bucket string
		want   time.Time
	}{
		{"day floors to midnight", at(2026, time.July, 15), "day", midnight(2026, time.July, 15)},
		{"week from Wednesday", at(2026, time.July, 15), "week", midnight(2026, time.July, 13)},
		{"week from Monday is itself", at(2026, time.July, 13), "week", midnight(2026, time.July, 13)},
		{"week from Sunday reaches back", at(2026, time.July, 19), "week", midnight(2026, time.July, 13)},
		{"week crosses a month boundary", at(2026, time.August, 1), "week", midnight(2026, time.July, 27)},
		{"month floors to the first", at(2026, time.July, 15), "month", midnight(2026, time.July, 1)},
	}
	for _, c := range cases {
		if got := bucketStart(c.in, c.bucket); !got.Equal(c.want) {
			t.Errorf("%s: bucketStart = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestLongestRun(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		days []int
		want int
	}{
		{"empty", nil, 0},
		{"single day", []int{5}, 1},
		{"two runs", []int{1, 2, 3, 7, 8}, 3},
		{"longer run later", []int{1, 2, 10, 11, 12, 13}, 4},
		{"no consecutive days", []int{2, 4, 6}, 1},
	}
	for _, c := range cases {
		days := map[int]bool{}
		for _, d := range c.days {
			days[d] = true
		}
		if got := longestRun(days); got != c.want {
			t.Errorf("%s: longestRun = %d, want %d", c.name, got, c.want)
		}
	}
}

func TestLogCursorRoundTrip(t *testing.T) {
	t.Parallel()
	wantNS, wantID := int64(1753000000000000000), int64(42)
	ns, id, err := decodeLogCursor(encodeLogCursor(wantNS, wantID))
	if err != nil || ns != wantNS || id != wantID {
		t.Fatalf("round trip = (%d, %d, %v), want (%d, %d, nil)", ns, id, err, wantNS, wantID)
	}
	// The empty cursor is the first page, never an error.
	if ns, id, err := decodeLogCursor(""); err != nil || ns != 0 || id != 0 {
		t.Fatalf("empty cursor = (%d, %d, %v), want (0, 0, nil)", ns, id, err)
	}
}

func TestLogCursorMalformed(t *testing.T) {
	t.Parallel()
	enc := func(raw string) string {
		return base64.RawURLEncoding.EncodeToString([]byte(raw))
	}
	for _, bad := range []string{
		"%%%",              // not base64url
		enc("nocolon"),     // no separator
		enc("abc:42"),      // non-numeric ns
		enc("42:abc"),      // non-numeric id
		enc(":"),           // both parts empty
		enc("1:2:3") + "!", // trailing junk breaks decoding
	} {
		if _, _, err := decodeLogCursor(bad); err == nil {
			t.Errorf("cursor %q decoded, want error", bad)
		}
	}
}

// statsFixture is a catalog holding every medium, with listening in each.
type statsFixture struct {
	ctx     context.Context
	svc     *Library
	uc      *UserCtx
	views   map[string]*model.ItemView // by title
	show    string                     // the show's API pid
	station string                     // the station's API pid
	gone    string                     // bare pid of a track that left the catalog
	now     time.Time                  // when "today's" listens started
}

func (f *statsFixture) view(t *testing.T, title string) *model.ItemView {
	t.Helper()
	v := f.views[title]
	if v == nil {
		t.Fatalf("no fixture item titled %q", title)
	}
	return v
}

func newStatsFixture(t *testing.T) *statsFixture {
	t.Helper()
	libDir := t.TempDir()
	for _, s := range []struct{ dir, name, title, artist, album, genre string }{
		// One artist under two spellings of one match key.
		{"one", "b1", "Halo", "Beyoncé", "I Am", "Pop"},
		{"two", "b2", "Formation", "Beyonce", "Lemonade", "Pop"},
		// One album title by one artist, kept apart by its folders.
		{"Blue", "j1", "River", "Joni", "Blue", "Folk"},
		{"Blue Again", "j2", "Carey", "Joni", "Blue", "Folk"},
	} {
		if _, err := fixtures.Generate(filepath.Join(libDir, s.dir), fixtures.Spec{
			Name: s.name, Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": s.title, "ARTIST": s.artist, "ALBUMARTIST": s.artist,
				"ALBUM": s.album, "GENRE": s.genre, "TRACKNUMBER": "1"},
		}); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := fixtures.GenerateBook(libDir); err != nil {
		t.Fatal(err)
	}
	if _, err := fixtures.GenerateChapteredBook(libDir); err != nil {
		t.Fatal(err)
	}
	if _, err := fixtures.GenerateM4B(filepath.Join(libDir, "Bea Writer", "Other Book"), fixtures.Spec{
		Name: "Other Book", Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Other Book", "ALBUM": "Other Book", "ARTIST": "Bea Writer", "ALBUMARTIST": "Bea Writer"},
	}); err != nil {
		t.Fatal(err)
	}
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".mp3") {
			w.Header().Set("Content-Type", "audio/mpeg")
			_, _ = w.Write([]byte("ID3\x04\x00\x00\x00\x00\x00\x00"))
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		item := func(title, guid string, day int) string {
			return fmt.Sprintf(`<item><title>%s</title><guid>%s</guid><pubDate>%s</pubDate><enclosure url="http://%s/%s.mp3" type="audio/mpeg" length="10"/></item>`,
				html.EscapeString(title), guid, time.Date(2026, 6, day, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z), r.Host, guid)
		}
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Stats Cast</title>%s%s</channel></rss>`,
			item("Ep One", "one", 1), item("Ep Two", "two", 2))
	}))
	t.Cleanup(host.Close)
	dir := t.TempDir()
	ctx, svc, admin, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.Roots = []Root{{Name: "lib", Path: libDir}}
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	sub, _, err := svc.Podcasts.Subscribe(ctx, admin, SubscribeRequest{URL: host.URL + "/feed.xml"})
	if err != nil {
		t.Fatal(err)
	}
	st, err := svc.Radio.CreateRadioStation(ctx, admin, RadioStationEdit{Name: "Groove Salad", StreamURL: "https://ice.example.net/groove"})
	if err != nil {
		t.Fatal(err)
	}
	f := &statsFixture{ctx: ctx, svc: svc, uc: admin, views: map[string]*model.ItemView{},
		show: sub.Show.PID, station: st.PID, gone: string(model.NewPID())}
	var pids []model.PID
	for _, mt := range []string{"music", "audiobook"} {
		page, err := svc.Reads.Items(ctx, admin, ItemFilter{MediaType: mt}, "", 50)
		if err != nil {
			t.Fatal(err)
		}
		for _, it := range page.Items {
			_, bare, _ := parseAPIPID(it.PID)
			pids = append(pids, bare)
		}
	}
	eps, _, err := svc.Podcasts.Episodes(ctx, admin, sub.Show.PID, "", 10)
	if err != nil || len(eps) != 2 {
		t.Fatalf("episodes = %+v (%v), want two", eps, err)
	}
	for _, ep := range eps {
		_, bare, _ := parseAPIPID(ep.PID)
		pids = append(pids, bare)
	}
	views, err := svc.lib.GetMany(ctx, pids)
	if err != nil {
		t.Fatal(err)
	}
	for _, v := range views {
		f.views[v.Title] = v
	}

	// Today's listens start now, which the reads' window (ending an hour
	// ahead) includes, so they are today at any start time.
	now := time.Now().UTC()
	f.now = now
	day := 24 * time.Hour
	var sessions []wdb.ListenSession
	listen := func(bare, mt string, at time.Time, minutes int) {
		sessions = append(sessions, wdb.ListenSession{UserID: admin.ID, SessionID: fmt.Sprintf("s-%d", len(sessions)),
			ItemPID: bare, MediaType: mt, StartedAt: at, MsPlayed: int64(minutes) * time.Minute.Milliseconds()})
	}
	music := map[string]int{"Halo": 5, "Formation": 3, "River": 4, "Carey": 2}
	for title, m := range music {
		listen(string(f.view(t, title).PID), "music", now, m)
	}
	listen(f.gone, "music", now, 1)
	listen(string(f.view(t, "Ep One").PID), "podcast", now.Add(-5*day), 6)
	listen(string(f.view(t, "Ep Two").PID), "podcast", now.Add(-5*day), 2)
	listen(string(f.view(t, "The Fixture Book").PID), "audiobook", now, 7)
	listen(string(f.view(t, "The Chaptered Fixture").PID), "audiobook", now, 1)
	listen(string(f.view(t, "Other Book").PID), "audiobook", now, 2)
	_, bareStation, _ := strings.Cut(st.PID, "-")
	listen(bareStation, "radio", now.Add(-day), 8)
	listen(bareStation, "radio", now.Add(-2*day), 1)
	if _, err := svc.db.InsertListens(ctx, sessions); err != nil {
		t.Fatal(err)
	}
	return f
}

func entityName(t *testing.T, f *statsFixture, kind read.EntityKind, pid model.PID) string {
	t.Helper()
	infos, err := f.svc.lib.EntityByPIDs(f.ctx, kind, []model.PID{pid})
	if err != nil || infos[pid] == nil {
		t.Fatalf("entity %s %s: %v", kind, pid, err)
	}
	return infos[pid].Name
}

// Every read of the stats surface counts one medium when asked to, and
// each top kind groups its own medium by the entity its members name.
func TestStatsPerMedium(t *testing.T) {
	t.Parallel()
	f := newStatsFixture(t)
	ctx, svc, uc := f.ctx, f.svc, f.uc
	minute := time.Minute.Milliseconds()

	t.Run("listening totals", func(t *testing.T) {
		for _, c := range []struct {
			media    string
			ms       int64
			sessions int
		}{
			{"", 42 * minute, 12}, {"music", 15 * minute, 5}, {"podcast", 8 * minute, 2},
			{"audiobook", 10 * minute, 3}, {"radio", 9 * minute, 2},
		} {
			got, err := svc.Reads.ListeningStats(ctx, uc, "30d", "day", c.media)
			if err != nil {
				t.Fatal(err)
			}
			var bucketMs int64
			bucketSessions := 0
			for _, b := range got.Buckets {
				bucketMs += b.Ms
				bucketSessions += b.Sessions
			}
			if got.TotalMs != c.ms || got.Sessions != c.sessions || bucketMs != c.ms || bucketSessions != c.sessions {
				t.Errorf("%q: total %d over %d, buckets %d over %d; want %d over %d",
					c.media, got.TotalMs, got.Sessions, bucketMs, bucketSessions, c.ms, c.sessions)
			}
			if c.media == "" {
				if len(got.ByMediaType) != 4 {
					t.Errorf("every medium: byMediaType = %+v, want four", got.ByMediaType)
				}
				continue
			}
			if len(got.ByMediaType) != 1 || got.ByMediaType[0] != (MediaTypeListening{MediaType: c.media, Ms: c.ms, Sessions: c.sessions}) {
				t.Errorf("%q: byMediaType = %+v, want that medium alone", c.media, got.ByMediaType)
			}
		}
		if _, err := svc.Reads.ListeningStats(ctx, uc, "30d", "day", "vinyl"); KindOf(err) != KindInvalid {
			t.Errorf("unknown medium: err = %v, want invalid-request", err)
		}
	})

	t.Run("heatmap and streaks", func(t *testing.T) {
		today := f.now
		for _, c := range []struct {
			media   string
			current int
		}{
			{"", 3}, {"music", 1}, {"radio", 2}, {"podcast", 0}, {"audiobook", 1},
		} {
			got, err := svc.Reads.ListeningHeatmap(ctx, uc, today.Year(), c.media)
			if err != nil {
				t.Fatal(err)
			}
			if got.CurrentStreakDays != c.current {
				t.Errorf("%q: current streak = %d, want %d", c.media, got.CurrentStreakDays, c.current)
			}
		}
		got, err := svc.Reads.ListeningHeatmap(ctx, uc, today.Year(), "music")
		if err != nil {
			t.Fatal(err)
		}
		if len(got.Days) != 1 || got.Days[0].Date.Day() != today.Day() || got.Days[0].Sessions != 5 || got.LongestStreakDays != 1 {
			t.Errorf("music heatmap = %+v, want today's five sessions alone", got)
		}
		if _, err := svc.Reads.ListeningHeatmap(ctx, uc, today.Year(), "vinyl"); KindOf(err) != KindInvalid {
			t.Errorf("unknown medium: err = %v, want invalid-request", err)
		}
	})

	top := func(t *testing.T, kind string) []TopEntry {
		t.Helper()
		list, err := svc.Reads.TopListFor(ctx, uc, kind, "30d", 10)
		if err != nil {
			t.Fatalf("%s: %v", kind, err)
		}
		return list.Entries
	}
	drawn := func(t *testing.T, e TopEntry, pid, art string, ms int64, plays int) {
		t.Helper()
		if e.PID != pid || e.ArtPID != art || e.Ms != ms || e.Plays != plays {
			t.Errorf("entry %+v, want pid %s drawing %s, %dms over %d", e, pid, art, ms, plays)
		}
	}
	own := func(t *testing.T, e TopEntry, pid string, ms int64, plays int) {
		t.Helper()
		drawn(t, e, pid, pid, ms, plays)
	}
	portrait := func(t *testing.T, artist model.PID) {
		t.Helper()
		if _, err := svc.Editor.SetEntityArtwork(ctx, uc, "artist", apiPID(PrefixArtist, artist), "front", coverPNG(t, 40), false); err != nil {
			t.Fatal(err)
		}
	}

	t.Run("artists", func(t *testing.T) {
		halo, formation, river := f.view(t, "Halo"), f.view(t, "Formation"), f.view(t, "River")
		if halo.ArtistPID == "" || halo.ArtistPID != formation.ArtistPID {
			t.Fatalf("the two spellings are not one artist: %q %q", halo.ArtistPID, formation.ArtistPID)
		}
		got := top(t, "artists")
		if len(got) != 2 {
			t.Fatalf("artists = %+v, want two", got)
		}
		// With no picture of its own, an artist draws its most-listened
		// track's.
		drawn(t, got[0], apiPID(PrefixArtist, halo.ArtistPID), itemAPIPID(halo), 8*minute, 2)
		if want := entityName(t, f, read.EntityArtist, halo.ArtistPID); got[0].Name != want {
			t.Errorf("artist name = %q, want the entity's %q", got[0].Name, want)
		}
		drawn(t, got[1], apiPID(PrefixArtist, river.ArtistPID), itemAPIPID(river), 6*minute, 2)
		portrait(t, river.ArtistPID)
		got = top(t, "artists")
		if len(got) != 2 {
			t.Fatalf("artists = %+v, want two", got)
		}
		drawn(t, got[0], apiPID(PrefixArtist, halo.ArtistPID), itemAPIPID(halo), 8*minute, 2)
		own(t, got[1], apiPID(PrefixArtist, river.ArtistPID), 6*minute, 2)
	})

	t.Run("albums", func(t *testing.T) {
		river, carey := f.view(t, "River"), f.view(t, "Carey")
		if river.AlbumPID == "" || river.AlbumPID == carey.AlbumPID {
			t.Fatalf("the two Blues are one album: %q %q", river.AlbumPID, carey.AlbumPID)
		}
		got := top(t, "albums")
		if len(got) != 4 {
			t.Fatalf("albums = %+v, want four", got)
		}
		own(t, got[0], apiPID(PrefixAlbum, f.view(t, "Halo").AlbumPID), 5*minute, 1)
		own(t, got[1], apiPID(PrefixAlbum, river.AlbumPID), 4*minute, 1)
		own(t, got[3], apiPID(PrefixAlbum, carey.AlbumPID), 2*minute, 1)
		if got[1].Name != "Blue" || got[3].Name != "Blue" {
			t.Errorf("the two Blues are named %q and %q", got[1].Name, got[3].Name)
		}
	})

	t.Run("tracks", func(t *testing.T) {
		got := top(t, "tracks")
		if len(got) != 5 {
			t.Fatalf("tracks = %+v, want five", got)
		}
		own(t, got[0], itemAPIPID(f.view(t, "Halo")), 5*minute, 1)
		if got[0].Name != "Halo" {
			t.Errorf("track name = %q", got[0].Name)
		}
		// The track that left keeps its time under its pid, unnamed and
		// with no picture.
		if g := got[4]; g.PID != apiPID(PrefixTrack, model.PID(f.gone)) || g.Name != "" || g.ArtPID != "" || g.Ms != minute {
			t.Errorf("gone track = %+v", g)
		}
	})

	t.Run("genres", func(t *testing.T) {
		got := top(t, "genres")
		if len(got) != 2 || got[0].Name != "Pop" || got[0].Ms != 8*minute || got[1].Name != "Folk" {
			t.Fatalf("genres = %+v", got)
		}
		for _, e := range got {
			if e.PID != "" || e.ArtPID != "" {
				t.Errorf("genre %+v carries a pid or art", e)
			}
		}
	})

	t.Run("shows and episodes", func(t *testing.T) {
		shows := top(t, "shows")
		if len(shows) != 1 || shows[0].Name != "Stats Cast" {
			t.Fatalf("shows = %+v", shows)
		}
		// With no picture of its own, a show draws its most-listened
		// episode's; with one, its own.
		drawn(t, shows[0], f.show, itemAPIPID(f.view(t, "Ep One")), 8*minute, 2)
		if _, err := svc.Editor.SetEntityArtwork(ctx, uc, "podcast", f.show, "front", coverPNG(t, 40), false); err != nil {
			t.Fatal(err)
		}
		own(t, top(t, "shows")[0], f.show, 8*minute, 2)
		eps := top(t, "episodes")
		if len(eps) != 2 || eps[0].Name != "Ep One" {
			t.Fatalf("episodes = %+v", eps)
		}
		own(t, eps[0], itemAPIPID(f.view(t, "Ep One")), 6*minute, 1)
		if !strings.HasPrefix(eps[0].PID, PrefixEpisode+"-") {
			t.Errorf("episode pid = %q", eps[0].PID)
		}
	})

	t.Run("books and authors", func(t *testing.T) {
		books := top(t, "books")
		if len(books) != 3 || books[0].Name != "The Fixture Book" {
			t.Fatalf("books = %+v", books)
		}
		own(t, books[0], itemAPIPID(f.view(t, "The Fixture Book")), 7*minute, 1)
		if !strings.HasPrefix(books[0].PID, PrefixBook+"-") {
			t.Errorf("book pid = %q", books[0].PID)
		}
		ada, other := f.view(t, "The Fixture Book"), f.view(t, "Other Book")
		authors := top(t, "authors")
		if len(authors) != 2 || authors[0].Name != "Ada Author" || authors[1].Name != "Bea Writer" {
			t.Fatalf("authors = %+v", authors)
		}
		drawn(t, authors[0], apiPID(PrefixArtist, ada.ArtistPID), itemAPIPID(ada), 8*minute, 2)
		drawn(t, authors[1], apiPID(PrefixArtist, other.ArtistPID), itemAPIPID(other), 2*minute, 1)
		portrait(t, other.ArtistPID)
		authors = top(t, "authors")
		if len(authors) != 2 {
			t.Fatalf("authors = %+v", authors)
		}
		drawn(t, authors[0], apiPID(PrefixArtist, ada.ArtistPID), itemAPIPID(ada), 8*minute, 2)
		own(t, authors[1], apiPID(PrefixArtist, other.ArtistPID), 2*minute, 1)
	})

	t.Run("stations", func(t *testing.T) {
		got := top(t, "stations")
		if len(got) != 1 || got[0].Name != "Groove Salad" {
			t.Fatalf("stations = %+v", got)
		}
		own(t, got[0], f.station, 9*minute, 2)
		if _, err := svc.Reads.TopListFor(ctx, uc, "vinyl", "30d", 10); KindOf(err) != KindInvalid {
			t.Errorf("unknown kind: err = %v, want invalid-request", err)
		}
	})

	t.Run("recap", func(t *testing.T) {
		portrait(t, f.view(t, "River").ArtistPID)
		portrait(t, f.view(t, "Other Book").ArtistPID)
		recap, err := svc.Reads.UserYearInReview(ctx, uc, f.now.Year())
		if err != nil {
			t.Fatal(err)
		}
		if len(recap.TopBooks) != 3 || recap.TopBooks[0].PID != itemAPIPID(f.view(t, "The Fixture Book")) {
			t.Errorf("recap books = %+v", recap.TopBooks)
		}
		if len(recap.TopAuthors) != 2 || recap.TopAuthors[0].PID != apiPID(PrefixArtist, f.view(t, "The Fixture Book").ArtistPID) {
			t.Errorf("recap authors = %+v", recap.TopAuthors)
		}
		if len(recap.TopArtists) != 2 || recap.TopArtists[0].PID != apiPID(PrefixArtist, f.view(t, "Halo").ArtistPID) {
			t.Errorf("recap artists = %+v", recap.TopArtists)
		}
		// The recaps draw an artist or author the way the top lists do.
		halo, ada := f.view(t, "Halo"), f.view(t, "The Fixture Book")
		if len(recap.TopArtists) == 2 && (recap.TopArtists[0].ArtPID != itemAPIPID(halo) ||
			recap.TopArtists[1].ArtPID != apiPID(PrefixArtist, f.view(t, "River").ArtistPID)) {
			t.Errorf("recap artists draw %+v", recap.TopArtists)
		}
		if len(recap.TopAuthors) == 2 && (recap.TopAuthors[0].ArtPID != itemAPIPID(ada) ||
			recap.TopAuthors[1].ArtPID != apiPID(PrefixArtist, f.view(t, "Other Book").ArtistPID)) {
			t.Errorf("recap authors draw %+v", recap.TopAuthors)
		}
		server, err := svc.Reads.ServerWideYearInReview(ctx, uc, f.now.Year())
		if err != nil {
			t.Fatal(err)
		}
		if len(server.TopArtists) != 2 || server.TopArtists[0].ArtPID != itemAPIPID(halo) {
			t.Errorf("server-wide recap artists draw %+v", server.TopArtists)
		}
	})

	// Merging an artist away folds its listening into the survivor, named
	// by the survivor. Last, since it changes the catalog.
	t.Run("merged artist", func(t *testing.T) {
		halo, river := f.view(t, "Halo"), f.view(t, "River")
		portrait(t, river.ArtistPID)
		if _, err := svc.lib.Merge(ctx, model.MergeArtist, river.ArtistPID, halo.ArtistPID); err != nil {
			t.Fatal(err)
		}
		got := top(t, "artists")
		if len(got) != 1 {
			t.Fatalf("artists after merge = %+v, want one", got)
		}
		own(t, got[0], apiPID(PrefixArtist, river.ArtistPID), 14*minute, 4)
		if got[0].Name != entityName(t, f, read.EntityArtist, river.ArtistPID) {
			t.Errorf("merged artist named %q", got[0].Name)
		}
	})
}

// The fold over item views, for the members a scan cannot produce: two
// artists showing one name, members with no entity, and members naming
// nothing at all.
func TestFoldTopGroups(t *testing.T) {
	t.Parallel()
	a, b := model.NewPID(), model.NewPID()
	views := map[string]*model.ItemView{}
	add := func(v model.ItemView) string {
		v.PID = model.NewPID()
		if v.Kind == "" {
			v.Kind = model.KindTrack
		}
		views[string(v.PID)] = &v
		return string(v.PID)
	}
	totals := map[string]*itemTotals{}
	listen := func(pid string, ms int64) { totals[pid] = &itemTotals{pid: pid, ms: ms, plays: 1} }
	listen(add(model.ItemView{Title: "one", Artist: "Nirvana", ArtistPID: a, Genre: "Grunge"}), 50)
	listen(add(model.ItemView{Title: "two", Artist: "Nirvana", ArtistPID: b, Genre: "grunge"}), 40)
	loose := add(model.ItemView{Title: "three", Artist: "Loose"})
	listen(loose, 30)
	listen(add(model.ItemView{Title: "four", Artist: "loose"}), 20)
	listen(add(model.ItemView{Title: "five"}), 10)
	listen(string(model.NewPID()), 5) // left the catalog

	byKey := func(kind string) map[string]TopEntry {
		out := map[string]TopEntry{}
		for _, g := range foldTopGroups(totals, views, kind) {
			out[g.entry.PID+"|"+g.entry.Name] = g.entry
		}
		return out
	}
	artists := byKey("artists")
	if len(artists) != 3 {
		t.Fatalf("artists = %+v, want two Nirvanas and one Loose", artists)
	}
	if e := artists[apiPID(PrefixArtist, a)+"|Nirvana"]; e.Ms != 50 || e.ArtPID != apiPID(PrefixArtist, a) {
		t.Errorf("first Nirvana = %+v", e)
	}
	if e := artists[apiPID(PrefixArtist, b)+"|Nirvana"]; e.Ms != 40 {
		t.Errorf("second Nirvana = %+v", e)
	}
	// No entity: a name group with no pid, drawing its top item's art.
	if e := artists["|Loose"]; e.Ms != 50 || e.Plays != 2 || e.ArtPID != apiPID(PrefixTrack, model.PID(loose)) {
		t.Errorf("name group = %+v", e)
	}
	genres := byKey("genres")
	if e := genres["|Grunge"]; len(genres) != 1 || e.Ms != 90 || e.ArtPID != "" {
		t.Errorf("genres = %+v", genres)
	}
	if len(byKey("tracks")) != 6 {
		t.Errorf("tracks = %+v, want every item and the one that left", byKey("tracks"))
	}

	// Albums and shows with no entity fall back to name groups too: an
	// album on its album artist (track artist when none) and title, a show
	// on its title. A show entity with no title names nothing.
	// Entries by art pid: a name group's is its top member's, so two
	// groups showing one name stay two keys.
	fold := func(kind string, vs ...model.ItemView) (map[string]TopEntry, []string) {
		views, totals := map[string]*model.ItemView{}, map[string]*itemTotals{}
		var pids []string
		for i, v := range vs {
			v.PID = model.NewPID()
			pid := string(v.PID)
			views[pid], totals[pid] = &v, &itemTotals{pid: pid, ms: int64(100 - 10*i), plays: 1}
			pids = append(pids, pid)
		}
		out := map[string]TopEntry{}
		for _, g := range foldTopGroups(totals, views, kind) {
			out[g.entry.ArtPID] = g.entry
		}
		return out, pids
	}
	albums, apids := fold("albums",
		model.ItemView{Kind: model.KindTrack, Album: "Blue", AlbumArtist: "Joni"},
		model.ItemView{Kind: model.KindTrack, Album: "blue", Artist: "joni"},
		model.ItemView{Kind: model.KindTrack, Album: "Blue", AlbumArtist: "Other"},
		model.ItemView{Kind: model.KindTrack, AlbumArtist: "Joni"})
	joni, other := albums[apiPID(PrefixTrack, model.PID(apids[0]))], albums[apiPID(PrefixTrack, model.PID(apids[2]))]
	if len(albums) != 2 || joni.Name != "Blue" || joni.PID != "" || joni.Ms != 190 || joni.Plays != 2 ||
		other.Name != "Blue" || other.Ms != 80 {
		t.Errorf("album name groups = %+v, want Joni's Blue (two members) and Other's", albums)
	}
	show := model.NewPID()
	shows, spids := fold("shows",
		model.ItemView{Kind: model.KindEpisode, Artist: "Loose Cast"},
		model.ItemView{Kind: model.KindEpisode, Artist: "loose cast"},
		model.ItemView{Kind: model.KindEpisode, PodcastPID: show})
	if e := shows[apiPID(PrefixEpisode, model.PID(spids[0]))]; len(shows) != 1 || e.Name != "Loose Cast" || e.PID != "" || e.Ms != 190 {
		t.Errorf("show name groups = %+v, want Loose Cast alone, the untitled show counting toward nothing", shows)
	}
}

// A station read that fails is the top list's failure, never a list of
// stations that all look deleted.
func TestTopStationsFailWhenTheStationsCannotBeRead(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	if _, err := svc.db.InsertListens(ctx, []wdb.ListenSession{{UserID: admin.ID, SessionID: "r-1",
		ItemPID: string(model.NewPID()), MediaType: "radio", StartedAt: time.Now().Add(-time.Minute), MsPlayed: 60_000}}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.db.Writer().Exec(`DROP TABLE radio_stations`); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.Reads.TopListFor(ctx, admin, "stations", "30d", 10); KindOf(err) != KindInternal {
		t.Fatalf("err = %v, want internal", err)
	}
	// The log keeps its best effort.
	if log, err := svc.Reads.ListenLog(ctx, admin, "", "", 10); err != nil || len(log.Sessions) != 1 {
		t.Fatalf("listen log = %+v (%v), want the session unnamed", log, err)
	}
}

// An entry the caller cannot open now keeps its name and time with no
// pid and no picture, and a fallback picture is only ever something the
// caller can open.
func TestTopEntriesOpenOnlyWhatTheCallerCanOpen(t *testing.T) {
	t.Parallel()
	f := newStatsFixture(t)
	ctx, svc, admin := f.ctx, f.svc, f.uc
	minute := time.Minute.Milliseconds()
	halo, formation, river, carey := f.view(t, "Halo"), f.view(t, "Formation"), f.view(t, "River"), f.view(t, "Carey")
	beyonce, joni := apiPID(PrefixArtist, halo.ArtistPID), apiPID(PrefixArtist, river.ArtistPID)
	her, him := entityName(t, f, read.EntityArtist, halo.ArtistPID), entityName(t, f, read.EntityArtist, river.ArtistPID)
	list := func(t *testing.T, uc *UserCtx, kind string) []TopEntry {
		t.Helper()
		list, err := svc.Reads.TopListFor(ctx, uc, kind, "30d", 10)
		if err != nil {
			t.Fatalf("%s: %v", kind, err)
		}
		return list.Entries
	}
	// By name, for lists whose names are distinct.
	top := func(t *testing.T, uc *UserCtx, kind string) map[string]TopEntry {
		t.Helper()
		out := map[string]TopEntry{}
		for _, e := range list(t, uc, kind) {
			out[e.Name] = e
		}
		return out
	}
	closed := func(t *testing.T, e TopEntry, name string, ms int64) {
		t.Helper()
		if e.Name != name || e.Ms != ms || e.PID != "" || e.ArtPID != "" {
			t.Errorf("entry %+v, want %s's %dms with no pid and no picture", e, name, ms)
		}
	}
	open := func(t *testing.T, e TopEntry, pid, art string) {
		t.Helper()
		if e.PID != pid || e.ArtPID != art {
			t.Errorf("entry %+v, want pid %s drawing %s", e, pid, art)
		}
	}

	t.Run("trash", func(t *testing.T) {
		if _, err := svc.Tools.DeleteItems(ctx, admin, []string{itemAPIPID(halo)}, "trash", false); err != nil {
			t.Fatal(err)
		}
		closed(t, top(t, admin, "tracks")["Halo"], "Halo", 5*minute)
		// The artist still opens, and draws the track it can still open.
		open(t, top(t, admin, "artists")[her], beyonce, itemAPIPID(formation))
		recap, err := svc.Reads.UserYearInReview(ctx, admin, f.now.Year())
		if err != nil {
			t.Fatal(err)
		}
		if len(recap.TopTracks) == 0 || recap.TopTracks[0].Name != "Halo" {
			t.Fatalf("recap tracks = %+v", recap.TopTracks)
		}
		closed(t, recap.TopTracks[0], "Halo", 5*minute)
		server, err := svc.Reads.ServerWideYearInReview(ctx, admin, f.now.Year())
		if err != nil {
			t.Fatal(err)
		}
		if len(server.TopTracks) == 0 || server.TopTracks[0].Name != "Halo" {
			t.Fatalf("server recap tracks = %+v", server.TopTracks)
		}
		closed(t, server.TopTracks[0], "Halo", 5*minute)

		entries, err := svc.Tools.TrashEntries(ctx, admin, false, 50)
		if err != nil || len(entries) != 1 {
			t.Fatalf("trash = %+v (%v), want Halo alone", entries, err)
		}
		if err := svc.Tools.RestoreTrashEntry(ctx, admin, entries[0].ID); err != nil {
			t.Fatal(err)
		}
		open(t, top(t, admin, "tracks")["Halo"], itemAPIPID(halo), itemAPIPID(halo))
		open(t, top(t, admin, "artists")[her], beyonce, itemAPIPID(halo))
	})

	t.Run("content rules", func(t *testing.T) {
		for _, v := range []*model.ItemView{halo, formation, river} {
			if _, err := svc.Editor.SetItemTag(ctx, admin, itemAPIPID(v), "MOOD", []string{"calm"}, MetadataEditParams{}); err != nil {
				t.Fatal(err)
			}
		}
		kid := &UserCtx{ID: admin.ID, CatalogPID: admin.CatalogPID, AllLibraries: true, Explicit: true,
			TagDeny: []TagRule{{Key: "MOOD", Value: "calm"}}}
		tracks := top(t, kid, "tracks")
		closed(t, tracks["Halo"], "Halo", 5*minute)
		closed(t, tracks["River"], "River", 4*minute)
		open(t, tracks["Carey"], itemAPIPID(carey), itemAPIPID(carey))
		// Every track of hers is hidden, so the artist is too; his
		// most-listened is hidden, so he draws the one left.
		artists := top(t, kid, "artists")
		closed(t, artists[her], her, 8*minute)
		open(t, artists[him], joni, itemAPIPID(carey))
		// Four albums, two of them named Blue: River's closed, Carey's open.
		albums := list(t, kid, "albums")
		if len(albums) != 4 {
			t.Fatalf("albums = %+v, want four", albums)
		}
		closed(t, albums[0], "I Am", 5*minute)
		closed(t, albums[1], "Blue", 4*minute)
		closed(t, albums[2], "Lemonade", 3*minute)
		open(t, albums[3], apiPID(PrefixAlbum, carey.AlbumPID), apiPID(PrefixAlbum, carey.AlbumPID))
		recap, err := svc.Reads.UserYearInReview(ctx, kid, f.now.Year())
		if err != nil {
			t.Fatal(err)
		}
		if len(recap.TopArtists) != 2 {
			t.Fatalf("recap artists = %+v", recap.TopArtists)
		}
		closed(t, recap.TopArtists[0], her, 8*minute)
		open(t, recap.TopArtists[1], joni, itemAPIPID(carey))
		server, err := svc.Reads.ServerWideYearInReview(ctx, kid, f.now.Year())
		if err != nil {
			t.Fatal(err)
		}
		if len(server.TopArtists) != 1 {
			t.Fatalf("server recap artists = %+v", server.TopArtists)
		}
		open(t, server.TopArtists[0], joni, itemAPIPID(carey))
		// The admin sees what the rules hide from the other caller.
		open(t, top(t, admin, "artists")[her], beyonce, itemAPIPID(halo))
	})

	t.Run("no podcast library", func(t *testing.T) {
		music := &UserCtx{ID: admin.ID, CatalogPID: admin.CatalogPID, Explicit: true,
			Libraries: map[string]bool{string(halo.LibraryPID): true}}
		closed(t, top(t, music, "shows")["Stats Cast"], "Stats Cast", 8*minute)
		episodes := top(t, music, "episodes")
		closed(t, episodes["Ep One"], "Ep One", 6*minute)
		closed(t, episodes["Ep Two"], "Ep Two", 2*minute)
		book := f.view(t, "The Fixture Book")
		open(t, top(t, music, "books")[book.Title], itemAPIPID(book), itemAPIPID(book))
		recap, err := svc.Reads.UserYearInReview(ctx, music, f.now.Year())
		if err != nil {
			t.Fatal(err)
		}
		if len(recap.TopShows) != 1 {
			t.Fatalf("recap shows = %+v", recap.TopShows)
		}
		closed(t, recap.TopShows[0], "Stats Cast", 8*minute)
	})
}

// openTop reads one top list for a caller, by name.
func openTop(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, kind string) map[string]TopEntry {
	t.Helper()
	list, err := svc.Reads.TopListFor(ctx, uc, kind, "30d", 10)
	if err != nil {
		t.Fatalf("%s: %v", kind, err)
	}
	out := map[string]TopEntry{}
	for _, e := range list.Entries {
		out[e.Name] = e
	}
	return out
}

// wantTopEntry checks an entry's pid and picture; empty for neither.
func wantTopEntry(t *testing.T, e TopEntry, name, pid, art string) {
	t.Helper()
	if e.Name != name || e.Ms == 0 || e.PID != pid || e.ArtPID != art {
		t.Errorf("entry %+v, want %s with pid %q drawing %q", e, name, pid, art)
	}
}

// A caller without explicit content opens no explicit show and no
// episode an advisory flag hides, its own or its show's, and a show's
// fallback picture is an episode it can open; one with explicit content
// opens them all.
func TestTopEntriesFollowTheExplicitToggle(t *testing.T) {
	t.Parallel()
	host := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".mp3") {
			w.Header().Set("Content-Type", "audio/mpeg")
			_, _ = w.Write([]byte("ID3\x04\x00\x00\x00\x00\x00\x00"))
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		item := func(title, guid, explicit string) string {
			return fmt.Sprintf(`<item><title>%s</title><guid>%s</guid><pubDate>%s</pubDate><itunes:explicit>%s</itunes:explicit><enclosure url="http://%s/%s.mp3" type="audio/mpeg" length="10"/></item>`,
				title, guid, time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z), explicit, r.Host, guid)
		}
		show := func(title, explicit string, items ...string) {
			fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>%s</title><itunes:explicit>%s</itunes:explicit>%s</channel></rss>`,
				title, explicit, strings.Join(items, ""))
		}
		if strings.HasSuffix(r.URL.Path, "/rude.xml") {
			show("Rude Cast", "true", item("Rude Ep", "rude", "false"))
			return
		}
		show("Clean Cast", "false", item("Calm Ep", "calm", "false"), item("Rough Ep", "rough", "true"))
	}))
	t.Cleanup(host.Close)
	dir := t.TempDir()
	ctx, svc, admin, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.Roots = []Root{{Name: "lib", Path: t.TempDir()}}
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
	})
	shows := map[string]string{}
	views := map[string]*model.ItemView{}
	for _, feed := range []string{"/clean.xml", "/rude.xml"} {
		sub, _, err := svc.Podcasts.Subscribe(ctx, admin, SubscribeRequest{URL: host.URL + feed})
		if err != nil {
			t.Fatal(err)
		}
		shows[sub.Show.Title] = sub.Show.PID
		eps, _, err := svc.Podcasts.Episodes(ctx, admin, sub.Show.PID, "", 10)
		if err != nil {
			t.Fatal(err)
		}
		var pids []model.PID
		for _, ep := range eps {
			_, bare, _ := parseAPIPID(ep.PID)
			pids = append(pids, bare)
		}
		got, err := svc.lib.GetMany(ctx, pids)
		if err != nil {
			t.Fatal(err)
		}
		for _, v := range got {
			views[v.Title] = v
		}
	}
	calm, rough, rude := views["Calm Ep"], views["Rough Ep"], views["Rude Ep"]
	if calm == nil || rough == nil || rude == nil || calm.AdvisoryFlagged() || !rough.Explicit || !rude.PodcastExplicit {
		t.Fatalf("fixture episodes = %+v", views)
	}
	var sessions []wdb.ListenSession
	for i, l := range []struct {
		v       *model.ItemView
		minutes int
	}{{rough, 3}, {calm, 2}, {rude, 4}} {
		sessions = append(sessions, wdb.ListenSession{UserID: admin.ID, SessionID: fmt.Sprintf("x-%d", i),
			ItemPID: string(l.v.PID), MediaType: "podcast", StartedAt: time.Now().UTC(), MsPlayed: int64(l.minutes) * time.Minute.Milliseconds()})
	}
	if _, err := svc.db.InsertListens(ctx, sessions); err != nil {
		t.Fatal(err)
	}

	kid := &UserCtx{ID: admin.ID, CatalogPID: admin.CatalogPID, AllLibraries: true}
	got := openTop(t, ctx, svc, kid, "shows")
	wantTopEntry(t, got["Rude Cast"], "Rude Cast", "", "")
	wantTopEntry(t, got["Clean Cast"], "Clean Cast", shows["Clean Cast"], itemAPIPID(calm))
	got = openTop(t, ctx, svc, kid, "episodes")
	wantTopEntry(t, got["Rude Ep"], "Rude Ep", "", "")
	wantTopEntry(t, got["Rough Ep"], "Rough Ep", "", "")
	wantTopEntry(t, got["Calm Ep"], "Calm Ep", itemAPIPID(calm), itemAPIPID(calm))

	grown := &UserCtx{ID: admin.ID, CatalogPID: admin.CatalogPID, AllLibraries: true, Explicit: true}
	got = openTop(t, ctx, svc, grown, "shows")
	wantTopEntry(t, got["Rude Cast"], "Rude Cast", shows["Rude Cast"], itemAPIPID(rude))
	wantTopEntry(t, got["Clean Cast"], "Clean Cast", shows["Clean Cast"], itemAPIPID(rough))
	got = openTop(t, ctx, svc, grown, "episodes")
	for _, v := range []*model.ItemView{rude, rough, calm} {
		wantTopEntry(t, got[v.Title], v.Title, itemAPIPID(v), itemAPIPID(v))
	}
}

// A library grant closes an artist none of whose tracks the caller's
// libraries hold, and an artist it can open draws a track from them,
// never its most-listened one in a library it was not granted.
func TestTopArtistsFollowLibraryGrants(t *testing.T) {
	t.Parallel()
	libA, libB := t.TempDir(), t.TempDir()
	for _, s := range []struct{ lib, name, title, artist string }{
		{libA, "a1", "Alpha Song", "Alpha"},
		{libA, "a2", "Shared Low", "Both"},
		{libB, "b1", "Beta Song", "Beta"},
		{libB, "b2", "Shared High", "Both"},
	} {
		if _, err := fixtures.Generate(filepath.Join(s.lib, s.name), fixtures.Spec{
			Name: s.name, Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": s.title, "ARTIST": s.artist, "ALBUMARTIST": s.artist, "ALBUM": s.title, "TRACKNUMBER": "1"},
		}); err != nil {
			t.Fatal(err)
		}
	}
	ctx, svc, admin, _ := openServiceAt(t, t.TempDir(), func(cfg *Config) {
		cfg.Roots = []Root{{Name: "a", Path: libA}, {Name: "b", Path: libB}}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	page, err := svc.Reads.Items(ctx, admin, ItemFilter{MediaType: "music"}, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	var pids []model.PID
	for _, it := range page.Items {
		_, bare, _ := parseAPIPID(it.PID)
		pids = append(pids, bare)
	}
	got, err := svc.lib.GetMany(ctx, pids)
	if err != nil {
		t.Fatal(err)
	}
	views := map[string]*model.ItemView{}
	for _, v := range got {
		views[v.Title] = v
	}
	alpha, low, beta, high := views["Alpha Song"], views["Shared Low"], views["Beta Song"], views["Shared High"]
	if alpha == nil || low == nil || beta == nil || high == nil || low.ArtistPID != high.ArtistPID ||
		low.LibraryPID == high.LibraryPID || alpha.LibraryPID != low.LibraryPID {
		t.Fatalf("fixture tracks = %+v", views)
	}
	var sessions []wdb.ListenSession
	for i, l := range []struct {
		v       *model.ItemView
		minutes int
	}{{high, 5}, {beta, 4}, {alpha, 3}, {low, 2}} {
		sessions = append(sessions, wdb.ListenSession{UserID: admin.ID, SessionID: fmt.Sprintf("g-%d", i),
			ItemPID: string(l.v.PID), MediaType: "music", StartedAt: time.Now().UTC(), MsPlayed: int64(l.minutes) * time.Minute.Milliseconds()})
	}
	if _, err := svc.db.InsertListens(ctx, sessions); err != nil {
		t.Fatal(err)
	}

	granted := &UserCtx{ID: admin.ID, CatalogPID: admin.CatalogPID, Explicit: true,
		Libraries: map[string]bool{string(alpha.LibraryPID): true}}
	artists := openTop(t, ctx, svc, granted, "artists")
	wantTopEntry(t, artists["Beta"], "Beta", "", "")
	wantTopEntry(t, artists["Both"], "Both", apiPID(PrefixArtist, low.ArtistPID), itemAPIPID(low))
	wantTopEntry(t, artists["Alpha"], "Alpha", apiPID(PrefixArtist, alpha.ArtistPID), itemAPIPID(alpha))
	tracks := openTop(t, ctx, svc, granted, "tracks")
	wantTopEntry(t, tracks["Shared High"], "Shared High", "", "")
	wantTopEntry(t, tracks["Beta Song"], "Beta Song", "", "")
	wantTopEntry(t, tracks["Shared Low"], "Shared Low", itemAPIPID(low), itemAPIPID(low))
	// The administrator sees both libraries.
	wantTopEntry(t, openTop(t, ctx, svc, admin, "artists")["Both"], "Both", apiPID(PrefixArtist, low.ArtistPID), itemAPIPID(high))
}
