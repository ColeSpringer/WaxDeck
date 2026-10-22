package service

import (
	"context"
	"slices"
	"sync"
	"sync/atomic"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
	"github.com/colespringer/waxbin/waxerr"
)

// advisoryTagKey is the custom tag the content-advisory surfaces read:
// the kids-mode deny rule the admin screen offers targets it, and the
// Subsonic explicitStatus emission below queries it.
const advisoryTagKey = "ITUNESADVISORY"

// advisoryExplicitValues are the values that assert explicit: "1", and
// the legacy "4" older iTunes wrote for the same fact. "2" is a
// declared clean and "0" says nothing; neither is matched, and the
// emission stays positive-only.
var advisoryExplicitValues = []string{"1", "4"}

// TrackFacts is the flat per-track shape the Subsonic adapter groups
// into its artist and album views. The display strings carry the
// grouping labels; the entity pids carry the identity the catalog
// actually keeps, so the compatibility surface can key a group on the
// real artist or album instead of on its spelling. A pid is empty when
// the catalog holds no such entity for the track (a loose track has no
// album row), and the adapter falls back to a minted identifier there.
type TrackFacts struct {
	PID         string
	Title       string
	Artist      string
	AlbumArtist string
	Album       string
	Genre       string
	TrackNo     int
	DiscNo      int
	Year        int
	// BPM is the stated tempo, whole; 0 for a track carrying none.
	BPM        int
	DurationMS int64
	Codec      string
	Container  string

	// Explicit reports an ITUNESADVISORY custom tag asserting explicit
	// (advisoryExplicitValues); a declared clean and an absent tag both
	// stay false, and the adapter's emission is positive-only, so false
	// reads as unasserted rather than clean.
	Explicit bool

	// API-form entity pids (ar-..., al-...). AlbumArtistPID carries the same
	// fallback as the AlbumArtist display string above, so it is the
	// grouping handle; the raw track-artist pid is deliberately absent,
	// because a consumer reaching for it would be reaching for the
	// wrong key.
	AlbumArtistPID string
	AlbumPID       string

	// LibraryPID is the library holding the primary file (lb-...), which
	// musicFolderId scopes by; FilePID is that file (fl-...), FileFacts'
	// key. Virtual marks a track carved out of a larger file by a cue
	// sheet, whose file is the whole rip.
	LibraryPID string
	FilePID    string
	Virtual    bool
}

// trackFactsCache holds the compatibility surface's caches: the
// unrestricted sweep, keyed by the catalog content position so a change
// to what it lists invalidates it, and beside it the primary-file facts
// and the per-user entity ratings (marks.go).
type trackFactsCache struct {
	mu    sync.Mutex
	tail  int64
	valid bool
	rows  []TrackFacts

	watch   catalogWatch
	files   fileFactsCache
	ratings entityRatingMemo
	// entityReadHook stands in for the catalog's read of one entity's
	// state in tests, changesHook for its change-log reads.
	entityReadHook func(context.Context, model.PID, model.MergeEntity, model.PID) (*model.EntityPlayState, error)
	changesHook    func(ctx context.Context, since int64) ([]model.Change, error)
	headHook       func(ctx context.Context) (int64, error)
	// feedHook stands in for the feed position in tests, fallbackHook
	// for a store error under a read that falls back (fallbacks.go).
	feedHook     func() int64
	fallbackHook func(read string) error
}

// changesSince reads the change log after since.
func (l *Library) changesSince(ctx context.Context, since int64) ([]model.Change, error) {
	if hook := l.trackFacts.changesHook; hook != nil {
		return hook(ctx, since)
	}
	return l.lib.Changes(ctx, since)
}

// CatalogTailSeq is the catalog's feed position under the generation
// mint count, packed high so it only grows, across a replaced catalog
// too. Holds while tail < 2^40. Every change-log row moves it, a play
// or a star included; CatalogContentSeq is the one only content moves.
func (l *Library) CatalogTailSeq() int64 {
	l.feed.mu.Lock()
	defer l.feed.mu.Unlock()
	return l.feed.mints<<40 | l.feed.tail
}

// stateOnlyChanges are the change-log rows that leave the catalog's
// content as it was: a user's play states, stars, ratings, bookmarks and
// queue, accounts, playlists, and job progress.
var stateOnlyChanges = map[string]bool{
	"play_state": true, "entity_play_state": true, "bookmark": true, "play_queue": true,
	"user": true, "playlist": true, "job": true,
}

