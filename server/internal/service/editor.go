package service

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin"
	waxart "github.com/colespringer/waxbin/art"
	"github.com/colespringer/waxbin/model"
	waxlabel "github.com/colespringer/waxlabel"
)

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
}

// WriteBackFailureDTO is one file a write-back could not update.
type WriteBackFailureDTO struct {
	FilePID string
	Path    string
	Reason  string
}

// EditOutcomeDTO reports a committed catalog edit: write-back failures
// and non-fatal warnings ride along, never an error.
type EditOutcomeDTO struct {
	Failures []WriteBackFailureDTO
	Warnings []string
}

// BulkEditOutcomeDTO reports a bulk edit's per-item outcomes.
type BulkEditOutcomeDTO struct {
	Edited   []string
	Skipped  []string
	Failures []WriteBackFailureDTO
}

// TagEditOutcomeDTO reports a custom-tag edit.
type TagEditOutcomeDTO struct {
	Key    string
	Stored int
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
}

// MetadataEditParams carries the shared edit switches.
type MetadataEditParams struct {
	WriteBack bool
	Lock      bool
	Force     bool
}

// --- field vocabulary ------------------------------------------------------------

// editorTrackFields is the track scalar vocabulary; every track field
// has an on-disk tag form.
var editorTrackFields = []EditableFieldDTO{
	{"title", true}, {"artist", true}, {"album_artist", true}, {"album", true},
	{"composer", true}, {"composer_sort", true}, {"comment", true}, {"genre", true},
	{"year", true}, {"track_no", true}, {"disc_no", true}, {"isrc", true},
	{"mbid", true}, {"compilation", true},
}

// editorBookFields is the book scalar vocabulary. Only the fields the
// audiobook scanner reconstructs from tags write back; the enrichment
// fields (subtitle, identifiers, publisher, edition, description, mbid)
// are database-only by upstream design.
var editorBookFields = []EditableFieldDTO{
	{"title", true}, {"author", true}, {"author_sort", true}, {"narrator", true},
	{"series", true}, {"subtitle", false}, {"genre", true}, {"year", true},
	{"asin", false}, {"isbn", false}, {"publisher", false}, {"edition", false},
	{"description", false}, {"mbid", false},
}

// editorEpisodeFields is the episode scalar vocabulary. Episodes are
// not tagged files upstream, so nothing writes back.
var editorEpisodeFields = []EditableFieldDTO{
	{"title", false}, {"description", false}, {"pinned", false}, {"season", false},
	{"episode_no", false}, {"episode_type", false}, {"explicit", false},
	{"link", false},
}

// editorMusicRoles are the track credit roles; each has a canonical tag
// key for write-back.
var editorMusicRoles = []EditableFieldDTO{
	{"composer", true}, {"lyricist", true}, {"conductor", true}, {"performer", true},
	{"remixer", true}, {"producer", true}, {"engineer", true}, {"mixer", true},
	{"arranger", true}, {"writer", true}, {"djmixer", true},
}

// editorBookRoles are the book credit roles; translator and editor have
// no round-trippable tag form and stay database-only.
var editorBookRoles = []EditableFieldDTO{
	{"author", true}, {"narrator", true}, {"translator", false}, {"editor", false},
}

// editorEntityFields is the entity edit vocabulary. Only an album's
// release identifiers and sort, and an artist's sort, fan out to member
// files; entity MBIDs and release-group fields stay database-only.
var editorEntityFields = []EntityTypeFieldsDTO{
	{EntityType: "artist", Fields: []EditableFieldDTO{{"sort", true}, {"mbid", false}}},
	{EntityType: "release-group", Fields: []EditableFieldDTO{{"sort", false}, {"mbid", false}, {"type", false}}},
	{EntityType: "album", Fields: []EditableFieldDTO{
		{"sort", true}, {"mbid", false}, {"barcode", true}, {"label", true}, {"catalog_number", true},
	}},
}

// editorFieldsForKind returns the ordered scalar vocabulary for a kind.
func editorFieldsForKind(k model.Kind) []EditableFieldDTO {
	switch k {
	case model.KindBook:
		return editorBookFields
	case model.KindEpisode:
		return editorEpisodeFields
	default:
		return editorTrackFields
	}
}

// editorRolesForKind returns the credit role vocabulary for a kind.
func editorRolesForKind(k model.Kind) []EditableFieldDTO {
	switch k {
	case model.KindBook:
		return editorBookRoles
	case model.KindEpisode:
		return nil
	default:
		return editorMusicRoles
	}
}

// MetadataFieldVocabulary is the fields endpoint's payload: the scalar
// and credit vocabulary per item kind plus the entity edit vocabulary.
func (l *Library) MetadataFieldVocabulary() MetadataFieldsDTO {
	kinds := []model.Kind{model.KindTrack, model.KindBook, model.KindEpisode}
	out := MetadataFieldsDTO{Kinds: make([]KindFieldsDTO, 0, len(kinds))}
	for _, k := range kinds {
		roles := editorRolesForKind(k)
		if roles == nil {
			roles = []EditableFieldDTO{}
		}
		out.Kinds = append(out.Kinds, KindFieldsDTO{
			Kind:        mediaTypeForKind(k),
			Fields:      editorFieldsForKind(k),
			CreditRoles: roles,
		})
	}
	out.EntityTypes = editorEntityFields
	return out
}

// --- identifier validation --------------------------------------------------------

// Upstream stores identifier values unvalidated; the spec promises the
// server format-checks them, so the checks live here.
var (
	editorISRCRe    = regexp.MustCompile(`^[A-Za-z]{2}[A-Za-z0-9]{3}[0-9]{7}$`)
	editorASINRe    = regexp.MustCompile(`^[A-Za-z0-9]{10}$`)
	editorBarcodeRe = regexp.MustCompile(`^([0-9]{8}|[0-9]{12,14})$`)
	editorMBIDRe    = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)
)

func validISRC(s string) bool { return editorISRCRe.MatchString(s) }

func validASIN(s string) bool { return editorASINRe.MatchString(s) }

func validBarcode(s string) bool { return editorBarcodeRe.MatchString(s) }

func validMBID(s string) bool { return editorMBIDRe.MatchString(s) }

