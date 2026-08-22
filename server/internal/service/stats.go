package service

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The stats surface aggregates the caller's own listen_sessions rows.
// It deliberately skips library-visibility filtering: a user's history
// is their own record of what they played, and hiding rows after a
// grant change would silently falsify their totals. Item metadata for
// display resolves best-effort; items gone from the catalog keep their
// listening time under an empty title.
//
// All calendar bucketing happens here in the user's preferred timezone
// (UTC when unset): sessions store UTC and SQLite cannot bucket in an
// arbitrary IANA zone, so rows stream out raw and Go does the calendar
// math.

// ListeningBucket is one chart bucket.
type ListeningBucket struct {
	Start    time.Time // first day of the bucket, midnight in the user's zone
	Ms       int64
	Sessions int
}

// MediaTypeListening is one media type's share.
type MediaTypeListening struct {
	MediaType string
	Ms        int64
	Sessions  int
}

// ListeningStats is the bucketed listening-time answer.
type ListeningStats struct {
	Range       string
	Bucket      string
	Timezone    string
	TotalMs     int64
	Sessions    int
	TimeSavedMs int64
	Buckets     []ListeningBucket
	ByMediaType []MediaTypeListening
}

// HeatmapDay is one day with listening.
type HeatmapDay struct {
	Date     time.Time // midnight in the user's zone
	Ms       int64
	Sessions int
}

// ListeningHeatmap is one calendar year of days plus streaks.
type ListeningHeatmap struct {
	Year              int
	Timezone          string
	Days              []HeatmapDay
	CurrentStreakDays int
	LongestStreakDays int
}

// TopEntry is one ranked top-list entry. ArtItemPID names the group's
// most-listened item as its artwork representative (API-prefixed).
type TopEntry struct {
	Name       string
	PID        string // API pid when the entry is one item; empty for name groups
	ArtItemPID string
	Plays      int
	Ms         int64
}

// TopList is one ranked list.
type TopList struct {
	Kind    string
	Range   string
	Entries []TopEntry
}

// ListenLogEntry is one session of the per-device log.
type ListenLogEntry struct {
	PID       string
	Title     string
	Artist    string
	MediaType string
	StartedAt time.Time
	MsPlayed  int64
	SkippedMs int64
	Finished  bool
	Client    string
	Source    string
}

// ListenLogPage is one page of the log.
type ListenLogPage struct {
	Sessions []ListenLogEntry
	Next     string
}

// MonthListening is one month of a year in review.
type MonthListening struct {
	Month    int
	Ms       int64
	Sessions int
}

// YearInReview is one user's yearly recap.
type YearInReview struct {
	Year              int
	Timezone          string
	TotalMs           int64
	Sessions          int
	DistinctItems     int
	NewInLibrary      int
	TimeSavedMs       int64
	LongestStreakDays int
	ByMonth           []MonthListening
	ByMediaType       []MediaTypeListening
	TopArtists        []TopEntry
	TopTracks         []TopEntry
	TopGenres         []TopEntry
	TopShows          []TopEntry
}

// ServerYearInReview is the whole server's yearly recap.
type ServerYearInReview struct {
	Year         int
	Participants int
	TotalMs      int64
	Sessions     int
	TopArtists   []TopEntry
	TopTracks    []TopEntry
	TopGenres    []TopEntry
}

// statsRanges maps the API range names onto durations; "all" is absent
// and means everything.
var statsRanges = map[string]time.Duration{
	"7d":   7 * 24 * time.Hour,
	"30d":  30 * 24 * time.Hour,
	"90d":  90 * 24 * time.Hour,
	"365d": 365 * 24 * time.Hour,
}

// userLocation resolves the caller's calendar timezone.
func (l *Library) userLocation(ctx context.Context, uc *UserCtx) (*time.Location, string) {
	p, err := l.Prefs(ctx, uc)
	if err != nil || p.Timezone == "" {
		return time.UTC, "UTC"
	}
	loc, err := time.LoadLocation(p.Timezone)
	if err != nil {
		return time.UTC, "UTC"
	}
	return loc, p.Timezone
}

