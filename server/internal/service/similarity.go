package service

import (
	"context"
	"errors"
	"io/fs"
	"slices"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/similarity"
)

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
	AnalyzeFile(ctx context.Context, path string) ([]float32, error)
}

// embeddedAnalysisPace is the breath between tracks in the embedded
// analysis loop: analysis is a background chore that must never
// compete with playback for CPU, and at one track every quarter
// second a large library still finishes in days, which is fine.
const embeddedAnalysisPace = 250 * time.Millisecond

// DrainEmbeddedAnalysis leases queued tracks and analyzes them in
// process, one at a time. It returns whether any work was attempted
// (the worker loop paces on that). Filesystem failures keep their
// leased rows and re-offer when the lease lapses (a transient read
// failure heals on its own; the attempt cap is the backstop); a
// decoder verdict about the bytes (undecodable, too short, silent)
// retires the row, since retrying cannot fix it and a rescan
// re-enqueues if the file changes.
func (l *Library) DrainEmbeddedAnalysis(ctx context.Context, an SonicAnalyzer) (bool, error) {
	if an == nil || !l.SonicAnalysisEnabled() {
		return false, nil
	}
	work, err := l.db.LeaseSimilarityWork(ctx, 5, workLease)
	if err != nil {
		return false, &Error{Kind: KindInternal, Err: err}
	}
	if len(work) == 0 {
		return false, nil
	}
	for _, w := range work {
		if err := ctx.Err(); err != nil {
			return true, nil
		}
		// Catalog misses retire the row: the item left the library,
		// and a return re-enqueues under a fresh data version.
		it, err := l.lib.Get(ctx, model.PID(w.ItemPID))
		if err != nil {
			l.completeAnalysis(ctx, w.Essence)
			continue
		}
		f, err := l.lib.File(ctx, it.FilePID)
		if err != nil {
			l.completeAnalysis(ctx, w.Essence)
			continue
		}
		vec, err := an.AnalyzeFile(ctx, string(f.Path))
		if err != nil {
			// A filesystem-level failure (a locked file, a NAS hiccup,
			// a slow mount) keeps the row leased: it re-offers when
			// the lease lapses and rests after the attempt cap, like a
			// leased-but-silent external worker. Anything the decoder
			// or embedder concluded about the bytes (undecodable, too
			// short, silent) is a verdict retrying cannot change, so
			// those retire their rows; a rescan re-enqueues if the
			// file changes.
			var pathErr *fs.PathError
			if errors.As(err, &pathErr) {
				l.log.Warn("embedded analysis could not read a track; it will retry", "pid", w.ItemPID, "err", err)
				continue
			}
			l.log.Warn("embedded analysis skipped a track", "pid", w.ItemPID, "err", err)
			l.completeAnalysis(ctx, w.Essence)
			continue
		}
		res, err := l.IngestEmbeddings(ctx, an.Model(), an.VectorDims(), []EmbeddingUpload{{
			PID:     apiPID(PrefixTrack, model.PID(w.ItemPID)),
			Essence: w.Essence,
			Vector:  vec,
		}})
		if err != nil {
			return true, err
		}
		for _, rej := range res.Rejected {
			l.log.Warn("embedded analysis vector rejected", "pid", w.ItemPID, "reason", rej.Message)
			l.completeAnalysis(ctx, w.Essence)
		}
		select {
		case <-ctx.Done():
			return true, nil
		case <-time.After(embeddedAnalysisPace):
		}
	}
	return true, nil
}

func (l *Library) completeAnalysis(ctx context.Context, essence string) {
	if err := l.db.CompleteSimilarityWork(ctx, essence); err != nil {
		l.log.Warn("retiring analysis work", "essence", essence, "err", err)
	}
}

