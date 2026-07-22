package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"
	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/fingerprint"
	"github.com/colespringer/waxbin/inbox"
	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Upload session states.
const (
	uploadReceiving = "receiving"
	uploadStaged    = "staged"
	uploadImported  = "imported"
	uploadDiscarded = "discarded"
)

// MaxUploadChunk bounds one data request's body.
const MaxUploadChunk = 32 << 20

// uploadFormatSet builds the accepted-extension set (lowercase, no
// dot). The default is every format the catalog scans and the decode
// stack reads.
func uploadFormatSet(formats []string) map[string]bool {
	if len(formats) == 0 {
		formats = []string{
			"flac", "mp3", "m4a", "m4b", "aac", "ogg", "oga", "opus",
			"wav", "aif", "aiff", "mka", "webm",
		}
	}
	out := make(map[string]bool, len(formats))
	for _, f := range formats {
		out[strings.ToLower(strings.TrimPrefix(strings.TrimSpace(f), "."))] = true
	}
	return out
}

// UploadDTO is the API-facing session shape.
type UploadDTO struct {
	ID            string
	FileName      string
	SizeBytes     int64
	ReceivedBytes int64
	MediaType     string
	LibraryPID    string
	BatchID       string
	State         string
	ReviewEntryID string
	Duplicate     *DuplicateDTO
	UploadedBy    string
	CreatedAt     time.Time
	ExpiresAt     time.Time
}

// UploadQuotaDTO is the caller's allowance snapshot: declared bytes of
// live sessions against the account cap (0 meaning no cap).
type UploadQuotaDTO struct {
	BytesInUse int64
	QuotaBytes int64
}

// DuplicateDTO is the dedupe warning payload.
type DuplicateDTO struct {
	ItemPID string
	Kind    string
	Title   string
	Artist  string
}

// UploadCreateParams are the session parameters.
type UploadCreateParams struct {
	FileName   string
	SizeBytes  int64
	MediaType  string
	LibraryPID string
	SHA256     string
	BatchID    string
	BatchPath  string
}

func uploadDTO(u wdb.Upload) UploadDTO {
	dto := UploadDTO{
		ID:            u.ID,
		FileName:      u.FileName,
		SizeBytes:     u.SizeBytes,
		ReceivedBytes: u.ReceivedBytes,
		MediaType:     u.MediaType,
		LibraryPID:    u.LibraryPID,
		BatchID:       u.BatchID,
		State:         u.State,
		ReviewEntryID: u.ReviewEntryID,
		UploadedBy:    u.UserID,
		CreatedAt:     time.Unix(0, u.CreatedAtNS).UTC(),
	}
	if u.ExpiresAtNS > 0 {
		dto.ExpiresAt = time.Unix(0, u.ExpiresAtNS).UTC()
	}
	if u.DuplicatePID != "" {
		dto.Duplicate = &DuplicateDTO{ItemPID: u.DuplicatePID, Kind: u.DuplicateKind}
	}
	return dto
}

// requireUploader gates the upload surface.
func (l *Library) requireUploader(uc *UserCtx) error {
	if !uc.UploadEnabled {
		return &Error{Kind: KindForbidden, Msg: "your account has no upload rights"}
	}
	return nil
}

// validateUploadTargetLibrary checks a caller-named target library
// for the upload surfaces (sessions and batches): it must exist, be
// visible to the caller, and be writable. Empty means the server
// routes by media type and passes here.
func (l *Library) validateUploadTargetLibrary(ctx context.Context, uc *UserCtx, apiPID string) error {
	if apiPID == "" {
		return nil
	}
	prefix, pid, ok := parseAPIPID(apiPID)
	if !ok || prefix != PrefixLibrary {
		return errNotFound("no such library")
	}
	if _, err := l.libraryByPID(ctx, pid); err != nil {
		return err
	}
	if !uc.AllLibraries && !uc.Libraries[string(pid)] {
		return errNotFound("no such library")
	}
	return l.CheckWritable(ctx, string(pid))
}