// validISBN checks a 10 or 13 digit ISBN, hyphens and spaces ignored,
// including its checksum. ISBN-10 allows the X check digit.
func validISBN(s string) bool {
	cleaned := strings.Map(func(r rune) rune {
		if r == '-' || r == ' ' {
			return -1
		}
		return r
	}, s)
	switch len(cleaned) {
	case 10:
		sum := 0
		for i, r := range cleaned {
			var v int
			switch {
			case r >= '0' && r <= '9':
				v = int(r - '0')
			case (r == 'X' || r == 'x') && i == 9:
				v = 10
			default:
				return false
			}
			sum += (10 - i) * v
		}
		return sum%11 == 0
	case 13:
		sum := 0
		for i, r := range cleaned {
			if r < '0' || r > '9' {
				return false
			}
			w := 1
			if i%2 == 1 {
				w = 3
			}
			sum += w * int(r-'0')
		}
		return sum%10 == 0
	default:
		return false
	}
}

// validYear reports whether s is the non-negative integer WaxBin's year field
// accepts; any other value fails the whole edit, so an enrich pass drops it.
func validYear(s string) bool {
	s = strings.TrimSpace(s)
	if s == "" {
		return false
	}
	n, err := strconv.Atoi(s)
	return err == nil && n >= 0
}

// validateIdentifierField rejects a malformed identifier value; the
// empty string always passes (it clears the field).
func validateIdentifierField(name, value string) error {
	if value == "" {
		return nil
	}
	bad := false
	switch name {
	case "isrc":
		bad = !validISRC(value)
	case "isbn":
		bad = !validISBN(value)
	case "asin":
		bad = !validASIN(value)
	case "barcode":
		bad = !validBarcode(value)
	case "mbid":
		bad = !validMBID(value)
	}
	if bad {
		return errInvalid(name + " is not a valid identifier: " + value)
	}
	return nil
}

// validateFieldEdits checks a scalar edit against the kind's vocabulary
// and the write-back policy (episodes never write back).
func validateFieldEdits(it *model.ItemView, fields map[string]string, writeBack bool) error {
	if len(fields) == 0 {
		return errInvalid("at least one field edit is required")
	}
	if writeBack && it.Kind == model.KindEpisode {
		return errInvalid("podcast episodes never write back to files; edits are database-only by upstream design")
	}
	allowed := map[string]bool{}
	for _, f := range editorFieldsForKind(it.Kind) {
		allowed[f.Name] = true
	}
	for name, value := range fields {
		if !allowed[name] {
			return errInvalid("field " + name + " is not editable on a " + mediaTypeForKind(it.Kind) + " item")
		}
		if err := validateIdentifierField(name, value); err != nil {
			return err
		}
	}
	return nil
}

// editOutcomeFromWriteBack converts an upstream write-back error into
// result failures; any other error passes through classified.
func editOutcomeFromWriteBack(err error) (EditOutcomeDTO, error) {
	if err == nil {
		return EditOutcomeDTO{}, nil
	}
	var wbe *waxbin.WriteBackError
	if errors.As(err, &wbe) {
		return EditOutcomeDTO{Failures: writeBackFailures(wbe)}, nil
	}
	return EditOutcomeDTO{}, classify(err)
}

func writeBackFailures(wbe *waxbin.WriteBackError) []WriteBackFailureDTO {
	out := make([]WriteBackFailureDTO, 0, len(wbe.Failures))
	for _, f := range wbe.Failures {
		out = append(out, WriteBackFailureDTO{
			FilePID: string(f.FilePID), Path: f.Path, Reason: f.Reason,
		})
	}
	return out
}

// --- scalar edits -----------------------------------------------------------------

