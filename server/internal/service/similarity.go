package service

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/pidpath"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
	"github.com/colespringer/waxbin/waxerr"

	"github.com/colespringer/waxdeck/server/internal/analyzer"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/similarity"
)

// Similarity is sonic similarity and the discoveries drawn from it.
type Similarity struct {
	*core
	// sim is the in-memory sonic-similarity engine, warmed lazily from
	// waxdeck.db on first use (it only holds data when a worker has
	// posted embeddings). simSweepVersion remembers the catalog data
	// version the last analysis sweep covered, so an unchanged catalog
	// never re-walks. simDrops counts the queue rows removed because their
	// own track left or moved on, or because they rested out of attempts
	// for a week, whose audio may be queued again, and simSweptDrops is the
	// count the last sweep covered: a sweep owed one runs on an unchanged
	// catalog. simWake nudges the sweep loop when tracks may have arrived;
	// lossy, ticker-backstopped.
	// simIndex is the latest walk's analysisIndex, which the status counts
	// from; simIndexMu keeps two walks of one catalog from running at
	// once, and simIndexChecked is when the index was last walked or
	// checked against the catalog, in unix nanoseconds. simWalk is the
	// walk running off any request, under simWalkMu. workerLocalPaths
	// mirrors Config.WorkerLocalPaths.
	sim              *similarity.Engine
	simWarm          sync.Once
	simWarmErr       error
	simSweepVersion  atomic.Int64
	simDrops         atomic.Uint64
	simSweptDrops    atomic.Uint64
	simWake          chan struct{}
	simIndex         atomic.Pointer[analysisIndex]
	simIndexMu       sync.Mutex
	simIndexChecked  atomic.Int64
	simWalkMu        sync.Mutex
	simWalk          *analysisWalk
	workerLocalPaths bool
	// workerAPIConfigured mirrors Config.WorkerAPIConfigured.
	workerAPIConfigured bool
}

func newSimilarity(c *core, cfg Config) *Similarity {
	return &Similarity{
		core:                c,
		sim:                 similarity.New(),
		simWake:             make(chan struct{}, 1),
		workerLocalPaths:    cfg.WorkerLocalPaths,
		workerAPIConfigured: cfg.WorkerAPIConfigured,
	}
}

// SimilarityStatus is the coverage answer for the status surface.
type SimilarityStatus struct {
	Enabled        bool
	Model          string
	Dims           int
	EmbeddedTracks int
	TotalTracks    int
	CoveragePct    float64
	QueueDepth     int
	LastIngestAt   time.Time
}

// SimilarityWorkItem is one leased analysis assignment.
type SimilarityWorkItem struct {
	PID        string // API pid
	Essence    string
	LocalPath  string
	MediaType  string
	DurationMs int64
}

// EmbeddingUpload is one posted vector.
type EmbeddingUpload struct {
	PID     string // API pid, echoed from the work item
	Essence string
	Vector  []float32
}

// RejectedEmbedding is one refused vector and why.
type RejectedEmbedding struct {
	PID     string
	Essence string
	Code    string
	Message string
}

// EmbeddingIngestResult is one ingest batch's outcome.
type EmbeddingIngestResult struct {
	Accepted int
	Replaced int
	Rejected []RejectedEmbedding
}

// workLease is how long a leased analysis item stays invisible before
// returning to the queue on its own (a crashed worker needs no
// cleanup). Generous: remote workers pull whole FLACs.
const workLease = 10 * time.Minute

// SonicAnalyzer computes a track embedding from a source file. The
// embedded analyzer implements it in process; nil means analysis only
// happens through the external worker API.
type SonicAnalyzer interface {
	Model() string
	VectorDims() int
	AnalyzeFileWindow(ctx context.Context, path string, fromSample, toSample int64) ([]float32, error)
}

// embeddedAnalysisPace is the breath between tracks in the embedded
// analysis loop: analysis is a background chore that must never
// compete with playback for CPU, and at one track every quarter
// second a large library still finishes in days, which is fine.
const embeddedAnalysisPace = 250 * time.Millisecond

// embeddedAnalysisBatch is how many queued tracks one embedded drain leases.
const embeddedAnalysisBatch = 5

