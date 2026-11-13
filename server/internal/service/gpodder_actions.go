package service

import (
	"context"
	"net/url"
	"sort"
	"strconv"
	"sync"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Episode actions: the upload write-through, the cursors and the download
// answers, and the first-party plays served back as actions.

// GpodderAction is one episode action as a gpodder client uploads and
// downloads it.
type GpodderAction struct {
	PodcastURL  string
	EpisodeURL  string
	DeviceID    string
	Action      string
	ActionTS    string
	StartedSec  *int64
	PositionSec *int64
	TotalSec    *int64
	// GUID names the episode by its feed's guid. Only an action the
	// service makes up carries one; none is stored.
	GUID string
}

func gpodderActionRows(actions []GpodderAction) []wdb.GpodderAction {
	rows := make([]wdb.GpodderAction, len(actions))
	for i, a := range actions {
		rows[i] = wdb.GpodderAction{
			PodcastURL: a.PodcastURL, EpisodeURL: a.EpisodeURL, DeviceID: a.DeviceID, Action: a.Action, ActionTS: a.ActionTS,
			StartedSec: a.StartedSec, PositionSec: a.PositionSec, TotalSec: a.TotalSec, GUID: a.GUID,
		}
	}
	return rows
}

func gpodderActionsOf(rows []wdb.GpodderAction) []GpodderAction {
	actions := make([]GpodderAction, len(rows))
	for i, r := range rows {
		actions[i] = GpodderAction{
			PodcastURL: r.PodcastURL, EpisodeURL: r.EpisodeURL, DeviceID: r.DeviceID, Action: r.Action, ActionTS: r.ActionTS,
			StartedSec: r.StartedSec, PositionSec: r.PositionSec, TotalSec: r.TotalSec, GUID: r.GUID,
		}
	}
	return actions
}

// GpodderRecordActions stores one uploaded batch of episode actions,
// stamped with the second it is stored in, and writes their play
// positions through to WaxDeck's playback state, so a gpodder client's
// progress survives into the first-party apps. The log keeps each
// account's newest actions, each once. A stored batch is the client's no
// more: the write-through after it is best effort, uploads naming feeds
// and episodes WaxDeck may not carry, and what it meets is the log's to
// say, never the client's to retry.
func (l *Podcasts) GpodderRecordActions(ctx context.Context, uc *UserCtx, uploaded []GpodderAction) error {
	now := time.Now()
	actions := gpodderActionRows(uploaded)
	untimed := make([]bool, len(actions))
	for i := range actions {
		actions[i].UserID, actions[i].UploadedSec = uc.ID, now.Unix()
		if actions[i].ActionTS == "" {
			// The protocol's time is optional, and gPodder cannot read an
			// action back without one: it is stored at its upload's.
			actions[i].ActionTS, untimed[i] = now.UTC().Format(gpodderTimeLayout), true
		}
	}
	if testHookMembership != nil {
		testHookMembership("record")
	}
	ids, err := l.db.AppendGpodderActions(ctx, actions, gpodderActionsPerUser)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if testHookMembership != nil {
		testHookMembership("recorded")
	}
	if err := l.gpodderWriteThrough(ctx, uc, actions, ids, untimed); err != nil {
		// The kind only: an episode's URL can carry a feed's token.
		l.log.Warn("gpodder play write-through", "user", uc.ID, "kind", string(KindOf(err)))
	}
	return nil
}

// gpodderWriteThrough checkpoints the play actions of a stored batch, ids
// the rows that keep them and untimed those uploaded with no time, which
// land as live checkpoints. An account that cannot see the podcast library
// moves none of its episodes; the log keeps the actions for the grant's
// return.
func (l *Podcasts) gpodderWriteThrough(ctx context.Context, uc *UserCtx, actions []wdb.GpodderAction, ids []int64, untimed []bool) error {
	if !l.Grants.podcastsVisible(ctx, uc) {
		return nil
	}
	var names *gpodderNames
	episodes := map[model.PID]map[string]*model.Episode{}
	for i, a := range actions {
		if a.Action != "play" || a.PositionSec == nil {
			continue
		}
		if names == nil {
			var err error
			if names, err = l.gpodderNames(ctx, uc); err != nil {
				return err
			}
		}
		if untimed[i] {
			a.ActionTS = ""
		}
		if err := l.gpodderApplyPlay(ctx, uc, names, episodes, a, ids[i]); err != nil {
			l.log.Warn("gpodder play write-through", "user", uc.ID, "kind", string(KindOf(err)))
		}
	}
	return nil
}

// gpodderApplyPlay checkpoints one play action's position on the episode
// it names, the show by the uploading device's URL for it or any other
// the account knows, and the episode by its enclosure, the newest of the
// show's when two share one. The action's time, when it has one, makes
// the checkpoint an offline replay, so the per-medium reconciliation
// applies; without one it lands as a live checkpoint. played and finished
// derive from the catalog's own episode duration.
func (l *Podcasts) gpodderApplyPlay(ctx context.Context, uc *UserCtx, names *gpodderNames, episodes map[model.PID]map[string]*model.Episode, a wdb.GpodderAction, id int64) error {
	device, err := names.device(ctx, l, uc, a.DeviceID)
	if err != nil {
		return err
	}
	pod := names.resolve(device, a.PodcastURL)
	if pod == nil {
		return nil
	}
	byURL, ok := episodes[pod.PID]
	if !ok {
		eps, err := l.lib.Podcasts().Episodes(ctx, pod.PID, 0)
		if err != nil {
			return nil
		}
		// Newest first, so the first of an enclosure is its newest episode.
		byURL = make(map[string]*model.Episode, len(eps))
		for _, ep := range eps {
			if _, taken := byURL[ep.EnclosureURL]; !taken {
				byURL[ep.EnclosureURL] = ep
			}
		}
		episodes[pod.PID] = byURL
	}
	ep := byURL[a.EpisodeURL]
	if ep == nil {
		return nil
	}
	var recordedAt *time.Time
	if t, err := parseGpodderTime(a.ActionTS); err == nil {
		recordedAt = &t
	}
	// The protocol has no way to report a skipped replay, and a skip is a
	// success there as it is everywhere else. The change is the stored
	// action's, so the gpodder surface does not say it again as the
	// server's own while the log keeps that action.
	_, err = l.Playback.checkpoint(ctx, uc, apiPID(PrefixEpisode, ep.PID), *a.PositionSec*1000, recordedAt, playChange(id))
	return err
}

// gpodderTimeLayout is the protocol's timestamp: zoneless ISO 8601,
// read as UTC.
const gpodderTimeLayout = "2006-01-02T15:04:05"

// parseGpodderTime reads an action's timestamp, zoneless or RFC 3339.
func parseGpodderTime(s string) (time.Time, error) {
	if t, err := time.Parse(gpodderTimeLayout, s); err == nil {
		return t, nil
	}
	t, err := time.Parse(time.RFC3339, s)
	return t.UTC(), err
}

// NormalizeGpodderTime checks an uploaded action's timestamp and spells it
// the protocol's way; empty stays empty, and anything unreadable, before
// 2000 or more than a day ahead is an error.
func NormalizeGpodderTime(s string) (string, error) {
	if s == "" {
		return "", nil
	}
	t, err := parseGpodderTime(s)
	if err != nil {
		return "", errInvalid("timestamp " + strconv.Quote(s) + " is not an ISO 8601 time")
	}
	if t.Before(time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC)) || t.After(time.Now().Add(24*time.Hour)) {
		return "", errInvalid("timestamp " + strconv.Quote(s) + " is not a time an action can have")
	}
	return t.Format(gpodderTimeLayout), nil
}