// catalogWatchPages bounds the change-log pages one look reads, a day of
// many listeners' state rows; a log further behind than that is taken to
// hold a change of every kind.
const catalogWatchPages = 100

// catalogWatch follows the change log for what the compatibility
// surface's caches depend on: the last row that changed content, the
// last that changed content or a play state, and how many artist or
// album changes it has seen, which can move a rating without any write
// of this service's (a merge re-points every user's, an orphan sweep
// drops them). A log pruned past where it read, or too far behind,
// counts as a change of every kind. A look that fails, its caller's own
// context gone included, says so and moves nothing: the rows it read are
// counted and the rest wait for the next look, and its caller keys
// nothing on the answer.
type catalogWatch struct {
	mu       sync.Mutex
	primed   bool
	gen      int64
	seq      int64 // read to here
	content  int64 // the last row at or before seq that changed content
	plays    int64 // the last that changed content or a play state
	entities uint64
	// began is when the last good look started; a caller that arrived
	// before it takes that look's answer rather than reading again.
	began time.Time
	good  bool
	// answered is the highest content position CatalogContentSeq gave.
	answered atomic.Int64
}

// watchState is what one look at the change log answers.
type watchState struct {
	gen, content, plays int64
	entities            uint64
}

// watchLook catches the watch up with the change log: one statement when
// nothing was written since the last look.
func (l *Library) watchLook(ctx context.Context) (watchState, bool) {
	arrived := time.Now()
	w := &l.trackFacts.watch
	w.mu.Lock()
	defer w.mu.Unlock()
	state := func() watchState {
		return watchState{gen: w.gen, content: w.content, plays: w.plays, entities: w.entities}
	}
	if w.good && w.began.After(arrived) {
		return state(), true
	}
	w.began, w.good = time.Now(), false
	fail := func() (watchState, bool) {
		return watchState{entities: w.entities}, false
	}
	head, err := l.latestChangeSeq(ctx)
	if err != nil {
		return fail()
	}
	gen := l.catalogGeneration()
	if !w.primed || w.gen != gen || head < w.seq {
		// Nothing was cached before the first look; after a replaced
		// catalog everything may differ.
		w.primed, w.gen, w.seq, w.content, w.plays = true, gen, head, head, head
		w.entities++
	}
	for pages := 0; w.seq < head; pages++ {
		if pages == catalogWatchPages {
			w.seq, w.content, w.plays = head, head, head
			w.entities++
			break
		}
		rows, err := l.changesSince(ctx, w.seq)
		if waxerr.CodeOf(err) == waxerr.CodeNotFound {
			w.seq, w.content, w.plays = head, head, head
			w.entities++
			break
		}
		if err != nil {
			return fail()
		}
		if len(rows) == 0 {
			break
		}
		for _, ch := range rows {
			switch ch.EntityType {
			case "artist", "album", model.ChangeCatalog:
				w.entities++
			}
			if !stateOnlyChanges[ch.EntityType] {
				w.content = ch.Seq
			}
			if !stateOnlyChanges[ch.EntityType] || ch.EntityType == "play_state" {
				w.plays = ch.Seq
			}
			w.seq = ch.Seq
		}
	}
	w.good = true
	return state(), true
}

// latestChangeSeq reads the change log's head.
func (l *Library) latestChangeSeq(ctx context.Context) (int64, error) {
	if hook := l.trackFacts.headHook; hook != nil {
		return hook(ctx)
	}
	return l.lib.LatestChangeSeq(ctx)
}

// feedKey is CatalogTailSeq, or the test hook standing in for it.
func (l *Library) feedKey() int64 {
	if hook := l.trackFacts.feedHook; hook != nil {
		return hook()
	}
	return l.CatalogTailSeq()
}

// CatalogContentSeq is CatalogTailSeq moved only by the rows that change
// the catalog's content: the key the caches of what the compatibility
// surface lists hold their entries under, which a play anywhere would
// otherwise empty. While the feed trails the log it answers the feed's
// position instead: what a restricted build reads besides the catalog
// (the tag spellings a content rule matches) follows the feed, so no
// build is filed under a position newer than its inputs, and the answer
// moves again once the feed catches up. It never goes back: a log it
// cannot read answers the last position it gave, or the start of a
// catalog replaced since.
func (l *Library) CatalogContentSeq(ctx context.Context) int64 {
	feed := l.feedKey()
	answered := &l.trackFacts.watch.answered
	st, ok := l.watchLook(ctx)
	if !ok {
		return max(answered.Load(), l.catalogGeneration()<<40)
	}
	key := min(st.gen<<40|st.content, feed)
	for {
		held := answered.Load()
		if key <= held {
			return held
		}
		if answered.CompareAndSwap(held, key) {
			return key
		}
	}
}