// ListeningStats aggregates the caller's listening over a range.
func (l *Library) ListeningStats(ctx context.Context, uc *UserCtx, rng, bucket string) (ListeningStats, error) {
	if _, ok := statsRanges[rng]; !ok && rng != "all" {
		return ListeningStats{}, errInvalid("unknown range " + rng)
	}
	if bucket != "day" && bucket != "week" && bucket != "month" {
		return ListeningStats{}, errInvalid("unknown bucket " + bucket)
	}
	loc, tzName := l.userLocation(ctx, uc)
	from := time.Time{}
	if d, ok := statsRanges[rng]; ok {
		from = time.Now().Add(-d)
	}
	out := ListeningStats{Range: rng, Bucket: bucket, Timezone: tzName}
	byBucket := map[time.Time]*ListeningBucket{}
	byMedia := map[string]*MediaTypeListening{}
	err := l.db.ListensInRange(ctx, uc.ID, from, time.Now().Add(time.Hour), func(r wdb.ListenRow) {
		out.TotalMs += r.MsPlayed
		out.Sessions++
		out.TimeSavedMs += r.SkippedMs
		start := bucketStart(r.StartedAt.In(loc), bucket)
		b := byBucket[start]
		if b == nil {
			b = &ListeningBucket{Start: start}
			byBucket[start] = b
		}
		b.Ms += r.MsPlayed
		b.Sessions++
		m := byMedia[r.MediaType]
		if m == nil {
			m = &MediaTypeListening{MediaType: r.MediaType}
			byMedia[r.MediaType] = m
		}
		m.Ms += r.MsPlayed
		m.Sessions++
	})
	if err != nil {
		return ListeningStats{}, &Error{Kind: KindInternal, Err: err}
	}
	for _, b := range byBucket {
		out.Buckets = append(out.Buckets, *b)
	}
	sort.Slice(out.Buckets, func(i, j int) bool { return out.Buckets[i].Start.Before(out.Buckets[j].Start) })
	out.ByMediaType = sortedMedia(byMedia)
	return out, nil
}

// bucketStart floors a local time to its bucket's first day.
func bucketStart(t time.Time, bucket string) time.Time {
	y, m, d := t.Date()
	switch bucket {
	case "week":
		day := time.Date(y, m, d, 0, 0, 0, 0, t.Location())
		// Monday-start weeks; Go's Sunday is 0.
		offset := (int(day.Weekday()) + 6) % 7
		return day.AddDate(0, 0, -offset)
	case "month":
		return time.Date(y, m, 1, 0, 0, 0, 0, t.Location())
	default:
		return time.Date(y, m, d, 0, 0, 0, 0, t.Location())
	}
}

// dayNumber converts a civil date to a serial day count, so consecutive
// days differ by exactly one regardless of zone or DST.
func dayNumber(t time.Time) int {
	y, m, d := t.Date()
	// Howard Hinnant's days-from-civil algorithm.
	if m <= 2 {
		y--
	}
	era := y / 400
	if y < 0 {
		era = (y - 399) / 400
	}
	yoe := y - era*400
	mp := (int(m) + 9) % 12
	doy := (153*mp+2)/5 + d - 1
	doe := yoe*365 + yoe/4 - yoe/100 + doy
	return era*146097 + doe - 719468
}

