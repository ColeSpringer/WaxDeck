package service

import "time"

// The service returns plain DTOs so the API layer never touches WaxBin
// types: the ownership boundary (only service and below import waxbin)
// is enforced by depguard-style linting, and these types are what cross
// it.

// ItemSummary is the compact list-row shape. Virtual marks a track
// carved out of a shared source file by a cue sheet: it plays a
// window, and its original bytes are the whole backing rip, which
// surfaces that serve originals must account for.
//
// ArtistPID and AlbumPID are the entity handles behind the display
// text, so a client can group and link by identity: two artists with
// the same name are two entities, and an album title alone is not a
// location. Each is empty when the entity is absent, and AlbumPID is
// track-only — an episode's or a book's Album is a show or series
// title with no album entity behind it.
//
// TrackNo and DiscNo ride the summary rather than the detail because a
// listing is where they are needed: an items page arrives in the
// catalog's own stable order, and these are what sort a release back
// into itself without a fetch per row.
type ItemSummary struct {
	PID        string
	MediaType  string
	Title      string
	Artist     string
	Album      string
	ArtistPID  string
	AlbumPID   string
	TrackNo    int
	DiscNo     int
	DurationMS int64
	Virtual    bool
}

// ItemDetail is the full single-item shape.
type ItemDetail struct {
	ItemSummary
	Genres     []string
	Year       int
	Codec      string
	Container  string
	SampleRate int
	Bitrate    int
	AddedAt    time.Time
}

// Page is one keyset page of items.
type Page struct {
	Items []ItemSummary
	Next  string
}

// SearchHit is one ranked search result.
type SearchHit struct {
	PID      string
	Kind     string
	Title    string
	Subtitle string
}

// SearchResults groups hits by kind.
type SearchResults struct {
	Query     string
	Artists   []SearchHit
	Albums    []SearchHit
	Tracks    []SearchHit
	Books     []SearchHit
	Episodes  []SearchHit
	Truncated bool
}

// Job mirrors a catalog job for the API.
type Job struct {
	PID      string
	Kind     string
	State    string
	Progress float64
	Message  string
	Error    string
}

// ArtBlob is resolved artwork. SourceHash identifies the source image
// the bytes derive from; combined with the requested size it makes a
// stable cache validator.
type ArtBlob struct {
	Bytes      []byte
	MimeType   string
	SourceHash string
}

// SyncedLine is one time-synced lyric line.
type SyncedLine struct {
	TimeMS int64
	Text   string
}

// Lyrics is an item's lyrics.
type Lyrics struct {
	PID      string
	Source   string
	Synced   []SyncedLine
	Unsynced string
}

// PlayState is a user's playback state for one item. Rating is nil when
// unrated (an explicit 0 is a valid rating).
type PlayState struct {
	PID        string
	PositionMS int64
	Played     bool
	Finished   bool
	PlayCount  int
	Starred    bool
	Rating     *int
	UpdatedAt  time.Time
}

// ListenSession is one reported listen, API-shaped.
type ListenSession struct {
	SessionID string
	PID       string
	StartedAt time.Time
	MsPlayed  int64
	SkippedMs int64
	Finished  bool
	Client    string
	Source    string
}

// RejectedListen is one refused session and why.
type RejectedListen struct {
	SessionID string
	Code      string
	Message   string
}

// ListenIngestResult is the outcome of one ingest batch.
type ListenIngestResult struct {
	Accepted   int
	Duplicates int
	Rejected   []RejectedListen
}