// CatalogPlaysSeq is the position plays move: the content position with
// every play-state row counted too, which is what a fold of a listener's
// played or most played list holds for. False when the log could not be
// read, and then nothing may be filed under the answer.
func (l *Library) CatalogPlaysSeq(ctx context.Context) (int64, bool) {
	st, ok := l.watchLook(ctx)
	if !ok {
		return 0, false
	}
	return st.gen<<40 | st.plays, true
}

// catalogGeneration counts catalog replacements: a reset or a restore
// moves it, and nothing short of one does.
func (l *Library) catalogGeneration() int64 {
	l.feed.mu.Lock()
	defer l.feed.mu.Unlock()
	return l.feed.mints
}

// TrackFacts sweeps every music track visible to the caller. Only the
// unrestricted sweep is cached - full visibility and no tag rules, the
// same predicate the facet cache applies - because a narrowed sweep
// published under the shared entry would hand everyone the narrowed
// rows. Everyone else pays the sweep each time, keeping visibility
// exact; the adapter's own index cache in front of this keys restricted
// builds on the caller's grants and rules.
func (l *Library) TrackFacts(ctx context.Context, uc *UserCtx) ([]TrackFacts, error) {
	tail := l.CatalogContentSeq(ctx)
	ruleFree := uc.Admin || (len(uc.TagAllow) == 0 && len(uc.TagDeny) == 0)
	cacheable := uc.AllLibraries && ruleFree
	if cacheable {
		l.trackFacts.mu.Lock()
		if l.trackFacts.valid && l.trackFacts.tail == tail {
			rows := l.trackFacts.rows
			l.trackFacts.mu.Unlock()
			return rows, nil
		}
		l.trackFacts.mu.Unlock()
	}
	sweep, fell := WatchDegraded(ctx)
	rows, err := l.sweepTrackFacts(sweep, uc)
	if err != nil {
		return nil, err
	}
	// Published only while the catalog still stands where the sweep began
	// (the adapter's index cache and publishFacetBuckets hold the same
	// rule): rows computed across a moving catalog would be stamped with a
	// position they no longer answer for. A sweep a read fell back under
	// is this caller's alone.
	if cacheable && !fell() && l.CatalogContentSeq(ctx) == tail {
		l.publishTrackFacts(tail, rows)
	}
	return rows, nil
}

// publishTrackFacts holds a sweep made at tail, unless one made at a
// newer position is held already: the position never goes back, so the
// sweep that finished last can be the older one.
func (l *Library) publishTrackFacts(tail int64, rows []TrackFacts) {
	l.trackFacts.mu.Lock()
	defer l.trackFacts.mu.Unlock()
	if l.trackFacts.valid && l.trackFacts.tail > tail {
		return
	}
	l.trackFacts.tail, l.trackFacts.valid, l.trackFacts.rows = tail, true, rows
}

