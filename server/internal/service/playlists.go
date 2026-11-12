package service

import (
	"sync"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// Playlists is playlists: editing, syncing, handing over, importing,
// artwork, smart playlists and the starter set.
type Playlists struct {
	*core
	// refResolveHook runs as a walk of the catalog's resolve ladder over
	// refs portable refs starts, and m3uResolveHook as the catalog's
	// resolve of an M3U8 document does, in a test; nothing in the server
	// sets them.
	refResolveHook func(opts waxbin.ResolveOptions, refs int)
	m3uResolveHook func()
	// m3us holds the catalog's latest resolutions of M3U8 documents.
	m3us m3uResolutions
	// coverSyncing single-flights playlist cover generation per playlist,
	// so concurrent readers of one shared list do not each composite it.
	coverSyncing map[model.PID]bool
	coverSyncMu  sync.Mutex
	// readerCovers keeps the member cover a reader is shown in place of a
	// shared playlist's stored one (readerMemberCover).
	readerCovers readerCoverCache
	// handoverHook fails a step of handing a deleted account's playlist
	// over in a test; nothing in the server sets it.
	handoverHook func(stage string, pl *model.Playlist) error
	// memberReadHook runs as a playlist's members are read, in a test;
	// nothing in the server sets it.
	memberReadHook func(pl *model.Playlist)
	// coverRecordHook runs before a generated cover's provenance is
	// recorded, in a test, failing what follows; nothing in the server
	// sets it.
	coverRecordHook func() error
	// isrcResolver mirrors Config.ISRCResolver.
	isrcResolver ISRCResolver
}

func newPlaylists(c *core, cfg Config) *Playlists {
	return &Playlists{core: c, isrcResolver: cfg.ISRCResolver}
}

// Playlist is the API-facing playlist shape. ItemCount is the members
// this caller is offered, which is what the item listing hands back;
// it is nil when the count is omitted (smart playlists on list pages,
// where computing it would evaluate every rule). Rule is nil for static
// playlists.
type Playlist struct {
	PID        string
	Name       string
	Kind       string
	Visibility string
	OwnerName  string
	IsOwner    bool
	ItemCount  *int
	Rule       *SmartRule
	// HasArt says a cover is stored for this playlist, whether the owner
	// uploaded one or WaxDeck built it from the members. It is what tells
	// a grid to fetch the art endpoint instead of drawing a placeholder.
	HasArt    bool
	CreatedAt time.Time
	UpdatedAt time.Time
}

// SmartRule is the wire shape of a smart playlist rule. LimitMode
// interprets Limit (empty or "count" is a plain member cap; "random",
// "minutes", and "megabytes" are the shuffle and budget modes);
// LimitSeed pins a random or budget draw.
type SmartRule struct {
	Root      RuleNode
	Sorts     []RuleSort
	Limit     int
	LimitMode string
	LimitSeed int64
}

// RuleNode is one node of a rule's condition tree; Type selects which
// fields are meaningful (all, any, not, condition).
type RuleNode struct {
	Type   string
	Nodes  []RuleNode
	Node   *RuleNode
	Field  string
	Op     string
	Value  string
	Values []string
}

// RuleSort is one sort key.
type RuleSort struct {
	Field string
	Desc  bool
}

// PlaylistPage is one page of playlists.
type PlaylistPage struct {
	Playlists []Playlist
	Next      string
}

// PlaylistEntry is one playlist member; Position is set only for
// static playlists and is the stored (unfiltered) order.
type PlaylistEntry struct {
	Position *int
	Item     ItemSummary
}

// PlaylistItemsPage is one page of playlist members.
type PlaylistItemsPage struct {
	Entries []PlaylistEntry
	Next    string
}

// PlaylistPreview is a stateless rule evaluation.
type PlaylistPreview struct {
	Items []ItemSummary
	Total int
}

// RuleFieldInfo describes one rule field for editors.
type RuleFieldInfo struct {
	Name        string
	Kind        string
	Ops         []string
	UserState   bool
	Sortable    bool
	Description string
}

// RuleTagKey is one custom tag key usable as a tag.KEY field.
type RuleTagKey struct {
	Key       string
	ItemCount int
}

// RuleFields is the rule vocabulary.
type RuleFields struct {
	Fields  []RuleFieldInfo
	TagKeys []RuleTagKey
}

// PlaylistCreate is the create request.
type PlaylistCreate struct {
	Name       string
	Kind       string
	Visibility string
	Rule       *SmartRule
	ItemPIDs   []string
}

// PlaylistUpdate is the partial update request; nil means unchanged.
type PlaylistUpdate struct {
	Name       *string
	Visibility *string
	Rule       *SmartRule
}

// M3uImportOutcome reports an M3U8 import.
type M3uImportOutcome struct {
	Playlist       Playlist
	Matched        int
	Unmatched      int
	UnmatchedPaths []string
}

// How one path line of an M3U8 document reads: an entry, the item of the
// line before it through a different path to it (another of its files,
// or another spelling of the same file), or nothing the caller can see.
const (
	M3uMatched   = "matched"
	M3uMerged    = "merged"
	M3uUnmatched = "unmatched"
)

// M3uPreviewLine is one path line of an M3U8 document and what it
// matched; Item is nil on an unmatched line.
type M3uPreviewLine struct {
	Path    string
	Outcome string
	Item    *ItemSummary
}

// M3uPreview reports how an M3U8 document would import, line by line.
type M3uPreview struct {
	Matched   int
	Merged    int
	Unmatched int
	Lines     []M3uPreviewLine
}