// ListeningHeatmap answers one calendar year of per-day listening plus
// streaks. Streaks scan the user's whole history so runs cross year
// boundaries honestly.
func (l *Library) ListeningHeatmap(ctx context.Context, uc *UserCtx, year int) (ListeningHeatmap, error) {
	loc, tzName := l.userLocation(ctx, uc)
	if year == 0 {
		year = time.Now().In(loc).Year()
	}
	out := ListeningHeatmap{Year: year, Timezone: tzName}
	days := map[int]*HeatmapDay{}
	err := l.db.ListensInRange(ctx, uc.ID, time.Time{}, time.Now().Add(time.Hour), func(r wdb.ListenRow) {
		local := r.StartedAt.In(loc)
		dn := dayNumber(local)
		d := days[dn]
		if d == nil {
			y, m, dd := local.Date()
			d = &HeatmapDay{Date: time.Date(y, m, dd, 0, 0, 0, 0, loc)}
			days[dn] = d
		}
		d.Ms += r.MsPlayed
		d.Sessions++
	})
	if err != nil {
		return ListeningHeatmap{}, &Error{Kind: KindInternal, Err: err}
	}
	nums := make([]int, 0, len(days))
	for dn, d := range days {
		nums = append(nums, dn)
		if d.Date.Year() == year {
			out.Days = append(out.Days, *d)
		}
	}
	sort.Ints(nums)
	sort.Slice(out.Days, func(i, j int) bool { return out.Days[i].Date.Before(out.Days[j].Date) })
	yearStart := dayNumber(time.Date(year, 1, 1, 0, 0, 0, 0, loc))
	yearEnd := dayNumber(time.Date(year+1, 1, 1, 0, 0, 0, 0, loc))
	runStart := 0
	for i := 0; i < len(nums); i++ {
		if i > 0 && nums[i] == nums[i-1]+1 {
			// The run continues.
		} else {
			runStart = i
		}
		run := i - runStart + 1
		// A run counts for the year when any of its days lands in it.
		if nums[i] >= yearStart && nums[runStart] < yearEnd && run > out.LongestStreakDays {
			out.LongestStreakDays = run
		}
		if i == len(nums)-1 {
			today := dayNumber(time.Now().In(loc))
			if nums[i] == today || nums[i] == today-1 {
				out.CurrentStreakDays = run
			}
		}
	}
	return out, nil
}

// itemTotals is the per-item aggregation the top lists group from.
type itemTotals struct {
	pid   string // bare catalog pid
	ms    int64
	plays int
}

// TopListFor answers one ranked top list over a range.
func (l *Library) TopListFor(ctx context.Context, uc *UserCtx, kind, rng string, limit int) (TopList, error) {
	if _, ok := statsRanges[rng]; !ok && rng != "all" {
		return TopList{}, errInvalid("unknown range " + rng)
	}
	switch kind {
	case "artists", "albums", "genres", "shows", "stations":
	default:
		return TopList{}, errInvalid("unknown kind " + kind)
	}
	from := time.Time{}
	if d, ok := statsRanges[rng]; ok {
		from = time.Now().Add(-d)
	}
	// Shows aggregate podcast sessions and stations aggregate radio;
	// the music kinds aggregate music sessions, so audiobook and
	// spoken-word hours never drown a music top list.
	wantMedia := "music"
	switch kind {
	case "shows":
		wantMedia = "podcast"
	case "stations":
		wantMedia = "radio"
	}
	totals := map[string]*itemTotals{}
	err := l.db.ListensInRange(ctx, uc.ID, from, time.Now().Add(time.Hour), func(r wdb.ListenRow) {
		if r.MediaType != wantMedia {
			return
		}
		t := totals[r.ItemPID]
		if t == nil {
			t = &itemTotals{pid: r.ItemPID}
			totals[r.ItemPID] = t
		}
		t.ms += r.MsPlayed
		t.plays++
	})
	if err != nil {
		return TopList{}, &Error{Kind: KindInternal, Err: err}
	}
	// Stations resolve from the station table rather than through
	// `groupTotals`, whose whole path is the catalog: a station has no
	// item view, no artist, and no album to group by, and its artwork
	// comes from the logo proxy rather than from an item.
	if kind == "stations" {
		entries, err := l.stationTotals(ctx, totals, limit)
		if err != nil {
			return TopList{}, err
		}
		return TopList{Kind: kind, Range: rng, Entries: entries}, nil
	}
	entries, err := l.groupTotals(ctx, totals, kind, limit)
	if err != nil {
		return TopList{}, err
	}
	return TopList{Kind: kind, Range: rng, Entries: entries}, nil
}

// stationNames reads the station library once and maps bare id to name.
//
// One query rather than a lookup per row, the way [liveStationPIDs]
// already reads this table: it is capped at five hundred shared rows, so
// the whole of it costs less than the per-row form does on a page that
// is mostly radio - and the per-row form ran before the ranking was
// truncated, so most of what it fetched was discarded.
//
// Best effort. A read that failed leaves every station unnamed, which is
// what a deleted one already looks like, rather than failing the page.
func (l *Library) stationNames(ctx context.Context) map[string]string {
	rows, err := l.db.ListRadioStations(ctx)
	if err != nil {
		l.log.Debug("reading stations for listening stats", "err", err)
		return nil
	}
	names := make(map[string]string, len(rows))
	for _, r := range rows {
		names[r.ID] = r.Name
	}
	return names
}

