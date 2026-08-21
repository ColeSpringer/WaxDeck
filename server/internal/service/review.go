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
// setting so scans and enrichment respect it.
func waxbinTagOpts(lock bool) waxbin.TagEditOptions {
	return waxbin.TagEditOptions{Lock: model.LockOf(lock), Force: true}
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
	uploader := ""
	if !uc.Admin {
		uploader = uc.ID
	}
	beforeNS, beforeID, err := decodeTimeCursor(cursor)
	if err != nil {
		return nil, "", errInvalid("bad cursor")
	}
	rows, err := l.db.ListReviewEntries(ctx, status, uploader, beforeNS, beforeID, limit)
	if err != nil {
		return nil, "", &Error{Kind: KindInternal, Err: err}
	}
	out := make([]ReviewEntryDTO, 0, len(rows))
	for _, r := range rows {
		out = append(out, reviewDTO(r))
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
	// Staged paths are private server layout; show the base name.
	for i := range detail.Tracks {
		if detail.Tracks[i].PID == "" {
			detail.Tracks[i].Path = filepath.Base(detail.Tracks[i].Path)
		}
		detail.Tracks[i].Tags = nil
		detail.Tracks[i].Fingerprint = ""
	}
	return detail, nil
}

// DecideReviewEntry applies one decision to a pending entry.
func (l *Library) DecideReviewEntry(ctx context.Context, uc *UserCtx, id, action, candidateMBID string) (ReviewEntryDTO, []string, error) {
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
		warnings, err = l.applyEntry(ctx, &e, &payload, candidateMBID, uc.ID, false)
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
			for _, doc := range payload.Tracks {
				if doc.PID == "" {
					continue
				}
				if err := l.markUnofficial(ctx, model.PID(doc.PID)); err != nil {
					warnings = append(warnings, filepath.Base(doc.Path)+": "+err.Error())
				}
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
		// A failed decide may have already moved part of the unit into
		// the library; discarding the rest must not silently orphan
		// those items there. Refuse while any still exists (deleting
		// them, or a decide that finishes the unit, unblocks).
		landed := l.landedTracks(ctx, &payload)
		if landed > 0 {
			return ReviewEntryDTO{}, nil, &Error{Kind: KindConflict,
				Msg: fmt.Sprintf("%d of the files already entered the library; delete the items there first", landed)}
		}
		if err := l.discardEntryFiles(ctx, &e, uc); err != nil {
			return ReviewEntryDTO{}, nil, err
		}
		e.Status = reviewDiscarded
		e.DecidedAtNS = time.Now().UnixNano()
		e.DecidedBy = uc.ID
		if err := l.db.UpdateReviewEntry(ctx, e); err != nil {
			return ReviewEntryDTO{}, nil, &Error{Kind: KindInternal, Err: err}
		}
	default:
		return ReviewEntryDTO{}, nil, errInvalid("unknown decision")
	}
	l.notifyReview(ctx, e.ID, e.UploadedBy)
	return reviewDTO(e), warnings, nil
}

// markUnofficial sets the locked release-status tag.
func (l *Library) markUnofficial(ctx context.Context, pid model.PID) error {
	if _, _, err := l.lib.SetItemTag(ctx, pid, releaseStatusKey,
		[]string{releaseStatusUnofficial}, waxbinTagOpts(true)); err != nil {
		return classify(err)
	}
	return nil
}

// clearUnofficial removes the release-status tag and its lock.
func (l *Library) clearUnofficial(ctx context.Context, pid model.PID) error {
	if _, _, err := l.lib.SetItemTag(ctx, pid, releaseStatusKey, nil, waxbinTagOpts(false)); err != nil {
		return classify(err)
	}
	return nil
}

// discardEntryFiles removes an import entry's staged files and marks
// the backing uploads discarded.
func (l *Library) discardEntryFiles(ctx context.Context, e *wdb.ReviewEntry, uc *UserCtx) error {
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
			l.log.Warn("marking upload discarded", "upload", u.ID, "err", err)
		}
		l.emitUserEvent(ctx, u.UserID, eventUpload, u.ID)
	}
	return nil
}

// RevertReviewEntry restores an applied entry's snapshot.
func (l *Library) RevertReviewEntry(ctx context.Context, uc *UserCtx, id string) (ReviewEntryDTO, error) {
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
	EntryID string
	OK      bool
	Error   string
}

// DecideReviewBulk applies one decision to many entries independently.
func (l *Library) DecideReviewBulk(ctx context.Context, uc *UserCtx, entryIDs []string, action string) []BulkOutcome {
	out := make([]BulkOutcome, 0, len(entryIDs))
	for _, id := range entryIDs {
		_, _, err := l.DecideReviewEntry(ctx, uc, id, action, "")
		o := BulkOutcome{EntryID: id, OK: err == nil}
		if err != nil {
			o.Error = err.Error()
		}
		out = append(out, o)
	}
	return out
}

// ReviewStatsFor computes the calibration statistics.
func (l *Library) ReviewStatsFor(ctx context.Context) (ReviewStatsDTO, error) {
	s, err := l.db.ReviewStatsNow(ctx)
	if err != nil {
		return ReviewStatsDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	return s, nil
}
