package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"strconv"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/fingerprint"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
	"github.com/oklog/ulid/v2"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/match"
)

// The matching pipeline: album units of files become review entries,
// the identify worker scores candidates through the engine, confident
// matches auto apply under the library's matching mode, and everything
// else waits for a decision. Entries store their evidence as a JSON
// payload; the catalog is touched only when a decision applies.

// The unofficial state rides a locked custom tag: RELEASESTATUS of
// unofficial (or an already tagged bootleg) excludes content from match
// retries and health penalties. Content with no canonical release is a
// terminal state, not an error.
const (
	releaseStatusKey        = "RELEASESTATUS"
	releaseStatusUnofficial = "unofficial"
)

// Review entry lifecycle states.
const (
	reviewPending     = "pending"
	reviewApplied     = "applied"
	reviewAutoApplied = "auto-applied"
	reviewAsIs        = "as-is"
	reviewUnofficial  = "unofficial"
	reviewSkipped     = "skipped"
	reviewDiscarded   = "discarded"
	reviewReverted    = "reverted"
)

// Entry kinds and origins.
const (
	reviewKindMatch  = "match"
	reviewKindImport = "import"

	reviewOriginScan    = "scan"
	reviewOriginUpload  = "upload"
	reviewOriginRematch = "rematch"
	reviewOriginAcquire = "acquisition"
)

// Library matching modes.
const (
	matchingAuto   = "auto"
	matchingReview = "review"
	matchingOff    = "off"
)

// reviewTrackDoc is one file in a stored review unit. Imported records
// that the file physically entered the library even when its item pid
// never resolved: a retried decision must not re-import it (the staged
// copy was moved), and a discard must count it as landed.
type reviewTrackDoc struct {
	PID         string            `json:"pid,omitempty"`
	Imported    bool              `json:"imported,omitempty"`
	Path        string            `json:"path"`
	Title       string            `json:"title"`
	Artist      string            `json:"artist,omitempty"`
	TrackNo     int               `json:"trackNo,omitempty"`
	DiscNo      int               `json:"discNo,omitempty"`
	DurationMS  int64             `json:"durationMs"`
	Tags        map[string]string `json:"tags,omitempty"`
	Fingerprint string            `json:"fingerprint,omitempty"`
}

// reviewPairingDoc is one stored file-to-release-track pairing.
type reviewPairingDoc struct {
	TrackIndex    int     `json:"trackIndex"`
	Position      int     `json:"position"`
	Disc          int     `json:"disc,omitempty"`
	Title         string  `json:"title"`
	Artist        string  `json:"artist,omitempty"`
	DurationMS    int64   `json:"durationMs,omitempty"`
	RecordingMBID string  `json:"recordingMbid,omitempty"`
	Distance      float64 `json:"distance"`
}

// reviewComponentDoc is one stored distance component.
type reviewComponentDoc struct {
	Name     string  `json:"name"`
	Distance float64 `json:"distance"`
	Weight   float64 `json:"weight"`
}

// reviewCandidateDoc is one stored scored candidate.
type reviewCandidateDoc struct {
	MBID             string               `json:"mbid"`
	ReleaseGroupMBID string               `json:"releaseGroupMbid,omitempty"`
	Title            string               `json:"title"`
	Artist           string               `json:"artist"`
	Year             int                  `json:"year,omitempty"`
	MediaCount       int                  `json:"mediaCount,omitempty"`
	TrackCount       int                  `json:"trackCount"`
	Country          string               `json:"country,omitempty"`
	Label            string               `json:"label,omitempty"`
	CatalogNumber    string               `json:"catalogNumber,omitempty"`
	Compilation      bool                 `json:"compilation,omitempty"`
	SimilarityPct    float64              `json:"similarityPct"`
	Components       []reviewComponentDoc `json:"components,omitempty"`
	Pairings         []reviewPairingDoc   `json:"pairings"`
	MissingTitles    []string             `json:"missingTitles,omitempty"`
	ExtraIndexes     []int                `json:"extraIndexes,omitempty"`
}

// reviewPayload is the entry's stored evidence.
type reviewPayload struct {
	Tracks     []reviewTrackDoc     `json:"tracks"`
	Candidates []reviewCandidateDoc `json:"candidates"`
}

// reviewSnapshot preserves pre-apply values for revert: per catalog
// item, the scalar fields the apply overwrote.
type reviewSnapshot struct {
	Items map[string]map[string]string `json:"items"`
}

