// Package syncsource defines the full-order playlist listing a synced
// playlist reconciles against. It is a WaxDeck-owned capability beside
// WaxBin's source.Provider port: a provider that can list a playlist in
// true order - no newest-first stop cursor, unavailable entries flagged
// rather than dropped - advertises it by implementing Snapshotter, and
// the playlist-sync reconciler finds it by type assertion, the same way
// the acquisition format preference rides its own optional interface.
package syncsource

import "context"

// PlaylistSnapshotEntry is one entry of a playlist snapshot, carrying
// the source's own entry identity and its true playlist position.
type PlaylistSnapshotEntry struct {
	ID         string // the source's entry id (a video id)
	Index      int    // 0-based true playlist position, stable across drops
	URL        string // the canonical per-entry URL a fetch takes
	Title      string
	DurationMS int64
	// ThumbnailURL is the entry's own thumbnail, known only for
	// entries the enrichment budget reached.
	ThumbnailURL string
	// Unavailable says the source reported the entry undeliverable
	// (members-only, geo-blocked, removed, ...). Flagged, never
	// dropped: a mirror must keep an already-downloaded track after
	// its source video goes private. Meaningful only when
	// AvailabilityKnown is true; past the enrichment budget
	// availability stays unknown until a download attempt says.
	Unavailable       bool
	AvailabilityKnown bool
}

// PlaylistSnapshot is the full ordered state of one playlist: every
// listed entry in playlist order, no incremental cursor.
type PlaylistSnapshot struct {
	ID          string
	IdentityKey string // the provider's stable identity for the playlist
	Title       string
	Author      string
	// CoverURL is the best cover the source offers, best-effort: for a
	// provider with no playlist-level image it is the first available
	// entry's thumbnail, which is also what the platform itself shows
	// for a playlist without a hand-set cover.
	CoverURL string
	Entries  []PlaylistSnapshotEntry
	// Truncated says the listing hit the provider's item cap and the
	// source holds more entries than Entries carries.
	Truncated bool
}

// SnapshotOptions bounds one snapshot. Zero values take the provider's
// defaults; a small MaxEntries with a small EnrichLimit is the cheap
// identity-and-cover probe a bind uses.
type SnapshotOptions struct {
	MaxEntries  int
	EnrichLimit int
}

// Snapshotter lists a playlist URL in full order.
type Snapshotter interface {
	PlaylistSnapshot(ctx context.Context, url string, opts SnapshotOptions) (*PlaylistSnapshot, error)
}