func (l *Library) sweepTrackFacts(ctx context.Context, uc *UserCtx) ([]TrackFacts, error) {
	explicit := l.explicitTrackPIDs(ctx)
	// The caller's tag rules ride the query, as they do on the
	// first-party listing path: viewVisible below covers library grants
	// only, and without the node a tag-deny account would browse tracks
	// through the compatibility surface that every other surface hides
	// and the stream refuses.
	q := visibleTracks().WhereNode(l.contentRuleNode(ctx, uc)).Build()
	var out []TrackFacts
	cursor := read.Cursor("")
	for {
		page, err := l.lib.QueryPage(ctx, q, cursor, 1000, false, model.PID(uc.CatalogPID))
		if err != nil {
			return nil, classify(err)
		}
		for _, it := range page.Items {
			// The row's own library, not the located-path cache, which
			// trails the catalog by a poll.
			if !l.viewVisible(ctx, uc, it) {
				continue
			}
			albumArtist := it.AlbumArtist
			if albumArtist == "" {
				albumArtist = it.Artist
			}
			// Mirror that fallback in pid space. The catalog's own
			// album-artist handle resolves a book's author but does not
			// fall back to the track artist, so a track with no
			// album-artist tag would otherwise come back with no
			// album-artist identity at all and drop out of the artist
			// index the display string still places it in.
			albumArtistPID := it.AlbumArtistPID
			if albumArtistPID == "" {
				albumArtistPID = it.ArtistPID
			}
			out = append(out, TrackFacts{
				PID:         itemAPIPID(it),
				Title:       it.Title,
				Artist:      it.Artist,
				AlbumArtist: albumArtist,
				Album:       it.Album,
				Genre:       it.Genre,
				TrackNo:     it.TrackNo,
				DiscNo:      it.DiscNo,
				Year:        it.Year,
				BPM:         it.BPM,
				DurationMS:  it.DurationMS,
				Codec:       it.Codec,
				Container:   it.Container,
				// Deliberately not it.Explicit, which is the episode
				// advisory pair's item half and always false for tracks.
				Explicit: explicit[it.PID],

				AlbumArtistPID: entityAPIPID(PrefixArtist, albumArtistPID),
				AlbumPID:       entityAPIPID(PrefixAlbum, it.AlbumPID),

				LibraryPID: entityAPIPID(PrefixLibrary, it.LibraryPID),
				FilePID:    FileAPIPID(string(it.FilePID)),
				Virtual:    it.Virtual,
			})
		}
		if !page.HasMore {
			return out, nil
		}
		cursor = page.Next
	}
}

// explicitTrackPIDs gathers the tracks asserting the explicit advisory
// as one tag query rather than a per-track tag read, which would be an
// N+1 on the compatibility surface's request path whenever the sweep
// re-runs. The key check keeps the common no-advisory library from
// paying the tag walk at all. Failures degrade to no labels with a
// warning rather than failing the sweep: the flag is a decoration on
// rows the sweep still owns, and 24 handler sites answer "reading the
// library failed" when the index cannot build (the genre-label
// fallback in facets is the same call). No per-item visibility pass:
// the set is only consulted for rows the sweep itself admits.
func (l *Library) explicitTrackPIDs(ctx context.Context) map[model.PID]bool {
	out := map[model.PID]bool{}
	var keys []read.TagKeyCount
	err := l.fallbackFault("advisory tags")
	if err == nil {
		keys, err = l.lib.TagKeys(ctx)
	}
	if err != nil {
		l.log.Warn("track facts: advisory tag keys unreadable; serving no explicit flags", "err", err)
		noteDegraded(ctx)
		return out
	}
	if !slices.ContainsFunc(keys, func(k read.TagKeyCount) bool { return k.Key == advisoryTagKey }) {
		return out
	}
	items, err := l.lib.Query(ctx, visibleTracks().
		WhereValues("tag."+advisoryTagKey, query.OpIn, query.Values(advisoryExplicitValues)...).
		Build(), "")
	if err != nil {
		l.log.Warn("track facts: advisory tag query failed; serving no explicit flags", "err", err)
		noteDegraded(ctx)
		return out
	}
	for _, it := range items {
		out[it.PID] = true
	}
	return out
}

// EntityFacts is what the compatibility surface shows of one artist or
// album entity.
type EntityFacts struct {
	Name string
	// Year is an album's release year by the catalog's rule over all its
	// members (AlbumYear); 0 for an artist or an undated album.
	Year int
}

// EntityFacts resolves artist and album entity pids, in one batch per
// kind, keyed by API pid. Pids naming nothing the catalog holds are
// absent.
func (l *Library) EntityFacts(ctx context.Context, apiPIDs []string) (map[string]EntityFacts, error) {
	byKind := map[read.EntityKind]map[model.PID]string{}
	for _, api := range apiPIDs {
		prefix, pid, ok := parseAPIPID(api)
		if !ok || (prefix != PrefixArtist && prefix != PrefixAlbum) {
			continue
		}
		kind, _ := entityKindForPrefix(prefix)
		if byKind[kind] == nil {
			byKind[kind] = map[model.PID]string{}
		}
		byKind[kind][pid] = api
	}
	out := make(map[string]EntityFacts, len(apiPIDs))
	for kind, back := range byKind {
		pids := make([]model.PID, 0, len(back))
		for pid := range back {
			pids = append(pids, pid)
		}
		infos, err := l.lib.EntityByPIDs(ctx, kind, pids)
		if err != nil {
			return nil, classify(err)
		}
		for pid, info := range infos {
			if info == nil {
				continue
			}
			f := EntityFacts{Name: info.Name}
			if kind == read.EntityAlbum {
				f.Year = info.Year
			}
			out[back[pid]] = f
		}
	}
	return out, nil
}