// DrainEmbeddedAnalysis leases queued tracks and analyzes them in
// process, one at a time. It returns whether any work was attempted
// (the worker loop paces on that). Filesystem failures keep their
// leased rows and re-offer when the lease lapses (a transient read
// failure heals on its own); the attempt cap is the backstop, and the
// scheduled prune queues a row it stopped again a week after its last
// lease. A decoder verdict about the bytes (undecodable, too short,
// silent) retires the row, since retrying cannot fix it and a rescan
// re-enqueues if the file changes. A track that left the library, or
// holds other audio than it was queued with, drops its row unread. A
// hand-off leaves the queue waiting for it, and one that begins mid-batch
// ends the batch with its rows still leased, as a shutdown does, which is
// no verdict on a decode it cuts short: the rows it had not settled get
// back their attempts. A catalog read that fails for any other reason,
// before the decode or as its vector is filed, keeps that row leased
// without spending its attempt, and the batch goes on, paced like an
// analyzed row since the worker loop calls again while work is attempted.
func (l *Similarity) DrainEmbeddedAnalysis(ctx context.Context, an SonicAnalyzer) (_ bool, err error) {
	if an == nil || !l.Settings.SonicAnalysisEnabled() || l.library.Maintenance() {
		return false, nil
	}
	work, err := l.db.LeaseSimilarityWork(ctx, embeddedAnalysisBatch, workLease, true)
	if err != nil {
		// A lease the caller's end cut short leased nothing and is no failure.
		if ctx.Err() != nil {
			return false, nil
		}
		return false, &Error{Kind: KindInternal, Err: err}
	}
	if len(work) == 0 {
		return false, nil
	}
	// The rows from work[settled] on are leased and not settled yet: a stop
	// for a hand-off or a shutdown gives back their attempts.
	settled := 0
	defer func() {
		if KindOf(err) == KindMaintenance || ctx.Err() != nil {
			l.refundAttempts(ctx, work[settled:])
		}
	}()
	for i, w := range work {
		if ctx.Err() != nil {
			return true, nil
		}
		it, f, err := l.sonicTrack(ctx, model.PID(w.ItemPID), w.Essence)
		switch {
		case errors.Is(err, errAnalysisStale):
			l.log.Debug("dropped a sonic analysis: the track no longer holds its audio", "pid", w.ItemPID, "essence", w.Essence)
			fallthrough
		case KindOf(err) == KindNotFound:
			l.dropSonicRow(ctx, w.Essence)
			settled = i + 1
			continue
		case err != nil:
			if err = l.keepUnread(ctx, err, w); err != nil {
				return true, err
			}
			settled = i + 1
			if !restBetweenTracks(ctx) {
				return true, nil
			}
			continue
		}
		var vec []float32
		from, to, err := sonicWindow(it)
		if err == nil {
			vec, err = an.AnalyzeFileWindow(ctx, string(f.Path), from, to)
		}
		var pathErr *fs.PathError
		switch {
		case ctx.Err() != nil:
			// A shutdown cut the decode short: no verdict on the audio, and
			// the row re-offers when its lease lapses.
			return true, nil
		case errors.As(err, &pathErr):
			// A filesystem-level failure (a locked file, a NAS hiccup, a
			// slow mount) keeps the row leased: it re-offers when the
			// lease lapses; the attempt cap stops it, for a week.
			l.log.Warn("embedded analysis could not read a track; it will retry", "pid", w.ItemPID, "err", err)
		case err != nil:
			// A verdict on the audio (undecodable, too short, silent, a
			// window with nothing to place it by) that retrying cannot move.
			l.retireAnalysis(ctx, w, err.Error())
		default:
			res, err := l.IngestEmbeddings(ctx, an.Model(), an.VectorDims(), []EmbeddingUpload{{
				PID:     apiPID(PrefixTrack, model.PID(w.ItemPID)),
				Essence: w.Essence,
				Vector:  vec,
			}})
			if err != nil {
				return true, err
			}
			for _, rej := range res.Rejected {
				// Only a refusal of the vector itself judges the audio. One for
				// audio that changed during the decode, or for a track the
				// catalog could not read, was settled by the ingest.
				if rej.Code == string(KindInvalid) {
					l.retireAnalysis(ctx, w, rej.Message)
				}
			}
		}
		settled = i + 1
		// Paced whatever came of it: the decode is the cost.
		if !restBetweenTracks(ctx) {
			return true, nil
		}
	}
	return true, nil
}

// restBetweenTracks waits out embeddedAnalysisPace; false when ctx ended
// first.
func restBetweenTracks(ctx context.Context) bool {
	select {
	case <-ctx.Done():
		return false
	case <-time.After(embeddedAnalysisPace):
		return true
	}
}

// keepUnread settles a leased row whose catalog read failed, which is no
// verdict on its track: the row stays leased, to re-offer when its lease
// lapses, and gets back the attempt the lease charged, since the read
// attempted nothing, and keepUnread returns nil so the batch goes on. A
// hand-off is returned with the row unsettled: it ends the batch (every
// read fails then), whose owner settles what it left.
func (l *Similarity) keepUnread(ctx context.Context, err error, w wdb.SimilarityWork) error {
	if KindOf(err) == KindMaintenance {
		return err
	}
	// A read the caller's own end cut short is no failure to report.
	if ctx.Err() == nil {
		l.log.Warn("could not read a track for analysis; it will retry", "pid", w.ItemPID, "essence", w.Essence, "err", err)
	}
	l.refundAttempts(ctx, []wdb.SimilarityWork{w})
	return nil
}

// refundAttempts gives back the attempt a lease charged each row, on a
// context the caller's end does not cut short: a shutdown is no verdict on
// a row either.
func (l *Similarity) refundAttempts(ctx context.Context, rows []wdb.SimilarityWork) {
	ctx = context.WithoutCancel(ctx)
	for _, w := range rows {
		if err := l.db.RefundSimilarityAttempt(ctx, w.Essence); err != nil {
			l.log.Warn("giving back an analysis attempt", "essence", w.Essence, "err", err)
		}
	}
}

