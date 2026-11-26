package service

import (
	"cmp"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"maps"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The stats surface aggregates the caller's own listen_sessions rows.
// It deliberately skips library-visibility filtering: a user's history
// is their own record of what they played, and hiding rows after a
// grant change would silently falsify their totals. Item metadata for
// display resolves best-effort; items gone from the catalog keep their
// listening time under an empty title. What the caller cannot open now
// keeps its name and time without its pid and picture (closeUnopenable).
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

// TopEntry is one ranked top-list entry.
type TopEntry struct {
	Name   string
	PID    string // the entry's entity or item (API pid); empty for genres and name groups
	ArtPID string // the API pid whose picture the entry draws; empty for none
	Plays  int
	Ms     int64
}

// TopList is one ranked list.
type TopList struct {
	Kind    string
	Range   string
	Entries []TopEntry
}

// ListenLogEntry is one session of the per-device log.
type ListenLogEntry struct {
	SessionID string
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
	TopBooks          []TopEntry
	TopAuthors        []TopEntry
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
func (l *Reads) userLocation(ctx context.Context, uc *UserCtx) (*time.Location, string) {
	p, err := l.Identity.Prefs(ctx, uc)
	if err != nil || p.Timezone == "" {
		return time.UTC, "UTC"
	}
	loc, err := time.LoadLocation(p.Timezone)
	if err != nil {
		return time.UTC, "UTC"
	}
	return loc, p.Timezone
}

// statsMedia are the media a listen session records.
var statsMedia = map[string]bool{"music": true, "podcast": true, "audiobook": true, "radio": true}

// checkStatsMedia accepts a medium a session can record, or "" for all.
func checkStatsMedia(media string) error {
	if media != "" && !statsMedia[media] {
		return errInvalid("unknown mediaType " + media)
	}
	return nil
}

// ListeningStats aggregates the caller's listening over a range, of one
// medium or ("") of every one.
func (l *Reads) ListeningStats(ctx context.Context, uc *UserCtx, rng, bucket, media string) (ListeningStats, error) {
	if _, ok := statsRanges[rng]; !ok && rng != "all" {
		return ListeningStats{}, errInvalid("unknown range " + rng)
	}
	if bucket != "day" && bucket != "week" && bucket != "month" {
		return ListeningStats{}, errInvalid("unknown bucket " + bucket)
	}
	if err := checkStatsMedia(media); err != nil {
		return ListeningStats{}, err
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
		if media != "" && r.MediaType != media {
			return
		}
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
// streaks, of one medium or ("") of every one. Streaks scan the user's
// whole history so runs cross year boundaries honestly.
func (l *Reads) ListeningHeatmap(ctx context.Context, uc *UserCtx, year int, media string) (ListeningHeatmap, error) {
	if err := checkStatsMedia(media); err != nil {
		return ListeningHeatmap{}, err
	}
	loc, tzName := l.userLocation(ctx, uc)
	if year == 0 {
		year = time.Now().In(loc).Year()
	}
	out := ListeningHeatmap{Year: year, Timezone: tzName}
	days := map[int]*HeatmapDay{}
	err := l.db.ListensInRange(ctx, uc.ID, time.Time{}, time.Now().Add(time.Hour), func(r wdb.ListenRow) {
		if media != "" && r.MediaType != media {
			return
		}
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

// topKindMedia is each top-list kind and the one medium whose sessions
// it counts, so spoken-word hours never drown a music list.
var topKindMedia = map[string]string{
	"artists": "music", "albums": "music", "tracks": "music", "genres": "music",
	"shows": "podcast", "episodes": "podcast",
	"books": "audiobook", "authors": "audiobook",
	"stations": "radio",
}

// TopListFor answers one ranked top list over a range.
func (l *Reads) TopListFor(ctx context.Context, uc *UserCtx, kind, rng string, limit int) (TopList, error) {
	if _, ok := statsRanges[rng]; !ok && rng != "all" {
		return TopList{}, errInvalid("unknown range " + rng)
	}
	wantMedia, ok := topKindMedia[kind]
	if !ok {
		return TopList{}, errInvalid("unknown kind " + kind)
	}
	from := time.Time{}
	if d, ok := statsRanges[rng]; ok {
		from = time.Now().Add(-d)
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
	entries, err := l.groupTotals(ctx, uc, totals, kind, limit)
	if err != nil {
		return TopList{}, err
	}
	return TopList{Kind: kind, Range: rng, Entries: entries}, nil
}

// readStationNames reads the station library once and maps bare id to
// name.
//
// One query rather than a lookup per row, the way [liveStationPIDs]
// already reads this table: it is capped at five hundred shared rows, so
// the whole of it costs less than the per-row form does on a page that
// is mostly radio - and the per-row form ran before the ranking was
// truncated, so most of what it fetched was discarded.
func (l *Reads) readStationNames(ctx context.Context) (map[string]string, error) {
	rows, err := l.db.ListRadioStations(ctx)
	if err != nil {
		return nil, err
	}
	names := make(map[string]string, len(rows))
	for _, r := range rows {
		names[r.ID] = r.Name
	}
	return names, nil
}

// stationNames is readStationNames at best effort, for the listen log: a
// read that failed leaves every station unnamed rather than failing the
// page.
func (l *Reads) stationNames(ctx context.Context) map[string]string {
	names, err := l.readStationNames(ctx)
	if err != nil {
		l.log.Debug("reading stations for listening stats", "err", err)
		return nil
	}
	return names
}

// stationTotals ranks per-station totals, naming each from the station
// library. A station that has since been deleted keeps its time under
// its pid with no name, for the reason tracks do: time is never
// silently dropped from a list that claims to total it. It keeps no art
// handle, for the reason a deleted track keeps none - a cover URL for a
// row nothing answers for is a 404 per entry, and the client draws its
// own placeholder from the domain either way. Since an empty name says
// the station left, a station library that cannot be read fails the
// list rather than answering every station that way.
func (l *Reads) stationTotals(ctx context.Context, totals map[string]*itemTotals, limit int) ([]TopEntry, error) {
	if len(totals) == 0 {
		return nil, nil
	}
	names, err := l.readStationNames(ctx)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	entries := make([]TopEntry, 0, len(totals))
	for pid, t := range totals {
		station := apiPID(PrefixRadioStation, model.PID(pid))
		e := TopEntry{PID: station, Plays: t.plays, Ms: t.ms}
		if name, ok := names[pid]; ok {
			e.Name, e.ArtPID = name, station
		}
		entries = append(entries, e)
	}
	return rankTopEntries(entries, limit), nil
}

// groupTotals resolves item metadata and folds per-item totals into the
// kind's entries, named and ranked.
func (l *Reads) groupTotals(ctx context.Context, uc *UserCtx, totals map[string]*itemTotals, kind string, limit int) ([]TopEntry, error) {
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
	groups := foldTopGroups(totals, byPID, kind)
	if err := l.nameEntityGroups(ctx, groups, kind, limit); err != nil {
		return nil, err
	}
	groups = rankTopGroups(groups, limit)
	if err := l.closeUnopenable(ctx, uc, kind, groups, byPID); err != nil {
		return nil, err
	}
	entries := make([]TopEntry, len(groups))
	for i, g := range groups {
		entries[i] = g.entry
	}
	return entries, nil
}

// closeUnopenable takes the pid and picture off every returned entry the
// caller cannot open now, keeping its name and time (the history stays
// the caller's record): an item in the trash or outside what the caller
// may see, an entity none of whose items it may see, a show outside its
// reach. An item that has left keeps its pid. Every picture an entry
// draws from a member is the most-listened member the caller can open.
func (l *Reads) closeUnopenable(ctx context.Context, uc *UserCtx, kind string, groups []*topGroup, byPID map[string]*model.ItemView) error {
	var members []*model.ItemView
	for _, g := range groups {
		for _, m := range g.members {
			if v := byPID[m.pid]; v != nil {
				members = append(members, v)
			}
		}
	}
	opens, err := l.openItems(ctx, uc, members)
	if err != nil {
		return err
	}
	if _, ok := topItemPrefix[kind]; ok {
		for _, g := range groups {
			if byPID[g.repPID] != nil && !opens[model.PID(g.repPID)] {
				g.entry.PID, g.entry.ArtPID = "", ""
			}
		}
		return nil
	}
	closed, err := l.closedEntities(ctx, uc, kind, groups, byPID)
	if err != nil {
		return err
	}
	for _, g := range groups {
		switch {
		case g.entity != "" && closed[g.entity]:
			g.entry.PID, g.entry.ArtPID = "", ""
		case g.entity == "" && g.entry.ArtPID != "":
			// A name group draws a member's picture or none.
			g.entry.ArtPID = g.openArt(opens)
		}
	}
	if ent, ok := topFallbackArt[kind]; ok {
		l.drawUnpicturedEntities(ctx, ent, groups, opens)
	}
	return nil
}

// openItems answers which of the items the caller can open now: not in
// the trash, inside its grants and passing its content rules. The tag
// rules are one batched read, and nothing at all for a caller they do
// not narrow.
func (l *Reads) openItems(ctx context.Context, uc *UserCtx, items []*model.ItemView) (map[model.PID]bool, error) {
	verdicts, err := l.Grants.tagVerdicts(ctx, uc, items)
	if err != nil {
		return nil, err
	}
	out := make(map[model.PID]bool, len(items))
	for _, v := range items {
		if l.Grants.offersWith(ctx, uc, verdicts, v) {
			out[v.PID] = true
		}
	}
	return out, nil
}

// closedEntities answers which of the groups' entities the caller cannot
// open: an artist, album or author with no member its listings offer (as
// the entity cards gate, skipped for a caller of full reach), and a show
// its detail would refuse (showReached, judged off the members' views,
// which carry the show's advisory flag).
func (l *Reads) closedEntities(ctx context.Context, uc *UserCtx, kind string, groups []*topGroup, byPID map[string]*model.ItemView) (map[model.PID]bool, error) {
	closed := map[model.PID]bool{}
	if kind == "shows" {
		podcasts := l.Grants.podcastsVisible(ctx, uc)
		for _, g := range groups {
			if g.entity == "" {
				continue
			}
			v := byPID[g.repPID]
			if !podcasts || (!uc.Explicit && v != nil && v.PodcastExplicit) {
				closed[g.entity] = true
			}
		}
		return closed, nil
	}
	if fullReach(uc) {
		return closed, nil
	}
	var pids []model.PID
	for _, g := range groups {
		if g.entity != "" {
			pids = append(pids, g.entity)
		}
	}
	if len(pids) == 0 {
		return closed, nil
	}
	visible, err := l.visibleEntities(ctx, uc, topEntityPrefix[kind], pids)
	if err != nil {
		return nil, err
	}
	for _, pid := range pids {
		if !visible[pid] {
			closed[pid] = true
		}
	}
	return closed, nil
}

// topFallbackArt is the art level of each kind whose entity's picture
// never falls through to a member's: an artist's chain is its own
// portrait, a show's its feed image. An album's falls through on its own.
var topFallbackArt = map[string]model.ArtEntity{
	"artists": model.ArtArtist, "authors": model.ArtArtist, "shows": model.ArtPodcast,
}

// drawUnpicturedEntities gives a returned entity entry with no picture of
// its own the picture of its most-listened member the caller can open,
// or keeps the entity's URL when it can open none. One read per returned
// entry, so at most the list's limit; a read that fails keeps the
// entity's own URL.
func (l *Reads) drawUnpicturedEntities(ctx context.Context, ent model.ArtEntity, groups []*topGroup, opens map[model.PID]bool) {
	for _, g := range groups {
		if g.entity == "" || g.entry.PID == "" {
			continue
		}
		art := g.openArt(opens)
		if art == "" {
			continue
		}
		_, err := l.lib.ArtProvenance(ctx, model.EntityRef{Type: ent, PID: g.entity}, model.ArtRoleFront)
		switch {
		case err == nil:
		case KindOf(err) == KindNotFound:
			g.entry.ArtPID = art
		default:
			l.log.Debug("reading an entity's picture for listening stats", "entity", g.entity, "err", err)
		}
	}
}

// topItemPrefix is the per-item kinds' pid prefix, for an item that has
// left the catalog and so has no kind to read one from.
var topItemPrefix = map[string]string{"tracks": PrefixTrack, "episodes": PrefixEpisode, "books": PrefixBook}

// topEntityPrefix is the entity each grouped kind gathers its members
// under.
var topEntityPrefix = map[string]string{
	"artists": PrefixArtist, "authors": PrefixArtist, "albums": PrefixAlbum, "shows": PrefixPodcast,
}

// topGroup is one entry while its members are folded in.
type topGroup struct {
	entry   TopEntry
	entity  model.PID // bare entity pid, empty for a name group or an item
	repMs   int64     // the representative member's time
	repPID  string    // and its bare pid, so the choice repeats
	members []topPicture
}

// topPicture is one member's time and the art pid it can lend its entry.
type topPicture struct {
	pid, art string // bare item pid, API art pid
	ms       int64
}

// openArt is the art pid of the group's most-listened member the caller
// can open (lowest pid on a tie), or empty for none.
func (g *topGroup) openArt(opens map[model.PID]bool) string {
	var best *topPicture
	for i := range g.members {
		m := &g.members[i]
		if !opens[model.PID(m.pid)] {
			continue
		}
		if best == nil || m.ms > best.ms || (m.ms == best.ms && m.pid < best.pid) {
			best = m
		}
	}
	if best == nil {
		return ""
	}
	return best.art
}

// topMember is what one item contributes to its kind's entry.
type topMember struct {
	key, name, pid, art string
	itemArt             string // the item's own art pid, under an entity
	entity              model.PID
}

// foldTopGroups folds per-item totals into the kind's groups. A group
// takes its name and art from its most-listened member (lowest pid on a
// tie), so two reads of one history answer the same entry.
func foldTopGroups(totals map[string]*itemTotals, byPID map[string]*model.ItemView, kind string) []*topGroup {
	groups := map[string]*topGroup{}
	for pid, t := range totals {
		m, ok := topMemberOf(kind, pid, byPID[pid])
		if !ok {
			continue
		}
		g := groups[m.key]
		if g == nil {
			g = &topGroup{entry: TopEntry{PID: m.pid}, entity: m.entity}
			groups[m.key] = g
		}
		g.entry.Ms += t.ms
		g.entry.Plays += t.plays
		if art := cmp.Or(m.itemArt, m.art); art != "" {
			g.members = append(g.members, topPicture{pid: pid, art: art, ms: t.ms})
		}
		if g.repPID == "" || t.ms > g.repMs || (t.ms == g.repMs && pid < g.repPID) {
			g.repMs, g.repPID = t.ms, pid
			g.entry.Name, g.entry.ArtPID = m.name, m.art
		}
	}
	out := make([]*topGroup, 0, len(groups))
	for _, g := range groups {
		out = append(out, g)
	}
	return out
}

// topMemberOf places one item in its kind. Per-item kinds keep an item
// that left under its pid, unnamed, so time is never silently dropped
// from them; the grouped kinds drop it, and drop an item that names no
// entity and no name of the kind.
func topMemberOf(kind, pid string, v *model.ItemView) (topMember, bool) {
	if prefix, ok := topItemPrefix[kind]; ok {
		if v == nil {
			return topMember{key: pid, pid: apiPID(prefix, model.PID(pid))}, true
		}
		own := itemAPIPID(v)
		return topMember{key: pid, name: v.Title, pid: own, art: own}, true
	}
	if v == nil {
		return topMember{}, false
	}
	prefix := topEntityPrefix[kind]
	switch kind {
	case "genres":
		if v.Genre == "" {
			return topMember{}, false
		}
		return topMember{key: nameGroupKey(v.Genre), name: v.Genre}, true
	case "artists", "authors":
		// A book's author is its artist.
		return entityMember(prefix, v.ArtistPID, v.Artist, v.Artist, v)
	case "albums":
		// A name group keys on the album artist (track artist as
		// fallback), so a compilation with no album entity does not
		// fragment into one entry per contributing artist.
		albumArtist := v.AlbumArtist
		if albumArtist == "" {
			albumArtist = v.Artist
		}
		return entityMember(prefix, v.AlbumPID, v.Album, albumArtist+"\x00"+v.Album, v)
	case "shows":
		// Episode views carry the show title through Artist, and no read
		// names a show otherwise, so an untitled one names nothing.
		if v.Artist == "" {
			return topMember{}, false
		}
		return entityMember(prefix, v.PodcastPID, clipFeedTitle(v.Artist), v.Artist, v)
	}
	return topMember{}, false
}

// entityMember places an item under its entity, or, with none, under a
// name group keyed on fold that carries no pid and draws the item's art.
func entityMember(prefix string, entity model.PID, name, fold string, v *model.ItemView) (topMember, bool) {
	if entity != "" {
		p := apiPID(prefix, entity)
		return topMember{key: string(entity), name: name, pid: p, art: p, itemArt: itemAPIPID(v), entity: entity}, true
	}
	if name == "" {
		return topMember{}, false
	}
	return topMember{key: nameGroupKey(fold), name: name, art: itemAPIPID(v)}, true
}

// nameGroupKey folds a name into a group key. The NUL lead keeps it apart
// from every pid key, which a ULID never starts with.
func nameGroupKey(name string) string {
	return "\x00" + strings.ToLower(name)
}

// nameEntityGroups names entity groups by the entity itself, one batched
// read per list; a member's text stands in for a pid the read has no row
// for. Names resolve before ranking, so the name tie-break orders entries
// by the names they are shown with, but only for groups that can still
// make the cut (the limit-th largest time or more), so a long tail costs
// no entity reads.
func (l *Reads) nameEntityGroups(ctx context.Context, groups []*topGroup, kind string, limit int) error {
	entityKind, ok := entityKindForPrefix(topEntityPrefix[kind])
	if !ok {
		return nil
	}
	var cut int64
	if limit > 0 && len(groups) > limit {
		ms := make([]int64, len(groups))
		for i, g := range groups {
			ms[i] = g.entry.Ms
		}
		slices.Sort(ms)
		cut = ms[len(ms)-limit]
	}
	var pids []model.PID
	for _, g := range groups {
		if g.entity != "" && g.entry.Ms >= cut {
			pids = append(pids, g.entity)
		}
	}
	if len(pids) == 0 {
		return nil
	}
	infos, err := l.lib.EntityByPIDs(ctx, entityKind, pids)
	if err != nil {
		return classify(err)
	}
	for _, g := range groups {
		if info := infos[g.entity]; g.entity != "" && info != nil && info.Name != "" {
			g.entry.Name = info.Name
		}
	}
	return nil
}

// rankTopGroups is rankTopEntries over the groups the entries come from.
func rankTopGroups(groups []*topGroup, limit int) []*topGroup {
	sort.Slice(groups, func(i, j int) bool { return topEntryLess(groups[i].entry, groups[j].entry) })
	if len(groups) > limit {
		groups = groups[:limit]
	}
	return groups
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
	sort.Slice(entries, func(i, j int) bool { return topEntryLess(entries[i], entries[j]) })
	if len(entries) > limit {
		entries = entries[:limit]
	}
	return entries
}

func topEntryLess(a, b TopEntry) bool {
	if a.Ms != b.Ms {
		return a.Ms > b.Ms
	}
	if a.Name != b.Name {
		return a.Name < b.Name
	}
	return a.PID < b.PID
}

// ListenLog pages the caller's session log newest first.
func (l *Reads) ListenLog(ctx context.Context, uc *UserCtx, client, cursor string, limit int) (ListenLogPage, error) {
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
			SessionID: r.SessionID,
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
			e.Title, e.Artist, _ = itemNames(v)
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
func (l *Reads) UserYearInReview(ctx context.Context, uc *UserCtx, year int) (YearInReview, error) {
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
	bookTotals := map[string]*itemTotals{}
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
		case "audiobook":
			totals = bookTotals
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
	if out.TopArtists, err = l.groupTotals(ctx, uc, musicTotals, "artists", topN); err != nil {
		return YearInReview{}, err
	}
	if out.TopTracks, err = l.groupTotals(ctx, uc, musicTotals, "tracks", topN); err != nil {
		return YearInReview{}, err
	}
	if out.TopGenres, err = l.groupTotals(ctx, uc, musicTotals, "genres", topN); err != nil {
		return YearInReview{}, err
	}
	if out.TopShows, err = l.groupTotals(ctx, uc, showTotals, "shows", topN); err != nil {
		return YearInReview{}, err
	}
	if out.TopBooks, err = l.groupTotals(ctx, uc, bookTotals, "books", topN); err != nil {
		return YearInReview{}, err
	}
	if out.TopAuthors, err = l.groupTotals(ctx, uc, bookTotals, "authors", topN); err != nil {
		return YearInReview{}, err
	}
	// New-in-library is catalog-structural (what joined the library that
	// year), answered by the catalog's own recap, which counts every
	// library: a caller not of full reach counts its own reach instead.
	// The year boundary is UTC either way; a few hours' skew on additions
	// is acceptable for a count of arrivals, unlike listening time.
	if fullReach(uc) {
		if rev, err := l.lib.YearInReview(ctx, model.PID(uc.CatalogPID), year, 1); err == nil {
			out.NewInLibrary = rev.NewInLibrary
		}
	} else {
		out.NewInLibrary = l.arrivalsInReach(ctx, uc, year)
	}
	return out, nil
}

// arrivalsInReach counts the tracks and books that entered the catalog
// in a UTC year among those the caller may enumerate. A count that cannot
// be taken is zero, as the catalog recap's failure is.
func (l *Reads) arrivalsInReach(ctx context.Context, uc *UserCtx, year int) int {
	from, to := yearWindow(year, time.UTC)
	q := l.facetScopeBuilder(ctx, uc).
		WhereValues("kind", query.OpIn, string(model.KindTrack), string(model.KindBook)).
		Where("added", query.OpGte, from.UnixNano()).
		Where("added", query.OpLt, to.UnixNano()).
		Build()
	n, err := l.lib.Count(ctx, q, "")
	if err != nil {
		l.log.Warn("counting the year's arrivals", "year", year, "err", err)
		return 0
	}
	return n
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
func (l *Reads) ServerWideYearInReview(ctx context.Context, uc *UserCtx, year int) (ServerYearInReview, error) {
	if year == 0 {
		year = time.Now().Year()
	}
	type member struct {
		loc      *time.Location
		optedOut bool
	}
	members := map[string]member{}
	if err := l.db.EachUser(ctx, func(u *wdb.User) error {
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
		return nil
	}); err != nil {
		return ServerYearInReview{}, &Error{Kind: KindInternal, Err: err}
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
	// The totals are everyone's, the names are not: an item the reader
	// cannot see stays out of the rankings.
	if err := l.dropUnseen(ctx, uc, musicTotals); err != nil {
		return ServerYearInReview{}, err
	}
	const topN = 5
	if out.TopArtists, err = l.groupTotals(ctx, uc, musicTotals, "artists", topN); err != nil {
		return ServerYearInReview{}, err
	}
	if out.TopTracks, err = l.groupTotals(ctx, uc, musicTotals, "tracks", topN); err != nil {
		return ServerYearInReview{}, err
	}
	if out.TopGenres, err = l.groupTotals(ctx, uc, musicTotals, "genres", topN); err != nil {
		return ServerYearInReview{}, err
	}
	return out, nil
}

// dropUnseen removes the totals of tracks the caller's library grants
// or tag rules hide. A track in the trash or gone from the catalog
// stays, as it does for a reader of full reach: the trash hides nothing
// a grant allows, and a gone track names nothing.
func (l *Reads) dropUnseen(ctx context.Context, uc *UserCtx, totals map[string]*itemTotals) error {
	if fullReach(uc) || len(totals) == 0 {
		return nil
	}
	// The history is the whole server's, so the tracks are read and
	// tag-checked in batches rather than one at a time.
	pids := make([]model.PID, 0, len(totals))
	for pid := range totals {
		pids = append(pids, model.PID(pid))
	}
	views, err := l.itemViewsByPID(ctx, pids)
	if err != nil {
		return err
	}
	allowed, err := l.Grants.tagVerdicts(ctx, uc, slices.Collect(maps.Values(views)))
	if err != nil {
		return err
	}
	for pid, v := range views {
		if !l.Grants.viewVisible(ctx, uc, v) || !l.Grants.contentAllows(ctx, uc, allowed, v) {
			delete(totals, string(pid))
		}
	}
	return nil
}

func sortedMedia(byMedia map[string]*MediaTypeListening) []MediaTypeListening {
	out := make([]MediaTypeListening, 0, len(byMedia))
	for _, m := range byMedia {
		out = append(out, *m)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Ms > out[j].Ms })
	return out
}
