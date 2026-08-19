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

// MaxUploadChunk bounds one data request's body, as the contract
// promises. Without it a session's own declared size is the only bound
// on a single PUT, so one request could legitimately stream gigabytes.
const MaxUploadChunk = 32 << 20

// MaxUploadSize bounds one session's declared size. It is the schema's
// own maximum, and the reason the quota arithmetic further down is safe
// to do in int64 at all: an unbounded sizeBytes overflows `used + size`
// and wraps past the very limit it is being checked against.
//
// 16 GiB clears the largest single file anybody uploads - a long
// hi-res or DSD single-file release, a hundred-hour audiobook - by
// enough that it refuses nothing real. What actually decides whether a
// big upload is accepted is the caller's quota and the room on the
// staging volume, both of which move; this one does not.
const MaxUploadSize = 16 << 30

// stagingReserve is the room checkStagingRoom leaves free after an
// upload it accepts. Staging shares its volume with the catalog, its
// write-ahead log, and the archive a scheduled backup builds beside
// them, and a volume driven to zero fails in ways a refused upload does
// not.
//
// It does not cover the import: that renames within the volume when the
// library lives on it (`Copy: false`), and copies onto a different one
// when it does not - a volume this check never probes. Nor does it
// scale: it is a floor for the databases, not a fraction of the disk.
const stagingReserve = 512 << 20