// dropSonicRow drops the queue row of key, whose own track left the
// catalog or holds other audio now. Another track can hold that audio
// still, so the next sweep queues it again even if nothing else in the
// catalog moved.
func (l *Similarity) dropSonicRow(ctx context.Context, key string) {
	l.completeAnalysis(ctx, key)
	l.sweepOwed(1)
}

// sweepOwed has the next sweep walk the catalog though its data version
// did not move, for n queue rows removed whose audio may be queued again.
func (l *Similarity) sweepOwed(n int64) {
	l.simDrops.Add(uint64(n))
	l.wakeup()
}

// sonicTrack reads a queued track as the catalog holds it now: its view,
// and the file its analysis key is taken from. errAnalysisStale when they
// hold other audio than key; not-found when the track or its file is gone.
func (l *Similarity) sonicTrack(ctx context.Context, pid model.PID, key string) (*model.ItemView, *model.File, error) {
	it, f, err := l.Playback.itemFile(ctx, pid)
	if err != nil {
		return nil, nil, err
	}
	if analysisKey(f.EssenceHash, it) != key {
		return it, f, errAnalysisStale
	}
	return it, f, nil
}

// errNoWindow is a carved track whose frame window cannot be placed in
// samples: its file declares no rate, or the window ends before it starts.
var errNoWindow = errors.New("the track's window cannot be placed in its file")

// sonicWindow is the sample window a track's view places it at in its
// file (to 0 running to the end), [0, 0) for a whole file: read off the
// view its analysis key was taken from.
func sonicWindow(it *model.ItemView) (from, to int64, err error) {
	// Placed the way streaming places it.
	loc := pidpath.Location{FilePID: it.FilePID, SampleRate: it.SampleRate,
		Virtual: it.Virtual, StartFrames: it.StartFrames, EndFrames: it.EndFrames}
	switch from, to, err = loc.Span(); {
	case err != nil:
		return 0, 0, fmt.Errorf("%w: the file declares no sample rate", errNoWindow)
	case to > 0 && to < from:
		return 0, 0, fmt.Errorf("%w: it ends before it starts", errNoWindow)
	}
	return from, to, nil
}

// retireAnalysis rests a key whose audio cannot be analyzed, and says so.
func (l *Similarity) retireAnalysis(ctx context.Context, w wdb.SimilarityWork, reason string) {
	l.log.Warn("sonic analysis cannot read a track; it rests until its audio changes", "pid", w.ItemPID, "reason", reason)
	if err := l.db.RetireSimilarityWork(ctx, w.Essence, reason); err != nil {
		l.log.Warn("retiring analysis work", "essence", w.Essence, "err", err)
	}
}

// analysisKey names the audio a vector describes: the file's essence, or
// for a cue-carved track the essence and its frame window, so the tracks
// of one rip never share a vector. Opaque to workers.
func analysisKey(essence string, it *model.ItemView) string {
	if essence == "" || !it.Virtual {
		return essence
	}
	return fmt.Sprintf("%s%s%d-%d", essence, wdb.CarvedKeyMark, it.StartFrames, it.EndFrames)
}

// keyAudio is the file essence an analysis key belongs to.
func keyAudio(key string) string {
	essence, _, _ := strings.Cut(key, wdb.CarvedKeyMark)
	return essence
}

func (l *Similarity) completeAnalysis(ctx context.Context, essence string) {
	if err := l.db.CompleteSimilarityWork(ctx, essence); err != nil {
		l.log.Warn("retiring analysis work", "essence", essence, "err", err)
	}
}

// warmSimilarity loads stored vectors and edges into the in-memory
// engine once. Cheap when empty (the common case without a worker).
func (l *Similarity) warmSimilarity(ctx context.Context) error {
	l.simWarm.Do(func() {
		_, _, err := l.db.Embeddings(ctx, func(e wdb.Embedding) {
			if vec := similarity.Decode(e.Vector); vec != nil {
				l.sim.Load(e.Essence, vec)
			}
		})
		if err != nil {
			l.simWarmErr = err
			return
		}
		edges := map[string][]similarity.Edge{}
		err = l.db.GraphEdges(ctx, func(g wdb.GraphEdge) {
			edges[g.Essence] = append(edges[g.Essence], similarity.Edge{
				Neighbor: g.Neighbor, Distance: g.Distance,
			})
		})
		if err != nil {
			l.simWarmErr = err
			return
		}
		for essence, list := range edges {
			l.sim.LoadEdges(essence, list)
		}
	})
	if l.simWarmErr != nil {
		return &Error{Kind: KindInternal, Err: l.simWarmErr}
	}
	return nil
}