// EditItemMetadata applies scalar field edits to one item's catalog
// row, optionally mirroring them into the backing file's tags.
func (l *Library) EditItemMetadata(ctx context.Context, uc *UserCtx, apiPID string, fields map[string]string, p MetadataEditParams) (EditOutcomeDTO, error) {
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if err := validateFieldEdits(it, fields, p.WriteBack); err != nil {
		return EditOutcomeDTO{}, err
	}
	if p.WriteBack {
		if err := l.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	err = l.lib.EditFields(ctx, it.PID, fields, waxbin.EditOptions{
		WriteBack: p.WriteBack, Lock: model.LockOf(p.Lock), Force: p.Force,
	})
	return editOutcomeFromWriteBack(err)
}

// BulkEditMetadata applies the same scalar edits to many items in one
// atomic catalog batch. With skipLocked, items whose target fields are
// locked are reported instead of failing the batch; write-back failures
// are per item and never undo the catalog batch.
func (l *Library) BulkEditMetadata(ctx context.Context, uc *UserCtx, apiPIDs []string, fields map[string]string, writeBack, skipLocked, force bool) (BulkEditOutcomeDTO, error) {
	if len(apiPIDs) == 0 {
		return BulkEditOutcomeDTO{}, errInvalid("at least one item is required")
	}
	if len(apiPIDs) > 1000 {
		return BulkEditOutcomeDTO{}, errInvalid("at most 1000 items per bulk edit")
	}
	if skipLocked && force {
		return BulkEditOutcomeDTO{}, errInvalid("skipLocked and force are mutually exclusive")
	}
	pids := make([]model.PID, 0, len(apiPIDs))
	apiByBare := make(map[model.PID]string, len(apiPIDs))
	for _, apiPID := range apiPIDs {
		it, err := l.getVisibleItem(ctx, uc, apiPID)
		if err != nil {
			return BulkEditOutcomeDTO{}, err
		}
		if err := validateFieldEdits(it, fields, writeBack); err != nil {
			return BulkEditOutcomeDTO{}, err
		}
		if writeBack {
			if err := l.checkPathWritable(ctx, string(it.Path)); err != nil {
				return BulkEditOutcomeDTO{}, err
			}
		}
		if _, seen := apiByBare[it.PID]; seen {
			continue
		}
		pids = append(pids, it.PID)
		apiByBare[it.PID] = apiPID
	}
	res, err := l.lib.EditManyFields(ctx, pids, fields, waxbin.EditOptions{
		WriteBack: writeBack, Force: force, SkipLocked: skipLocked,
		Lock: model.LockOn,
	})
	if err != nil {
		return BulkEditOutcomeDTO{}, classify(err)
	}
	out := BulkEditOutcomeDTO{Edited: []string{}, Skipped: []string{}}
	for _, pid := range res.Edited {
		out.Edited = append(out.Edited, apiByBare[pid])
	}
	for _, pid := range res.Skipped {
		out.Skipped = append(out.Skipped, apiByBare[pid])
	}
	for _, wbe := range res.WriteBackErrors {
		out.Failures = append(out.Failures, writeBackFailures(wbe)...)
	}
	return out, nil
}

// --- credits ----------------------------------------------------------------------

// SetItemCredits replaces one contributor role's people. A book
// translator or editor credit has no tag form: a write-back request for
// those still edits the catalog and answers with a warning.
func (l *Library) SetItemCredits(ctx context.Context, uc *UserCtx, apiPID, role string, names []string, p MetadataEditParams) (EditOutcomeDTO, error) {
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	r := model.ContributorRole(strings.ToLower(strings.TrimSpace(role)))
	if !model.RoleValidForKind(r, it.Kind) {
		return EditOutcomeDTO{}, errInvalid("role " + role + " does not apply to a " + mediaTypeForKind(it.Kind) + " item")
	}
	if len(names) > 100 {
		return EditOutcomeDTO{}, errInvalid("at most 100 names per role")
	}
	var warnings []string
	writeBack := p.WriteBack
	if writeBack && (r == model.RoleTranslator || r == model.RoleEditor) {
		// No round-trippable tag exists for these roles; the catalog edit
		// still lands and the caller learns why the files stay untouched.
		writeBack = false
		warnings = append(warnings, "role "+string(r)+" has no on-disk tag form; the credit is database-only")
	}
	if writeBack {
		if err := l.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	_, err = l.lib.SetCredits(ctx, it.PID, r, names, waxbin.CreditEditOptions{
		WriteBack: writeBack, Lock: model.LockOf(p.Lock), Force: p.Force,
	})
	out, err := editOutcomeFromWriteBack(err)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	out.Warnings = append(out.Warnings, warnings...)
	return out, nil
}

// --- lyrics -----------------------------------------------------------------------

// SetItemLyrics stores replacement lyrics (parsed LRC and/or a plain
// block) with user provenance. With writeBack the .lrc sidecar is
// written next to the backing file with crash-safe discipline. Embedded
// tag write-back is deliberately skipped here: the catalog row plus the
// sidecar carry the contract, and embedded lyrics follow along on the
// next tag write (MP4 and Matroska refuse embedded synced lyrics
// upstream anyway, so the sidecar is the durable form).
func (l *Library) SetItemLyrics(ctx context.Context, uc *UserCtx, apiPID, lrc, plain string, p MetadataEditParams) (EditOutcomeDTO, error) {
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if len(lrc) > 200000 || len(plain) > 200000 {
		return EditOutcomeDTO{}, errInvalid("lyrics are limited to 200000 characters per block")
	}
	if p.WriteBack && it.Kind == model.KindEpisode {
		return EditOutcomeDTO{}, errInvalid("podcast episodes never write back to files; edits are database-only by upstream design")
	}
	var warnings []string
	var synced []model.SyncedLine
	if lrc != "" {
		lines, dropped := waxlabel.ParseLRCReportFull(lrc)
		for _, n := range dropped {
			warnings = append(warnings, "lrc line "+strconv.Itoa(n)+": malformed line skipped")
		}
		synced = make([]model.SyncedLine, 0, len(lines))
		for _, ln := range lines {
			synced = append(synced, model.SyncedLine{TimeMS: ln.Time.Milliseconds(), Text: ln.Text})
		}
	}
	ly := &model.Lyrics{Source: model.SourceUser, Synced: synced, Unsynced: plain}
	if !ly.HasContent() {
		return EditOutcomeDTO{}, errInvalid("lyrics must carry timed lines or plain text")
	}
	if p.WriteBack {
		if err := l.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	if err := l.lib.SetLyrics(ctx, it.PID, ly, model.LockOf(p.Lock), p.Force); err != nil {
		return EditOutcomeDTO{}, classify(err)
	}
	out := EditOutcomeDTO{Warnings: warnings}
	if p.WriteBack {
		if fail := l.writeLyricsSidecar(it, synced, plain); fail != nil {
			out.Failures = append(out.Failures, *fail)
		}
	}
	return out, nil
}

// writeLyricsSidecar writes the .lrc sidecar next to the item's backing
// file. The catalog edit has already committed, so any refusal or
// failure is reported as a write-back failure, never an error.
func (l *Library) writeLyricsSidecar(it *model.ItemView, synced []model.SyncedLine, plain string) *WriteBackFailureDTO {
	fail := func(path, reason string) *WriteBackFailureDTO {
		return &WriteBackFailureDTO{FilePID: string(it.FilePID), Path: path, Reason: reason}
	}
	if it.Virtual {
		return fail(it.DisplayPath, "the backing file is shared by several items; sidecar write-back is refused")
	}
	path := string(it.Path)
	if path == "" {
		path = it.DisplayPath
	}
	if path == "" {
		return fail("", "no backing file path is known")
	}
	var content string
	if len(synced) > 0 {
		lines := make([]waxlabel.SyncedLine, 0, len(synced))
		for _, ln := range synced {
			lines = append(lines, waxlabel.SyncedLine{
				Time: time.Duration(ln.TimeMS) * time.Millisecond, Text: ln.Text,
			})
		}
		content = waxlabel.FormatLRC(lines)
	} else {
		content = plain
	}
	if !strings.HasSuffix(content, "\n") {
		content += "\n"
	}
	sidecar := strings.TrimSuffix(path, filepath.Ext(path)) + ".lrc"
	if err := writeFileCrashSafe(sidecar, []byte(content)); err != nil {
		return fail(sidecar, "sidecar write failed: "+err.Error())
	}
	return nil
}

// writeFileCrashSafe writes bytes with the repo's durability rule:
// temp file in the target directory, verify the written bytes, fsync,
// atomic rename, fsync the directory.
func writeFileCrashSafe(path string, data []byte) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".tmp*")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	written, err := os.ReadFile(tmpName)
	if err != nil {
		return err
	}
	if !bytes.Equal(written, data) {
		return errors.New("verification re-read does not match the written bytes")
	}
	if err := os.Rename(tmpName, path); err != nil {
		return err
	}
	if d, err := os.Open(dir); err == nil {
		_ = d.Sync()
		d.Close()
	}
	return nil
}

// ClearItemLyrics removes the stored lyrics and their lock; files are
// untouched. Force is implied: the caller explicitly chose the clear,
// and the lock exists to fend off scans and enrichment.
func (l *Library) ClearItemLyrics(ctx context.Context, uc *UserCtx, apiPID string) error {
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return err
	}
	if err := l.lib.SetLyrics(ctx, it.PID, nil, model.LockOff, true); err != nil {
		return classify(err)
	}
	return nil
}

// --- chapters ---------------------------------------------------------------------

