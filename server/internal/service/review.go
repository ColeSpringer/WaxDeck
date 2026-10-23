package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// waxbinTagOpts builds the tag edit options the unofficial mark uses:
// always forced (the mark must land over an earlier lock), locked when
// setting so scans and enrichment respect it, and written to the files
// when writeBack says so.
func waxbinTagOpts(lock, writeBack bool) waxbin.TagEditOptions {
	return waxbin.TagEditOptions{Lock: model.LockOf(lock), Force: true, WriteBack: writeBack}
}

// ReviewEntryDTO is the API-facing entry summary.
type ReviewEntryDTO struct {
	ID          string
	Kind        string
	Status      string
	MediaType   string
	Origin      string
	Title       string
	Artist      string
	TrackCount  int
	LibraryPID  string
	UploadedBy  string
	Identifying bool
	Best        *CandidateSummaryDTO
	AppliedMBID string
	CreatedAt   time.Time
	DecidedAt   time.Time
	DecidedBy   string
	// DuplicateCount is how many of the unit's files arrived carrying a
	// duplicate warning.
	DuplicateCount int
}

// CandidateSummaryDTO is the ranked best in one line.
type CandidateSummaryDTO struct {
	MBID          string
	Title         string
	Artist        string
	Year          int
	SimilarityPct float64
}

// ReviewDetailDTO adds the stored evidence.
type ReviewDetailDTO struct {
	ReviewEntryDTO
	Tracks     []reviewTrackDoc
	Candidates []reviewCandidateDoc
	// IdentifyDeclined says the submission asked not to be identified,
	// which is what tells an empty candidate list apart from a search
	// that came back empty.
	IdentifyDeclined bool
	// Override is what the last re-identify searched for; nil when
	// nothing was typed.
	Override *ReviewOverrideDTO
	// Suggested is what the matching parse read out of a loose
	// acquisition's source title. A suggestion, never a claim about the
	// files; Override supersedes it.
	Suggested *ReviewOverrideDTO
}

// ReviewStatsDTO mirrors the calibration surface.
type ReviewStatsDTO = wdb.ReviewStats

func reviewDTO(e wdb.ReviewEntry) ReviewEntryDTO {
	dto := ReviewEntryDTO{
		ID:          e.ID,
		Kind:        e.Kind,
		Status:      e.Status,
		MediaType:   e.MediaType,
		Origin:      e.Origin,
		Title:       e.Title,
		Artist:      e.Artist,
		TrackCount:  e.TrackCount,
		LibraryPID:  e.LibraryPID,
		UploadedBy:  e.UploadedBy,
		Identifying: e.Identifying,
		AppliedMBID: e.AppliedMBID,
		CreatedAt:   time.Unix(0, e.CreatedAtNS).UTC(),
		DecidedBy:   e.DecidedBy,
	}
	if e.DecidedAtNS > 0 {
		dto.DecidedAt = time.Unix(0, e.DecidedAtNS).UTC()
	}
	if e.BestMBID != "" {
		dto.Best = &CandidateSummaryDTO{
			MBID: e.BestMBID, Title: e.BestTitle, Artist: e.BestArtist,
			Year: e.BestYear, SimilarityPct: e.BestSimilarity,
		}
	}
	return dto
}

// ListReviewQueue pages entries: administrators see everything, other
// callers their own uploads' entries.
func (l *Library) ListReviewQueue(ctx context.Context, uc *UserCtx, status, cursor string, limit int) ([]ReviewEntryDTO, string, error) {
	uploader := reviewScope(uc)
	beforeNS, beforeID, err := decodeTimeCursor(cursor)
	if err != nil {
		return nil, "", errInvalid("bad cursor")
	}
	rows, err := l.db.ListReviewEntries(ctx, status, uploader, beforeNS, beforeID, limit)
	if err != nil {
		return nil, "", &Error{Kind: KindInternal, Err: err}
	}
	ids := make([]string, len(rows))
	for i, r := range rows {
		ids[i] = r.ID
	}
	dups, err := l.db.DuplicateCountsByEntry(ctx, ids)
	if err != nil {
		return nil, "", &Error{Kind: KindInternal, Err: err}
	}
	out := make([]ReviewEntryDTO, 0, len(rows))
	for _, r := range rows {
		dto := reviewDTO(r)
		dto.DuplicateCount = dups[r.ID]
		out = append(out, dto)
	}
	next := ""
	if len(rows) == limit {
		last := rows[len(rows)-1]
		next = encodeTimeCursor(last.CreatedAtNS, last.ID)
	}
	return out, next, nil
}