// StatusFor answers coverage. enabled reports whether an
// analyzer can feed the surface. The counts are the whole library's for
// a caller of full reach and the caller's own tracks' otherwise, both
// read off the latest analysisIndex, so they are the sweep's own reading
// of the library: a vector kept for a trashed track counts nowhere, and
// audio the analyzer judged unreadable leaves the total along with the
// queue.
func (l *Similarity) StatusFor(ctx context.Context, uc *UserCtx) (SimilarityStatus, error) {
	idx, err := l.statusAnalysisIndex(ctx)
	if err != nil {
		return SimilarityStatus{}, err
	}
	stored, err := l.db.StoredVectors(ctx)
	if err != nil {
		return SimilarityStatus{}, &Error{Kind: KindInternal, Err: err}
	}
	queue, err := l.db.SimilarityQueueStates(ctx)
	if err != nil {
		return SimilarityStatus{}, &Error{Kind: KindInternal, Err: err}
	}
	cov, err := l.coverageOf(ctx, uc, idx, stored.Keys, queue)
	if err != nil {
		return SimilarityStatus{}, err
	}
	st := SimilarityStatus{
		Enabled:        l.analysisOn(),
		Model:          stored.Model,
		Dims:           stored.Dims,
		EmbeddedTracks: cov.embedded,
		TotalTracks:    cov.total(),
		QueueDepth:     cov.queued,
		LastIngestAt:   stored.LastIngest,
	}
	if st.TotalTracks > 0 {
		st.CoveragePct = float64(st.EmbeddedTracks) / float64(st.TotalTracks) * 100
	}
	return st, nil
}

// analysisOn reports whether an analyzer can feed the sonic surface: the
// embedded one, or an external worker holding a token. Sweeps run only
// then.
func (l *Similarity) analysisOn() bool {
	return l.Settings.SonicAnalysisEnabled() || l.workerAPIConfigured
}

// analysisCoverage is the status counts: tracks holding a vector, tracks
// waiting in the queue, and the rest: tracks no sweep has queued yet,
// and those out of attempts with their audio never judged, which stay
// in the total so an outage shows, until the weekly prune clears them for
// another round.
type analysisCoverage struct{ embedded, queued, pending int }

func (c analysisCoverage) total() int { return c.embedded + c.queued + c.pending }

// coverageOf counts the index's tracks the caller may enumerate against
// the stored vectors and the queue, leaving out those the analyzer
// judged it cannot read: nothing will ever drain them. Library grants are
// read off the index; tag rules need the catalog, one count per chunk of
// each class.
func (l *Similarity) coverageOf(ctx context.Context, uc *UserCtx, idx *analysisIndex, stored map[string]bool, queue map[string]wdb.QueueState) (analysisCoverage, error) {
	const embedded, queued, pending = 0, 1, 2
	var counts [3]int
	var pids [3][]string
	ruled := tagRestricted(uc)
	for _, t := range idx.tracks {
		if !uc.AllLibraries && !uc.Libraries[t.library] {
			continue
		}
		class := pending
		if stored[t.key] {
			class = embedded
		} else if state, ok := queue[t.key]; ok {
			switch state {
			case wdb.QueueWaiting:
				class = queued
			case wdb.QueueRetired:
				continue
			}
		}
		if ruled {
			pids[class] = append(pids[class], string(t.pid))
		} else {
			counts[class]++
		}
	}
	if ruled {
		rule := l.Grants.contentRuleNode(ctx, uc)
		base := func() *query.Builder { return visibleItems().WhereNode(rule) }
		for class := range pids {
			n, err := l.countAmong(ctx, pids[class], base)
			if err != nil {
				return analysisCoverage{}, err
			}
			counts[class] = n
		}
	}
	return analysisCoverage{embedded: counts[embedded], queued: counts[queued], pending: counts[pending]}, nil
}

// countAmong counts the items base selects among the bare pids, once per
// 400 of them, under the engine's 500-value membership test.
func (l *Similarity) countAmong(ctx context.Context, pids []string, base func() *query.Builder) (int, error) {
	n := 0
	for start := 0; start < len(pids); start += 400 {
		chunk := pids[start:min(start+400, len(pids))]
		c, err := l.lib.Count(ctx, base().WhereValues("pid", query.OpIn, query.Values(chunk)...).Build(), "")
		if err != nil {
			return 0, classify(err)
		}
		n += c
	}
	return n, nil
}

// analysisIndex is one walk of the catalog, read for sonic analysis:
// every visible music track the sweep queues, in title order, and the
// keys only tracks under the analysis floor hold. Those stay live (a
// vector one has is kept) but are never queued.
type analysisIndex struct {
	version int64
	tracks  []analysisTrack
	refused map[string]bool
}

// analysisTrack is one track the sweep queues: its bare pid, the key its
// vector lives under, and the bare pid of the library its primary file
// sits in, which is what a grant reaches it through (viewVisible's rule).
type analysisTrack struct {
	pid     model.PID
	key     string
	library string
}

// live is every key the walk found audio under, the refused included.
func (x *analysisIndex) live() map[string]bool {
	live := make(map[string]bool, len(x.tracks)+len(x.refused))
	for _, t := range x.tracks {
		live[t.key] = true
	}
	for key := range x.refused {
		live[key] = true
	}
	return live
}