// SetBookChapters replaces an audiobook's chapter list; an empty list
// restores the embedded chapters. Chapters are addressed on the book
// timeline (StartMS/EndMS spanning all parts, symmetric with the read);
// the facade splits them across a multi-file book's parts internally, so
// the same flat list works for single- and multi-file books alike.
func (l *Library) SetBookChapters(ctx context.Context, uc *UserCtx, apiPID string, chapters []ChapterMark, lock, force bool) (EditOutcomeDTO, error) {
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if it.Kind != model.KindBook {
		return EditOutcomeDTO{}, errInvalid("chapters are only editable on audiobooks")
	}
	if err := validateChapterList(chapters); err != nil {
		return EditOutcomeDTO{}, err
	}
	// Book-timeline offsets go straight to the facade, which resolves each
	// chapter to the part that backs it and stores per-part file offsets.
	stored := make([]model.Chapter, 0, len(chapters))
	for i, ch := range chapters {
		stored = append(stored, model.Chapter{
			Position: i, Title: ch.Title, StartMS: ch.StartMS, EndMS: ch.EndMS,
		})
	}
	if err := l.lib.SetChapters(ctx, it.PID, stored, model.LockOf(lock), force); err != nil {
		return EditOutcomeDTO{}, classify(err)
	}
	return EditOutcomeDTO{}, nil
}

// validateChapterList enforces ordered, non-overlapping chapters with
// sequential indexes; only the final chapter may be open-ended.
func validateChapterList(chapters []ChapterMark) error {
	if len(chapters) > 2000 {
		return errInvalid("at most 2000 chapters")
	}
	for i, ch := range chapters {
		if ch.Index != i {
			return errInvalid("chapter indexes must run sequentially from 0")
		}
		if ch.StartMS < 0 {
			return errInvalid("chapter start must not be negative")
		}
		if ch.EndMS != 0 && ch.EndMS <= ch.StartMS {
			return errInvalid("chapter end must be after its start")
		}
		if ch.EndMS == 0 && i != len(chapters)-1 {
			return errInvalid("only the final chapter may be open-ended")
		}
		if i > 0 {
			prev := chapters[i-1]
			if ch.StartMS < prev.EndMS || ch.StartMS <= prev.StartMS {
				return errInvalid("chapters must be ordered and non-overlapping")
			}
		}
	}
	return nil
}

// --- artwork ----------------------------------------------------------------------

// validateArtworkBytes enforces the size cap and that the body is a
// picture the catalog can recognize.
//
// The recognizer is the store's own: art.Describe decodes what there is
// a decoder for - JPEG, PNG, GIF, WebP, BMP, TIFF - and magic-sniffs the
// exotic ISOBMFF containers (AVIF, HEIC) it cannot decode, which is
// exactly the set the store will hold. Asking it here rather than
// letting the store refuse further in keeps a refusal a 415 with a
// sentence instead of a write that fails halfway, and it is the one
// check that cannot be talked out of: the store falls back to a
// caller-named format for bytes it does not recognize, so an nginx error
// page named as a TIFF would otherwise be stored as somebody's cover and
// embedded into every backing file behind it.
func validateArtworkBytes(raw []byte) error {
	if len(raw) == 0 {
		return errInvalid("an image body is required")
	}
	if len(raw) > maxArtworkBytes {
		return errInvalid("artwork is limited to 16 MiB")
	}
	if waxart.Describe(raw).Format == "" {
		return &Error{Kind: KindFormat, Msg: "the body is not a recognized image"}
	}
	return nil
}

// SetItemArtwork stores raw image bytes as the item's front cover.
// Force is implied on the catalog write: the caller chose the image, so
// an existing lock (set by an earlier artwork edit) never blocks the
// replacement, per the spec's no-silent-downgrade wording.
func (l *Library) SetItemArtwork(ctx context.Context, uc *UserCtx, apiPID, role string, raw []byte, writeBack, lock bool) (EditOutcomeDTO, error) {
	art, ok := model.ParseArtRole(role)
	if !ok {
		return EditOutcomeDTO{}, errInvalid("unknown art role " + role)
	}
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if err := validateArtworkBytes(raw); err != nil {
		return EditOutcomeDTO{}, err
	}
	// Write-back embeds a front cover into the backing files; the auxiliary
	// slots are catalog-only, so a write-back request on one is ignored.
	writeBack = writeBack && art == model.ArtRoleFront
	if writeBack {
		if err := l.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	out, err := editOutcomeFromWriteBack(l.lib.SetItemArt(ctx, it.PID, art, raw, waxbin.ArtEditOptions{
		WriteBack: writeBack, Lock: model.LockOf(lock), Force: true,
	}))
	if err == nil {
		// The catalog write committed (a write-back failure rides the
		// outcome, not the error). A generated playlist cover may have been
		// built from this item's old art, and a replacement in place moves
		// no membership, so the epoch is what tells those covers to rebuild.
		l.noteArtworkChanged(ctx)
	}
	return out, err
}

// ClearItemArtwork removes the stored item art in one slot. A cleared front
// cover falls back to the entity chain; the other slots have no fallback.
// Files are untouched.
func (l *Library) ClearItemArtwork(ctx context.Context, uc *UserCtx, apiPID, role string) error {
	art, ok := model.ParseArtRole(role)
	if !ok {
		return errInvalid("unknown art role " + role)
	}
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return err
	}
	// The pin is left exactly as it stands, for the reason ClearEntityArtwork
	// leaves it: clearing says "there is no cover", not "refill this". Force
	// is what lets the clear through a pinned slot, which is the one action
	// the artwork manager offers there.
	if err := l.lib.SetItemArt(ctx, it.PID, art, nil, waxbin.ArtEditOptions{
		Lock: model.LockUnchanged, Force: true,
	}); err != nil {
		return classify(err)
	}
	l.noteArtworkChanged(ctx)
	return nil
}

// EntityArtworkLock reports whether an entity's front cover is pinned.
// It is what explains an entity that shows no cover and refuses every
// attempt to give it one: the cover was cleared and the pin left
// standing, which is the one artwork state nothing else surfaces.
func (l *Library) EntityArtworkLock(ctx context.Context, entityType, apiEntityPID string) (bool, error) {
	ent, pid, err := lockableArtEntity(entityType, apiEntityPID)
	if err != nil {
		return false, err
	}
	locked, err := l.lib.ArtLocked(ctx, ent, pid)
	if err != nil {
		return false, classify(err)
	}
	return locked, nil
}

// SetEntityArtworkLock pins or unpins an entity's front cover without
// touching the cover itself, which setting artwork cannot express: that
// always writes the image slot too. Unpinning here is the way out of a
// cover that was cleared and left pinned.
func (l *Library) SetEntityArtworkLock(ctx context.Context, entityType, apiEntityPID string, lock bool) (bool, error) {
	ent, pid, err := lockableArtEntity(entityType, apiEntityPID)
	if err != nil {
		return false, err
	}
	was, err := l.lib.ArtLocked(ctx, ent, pid)
	if err != nil {
		return false, classify(err)
	}
	if err := l.lib.SetArtLock(ctx, ent, pid, lock); err != nil {
		return false, classify(err)
	}
	// Only on a change. The artwork epoch is what tells every generated
	// playlist cover to re-composite, and a pin moves no bytes: bumping
	// it for a lock that already read this way would rebuild every
	// mosaic in the library to record nothing.
	if was != lock {
		l.noteArtworkChanged(ctx)
	}
	return lock, nil
}

