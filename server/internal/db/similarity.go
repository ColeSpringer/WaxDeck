package db

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

// Embedding is one stored track embedding. Essence is the key: identical
// audio bytes carry identical essences across retags and re-rips, so a
// vector survives everything short of a re-encode. Vector is the packed
// little-endian float32 form; the similarity engine owns the encoding.
type Embedding struct {
	Essence   string
	ItemPID   string
	Model     string
	Dims      int
	Vector    []byte
	CreatedAt time.Time
}

// GraphEdge is one nearest-neighbor edge of the similarity graph.
type GraphEdge struct {
	Essence  string
	Rank     int
	Neighbor string
	Distance float64
}

// SimilarityWork is one leased analysis work item.
type SimilarityWork struct {
	Essence string
	ItemPID string
}

// UpsertEmbedding stores or replaces one vector, reporting whether it
// replaced a prior one.
func (d *DB) UpsertEmbedding(ctx context.Context, e Embedding) (replaced bool, err error) {
	var existing int
	err = d.w.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM embeddings WHERE essence = ?`, e.Essence).Scan(&existing)
	if err != nil {
		return false, fmt.Errorf("db: checking embedding: %w", err)
	}
	_, err = d.w.ExecContext(ctx, `
		INSERT INTO embeddings (essence, item_pid, model, dims, vector, created_at_ns)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT (essence) DO UPDATE SET
			item_pid = excluded.item_pid, model = excluded.model,
			dims = excluded.dims, vector = excluded.vector,
			created_at_ns = excluded.created_at_ns`,
		e.Essence, e.ItemPID, e.Model, e.Dims, e.Vector, time.Now().UnixNano())
	if err != nil {
		return false, fmt.Errorf("db: storing embedding: %w", err)
	}
	return existing > 0, nil
}

// Embeddings streams every stored vector to fn, used to warm the
// in-memory engine. Returns the stored model and dims of the first row
// (mixed models never persist; ingest drops other models on a switch).
func (d *DB) Embeddings(ctx context.Context, fn func(Embedding)) (model string, dims int, err error) {
	rows, err := d.r.QueryContext(ctx,
		`SELECT essence, item_pid, model, dims, vector FROM embeddings`)
	if err != nil {
		return "", 0, fmt.Errorf("db: reading embeddings: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var e Embedding
		if err := rows.Scan(&e.Essence, &e.ItemPID, &e.Model, &e.Dims, &e.Vector); err != nil {
			return "", 0, fmt.Errorf("db: reading embeddings: %w", err)
		}
		if model == "" {
			model, dims = e.Model, e.Dims
		}
		fn(e)
	}
	return model, dims, rows.Err()
}

// EmbeddingStats reports coverage figures for the status surface.
func (d *DB) EmbeddingStats(ctx context.Context) (count int, model string, dims int, lastIngest time.Time, err error) {
	err = d.r.QueryRowContext(ctx,
		`SELECT COUNT(*), COALESCE(MAX(created_at_ns), 0) FROM embeddings`).Scan(&count, &lastIngestNS{&lastIngest})
	if err != nil {
		return 0, "", 0, time.Time{}, fmt.Errorf("db: embedding stats: %w", err)
	}
	if count > 0 {
		err = d.r.QueryRowContext(ctx,
			`SELECT model, dims FROM embeddings LIMIT 1`).Scan(&model, &dims)
		if err != nil {
			return 0, "", 0, time.Time{}, fmt.Errorf("db: embedding stats: %w", err)
		}
	}
	return count, model, dims, lastIngest, nil
}

// lastIngestNS scans a nanosecond timestamp into a time.Time, zero for 0.
type lastIngestNS struct{ t *time.Time }

func (s *lastIngestNS) Scan(v any) error {
	ns, ok := v.(int64)
	if !ok || ns == 0 {
		*s.t = time.Time{}
		return nil
	}
	*s.t = time.Unix(0, ns).UTC()
	return nil
}

// DeleteEmbeddingsNotModel removes every vector of a different model
// and, when any went, the whole neighbor graph with them (its edges
// mix models otherwise). One transaction: a crash between the two
// deletes must not leave a graph pointing at vanished vectors.
func (d *DB) DeleteEmbeddingsNotModel(ctx context.Context, model string) (int64, error) {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return 0, fmt.Errorf("db: dropping old-model embeddings: %w", err)
	}
	defer tx.Rollback()
	res, err := tx.ExecContext(ctx,
		`DELETE FROM embeddings WHERE model <> ?`, model)
	if err != nil {
		return 0, fmt.Errorf("db: dropping old-model embeddings: %w", err)
	}
	n, _ := res.RowsAffected()
	if n > 0 {
		if _, err := tx.ExecContext(ctx, `DELETE FROM similarity_graph`); err != nil {
			return 0, fmt.Errorf("db: dropping old-model graph: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return 0, fmt.Errorf("db: dropping old-model embeddings: %w", err)
	}
	return n, nil
}

// ReplaceGraphNode replaces one node's full edge list in a single
// transaction on the write connection.
func (d *DB) ReplaceGraphNode(ctx context.Context, essence string, edges []GraphEdge) error {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: replacing graph node: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx,
		`DELETE FROM similarity_graph WHERE essence = ?`, essence); err != nil {
		return fmt.Errorf("db: replacing graph node: %w", err)
	}
	for _, e := range edges {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO similarity_graph (essence, rank, neighbor, distance)
			VALUES (?, ?, ?, ?)`,
			essence, e.Rank, e.Neighbor, e.Distance); err != nil {
			return fmt.Errorf("db: replacing graph node: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("db: replacing graph node: %w", err)
	}
	return nil
}