// walkAnalysis reads the catalog, as of version, into an analysisIndex.
func (l *Similarity) walkAnalysis(ctx context.Context, version int64) (*analysisIndex, error) {
	defaultUser, err := l.lib.DefaultUser(ctx)
	if err != nil {
		return nil, classify(err)
	}
	idx := &analysisIndex{version: version, refused: map[string]bool{}}
	// Carved siblings share one file: read its essence once.
	essences := map[model.PID]string{}
	q := visibleItems().Where("kind", query.OpIs, string(model.KindTrack)).OrderBy("title", false).Build()
	cursor := ""
	for {
		page, err := l.lib.QueryPage(ctx, q, read.Cursor(cursor), 500, false, defaultUser.PID)
		if err != nil {
			return nil, classify(err)
		}
		for _, it := range page.Items {
			essence, ok := essences[it.FilePID]
			if !ok {
				f, err := l.catalogFile(ctx, it.FilePID)
				switch {
				case err == nil:
					essence = f.EssenceHash
				case waxerr.CodeOf(err) != waxerr.CodeNotFound:
					// Unread is not gone: a walk that cannot read the
					// catalog answers nothing, and runs again next time.
					return nil, classify(err)
				}
				essences[it.FilePID] = essence
			}
			if essence == "" {
				continue
			}
			key := analysisKey(essence, it)
			// Under the floor the analyzer refuses it, every time it is asked.
			if analyzer.TooShort(it.DurationMS) {
				idx.refused[key] = true
				continue
			}
			idx.tracks = append(idx.tracks, analysisTrack{pid: it.PID, key: key, library: string(it.LibraryPID)})
		}
		if !page.HasMore {
			break
		}
		cursor = string(page.Next)
	}
	// A key a long enough track holds is queued, whatever another track
	// of the audio reads, so the sweep must not drop its row.
	for _, t := range idx.tracks {
		delete(idx.refused, t.key)
	}
	return idx, nil
}

// analysisIndexAt answers the index of catalog version, walking one
// unless the latest is of it. DataVersion is only ever compared for
// equality.
func (l *Similarity) analysisIndexAt(ctx context.Context, version int64) (*analysisIndex, error) {
	l.simIndexMu.Lock()
	defer l.simIndexMu.Unlock()
	if cur := l.simIndex.Load(); cur != nil && cur.version == version {
		return cur, nil
	}
	idx, err := l.walkAnalysis(ctx, version)
	if err != nil {
		return nil, err
	}
	l.simIndex.Store(idx)
	l.simIndexChecked.Store(time.Now().UnixNano())
	return idx, nil
}

// statusIndexReuse is how long the latest walk answers the status before
// it is checked against the catalog again.
const statusIndexReuse = 30 * time.Second

// statusAnalysisIndex answers the index the status counts from. Before
// the first walk it waits for one, run off the request so a caller that
// gives up does not cancel it. After that it answers the latest walk at
// once and has a fresh one start in the background, at most once a
// statusIndexReuse and whether or not analysis is on: departures reach a
// sweep only at its backstop, and a sweep that keeps failing never walks.
func (l *Similarity) statusAnalysisIndex(ctx context.Context) (*analysisIndex, error) {
	if cur := l.simIndex.Load(); cur != nil {
		if !l.library.Maintenance() {
			l.refreshAnalysisIndex()
		}
		return cur, nil
	}
	walk := l.walkInBackground()
	if walk == nil {
		// A Library with no supervisor to run it on walks here.
		version, err := l.lib.DataVersion(ctx)
		if err != nil {
			return nil, classify(err)
		}
		return l.analysisIndexAt(ctx, version)
	}
	select {
	case <-walk.done:
	case <-ctx.Done():
		return nil, ctx.Err()
	}
	if walk.err != nil {
		return nil, walk.err
	}
	if cur := l.simIndex.Load(); cur != nil {
		return cur, nil
	}
	return nil, &Error{Kind: KindInternal, Err: errors.New("walking the library for the analysis status failed")}
}

// refreshAnalysisIndex starts a walk in the background, which reads the
// catalog only if it moved past the latest, unless one was checked
// within statusIndexReuse.
func (l *Similarity) refreshAnalysisIndex() {
	now := time.Now().UnixNano()
	last := l.simIndexChecked.Load()
	if now-last < int64(statusIndexReuse) || !l.simIndexChecked.CompareAndSwap(last, now) {
		return
	}
	l.walkInBackground()
}

// analysisWalk is a walk run off any request: done closes when it ends,
// and err, set before that, is what it ended with.
type analysisWalk struct {
	done chan struct{}
	err  error
}

// walkInBackground answers the walk in flight, starting one under the
// supervisor when none is; nil when the Library has no supervisor.
func (l *Similarity) walkInBackground() *analysisWalk {
	if l.workers == nil || l.procCtx == nil {
		return nil
	}
	l.simWalkMu.Lock()
	if w := l.simWalk; w != nil {
		l.simWalkMu.Unlock()
		return w
	}
	w := &analysisWalk{done: make(chan struct{})}
	l.simWalk = w
	l.simWalkMu.Unlock()
	end := func(err error) {
		w.err = err
		l.simWalkMu.Lock()
		l.simWalk = nil
		l.simWalkMu.Unlock()
		close(w.done)
	}
	started := l.workers.GoOnce(l.procCtx, "analysis-index", func(ctx context.Context) (err error) {
		defer func() { end(err) }()
		version, err := l.lib.DataVersion(ctx)
		if err != nil {
			return classify(err)
		}
		_, err = l.analysisIndexAt(ctx, version)
		return err
	})
	if !started {
		end(context.Canceled)
	}
	return w
}

