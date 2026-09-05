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
// track-only - an episode's or a book's Album is a show or series
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
	// AdvisoryFlagged folds the episode advisory pair (the episode's
	// own feed flag or its show's). Always false for other kinds, whose
	// advisory lives in the ITUNESADVISORY custom tag instead.
	AdvisoryFlagged bool
}

// ItemDetail is the full single-item shape.
type ItemDetail struct {
	ItemSummary
	Genres []string
	Year   int
	// BPM is the track's stated tempo, whole; 0 for an item carrying
	// none, which is most of them.
	BPM        int
	Codec      string
	Container  string
	SampleRate int
	Bitrate    int
	AddedAt    time.Time
	// MBID and ISRC are the recording's own identifiers, empty for the
	// items carrying neither, which is most of an untagged library.
	MBID      string
	ISRC      string
	ArtSource ArtSourceDTO
}

// AlbumDetail is one album entity's identity and counts. Everything
// after ReleaseGroupPID is edition-scoped and lives nowhere else in the
// API: the item row carries what the file is, this carries what the
// release is.
type AlbumDetail struct {
	PID             string
	Title           string
	SortKey         string
	MBID            string
	Year            int
	ReleaseGroupPID string
	Barcode         string
	Label           string
	CatalogNumber   string
	Media           string
	Country         string
	ItemCount       int
	TotalDurationMS int64
	ArtSource       ArtSourceDTO
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
// stable cache validator. Source carries where the answering level's
// picture came from, which the art endpoint reports as headers.
type ArtBlob struct {
	Bytes      []byte
	MimeType   string
	SourceHash string
	Source     ArtSourceDTO
	// Width and Height are the pixel dimensions of what is being served:
	// a thumbnail's own, or the source's for an unscaled answer. Both
	// zero means nothing here could measure the picture, which is the
	// one case a resolve hands back bytes it could not scale.
	Width  int
	Height int
	// Box is the ladder rung this resolve answered at: the requested
	// size rounded up (waxbin/art.Rung), or 0 when no size was asked
	// for. Every request rounding to the same rung gets the same bytes,
	// so it - not the raw request - is what a cache key or a size guard
	// is written against.
	Box int
}

// ArtSourceDTO says where a picture came from: the producer, the
// provider that supplied a fetched one, the URL it was fetched from,
// and which rung of the fallback chain answered.
//
// Zero Source means unattributed, which is what every surface that
// cannot answer the question reports rather than guessing.
type ArtSourceDTO struct {
	Source    string
	Provider  string
	SourceURL string
	Level     string
	// Derived marks a level answering with a member's picture rather
	// than one of its own - an album showing a track's cover, which is
	// the ordinary case for an album nobody gave a durable one. Source
	// is that member's, so this is what keeps a caption from reading as
	// though the album made the choice.
	Derived   bool
	UpdatedAt time.Time
}

// Attributed reports whether this names a producer. An unattributed
// source draws no mark.
func (a ArtSourceDTO) Attributed() bool { return a.Source != "" }

// SyncedLine is one time-synced lyric line.
type SyncedLine struct {
	TimeMS int64
	Text   string
}

// Lyrics is an item's lyrics.
type Lyrics struct {
	PID      string
	Source   string
	Provider string
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
	// LastPlayedAt is when a play was last counted; zero until one has
	// been. A manual played mark leaves it alone, so it reads as the
	// listening record rather than as the flag's age.
	LastPlayedAt time.Time
	UpdatedAt    time.Time
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