// GraphEdges streams the whole graph to fn, used to warm the in-memory
// engine.
func (d *DB) GraphEdges(ctx context.Context, fn func(GraphEdge)) error {
	rows, err := d.r.QueryContext(ctx,
		`SELECT essence, rank, neighbor, distance FROM similarity_graph ORDER BY essence, rank`)
	if err != nil {
		return fmt.Errorf("db: reading graph: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var e GraphEdge
		if err := rows.Scan(&e.Essence, &e.Rank, &e.Neighbor, &e.Distance); err != nil {
			return fmt.Errorf("db: reading graph: %w", err)
		}
		fn(e)
	}
	return rows.Err()
}

// RemoveEmbedding drops one essence's vector, its edges, and every edge
// pointing at it, returning the nodes that lost an edge (they need a
// lazy backfill, recorded by the caller).
func (d *DB) RemoveEmbedding(ctx context.Context, essence string) (affected []string, err error) {
	rows, err := d.r.QueryContext(ctx,
		`SELECT DISTINCT essence FROM similarity_graph WHERE neighbor = ?`, essence)
	if err != nil {
		return nil, fmt.Errorf("db: removing embedding: %w", err)
	}
	for rows.Next() {
		var e string
		if err := rows.Scan(&e); err != nil {
			rows.Close()
			return nil, fmt.Errorf("db: removing embedding: %w", err)
		}
		affected = append(affected, e)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("db: removing embedding: %w", err)
	}
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("db: removing embedding: %w", err)
	}
	defer tx.Rollback()
	for _, q := range []string{
		`DELETE FROM embeddings WHERE essence = ?`,
		`DELETE FROM similarity_graph WHERE essence = ?`,
		`DELETE FROM similarity_graph WHERE neighbor = ?`,
		`DELETE FROM similarity_queue WHERE essence = ?`,
	} {
		if _, err := tx.ExecContext(ctx, q, essence); err != nil {
			return nil, fmt.Errorf("db: removing embedding: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("db: removing embedding: %w", err)
	}
	return affected, nil
}

// EnqueueSimilarity queues one track for analysis; a queued or embedded
// essence is left alone.
func (d *DB) EnqueueSimilarity(ctx context.Context, essence, itemPID string) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO similarity_queue (essence, item_pid, enqueued_at_ns)
		SELECT ?, ?, ?
		WHERE NOT EXISTS (SELECT 1 FROM embeddings WHERE essence = ?)
		ON CONFLICT (essence) DO NOTHING`,
		essence, itemPID, time.Now().UnixNano(), essence)
	if err != nil {
		return fmt.Errorf("db: enqueueing analysis: %w", err)
	}
	return nil
}

// maxAnalysisAttempts caps how often one essence is offered to
// workers. An item a worker leases but never reports (undecodable,
// crashes the model) would otherwise re-lease forever; past the cap
// it stops being offered and drops out of the queue depth. Attempts
// only grow when someone actually leases, so an idle queue never
// burns them, and a re-rip changes the essence and starts fresh.
const maxAnalysisAttempts = 8

// LeaseSimilarityWork leases up to limit queue rows for a worker. The
// lease expires on its own, so a crashed worker's items return to the
// queue without cleanup.
func (d *DB) LeaseSimilarityWork(ctx context.Context, limit int, lease time.Duration) ([]SimilarityWork, error) {
	now := time.Now().UnixNano()
	until := time.Now().Add(lease).UnixNano()
	rows, err := d.w.QueryContext(ctx, `
		UPDATE similarity_queue
		SET lease_until_ns = ?, attempts = attempts + 1
		WHERE essence IN (
			SELECT essence FROM similarity_queue
			WHERE lease_until_ns < ? AND attempts < ?
			ORDER BY enqueued_at_ns
			LIMIT ?
		)
		RETURNING essence, item_pid`, until, now, maxAnalysisAttempts, limit)
	if err != nil {
		return nil, fmt.Errorf("db: leasing analysis work: %w", err)
	}
	defer rows.Close()
	var out []SimilarityWork
	for rows.Next() {
		var w SimilarityWork
		if err := rows.Scan(&w.Essence, &w.ItemPID); err != nil {
			return nil, fmt.Errorf("db: leasing analysis work: %w", err)
		}
		out = append(out, w)
	}
	return out, rows.Err()
}

// CompleteSimilarityWork removes a queue row once its vector arrived.
func (d *DB) CompleteSimilarityWork(ctx context.Context, essence string) error {
	_, err := d.w.ExecContext(ctx,
		`DELETE FROM similarity_queue WHERE essence = ?`, essence)
	if err != nil {
		return fmt.Errorf("db: completing analysis work: %w", err)
	}
	return nil
}

// SimilarityQueueDepth reports how many tracks await analysis.
// Attempt-exhausted rows are excluded: they will not be offered
// again, so counting them would show a backlog nothing drains.
func (d *DB) SimilarityQueueDepth(ctx context.Context) (int, error) {
	var n int
	err := d.r.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM similarity_queue WHERE attempts < ?`,
		maxAnalysisAttempts).Scan(&n)
	if err != nil {
		return 0, fmt.Errorf("db: analysis queue depth: %w", err)
	}
	return n, nil
}

