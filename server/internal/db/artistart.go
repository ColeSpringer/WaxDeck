package db

import (
	"context"
	"fmt"
	"strings"
)

// ArtistArtMiss is the sweep's memory of one artist the providers held
// nothing for: when the ask was made and under which MBID. The MBID
// rides along so a miss recorded before an artist gained its anchor
// does not suppress the keyed lookup that anchor unlocks. Hits are not
// remembered - the stored art itself is what gates those.
type ArtistArtMiss struct {
	MBID          string
	AttemptedAtNS int64
}

// ArtistArtMisses reads the miss rows for one page of artists, keyed
// by pid. Absent pids simply have no entry.
func (d *DB) ArtistArtMisses(ctx context.Context, artistPIDs []string) (map[string]ArtistArtMiss, error) {
	if len(artistPIDs) == 0 {
		return nil, nil
	}
	args := make([]any, len(artistPIDs))
	for i, pid := range artistPIDs {
		args[i] = pid
	}
	rows, err := d.r.QueryContext(ctx, `
		SELECT artist_pid, mbid, attempted_at_ns FROM artist_art_misses
		WHERE artist_pid IN (?`+strings.Repeat(",?", len(artistPIDs)-1)+`)`, args...)
	if err != nil {
		return nil, fmt.Errorf("db: reading artist art misses: %w", err)
	}
	defer rows.Close()
	out := make(map[string]ArtistArtMiss, len(artistPIDs))
	for rows.Next() {
		var pid string
		var m ArtistArtMiss
		if err := rows.Scan(&pid, &m.MBID, &m.AttemptedAtNS); err != nil {
			return nil, fmt.Errorf("db: scanning artist art miss: %w", err)
		}
		out[pid] = m
	}
	return out, rows.Err()
}

// RecordArtistArtMiss upserts one artist's miss row.
func (d *DB) RecordArtistArtMiss(ctx context.Context, artistPID, mbid string, ns int64) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO artist_art_misses (artist_pid, mbid, attempted_at_ns)
		VALUES (?, ?, ?)
		ON CONFLICT (artist_pid) DO UPDATE SET
			mbid = excluded.mbid, attempted_at_ns = excluded.attempted_at_ns`,
		artistPID, mbid, ns)
	if err != nil {
		return fmt.Errorf("db: recording artist art miss: %w", err)
	}
	return nil
}

// ClearArtistArtMiss drops an artist's miss row, once a portrait
// landed: a stale fresh miss must not block a refill after that
// portrait is cleared again.
func (d *DB) ClearArtistArtMiss(ctx context.Context, artistPID string) error {
	if _, err := d.w.ExecContext(ctx, `
		DELETE FROM artist_art_misses WHERE artist_pid = ?`, artistPID); err != nil {
		return fmt.Errorf("db: clearing artist art miss: %w", err)
	}
	return nil
}

// ClearArtistArtMisses drops the whole miss memory, for a forced
// enrichment run: "ask everything again" includes the artists the
// providers held nothing for last time.
func (d *DB) ClearArtistArtMisses(ctx context.Context) error {
	if _, err := d.w.ExecContext(ctx, `DELETE FROM artist_art_misses`); err != nil {
		return fmt.Errorf("db: clearing artist art misses: %w", err)
	}
	return nil
}

// PruneArtistArtMisses drops miss rows older than the cutoff. A row
// past the retry window has no effect on the sweep (it re-asks and
// re-records), so pruning is pure hygiene - it is also what keeps rows
// for merged-away or deleted artists from accumulating forever.
func (d *DB) PruneArtistArtMisses(ctx context.Context, olderThanNS int64) (int64, error) {
	res, err := d.w.ExecContext(ctx, `
		DELETE FROM artist_art_misses WHERE attempted_at_ns < ?`, olderThanNS)
	if err != nil {
		return 0, fmt.Errorf("db: pruning artist art misses: %w", err)
	}
	return res.RowsAffected()
}