// stationTotals ranks per-station totals, naming each from the station
// library. A station that has since been deleted keeps its time under
// its pid with no name, for the reason tracks do: time is never
// silently dropped from a list that claims to total it. It keeps no art
// handle, for the reason a deleted track keeps none - a cover URL for a
// row nothing answers for is a 404 per entry, and the client draws its
// own placeholder from the domain either way.
func (l *Library) stationTotals(ctx context.Context, totals map[string]*itemTotals, limit int) ([]TopEntry, error) {
	if len(totals) == 0 {
		return nil, nil
	}
	names := l.stationNames(ctx)
	entries := make([]TopEntry, 0, len(totals))
	for pid, t := range totals {
		station := apiPID(PrefixRadioStation, model.PID(pid))
		e := TopEntry{PID: station, Plays: t.plays, Ms: t.ms}
		if name, ok := names[pid]; ok {
			e.Name, e.ArtItemPID = name, station
		}
		entries = append(entries, e)
	}
	return rankTopEntries(entries, limit), nil
}

// groupTotals resolves item metadata and folds per-item totals into
// name groups (or items themselves for kind "tracks").
func (l *Library) groupTotals(ctx context.Context, totals map[string]*itemTotals, kind string, limit int) ([]TopEntry, error) {
	if len(totals) == 0 {
		return nil, nil
	}
	pids := make([]model.PID, 0, len(totals))
	for pid := range totals {
		pids = append(pids, model.PID(pid))
	}
	views, err := l.lib.GetMany(ctx, pids)
	if err != nil {
		return nil, classify(err)
	}
	byPID := make(map[string]*model.ItemView, len(views))
	for _, v := range views {
		byPID[string(v.PID)] = v
	}
	type group struct {
		entry TopEntry
		topMs int64 // the representative item's listening time
	}
	groups := map[string]*group{}
	for pid, t := range totals {
		v := byPID[pid]
		if v == nil {
			// The item left the catalog; a name group cannot form
			// around it. Tracks keep it under an empty title so time
			// is never silently dropped from per-item lists.
			if kind != "tracks" {
				continue
			}
		}
		var key, name, entryPID, artPID string
		switch kind {
		case "tracks":
			key = pid
			if v != nil {
				name = v.Title
				entryPID = itemAPIPID(v)
				artPID = entryPID
			}
		case "artists":
			if v.Artist == "" {
				continue
			}
			key, name = strings.ToLower(v.Artist), v.Artist
			artPID = itemAPIPID(v)
		case "albums":
			if v.Album == "" {
				continue
			}
			// Album-artist grouping (track artist as fallback), the
			// same rule the compatibility surface's browse uses: a
			// various-artists compilation keyed by track artist would
			// fragment into one entry per contributing artist.
			albumArtist := v.AlbumArtist
			if albumArtist == "" {
				albumArtist = v.Artist
			}
			key, name = strings.ToLower(albumArtist+"\x00"+v.Album), v.Album
			artPID = itemAPIPID(v)
		case "genres":
			if v.Genre == "" {
				continue
			}
			key, name = strings.ToLower(v.Genre), v.Genre
		case "shows":
			// Episode views carry the show title through Artist.
			if v.Artist == "" {
				continue
			}
			key, name = strings.ToLower(v.Artist), v.Artist
			artPID = itemAPIPID(v)
		}
		g := groups[key]
		if g == nil {
			g = &group{entry: TopEntry{Name: name, PID: entryPID}}
			groups[key] = g
		}
		g.entry.Ms += t.ms
		g.entry.Plays += t.plays
		if t.ms > g.topMs {
			g.topMs = t.ms
			g.entry.ArtItemPID = artPID
			if kind == "tracks" {
				g.entry.Name, g.entry.PID = name, entryPID
			}
		}
	}
	entries := make([]TopEntry, 0, len(groups))
	for _, g := range groups {
		entries = append(entries, g.entry)
	}
	return rankTopEntries(entries, limit), nil
}