// AddSimilarityBackfill records nodes that lost a neighbor edge.
func (d *DB) AddSimilarityBackfill(ctx context.Context, essences []string) error {
	for _, e := range essences {
		if _, err := d.w.ExecContext(ctx, `
			INSERT INTO similarity_backfill (essence) VALUES (?)
			ON CONFLICT (essence) DO NOTHING`, e); err != nil {
			return fmt.Errorf("db: recording backfill: %w", err)
		}
	}
	return nil
}

// TakeSimilarityBackfill pops up to limit backfill entries.
func (d *DB) TakeSimilarityBackfill(ctx context.Context, limit int) ([]string, error) {
	rows, err := d.w.QueryContext(ctx, `
		DELETE FROM similarity_backfill
		WHERE essence IN (SELECT essence FROM similarity_backfill LIMIT ?)
		RETURNING essence`, limit)
	if err != nil {
		return nil, fmt.Errorf("db: taking backfill: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var e string
		if err := rows.Scan(&e); err != nil {
			return nil, fmt.Errorf("db: taking backfill: %w", err)
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// EmbeddingItemPID answers the stored item pid for one essence.
func (d *DB) EmbeddingItemPID(ctx context.Context, essence string) (string, error) {
	var pid string
	err := d.r.QueryRowContext(ctx,
		`SELECT item_pid FROM embeddings WHERE essence = ?`, essence).Scan(&pid)
	if err == sql.ErrNoRows {
		return "", ErrNotFound
	}
	if err != nil {
		return "", fmt.Errorf("db: embedding item: %w", err)
	}
	return pid, nil
}

// EmbeddingItemPIDs answers stored item pids for a batch of essences
// in a few chunked IN queries; absent essences are absent keys. The
// discovery surface resolves whole candidate pools through this (a
// wide mix scans thousands of edges), so per-essence round trips are
// the wrong shape.
func (d *DB) EmbeddingItemPIDs(ctx context.Context, essences []string) (map[string]string, error) {
	out := make(map[string]string, len(essences))
	const chunkSize = 500
	for start := 0; start < len(essences); start += chunkSize {
		chunk := essences[start:min(start+chunkSize, len(essences))]
		placeholders := strings.Repeat("?,", len(chunk)-1) + "?"
		args := make([]any, len(chunk))
		for i, e := range chunk {
			args[i] = e
		}
		rows, err := d.r.QueryContext(ctx,
			`SELECT essence, item_pid FROM embeddings WHERE essence IN (`+placeholders+`)`, args...)
		if err != nil {
			return nil, fmt.Errorf("db: embedding items: %w", err)
		}
		for rows.Next() {
			var essence, pid string
			if err := rows.Scan(&essence, &pid); err != nil {
				rows.Close()
				return nil, fmt.Errorf("db: embedding items: %w", err)
			}
			out[essence] = pid
		}
		if err := rows.Err(); err != nil {
			rows.Close()
			return nil, fmt.Errorf("db: embedding items: %w", err)
		}
		rows.Close()
	}
	return out, nil
}