// GpodderCursorLag is how far behind the clock every gpodder cursor
// trails. A change takes its stamp a moment before it counts as in
// flight, and a read answering a few seconds back loses none of them; a
// client that reads those seconds twice loses nothing.
const GpodderCursorLag = 5 * time.Second

// gpodderCursor is the cursor a read of the account starting now answers:
// the clock less the lag, and before the oldest write still in flight,
// however long that write waits for the writer.
func (l *Podcasts) gpodderCursor(userID string) (cursor, clock int64) {
	return l.gpodderCursorAt(userID, time.Now())
}

// gpodderCursorAt is gpodderCursor for a read that started at at, clock
// its answer without the writes in flight.
func (l *Podcasts) gpodderCursorAt(userID string, at time.Time) (cursor, clock int64) {
	clock = at.Add(-GpodderCursorLag).Unix()
	cursor = clock
	if sec, ok := l.db.GpodderWriteInFlight(userID); ok {
		cursor = min(cursor, sec-1)
	}
	return cursor, clock
}

// GpodderEpisodesUploadCursor is the timestamp an episodes upload that
// arrived at arrived answers, taken before the upload's own work. A
// client keeps it as the since of its next download, and the endpoint
// names no device, so it is no later than the lowest any episodes
// download signed in with the same app password answered in the last
// gpodderAnswersFor: a client that downloads, then uploads for a while,
// skips nothing another device stored meanwhile, and one stuck reading
// from a low point holds back no other client's answers. Nor is it later
// than the cursor of a read starting when the upload arrived. appPassword
// is the app password the request signed in with, directly or through
// the session its cookie names; "" keys the account's other reads.
func (l *Podcasts) GpodderEpisodesUploadCursor(uc *UserCtx, appPassword string, arrived time.Time) int64 {
	cursor, _ := l.gpodderCursorAt(uc.ID, arrived)
	if read, ok := l.gpodderDownloads.lowest(gpodderReaderKey(uc, appPassword), time.Now()); ok {
		cursor = min(cursor, read)
	}
	return max(cursor, 0)
}