// rankTopEntries orders a top list and cuts it to limit.
//
// Ranking by listening time, name-ascending on a tie, and pid last so a
// list is stable between two reads that measured the same thing. The pid
// is what makes that true rather than nearly true: `sort.Slice` is not a
// stable sort, and every entry whose item has left the catalog carries
// the same empty name - so a tie between two of those decided on name
// alone leaves their order to the sort, and `entries[:limit]` can answer
// with a different set each time it is asked.
func rankTopEntries(entries []TopEntry, limit int) []TopEntry {
	sort.Slice(entries, func(i, j int) bool {
		a, b := entries[i], entries[j]
		if a.Ms != b.Ms {
			return a.Ms > b.Ms
		}
		if a.Name != b.Name {
			return a.Name < b.Name
		}
		return a.PID < b.PID
	})
	if len(entries) > limit {
		entries = entries[:limit]
	}
	return entries
}

// ListenLog pages the caller's session log newest first.
func (l *Library) ListenLog(ctx context.Context, uc *UserCtx, client, cursor string, limit int) (ListenLogPage, error) {
	beforeNS, beforeID, err := decodeLogCursor(cursor)
	if err != nil {
		return ListenLogPage{}, errInvalid("malformed cursor")
	}
	rows, err := l.db.ListenLog(ctx, uc.ID, client, beforeNS, beforeID, limit+1)
	if err != nil {
		return ListenLogPage{}, &Error{Kind: KindInternal, Err: err}
	}
	more := len(rows) > limit
	if more {
		rows = rows[:limit]
	}
	pids := make([]model.PID, 0, len(rows))
	seen := map[string]bool{}
	anyRadio := false
	for _, r := range rows {
		// A station is not in the catalog, so asking the item store for
		// one would be a miss the log then renders as a nameless row.
		// The station library is what answers for it.
		if r.MediaType == "radio" {
			anyRadio = true
			continue
		}
		if seen[r.ItemPID] {
			continue
		}
		seen[r.ItemPID] = true
		pids = append(pids, model.PID(r.ItemPID))
	}
	// Read whole, once, and only for a page that holds a radio row: the
	// non-radio pids beside it are already one GetMany rather than a
	// query each, and this table is small and capped.
	var stationNames map[string]string
	if anyRadio {
		stationNames = l.stationNames(ctx)
	}
	byPID := map[string]*model.ItemView{}
	if len(pids) > 0 {
		views, err := l.lib.GetMany(ctx, pids)
		if err != nil {
			return ListenLogPage{}, classify(err)
		}
		for _, v := range views {
			byPID[string(v.PID)] = v
		}
	}
	out := ListenLogPage{Sessions: make([]ListenLogEntry, 0, len(rows))}
	for _, r := range rows {
		e := ListenLogEntry{
			PID:       prefixForMediaType(r.MediaType) + "-" + r.ItemPID,
			MediaType: r.MediaType,
			StartedAt: r.StartedAt,
			MsPlayed:  r.MsPlayed,
			SkippedMs: r.SkippedMs,
			Finished:  r.Finished,
			Client:    r.Client,
			Source:    r.Source,
		}
		// Keyed by bare id in a map that now holds every station rather
		// than only this page's, so the media type is what says the
		// lookup applies at all.
		if r.MediaType == "radio" {
			if name, ok := stationNames[r.ItemPID]; ok {
				e.Title = name
			}
		}
		if v := byPID[r.ItemPID]; v != nil {
			e.Title, e.Artist = v.Title, v.Artist
			e.PID = itemAPIPID(v)
		}
		out.Sessions = append(out.Sessions, e)
	}
	if more {
		last := rows[len(rows)-1]
		out.Next = encodeLogCursor(last.StartedAt.UnixNano(), last.RowID)
	}
	return out, nil
}

// prefixForMediaType maps a stored media type back to an item prefix,
// for rows whose item no longer resolves.
func prefixForMediaType(mt string) string {
	switch mt {
	case "podcast":
		return PrefixEpisode
	case "audiobook":
		return PrefixBook
	case "radio":
		// Not an item prefix at all: a station is addressable but is
		// not in the catalog, so nothing downstream may try to resolve
		// this through the item store.
		return PrefixRadioStation
	default:
		return PrefixTrack
	}
}

func encodeLogCursor(ns, id int64) string {
	return base64.RawURLEncoding.EncodeToString(
		[]byte(strconv.FormatInt(ns, 10) + ":" + strconv.FormatInt(id, 10)))
}

