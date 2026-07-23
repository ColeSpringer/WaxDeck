package service

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin"
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
type FieldProvenanceDTO struct {
	Field     string
	Source    string
	Provider  string
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
	Synced bool
	Source string
	LRC    string
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
	WriteBackIssues []WriteBackIssueDTO
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
	{"composer", true}, {"comment", true}, {"genre", true}, {"year", true},
	{"track_no", true}, {"disc_no", true}, {"isrc", true}, {"mbid", true},
	{"compilation", true},
}

// editorBookFields is the book scalar vocabulary. Only the fields the
// audiobook scanner reconstructs from tags write back; the enrichment
// fields (subtitle, identifiers, publisher, edition, description, mbid)
// are database-only by upstream design.
var editorBookFields = []EditableFieldDTO{
	{"title", true}, {"author", true}, {"narrator", true}, {"series", true},
	{"subtitle", false}, {"genre", true}, {"year", true}, {"asin", false},
	{"isbn", false}, {"publisher", false}, {"edition", false},
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
		WriteBack: p.WriteBack, Lock: p.Lock, Force: p.Force,
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
		Lock: true,
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
		WriteBack: writeBack, Lock: p.Lock, Force: p.Force,
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
	ly := &model.Lyrics{Source: "user", Synced: synced, Unsynced: plain}
	if !ly.HasContent() {
		return EditOutcomeDTO{}, errInvalid("lyrics must carry timed lines or plain text")
	}
	if p.WriteBack {
		if err := l.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	if err := l.lib.SetLyrics(ctx, it.PID, ly, p.Lock, p.Force); err != nil {
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
	if err := l.lib.SetLyrics(ctx, it.PID, nil, false, true); err != nil {
		return classify(err)
	}
	return nil
}

// --- chapters ---------------------------------------------------------------------

// SetBookChapters replaces a single-file audiobook's chapter list; an
// empty list restores the embedded chapters. Multi-file books keep
// their part boundaries as the navigation grain, an upstream limit.
func (l *Library) SetBookChapters(ctx context.Context, uc *UserCtx, apiPID string, chapters []ChapterMark, lock, force bool) (EditOutcomeDTO, error) {
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if it.Kind != model.KindBook {
		return EditOutcomeDTO{}, errInvalid("chapters are only editable on audiobooks")
	}
	bd, err := l.lib.Book(ctx, it.PID)
	if err != nil {
		return EditOutcomeDTO{}, classify(err)
	}
	if len(bd.Files) > 1 {
		return EditOutcomeDTO{}, errInvalid("user chapters are limited to single-file books upstream; multi-file books navigate by their parts")
	}
	if err := validateChapterList(chapters); err != nil {
		return EditOutcomeDTO{}, err
	}
	// A single-file book's timeline is its file's timeline, so the
	// book-timeline offsets store directly as file offsets.
	stored := make([]model.Chapter, 0, len(chapters))
	for i, ch := range chapters {
		stored = append(stored, model.Chapter{
			Position: i, Title: ch.Title, FileStartMS: ch.StartMS, FileEndMS: ch.EndMS,
		})
	}
	if err := l.lib.SetChapters(ctx, it.PID, stored, lock, force); err != nil {
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

// validateArtworkBytes enforces the size cap and that the body is an
// image the server recognizes.
func validateArtworkBytes(raw []byte) error {
	if len(raw) == 0 {
		return errInvalid("an image body is required")
	}
	if len(raw) > maxArtworkBytes {
		return errInvalid("artwork is limited to 16 MiB")
	}
	if !strings.HasPrefix(http.DetectContentType(raw), "image/") {
		return &Error{Kind: KindFormat, Msg: "the body is not a recognized image"}
	}
	return nil
}

// SetItemArtwork stores raw image bytes as the item's front cover.
// Force is implied on the catalog write: the caller chose the image, so
// an existing lock (set by an earlier artwork edit) never blocks the
// replacement, per the spec's no-silent-downgrade wording.
func (l *Library) SetItemArtwork(ctx context.Context, uc *UserCtx, apiPID string, raw []byte, writeBack, lock bool) (EditOutcomeDTO, error) {
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if err := validateArtworkBytes(raw); err != nil {
		return EditOutcomeDTO{}, err
	}
	if writeBack {
		if err := l.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	err = l.lib.SetItemArt(ctx, it.PID, model.ArtRoleFront, raw, lock, true, writeBack)
	return editOutcomeFromWriteBack(err)
}

// ClearItemArtwork removes the stored item art; resolution falls back
// to the entity chain. Files are untouched.
func (l *Library) ClearItemArtwork(ctx context.Context, uc *UserCtx, apiPID string) error {
	it, err := l.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return err
	}
	if err := l.lib.SetItemArt(ctx, it.PID, model.ArtRoleFront, nil, false, true, false); err != nil {
		return classify(err)
	}
	return nil
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
	default:
		return "", false
	}
}

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
// established prefixes; release groups and genres have no API prefix
// convention yet, so any well-formed prefix is accepted for them and
// the bare PID passes through.
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
// no-op).
func (l *Library) SetEntityArtwork(ctx context.Context, entityType, apiEntityPID string, raw []byte, writeBack bool) (EditOutcomeDTO, error) {
	ent, ok := artEntityForType(entityType)
	if !ok {
		return EditOutcomeDTO{}, errInvalid("unknown entity type " + entityType)
	}
	pid, err := editorEntityPID(entityType, apiEntityPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if err := validateArtworkBytes(raw); err != nil {
		return EditOutcomeDTO{}, err
	}
	// Entity write-back fans into member files across libraries; the
	// server-wide flag gates it (per-library precision would need the
	// member enumeration the facade does internally).
	if writeBack {
		if err := l.CheckWritable(ctx, ""); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	err = l.lib.SetEntityArt(ctx, ent, pid, model.ArtRoleFront, raw, writeBack)
	return editOutcomeFromWriteBack(err)
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
		Lock: lock, Force: force,
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
		Lock: false, Force: true,
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
		WriteBack: p.WriteBack, Lock: p.Lock, Force: p.Force,
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
	out := ItemMetadataDTO{
		PID:          itemAPIPID(it),
		MediaType:    mediaTypeForKind(it.Kind),
		Fields:       editorScalarFields(it, prov),
		LockedFields: []string{},
		Provenance:   []FieldProvenanceDTO{},
		Credits:      []CreditDTO{},
		CustomTags:   []CustomTagDTO{},
		VirtualTrack: it.Virtual,
		// Per-file diagnostics have no per-item query surface on the
		// facade yet (the library-wide Audit sweep is the only reader),
		// so write-back issues stay empty here. The upstream ask is
		// already filed in docs/upstream-requests.md ("A query surface
		// for per-file diagnostics").
		WriteBackIssues: []WriteBackIssueDTO{},
	}
	// The item's album, artist, and release-group entity pids are also
	// omitted: the facade exposes no item-to-entity link read (the
	// filed "Entity facets in the item query grammar" ask is the same
	// gap seen from the query side).
	for _, r := range prov {
		dto := FieldProvenanceDTO{
			Field: r.Field, Source: string(r.Source), Provider: r.Provider, Locked: r.Locked,
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

	// The facade resolves art through the entity fallback chain, so an
	// item with only inherited album art also reads true; a level-scoped
	// art read does not exist upstream.
	ref := model.EntityRef{Type: model.ArtTrack, PID: it.PID}
	if it.Kind == model.KindEpisode {
		ref.Type = model.ArtEpisode
	}
	if blob, err := l.lib.ResolveArt(ctx, ref, model.ArtRoleFront, 64); err == nil && blob != nil {
		out.HasArtwork = true
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
		set("genre", it.Genre)
		setInt("year", it.Year)
		setInt("track_no", it.TrackNo)
		setInt("disc_no", it.DiscNo)
		if it.Compilation {
			fields["compilation"] = "true"
		}
	}
	// Curated values cover the vocabulary the view does not surface
	// (composer, comment, identifiers, the episode extras); a
	// tag-sourced value for those fields has no provenance row and
	// stays absent until a fuller item read exists upstream.
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
	out := &LyricsStateDTO{Source: ly.Source, Synced: len(ly.Synced) > 0}
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
