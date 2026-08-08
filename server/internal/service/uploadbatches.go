package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"path"
	"sort"
	"strings"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxdeck/server/internal/match"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Upload batch states.
const (
	batchOpen      = "open"
	batchFinalized = "finalized"
	batchExpired   = "expired"
)

// Upload batch grouping intents.
const (
	groupingAuto   = "auto"
	groupingAlbum  = "album"
	groupingTracks = "tracks"
)

// uploadBatchTTL is how long a batch accepts members before the
// janitor finalizes it with whatever arrived. Members keep the normal
// upload retention; only the grouping window is this short.
const uploadBatchTTL = 24 * time.Hour

// UploadBatchDTO is the API-facing batch shape.
type UploadBatchDTO struct {
	ID             string
	Grouping       string
	MediaType      string
	LibraryPID     string
	State          string
	ReviewEntryIDs []string
	CreatedAt      time.Time
	ExpiresAt      time.Time
}

// UploadBatchCreateParams are the batch parameters.
type UploadBatchCreateParams struct {
	Grouping   string
	MediaType  string
	LibraryPID string
	// Identify is the batch's identification choice for every entry it
	// opens; nil means the account default.
	Identify *bool
}

func uploadBatchDTO(b wdb.UploadBatch) UploadBatchDTO {
	dto := UploadBatchDTO{
		ID:         b.ID,
		Grouping:   b.Grouping,
		MediaType:  b.MediaType,
		LibraryPID: b.LibraryPID,
		State:      b.State,
		CreatedAt:  time.Unix(0, b.CreatedAtNS).UTC(),
		ExpiresAt:  time.Unix(0, b.ExpiresAtNS).UTC(),
	}
	// A malformed document (impossible through this code) reads as no
	// entries rather than failing the whole view.
	var ids []string
	if err := json.Unmarshal([]byte(b.ReviewEntryIDs), &ids); err == nil {
		dto.ReviewEntryIDs = ids
	}
	return dto
}