// lockableArtEntity resolves an entity type and pid for the pin surface,
// refusing playlists.
//
// The refusal is structural rather than a matter of the three playlist
// art call sites agreeing forever. A playlist's cover authority is its
// own custom/generated origin marker; a pin standing on one makes the
// mosaic unwritable, and clearPlaylistArtwork deletes the origin marker
// before clearing the art, so the next read composites, is refused, and
// returns before recording the fingerprint. Every later read then
// re-resolves every member, composites again, and is refused again -
// permanently, on the read path.
func lockableArtEntity(entityType, apiEntityPID string) (model.ArtEntity, model.PID, error) {
	ent, ok := artEntityForType(entityType)
	if !ok {
		return "", "", errInvalid("unknown entity type " + entityType)
	}
	if ent == model.ArtPlaylist {
		return "", "", errInvalid("a playlist cover has no pin; clearing one hands the slot back to the generated mosaic")
	}
	pid, err := editorEntityPID(entityType, apiEntityPID)
	if err != nil {
		return "", "", err
	}
	return ent, pid, nil
}

// artEntityForType maps an API entity type to the art entity vocabulary.
func artEntityForType(entityType string) (model.ArtEntity, bool) {
	switch entityType {
	case "album":
		return model.ArtAlbum, true
	case "artist":
		return model.ArtArtist, true
	case "release-group":
		return model.ArtReleaseGroup, true
	case "genre":
		return model.ArtGenre, true
	case "playlist":
		return model.ArtPlaylist, true
	default:
		return "", false
	}
}

// EntityArtworkOwned reports whether an entity type's artwork belongs to
// a user rather than to the catalog. A playlist cover is the owner's;
// every catalog entity is administrators-only, which is what the API
// layer checks before it gets here.
func EntityArtworkOwned(entityType string) bool { return entityType == "playlist" }

// mergeEntityForType maps an API entity type to the curation entity
// vocabulary.
func mergeEntityForType(entityType string) (model.MergeEntity, bool) {
	switch entityType {
	case "album":
		return model.MergeAlbum, true
	case "artist":
		return model.MergeArtist, true
	case "release-group":
		return model.MergeReleaseGroup, true
	case "genre":
		return model.MergeGenre, true
	default:
		return "", false
	}
}

// editorEntityPID parses an entity's API pid. Albums and artists carry
// established prefixes and are checked against them. Release groups
// mint `rg-` on reads now, but this stays permissive for them and for
// genres: both have accepted any well-formed prefix since before the
// read existed, and tightening it would refuse pids clients already
// hold.
func editorEntityPID(entityType, apiEntityPID string) (model.PID, error) {
	prefix, pid, ok := parseAPIPID(apiEntityPID)
	if !ok {
		return "", errNotFound("no " + entityType + " with pid " + apiEntityPID)
	}
	switch entityType {
	case "album":
		if prefix != PrefixAlbum {
			return "", errNotFound("no album with pid " + apiEntityPID)
		}
	case "artist":
		if prefix != PrefixArtist {
			return "", errNotFound("no artist with pid " + apiEntityPID)
		}
	}
	return pid, nil
}