// AlbumYear is the year an album shows given its members' years, by the
// catalog's own rule, for a group the catalog holds no album for.
func AlbumYear(years []int) int { return model.AlbumYear(years) }

// FileFacts is what the compatibility surface shows of a track's primary
// file.
type FileFacts struct {
	SizeBytes   int64
	BitrateKbps int
	// AddedAt is when the catalog first saw the file.
	AddedAt time.Time
}

// fileFactsReadCap bounds the files one FileFacts call reads: the catalog
// has no batch file read, so each is a point read.
const fileFactsReadCap = 500

// fileFactsCacheCap bounds the cache, cleared whole when passed.
const fileFactsCacheCap = 50_000

// fileFactsTTL bounds how stale a held fact can be. A file's size,
// bitrate and first-seen time move only when it is replaced in place, so
// the cache is not keyed on the catalog's feed position, which moves with
// every play anywhere and would empty it on nearly every request.
const fileFactsTTL = 10 * time.Minute

// fileFactsCache holds FileFacts' answers for one catalog generation; a
// nil fact records a file that is not there.
type fileFactsCache struct {
	mu    sync.Mutex
	gen   int64
	facts map[model.PID]heldFileFacts
}

type heldFileFacts struct {
	facts *FileFacts
	at    time.Time
}

// FileFacts reads the facts of the named primary files (fl-...), keyed
// by API pid: at most fileFactsReadCap from the catalog per call, the
// rest from a best-effort cache, emptied by a replaced catalog and
// holding an answer for at most fileFactsTTL. A file that cannot be read
// is absent; the facts decorate a response the caller already scoped, so
// nothing here checks visibility and nothing fails it.
func (l *Library) FileFacts(ctx context.Context, apiFilePIDs []string) map[string]FileFacts {
	type miss struct {
		api string
		pid model.PID
	}
	gen, now := l.catalogGeneration(), time.Now()
	c := &l.trackFacts.files
	out := make(map[string]FileFacts, len(apiFilePIDs))
	var misses []miss
	c.mu.Lock()
	if c.facts == nil || c.gen != gen {
		c.gen, c.facts = gen, map[model.PID]heldFileFacts{}
	}
	for _, api := range apiFilePIDs {
		bare, ok := ParseFilePID(api)
		if !ok {
			continue
		}
		pid := model.PID(bare)
		if held, ok := c.facts[pid]; ok && now.Sub(held.at) < fileFactsTTL {
			if held.facts != nil {
				out[api] = *held.facts
			}
			continue
		}
		misses = append(misses, miss{api, pid})
	}
	c.mu.Unlock()

	fresh := map[model.PID]*FileFacts{}
	reads, failed := 0, 0
	var firstErr error
	for _, m := range misses {
		f, done := fresh[m.pid]
		if !done {
			if reads == fileFactsReadCap {
				break
			}
			reads++
			file, err := l.readFile(ctx, m.pid)
			switch {
			case err == nil:
				f = &FileFacts{SizeBytes: file.Size, BitrateKbps: file.Bitrate}
				if file.FirstSeen > 0 {
					f.AddedAt = time.Unix(0, file.FirstSeen).UTC()
				}
			case KindOf(classify(err)) != KindNotFound:
				// Not remembered: a read that failed for any other reason
				// may answer next time.
				failed++
				if firstErr == nil {
					firstErr = err
				}
				continue
			}
			fresh[m.pid] = f
		}
		if f != nil {
			out[m.api] = *f
		}
	}
	if failed > 0 {
		l.log.Warn("subsonic file facts: reads failed", "failed", failed, "err", firstErr)
	}
	if len(fresh) == 0 {
		return out
	}
	c.mu.Lock()
	if c.gen == gen {
		if len(c.facts)+len(fresh) > fileFactsCacheCap {
			c.facts = make(map[model.PID]heldFileFacts, len(fresh))
		}
		for pid, f := range fresh {
			c.facts[pid] = heldFileFacts{facts: f, at: now}
		}
	}
	c.mu.Unlock()
	return out
}