// CreateUploadBatch opens a batch for grouped sessions, mirroring
// CreateUpload's target validation; members join by session-side
// batchId and must match the batch's media type and library.
func (l *Library) CreateUploadBatch(ctx context.Context, uc *UserCtx, p UploadBatchCreateParams) (UploadBatchDTO, error) {
	if err := l.requireUploader(uc); err != nil {
		return UploadBatchDTO{}, err
	}
	if err := l.CheckWritable(ctx, ""); err != nil {
		return UploadBatchDTO{}, err
	}
	switch p.Grouping {
	case groupingAuto, groupingAlbum, groupingTracks:
	default:
		return UploadBatchDTO{}, errInvalid("unknown grouping")
	}
	if _, ok := kindForMediaType(p.MediaType); !ok {
		return UploadBatchDTO{}, errInvalid("unknown media type")
	}
	if err := l.validateUploadTargetLibrary(ctx, uc, p.LibraryPID); err != nil {
		return UploadBatchDTO{}, err
	}
	b := wdb.UploadBatch{
		ID:             "ub-" + ulid.Make().String(),
		UserID:         uc.ID,
		Grouping:       p.Grouping,
		MediaType:      p.MediaType,
		LibraryPID:     p.LibraryPID,
		State:          batchOpen,
		ReviewEntryIDs: "[]",
		Identify:       l.resolveIdentify(ctx, uc.ID, p.Identify),
		CreatedAtNS:    time.Now().UnixNano(),
		ExpiresAtNS:    time.Now().Add(uploadBatchTTL).UnixNano(),
	}
	if err := l.db.InsertUploadBatch(ctx, b); err != nil {
		return UploadBatchDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	return uploadBatchDTO(b), nil
}

// cleanBatchPath validates a member's batch-relative directory hint:
// forward slashes, relative, no parent traversal, no control bytes
// (cluster keys separate on NUL), bounded length. The hint is only
// ever a clustering key, never a filesystem path on the server.
func cleanBatchPath(p string) (string, error) {
	if p == "" {
		return "", nil
	}
	if len(p) > 512 {
		return "", errInvalid("batchPath must be at most 512 characters")
	}
	for _, r := range p {
		if r < 0x20 {
			return "", errInvalid("batchPath must not contain control characters")
		}
	}
	if strings.Contains(p, `\`) {
		return "", errInvalid("batchPath must use forward slashes")
	}
	if strings.HasPrefix(p, "/") {
		return "", errInvalid("batchPath must be relative")
	}
	cleaned := path.Clean(p)
	if cleaned == "." {
		return "", nil
	}
	if cleaned == ".." || strings.HasPrefix(cleaned, "../") {
		return "", errInvalid("batchPath must not traverse upward")
	}
	return cleaned, nil
}

// batchForMember validates a session's batch join at creation time.
func (l *Library) batchForMember(ctx context.Context, uc *UserCtx, p *UploadCreateParams) error {
	if p.BatchPath != "" && p.BatchID == "" {
		return errInvalid("batchPath is only meaningful with batchId")
	}
	if p.BatchID == "" {
		return nil
	}
	b, err := l.db.UploadBatchByID(ctx, p.BatchID)
	if errors.Is(err, wdb.ErrNotFound) {
		return errNotFound("no such upload batch")
	}
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	// Not the caller's batch reads as absent, like foreign uploads do.
	if b.UserID != uc.ID {
		return errNotFound("no such upload batch")
	}
	if b.State != batchOpen {
		return errInvalid("the batch is no longer open")
	}
	if p.MediaType != b.MediaType {
		return errInvalid("the session's media type must match the batch's")
	}
	if p.LibraryPID != b.LibraryPID {
		return errInvalid("the session's library must match the batch's")
	}
	// The batch decided identification for everything in it, so a
	// member's own value is replaced rather than validated against it.
	// This also covers the fall-through below, where a batch that closed
	// mid-transfer leaves the member to open its own entry.
	p.Identify = &b.Identify
	cleaned, err := cleanBatchPath(p.BatchPath)
	if err != nil {
		return err
	}
	p.BatchPath = cleaned
	return nil
}

// CompleteUploadBatch finalizes a batch: members staged by now are
// grouped per the batch's intent and their review entries open.
// Idempotent on a finalized batch (also finishing the entry-opening
// work an interrupted finalize left behind); a batch the janitor
// already expired answers conflict.
func (l *Library) CompleteUploadBatch(ctx context.Context, uc *UserCtx, id string) (UploadBatchDTO, error) {
	pre, err := l.db.UploadBatchByID(ctx, id)
	if errors.Is(err, wdb.ErrNotFound) {
		return UploadBatchDTO{}, errNotFound("no such upload batch")
	}
	if err != nil {
		return UploadBatchDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	if pre.UserID != uc.ID && !uc.Admin {
		return UploadBatchDTO{}, errNotFound("no such upload batch")
	}
	// One finalize at a time per process: a concurrent retry (double
	// click, a timed-out client trying again) must see the first
	// call's links, not gather the same unlinked members and open
	// duplicate entries.
	b, declined, err := func() (wdb.UploadBatch, []string, error) {
		l.batchFinalizeMu.Lock()
		defer l.batchFinalizeMu.Unlock()
		b, members, flipped, err := l.db.FinalizeUploadBatch(ctx, id, batchFinalized)
		if errors.Is(err, wdb.ErrNotFound) {
			return b, nil, errNotFound("no such upload batch")
		}
		if err != nil {
			return b, nil, &Error{Kind: KindInternal, Err: err}
		}
		if !flipped && b.State == batchExpired {
			return b, nil, &Error{Kind: KindConflict,
				Msg: "the batch expired; the files that arrived were already sent to review"}
		}
		return l.openBatchEntries(ctx, b, members)
	}()
	if err != nil {
		return UploadBatchDTO{}, err
	}
	l.importDeclinedEntries(declined)
	return uploadBatchDTO(b), nil
}

// importDeclinedEntries lands what a finalize opened for a submission
// that declined identification. Outside the finalize lock: importing
// needs none of it, and two hundred files would otherwise hold every
// other account's finalize. On procCtx, as the entry opening is.
func (l *Library) importDeclinedEntries(entryIDs []string) {
	for _, id := range entryIDs {
		l.importDeclinedEntry(l.procCtx, id)
	}
}

// DrainExpiredUploadBatches processes one round of batches the
// janitor owes work: overdue open ones auto-finalize with whatever
// arrived (completed members are never silently discarded; the
// grouping degrades to what staged), and expired ones an interrupted
// entry opening left half-done get their entries repaired. true means
// a batch was fully processed - a round where every batch failed
// reports false so the caller's drain loop waits for the next tick
// instead of hot-looping over the same failures.
func (l *Library) DrainExpiredUploadBatches(ctx context.Context) bool {
	rows, err := l.db.ExpiredUploadBatches(ctx, time.Now().UnixNano(), 20)
	if err != nil {
		l.log.Warn("listing expired upload batches", "err", err)
		return false
	}
	if len(rows) == 0 {
		return false
	}
	progress := false
	for _, b := range rows {
		if l.expireBatch(ctx, b.ID) {
			progress = true
		}
	}
	return progress
}

// expireBatch finalizes one overdue or half-repaired batch. Only the
// entry opening takes the finalize lock.
func (l *Library) expireBatch(ctx context.Context, id string) bool {
	declined, ok := func() ([]string, bool) {
		l.batchFinalizeMu.Lock()
		defer l.batchFinalizeMu.Unlock()
		fb, members, _, err := l.db.FinalizeUploadBatch(ctx, id, batchExpired)
		if err != nil {
			l.log.Warn("expiring upload batch", "batch", id, "err", err)
			return nil, false
		}
		_, declined, err := l.openBatchEntries(ctx, fb, members)
		if err != nil {
			l.log.Warn("opening entries for expired batch", "batch", id, "err", err)
			return nil, false
		}
		return declined, true
	}()
	if !ok {
		return false
	}
	l.importDeclinedEntries(declined)
	return true
}

// openBatchEntries groups a closed batch's gathered members per its
// grouping intent, opens their review entries, and links each member.
// The updated batch row (with the recorded entry ids) is returned;
// entry ids opened before an error are persisted so an interrupted
// call resumes instead of double-opening. Link and record failures
// are attempted to completion but reported, never swallowed: a
// success answer with an unlinked member would let retention reap
// its staged file while the entry still references it.
func (l *Library) openBatchEntries(ctx context.Context, b wdb.UploadBatch, members []wdb.Upload) (wdb.UploadBatch, []string, error) {
	if len(members) == 0 {
		return b, nil, nil
	}
	// The batch flip is already committed; what remains is server-side
	// completion of that decision, so it rides the process context -
	// a client disconnect mid-finalize must not cancel entry opening
	// or member linking halfway (the idempotent retry could then only
	// cover the unlinked members with fresh entries).
	ctx = l.procCtx
	type memberDoc struct {
		row wdb.Upload
		doc reviewTrackDoc
	}
	docs := make([]memberDoc, 0, len(members))
	for _, m := range members {
		var doc reviewTrackDoc
		if err := json.Unmarshal([]byte(m.TrackDoc), &doc); err != nil || doc.Path == "" {
			// A member with no usable document (impossible through the
			// normal flow) cannot enter review; leave it to retention.
			l.log.Warn("batch member without track document", "upload", m.ID)
			continue
		}
		docs = append(docs, memberDoc{row: m, doc: doc})
	}
	if len(docs) == 0 {
		return b, nil, nil
	}

	var ids []string
	if err := json.Unmarshal([]byte(b.ReviewEntryIDs), &ids); err != nil {
		ids = nil
	}
	// Entries this call opened for a submission that declined
	// identification, for the caller to import off the lock.
	var declined []string
	persist := func() error {
		b.ReviewEntryIDs = marshalJSON(ids)
		if err := l.db.SetUploadBatchEntries(ctx, b.ID, b.ReviewEntryIDs); err != nil {
			return fmt.Errorf("recording batch %s entries: %w", b.ID, err)
		}
		return nil
	}
	// The first failure is remembered but the remaining members still
	// process: every link that lands is durable progress a retry never
	// has to redo.
	var firstErr error
	fail := func(what, id string, err error) {
		l.log.Warn(what, "id", id, "err", err)
		if firstErr == nil {
			firstErr = fmt.Errorf("%s %s: %w", what, id, err)
		}
	}

	// Repair pass: a member whose document already sits inside one of
	// the batch's recorded entries was gathered only because its link
	// never landed (an interrupted earlier finalize); complete the
	// link instead of opening a duplicate entry over the same file.
	if len(ids) > 0 {
		covered := map[string]string{}
		for _, entryID := range ids {
			entry, err := l.db.ReviewEntryByID(ctx, entryID)
			if err != nil {
				continue
			}
			var payload reviewPayload
			if err := json.Unmarshal([]byte(entry.Payload), &payload); err != nil {
				continue
			}
			for _, t := range payload.Tracks {
				covered[t.Path] = entryID
			}
		}
		remaining := make([]memberDoc, 0, len(docs))
		for _, d := range docs {
			entryID, ok := covered[d.doc.Path]
			if !ok {
				remaining = append(remaining, d)
				continue
			}
			linked, err := l.db.LinkUploadReviewEntry(ctx, d.row.ID, entryID)
			if err != nil {
				fail("linking batch member", d.row.ID, err)
				continue
			}
			if linked {
				l.emitUserEvent(ctx, d.row.UserID, eventUpload, d.row.ID)
			}
		}
		docs = remaining
	}
	if len(docs) == 0 {
		if firstErr != nil {
			return b, nil, &Error{Kind: KindInternal, Err: firstErr}
		}
		return b, nil, nil
	}

	// Units per the grouping intent, each a deterministic doc order.
	var units [][]memberDoc
	switch b.Grouping {
	case groupingAlbum:
		sort.SliceStable(docs, func(i, j int) bool {
			a, z := docs[i].doc, docs[j].doc
			if a.DiscNo != z.DiscNo {
				return a.DiscNo < z.DiscNo
			}
			if a.TrackNo != z.TrackNo {
				return a.TrackNo < z.TrackNo
			}
			return a.Path < z.Path
		})
		units = [][]memberDoc{docs}
	case groupingTracks:
		for _, d := range docs {
			units = append(units, []memberDoc{d})
		}
	default: // auto
		byID := make(map[string]memberDoc, len(docs))
		tracks := make([]match.Track, 0, len(docs))
		for _, d := range docs {
			byID[d.row.ID] = d
			tags := d.doc.Tags
			if tags == nil {
				tags = map[string]string{}
			}
			// The cluster path is the client-declared batch-relative
			// location, not the staging path: staged files each live in
			// their own session directory, which would defeat the
			// directory fallback and the disc-folder fold.
			tracks = append(tracks, match.Track{
				PID:         d.row.ID,
				Path:        path.Join(d.row.BatchPath, d.row.FileName),
				Tags:        tags,
				DurationSec: float64(d.doc.DurationMS) / 1000,
			})
		}
		for _, unit := range match.Cluster(tracks) {
			unitDocs := make([]memberDoc, 0, len(unit.Tracks))
			for _, tr := range unit.Tracks {
				unitDocs = append(unitDocs, byID[tr.PID])
			}
			units = append(units, unitDocs)
		}
	}

	for _, unit := range units {
		unitDocs := make([]reviewTrackDoc, 0, len(unit))
		for _, d := range unit {
			unitDocs = append(unitDocs, d.doc)
		}
		first := unitDocs[0]
		entry := wdb.ReviewEntry{
			Kind:       reviewKindImport,
			MediaType:  b.MediaType,
			Origin:     reviewOriginUpload,
			LibraryPID: b.LibraryPID,
			UploadedBy: b.UserID,
			Title:      firstNonEmpty(first.Tags["ALBUM"], first.Title),
			Artist:     firstNonEmpty(first.Tags["ALBUMARTIST"], first.Artist),
		}
		entryID, err := l.openReviewEntry(ctx, entry, reviewPayload{Tracks: unitDocs}, b.Identify)
		if err != nil {
			return b, declined, err
		}
		// Recorded before the links land: the id list is what the
		// repair pass reads, so a crash right here leaves a batch the
		// next attempt can heal instead of double-opening.
		ids = append(ids, entryID)
		if err := persist(); err != nil {
			fail("recording batch entries", b.ID, err)
		}
		for _, d := range unit {
			linked, err := l.db.LinkUploadReviewEntry(ctx, d.row.ID, entryID)
			if err != nil {
				fail("linking batch member", d.row.ID, err)
				continue
			}
			if !linked {
				// The member vanished (deleted mid-finalize) or is
				// already linked; nothing to record either way.
				continue
			}
			l.emitUserEvent(ctx, d.row.UserID, eventUpload, d.row.ID)
		}
		if !b.Identify {
			// Handed back, not imported here: the caller runs these off
			// the finalize lock.
			declined = append(declined, entryID)
		}
	}
	if firstErr != nil {
		return b, declined, &Error{Kind: KindInternal, Err: firstErr}
	}
	return b, declined, nil
}