// SetEntityArtwork stores durable front-cover art on an entity. Albums
// may fan the cover into member files with writeBack; other entity
// types are catalog-only (the facade treats their write-back as a
// no-op). A playlist takes its owner's cover here, over the one the
// server generates from its members.
func (l *Library) SetEntityArtwork(ctx context.Context, uc *UserCtx, entityType, apiEntityPID, role string, raw []byte, writeBack bool) (EditOutcomeDTO, error) {
	art, ok := model.ParseArtRole(role)
	if !ok {
		return EditOutcomeDTO{}, errInvalid("unknown art role " + role)
	}
	ent, ok := artEntityForType(entityType)
	if !ok {
		return EditOutcomeDTO{}, errInvalid("unknown entity type " + entityType)
	}
	if err := validateArtworkBytes(raw); err != nil {
		return EditOutcomeDTO{}, err
	}
	if ent == model.ArtPlaylist {
		return l.setPlaylistArtwork(ctx, uc, apiEntityPID, art, raw)
	}
	pid, err := editorEntityPID(entityType, apiEntityPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	// Only a front cover fans into member files; the auxiliary slots are
	// catalog-only. Entity write-back crosses libraries, so the server-wide
	// flag gates it (per-library precision would need the member enumeration
	// the facade does internally).
	writeBack = writeBack && art == model.ArtRoleFront
	if writeBack {
		if err := l.CheckWritable(ctx, ""); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	// Pin it, and override whatever pin stood before. The caller chose
	// this image, which is the same rule the item path states, and the
	// pin is what carries it through an enrichment run that would
	// otherwise refill the slot from a provider.
	out, err := editOutcomeFromWriteBack(l.lib.SetEntityArt(ctx, ent, pid, art, raw, waxbin.ArtEditOptions{
		WriteBack: writeBack, Lock: model.LockOn, Force: true,
	}))
	if err == nil {
		// An album or artist cover is what a member track resolves when it
		// carries none of its own, so this moves playlist covers too.
		l.noteArtworkChanged(ctx)
	}
	return out, err
}

// ClearEntityArtwork removes one artwork slot from an entity. Files
// already carrying an embedded cover keep it; this clears the catalog's
// copy. Clearing a playlist's uploaded cover hands the slot back to the
// generated mosaic rather than leaving the playlist bare.
func (l *Library) ClearEntityArtwork(ctx context.Context, uc *UserCtx, entityType, apiEntityPID, role string) error {
	art, ok := model.ParseArtRole(role)
	if !ok {
		return errInvalid("unknown art role " + role)
	}
	ent, ok := artEntityForType(entityType)
	if !ok {
		return errInvalid("unknown entity type " + entityType)
	}
	if ent == model.ArtPlaylist {
		return l.clearPlaylistArtwork(ctx, uc, apiEntityPID, art)
	}
	pid, err := editorEntityPID(entityType, apiEntityPID)
	if err != nil {
		return err
	}
	// No write-back on a clear: a cover already embedded in a file is the
	// file's, and stripping it is the organizer's business, not this
	// endpoint's.
	//
	// The pin is left exactly as it stands rather than dropped. Clearing a
	// catalog entity's cover says "there is no cover", not "give me the
	// default back", so a cleared-and-pinned cover is a real intent - do not
	// refill this - and it is a state ArtRoles reports and the lock endpoint
	// below can undo. Force skips the lock check and nothing else, so the
	// clear goes through a pinned slot without rewriting the pin.
	if err := l.lib.SetEntityArt(ctx, ent, pid, art, nil, waxbin.ArtEditOptions{
		Lock: model.LockUnchanged, Force: true,
	}); err != nil {
		return classify(err)
	}
	l.noteArtworkChanged(ctx)
	return nil
}

// setPlaylistArtwork stores an owner's cover and records it as custom,
// so the member-derived mosaic stops overwriting it.
func (l *Library) setPlaylistArtwork(ctx context.Context, uc *UserCtx, apiPlaylistPID string, role model.ArtRole, raw []byte) (EditOutcomeDTO, error) {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	// Claim the slot before storing the image, and fail the request if the
	// claim cannot be recorded. Both halves matter: with the image first,
	// a concurrent playlist read regenerates the mosaic over the upload in
	// the window between them, and with a best-effort claim the endpoint
	// answers 200 while the next read overwrites what the user just
	// uploaded. Only the front cover is the playlist's face; an auxiliary
	// slot does not displace the generated one.
	var undoClaim func()
	if role == model.ArtRoleFront {
		undo, err := l.claimPlaylistCoverCustom(ctx, pl.PID)
		if err != nil {
			return EditOutcomeDTO{}, classify(err)
		}
		undoClaim = undo
	}
	// A playlist has no files to write a cover back into: it is a
	// terminal art level with no ancestry and no members of its own.
	//
	// Never pinned, here or in the two paths below. A playlist's cover
	// authority is WaxDeck's own playlist_cover origin marker, which
	// claimPlaylistCoverCustom just set; a pin would additionally make
	// the generated mosaic unwritable, and the generator retries on
	// every read.
	if err := l.lib.SetEntityArt(ctx, model.ArtPlaylist, pl.PID, role, raw, waxbin.ArtEditOptions{
		Lock: model.LockOff, Force: true,
	}); err != nil {
		if undoClaim != nil {
			// Nothing was stored, so the claim has to go back the way it was
			// or the next read leaves the previous cover in place while
			// believing it is a custom one.
			undoClaim()
		}
		return EditOutcomeDTO{}, classify(err)
	}
	return EditOutcomeDTO{}, nil
}

// clearPlaylistArtwork drops an owner's cover and rebuilds the mosaic
// in its place, so clearing gives the default back rather than nothing.
func (l *Library) clearPlaylistArtwork(ctx context.Context, uc *UserCtx, apiPlaylistPID string, role model.ArtRole) error {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return err
	}
	// Drop the provenance before the art, and fail on it. The other order
	// leaves the playlist bare with a custom marker on it, which no later
	// read repairs: the marker is exactly what stops regeneration.
	if role == model.ArtRoleFront {
		if err := l.db.DeletePlaylistCover(ctx, string(pl.PID)); err != nil {
			return classify(err)
		}
		pl.HasArt = false
	}
	if err := l.lib.SetEntityArt(ctx, model.ArtPlaylist, pl.PID, role, nil, waxbin.ArtEditOptions{
		Lock: model.LockOff, Force: true,
	}); err != nil {
		return classify(err)
	}
	if role == model.ArtRoleFront {
		l.refreshPlaylistCover(ctx, pl)
	}
	return nil
}

// --- custom tags ------------------------------------------------------------------

// SetItemTag replaces one custom tag's ordered values. The catalog
// canonicalizes the key and rejects reserved keys it owns through
// another surface.
func (l *Library) SetItemTag(ctx context.Context, uc *UserCtx, apiPID, key string, values []string, lock, force bool) (TagEditOutcomeDTO, error) {
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return TagEditOutcomeDTO{}, err
	}
	if len(values) > 100 {
		return TagEditOutcomeDTO{}, errInvalid("at most 100 values per tag")
	}
	canon, stored, err := l.lib.SetItemTag(ctx, it.PID, key, values, waxbin.TagEditOptions{
		Lock: model.LockOf(lock), Force: force,
	})
	if err != nil {
		return TagEditOutcomeDTO{}, classify(err)
	}
	return TagEditOutcomeDTO{Key: canon, Stored: stored}, nil
}

// ClearItemTag removes the tag and its lock.
func (l *Library) ClearItemTag(ctx context.Context, uc *UserCtx, apiPID, key string) error {
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return err
	}
	if _, _, err := l.lib.SetItemTag(ctx, it.PID, key, nil, waxbin.TagEditOptions{
		Lock: model.LockOff, Force: true,
	}); err != nil {
		return classify(err)
	}
	return nil
}

// --- locks ------------------------------------------------------------------------

// SetItemLocks locks or unlocks the named fields (scalar names plus the
// namespaced lyrics/chapters/art, credit.ROLE, and tag.KEY artifacts)
// and returns every field locked afterward.
func (l *Library) SetItemLocks(ctx context.Context, uc *UserCtx, apiPID string, fields []string, locked bool) ([]string, error) {
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return nil, err
	}
	if len(fields) == 0 {
		return nil, errInvalid("at least one field is required")
	}
	if len(fields) > 100 {
		return nil, errInvalid("at most 100 fields per request")
	}
	canonical := make([]string, 0, len(fields))
	for _, f := range fields {
		// Tag lock names canonicalize with the tag keys themselves.
		if key, ok := model.CutTagPrefix(f); ok {
			canon, valid := model.CanonicalTagKey(key)
			if !valid {
				return nil, errInvalid("field " + f + " is not lockable")
			}
			f = model.TagLockField(canon)
		}
		if !model.IsCuratableField(f) {
			return nil, errInvalid("field " + f + " is not lockable")
		}
		canonical = append(canonical, f)
	}
	if locked {
		err = l.lib.Lock(ctx, it.PID, canonical...)
	} else {
		err = l.lib.Unlock(ctx, it.PID, canonical...)
	}
	if err != nil {
		return nil, classify(err)
	}
	return l.lockedFieldsFor(ctx, it.PID)
}

// lockedFieldsFor lists every currently locked field, sorted for a
// stable response.
func (l *Library) lockedFieldsFor(ctx context.Context, pid model.PID) ([]string, error) {
	rows, err := l.lib.Provenance(ctx, pid)
	if err != nil {
		return nil, classify(err)
	}
	out := []string{}
	for _, r := range rows {
		if r.Locked {
			out = append(out, r.Field)
		}
	}
	sort.Strings(out)
	return out, nil
}