func decodeLogCursor(c string) (ns, id int64, err error) {
	if c == "" {
		return 0, 0, nil
	}
	raw, err := base64.RawURLEncoding.DecodeString(c)
	if err != nil {
		return 0, 0, err
	}
	a, b, found := strings.Cut(string(raw), ":")
	if !found {
		return 0, 0, fmt.Errorf("malformed cursor")
	}
	if ns, err = strconv.ParseInt(a, 10, 64); err != nil {
		return 0, 0, err
	}
	if id, err = strconv.ParseInt(b, 10, 64); err != nil {
		return 0, 0, err
	}
	return ns, id, nil
}

// yearWindow answers the UTC instants bounding a calendar year in loc.
func yearWindow(year int, loc *time.Location) (from, to time.Time) {
	return time.Date(year, 1, 1, 0, 0, 0, 0, loc),
		time.Date(year+1, 1, 1, 0, 0, 0, 0, loc)
}

// UserYearInReview computes the caller's recap for one year.
func (l *Library) UserYearInReview(ctx context.Context, uc *UserCtx, year int) (YearInReview, error) {
	loc, tzName := l.userLocation(ctx, uc)
	if year == 0 {
		year = time.Now().In(loc).Year()
	}
	from, to := yearWindow(year, loc)
	out := YearInReview{Year: year, Timezone: tzName}
	months := [12]MonthListening{}
	byMedia := map[string]*MediaTypeListening{}
	musicTotals := map[string]*itemTotals{}
	showTotals := map[string]*itemTotals{}
	distinct := map[string]bool{}
	days := map[int]bool{}
	err := l.db.ListensInRange(ctx, uc.ID, from, to, func(r wdb.ListenRow) {
		local := r.StartedAt.In(loc)
		if local.Year() != year {
			// The scan window is exact for the caller's own zone, but a
			// DST edge can still land a row on the boundary.
			return
		}
		out.TotalMs += r.MsPlayed
		out.Sessions++
		out.TimeSavedMs += r.SkippedMs
		// A station is not an item, so it counts toward the time and
		// toward its own media slice but never toward "how many
		// different things did you listen to".
		if r.MediaType != "radio" {
			distinct[r.ItemPID] = true
		}
		days[dayNumber(local)] = true
		months[local.Month()-1].Ms += r.MsPlayed
		months[local.Month()-1].Sessions++
		m := byMedia[r.MediaType]
		if m == nil {
			m = &MediaTypeListening{MediaType: r.MediaType}
			byMedia[r.MediaType] = m
		}
		m.Ms += r.MsPlayed
		m.Sessions++
		var totals map[string]*itemTotals
		switch r.MediaType {
		case "music":
			totals = musicTotals
		case "podcast":
			totals = showTotals
		default:
			return
		}
		t := totals[r.ItemPID]
		if t == nil {
			t = &itemTotals{pid: r.ItemPID}
			totals[r.ItemPID] = t
		}
		t.ms += r.MsPlayed
		t.plays++
	})
	if err != nil {
		return YearInReview{}, &Error{Kind: KindInternal, Err: err}
	}
	out.DistinctItems = len(distinct)
	for i := range months {
		months[i].Month = i + 1
		out.ByMonth = append(out.ByMonth, months[i])
	}
	out.ByMediaType = sortedMedia(byMedia)
	out.LongestStreakDays = longestRun(days)
	const topN = 5
	if out.TopArtists, err = l.groupTotals(ctx, musicTotals, "artists", topN); err != nil {
		return YearInReview{}, err
	}
	if out.TopTracks, err = l.groupTotals(ctx, musicTotals, "tracks", topN); err != nil {
		return YearInReview{}, err
	}
	if out.TopGenres, err = l.groupTotals(ctx, musicTotals, "genres", topN); err != nil {
		return YearInReview{}, err
	}
	if out.TopShows, err = l.groupTotals(ctx, showTotals, "shows", topN); err != nil {
		return YearInReview{}, err
	}
	// New-in-library is catalog-structural (what joined the library that
	// year), answered by the catalog's own recap. Its year boundary is
	// UTC; a few hours' skew on additions is acceptable for a count of
	// arrivals, unlike listening time.
	if rev, err := l.lib.YearInReview(ctx, model.PID(uc.CatalogPID), year, 1); err == nil {
		out.NewInLibrary = rev.NewInLibrary
	}
	return out, nil
}