// CreateUpload opens a resumable session, charging the declared size
// against the caller's quota up front.
func (l *Library) CreateUpload(ctx context.Context, uc *UserCtx, p UploadCreateParams) (UploadDTO, error) {
	if err := l.requireUploader(uc); err != nil {
		return UploadDTO{}, err
	}
	if err := l.CheckWritable(ctx, ""); err != nil {
		return UploadDTO{}, err
	}
	name := filepath.Base(strings.TrimSpace(p.FileName))
	if name == "" || name == "." || name != p.FileName {
		return UploadDTO{}, errInvalid("fileName must be a bare file name")
	}
	if p.SizeBytes <= 0 {
		return UploadDTO{}, errInvalid("sizeBytes must be positive")
	}
	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(name), "."))
	if !l.uploadFormats[ext] {
		return UploadDTO{}, &Error{Kind: KindFormat, Msg: fmt.Sprintf("files of type %q are not accepted", ext)}
	}
	if _, ok := kindForMediaType(p.MediaType); !ok {
		return UploadDTO{}, errInvalid("unknown media type")
	}
	if err := l.validateUploadTargetLibrary(ctx, uc, p.LibraryPID); err != nil {
		return UploadDTO{}, err
	}
	if err := l.batchForMember(ctx, uc, &p); err != nil {
		return UploadDTO{}, err
	}
	if uc.UploadQuotaBytes > 0 {
		used, err := l.db.UploadBytesInUse(ctx, uc.ID)
		if err != nil {
			return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
		}
		if used+p.SizeBytes > uc.UploadQuotaBytes {
			return UploadDTO{}, &Error{Kind: KindQuota, Msg: fmt.Sprintf(
				"quota is %d bytes, %d in use; this upload needs %d more",
				uc.UploadQuotaBytes, used, p.SizeBytes)}
		}
	}

	u := wdb.Upload{
		ID:          "up-" + ulid.Make().String(),
		UserID:      uc.ID,
		FileName:    name,
		SizeBytes:   p.SizeBytes,
		MediaType:   p.MediaType,
		LibraryPID:  p.LibraryPID,
		BatchID:     p.BatchID,
		BatchPath:   p.BatchPath,
		SHA256:      strings.ToLower(p.SHA256),
		State:       uploadReceiving,
		CreatedAtNS: time.Now().UnixNano(),
		ExpiresAtNS: time.Now().Add(l.uploadRetention).UnixNano(),
	}

	// The up-front exact-duplicate warning, when the caller sent the
	// hash: any cataloged file with identical bytes.
	if u.SHA256 != "" {
		if pid, ok := l.findContentDuplicate(ctx, u.SHA256); ok {
			u.DuplicatePID = pid
			u.DuplicateKind = "content"
		}
	}

	dir := filepath.Join(l.stagingDir, u.ID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.InsertUpload(ctx, u); err != nil {
		return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	l.emitUserEvent(ctx, uc.ID, eventUpload, u.ID)
	return l.hydrateUploadDuplicate(ctx, u), nil
}

// findContentDuplicate scans cataloged files for a byte-identical
// content hash.
func (l *Library) findContentDuplicate(ctx context.Context, sha string) (string, bool) {
	// The facade exposes per-file content hashes, not a hash index;
	// resolving through the portable-ref ladder needs an essence hash,
	// which is not the plain file hash. This pre-check is therefore
	// best-effort: it answers only when the identical file was uploaded
	// through this server before (session history), and the essence
	// check at completion is the real net. The hash lookup goes straight
	// to the row, so a match older than any recent-session window still
	// counts.
	pid, ok, err := l.db.ContentDuplicateByHash(ctx, sha, uploadImported)
	if err != nil {
		return "", false
	}
	return pid, ok
}

// hydrateUploadDuplicate fills the duplicate's display fields.
func (l *Library) hydrateUploadDuplicate(ctx context.Context, u wdb.Upload) UploadDTO {
	dto := uploadDTO(u)
	if dto.Duplicate != nil {
		if it, err := l.lib.Get(ctx, model.PID(dto.Duplicate.ItemPID)); err == nil {
			dto.Duplicate.Title = it.Title
			dto.Duplicate.Artist = it.Artist
			dto.Duplicate.ItemPID = itemAPIPID(it)
		}
	}
	return dto
}

// uploadForCaller loads a session the caller may touch.
func (l *Library) uploadForCaller(ctx context.Context, uc *UserCtx, id string) (wdb.Upload, error) {
	u, err := l.db.UploadByID(ctx, id)
	if errors.Is(err, wdb.ErrNotFound) {
		return wdb.Upload{}, errNotFound("no such upload")
	}
	if err != nil {
		return wdb.Upload{}, &Error{Kind: KindInternal, Err: err}
	}
	if u.UserID != uc.ID && !uc.Admin {
		return wdb.Upload{}, errNotFound("no such upload")
	}
	return u, nil
}

// GetUpload reads one session.
func (l *Library) GetUpload(ctx context.Context, uc *UserCtx, id string) (UploadDTO, error) {
	u, err := l.uploadForCaller(ctx, uc, id)
	if err != nil {
		return UploadDTO{}, err
	}
	return l.hydrateUploadDuplicate(ctx, u), nil
}

// ListUploadsPage pages the caller's sessions (everyone's for
// administrators). The quota snapshot is always the caller's own; it
// rides the page because usage is volatile and the uploads screen
// refetches this listing anyway.
func (l *Library) ListUploadsPage(ctx context.Context, uc *UserCtx, cursor string, limit int) ([]UploadDTO, string, UploadQuotaDTO, error) {
	owner := uc.ID
	if uc.Admin {
		owner = ""
	}
	beforeNS, beforeID, err := decodeTimeCursor(cursor)
	if err != nil {
		return nil, "", UploadQuotaDTO{}, errInvalid("bad cursor")
	}
	rows, err := l.db.ListUploads(ctx, owner, beforeNS, beforeID, limit)
	if err != nil {
		return nil, "", UploadQuotaDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	used, err := l.db.UploadBytesInUse(ctx, uc.ID)
	if err != nil {
		return nil, "", UploadQuotaDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	quota := UploadQuotaDTO{BytesInUse: used, QuotaBytes: uc.UploadQuotaBytes}
	out := make([]UploadDTO, 0, len(rows))
	for _, r := range rows {
		out = append(out, l.hydrateUploadDuplicate(ctx, r))
	}
	next := ""
	if len(rows) == limit {
		last := rows[len(rows)-1]
		next = encodeTimeCursor(last.CreatedAtNS, last.ID)
	}
	return out, next, quota, nil
}

// AppendUploadData writes one chunk at offset, which must equal the
// session's received byte count.
func (l *Library) AppendUploadData(ctx context.Context, uc *UserCtx, id string, offset int64, body io.Reader) (UploadDTO, error) {
	u, err := l.uploadForCaller(ctx, uc, id)
	if err != nil {
		return UploadDTO{}, err
	}
	if u.State != uploadReceiving {
		return UploadDTO{}, &Error{Kind: KindConflict, Msg: "the upload is no longer receiving bytes"}
	}
	if offset != u.ReceivedBytes {
		return UploadDTO{}, &Error{Kind: KindConflict, Msg: fmt.Sprintf(
			"offset %d does not match the %d bytes received; resume there", offset, u.ReceivedBytes)}
	}
	part := l.uploadPartPath(u)
	f, err := os.OpenFile(part, os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	defer f.Close()
	if _, err := f.Seek(offset, io.SeekStart); err != nil {
		return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	remaining := u.SizeBytes - u.ReceivedBytes
	n, err := io.Copy(f, io.LimitReader(body, remaining+1))
	if err != nil {
		return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	if n > remaining {
		// The over-length bytes already hit disk at this offset; truncate back
		// to the last good length so a corrected retry cannot leave a stray
		// trailing byte past the declared size.
		if terr := f.Truncate(offset); terr != nil {
			l.log.Warn("truncating over-length upload chunk", "upload", u.ID, "err", terr)
		}
		return UploadDTO{}, errInvalid("more bytes than the declared size")
	}
	if err := f.Sync(); err != nil {
		return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	u.ReceivedBytes += n
	if err := l.db.UpdateUpload(ctx, u); err != nil {
		return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	return uploadDTO(u), nil
}

func (l *Library) uploadPartPath(u wdb.Upload) string {
	return filepath.Join(l.stagingDir, u.ID, u.FileName+".part")
}

func (l *Library) uploadFinalPath(u wdb.Upload) string {
	return filepath.Join(l.stagingDir, u.ID, u.FileName)
}

// CompleteUpload verifies the staged bytes, promotes them to their
// final staging name (crash-safe), runs the duplicate checks, and
// opens the review entry the identify pipeline fills.
func (l *Library) CompleteUpload(ctx context.Context, uc *UserCtx, id string) (UploadDTO, error) {
	u, err := l.uploadForCaller(ctx, uc, id)
	if err != nil {
		return UploadDTO{}, err
	}
	switch u.State {
	case uploadReceiving:
	case uploadStaged:
		// Idempotent: a retried complete answers the same session.
		return l.hydrateUploadDuplicate(ctx, u), nil
	default:
		return UploadDTO{}, &Error{Kind: KindConflict, Msg: "the upload is already decided"}
	}
	if u.ReceivedBytes != u.SizeBytes {
		return UploadDTO{}, &Error{Kind: KindConflict, Msg: fmt.Sprintf(
			"%d of %d bytes received; the upload is incomplete", u.ReceivedBytes, u.SizeBytes)}
	}
	part := l.uploadPartPath(u)
	if u.SHA256 != "" {
		sum, err := fileSHA256(part)
		if err != nil {
			return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
		}
		if sum != u.SHA256 {
			return UploadDTO{}, &Error{Kind: KindConflict, Msg: "the received bytes do not match the declared SHA-256"}
		}
	}
	// The audio must at least parse; garbage fails here, not at import.
	doc, err := waxlabel.ParseFile(ctx, part)
	if err != nil {
		return UploadDTO{}, &Error{Kind: KindFormat, Msg: "the file does not parse as audio"}
	}
	final := l.uploadFinalPath(u)
	if err := os.Rename(part, final); err != nil {
		return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	if dir, err := os.Open(filepath.Dir(final)); err == nil {
		_ = dir.Sync()
		dir.Close()
	}
	u.State = uploadStaged
	u.StagingPath = final

	// Duplicate checks: exact essence through the import planner, then
	// an acoustic fingerprint resolve when the tooling is present.
	tags := flatTags(doc)
	kind, _ := kindForMediaType(u.MediaType)
	if kind != model.KindEpisode {
		if res, err := l.lib.ImportAcquired(ctx, waxbin.AcquiredFile{Path: final}, kind, waxbin.AcquiredMeta{
			SourceType: model.SourceManual, Copy: true, DupPolicy: model.DupAllow,
		}); err == nil && res.AlreadyPresent && res.AlreadyPresentPID != "" {
			u.DuplicatePID = string(res.AlreadyPresentPID)
			u.DuplicateKind = "content"
		}
	}
	var fp string
	var fpDur int
	if l.fpcalcPath != "" {
		if v, d, err := fingerprint.ChromaprintCompressed(ctx, l.fpcalcPath, final, 0); err == nil {
			fp, fpDur = v, d
		}
	}
	if u.DuplicatePID == "" {
		ref := model.PortableRef{
			Kind:       kind,
			Artist:     firstNonEmpty(tags["ARTIST"], tags["ALBUMARTIST"]),
			Title:      tags["TITLE"],
			Album:      tags["ALBUM"],
			DurationMS: int64(fpDur) * 1000,
		}
		if it, rung, err := l.lib.ResolveRef(ctx, ref); err == nil && it != nil {
			switch rung {
			case model.MatchFingerprint:
				u.DuplicatePID = string(it.PID)
				u.DuplicateKind = "fingerprint"
			case model.MatchDescriptive:
				u.DuplicatePID = string(it.PID)
				u.DuplicateKind = "name"
			}
		}
	}

	track := reviewTrackDoc{
		Path:        final,
		Title:       firstNonEmpty(tags["TITLE"], strings.TrimSuffix(u.FileName, filepath.Ext(u.FileName))),
		Artist:      tags["ARTIST"],
		TrackNo:     parseIntTag(tags["TRACKNUMBER"]),
		DiscNo:      parseIntTag(tags["DISCNUMBER"]),
		DurationMS:  int64(fpDur) * 1000,
		Tags:        tags,
		Fingerprint: fp,
	}
	if u.BatchID != "" {
		// A batch member defers entry opening to the batch finalize,
		// persisting the built document instead. The conditional write
		// races finalize correctly under either ordering: it lands only
		// while the batch is open (finalize's gather then covers the
		// member), and a batch closed mid-work affects zero rows, so
		// the member falls through to the per-file path below —
		// exactly one review entry either way.
		staged, err := l.db.StageBatchMember(ctx, u, marshalJSON(track))
		if err != nil {
			return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
		}
		if staged {
			l.emitUserEvent(ctx, uc.ID, eventUpload, u.ID)
			return l.hydrateUploadDuplicate(ctx, u), nil
		}
	}
	entry := wdb.ReviewEntry{
		Kind:       reviewKindImport,
		MediaType:  u.MediaType,
		Origin:     reviewOriginUpload,
		LibraryPID: u.LibraryPID,
		UploadedBy: u.UserID,
		Title:      firstNonEmpty(tags["ALBUM"], track.Title),
		Artist:     firstNonEmpty(tags["ALBUMARTIST"], tags["ARTIST"]),
	}
	entryID, err := l.openReviewEntry(ctx, entry, reviewPayload{Tracks: []reviewTrackDoc{track}})
	if err != nil {
		return UploadDTO{}, err
	}
	u.ReviewEntryID = entryID
	if err := l.db.UpdateUpload(ctx, u); err != nil {
		return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	l.emitUserEvent(ctx, uc.ID, eventUpload, u.ID)
	return l.hydrateUploadDuplicate(ctx, u), nil
}

// DeleteUpload abandons a session and reclaims its staged bytes.
func (l *Library) DeleteUpload(ctx context.Context, uc *UserCtx, id string) error {
	u, err := l.uploadForCaller(ctx, uc, id)
	if err != nil {
		return err
	}
	if u.State == uploadImported {
		return &Error{Kind: KindConflict, Msg: "the upload already entered the library; delete the item there"}
	}
	if err := os.RemoveAll(filepath.Join(l.stagingDir, u.ID)); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	l.discardPendingEntry(ctx, u.ReviewEntryID, uc.ID)
	if err := l.db.DeleteUpload(ctx, id); err != nil && !errors.Is(err, wdb.ErrNotFound) {
		return &Error{Kind: KindInternal, Err: err}
	}
	l.emitUserEvent(ctx, uc.ID, eventUpload, id)
	return nil
}

// importEntryFiles moves an import entry's staged files into the
// library and fills in the resulting item pids.
func (l *Library) importEntryFiles(ctx context.Context, entry *wdb.ReviewEntry, payload *reviewPayload) ([]string, error) {
	var warnings []string
	for i := range payload.Tracks {
		doc := &payload.Tracks[i]
		if doc.PID != "" {
			continue // already in the library
		}
		kind, _ := kindForMediaType(entry.MediaType)
		res, err := l.lib.ImportAcquired(ctx, waxbin.AcquiredFile{Path: doc.Path}, kind, waxbin.AcquiredMeta{
			SourceType: model.SourceManual, Copy: false, DupPolicy: model.DupAllow,
		})
		if err != nil {
			return warnings, classify(err)
		}
		switch {
		case res.EpisodePID != "":
			doc.PID = string(res.EpisodePID)
		case res.Plan != nil:
			report, err := l.lib.ApplyImport(ctx, res.Plan)
			if err != nil {
				return warnings, classify(err)
			}
			if report.Imported == 0 {
				warnings = append(warnings, fmt.Sprintf("%s: the import planner quarantined the file", filepath.Base(doc.Path)))
				continue
			}
			pid, err := l.resolveImportedItem(ctx, res.Plan, doc)
			if err != nil {
				warnings = append(warnings, fmt.Sprintf("%s: imported but not yet resolvable: %v", filepath.Base(doc.Path), err))
				continue
			}
			doc.PID = pid
		default:
			warnings = append(warnings, fmt.Sprintf("%s: the import produced nothing", filepath.Base(doc.Path)))
		}
	}
	// Mark the backing sessions imported and remember which item each
	// staged file became: that link is what grants the uploader
	// item-scoped editing rights afterward.
	if entry.Origin == reviewOriginUpload || entry.Origin == reviewOriginAcquire {
		itemByPath := make(map[string]string, len(payload.Tracks))
		for _, doc := range payload.Tracks {
			if doc.PID != "" {
				itemByPath[doc.Path] = doc.PID
			}
		}
		if rows, err := l.db.ListUploads(ctx, entry.UploadedBy, 0, "", 200); err == nil {
			for _, r := range rows {
				if r.ReviewEntryID == entry.ID && r.State == uploadStaged {
					r.State = uploadImported
					r.ItemPID = itemByPath[r.StagingPath]
					if err := l.db.UpdateUpload(ctx, r); err != nil {
						l.log.Warn("marking upload imported", "upload", r.ID, "err", err)
					}
					_ = os.RemoveAll(filepath.Join(l.stagingDir, r.ID))
					l.emitUserEvent(ctx, r.UserID, eventUpload, r.ID)
				}
			}
		}
	}
	return warnings, nil
}

// CanCurateItem reports whether the caller may run item-scoped
// metadata mutations on the item: administrators always, everyone
// else exactly for the items their own uploads and acquisitions
// brought into the library.
func (l *Library) CanCurateItem(ctx context.Context, uc *UserCtx, apiItemPID string) bool {
	if uc.Admin {
		return true
	}
	_, pid, ok := parseAPIPID(apiItemPID)
	if !ok {
		return false
	}
	owns, err := l.db.UploadOwnsItem(ctx, uc.ID, string(pid))
	if err != nil {
		l.log.Warn("checking upload ownership", "item", apiItemPID, "err", err)
		return false
	}
	return owns
}

// resolveImportedItem finds the item an applied import produced for a
// staged file, through the plan action's essence.
func (l *Library) resolveImportedItem(ctx context.Context, plan *inbox.Plan, doc *reviewTrackDoc) (string, error) {
	essence := ""
	for _, a := range plan.Actions {
		if a.Src == doc.Path {
			essence = a.Essence
			break
		}
	}
	if essence == "" {
		return "", errors.New("no essence recorded for the staged file")
	}
	it, _, err := l.lib.ResolveRef(ctx, model.PortableRef{Essence: essence})
	if err != nil {
		return "", err
	}
	if it == nil {
		return "", errors.New("essence did not resolve")
	}
	return string(it.PID), nil
}

// discardPendingEntry closes an upload's linked review entry when it is still
// pending, so an abandoned or reclaimed upload never leaves an undecidable
// entry pointing at a staged file that is now gone. decidedBy is the acting
// user, or empty for the janitor.
func (l *Library) discardPendingEntry(ctx context.Context, reviewEntryID, decidedBy string) {
	if reviewEntryID == "" {
		return
	}
	entry, err := l.db.ReviewEntryByID(ctx, reviewEntryID)
	if err != nil || entry.Status != reviewPending {
		return
	}
	entry.Status = reviewDiscarded
	entry.Identifying = false
	entry.DecidedAtNS = time.Now().UnixNano()
	entry.DecidedBy = decidedBy
	if err := l.db.UpdateReviewEntry(ctx, entry); err == nil {
		l.notifyReview(ctx, entry.ID, entry.UploadedBy)
	}
}

// DrainExpiredUploads reclaims one batch of expired sessions; true
// means a session was fully reclaimed. A round where every row failed
// reports false so the caller's drain loop waits for the next tick
// instead of hot-looping over the same failures (a failed row stays
// expired and is re-listed).
func (l *Library) DrainExpiredUploads(ctx context.Context) bool {
	rows, err := l.db.ExpiredUploads(ctx, time.Now().UnixNano(), 20)
	if err != nil {
		l.log.Warn("listing expired uploads", "err", err)
		return false
	}
	if len(rows) == 0 {
		return false
	}
	progress := false
	for _, u := range rows {
		if err := os.RemoveAll(filepath.Join(l.stagingDir, u.ID)); err != nil {
			l.log.Warn("reclaiming expired upload", "upload", u.ID, "err", err)
			continue
		}
		u.State = uploadDiscarded
		if err := l.db.UpdateUpload(ctx, u); err != nil {
			l.log.Warn("marking upload expired", "upload", u.ID, "err", err)
			continue
		}
		progress = true
		// A completed-but-undecided upload has a pending entry pointing at the
		// file just removed; close it so it cannot later import a missing path.
		l.discardPendingEntry(ctx, u.ReviewEntryID, "")
		l.emitUserEvent(ctx, u.UserID, eventUpload, u.ID)
	}
	return progress
}

// flatTags flattens a parsed document's typed tag projection into the
// engine's canonical uppercase map.
func flatTags(doc *waxlabel.Document) map[string]string {
	t := doc.Fields()
	out := map[string]string{}
	set := func(k, v string) {
		if v != "" {
			out[k] = v
		}
	}
	set("TITLE", t.Title)
	if len(t.Artists) > 0 {
		set("ARTIST", t.Artists[0])
	}
	set("ALBUM", t.Album)
	set("ALBUMARTIST", t.AlbumArtist)
	if t.TrackNumber > 0 {
		out["TRACKNUMBER"] = strconv.Itoa(t.TrackNumber)
	}
	if t.DiscNumber > 0 {
		out["DISCNUMBER"] = strconv.Itoa(t.DiscNumber)
	}
	set("DATE", firstNonEmpty(t.OriginalDate, t.ReleaseDate, t.RecordingDate))
	if vals, ok := doc.Get(tag.Key("MUSICBRAINZ_ALBUMID")); ok && len(vals) > 0 {
		set("MUSICBRAINZ_ALBUMID", vals[0])
	}
	return out
}

func parseIntTag(s string) int {
	n := 0
	for _, r := range strings.TrimSpace(s) {
		if r < '0' || r > '9' {
			break
		}
		n = n*10 + int(r-'0')
		if n > 9999 {
			return 0
		}
	}
	return n
}

func fileSHA256(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// encodeTimeCursor and decodeTimeCursor are the (created_at_ns, id)
// keyset cursor used by the curation listings.
func encodeTimeCursor(ns int64, id string) string {
	return fmt.Sprintf("%d.%s", ns, id)
}

func decodeTimeCursor(cursor string) (int64, string, error) {
	if cursor == "" {
		return 0, "", nil
	}
	nsStr, id, ok := strings.Cut(cursor, ".")
	if !ok || id == "" {
		return 0, "", errors.New("bad cursor")
	}
	var ns int64
	if _, err := fmt.Sscanf(nsStr, "%d", &ns); err != nil {
		return 0, "", errors.New("bad cursor")
	}
	return ns, id, nil
}

// marshalJSON is a tiny helper for payload persistence sites that
// cannot reasonably fail.
func marshalJSON(v any) string {
	raw, err := json.Marshal(v)
	if err != nil {
		return "{}"
	}
	return string(raw)
}