// gpodderReaderKey is what the episodes downloads of one client of the
// account are remembered by: its app password.
func gpodderReaderKey(uc *UserCtx, appPassword string) string {
	return uc.ID + " " + appPassword
}

// gpodderAnswersFor is how long an episodes upload answers no later than
// what a download answered: longer than any client's sync, which
// downloads and then uploads.
const gpodderAnswersFor = 10 * time.Minute

// gpodderAnswersKept bounds the answers one client keeps; past it the
// newest two merge into one, the lower answer kept the longer.
const gpodderAnswersKept = 64

// gpodderAnswer is one download's answer and when it was given.
type gpodderAnswer struct {
	cursor int64
	at     time.Time
}

// gpodderDownloads keeps, by client (gpodderReaderKey), what episodes
// downloads answered in the last gpodderAnswersFor, in memory: after a
// restart an upload answers by the clock until the next download. A
// client's answers are kept oldest first with rising cursors, each new
// answer dropping the later ones it is no higher than, so the first is
// the lowest.
type gpodderDownloads struct {
	mu   sync.Mutex
	held map[string][]gpodderAnswer
}

func (h *gpodderDownloads) note(key string, cursor int64, at time.Time) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.held == nil {
		h.held = map[string][]gpodderAnswer{}
	}
	for k := range h.held {
		h.expire(k, at)
	}
	kept := h.held[key]
	for len(kept) > 0 && kept[len(kept)-1].cursor >= cursor {
		kept = kept[:len(kept)-1]
	}
	kept = append(kept, gpodderAnswer{cursor: cursor, at: at})
	if n := len(kept); n > gpodderAnswersKept {
		kept[n-2].at = kept[n-1].at
		kept = kept[:n-1]
	}
	h.held[key] = kept
}

func (h *gpodderDownloads) lowest(key string, at time.Time) (int64, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if kept := h.expire(key, at); len(kept) > 0 {
		return kept[0].cursor, true
	}
	return 0, false
}

// expire drops a client's answers given gpodderAnswersFor or longer
// before at, and the client with its last. The caller holds mu.
func (h *gpodderDownloads) expire(key string, at time.Time) []gpodderAnswer {
	kept := h.held[key]
	for len(kept) > 0 && at.Sub(kept[0].at) >= gpodderAnswersFor {
		kept = kept[1:]
	}
	if len(kept) == 0 {
		delete(h.held, key)
	} else {
		h.held[key] = kept
	}
	return kept
}

// gpodderPaging bounds the stamp reads behind one episodes download: the
// stamps one read takes, the most one download reads, and the plays past
// which it stops at the end of a second.
type gpodderPaging struct{ page, budget, plays int }

// gpodderDownloadPaging reads a long history in one download: a year of
// heavy listening is tens of thousands of stamps, most of them music.
var gpodderDownloadPaging = gpodderPaging{page: 5000, budget: 50_000, plays: 5000}