// reviewEntryForCaller loads an entry the caller may see.
func (l *Library) reviewEntryForCaller(ctx context.Context, uc *UserCtx, id string) (wdb.ReviewEntry, error) {
	e, err := l.db.ReviewEntryByID(ctx, id)
	if errors.Is(err, wdb.ErrNotFound) {
		return wdb.ReviewEntry{}, errNotFound("no such review entry")
	}
	if err != nil {
		return wdb.ReviewEntry{}, &Error{Kind: KindInternal, Err: err}
	}
	if !uc.Admin && e.UploadedBy != uc.ID {
		return wdb.ReviewEntry{}, errNotFound("no such review entry")
	}
	return e, nil
}

// GetReviewEntry reads one entry with its evidence.
func (l *Library) GetReviewEntry(ctx context.Context, uc *UserCtx, id string) (ReviewDetailDTO, error) {
	e, err := l.reviewEntryForCaller(ctx, uc, id)
	if err != nil {
		return ReviewDetailDTO{}, err
	}
	var payload reviewPayload
	if err := json.Unmarshal([]byte(e.Payload), &payload); err != nil {
		return ReviewDetailDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	detail := ReviewDetailDTO{
		ReviewEntryDTO:   reviewDTO(e),
		Tracks:           payload.Tracks,
		Candidates:       payload.Candidates,
		IdentifyDeclined: payload.IdentifyDeclined,
	}
	if o := payload.Override; o != nil {
		detail.Override = &ReviewOverrideDTO{
			Artist: o.Artist, Album: o.Album, Title: o.Title,
		}
	}
	if s := payload.Suggested; s != nil {
		detail.Suggested = &ReviewOverrideDTO{
			Artist: s.Artist, Album: s.Album, Title: s.Title,
		}
	}
	// Each file's upload says whether it arrived duplicating the
	// library, matched on the staged path before the paths are cut to
	// base names.
	if e.Origin == reviewOriginUpload || e.Origin == reviewOriginAcquire {
		rows, err := l.db.ListUploadsByReviewEntry(ctx, e.ID)
		if err != nil {
			return ReviewDetailDTO{}, &Error{Kind: KindInternal, Err: err}
		}
		for _, r := range rows {
			if r.DuplicatePID == "" {
				continue
			}
			detail.DuplicateCount++
			for i := range detail.Tracks {
				if detail.Tracks[i].Path == r.StagingPath {
					detail.Tracks[i].Duplicate = l.duplicateFor(ctx, uc, r.DuplicatePID, r.DuplicateKind)
				}
			}
		}
	}
	// Staged paths are private server layout, and where the library
	// keeps its files is the administrators' to read: everyone else
	// gets the base name. An uploaded or downloaded file is named alone
	// for administrators too: its staging path is gone once it lands,
	// and where it landed is the item's to say. A copy that joined an
	// item the reader cannot see does not name it, as its duplicate
	// warning does not. The payload stores bare catalog pids - its
	// internal consumers cast them straight to model.PID - while the
	// wire carries type-prefixed pids everywhere, so a cataloged track's
	// pid is prefixed on the way out; served bare, the review screen's
	// own edit door pushed a location nothing could resolve. An entry
	// whose media type maps to no kind keeps its pid bare rather than
	// guessing a prefix: the kind fallback is tr-, and tr-<book pid> is
	// the same broken door.
	kind, kindKnown := kindForMediaType(e.MediaType)
	prefix := prefixForKind(kind)
	staged := e.Origin == reviewOriginUpload || e.Origin == reviewOriginAcquire
	for i := range detail.Tracks {
		tr := &detail.Tracks[i]
		if tr.PID == "" || !uc.Admin || staged {
			tr.Path = filepath.Base(tr.Path)
		}
		if tr.PID != "" && tr.Joined && !uc.Admin {
			if _, ok := l.itemInReach(ctx, uc, model.PID(tr.PID)); !ok {
				tr.PID = ""
			}
		}
		if _, _, ok := parseAPIPID(tr.PID); tr.PID != "" && !ok && kindKnown {
			tr.PID = apiPID(prefix, model.PID(tr.PID))
		}
		tr.Tags = nil
		tr.Fingerprint = ""
	}
	return detail, nil
}

// claimEntry holds an entry for one change at a time - a decision, a
// revert, a new search, a discard - so a second does not read the
// first's half-done state as its own; ok is false while another holds it.
// A declined import the claim held off goes once it is released.
func (l *Library) claimEntry(id string) (release func(), ok bool) {
	if _, busy := l.deciding.LoadOrStore(id, struct{}{}); busy {
		return nil, false
	}
	return func() {
		l.deciding.Delete(id)
		if _, owed := l.heldOff.LoadAndDelete(id); owed {
			l.importLater([]string{id})
		}
	}, true
}

// errEntryBusy answers a change to an entry another is still making.
func errEntryBusy() error {
	return &Error{Kind: KindConflict, Msg: "the entry is being decided; ask again shortly"}
}

// DecideReviewEntry applies one decision to a pending entry. Once it
// starts it finishes, whether or not the client is still there for the
// answer: stopping between moving the files and recording them would
// leave them landed under an entry that says they never did.
func (l *Library) DecideReviewEntry(ctx context.Context, uc *UserCtx, id, action, candidateMBID string) (ReviewEntryDTO, []string, error) {
	release, ok := l.claimEntry(id)
	if !ok {
		return ReviewEntryDTO{}, nil, errEntryBusy()
	}
	defer release()
	ctx, cancel := l.untilShutdown(ctx)
	defer cancel()
	e, err := l.reviewEntryForCaller(ctx, uc, id)
	if err != nil {
		return ReviewEntryDTO{}, nil, err
	}
	if e.Status != reviewPending {
		return ReviewEntryDTO{}, nil, &Error{Kind: KindConflict, Msg: "the entry is already decided"}
	}
	var payload reviewPayload
	if err := json.Unmarshal([]byte(e.Payload), &payload); err != nil {
		return ReviewEntryDTO{}, nil, &Error{Kind: KindInternal, Err: err}
	}

	// Skips and discards touch no files; every other decision can write
	// into the entry's target library.
	if action != "skip" && action != "discard" {
		bareLib := ""
		if prefix, pid, ok := parseAPIPID(e.LibraryPID); ok && prefix == PrefixLibrary {
			bareLib = string(pid)
		}
		if err := l.CheckWritable(ctx, bareLib); err != nil {
			return ReviewEntryDTO{}, nil, err
		}
	}

	var warnings []string
	switch action {
	case "approve":
		if candidateMBID == "" {
			candidateMBID = e.BestMBID
		}
		if candidateMBID == "" {
			return ReviewEntryDTO{}, nil, errInvalid("the entry has no candidates to approve")
		}
		warnings, err = l.applyEntry(ctx, &e, &payload, candidateMBID, uc, false)
		if err != nil {
			return ReviewEntryDTO{}, warnings, err
		}
	case "as-is", "unofficial":
		if e.Kind == reviewKindImport {
			w, ierr := l.importEntryFiles(ctx, &e, &payload)
			warnings = append(warnings, w...)
			if ierr != nil {
				return ReviewEntryDTO{}, warnings, ierr
			}
			e.Payload = marshalJSON(payload)
		}
		if action == "unofficial" {
			// The mark reaches the files as an approval's values do.
			var marked []model.PID
			for _, doc := range payload.Tracks {
				if doc.PID != "" && !doc.heldBefore() {
					marked = append(marked, model.PID(doc.PID))
				}
			}
			writeBack := l.unitWritable(ctx, marked)
			for _, doc := range payload.Tracks {
				// A joined file's item was the library's before this
				// entry, and is not this decision's to mark; it says so,
				// as an approval says what it left alone.
				if doc.heldBefore() {
					warnings = append(warnings, filepath.Base(doc.Path)+": already in the library; it was not marked unofficial")
					continue
				}
				if doc.PID == "" {
					continue
				}
				w, err := l.markUnofficial(ctx, uc, model.PID(doc.PID), writeBack)
				if err != nil {
					warnings = append(warnings, filepath.Base(doc.Path)+": "+err.Error())
				}
				warnings = append(warnings, w...)
			}
			e.Status = reviewUnofficial
		} else {
			e.Status = reviewAsIs
		}
		e.DecidedAtNS = time.Now().UnixNano()
		e.DecidedBy = uc.ID
		if err := l.db.UpdateReviewEntry(ctx, e); err != nil {
			return ReviewEntryDTO{}, warnings, &Error{Kind: KindInternal, Err: err}
		}
	case "skip":
		e.Status = reviewSkipped
		e.DecidedAtNS = time.Now().UnixNano()
		e.DecidedBy = uc.ID
		if err := l.db.UpdateReviewEntry(ctx, e); err != nil {
			return ReviewEntryDTO{}, nil, &Error{Kind: KindInternal, Err: err}
		}
	case "discard":
		if e.Kind != reviewKindImport {
			return ReviewEntryDTO{}, nil, errInvalid("only entries staging new files can discard them")
		}
		// A failed decide may have moved part of the unit into the
		// library already. Those files stay where they landed, as their
		// own items or copies; the discard drops what is still staged,
		// and says what stayed.
		if landed := l.landedTracks(ctx, &payload); landed > 0 {
			warnings = append(warnings, fmt.Sprintf(
				"%d of the files already entered the library and stay there", landed))
		}
		if err := l.discardEntryFiles(ctx, &e); err != nil {
			return ReviewEntryDTO{}, warnings, err
		}
		e.Status = reviewDiscarded
		e.DecidedAtNS = time.Now().UnixNano()
		e.DecidedBy = uc.ID
		if err := l.db.UpdateReviewEntry(ctx, e); err != nil {
			return ReviewEntryDTO{}, warnings, &Error{Kind: KindInternal, Err: err}
		}
	default:
		return ReviewEntryDTO{}, nil, errInvalid("unknown decision")
	}
	l.notifyReview(ctx, e.ID, e.UploadedBy)
	return reviewDTO(e), warnings, nil
}

// markUnofficial sets the locked release-status tag, in the files too
// with writeBack, answering reader the files that could not take it.
func (l *Library) markUnofficial(ctx context.Context, reader *UserCtx, pid model.PID, writeBack bool) ([]string, error) {
	return l.tagWriteBackWarnings(ctx, reader, l.setReleaseStatus(ctx, pid, true, writeBack))
}

// setReleaseStatus marks an item unofficial, the release-status tag
// locked, or clears the mark, in the files too with writeBack.
func (l *Library) setReleaseStatus(ctx context.Context, pid model.PID, unofficial, writeBack bool) error {
	var values []string
	if unofficial {
		values = []string{releaseStatusUnofficial}
	}
	_, _, err := l.lib.SetItemTag(ctx, pid, releaseStatusKey, values, waxbinTagOpts(unofficial, writeBack))
	return err
}

// tagWriteBackWarnings splits a tag edit's error: files the write could
// not reach are warnings beside a standing edit, those reader may see,
// and anything else fails it.
func (l *Library) tagWriteBackWarnings(ctx context.Context, reader *UserCtx, err error) ([]string, error) {
	if err == nil {
		return nil, nil
	}
	var wbe *waxbin.WriteBackError
	if !errors.As(err, &wbe) {
		return nil, classify(err)
	}
	out := make([]string, 0, len(wbe.Failures))
	for _, f := range wbe.Failures {
		if l.mayReadFailure(ctx, reader, f) {
			out = append(out, l.writeBackWarning(f))
		}
	}
	return out, nil
}

// mayReadFailure reports whether reader may read of a file a write could
// not reach: an administrator, or no reader at all, any; anyone else one
// in a library they are granted.
func (l *Library) mayReadFailure(ctx context.Context, reader *UserCtx, f waxbin.WriteBackFailure) bool {
	return reader == nil || reader.Admin || f.FilePID == "" || l.fileGranted(ctx, reader, f.FilePID)
}

// writeBackWarning words one file a write could not reach, by name
// rather than by path: the reader may not be an administrator. A failure
// that names no file says so without a name.
func (l *Library) writeBackWarning(f waxbin.WriteBackFailure) string {
	msg := "tags not written: " + l.failureWords(f.Reason)
	if f.Path == "" {
		return msg
	}
	return filepath.Base(f.Path) + ": " + msg
}

// discardEntryFiles removes an import entry's staged files and marks
// the backing uploads discarded. An upload it cannot mark fails the
// discard, which leaves the entry undecided: a retry finds the row still
// staged, its files already gone, and marks it.
func (l *Library) discardEntryFiles(ctx context.Context, e *wdb.ReviewEntry) error {
	if e.Origin != reviewOriginUpload && e.Origin != reviewOriginAcquire {
		return errInvalid("only upload and acquisition entries hold discardable files")
	}
	rows, err := l.db.ListUploadsByReviewEntry(ctx, e.ID)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	for _, u := range rows {
		if u.State != uploadStaged {
			continue
		}
		if err := os.RemoveAll(filepath.Join(l.stagingDir, u.ID)); err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
		u.State = uploadDiscarded
		if err := l.db.UpdateUpload(ctx, u); err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
		l.emitUserEvent(ctx, u.UserID, eventUpload, u.ID)
	}
	return nil
}

// RevertReviewEntry restores an applied entry's snapshot, finishing as
// a decision does once it starts.
func (l *Library) RevertReviewEntry(ctx context.Context, uc *UserCtx, id string) (ReviewEntryDTO, error) {
	release, ok := l.claimEntry(id)
	if !ok {
		return ReviewEntryDTO{}, errEntryBusy()
	}
	defer release()
	ctx, cancel := l.untilShutdown(ctx)
	defer cancel()
	e, err := l.reviewEntryForCaller(ctx, uc, id)
	if err != nil {
		return ReviewEntryDTO{}, err
	}
	if !uc.Admin && e.DecidedBy != uc.ID {
		return ReviewEntryDTO{}, &Error{Kind: KindForbidden, Msg: "only administrators and the deciding user revert"}
	}
	if err := l.revertEntry(ctx, &e, uc.ID); err != nil {
		return ReviewEntryDTO{}, err
	}
	return reviewDTO(e), nil
}

// ReviewOverrideDTO is what a re-identify searches for in place of the
// files' own tags. Empty fields mean "use what the files claim".
type ReviewOverrideDTO struct {
	Artist string
	Album  string
	Title  string
}

// maxOverrideField bounds one typed search value, matching the
// contract's own maxLength.
const maxOverrideField = 300

// ReidentifyEntry stores a search override on a pending entry and
// requeues it for the identify worker.
//
// The sibling of openReviewEntry's update path: the same fields move,
// minus the insert. The override replaces whatever was there, so an
// empty request is how a reviewer goes back to the plain derivation.
func (l *Library) ReidentifyEntry(ctx context.Context, uc *UserCtx, id string, o ReviewOverrideDTO) (ReviewEntryDTO, error) {
	release, ok := l.claimEntry(id)
	if !ok {
		return ReviewEntryDTO{}, errEntryBusy()
	}
	defer release()
	e, err := l.reviewEntryForCaller(ctx, uc, id)
	if err != nil {
		return ReviewEntryDTO{}, err
	}
	if e.Status != reviewPending {
		return ReviewEntryDTO{}, &Error{Kind: KindConflict, Msg: "the entry is already decided"}
	}
	override := reviewOverride{
		Artist: strings.TrimSpace(o.Artist),
		Album:  strings.TrimSpace(o.Album),
		Title:  strings.TrimSpace(o.Title),
	}
	for _, v := range []string{override.Artist, override.Album, override.Title} {
		// Runes, because the contract's maxLength counts characters:
		// a byte check would refuse a 300-character CJK query at 100.
		if utf8.RuneCountInString(v) > maxOverrideField {
			return ReviewEntryDTO{}, errInvalid(fmt.Sprintf("a search value may be at most %d characters", maxOverrideField))
		}
	}
	var payload reviewPayload
	if err := json.Unmarshal([]byte(e.Payload), &payload); err != nil {
		return ReviewEntryDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	if override.empty() {
		payload.Override = nil
	} else {
		payload.Override = &override
	}
	// Searching again is asking to be identified, whatever the
	// submission originally said - so the declined mark goes with it,
	// and the empty state stops claiming nothing was searched.
	payload.IdentifyDeclined = false
	raw, err := json.Marshal(payload)
	if err != nil {
		return ReviewEntryDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	// Queued before the flag is raised: every path that clears
	// `identifying` needs a queue row, so the other order strands a
	// spinner for good if the enqueue never lands.
	if err := l.db.EnqueueMatch(ctx, e.ID); err != nil {
		return ReviewEntryDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	e.Payload = string(raw)
	e.Identifying = true
	if err := l.db.UpdateReviewEntry(ctx, e); err != nil {
		return ReviewEntryDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	l.matchWakeup()
	return reviewDTO(e), nil
}

// BulkOutcome is one entry's outcome in a bulk decision.
type BulkOutcome struct {
	EntryID  string
	OK       bool
	Code     string
	Error    string
	Warnings []string
}

// DecideReviewBulk applies one decision to many entries independently,
// reporting each as the single decide would: a refusal by its code, a
// decision that stood with its warnings, and a refusal with none, since
// what landed before it is no part of a decision.
func (l *Library) DecideReviewBulk(ctx context.Context, uc *UserCtx, entryIDs []string, action string) []BulkOutcome {
	out := make([]BulkOutcome, 0, len(entryIDs))
	for _, id := range entryIDs {
		_, warnings, err := l.DecideReviewEntry(ctx, uc, id, action, "")
		o := BulkOutcome{EntryID: id, OK: err == nil}
		if err == nil {
			o.Warnings = warnings
		} else {
			o.Code, o.Error = string(KindOf(err)), err.Error()
			if KindOf(err) == KindInternal {
				// The cause is for the log, as a single decide's is.
				l.log.Error("bulk review decision", "entry", id, "err", err)
				o.Error = "an internal error stopped this decision"
			}
		}
		out = append(out, o)
	}
	return out
}

// reviewScope is the uploader a caller's review reads are limited to:
// none for an administrator, else the caller, who sees what their own
// uploads, acquisitions and rematches produced. Scan entries, and an
// administrator's rematches, carry no uploader, so they stay the
// administrators'.
func reviewScope(uc *UserCtx) string {
	if uc.Admin {
		return ""
	}
	return uc.ID
}

// ReviewStatsFor computes the calibration statistics over the entries
// the caller's queue lists.
func (l *Library) ReviewStatsFor(ctx context.Context, uc *UserCtx) (ReviewStatsDTO, error) {
	s, err := l.db.ReviewStatsNow(ctx, reviewScope(uc))
	if err != nil {
		return ReviewStatsDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	return s, nil
}