// stagingReservationWindow is how long a session's unwritten bytes keep
// holding room. See db.UploadBytesOutstanding for why a promise needs
// an expiry at all, and which way the error runs.
const stagingReservationWindow = time.Hour

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
// sessions still in staging against the account's pending-upload limit
// (0 meaning no limit).
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
	// Identify is the submission's identification choice; nil means the
	// account default. Joining a batch overwrites it with the batch's,
	// so every file in a batch is treated alike.
	Identify *bool
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
// against the caller's pending-upload limit up front.
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
	if p.SizeBytes > MaxUploadSize {
		// Invalid rather than over-quota: nothing the caller or the
		// operator can free moves a compile-time ceiling, and
		// `quota-exceeded` reads as "clear some space and retry" in
		// every client that words it. A refused declaration keeps the
		// server's own sentence, which is the one that names the size.
		return UploadDTO{}, errInvalid(fmt.Sprintf(
			"one upload may declare at most %d bytes; this one declares %d",
			MaxUploadSize, p.SizeBytes))
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
	// The two allowance checks and the insert that spends them run one
	// caller at a time. Both read a total and then add to it, so
	// concurrent creates otherwise all read the same pre-insert figure,
	// all pass, and all insert - which is the overrun the staging check
	// exists to stop, arriving by a different door. Creates are paced
	// and never hot, so the cost of serializing them is nothing.
	l.admitUpload.Lock()
	defer l.admitUpload.Unlock()
	if uc.UploadQuotaBytes > 0 {
		used, err := l.db.UploadBytesInUse(ctx, uc.ID)
		if err != nil {
			return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
		}
		if used+p.SizeBytes > uc.UploadQuotaBytes {
			return UploadDTO{}, &Error{Kind: KindQuota, Msg: fmt.Sprintf(
				"uploads waiting for review may total %d bytes, %d in use; this one needs %d more. Importing or discarding what is staged frees the room",
				uc.UploadQuotaBytes, used, p.SizeBytes)}
		}
	}
	// Last of the three ceilings, and the only one the caller cannot
	// clear by deciding their own staged uploads: it is the server's
	// disk. Checked after the quota so somebody who is simply over their
	// own allowance hears that instead.
	if err := l.checkStagingRoom(ctx, p.SizeBytes); err != nil {
		return UploadDTO{}, err
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
		Identify:    l.resolveIdentify(ctx, uc.ID, p.Identify),
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

// checkStagingRoom refuses a session the staging volume cannot hold.
//
// Free space alone is not the answer. It already reflects the bytes
// that landed, and says nothing about the bytes every session still
// receiving has been promised room for, so those are counted against it
// here - without them, a hundred sessions that each fit are each
// accepted and together overrun the volume.
//
// A platform that cannot answer, or a staging directory that has gone
// missing underneath the server, skips the check: refusing every upload
// on a number nobody could read is worse than the hole it closes.
func (l *Library) checkStagingRoom(ctx context.Context, size int64) error {
	// Absent in a Library built by hand rather than opened, which is how
	// several tests reach the surfaces around this one.
	if l.stagingFree == nil {
		return nil
	}
	free, ok := l.stagingFree(l.stagingDir)
	if !ok {
		return nil
	}
	since := time.Now().Add(-stagingReservationWindow).UnixNano()
	owed, err := l.db.UploadBytesOutstanding(ctx, since)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if free-owed-size < stagingReserve {
		// The figures stay in the log. Free space on the host and the
		// bytes every other account has in flight are the operator's to
		// see, and answering them to any caller with an upload grant
		// makes this endpoint an oracle for both.
		l.log.Warn("refusing an upload for want of staging room",
			"free", free, "promised", owed, "reserve", stagingReserve, "needs", size)
		return &Error{Kind: KindStorageFull,
			Msg: "the server has no room to stage this upload"}
	}
	return nil
}

// findContentDuplicate resolves a byte-identical content hash to an
// existing item.
func (l *Library) findContentDuplicate(ctx context.Context, sha string) (string, bool) {
	// The catalog's content-hash index answers "do I already hold these
	// exact bytes" across the whole library, the strongest pre-transfer
	// signal. The store tags the hash with its algorithm ("sha256:" plus
	// hex), so the bare upload digest is prefixed to match. A single-file
	// CUE album returns one item per virtual track sharing the file; any
	// of them is a fair warning, so the first wins.
	if items, err := l.lib.ItemsByContentHash(ctx, "sha256:"+sha); err == nil && len(items) > 0 {
		return string(items[0].PID), true
	}
	// A byte-identical upload still in flight (received, not yet
	// cataloged) is caught by this server's own upload history. The
	// completion-time essence check remains the real net: it survives a
	// retag the content hash does not.
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
	// Two bounds, and reading one byte past whichever binds first is how
	// they are told apart from a body that fits. The chunk cap is the
	// contract's promise about a single request; the remainder is this
	// session's own. Nothing is read past either, so a client streaming
	// an endless body gets one chunk's worth of disk and a refusal.
	limit := min(remaining, MaxUploadChunk)
	n, err := io.Copy(f, io.LimitReader(body, limit+1))
	if err != nil {
		return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	if n > limit {
		// The over-length bytes already hit disk at this offset; truncate back
		// to the last good length so a corrected retry cannot leave a stray
		// trailing byte past the declared size.
		if terr := f.Truncate(offset); terr != nil {
			l.log.Warn("truncating over-length upload chunk", "upload", u.ID, "err", terr)
		}
		if limit < remaining {
			return UploadDTO{}, errInvalid(fmt.Sprintf(
				"a chunk may carry at most %d bytes; resume at this offset with a shorter one",
				MaxUploadChunk))
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
		// the member falls through to the per-file path below -
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
	entryID, err := l.openReviewEntry(ctx, entry, reviewPayload{Tracks: []reviewTrackDoc{track}}, u.Identify)
	if err != nil {
		return UploadDTO{}, err
	}
	u.ReviewEntryID = entryID
	if err := l.db.UpdateUpload(ctx, u); err != nil {
		return UploadDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	if !u.Identify {
		// The session is linked, so settling can find it. This rewrites
		// the row (staged -> imported), which is why the answer is read
		// back rather than built from the copy above.
		// On procCtx, as batch finalize is: a client hanging up mid-copy
		// must not leave half an import behind.
		l.importDeclinedEntry(l.procCtx, entryID)
		if fresh, ferr := l.db.UploadByID(ctx, u.ID); ferr == nil {
			u = fresh
		}
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
	if l.pendingEntryHasLanded(ctx, u.ReviewEntryID) {
		return &Error{Kind: KindConflict,
			Msg: "part of this upload's review unit is already in the library; retry the decision, or delete the imported items first"}
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
// library and fills in the resulting item pids. A file that fails to
// enter the library keeps its staged bytes and session, whatever did
// import is settled and persisted on the entry, and the returned error
// carries the import's own reason - so the caller leaves the decision
// unmade and it can be retried once the cause is fixed.
func (l *Library) importEntryFiles(ctx context.Context, entry *wdb.ReviewEntry, payload *reviewPayload) ([]string, error) {
	var warnings, failures []string
	// Staging path -> item pid for every file that entered the library
	// ("" when the imported item did not resolve). Settling keys on
	// membership, and a failed decide persists the pids that did land:
	// staged copies are moved rather than copied, so a retry must skip
	// them or it would re-import files that are no longer staged.
	imported := map[string]string{}
	fail := func(err error) ([]string, error) {
		// Persist against the freshest row: everything the identify side
		// owns, since a stale full-row write would revert candidates on
		// an entry that stays pending and lose a typed search silently.
		// Only Tracks are this function's to write.
		row := *entry
		if fresh, ferr := l.db.ReviewEntryByID(ctx, entry.ID); ferr == nil {
			var fp reviewPayload
			if json.Unmarshal([]byte(fresh.Payload), &fp) == nil {
				if len(fp.Candidates) > 0 {
					payload.Candidates = fp.Candidates
				}
				payload.Override = fp.Override
				payload.Suggested = fp.Suggested
				payload.IdentifyDeclined = fp.IdentifyDeclined
			}
			row = fresh
		}
		row.Payload = marshalJSON(*payload)
		if uerr := l.db.UpdateReviewEntry(ctx, row); uerr != nil {
			l.log.Warn("persisting partial import", "entry", entry.ID, "err", uerr)
		}
		*entry = row
		l.settleImportedUploads(ctx, entry, imported)
		return warnings, err
	}
	for i := range payload.Tracks {
		doc := &payload.Tracks[i]
		if doc.PID != "" || doc.Imported {
			imported[doc.Path] = doc.PID // already in the library
			continue
		}
		kind, _ := kindForMediaType(entry.MediaType)
		res, err := l.lib.ImportAcquired(ctx, waxbin.AcquiredFile{Path: doc.Path}, kind, waxbin.AcquiredMeta{
			SourceType: model.SourceManual, Copy: false, DupPolicy: model.DupAllow,
		})
		if err != nil {
			return fail(classify(err))
		}
		switch {
		case res.EpisodePID != "":
			doc.PID = string(res.EpisodePID)
			imported[doc.Path] = doc.PID
		case res.Plan != nil:
			report, err := l.lib.ApplyImport(ctx, res.Plan)
			if err != nil {
				return fail(classify(err))
			}
			if report.Imported == 0 {
				failures = append(failures, fmt.Sprintf("%s: %s", filepath.Base(doc.Path),
					l.scrubStoragePaths(importFailureReason(res.Plan, report))))
				continue
			}
			doc.Imported = true
			imported[doc.Path] = ""
			pid, err := l.resolveImportedItem(ctx, res.Plan, doc)
			if err != nil {
				warnings = append(warnings, fmt.Sprintf("%s: imported but not yet resolvable: %v", filepath.Base(doc.Path), err))
				continue
			}
			doc.PID = pid
			imported[doc.Path] = pid
		default:
			failures = append(failures, fmt.Sprintf("%s: the import produced nothing", filepath.Base(doc.Path)))
		}
	}
	if len(failures) > 0 {
		msg := failures[0]
		if len(failures) > 1 {
			msg = fmt.Sprintf("%s (and %d more)", msg, len(failures)-1)
		}
		return fail(&Error{Kind: KindConflict, Msg: msg})
	}
	l.settleImportedUploads(ctx, entry, imported)
	return warnings, nil
}

// settleImportedUploads marks the upload sessions whose staged files
// entered the library and reclaims their staging space; every other
// session stays staged so its bytes survive for a retry. The recorded
// item pid is what grants the uploader item-scoped editing rights
// afterward.
func (l *Library) settleImportedUploads(ctx context.Context, entry *wdb.ReviewEntry, imported map[string]string) {
	if entry.Origin != reviewOriginUpload && entry.Origin != reviewOriginAcquire {
		return
	}
	rows, err := l.db.ListUploadsByReviewEntry(ctx, entry.ID)
	if err != nil {
		return
	}
	for _, r := range rows {
		if r.State != uploadStaged {
			continue
		}
		pid, ok := imported[r.StagingPath]
		if !ok {
			continue
		}
		r.State = uploadImported
		r.ItemPID = pid
		if err := l.db.UpdateUpload(ctx, r); err != nil {
			l.log.Warn("marking upload imported", "upload", r.ID, "err", err)
		}
		_ = os.RemoveAll(filepath.Join(l.stagingDir, r.ID))
		l.emitUserEvent(ctx, r.UserID, eventUpload, r.ID)
	}
}

// scrubStoragePaths strips server filesystem layout from a message
// bound for a client, matching the read surface's base-name posture:
// staging and library-root prefixes reduce to the path's own tail.
func (l *Library) scrubStoragePaths(s string) string {
	if l.stagingDir != "" {
		s = strings.ReplaceAll(s, l.stagingDir+string(filepath.Separator), "")
	}
	for _, r := range l.libraryRoots() {
		p := cleanRootPath(r.Path)
		if p == "" || p == "." {
			continue
		}
		s = strings.ReplaceAll(s, p+string(filepath.Separator), "")
		s = strings.ReplaceAll(s, p, "the library")
	}
	return s
}

// pendingEntryHasLanded reports whether an upload's linked review entry
// is still pending with tracks already in the library. Such an entry's
// staged bytes must survive (a retried decision needs them), and
// discarding it would orphan the landed items.
func (l *Library) pendingEntryHasLanded(ctx context.Context, reviewEntryID string) bool {
	if reviewEntryID == "" {
		return false
	}
	entry, err := l.db.ReviewEntryByID(ctx, reviewEntryID)
	if err != nil || entry.Status != reviewPending {
		return false
	}
	var payload reviewPayload
	if json.Unmarshal([]byte(entry.Payload), &payload) != nil {
		return false
	}
	return l.landedTracks(ctx, &payload) > 0
}

// landedTracks counts a payload's tracks that entered the library and
// still exist there: pid-resolving docs, plus imported docs whose pid
// never resolved (those cannot be re-checked, so they count).
func (l *Library) landedTracks(ctx context.Context, payload *reviewPayload) int {
	n := 0
	for _, doc := range payload.Tracks {
		if doc.PID == "" {
			if doc.Imported {
				n++
			}
			continue
		}
		if it, err := l.lib.Get(ctx, model.PID(doc.PID)); err == nil && it != nil {
			n++
		}
	}
	return n
}

// importFailureReason names why an applied plan imported nothing: the
// executor's recorded failure when one ran, else the planner's own
// verdict on the file.
func importFailureReason(plan *inbox.Plan, report *inbox.Report) string {
	if len(report.Failures) > 0 {
		return report.Failures[0].Err
	}
	for _, a := range plan.Actions {
		if a.Outcome != inbox.OutcomeImport && a.Reason != "" {
			return a.Reason
		}
	}
	return "the import planner produced no importable action"
}

// CanCurateItem reports whether the caller may run item-scoped
// metadata mutations on the item: administrators always, everyone
// else exactly for the items their own uploads and acquisitions
// brought into the library.
//
// A lookup that fails reads as no, which is the only safe answer for a
// gate. Callers that are describing the permission rather than
// enforcing it want the failure itself, and take [MayCurateItem].
func (l *Library) CanCurateItem(ctx context.Context, uc *UserCtx, apiItemPID string) bool {
	may, err := l.MayCurateItem(ctx, uc, apiItemPID)
	if err != nil {
		l.log.Warn("checking upload ownership", "item", apiItemPID, "err", err)
		return false
	}
	return may
}

// MayCurateItem is [CanCurateItem] with a failed lookup kept rather
// than folded into a no.
//
// The metadata read wants that difference. A gate that cannot answer
// must refuse; a document that says "you may not" when the truth is
// "the database did not answer" sends the person whose upload brought
// the item in to a refusal screen for an item their next save would be
// given - and a 200 carrying it is not something a client retries.
func (l *Library) MayCurateItem(ctx context.Context, uc *UserCtx, apiItemPID string) (bool, error) {
	if uc.Admin {
		return true, nil
	}
	_, pid, ok := parseAPIPID(apiItemPID)
	if !ok {
		return false, nil
	}
	return l.db.UploadOwnsItem(ctx, uc.ID, string(pid))
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
		if l.pendingEntryHasLanded(ctx, u.ReviewEntryID) {
			// Keep the bytes: the pending entry needs them for a
			// retried decision, and discarding it would orphan its
			// landed items. Push the expiry forward so the row leaves
			// the expired set instead of clogging every drain round.
			u.ExpiresAtNS = time.Now().Add(l.uploadRetention).UnixNano()
			if err := l.db.UpdateUpload(ctx, u); err != nil {
				l.log.Warn("deferring partially imported upload", "upload", u.ID, "err", err)
			}
			continue
		}
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