// warmSimilarity loads stored vectors and edges into the in-memory
// engine once. Cheap when empty (the common case without a worker).
func (l *Library) warmSimilarity(ctx context.Context) error {
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

// SimilarityStatusFor answers coverage. enabled reports whether an
// analyzer can feed the surface: the embedded analyzer's runtime
// setting, or a configured external worker token.
func (l *Library) SimilarityStatusFor(ctx context.Context, uc *UserCtx) (SimilarityStatus, error) {
	enabled := l.SonicAnalysisEnabled() || l.workerAPIConfigured
	count, mdl, dims, lastIngest, err := l.db.EmbeddingStats(ctx)
	if err != nil {
		return SimilarityStatus{}, &Error{Kind: KindInternal, Err: err}
	}
	depth, err := l.db.SimilarityQueueDepth(ctx)
	if err != nil {
		return SimilarityStatus{}, &Error{Kind: KindInternal, Err: err}
	}
	total, err := l.countAnalyzableTracks(ctx, uc.CatalogPID)
	if err != nil {
		return SimilarityStatus{}, err
	}
	st := SimilarityStatus{
		Enabled:        enabled,
		Model:          mdl,
		Dims:           dims,
		EmbeddedTracks: count,
		TotalTracks:    total,
		QueueDepth:     depth,
		LastIngestAt:   lastIngest,
	}
	if total > 0 {
		pct := float64(count) / float64(total) * 100
		if pct > 100 {
			pct = 100
		}
		st.CoveragePct = pct
	}
	return st, nil
}

// countAnalyzableTracks counts the catalog's music tracks; virtual
// (CUE-carved) tracks share their backing file's essence and are not
// analyzed per window, but they are a small minority and the coverage
// figure tolerates them.
func (l *Library) countAnalyzableTracks(ctx context.Context, catalogPID string) (int, error) {
	q := visibleItems().Where("kind", query.OpIs, string(model.KindTrack)).Build()
	n, err := l.lib.Count(ctx, q, model.PID(catalogPID))
	if err != nil {
		return 0, classify(err)
	}
	return n, nil
}

// LeaseSimilarityWork leases a work batch for a polling worker.
func (l *Library) LeaseSimilarityWork(ctx context.Context, limit int) ([]SimilarityWorkItem, error) {
	work, err := l.db.LeaseSimilarityWork(ctx, limit, workLease)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	// Snapshot the root count once: the single-root local-path optimization
	// only holds when exactly one root exists, and a runtime-added root must
	// disable it for the rest of this batch consistently.
	singleRoot := len(l.libraryRoots()) == 1
	out := make([]SimilarityWorkItem, 0, len(work))
	for _, w := range work {
		item := SimilarityWorkItem{
			PID:       apiPID(PrefixTrack, model.PID(w.ItemPID)),
			Essence:   w.Essence,
			MediaType: "music",
		}
		if it, err := l.lib.Get(ctx, model.PID(w.ItemPID)); err == nil {
			item.DurationMs = it.DurationMS
			if l.workerLocalPaths && singleRoot {
				if f, err := l.lib.File(ctx, it.FilePID); err == nil {
					item.LocalPath = string(f.RelPath)
				}
			}
		} else {
			// The item vanished between enqueue and lease; retire the
			// row instead of handing out dead work.
			if cerr := l.db.CompleteSimilarityWork(ctx, w.Essence); cerr != nil {
				l.log.Warn("retiring dead analysis work", "essence", w.Essence, "err", cerr)
			}
			continue
		}
		out = append(out, item)
	}
	return out, nil
}

// IngestEmbeddings records a worker's batch: vectors persist keyed by
// essence, the in-memory engine updates its neighbor graph
// incrementally, and the touched nodes' edge lists persist alongside.
// A model different from the stored vectors' replaces coverage
// model-wide (mixed models never compare).
func (l *Library) IngestEmbeddings(ctx context.Context, mdl string, dims int, batch []EmbeddingUpload) (EmbeddingIngestResult, error) {
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

// mustVector reads back the normalized stored vector for persistence
// (Ingest normalizes in place under its own lock).
func mustVector(e *similarity.Engine, essence string) []float32 {
	v, _ := e.Vector(essence)
	return v
}

func (l *Library) persistEdges(ctx context.Context, essence string, edges []similarity.Edge) error {
	rows := make([]wdb.GraphEdge, len(edges))
	for i, e := range edges {
		rows[i] = wdb.GraphEdge{Essence: essence, Rank: i, Neighbor: e.Neighbor, Distance: e.Distance}
	}
	if err := l.db.ReplaceGraphNode(ctx, essence, rows); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// SimilaritySweep reconciles the analysis queue with the catalog: new
// music tracks enqueue, embeddings whose audio left the catalog prune
// (edges removed, affected nodes queued for lazy recompute), and
// pending backfills recompute. It short-circuits when the catalog data
// version has not moved since the last sweep. Returns true when it did
// meaningful work (the worker loop uses that to pace itself).
func (l *Library) SimilaritySweep(ctx context.Context) (bool, error) {
	if !l.SonicAnalysisEnabled() && !l.workerAPIConfigured {
		return false, nil
	}
	if err := l.warmSimilarity(ctx); err != nil {
		return false, err
	}
	worked, err := l.drainBackfill(ctx)
	if err != nil {
		return worked, err
	}
	version, err := l.lib.DataVersion(ctx)
	if err != nil {
		return worked, classify(err)
	}
	if version == l.simSweepVersion.Load() {
		return worked, nil
	}
	defaultUser, err := l.lib.DefaultUser(ctx)
	if err != nil {
		return worked, classify(err)
	}
	live := map[string]bool{}
	q := visibleItems().Where("kind", query.OpIs, string(model.KindTrack)).OrderBy("title", false).Build()
	cursor := ""
	for {
		page, err := l.lib.QueryPage(ctx, q, read.Cursor(cursor), 500, false, defaultUser.PID)
		if err != nil {
			return worked, classify(err)
		}
		for _, it := range page.Items {
			if it.Virtual {
				// A CUE-carved track shares its backing file's essence;
				// per-window embeddings are not computed.
				continue
			}
			f, err := l.lib.File(ctx, it.FilePID)
			if err != nil || f.EssenceHash == "" {
				continue
			}
			live[f.EssenceHash] = true
			if !l.sim.Has(f.EssenceHash) {
				if err := l.db.EnqueueSimilarity(ctx, f.EssenceHash, string(it.PID)); err != nil {
					return worked, &Error{Kind: KindInternal, Err: err}
				}
				worked = true
			}
		}
		if !page.HasMore {
			break
		}
		cursor = string(page.Next)
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
		stale = slices.DeleteFunc(stale, func(essence string) bool {
			return len(restorable[owner[essence]]) > 0
		})
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
	return worked, nil
}

// drainBackfill recomputes queued nodes' edge lists.
func (l *Library) drainBackfill(ctx context.Context) (bool, error) {
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