// --- entity edits -----------------------------------------------------------------

// EditEntity applies curation edits to a shared artist, release group,
// or album; genre entities support artwork only.
func (l *Library) EditEntity(ctx context.Context, entityType, apiEntityPID string, edits map[string]string, p MetadataEditParams) (EditOutcomeDTO, error) {
	et, ok := mergeEntityForType(entityType)
	if !ok {
		return EditOutcomeDTO{}, errInvalid("unknown entity type " + entityType)
	}
	if !model.EntityEditable(et) {
		return EditOutcomeDTO{}, errInvalid("genre entities support artwork only; they carry no editable fields")
	}
	pid, err := editorEntityPID(entityType, apiEntityPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if len(edits) == 0 {
		return EditOutcomeDTO{}, errInvalid("at least one field edit is required")
	}
	for name, value := range edits {
		if !model.IsEntityEditField(et, name) {
			return EditOutcomeDTO{}, errInvalid("field " + name + " is not editable on a " + entityType + " entity")
		}
		if err := validateIdentifierField(name, value); err != nil {
			return EditOutcomeDTO{}, err
		}
		if name == "type" && value != "" && !model.ValidReleaseGroupType(value) {
			return EditOutcomeDTO{}, errInvalid("type is not a recognized release-group type: " + value)
		}
	}
	if p.WriteBack {
		if err := l.CheckWritable(ctx, ""); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	err = l.lib.EditEntity(ctx, et, pid, edits, waxbin.EntityEditOptions{
		WriteBack: p.WriteBack, Lock: model.LockOf(p.Lock), Force: p.Force,
	})
	return editOutcomeFromWriteBack(err)
}

// EntityCurationFor reads an entity's curated fields with provenance.
func (l *Library) EntityCurationFor(ctx context.Context, entityType, apiEntityPID string) ([]EntityCuratedFieldDTO, error) {
	et, ok := mergeEntityForType(entityType)
	if !ok {
		return nil, errInvalid("unknown entity type " + entityType)
	}
	pid, err := editorEntityPID(entityType, apiEntityPID)
	if err != nil {
		return nil, err
	}
	rows, err := l.lib.EntityCuration(ctx, et, pid)
	if err != nil {
		return nil, classify(err)
	}
	out := make([]EntityCuratedFieldDTO, 0, len(rows))
	for _, r := range rows {
		dto := EntityCuratedFieldDTO{
			Field: r.Field, Value: r.Value, Source: string(r.Source), Locked: r.Locked,
		}
		if r.UpdatedAt > 0 {
			dto.UpdatedAt = time.Unix(0, r.UpdatedAt).UTC()
		}
		out = append(out, dto)
	}
	return out, nil
}

// --- release status ---------------------------------------------------------------

// SetReleaseStatus marks or clears the item's unofficial state (a
// locked RELEASESTATUS custom tag of unofficial).
func (l *Library) SetReleaseStatus(ctx context.Context, uc *UserCtx, apiPID string, unofficial bool) error {
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return err
	}
	if unofficial {
		return l.markUnofficial(ctx, it.PID)
	}
	return l.clearUnofficial(ctx, it.PID)
}

// --- full metadata read -----------------------------------------------------------

// writeBackIssueCodes maps the catalog's write-back diagnostics onto the
// contract's codes. The catalog names them in snake_case and the API in
// kebab, so the two vocabularies are joined here once rather than
// stringified at the edge.
var writeBackIssueCodes = map[model.DiagnosticCode]string{
	model.DiagTagWriteUnsynced: "tag-write-unsynced",
	model.DiagTagWriteLost:     "tag-write-lost",
}

// writeBackIssues reads the write-back drift recorded against one item's
// files.
//
// The filter is by code and not by origin: `tag_write_lost` is recorded
// by the edit, organize, and replaygain writers alike, and all three are
// the same fact to an editor asking whether this file's tags match the
// catalog. Everything else the audit records (missing art, corrupt
// audio) belongs to the diagnostics dashboard, not here.
//
// It goes to the facade directly rather than through service
// FileDiagnostics, which is administrators-only because its rows carry
// raw file paths. This read is open to anyone who can see the item, so
// it has to withhold what makes that one administrators-only: the
// catalog stamps Detail with the tag writer's own error, and a failed
// write reads "writing tags to /srv/music/...: permission denied". Code,
// tag key, and file pid say what went wrong without saying where the
// library lives; Detail rides along for administrators, who can already
// read it whole from the diagnostics dashboard.
func (l *Library) writeBackIssues(ctx context.Context, uc *UserCtx, itemPID model.PID) ([]WriteBackIssueDTO, error) {
	rows, err := l.lib.FileDiagnostics(ctx, model.DiagnosticFilter{ItemPID: itemPID})
	if err != nil {
		return nil, classify(err)
	}
	out := make([]WriteBackIssueDTO, 0, len(rows))
	for _, d := range rows {
		code, ok := writeBackIssueCodes[d.Code]
		if !ok {
			continue
		}
		issue := WriteBackIssueDTO{
			FilePID: string(d.FilePID),
			Code:    code,
			TagKey:  d.TagKey,
		}
		if uc.Admin {
			issue.Detail = d.Detail
		}
		out = append(out, issue)
	}
	return out, nil
}

// ItemMetadataFor assembles everything the editor shows for one item.
// Readable by any user who can see the item.
func (l *Library) ItemMetadataFor(ctx context.Context, uc *UserCtx, apiPID string) (ItemMetadataDTO, error) {
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return ItemMetadataDTO{}, err
	}
	prov, err := l.lib.Provenance(ctx, it.PID)
	if err != nil {
		return ItemMetadataDTO{}, classify(err)
	}
	issues, err := l.writeBackIssues(ctx, uc, it.PID)
	if err != nil {
		return ItemMetadataDTO{}, err
	}
	out := ItemMetadataDTO{
		PID:             itemAPIPID(it),
		MediaType:       mediaTypeForKind(it.Kind),
		Fields:          editorScalarFields(it, prov),
		LockedFields:    []string{},
		Provenance:      []FieldProvenanceDTO{},
		Credits:         []CreditDTO{},
		CustomTags:      []CustomTagDTO{},
		VirtualTrack:    it.Virtual,
		ArtistPID:       entityAPIPID(PrefixArtist, it.ArtistPID),
		AlbumPID:        entityAPIPID(PrefixAlbum, it.AlbumPID),
		ReleaseGroupPID: entityAPIPID(PrefixReleaseGroup, it.ReleaseGroupPID),
		WriteBackIssues: issues,
	}
	// The same predicate the twelve item-scoped mutations gate on, so
	// the form the client draws and the answer it gets back cannot
	// drift; a lookup that fails says nothing rather than no.
	if may, err := l.MayCurateItem(ctx, uc, out.PID); err == nil {
		out.MayCurate = &may
	} else {
		l.log.Warn("describing curate permission", "item", out.PID, "err", err)
	}
	for _, r := range prov {
		dto := FieldProvenanceDTO{
			Field: r.Field, Source: string(r.Source), Provider: r.Provider,
			SourceURL: r.SourceURL, Locked: r.Locked,
		}
		if r.UpdatedAt > 0 {
			dto.UpdatedAt = time.Unix(0, r.UpdatedAt).UTC()
		}
		out.Provenance = append(out.Provenance, dto)
		if r.Locked {
			out.LockedFields = append(out.LockedFields, r.Field)
		}
	}
	sort.Strings(out.LockedFields)

	if it.Kind == model.KindBook {
		l.fillBookMetadata(ctx, it, &out)
	}

	credits, err := l.lib.Credits(ctx, it.PID)
	if err != nil {
		return ItemMetadataDTO{}, classify(err)
	}
	out.Credits = groupCredits(credits)

	tags, err := l.lib.ItemTags(ctx, it.PID)
	if err != nil {
		return ItemMetadataDTO{}, classify(err)
	}
	for _, tg := range tags {
		out.CustomTags = append(out.CustomTags, CustomTagDTO{Key: tg.Key, Values: tg.Values})
		if tg.Key == releaseStatusKey {
			for _, v := range tg.Values {
				switch strings.ToLower(v) {
				case releaseStatusUnofficial, "bootleg":
					out.Unofficial = true
				}
			}
		}
	}

	if ly, err := l.lib.Lyrics(ctx, it.PID); err == nil && ly != nil {
		out.Lyrics = lyricsStateDTO(ly)
	} else if err != nil && KindOf(classify(err)) != KindNotFound {
		return ItemMetadataDTO{}, classify(err)
	}

	// The facade resolves art through the entity fallback chain, so an item
	// with only inherited album art reads HasArtwork true. Level names which
	// chain level answered, so HasOwnArtwork isolates the item's own cover
	// from an inherited one for the editor's has-artwork indicator.
	ref := model.EntityRef{Type: model.ArtTrack, PID: it.PID}
	if it.Kind == model.KindEpisode {
		ref.Type = model.ArtEpisode
	}
	if prov, err := l.lib.ArtProvenance(ctx, ref, model.ArtRoleFront); err == nil && prov != nil {
		out.HasArtwork = true
		out.HasOwnArtwork = prov.Level == ref.Type && !prov.Derived
	}
	return out, nil
}

