package service

import (
	"time"
)

// Editor is the metadata editor.
type Editor struct{ *core }

func newEditor(c *core, _ Config) *Editor { return &Editor{core: c} }

// The metadata editor service: scalar field edits, credits, lyrics,
// chapters, artwork, custom tags, locks, entity curation, and release
// status. Every mutation is database-first: the catalog write commits
// before any on-disk write-back runs, and write-back trouble rides the
// result instead of failing the edit.

// maxArtworkBytes caps an uploaded cover image.
const maxArtworkBytes = 16 << 20

// EditableFieldDTO is one editable field or credit role with its
// write-back capability.
type EditableFieldDTO struct {
	Name      string
	WriteBack bool
}

// KindFieldsDTO is one item kind's editable vocabulary.
type KindFieldsDTO struct {
	Kind        string
	Fields      []EditableFieldDTO
	CreditRoles []EditableFieldDTO
}

// EntityTypeFieldsDTO is one entity type's editable vocabulary.
type EntityTypeFieldsDTO struct {
	EntityType string
	Fields     []EditableFieldDTO
}

// MetadataFieldsDTO is the editor's whole form vocabulary.
type MetadataFieldsDTO struct {
	Kinds       []KindFieldsDTO
	EntityTypes []EntityTypeFieldsDTO
	// ReservedTagKeys are the custom-tag keys upstream owns through
	// another surface (BPM through the bpm field, ISRC through its
	// own, and so on), so a custom-tag editor can refuse one before
	// the round trip rather than after it. The server refuses them
	// either way.
	ReservedTagKeys []string
}

// WriteBackFailureDTO is one file a write-back could not update.
type WriteBackFailureDTO struct {
	FilePID string
	Path    string
	Reason  string
}

// EditOutcomeDTO reports a committed catalog edit: write-back failures
// and non-fatal warnings ride along, never an error.
//
// MergedInto and MovedAlbums are the entity-edit half. Only an mbid
// clear re-keys an entity, so only that edit can leave the caller's pid
// gone (merged into a heuristic twin) or shed differently titled albums
// out of a release group; every other edit leaves both empty.
type EditOutcomeDTO struct {
	Failures    []WriteBackFailureDTO
	Warnings    []string
	MergedInto  string
	MovedAlbums []string
}

// BulkEditOutcomeDTO reports a bulk edit's per-item outcomes.
type BulkEditOutcomeDTO struct {
	Edited   []string
	Skipped  []string
	Failures []WriteBackFailureDTO

	// ResultingAlbumPID is where the edited items' release landed when
	// the edit rewrote a release-keying field and every edited item now
	// sits on one album; empty otherwise.
	ResultingAlbumPID string
}

// TagEditOutcomeDTO reports a custom-tag edit, with the files a
// write-back could not update.
type TagEditOutcomeDTO struct {
	Key      string
	Stored   int
	Failures []WriteBackFailureDTO
}

// FieldProvenanceDTO is one field's provenance row.
//
// The list carries two kinds. A scalar row names a metadata field and
// reports the value a curator set. An artifact row names "art" or
// "lyrics" and appears whenever the item holds one, with no value
// because the value is bytes. A non-empty list therefore does not mean
// the item was curated: an untouched track with a cover in its tags
// reports one art row sourced "tag".
type FieldProvenanceDTO struct {
	Field     string
	Source    string
	Provider  string
	SourceURL string
	Locked    bool
	UpdatedAt time.Time
}

// CreditDTO is one credit role with its people in stored order.
type CreditDTO struct {
	Role  string
	Names []string
}

// LyricsStateDTO summarizes stored lyrics for the editor.
type LyricsStateDTO struct {
	Synced   bool
	Source   string
	Provider string
	LRC      string
}

// CustomTagDTO is one custom tag.
type CustomTagDTO struct {
	Key    string
	Values []string
}

// WriteBackIssueDTO is one file out of step with the catalog.
type WriteBackIssueDTO struct {
	FilePID string
	Code    string
	TagKey  string
	Detail  string
}

// EntityCuratedFieldDTO is one curated entity field.
type EntityCuratedFieldDTO struct {
	Field     string
	Value     string
	Source    string
	Locked    bool
	UpdatedAt time.Time
}

// ItemMetadataDTO is everything the editor shows for one item.
type ItemMetadataDTO struct {
	PID             string
	MediaType       string
	Fields          map[string]string
	LockedFields    []string
	Provenance      []FieldProvenanceDTO
	Credits         []CreditDTO
	Lyrics          *LyricsStateDTO
	Chapters        []ChapterMark
	CustomTags      []CustomTagDTO
	Unofficial      bool
	VirtualTrack    bool
	HasArtwork      bool
	HasOwnArtwork   bool
	WriteBackIssues []WriteBackIssueDTO
	// The entity handles behind the display text, as ItemSummary carries
	// them. Empty when absent; AlbumPID and ReleaseGroupPID are
	// track-only, and the release group is additionally empty for a track
	// whose album has none, which is its own state rather than a missing
	// album.
	ArtistPID       string
	AlbumPID        string
	ReleaseGroupPID string
	// Whether the caller may edit any of this. The read is visible to
	// everyone who can see the item and the edits are not, so the
	// answer travels with the document rather than being re-derived
	// from a role by whoever drew the form.
	//
	// Nil where the ownership lookup failed: unanswered rather than
	// refused, because a client that turns a no into a refusal screen
	// must not be handed one by a transient database error.
	MayCurate *bool
	// How the item entered the library, when the catalog holds an
	// origin row. Read-only evidence rather than a field: nothing in
	// the edit surface writes it.
	Acquisition *ItemAcquisitionDTO
}

// ItemAcquisitionDTO is one item's recorded origin, redacted for a
// reader who is only known to be able to see the item.
type ItemAcquisitionDTO struct {
	SourceType string
	// The origin URL with userinfo and query stripped, and empty for
	// anything that is not http(s). See redactedSourceURL.
	SourceURL string
	// The origin's identifier in the provider's namespace, verbatim:
	// an id carries no credentials, and a correction needs to see the
	// standing one before rewriting it.
	SourceID   string
	Provider   string
	AcquiredAt time.Time
	// Whether the row is held against automatic rewrites - an import
	// re-recording over it, a scan re-deriving it from tags still in
	// the file.
	Locked bool
}

// MetadataEditParams carries the shared edit switches.
type MetadataEditParams struct {
	WriteBack bool
	Lock      bool
	Force     bool
}