func newReviewID() string { return "rv-" + ulid.Make().String() }

// notifyReview fans a review marker to every administrator plus the
// entry's uploader.
func (l *Library) notifyReview(ctx context.Context, entryID, uploadedBy string) {
	seen := map[string]bool{}
	if admins, err := l.db.EnabledAdminIDs(ctx); err == nil {
		for _, id := range admins {
			seen[id] = true
			l.emitUserEvent(ctx, id, eventReview, entryID)
		}
	} else {
		l.log.Warn("listing admins for review event", "err", err)
	}
	if uploadedBy != "" && !seen[uploadedBy] {
		l.emitUserEvent(ctx, uploadedBy, eventReview, entryID)
	}
}

// notifyReviewReady announces one entry whose identification just
// finished and which still needs a human decision. Emitted here, not
// at entry open, so an entry that auto-applies seconds later never
// notifies; scan and rematch entries stay silent too (bulk operations
// would flood, and their operator is already watching the queue). The
// entry re-reads so an auto-apply that landed meanwhile wins.
func (l *Library) notifyReviewReady(ctx context.Context, entryID string) {
	entry, err := l.db.ReviewEntryByID(ctx, entryID)
	if err != nil {
		return
	}
	if entry.Status != reviewPending {
		return
	}
	if entry.Origin != reviewOriginUpload && entry.Origin != reviewOriginAcquire {
		return
	}
	recipients := []string{}
	if admins, err := l.db.EnabledAdminIDs(ctx); err == nil {
		recipients = append(recipients, admins...)
	} else {
		l.log.Warn("listing admins for review notification", "err", err)
	}
	if entry.UploadedBy != "" {
		recipients = append(recipients, entry.UploadedBy)
	}
	what := entry.Title
	if entry.Artist != "" && what != "" {
		what = entry.Artist + ": " + what
	}
	if what == "" {
		what = fmt.Sprintf("%d files", entry.TrackCount)
	}
	l.EmitNotification(ctx, "review-ready", "Ready for review", what+" finished identification and waits for a decision.", recipients)
}

// openReviewEntry stores a pending entry and queues it for the
// identify worker.
func (l *Library) openReviewEntry(ctx context.Context, e wdb.ReviewEntry, payload reviewPayload) (string, error) {
	if e.ID == "" {
		e.ID = newReviewID()
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return "", &Error{Kind: KindInternal, Err: err}
	}
	e.Status = reviewPending
	e.Identifying = true
	e.Payload = string(raw)
	e.TrackCount = len(payload.Tracks)
	e.CreatedAtNS = time.Now().UnixNano()
	if err := l.db.InsertReviewEntry(ctx, e); err != nil {
		return "", &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.EnqueueMatch(ctx, e.ID); err != nil {
		return "", &Error{Kind: KindInternal, Err: err}
	}
	l.matchWakeup()
	l.notifyReview(ctx, e.ID, e.UploadedBy)
	return e.ID, nil
}

// matchWake is the identify worker's lossy wakeup hint; the ticker is
// the backstop.
func (l *Library) matchWakeup() {
	select {
	case l.matchWake <- struct{}{}:
	default:
	}
}

// MatchWakeups exposes the identify worker's wakeup channel to main.
func (l *Library) MatchWakeups() <-chan struct{} { return l.matchWake }

// RematchItem rebuilds the album unit containing an item and opens a
// fresh review entry for it. The unit is the item's album siblings;
// an item with no album is a unit of one.
func (l *Library) RematchItem(ctx context.Context, uc *UserCtx, apiItemPID string) (string, error) {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return "", err
	}
	if it.Kind != model.KindTrack {
		return "", errInvalid("matching covers music tracks; podcasts and audiobooks identify through their own pipelines")
	}
	unit, err := l.albumUnit(ctx, it)
	if err != nil {
		return "", err
	}
	libraryPID := ""
	if len(it.Path) > 0 {
		if lp, err := l.libraryForPath(ctx, string(it.Path)); err == nil {
			libraryPID = lp
		}
	}
	entry := wdb.ReviewEntry{
		Kind:       reviewKindMatch,
		MediaType:  mediaTypeForKind(it.Kind),
		Origin:     reviewOriginRematch,
		LibraryPID: libraryPID,
		Title:      firstNonEmpty(it.Album, it.Title),
		Artist:     firstNonEmpty(it.AlbumArtist, it.Artist),
	}
	return l.openReviewEntry(ctx, entry, reviewPayload{Tracks: unit})
}