// LeaseSimilarityWork leases a work batch for a polling worker. A hand-off
// hands out nothing, since a lease spends an attempt on work that cannot be
// read. A track the catalog no longer has, or one holding other audio than
// its work names, drops its row: a worker would pull audio its report is
// then refused for. Any other failed read keeps its row leased, its attempt
// given back, and leaves it out of the batch. A hand-off that begins
// mid-batch ends it, as does a request that ends mid-batch: nothing of it
// reaches the worker, and every row it kept stays leased with its attempt
// given back.
func (l *Similarity) LeaseSimilarityWork(ctx context.Context, limit int, windows bool) (_ []SimilarityWorkItem, err error) {
	if l.library.Maintenance() {
		return nil, nil
	}
	work, err := l.db.LeaseSimilarityWork(ctx, limit, workLease, windows)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	// Snapshot the root count once: the single-root local-path optimization
	// only holds when exactly one root exists, and a runtime-added root must
	// disable it for the rest of this batch consistently.
	singleRoot := len(l.Roots.libraryRoots()) == 1
	out := make([]SimilarityWorkItem, 0, len(work))
	// A batch that stops reaches no worker: the rows read ready, and those
	// from work[settled] on, not read yet, get back their attempts.
	var ready []wdb.SimilarityWork
	settled := 0
	defer func() {
		if err != nil {
			l.refundAttempts(ctx, append(ready, work[settled:]...))
		}
	}()
	for i, w := range work {
		if err := ctx.Err(); err != nil {
			return nil, &Error{Kind: KindInternal, Err: err}
		}
		it, f, err := l.sonicTrack(ctx, model.PID(w.ItemPID), w.Essence)
		switch {
		case errors.Is(err, errAnalysisStale):
			l.log.Debug("dropped a sonic analysis: the track no longer holds its audio", "pid", w.ItemPID, "essence", w.Essence)
			fallthrough
		case KindOf(err) == KindNotFound:
			l.dropSonicRow(ctx, w.Essence)
			settled = i + 1
			continue
		case err != nil:
			if err = l.keepUnread(ctx, err, w); err != nil {
				return nil, err
			}
			settled = i + 1
			continue
		}
		item := SimilarityWorkItem{
			PID:        apiPID(PrefixTrack, model.PID(w.ItemPID)),
			Essence:    w.Essence,
			MediaType:  "music",
			DurationMs: it.DurationMS,
		}
		// A carved track's file is the whole rip; only its audio URL
		// serves the window.
		if l.workerLocalPaths && singleRoot && !it.Virtual {
			item.LocalPath = string(f.RelPath)
		}
		out = append(out, item)
		ready = append(ready, w)
		settled = i + 1
	}
	return out, nil
}

// IngestEmbeddings records a worker's batch: vectors persist by analysis
// key, the engine updates its neighbor graph incrementally, and the touched
// edge lists persist. A new model replaces coverage (models never mix). A
// vector for audio its track no longer holds, a trashed track's included, is
// refused as not-found; one whose track the catalog could not read is
// refused as internal, its work left leased to come back. A hand-off ends
// the report, as does a request that ends mid-report.
func (l *Similarity) IngestEmbeddings(ctx context.Context, mdl string, dims int, batch []EmbeddingUpload) (EmbeddingIngestResult, error) {
	if err := l.warmSimilarity(ctx); err != nil {
		return EmbeddingIngestResult{}, err
	}
	storedCount, storedModel, _, _, err := l.db.EmbeddingStats(ctx)
	if err != nil {
		return EmbeddingIngestResult{}, &Error{Kind: KindInternal, Err: err}
	}
	if storedCount > 0 && storedModel != mdl {
		l.log.Info("similarity model switch; dropping stored vectors",
			"stored", storedModel, "new", mdl)
		if _, err := l.db.DeleteEmbeddingsNotModel(ctx, mdl); err != nil {
			return EmbeddingIngestResult{}, &Error{Kind: KindInternal, Err: err}
		}
		l.sim.Reset()
	}
	var res EmbeddingIngestResult
	for _, up := range batch {
		if err := ctx.Err(); err != nil {
			return res, &Error{Kind: KindInternal, Err: err}
		}
		reject := func(code, msg string) {
			res.Rejected = append(res.Rejected, RejectedEmbedding{
				PID: up.PID, Essence: up.Essence, Code: code, Message: msg,
			})
		}
		prefix, pid, ok := parseAPIPID(up.PID)
		if !ok || prefix != PrefixTrack {
			reject("invalid-request", "malformed track pid")
			continue
		}
		if up.Essence == "" || len(up.Essence) > 128 {
			reject("invalid-request", "malformed essence")
			continue
		}
		if len(up.Vector) != dims {
			reject("invalid-request", "vector length disagrees with dims")
			continue
		}
		// A worker reads the audio by pid, so a vector reported after the
		// track's audio changed may be of either: filed under neither, and
		// its work dropped rather than handed out under the track again.
		held, err := l.holdsSonicKey(ctx, pid, up.Essence)
		if err != nil {
			if err := l.keepUnread(ctx, err, wdb.SimilarityWork{Essence: up.Essence, ItemPID: string(pid)}); err != nil {
				return res, err
			}
			reject(string(KindInternal), "the catalog could not be read to check this vector; its work comes back when its lease lapses")
			continue
		}
		if !held {
			l.log.Debug("refused a vector: the track no longer holds its audio", "pid", string(pid), "essence", up.Essence)
			l.dropSonicRow(ctx, up.Essence)
			reject(string(KindNotFound), "the track no longer holds this audio")
			continue
		}
		edges, updated, ok := l.sim.Ingest(up.Essence, up.Vector)
		if !ok {
			reject("invalid-request", "vector is zero or wrong dimensionality")
			continue
		}
		replaced, err := l.db.UpsertEmbedding(ctx, wdb.Embedding{
			Essence: up.Essence,
			ItemPID: string(pid),
			Model:   mdl,
			Dims:    dims,
			Vector:  similarity.Encode(mustVector(l.sim, up.Essence)),
		})
		if err != nil {
			return res, &Error{Kind: KindInternal, Err: err}
		}
		if err := l.persistEdges(ctx, up.Essence, edges); err != nil {
			return res, err
		}
		for node, list := range updated {
			if err := l.persistEdges(ctx, node, list); err != nil {
				return res, err
			}
		}
		if err := l.db.CompleteSimilarityWork(ctx, up.Essence); err != nil {
			l.log.Warn("completing analysis work", "essence", up.Essence, "err", err)
		}
		if replaced {
			res.Replaced++
		} else {
			res.Accepted++
		}
	}
	return res, nil
}