// fillBookMetadata overlays the book-only detail fields and chapters;
// a detail read failure leaves the base view standing rather than
// failing the whole metadata read.
func (l *Library) fillBookMetadata(ctx context.Context, it *model.ItemView, out *ItemMetadataDTO) {
	bd, err := l.lib.Book(ctx, it.PID)
	if err != nil {
		return
	}
	set := func(name, value string) {
		if value != "" {
			out.Fields[name] = value
		}
	}
	set("subtitle", bd.Subtitle)
	set("isbn", bd.ISBN)
	set("publisher", bd.Publisher)
	set("edition", bd.Edition)
	set("description", bd.Description)
	for i, ch := range bd.Chapters {
		out.Chapters = append(out.Chapters, ChapterMark{
			Index: i, Title: ch.Title, StartMS: ch.StartMS, EndMS: ch.EndMS,
		})
	}
}

// editorScalarFields builds the kind's scalar field map from the item
// view, then overlays curated provenance values for the fields the view
// does not carry. Empty values are omitted.
func editorScalarFields(it *model.ItemView, prov []model.FieldProvenance) map[string]string {
	fields := map[string]string{}
	set := func(name, value string) {
		if value != "" {
			fields[name] = value
		}
	}
	setInt := func(name string, v int) {
		if v > 0 {
			fields[name] = strconv.Itoa(v)
		}
	}
	switch it.Kind {
	case model.KindBook:
		set("title", it.Title)
		set("author", it.Artist)
		set("author_sort", it.AuthorSort)
		set("narrator", it.Narrator)
		set("series", it.Series)
		set("subtitle", it.Subtitle)
		set("genre", it.Genre)
		setInt("year", it.Year)
		set("asin", it.ASIN)
	case model.KindEpisode:
		set("title", it.Title)
		setInt("season", it.Season)
	default:
		set("title", it.Title)
		set("artist", it.Artist)
		set("album_artist", it.AlbumArtist)
		set("album", it.Album)
		set("composer", it.Composer)
		set("composer_sort", it.ComposerSort)
		set("genre", it.Genre)
		setInt("year", it.Year)
		setInt("track_no", it.TrackNo)
		setInt("disc_no", it.DiscNo)
		if it.Compilation {
			fields["compilation"] = "true"
		}
	}
	// Curated values cover the vocabulary the view does not surface
	// (comment, identifiers, the episode extras); a tag-sourced value
	// for those fields has no provenance row and stays absent until a
	// fuller item read exists upstream.
	allowed := map[string]bool{}
	for _, f := range editorFieldsForKind(it.Kind) {
		allowed[f.Name] = true
	}
	for _, r := range prov {
		if allowed[r.Field] && r.Value != "" {
			fields[r.Field] = r.Value
		}
	}
	return fields
}

// groupCredits folds contributor rows into per-role name lists,
// preserving stored order.
func groupCredits(rows []model.Contributor) []CreditDTO {
	out := []CreditDTO{}
	index := map[model.ContributorRole]int{}
	for _, c := range rows {
		i, ok := index[c.Role]
		if !ok {
			i = len(out)
			index[c.Role] = i
			out = append(out, CreditDTO{Role: string(c.Role), Names: []string{}})
		}
		out[i].Names = append(out[i].Names, c.Name)
	}
	return out
}

// lyricsStateDTO renders stored lyrics in the editor's working format.
func lyricsStateDTO(ly *model.Lyrics) *LyricsStateDTO {
	out := &LyricsStateDTO{Source: string(ly.Source), Provider: ly.Provider, Synced: len(ly.Synced) > 0}
	if len(ly.Synced) > 0 {
		lines := make([]waxlabel.SyncedLine, 0, len(ly.Synced))
		for _, ln := range ly.Synced {
			lines = append(lines, waxlabel.SyncedLine{
				Time: time.Duration(ln.TimeMS) * time.Millisecond, Text: ln.Text,
			})
		}
		out.LRC = waxlabel.FormatLRC(lines)
	} else {
		out.LRC = ly.Unsynced
	}
	return out
}