// albumUnit gathers an item's album siblings as review track docs. It
// fetches every track sharing the album title and lets the engine's
// own clustering pick the unit the seed belongs to, which is what
// keeps a compilation together and two same-named albums by different
// artists apart (the store's album_artist column is empty for files
// tagged with per-track artists only, so filtering on it would lose
// siblings).
func (l *Library) albumUnit(ctx context.Context, it *model.ItemView) ([]reviewTrackDoc, error) {
	items := []*model.ItemView{it}
	if it.Album != "" {
		b := query.New(query.EntityTracks).Where("album", query.OpIs, it.Album)
		page, err := l.lib.QueryPage(ctx, b.Build(), read.Cursor(""), 1000, false, "")
		if err != nil {
			return nil, classify(err)
		}
		if len(page.Items) > 0 {
			byPID := make(map[string]*model.ItemView, len(page.Items))
			tracks := make([]match.Track, 0, len(page.Items))
			for _, sib := range page.Items {
				byPID[string(sib.PID)] = sib
				doc := itemTrackDoc(sib)
				tracks = append(tracks, match.Track{
					PID: doc.PID, Path: doc.Path, Tags: doc.Tags,
					DurationSec: float64(doc.DurationMS) / 1000,
				})
			}
			for _, unit := range match.Cluster(tracks) {
				holdsSeed := false
				for _, t := range unit.Tracks {
					if t.PID == string(it.PID) {
						holdsSeed = true
						break
					}
				}
				if holdsSeed {
					items = items[:0]
					for _, t := range unit.Tracks {
						items = append(items, byPID[t.PID])
					}
					break
				}
			}
		}
	}
	docs := make([]reviewTrackDoc, 0, len(items))
	for _, sib := range items {
		docs = append(docs, itemTrackDoc(sib))
	}
	return docs, nil
}

// itemTrackDoc renders a catalog item as a stored review track.
func itemTrackDoc(it *model.ItemView) reviewTrackDoc {
	return reviewTrackDoc{
		PID:        string(it.PID),
		Path:       it.DisplayPath,
		Title:      it.Title,
		Artist:     it.Artist,
		TrackNo:    it.TrackNo,
		DiscNo:     it.DiscNo,
		DurationMS: it.DurationMS,
		Tags:       itemTags(it),
	}
}

// itemTags rebuilds the engine's tag map from an item view.
func itemTags(it *model.ItemView) map[string]string {
	tags := map[string]string{}
	set := func(k, v string) {
		if v != "" {
			tags[k] = v
		}
	}
	set("TITLE", it.Title)
	set("ARTIST", it.Artist)
	set("ALBUM", it.Album)
	set("ALBUMARTIST", it.AlbumArtist)
	if it.TrackNo > 0 {
		tags["TRACKNUMBER"] = strconv.Itoa(it.TrackNo)
	}
	if it.DiscNo > 0 {
		tags["DISCNUMBER"] = strconv.Itoa(it.DiscNo)
	}
	if it.Year > 0 {
		tags["DATE"] = strconv.Itoa(it.Year)
	}
	if it.Compilation {
		tags["COMPILATION"] = "1"
	}
	return tags
}

// matchTracks converts stored track docs to engine input, computing
// fingerprints for real files when the fingerprint binary is present.
// Virtual tracks export no fingerprint by upstream design.
func (l *Library) matchTracks(ctx context.Context, docs []reviewTrackDoc) []match.Track {
	out := make([]match.Track, 0, len(docs))
	for _, d := range docs {
		t := match.Track{
			PID:         d.PID,
			Path:        d.Path,
			Tags:        d.Tags,
			DurationSec: float64(d.DurationMS) / 1000,
			Fingerprint: d.Fingerprint,
		}
		if t.Tags == nil {
			t.Tags = map[string]string{}
		}
		if t.Fingerprint == "" && l.fpcalcPath != "" && filepath.IsAbs(d.Path) {
			if fp, _, err := fingerprint.ChromaprintCompressed(ctx, l.fpcalcPath, d.Path, 0); err == nil {
				t.Fingerprint = fp
			}
		}
		out = append(out, t)
	}
	return out
}