// GpodderActionsSince lists the account's episode actions uploaded after
// sinceSec, oldest first, with the cursor the download answers: the
// stored actions, and play actions from device waxdeck for the positions
// the first-party apps moved, each naming its show by the account's URL
// for it. Filtering by podcast narrows both, the stored ones by the
// spelling they were uploaded with and the first-party ones by the show
// the URL names; filtering by any other device leaves the first-party
// ones out. An account that cannot see the podcast library reads none and
// is answered sinceSec back, so it skips nothing once the grant returns.
// The answer is remembered for the uploads of the same app password
// (GpodderEpisodesUploadCursor).
func (l *Podcasts) GpodderActionsSince(ctx context.Context, uc *UserCtx, appPassword string, sinceSec int64, podcastURL, deviceID string) ([]GpodderAction, int64, error) {
	cursor, _ := l.gpodderCursor(uc.ID)
	reader := gpodderReaderKey(uc, appPassword)
	if !l.Grants.podcastsVisible(ctx, uc) {
		l.gpodderDownloads.note(reader, sinceSec, time.Now())
		return nil, sinceSec, nil
	}
	stored, err := l.db.GpodderActionsSince(ctx, uc.ID, sinceSec, podcastURL, deviceID)
	if err != nil {
		return nil, 0, &Error{Kind: KindInternal, Err: err}
	}
	var made []wdb.GpodderAction
	if deviceID == "" || deviceID == GpodderOwnDevice {
		var through int64
		made, through, err = l.gpodderFirstPartyPlays(ctx, uc, sinceSec, podcastURL, gpodderDownloadPaging)
		if err != nil {
			return nil, 0, err
		}
		if through > 0 {
			cursor = min(cursor, through)
		}
	}
	rows := append(stored, made...)
	sort.SliceStable(rows, func(i, j int) bool { return rows[i].UploadedSec < rows[j].UploadedSec })
	cursor = max(cursor, 0)
	l.gpodderDownloads.note(reader, cursor, time.Now())
	return gpodderActionsOf(rows), cursor, nil
}

// gpodderFirstPartyPlays reads the positions the server saw move after
// sinceSec as play actions: an episode of a show the account follows,
// with an enclosure a client can match and a known length, its position
// in whole seconds and at the end once finished. A change a stored gpodder
// action made is that action's to tell, however the server read it (a
// position past the end of the catalog's copy finishes the episode here),
// and is said here once the log has let the action go; the next change
// WaxDeck's own surfaces make is said.
// through is nonzero when the read stopped short of the present, the last
// second it covers whole.
func (l *Podcasts) gpodderFirstPartyPlays(ctx context.Context, uc *UserCtx, sinceSec int64, podcastURL string, paging gpodderPaging) ([]wdb.GpodderAction, int64, error) {
	r := &gpodderPlayReader{l: l, uc: uc, shows: map[model.PID]gpodderPlayShow{}}
	if podcastURL != "" {
		names, err := l.gpodderNames(ctx, uc)
		if err != nil {
			return nil, 0, err
		}
		pod := names.resolve(nil, podcastURL)
		if pod == nil {
			return nil, 0, nil
		}
		r.wantShow = pod.PID
	}
	afterNS, afterPID := (sinceSec+1)*int64(time.Second), ""
	var out []wdb.GpodderAction
	for read := 0; ; {
		stamps, err := l.db.PositionStampsAfter(ctx, uc.ID, afterNS, afterPID, paging.page)
		if err != nil {
			return nil, 0, &Error{Kind: KindInternal, Err: err}
		}
		made, err := r.plays(ctx, stamps)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, made...)
		if len(stamps) < paging.page {
			return out, 0, nil
		}
		read += len(stamps)
		last := stamps[len(stamps)-1]
		afterNS, afterPID = last.SeenNS, last.ItemPID
		lastSec := last.SeenNS / int64(time.Second)
		whole := lastSec-1 > sinceSec
		switch {
		case read >= paging.budget && !whole:
			// Everything read sits in one second: answer it, the rest of
			// that second unsaid, rather than the same page for ever.
			return out, lastSec, nil
		case read >= paging.budget || (whole && len(out) >= paging.plays):
			return out, lastSec - 1, nil
		}
	}
}

// gpodderPlayReader turns pages of stamps into first-party play actions,
// keeping what it looked up across the pages of one download.
type gpodderPlayReader struct {
	l        *Podcasts
	uc       *UserCtx
	wantShow model.PID
	// followed is the account's URL for each show it follows.
	followed map[string]string
	shows    map[model.PID]gpodderPlayShow
}

// gpodderPlayShow is what a show's plays need of it: the feed URL they
// name, "" for a show gpodder clients do not sync, and whether its links
// go out bare.
type gpodderPlayShow struct {
	feed string
	bare bool
}