// holdsSonicKey reports whether the catalog, read now, files the track's
// audio under key. A track in the trash holds none: it has no file to check
// key against, and a rewrite before the trash would have had a worker pull
// other audio by its pid.
func (l *Similarity) holdsSonicKey(ctx context.Context, pid model.PID, key string) (bool, error) {
	_, _, err := l.sonicTrack(ctx, pid, key)
	switch {
	case err == nil:
		return true, nil
	case errors.Is(err, errAnalysisStale), KindOf(err) == KindNotFound:
		return false, nil
	}
	return false, err
}

// mustVector reads back the normalized stored vector for persistence
// (Ingest normalizes in place under its own lock).
func mustVector(e *similarity.Engine, essence string) []float32 {
	v, _ := e.Vector(essence)
	return v
}

func (l *Similarity) persistEdges(ctx context.Context, essence string, edges []similarity.Edge) error {
	rows := make([]wdb.GraphEdge, len(edges))
	for i, e := range edges {
		rows[i] = wdb.GraphEdge{Essence: essence, Rank: i, Neighbor: e.Neighbor, Distance: e.Distance}
	}
	if err := l.db.ReplaceGraphNode(ctx, essence, rows); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// similaritySchedule paces the sweep loop: a sweep shortly after boot,
// one once arrivals have stopped for settle, and the backstop, which
// also sweeps a scan that never goes quiet and covers what no wakeup
// names (departures, and edits that swap a track's audio).
type similaritySchedule struct {
	first, settle, backstop time.Duration
}

var defaultSimilaritySchedule = similaritySchedule{
	first:    30 * time.Second,
	settle:   30 * time.Second,
	backstop: 10 * time.Minute,
}

// RunSimilaritySweeps keeps the analysis queue reconciled with the
// catalog until ctx ends.
func (l *Similarity) RunSimilaritySweeps(ctx context.Context) error {
	return l.runSimilaritySweeps(ctx, defaultSimilaritySchedule)
}

func (l *Similarity) runSimilaritySweeps(ctx context.Context, s similaritySchedule) error {
	first := time.NewTimer(s.first)
	defer first.Stop()
	tick := time.NewTicker(s.backstop)
	defer tick.Stop()
	// Armed while a wakeup's sweep is owed, and restarted by every
	// arrival, so a scan is walked once when it goes quiet rather than
	// once per burst of it.
	settle := time.NewTimer(s.settle)
	settle.Stop()
	defer settle.Stop()
	retried := false
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-l.simWake:
			settle.Reset(s.settle)
			continue
		case <-first.C:
		case <-tick.C:
		case <-settle.C:
		}
		settle.Stop() // whatever was owed, this walk covers
		if _, err := l.Sweep(ctx); err != nil {
			if ctx.Err() != nil {
				return nil
			}
			l.log.Warn("similarity sweep", "err", err)
			// One prompt retry for a passing failure; a lasting one
			// waits for the backstop rather than logging every settle.
			if !retried {
				settle.Reset(s.settle)
			}
			retried = true
			continue
		}
		retried = false
	}
}

// wakeup tells the sweep loop that tracks may have arrived.
func (l *Similarity) wakeup() {
	select {
	case l.simWake <- struct{}{}:
	default:
	}
}