// longestRun answers the longest consecutive-day run in a day set.
func longestRun(days map[int]bool) int {
	nums := make([]int, 0, len(days))
	for d := range days {
		nums = append(nums, d)
	}
	sort.Ints(nums)
	best, run := 0, 0
	for i, d := range nums {
		if i > 0 && d == nums[i-1]+1 {
			run++
		} else {
			run = 1
		}
		if run > best {
			best = run
		}
	}
	return best
}

// ServerWideYearInReview aggregates every enrolled user's year. Each
// participant's sessions bucket in their own timezone; opted-out users
// are absent from every figure.
func (l *Library) ServerWideYearInReview(ctx context.Context, year int) (ServerYearInReview, error) {
	if year == 0 {
		year = time.Now().Year()
	}
	type member struct {
		loc      *time.Location
		optedOut bool
	}
	members := map[string]member{}
	after := ""
	for {
		users, err := l.db.ListUsers(ctx, after, 500)
		if err != nil {
			return ServerYearInReview{}, &Error{Kind: KindInternal, Err: err}
		}
		if len(users) == 0 {
			break
		}
		for _, u := range users {
			m := member{loc: time.UTC}
			if doc, err := l.db.PrefsJSON(ctx, u.ID); err == nil && doc != "" {
				var p Prefs
				if jsonErr := json.Unmarshal([]byte(doc), &p); jsonErr == nil {
					m.optedOut = p.SharedStatsOptOut
					if p.Timezone != "" {
						if loc, locErr := time.LoadLocation(p.Timezone); locErr == nil {
							m.loc = loc
						}
					}
				}
			}
			members[u.ID] = m
		}
		after = strings.ToLower(users[len(users)-1].Username)
	}
	// The widest instants any zone maps into this calendar year.
	from := time.Date(year, 1, 1, 0, 0, 0, 0, time.UTC).Add(-14 * time.Hour)
	to := time.Date(year+1, 1, 1, 0, 0, 0, 0, time.UTC).Add(12 * time.Hour)
	out := ServerYearInReview{Year: year}
	musicTotals := map[string]*itemTotals{}
	participants := map[string]bool{}
	err := l.db.ListensInRange(ctx, "", from, to, func(r wdb.ListenRow) {
		m, ok := members[r.UserID]
		if !ok || m.optedOut {
			return
		}
		if r.StartedAt.In(m.loc).Year() != year {
			return
		}
		// Deliberately before the media-type check, and radio now lands
		// here: the server-wide recap counts listening time, and a
		// listener whose year was radio has listened. It follows that
		// radio-only accounts start appearing in the participant count,
		// which is the intended reading rather than a side effect to be
		// discovered later.
		participants[r.UserID] = true
		out.TotalMs += r.MsPlayed
		out.Sessions++
		if r.MediaType != "music" {
			return
		}
		t := musicTotals[r.ItemPID]
		if t == nil {
			t = &itemTotals{pid: r.ItemPID}
			musicTotals[r.ItemPID] = t
		}
		t.ms += r.MsPlayed
		t.plays++
	})
	if err != nil {
		return ServerYearInReview{}, &Error{Kind: KindInternal, Err: err}
	}
	out.Participants = len(participants)
	const topN = 5
	if out.TopArtists, err = l.groupTotals(ctx, musicTotals, "artists", topN); err != nil {
		return ServerYearInReview{}, err
	}
	if out.TopTracks, err = l.groupTotals(ctx, musicTotals, "tracks", topN); err != nil {
		return ServerYearInReview{}, err
	}
	if out.TopGenres, err = l.groupTotals(ctx, musicTotals, "genres", topN); err != nil {
		return ServerYearInReview{}, err
	}
	return out, nil
}

func sortedMedia(byMedia map[string]*MediaTypeListening) []MediaTypeListening {
	out := make([]MediaTypeListening, 0, len(byMedia))
	for _, m := range byMedia {
		out = append(out, *m)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Ms > out[j].Ms })
	return out
}