// LibraryMatchingMode reads a library's matching mode (default auto).
// The key is the bare catalog pid; a prefixed API pid is normalized so
// both the handler (prefixed) and the pipeline (bare) read one truth.
func (l *Library) LibraryMatchingMode(ctx context.Context, libraryPID string) string {
	if prefix, bare, ok := parseAPIPID(libraryPID); ok && prefix == PrefixLibrary {
		libraryPID = string(bare)
	}
	mode, err := l.db.SettingGet(ctx, "matching:"+libraryPID)
	if err != nil || mode == "" {
		return matchingAuto
	}
	return mode
}

// LibraryMatchingFor reads a library's matching mode for the API,
// validating that the library exists first so an unknown or malformed
// pid answers not-found rather than a fabricated default. The pipeline
// reads the mode through LibraryMatchingMode, which never errors.
func (l *Library) LibraryMatchingFor(ctx context.Context, uc *UserCtx, apiLibraryPID string) (string, error) {
	if !uc.Admin {
		return "", &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	prefix, pid, ok := parseAPIPID(apiLibraryPID)
	if !ok || prefix != PrefixLibrary {
		return "", errNotFound("no such library")
	}
	if _, err := l.libraryByPID(ctx, pid); err != nil {
		return "", err
	}
	return l.LibraryMatchingMode(ctx, string(pid)), nil
}

// SetLibraryMatchingMode stores a library's matching mode.
func (l *Library) SetLibraryMatchingMode(ctx context.Context, uc *UserCtx, apiLibraryPID, mode string) error {
	if !uc.Admin {
		return &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	switch mode {
	case matchingAuto, matchingReview, matchingOff:
	default:
		return errInvalid("unknown matching mode")
	}
	prefix, pid, ok := parseAPIPID(apiLibraryPID)
	if !ok || prefix != PrefixLibrary {
		return errNotFound("no such library")
	}
	if _, err := l.libraryByPID(ctx, pid); err != nil {
		return err
	}
	if err := l.db.SettingSet(ctx, "matching:"+string(pid), mode, time.Now().UnixNano()); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// libraryByPID resolves a catalog library by bare pid.
func (l *Library) libraryByPID(ctx context.Context, pid model.PID) (*model.Library, error) {
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return nil, classify(err)
	}
	for _, lib := range libs {
		if lib.PID == pid {
			return lib, nil
		}
	}
	return nil, errNotFound("no such library")
}

// DrainMatchQueue runs one identify job; true means it did work.
func (l *Library) DrainMatchQueue(ctx context.Context) bool {
	now := time.Now()
	const (
		lease       = 10 * time.Minute
		maxAttempts = 5
	)
	if ids, err := l.db.DropExhaustedMatches(ctx, maxAttempts); err == nil {
		for _, id := range ids {
			l.finishIdentifyEmpty(ctx, id, "identification gave up after repeated provider failures")
		}
	}
	row, err := l.db.LeaseMatch(ctx, now.UnixNano(), int64(lease), maxAttempts)
	if err != nil {
		if !errors.Is(err, wdb.ErrNotFound) {
			l.log.Warn("leasing match work", "err", err)
		}
		return false
	}
	entry, err := l.db.ReviewEntryByID(ctx, row.EntryID)
	if err != nil {
		// The entry vanished; nothing to identify.
		_ = l.db.CompleteMatch(ctx, row.ID)
		return true
	}
	if entry.Status != reviewPending || !entry.Identifying {
		_ = l.db.CompleteMatch(ctx, row.ID)
		return true
	}
	if err := l.identifyEntry(ctx, &entry); err != nil {
		retry := time.Now().Add(backoffFor(row.Attempts)).UnixNano()
		if ferr := l.db.FailMatch(ctx, row.ID, err.Error(), retry); ferr != nil {
			l.log.Warn("recording match failure", "entry", entry.ID, "err", ferr)
		}
		l.log.Warn("identify failed", "entry", entry.ID, "attempt", row.Attempts+1, "err", err)
		return true
	}
	if err := l.db.CompleteMatch(ctx, row.ID); err != nil {
		l.log.Warn("completing match work", "entry", entry.ID, "err", err)
	}
	return true
}

func backoffFor(attempts int) time.Duration {
	d := time.Minute << attempts
	if d > 30*time.Minute {
		d = 30 * time.Minute
	}
	return d
}

// finishIdentifyEmpty closes identification with no candidates.
func (l *Library) finishIdentifyEmpty(ctx context.Context, entryID, note string) {
	entry, err := l.db.ReviewEntryByID(ctx, entryID)
	if err != nil {
		return
	}
	entry.Identifying = false
	if err := l.db.UpdateReviewEntry(ctx, entry); err != nil {
		l.log.Warn("closing identification", "entry", entryID, "err", err)
		return
	}
	if note != "" {
		l.log.Info("identification closed without candidates", "entry", entryID, "note", note)
	}
	l.notifyReview(ctx, entry.ID, entry.UploadedBy)
	l.notifyReviewReady(ctx, entry.ID)
}

// identifyEntry runs the engine for one entry and applies the
// confident outcome when the library's mode allows it.
func (l *Library) identifyEntry(ctx context.Context, entry *wdb.ReviewEntry) error {
	var payload reviewPayload
	if err := json.Unmarshal([]byte(entry.Payload), &payload); err != nil {
		return fmt.Errorf("decoding payload: %w", err)
	}
	mode := l.LibraryMatchingMode(ctx, entry.LibraryPID)
	if l.engine == nil || mode == matchingOff || entry.MediaType != "music" {
		entry.Identifying = false
		if err := l.db.UpdateReviewEntry(ctx, *entry); err != nil {
			return err
		}
		l.notifyReview(ctx, entry.ID, entry.UploadedBy)
		l.notifyReviewReady(ctx, entry.ID)
		return nil
	}

	tracks := l.matchTracks(ctx, payload.Tracks)
	// Persist computed fingerprints so a retry does not respawn fpcalc.
	for i := range tracks {
		payload.Tracks[i].Fingerprint = tracks[i].Fingerprint
	}
	units := match.Cluster(tracks)
	unit := match.Unit{Tracks: tracks}
	if len(units) == 1 {
		unit = units[0]
	}
	proposal, err := l.engine.Identify(ctx, unit)
	if err != nil {
		return fmt.Errorf("identifying: %w", err)
	}

	// The cluster may have reordered tracks; map pairings back to the
	// payload's track order by PID-or-path identity.
	indexOf := make(map[string]int, len(payload.Tracks))
	for i, d := range payload.Tracks {
		indexOf[d.PID+"\x00"+d.Path] = i
	}
	payload.Candidates = payload.Candidates[:0]
	for i := range proposal.Candidates {
		payload.Candidates = append(payload.Candidates, candidateDoc(&proposal.Candidates[i], unit, indexOf))
	}
	entry.Identifying = false
	if best := proposal.Best(); best != nil {
		entry.BestMBID = best.Release.MBID
		entry.BestTitle = best.Release.Title
		entry.BestArtist = best.Release.Artist
		entry.BestYear = best.Release.Year
		entry.BestSimilarity = best.Similarity() * 100
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	entry.Payload = string(raw)
	if err := l.db.UpdateReviewEntry(ctx, *entry); err != nil {
		return err
	}

	if proposal.Decision == match.DecisionAutoApply && mode == matchingAuto {
		if _, err := l.applyEntry(ctx, entry, &payload, entry.BestMBID, "", true); err != nil {
			// A failed apply leaves the entry pending for a person; the
			// evidence is stored either way.
			l.log.Warn("auto apply failed; leaving entry for review", "entry", entry.ID, "err", err)
		}
	}
	l.notifyReview(ctx, entry.ID, entry.UploadedBy)
	l.notifyReviewReady(ctx, entry.ID)
	return nil
}

// candidateDoc flattens a scored match for storage, remapping track
// indexes from the clustered unit back to payload order.
func candidateDoc(m *match.Match, unit match.Unit, indexOf map[string]int) reviewCandidateDoc {
	doc := reviewCandidateDoc{
		MBID:             m.Release.MBID,
		ReleaseGroupMBID: m.Release.ReleaseGroupMBID,
		Title:            m.Release.Title,
		Artist:           m.Release.Artist,
		Year:             m.Release.Year,
		MediaCount:       m.Release.Media,
		TrackCount:       len(m.Release.Tracks),
		Country:          m.Release.Country,
		Label:            m.Release.Label,
		CatalogNumber:    m.Release.CatalogNumber,
		Compilation:      m.Release.Compilation,
		SimilarityPct:    m.Similarity() * 100,
	}
	remap := func(unitIdx int) int {
		t := unit.Tracks[unitIdx]
		if i, ok := indexOf[t.PID+"\x00"+t.Path]; ok {
			return i
		}
		return unitIdx
	}
	for _, c := range m.Components {
		doc.Components = append(doc.Components, reviewComponentDoc{Name: c.Name, Distance: c.Distance, Weight: c.Weight})
	}
	for _, p := range m.Pairings {
		rt := m.Release.Tracks[p.ReleaseIndex]
		doc.Pairings = append(doc.Pairings, reviewPairingDoc{
			TrackIndex:    remap(p.TrackIndex),
			Position:      rt.Position,
			Disc:          rt.Disc,
			Title:         rt.Title,
			Artist:        rt.Artist,
			DurationMS:    int64(rt.DurationSec * 1000),
			RecordingMBID: rt.RecordingMBID,
			Distance:      p.Distance,
		})
	}
	for _, j := range m.MissingIndexes {
		doc.MissingTitles = append(doc.MissingTitles, m.Release.Tracks[j].Title)
	}
	for _, i := range m.ExtraIndexes {
		doc.ExtraIndexes = append(doc.ExtraIndexes, remap(i))
	}
	return doc
}

// applyEntry applies one candidate's metadata to the unit. For import
// entries the staged file enters the library first. Returns non-fatal
// warnings; the entry is decided on return.
func (l *Library) applyEntry(ctx context.Context, entry *wdb.ReviewEntry, payload *reviewPayload, candidateMBID, decidedBy string, auto bool) ([]string, error) {
	var cand *reviewCandidateDoc
	for i := range payload.Candidates {
		if payload.Candidates[i].MBID == candidateMBID {
			cand = &payload.Candidates[i]
			break
		}
	}
	if cand == nil {
		return nil, errInvalid("no such candidate on this entry")
	}

	var warnings []string
	if entry.Kind == reviewKindImport {
		w, err := l.importEntryFiles(ctx, entry, payload)
		warnings = append(warnings, w...)
		if err != nil {
			return warnings, err
		}
	}

	snapshot := reviewSnapshot{Items: map[string]map[string]string{}}
	// One edit per item, first-seen order. EditItemsFields rejects a duplicate
	// pid, so if two pairings resolve to the same file the last one wins, the
	// same outcome the old per-item last-write-wins loop produced.
	editByPID := make(map[model.PID]map[string]string, len(cand.Pairings))
	var order []model.PID
	for _, p := range cand.Pairings {
		doc := payload.Tracks[p.TrackIndex]
		if doc.PID == "" {
			warnings = append(warnings, fmt.Sprintf("%s: not in the library; skipped", filepath.Base(doc.Path)))
			continue
		}
		pid := model.PID(doc.PID)
		it, err := l.lib.Get(ctx, pid)
		if err != nil {
			warnings = append(warnings, fmt.Sprintf("%s: %v", doc.PID, err))
			continue
		}
		prior := map[string]string{
			"title": it.Title, "artist": it.Artist, "album_artist": it.AlbumArtist,
			"album": it.Album, "year": zeroableInt(it.Year), "track_no": zeroableInt(it.TrackNo),
			"disc_no": zeroableInt(it.DiscNo), "mbid": "",
		}
		edits := map[string]string{
			"album":        cand.Title,
			"album_artist": cand.Artist,
			"track_no":     strconv.Itoa(p.Position),
			"title":        p.Title,
		}
		if p.Title == "" {
			delete(edits, "title")
		}
		if cand.Year > 0 {
			edits["year"] = strconv.Itoa(cand.Year)
		}
		if p.Disc > 0 {
			edits["disc_no"] = strconv.Itoa(p.Disc)
		}
		if isUUID(p.RecordingMBID) {
			// The store validates mbid as a UUID; a malformed id from a
			// provider is dropped rather than sinking the whole apply.
			edits["mbid"] = p.RecordingMBID
		}
		if p.Artist != "" {
			edits["artist"] = p.Artist
		} else if cand.Compilation {
			// A compilation pairing without its own artist keeps the
			// file's artist tag.
		} else {
			edits["artist"] = cand.Artist
		}
		if cand.Compilation {
			edits["compilation"] = "true"
			// Record the prior flag so revert restores and unlocks it; without
			// this the apply leaves a locked compilation field the revert cannot
			// reach, and scans and enrichment then refuse to change it.
			prior["compilation"] = strconv.FormatBool(it.Compilation)
		}
		if _, seen := editByPID[pid]; !seen {
			order = append(order, pid)
		}
		editByPID[pid] = edits
		snapshot.Items[doc.PID] = prior
	}

	// Apply the whole unit in one atomic catalog batch, so a mid-unit failure
	// rolls the lot back instead of leaving earlier tracks edited under a
	// returned error. Catalog-only (no WriteBack), so no on-disk tag sync runs.
	if len(order) > 0 {
		batch := make([]model.ItemFieldEdit, 0, len(order))
		for _, pid := range order {
			batch = append(batch, model.ItemFieldEdit{ItemPID: pid, Fields: editByPID[pid]})
		}
		if _, err := l.lib.EditItemsFields(ctx, batch, waxbin.EditOptions{Lock: true, Force: true}); err != nil {
			return warnings, classify(err)
		}
	}

	rawSnap, err := json.Marshal(snapshot)
	if err != nil {
		return warnings, &Error{Kind: KindInternal, Err: err}
	}
	rawPayload, err := json.Marshal(*payload)
	if err != nil {
		return warnings, &Error{Kind: KindInternal, Err: err}
	}
	entry.Payload = string(rawPayload)
	entry.Snapshot = string(rawSnap)
	entry.AppliedMBID = cand.MBID
	entry.Auto = auto
	entry.Status = reviewApplied
	if auto {
		entry.Status = reviewAutoApplied
	}
	entry.DecidedAtNS = time.Now().UnixNano()
	entry.DecidedBy = decidedBy
	entry.BestMBID = cand.MBID
	entry.BestTitle = cand.Title
	entry.BestArtist = cand.Artist
	entry.BestYear = cand.Year
	entry.BestSimilarity = cand.SimilarityPct
	if err := l.db.UpdateReviewEntry(ctx, *entry); err != nil {
		return warnings, &Error{Kind: KindInternal, Err: err}
	}
	return warnings, nil
}

// revertEntry restores the snapshot an apply took and unlocks the
// fields the apply locked.
func (l *Library) revertEntry(ctx context.Context, entry *wdb.ReviewEntry, decidedBy string) error {
	if entry.Status != reviewApplied && entry.Status != reviewAutoApplied {
		return &Error{Kind: KindConflict, Msg: "only applied entries revert"}
	}
	var snap reviewSnapshot
	if entry.Snapshot == "" || json.Unmarshal([]byte(entry.Snapshot), &snap) != nil || len(snap.Items) == 0 {
		return &Error{Kind: KindConflict, Msg: "the entry carries no snapshot to restore"}
	}
	batch := make([]model.ItemFieldEdit, 0, len(snap.Items))
	for pid, fields := range snap.Items {
		batch = append(batch, model.ItemFieldEdit{ItemPID: model.PID(pid), Fields: fields})
	}
	// Restore the whole unit atomically, mirroring the apply. Catalog-only
	// (no WriteBack, like the apply), so the batch does no on-disk tag sync
	// and reports no per-item write-back failures; revert surfaces only a
	// hard error, not the warnings the apply collects.
	if _, err := l.lib.EditItemsFields(ctx, batch, waxbin.EditOptions{Lock: false, Force: true}); err != nil {
		return classify(err)
	}
	for pid, fields := range snap.Items {
		names := make([]string, 0, len(fields))
		for f := range fields {
			names = append(names, f)
		}
		if err := l.lib.Unlock(ctx, model.PID(pid), names...); err != nil {
			l.log.Warn("unlocking reverted fields", "item", pid, "err", err)
		}
	}
	entry.Status = reviewReverted
	entry.DecidedAtNS = time.Now().UnixNano()
	entry.DecidedBy = decidedBy
	if err := l.db.UpdateReviewEntry(ctx, *entry); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	l.notifyReview(ctx, entry.ID, entry.UploadedBy)
	return nil
}

// isUUID reports the canonical 8-4-4-4-12 hex form.
func isUUID(s string) bool {
	if len(s) != 36 {
		return false
	}
	for i, r := range s {
		switch i {
		case 8, 13, 18, 23:
			if r != '-' {
				return false
			}
		default:
			hex := (r >= '0' && r <= '9') || (r >= 'a' && r <= 'f') || (r >= 'A' && r <= 'F')
			if !hex {
				return false
			}
		}
	}
	return true
}

func zeroableInt(n int) string {
	if n == 0 {
		return ""
	}
	return strconv.Itoa(n)
}

func firstNonEmpty(vals ...string) string {
	for _, v := range vals {
		if v != "" {
			return v
		}
	}
	return ""
}