// Sweep reconciles the analysis queue with the catalog: new
// music tracks enqueue, embeddings whose audio left the catalog prune
// (edges removed, affected nodes queued for lazy recompute), and
// pending backfills recompute. Its walk is the analysisIndex the status
// counts from. It short-circuits when the catalog data version has not
// moved since the last sweep and no queue row was dropped for its track or
// pruned out of attempts since. Returns true when it did meaningful work
// (the worker loop uses that to pace itself).
func (l *Similarity) Sweep(ctx context.Context) (bool, error) {
	if !l.analysisOn() || l.library.Maintenance() {
		return false, nil
	}
	if err := l.warmSimilarity(ctx); err != nil {
		return false, err
	}
	worked, err := l.drainBackfill(ctx)
	if err != nil {
		return worked, err
	}
	// Read before the walk, so a row dropped while it runs owes the next.
	drops := l.simDrops.Load()
	version, err := l.lib.DataVersion(ctx)
	if err != nil {
		return worked, classify(err)
	}
	if version == l.simSweepVersion.Load() && drops == l.simSweptDrops.Load() {
		return worked, nil
	}
	// A walk that cannot read the catalog prunes nothing.
	idx, err := l.analysisIndexAt(ctx, version)
	if err != nil {
		return worked, err
	}
	for _, t := range idx.tracks {
		if !l.sim.Has(t.key) {
			if err := l.db.EnqueueSimilarity(ctx, t.key, string(t.pid)); err != nil {
				return worked, &Error{Kind: KindInternal, Err: err}
			}
			worked = true
		}
	}
	live := idx.live()
	// Rows whose audio left the catalog, resting ones included, and rows
	// of audio under the floor, queued before the scan read how short it
	// is: neither is ever analyzed.
	queue, err := l.db.SimilarityQueueStates(ctx)
	if err != nil {
		return worked, &Error{Kind: KindInternal, Err: err}
	}
	for key := range queue {
		if !live[key] || idx.refused[key] {
			l.completeAnalysis(ctx, key)
		}
	}
	// Prune vectors whose audio left the catalog. The essence keying
	// exists to survive retags and moves (the item row stays); a truly
	// deleted recording's vector is dead weight, and if the audio ever
	// returns one re-analysis is the honest price.
	var stale []string
	owner := map[string]model.PID{}
	_, _, err = l.db.Embeddings(ctx, func(e wdb.Embedding) {
		if !live[e.Essence] {
			stale = append(stale, e.Essence)
			owner[e.Essence] = model.PID(e.ItemPID)
		}
	})
	if err != nil {
		return worked, &Error{Kind: KindInternal, Err: err}
	}
	// A trashed item is archived and has lost its file row, exactly like a
	// permanently deleted one, so absence from the live set cannot tell
	// the two apart on its own. The trash journal can, and it is the
	// distinction that matters: trashing is restorable and leaves the
	// bytes on disk, so pruning here charged a full
	// re-analysis for every trash and restore of a file that never moved.
	// RestorableTrash is batched and index-served, and absence from its
	// map is the answer for "nothing restorable".
	//
	// It keys on the item the vector was recorded against. Two items
	// sharing one essence are already collapsed by that recording, so the
	// residual case - the recorded item purged while a second item with
	// the same audio is only trashed - prunes and costs one re-analysis
	// on restore, which is the pre-existing price rather than a new one.
	if len(stale) > 0 {
		pids := make([]model.PID, 0, len(stale))
		for _, essence := range stale {
			pids = append(pids, owner[essence])
		}
		restorable, err := l.lib.RestorableTrash(ctx, pids)
		if err != nil {
			return worked, classify(err)
		}
		// A trashed rip is logged against one of its tracks: a key kept
		// keeps every key of its audio.
		kept := map[string]bool{}
		for _, key := range stale {
			if len(restorable[owner[key]]) > 0 {
				kept[keyAudio(key)] = true
			}
		}
		stale = slices.DeleteFunc(stale, func(key string) bool { return kept[keyAudio(key)] })
	}
	for _, essence := range stale {
		affected, err := l.db.RemoveEmbedding(ctx, essence)
		if err != nil {
			return worked, &Error{Kind: KindInternal, Err: err}
		}
		l.sim.Remove(essence)
		if err := l.db.AddSimilarityBackfill(ctx, affected); err != nil {
			return worked, &Error{Kind: KindInternal, Err: err}
		}
		worked = true
	}
	if _, err := l.drainBackfill(ctx); err != nil {
		return worked, err
	}
	l.simSweepVersion.Store(version)
	l.simSweptDrops.Store(drops)
	return worked, nil
}

// drainBackfill recomputes queued nodes' edge lists.
func (l *Similarity) drainBackfill(ctx context.Context) (bool, error) {
	worked := false
	for {
		batch, err := l.db.TakeSimilarityBackfill(ctx, 100)
		if err != nil {
			return worked, &Error{Kind: KindInternal, Err: err}
		}
		if len(batch) == 0 {
			return worked, nil
		}
		for _, essence := range batch {
			edges, ok := l.sim.Recompute(essence)
			if !ok {
				continue
			}
			if err := l.persistEdges(ctx, essence, edges); err != nil {
				return worked, err
			}
			worked = true
		}
	}
}