func (r *gpodderPlayReader) plays(ctx context.Context, stamps []wdb.PositionStamp) ([]wdb.GpodderAction, error) {
	pids := make([]model.PID, 0, len(stamps))
	for _, st := range stamps {
		if !st.FromGpodder {
			pids = append(pids, model.PID(st.ItemPID))
		}
	}
	if len(pids) == 0 {
		return nil, nil
	}
	eps, err := r.l.lib.Podcasts().EpisodesByPIDs(ctx, pids)
	if err != nil {
		return nil, classify(err)
	}
	if len(eps) == 0 {
		return nil, nil
	}
	if r.followed == nil {
		if r.followed, err = r.l.accountFeedURLs(ctx, r.uc.ID); err != nil {
			return nil, err
		}
	}
	byPID := make(map[model.PID]*model.Episode, len(eps))
	statePIDs := make([]model.PID, 0, len(eps))
	for _, ep := range eps {
		if _, followed := r.followed[string(ep.PodcastPID)]; ep.EnclosureURL == "" || !followed {
			continue
		}
		byPID[ep.PID] = ep
		statePIDs = append(statePIDs, ep.PID)
	}
	if len(statePIDs) == 0 {
		return nil, nil
	}
	states, err := r.l.lib.PlayStatesForItems(ctx, statePIDs)
	if err != nil {
		return nil, classify(err)
	}
	var out []wdb.GpodderAction
	for _, st := range stamps {
		ep := byPID[model.PID(st.ItemPID)]
		if ep == nil || st.FromGpodder {
			continue
		}
		show := r.showOf(ctx, ep.PodcastPID)
		if show.feed == "" || (r.wantShow != "" && ep.PodcastPID != r.wantShow) {
			continue
		}
		episodeURL, guid := ep.EnclosureURL, ""
		if show.bare {
			if episodeURL, guid = bareEpisodeURL(ep.EnclosureURL), ep.GUID; episodeURL == "" {
				continue
			}
		}
		state := userPlayState(states[ep.PID], model.PID(r.uc.CatalogPID))
		if state == nil {
			continue
		}
		position, total, ok := gpodderPlayPosition(ep.DurationMS, state)
		if !ok {
			continue
		}
		seen := st.SeenNS / int64(time.Second)
		at := max(st.PositionNS, state.PlayedChangedAt)
		if at <= 0 {
			at = st.SeenNS
		}
		started := int64(0)
		out = append(out, wdb.GpodderAction{
			UserID: r.uc.ID, PodcastURL: show.feed, EpisodeURL: episodeURL, GUID: guid, DeviceID: GpodderOwnDevice,
			Action: "play", ActionTS: time.Unix(0, at).UTC().Format(gpodderTimeLayout),
			StartedSec: &started, PositionSec: &position, TotalSec: &total, UploadedSec: seen,
		})
	}
	return out, nil
}

// showOf is what a show's actions name it by, the account's own URL, and
// whether its links go out bare. The catalog fetched a show by the
// address of whoever added it last, so its links are that follower's: a
// private show's carry that follower's token, and another follower is told
// each episode by its guid and its link without query or login.
func (r *gpodderPlayReader) showOf(ctx context.Context, show model.PID) gpodderPlayShow {
	if s, ok := r.shows[show]; ok {
		return s
	}
	var s gpodderPlayShow
	if pod, err := r.l.lib.Podcasts().Get(ctx, show); err == nil && gpodderSyncs(pod) {
		own := r.followed[string(show)]
		s = gpodderPlayShow{feed: own, bare: own != pod.FeedURL && r.l.showIsPrivate(ctx, pod)}
	}
	r.shows[show] = s
	return s
}

// bareEpisodeURL is an episode link without its query, fragment or user
// info, "" for one that does not parse.
func bareEpisodeURL(raw string) string {
	u, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	u.User, u.RawQuery, u.ForceQuery, u.Fragment, u.RawFragment = nil, "", false, "", ""
	return u.String()
}

// gpodderPlayPosition is where a play action puts the listener, in whole
// seconds, and the episode's length, the end once finished. ok is false
// for an episode of no known length, which a play action says nothing of:
// a client reads one without its total as no position at all.
func gpodderPlayPosition(durationMS int64, st *model.PlayState) (position, total int64, ok bool) {
	if durationMS <= 0 {
		return 0, 0, false
	}
	total = max(durationMS/1000, 1)
	position = st.PositionMS / 1000
	if st.Finished {
		position = total
	}
	return position, total, true
}
