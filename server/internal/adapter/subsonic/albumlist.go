package subsonic

import (
	"context"
	"errors"
	"math/rand/v2"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// The album lists getAlbumList and getAlbumList2 share. The orderings
// the grouped index knows - alphabetical, by year, by genre, random -
// come from it; the per-user ones from the caller's own history, stars
// and ratings. newest is the recently added list, which is what clients
// label the row; the catalog's own "newest" is by release year, which is
// byYear here.

// refusal is a request the protocol refuses with one of its codes.
type refusal struct {
	code int
	msg  string
}

// listQuery is one album-list request, parsed.
type listQuery struct {
	typ          string
	size, offset int
	from, to     int
	genre        string
}

// parseListQuery reads and checks an album-list request: a type the
// surface knows, and the parameters that type requires.
func parseListQuery(r *http.Request) (listQuery, *refusal) {
	q := listQuery{
		typ:    r.Form.Get("type"),
		size:   clampCount(formInt(r, "size", 10)),
		offset: max(formInt(r, "offset", 0), 0),
	}
	switch q.typ {
	case "":
		return q, &refusal{10, "missing type"}
	case "random", "alphabeticalByName", "alphabeticalByArtist", "newest", "recent", "frequent", "starred", "highest":
	case "byYear":
		from, okFrom := formYear(r, "fromYear")
		to, okTo := formYear(r, "toYear")
		if !okFrom || !okTo {
			return q, &refusal{10, "byYear needs a fromYear and a toYear"}
		}
		q.from, q.to = from, to
	case "byGenre":
		if q.genre = r.Form.Get("genre"); q.genre == "" {
			return q, &refusal{10, "byGenre needs a genre"}
		}
	default:
		return q, &refusal{10, "unknown album list type " + q.typ}
	}
	return q, nil
}

func formYear(r *http.Request, name string) (int, bool) {
	n, err := strconv.Atoi(strings.TrimSpace(r.Form.Get(name)))
	return n, err == nil
}

// indexOrder answers the list types the index alone can order; false for
// the ones that read the caller's state. The slice may be the index's
// own, so callers read it and never reorder it.
func indexOrder(idx *index, q listQuery) ([]*album, bool) {
	switch q.typ {
	case "random":
		albums := append([]*album(nil), idx.albums...)
		rand.Shuffle(len(albums), func(i, j int) { albums[i], albums[j] = albums[j], albums[i] })
		return albums, true
	case "alphabeticalByName":
		return idx.albums, true
	case "alphabeticalByArtist":
		return idx.albumsByArtist(), true
	case "byYear":
		// The range runs either way; a reversed one lists newest first.
		// Year zero is unknown, kept only by a range that starts there.
		lo, hi := min(q.from, q.to), max(q.from, q.to)
		var albums []*album
		for _, al := range idx.albums {
			if al.year >= lo && al.year <= hi {
				albums = append(albums, al)
			}
		}
		desc := q.from > q.to
		sort.SliceStable(albums, func(i, j int) bool {
			if desc {
				return albums[i].year > albums[j].year
			}
			return albums[i].year < albums[j].year
		})
		return albums, true
	case "byGenre":
		var albums []*album
		for _, al := range idx.albums {
			if al.hasGenre(q.genre) {
				albums = append(albums, al)
			}
		}
		return albums, true
	}
	return nil, false
}

// albumsByArtist is the index's albums by artist, then by name, ordered
// once: the order is the index's own, so every request reads one slice.
func (idx *index) albumsByArtist() []*album {
	idx.byArtistOnce.Do(func() {
		type keyed struct {
			al           *album
			artist, name string
		}
		rows := make([]keyed, len(idx.albums))
		for i, al := range idx.albums {
			rows[i] = keyed{al, strings.ToLower(al.artist), strings.ToLower(al.name)}
		}
		sort.Slice(rows, func(i, j int) bool {
			a, b := rows[i], rows[j]
			if a.artist != b.artist {
				return a.artist < b.artist
			}
			if a.name != b.name {
				return a.name < b.name
			}
			return a.al.id < b.al.id
		})
		idx.byArtist = make([]*album, len(rows))
		for i, row := range rows {
			idx.byArtist[i] = row.al
		}
	})
	return idx.byArtist
}

// pageAlbums cuts one page out of an ordered list.
func pageAlbums(albums []*album, offset, size int) []*album {
	if offset >= len(albums) {
		return nil
	}
	return albums[offset:min(offset+size, len(albums))]
}

// albumList answers one album-list request over the index: the page, the
// marks of its albums when the list's own read carried them, the refusal
// when the request is one the protocol refuses, and an error when reading
// the caller's state failed.
func (h *Handler) albumList(ctx context.Context, r *http.Request, uc *service.UserCtx, idx *index) ([]*album, map[string]service.EntityMark, *refusal, error) {
	q, ref := parseListQuery(r)
	if ref != nil {
		return nil, nil, ref, nil
	}
	albums, ok := indexOrder(idx, q)
	var marks map[string]service.EntityMark
	if !ok {
		// Past the last album the index holds there is nothing to find,
		// whatever a list would read on the way.
		if q.offset >= len(idx.albums) {
			return nil, nil, nil, nil
		}
		var err error
		if albums, marks, err = h.stateOrder(ctx, uc, idx, q); err != nil {
			return nil, nil, nil, err
		}
	}
	return pageAlbums(albums, q.offset, q.size), marks, nil, nil
}

// stateOrder answers the list types read from the caller's own state, and
// the marks the starred list's read carries.
func (h *Handler) stateOrder(ctx context.Context, uc *service.UserCtx, idx *index, q listQuery) ([]*album, map[string]service.EntityMark, error) {
	want := q.offset + q.size
	switch q.typ {
	case "newest":
		albums, err := idx.newestAlbums(ctx, h.listSource(uc, "recently-added", idx.folder), want)
		return albums, nil, err
	case "recent", "frequent":
		albums, err := h.playedAlbums(ctx, uc, idx, q.typ, want)
		return albums, nil, err
	case "starred":
		return h.starredAlbums(ctx, uc, idx)
	case "highest":
		var pids []string
		for _, al := range idx.albums {
			if al.pid != "" {
				pids = append(pids, al.pid)
			}
		}
		ratings, err := h.svc.EntityRatings(ctx, uc, pids)
		if err != nil {
			return nil, nil, err
		}
		return highestAlbums(idx.albums, ratings), nil, nil
	}
	return nil, nil, nil
}

// starredAlbums lists the caller's starred albums the index holds, in the
// order they were starred, with their marks: the list's one star read,
// which the annotate pass takes rather than reading again.
func (h *Handler) starredAlbums(ctx context.Context, uc *service.UserCtx, idx *index) ([]*album, map[string]service.EntityMark, error) {
	order, marks, err := h.svc.StarredAlbumMarks(ctx, uc)
	if err != nil {
		return nil, nil, err
	}
	var albums []*album
	for _, pid := range order {
		if al := idx.albumByID[pid]; al != nil {
			albums = append(albums, al)
		}
	}
	return albums, marks, nil
}

// playedFoldsCap bounds the callers whose played folds one index holds;
// past it one is let go to make room.
const playedFoldsCap = 32

// playedFoldsHold is how long a caller's played folds outlast a move of
// the plays position: a listener elsewhere checkpoints every few seconds,
// which would otherwise drop them between the pages of a crawl.
const playedFoldsHold = time.Minute

// playedFolds are one caller's folds of their own played lists, read at
// the plays position plays at the time at.
type playedFolds struct {
	mu       sync.Mutex
	plays    int64
	at       time.Time
	recent   fold
	frequent []*album
	ranked   bool
}

// playedFor answers the caller's played folds at plays as of now: the
// held ones while the position stands, or for playedFoldsHold after they
// were read, a fresh set otherwise.
func (idx *index) playedFor(userID string, plays int64, now time.Time) *playedFolds {
	idx.playedMu.Lock()
	defer idx.playedMu.Unlock()
	if held := idx.played[userID]; held != nil && (held.plays == plays || now.Sub(held.at) < playedFoldsHold) {
		return held
	}
	if idx.played == nil {
		idx.played = map[string]*playedFolds{}
	}
	if _, held := idx.played[userID]; !held {
		for len(idx.played) >= playedFoldsCap {
			for k := range idx.played {
				delete(idx.played, k)
				break
			}
		}
	}
	folds := &playedFolds{plays: plays, at: now}
	idx.played[userID] = folds
	return folds
}

// playedAlbums answers recent or frequent from the caller's folds, held
// on the index while no play lands anywhere and for playedFoldsHold after
// one does, so a crawl reads its list once; read afresh, and kept nowhere,
// when the plays position cannot be read. A content change replaces the
// index, and the folds with it.
func (h *Handler) playedAlbums(ctx context.Context, uc *service.UserCtx, idx *index, typ string, want int) ([]*album, error) {
	list := "recently-played"
	if typ == "frequent" {
		list = "most-played"
	}
	src := h.listSource(uc, list, idx.folder)
	folds := &playedFolds{}
	if plays, ok := h.svc.CatalogPlaysSeq(ctx); ok {
		folds = idx.playedFor(uc.ID, plays, time.Now())
	}
	folds.mu.Lock()
	defer folds.mu.Unlock()
	if typ == "recent" {
		if err := folds.recent.extend(ctx, idx, src, want); err != nil {
			return nil, err
		}
		return folds.recent.albums, nil
	}
	if !folds.ranked {
		ranked, err := frequentAlbums(ctx, idx, src, func(ctx context.Context, pids []string) (map[string]service.ItemMark, error) {
			return h.svc.ItemMarks(ctx, uc, pids)
		})
		if err != nil {
			return nil, err
		}
		folds.frequent, folds.ranked = ranked, true
	}
	return folds.frequent, nil
}

// pageSource reads one page of a list of tracks: their pids, and the
// cursor of the next page, empty after the last.
type pageSource func(ctx context.Context, cursor string) ([]string, string, error)

// browseFoldPage is the page a folded list reads at a time.
const browseFoldPage = 500

// errListFellBack is a page of a list read while a read beneath it fell
// back: no fold takes it, so the request that asked fails instead.
var errListFellBack = errors.New("subsonic: a read beneath the list fell back")

// listSource pages one of the caller's music lists, narrowed to the
// music folder when one is named. A page a read fell back under is
// errListFellBack.
func (h *Handler) listSource(uc *service.UserCtx, list, folder string) pageSource {
	read := h.readList(uc, list, folder)
	return func(ctx context.Context, cursor string) ([]string, string, error) {
		watched, fell := h.watchReads(ctx)
		pids, next, err := read(watched, cursor)
		if err == nil && fell() {
			return nil, "", errListFellBack
		}
		return pids, next, err
	}
}

// readList pages one list as listSource asks it to.
func (h *Handler) readList(uc *service.UserCtx, list, folder string) pageSource {
	if h.pages != nil {
		return h.pages(uc, list, folder)
	}
	return h.browseSource(uc, list, folder)
}

// browseSource pages one of the caller's music lists from the service,
// the music folder's own when one is named: its library's tracks in the
// list's order, however far behind the rest of the catalog's they sit.
func (h *Handler) browseSource(uc *service.UserCtx, list, folder string) pageSource {
	filter := service.ItemFilter{MediaType: "music", Library: folder}
	return func(ctx context.Context, cursor string) ([]string, string, error) {
		page, err := h.svc.Browse(ctx, uc, list, filter, 0, cursor, browseFoldPage)
		if err != nil {
			return nil, "", err
		}
		pids := make([]string, len(page.Items))
		for i, it := range page.Items {
			pids[i] = it.PID
		}
		return pids, page.Next, nil
	}
}

// fold is a list of tracks turned into the list of their albums, each
// where its first track stands, as far as it has been read, and where the
// list goes on; with keepPIDs, also the index's tracks among what was
// read. A track outside the index (another folder, a library the caller
// cannot see) is skipped.
type fold struct {
	keepPIDs bool
	albums   []*album
	pids     []string
	seen     map[*album]bool
	cursor   string
	pages    int
	done     bool
	finished bool
}

// foldPageCap bounds the pages one fold reads, across every request that
// extends it; a list longer than that is taken to end there.
const foldPageCap = 40

// extend reads on until want albums are known, every album of the index
// is, the list ends, or foldPageCap pages are read: the stop for a list
// whose albums stand where they first appear. A page is taken whole so
// the cursor stays at its end, which can leave more than want albums.
func (f *fold) extend(ctx context.Context, idx *index, src pageSource, want int) error {
	want = min(want, len(idx.albums))
	for !f.done && len(f.albums) < want {
		if err := f.page(ctx, idx, src); err != nil {
			return err
		}
	}
	return nil
}

// readAll reads the list to its end or foldPageCap pages, for a list
// whose every track counts toward its album.
func (f *fold) readAll(ctx context.Context, idx *index, src pageSource) error {
	for !f.done {
		if err := f.page(ctx, idx, src); err != nil {
			return err
		}
	}
	return nil
}

// page reads one page of the list into the fold.
func (f *fold) page(ctx context.Context, idx *index, src pageSource) error {
	if f.pages == foldPageCap {
		f.done = true
		return nil
	}
	pids, next, err := src(ctx, f.cursor)
	if err != nil {
		return err
	}
	if f.seen == nil {
		f.seen = map[*album]bool{}
	}
	f.pages++
	for _, pid := range pids {
		al := idx.albumByTrack[pid]
		if al == nil {
			continue
		}
		if f.keepPIDs {
			f.pids = append(f.pids, pid)
		}
		if !f.seen[al] {
			f.seen[al] = true
			f.albums = append(f.albums, al)
		}
	}
	f.done, f.cursor = next == "", next
	return nil
}

// finish follows what the fold has read with the index's albums it has
// not met, in the index's order: the albums past the end of a list, or
// past the pages a fold reads.
func (f *fold) finish(idx *index) {
	if f.finished {
		return
	}
	f.finished = true
	for _, al := range idx.albums {
		if !f.seen[al] {
			f.albums = append(f.albums, al)
		}
	}
}

// newestAlbums folds the recently added list as far as want albums, once
// per index: it is the same list for every caller the index was built
// for, their grants and rules being what keys it, so the pages of one
// crawl, and the next client's, carry on from where the last one
// stopped. Once the fold is done it names every album of the index, so a
// crawl reaches the whole library. The slice is shared; callers read it
// and never reorder it.
func (idx *index) newestAlbums(ctx context.Context, src pageSource, want int) ([]*album, error) {
	idx.newestMu.Lock()
	defer idx.newestMu.Unlock()
	if err := idx.newest.extend(ctx, idx, src, want); err != nil {
		return nil, err
	}
	if idx.newest.done {
		idx.newest.finish(idx)
	}
	return idx.newest.albums, nil
}

// frequentAlbums ranks the albums of the caller's played list by their
// tracks' plays added up, so it reads the whole list (to foldPageCap):
// a track on a later page still adds to an album already seen. The list
// holds only tracks with plays, so its tracks are the ones whose marks
// count.
func frequentAlbums(ctx context.Context, idx *index, src pageSource, marksFor func(context.Context, []string) (map[string]service.ItemMark, error)) ([]*album, error) {
	f := fold{keepPIDs: true}
	if err := f.readAll(ctx, idx, src); err != nil {
		return nil, err
	}
	counts, err := marksFor(ctx, f.pids)
	if err != nil {
		return nil, err
	}
	return rankByPlays(f.albums, counts), nil
}

// rankByPlays orders albums by their tracks' plays added up, the album
// played more recently first on a tie, and drops the unplayed.
func rankByPlays(albums []*album, marks map[string]service.ItemMark) []*album {
	type ranked struct {
		al     *album
		plays  int
		latest time.Time
	}
	rows := make([]ranked, 0, len(albums))
	for _, al := range albums {
		row := ranked{al: al}
		for _, tr := range al.tracks {
			m := marks[tr.PID]
			row.plays += m.PlayCount
			if m.LastPlayedAt.After(row.latest) {
				row.latest = m.LastPlayedAt
			}
		}
		if row.plays > 0 {
			rows = append(rows, row)
		}
	}
	sort.SliceStable(rows, func(i, j int) bool {
		if rows[i].plays != rows[j].plays {
			return rows[i].plays > rows[j].plays
		}
		return rows[i].latest.After(rows[j].latest)
	})
	out := make([]*album, len(rows))
	for i, row := range rows {
		out[i] = row.al
	}
	return out
}

// highestAlbums keeps the albums the caller rated, best first, in the
// order given on a tie.
func highestAlbums(albums []*album, ratings map[string]int) []*album {
	var out []*album
	for _, al := range albums {
		if _, ok := ratings[al.pid]; ok && al.pid != "" {
			out = append(out, al)
		}
	}
	sort.SliceStable(out, func(i, j int) bool { return ratings[out[i].pid] > ratings[out[j].pid] })
	return out
}
