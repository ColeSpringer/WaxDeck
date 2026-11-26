// Package syncsource holds the acquisition capabilities WaxDeck adds
// beside WaxBin's source.Provider port, each found by type assertion: a
// provider that can list a playlist in true order - no newest-first stop
// cursor, unavailable entries flagged rather than dropped - implements
// Snapshotter for the playlist-sync reconciler, one that can honour an
// acquisition's options implements FetchWith (FetchOptions), and every
// acquisition source decides a link's shape from the link (LinkShape) and
// checks it before it is queued (Probe, AcquireTarget).
package syncsource

import "context"

// FetchOptions are what an acquisition asks of one fetch beyond WaxBin's
// source.FetchRequest. Format is the preferred output format ("" or
// "best" is the provider's default copy; "opus", "mp3", "m4a", "flac"
// transcode). Music says the download lands in a music library, so the
// provider may clean the title and read release facts the source states.
// OnEvent, when set, hears what the fetch is doing as it does it, on the
// fetching goroutine.
type FetchOptions struct {
	Format  string
	Music   bool
	OnEvent func(FetchEvent)
}

// The phases a fetch reports.
const (
	PhaseDownloading = "downloading"
	// PhaseProcessing is converting or cutting what was fetched.
	PhaseProcessing = "processing"
)

// FetchEvent is one thing a fetch did. Phase is PhaseDownloading or
// PhaseProcessing, or "" for activity within the phase it was in (a
// retry, a warning). Bytes and Total are the download's bytes so far and
// its size, 0 when unknown; a new download attempt starts again at 0.
type FetchEvent struct {
	Phase        string
	Bytes, Total int64
}

// ListProgress hears a listing as it reads: OnPage the entries listed
// so far after each page, OnLookup each entry lookup done of those the
// listing makes. Either may be nil.
type ListProgress struct {
	OnPage   func(listed int)
	OnLookup func(done, total int)
}

// EnumerateOptions are what an acquisition asks of one listing beyond
// WaxBin's source.Request.
type EnumerateOptions struct {
	Progress ListProgress
	// OnCut is told when the listing stopped at the source's own cap,
	// the source holding more than it listed.
	OnCut func()
}

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
	Progress    ListProgress
}

// Snapshotter lists a playlist URL in full order.
type Snapshotter interface {
	PlaylistSnapshot(ctx context.Context, url string, opts SnapshotOptions) (*PlaylistSnapshot, error)
}

// The shapes an acquisition link can name, in the words a task's summary
// uses.
const (
	ShapeVideo    = "video"
	ShapePlaylist = "playlist"
	ShapeChannel  = "channel"
)

// AcquireTarget is what a probe found a link to name: its shape, decided
// from the link alone, and the title the source gave it, when the check
// read one.
type AcquireTarget struct {
	Shape string
	Title string
}

// ReasonUnsupportedURL is the refusal of a link that is not a video,
// playlist or channel the provider can read.
const ReasonUnsupportedURL = "unsupported-url"

// Refusal is a provider's refusal of a link or an item, in WaxDeck's words:
// Reason is one of the API's source-refused reasons. Its text names only the
// reason; Err keeps the source's own failure for errors.Is and the log.
type Refusal struct {
	Reason string
	Err    error
}

func (r *Refusal) Error() string { return "the source refused the link: " + r.Reason }

func (r *Refusal) Unwrap() error { return r.Err }
