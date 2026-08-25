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

// reviewOverride is what a reviewer typed to search for in place of
// what the files claim. Data on the entry rather than a parameter of
// one run: identification rebuilds its query from the payload every
// time, so storing it here is what makes a retry after a provider
// failure search for the same thing.
type reviewOverride struct {
	Artist string `json:"artist,omitempty"`
	Album  string `json:"album,omitempty"`
	Title  string `json:"title,omitempty"`
}

// empty reports whether nothing was typed, which is how a cleared
// override is stored: as no override at all.
func (o reviewOverride) empty() bool {
	return o.Artist == "" && o.Album == "" && o.Title == ""
}

// reviewPayload is the entry's stored evidence.
type reviewPayload struct {
	Tracks     []reviewTrackDoc     `json:"tracks"`
	Candidates []reviewCandidateDoc `json:"candidates"`
	// IdentifyDeclined records that the submission asked not to be
	// identified, so a reader can tell an empty candidate list that was
	// never searched from one that was searched and found nothing.
	IdentifyDeclined bool `json:"identifyDeclined,omitempty"`
	// Override is what the last re-identify asked to search for.
	Override *reviewOverride `json:"override,omitempty"`
	// Suggested is what the matching parse read out of a loose
	// acquisition's source title, offered to the reviewer as a starting
	// point. A suggestion and nothing else: nothing here is written to
	// the files, and a stored Override supersedes it.
	Suggested *reviewOverride `json:"suggested,omitempty"`
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

// notifyIdentified announces one finished identification in whichever of
// its two terminal shapes it landed: waiting for a decision, or already
// filed. Emitted here, not at entry open, so the re-read sees an
// auto-apply that landed in between; scan and rematch stay silent.
func (l *Library) notifyIdentified(ctx context.Context, entryID string) {
	entry, err := l.db.ReviewEntryByID(ctx, entryID)
	if err != nil {
		return
	}
	if entry.Status != reviewPending && entry.Status != reviewAutoApplied {
		return
	}
	if entry.Origin != reviewOriginUpload && entry.Origin != reviewOriginAcquire {
		return
	}
	recipients := l.reviewRecipients(ctx, entry.UploadedBy)
	if entry.Status == reviewPending {
		l.EmitNotification(ctx, "review-ready", "Ready for review",
			entryWhat(entry.Artist, entry.Title, entry.TrackCount)+
				" finished identification and waits for a decision.", recipients)
		return
	}
	// Best* rather than the entry's own tags: an applied entry names what
	// it was identified *as*, which is what landed in the library.
	l.EmitNotification(ctx, "import-completed", "Import finished",
		entryWhat(entry.BestArtist, entry.BestTitle, entry.TrackCount)+
			" was identified and added to the library.", recipients)
	seen := map[string]bool{}
	for _, uid := range recipients {
		if uid == "" || seen[uid] {
			continue
		}
		seen[uid] = true
		l.emitUserEvent(ctx, uid, eventImportCompleted, entry.ID)
	}
}

// entryWhat names an entry for a notification body.
func entryWhat(artist, title string, tracks int) string {
	if title == "" {
		return fmt.Sprintf("%d files", tracks)
	}
	if artist != "" {
		return artist + ": " + title
	}
	return title
}

// openReviewEntry stores a pending entry and, unless the submission
// declined identification, queues it for the identify worker. A
// declined entry opens with no candidates and identification never
// started: the queue stays the audit trail and one decision imports
// the files with the tags they arrived with.
func (l *Library) openReviewEntry(ctx context.Context, e wdb.ReviewEntry, payload reviewPayload, identify bool) (string, error) {
	if e.ID == "" {
		e.ID = newReviewID()
	}
	payload.IdentifyDeclined = !identify
	raw, err := json.Marshal(payload)
	if err != nil {
		return "", &Error{Kind: KindInternal, Err: err}
	}
	e.Status = reviewPending
	e.Identifying = identify
	e.Payload = string(raw)
	e.TrackCount = len(payload.Tracks)
	e.CreatedAtNS = time.Now().UnixNano()
	if err := l.db.InsertReviewEntry(ctx, e); err != nil {
		return "", &Error{Kind: KindInternal, Err: err}
	}
	if identify {
		if err := l.db.EnqueueMatch(ctx, e.ID); err != nil {
			return "", &Error{Kind: KindInternal, Err: err}
		}
		l.matchWakeup()
	}
	// Only when a person is actually being awaited. An entry that
	// declined identification is on its way to importing itself with the
	// tags it arrived with, so a bell saying "the review queue changed"
	// asks somebody to look at a queue they have nothing to do in -
	// which is what an as-is upload used to ring. If that import stalls,
	// importDeclinedEntry rings then, when it is true.
	//
	// The scan origin is excluded for a different reason: batching, not
	// relevance. A scan that discovers a library opens thousands of
	// entries, and one event per entry per administrator is a flood that
	// arrives faster than the pacer behind it can spend. The sweeper
	// raises one marker per pass instead, once it knows how many it
	// opened.
	if identify && e.Origin != reviewOriginScan {
		l.notifyReview(ctx, e.ID, e.UploadedBy)
	}
	return e.ID, nil
}

// resolveIdentify picks a submission's identification choice: what it
// asked for, or the account's own default when it asked for nothing.
// Resolved once, when the submission is accepted, so a preference
// changed while bytes are still moving does not move what is moving.
func (l *Library) resolveIdentify(ctx context.Context, userID string, asked *bool) bool {
	if asked != nil {
		return *asked
	}
	return !l.PrefsForUser(ctx, userID).IdentifyOptOut
}

// importDeclinedEntry files a declined submission as-is, as the button
// would; an import that refuses leaves it pending for a person. Called
// after the caller links its upload rows, which settling keys on.
//
// The review marker is raised here and only here, on the three paths
// that leave the entry pending. Two notification layers meet in this
// function and they are easy to mistake for each other: notifyReview
// fans a user-stream marker, which is the in-app bell, while
// notifyReviewReady and notifyImported go to the external provider
// system. The stall paths already sent the external one and never rang
// the bell; the success path rang the bell for a queue with nothing in
// it. Both are now the other way round.
func (l *Library) importDeclinedEntry(ctx context.Context, entryID string) {
	entry, err := l.db.ReviewEntryByID(ctx, entryID)
	if err != nil {
		l.log.Warn("reading a declined entry to import", "entry", entryID, "err", err)
		return
	}
	if entry.Status != reviewPending || entry.Kind != reviewKindImport {
		return
	}
	var payload reviewPayload
	if err := json.Unmarshal([]byte(entry.Payload), &payload); err != nil {
		l.log.Warn("decoding a declined entry", "entry", entryID, "err", err)
		return
	}
	if !payload.IdentifyDeclined {
		return
	}

	// Declining is a statement about metadata, not consent to a second
	// copy - and importing is one-way, so the duplicate warning would
	// stop being actionable.
	if l.entryHasFlaggedDuplicate(ctx, entryID) {
		l.log.Info("a declined submission waits for review: it duplicates something", "entry", entryID)
		l.notifyReviewReady(ctx, &entry)
		l.notifyReview(ctx, entry.ID, entry.UploadedBy)
		return
	}

	// The same gate the decision surface applies: a library nothing may
	// be written to leaves the entry pending rather than half-importing.
	bareLib := ""
	if prefix, pid, ok := parseAPIPID(entry.LibraryPID); ok && prefix == PrefixLibrary {
		bareLib = string(pid)
	}
	if err := l.CheckWritable(ctx, bareLib); err != nil {
		l.log.Info("a declined submission waits for review", "entry", entryID, "err", err)
		l.notifyReviewReady(ctx, &entry)
		l.notifyReview(ctx, entry.ID, entry.UploadedBy)
		return
	}

	warnings, err := l.importEntryFiles(ctx, &entry, &payload)
	for _, w := range warnings {
		l.log.Info("importing a declined submission", "entry", entryID, "warning", w)
	}
	if err != nil {
		l.log.Warn("a declined submission could not import; it waits for review",
			"entry", entryID, "err", err)
		l.notifyReviewReady(ctx, &entry)
		l.notifyReview(ctx, entry.ID, entry.UploadedBy)
		return
	}
	entry.Payload = marshalJSON(payload)
	entry.Status = reviewAsIs
	entry.DecidedAtNS = time.Now().UnixNano()
	// The uploader decided it, at submission time. Naming them rather
	// than leaving it blank keeps "who did this" answerable, and blank
	// is what an auto-apply uses.
	entry.DecidedBy = entry.UploadedBy
	if err := l.db.UpdateReviewEntry(ctx, entry); err != nil {
		l.log.Warn("marking a declined submission imported", "entry", entryID, "err", err)
		return
	}
	l.notifyImported(ctx, &entry)
}

// entryHasFlaggedDuplicate reports whether any session behind an entry
// arrived carrying a duplicate warning.
func (l *Library) entryHasFlaggedDuplicate(ctx context.Context, entryID string) bool {
	rows, err := l.db.ListUploadsByReviewEntry(ctx, entryID)
	if err != nil {
		// Unreadable is treated as flagged: stopping for a person is
		// the recoverable outcome, importing twice is not.
		l.log.Warn("checking a declined entry for duplicates", "entry", entryID, "err", err)
		return true
	}
	for _, r := range rows {
		if r.DuplicatePID != "" {
			return true
		}
	}
	return false
}

// notifyReviewReady tells the administrators and the uploader that an
// entry is waiting for a decision.
func (l *Library) notifyReviewReady(ctx context.Context, entry *wdb.ReviewEntry) {
	l.EmitNotification(ctx, "review-ready", "Ready for review",
		entryWhat(entry.Artist, entry.Title, entry.TrackCount)+
			" could not be imported on its own and waits for a decision.",
		l.reviewRecipients(ctx, entry.UploadedBy))
}

// notifyImported announces files that reached the library with no
// decision asked for.
func (l *Library) notifyImported(ctx context.Context, entry *wdb.ReviewEntry) {
	recipients := l.reviewRecipients(ctx, entry.UploadedBy)
	l.EmitNotification(ctx, "import-completed", "Import finished",
		entryWhat(entry.Artist, entry.Title, entry.TrackCount)+
			" was added to the library with the tags it arrived with.", recipients)
	seen := map[string]bool{}
	for _, uid := range recipients {
		if uid == "" || seen[uid] {
			continue
		}
		seen[uid] = true
		l.emitUserEvent(ctx, uid, eventImportCompleted, entry.ID)
	}
}

// reviewRecipients is every administrator plus the entry's uploader.
func (l *Library) reviewRecipients(ctx context.Context, uploadedBy string) []string {
	recipients := []string{}
	if admins, err := l.db.EnabledAdminIDs(ctx); err == nil {
		recipients = append(recipients, admins...)
	} else {
		l.log.Warn("listing admins for a review notification", "err", err)
	}
	if uploadedBy != "" {
		recipients = append(recipients, uploadedBy)
	}
	return recipients
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
	libraryPID := string(it.LibraryPID)
	entry := wdb.ReviewEntry{
		Kind:       reviewKindMatch,
		MediaType:  mediaTypeForKind(it.Kind),
		Origin:     reviewOriginRematch,
		LibraryPID: libraryPID,
		Title:      firstNonEmpty(it.Album, it.Title),
		Artist:     firstNonEmpty(it.AlbumArtist, it.Artist),
	}
	// A rematch is a request to identify; there is nothing else it does.
	return l.openReviewEntry(ctx, entry, reviewPayload{Tracks: unit}, true)
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

// LibrarySinglesAutoApply reads whether a library lets confident
// one-file units apply themselves (default off: a lone track picking
// among near-tied releases is a wrong-release risk a person accepts
// deliberately). Stored as "true"/absent like the read-only flag; the
// key normalization matches LibraryMatchingMode.
func (l *Library) LibrarySinglesAutoApply(ctx context.Context, libraryPID string) bool {
	if prefix, bare, ok := parseAPIPID(libraryPID); ok && prefix == PrefixLibrary {
		libraryPID = string(bare)
	}
	v, err := l.db.SettingGet(ctx, "matching-singles:"+libraryPID)
	return err == nil && v == "true"
}

// singlesAutoApplyFor resolves the singles switch for one entry. An
// upload or acquisition carries no target library until import routing
// places it, so an empty pid falls back to the one library that could
// hold the entry's media - the unambiguous destination on the common
// single-library server. More than one candidate stays off: guessing
// which library's opt-in to honor would auto-apply under a grant
// nobody made for that destination.
func (l *Library) singlesAutoApplyFor(ctx context.Context, entry *wdb.ReviewEntry) bool {
	if entry.LibraryPID != "" {
		return l.LibrarySinglesAutoApply(ctx, entry.LibraryPID)
	}
	kind, ok := kindForMediaType(entry.MediaType)
	if !ok {
		return false
	}
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return false
	}
	var only *model.Library
	for _, lib := range libs {
		if lib.Mode == model.ModePodcast {
			continue
		}
		if lib.Media != "" && !lib.Media.Accepts(kind) {
			continue
		}
		if only != nil {
			return false
		}
		only = lib
	}
	return only != nil && l.LibrarySinglesAutoApply(ctx, string(only.PID))
}

// LibraryMatching is a library's matching behavior for the API.
type LibraryMatching struct {
	Mode             string
	SinglesAutoApply bool
}

// LibraryMatchingFor reads a library's matching behavior for the API,
// validating that the library exists first so an unknown or malformed
// pid answers not-found rather than a fabricated default. The pipeline
// reads the mode through LibraryMatchingMode, which never errors.
func (l *Library) LibraryMatchingFor(ctx context.Context, uc *UserCtx, apiLibraryPID string) (LibraryMatching, error) {
	if !uc.Admin {
		return LibraryMatching{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	prefix, pid, ok := parseAPIPID(apiLibraryPID)
	if !ok || prefix != PrefixLibrary {
		return LibraryMatching{}, errNotFound("no such library")
	}
	if _, err := l.libraryByPID(ctx, pid); err != nil {
		return LibraryMatching{}, err
	}
	return LibraryMatching{
		Mode:             l.LibraryMatchingMode(ctx, string(pid)),
		SinglesAutoApply: l.LibrarySinglesAutoApply(ctx, string(pid)),
	}, nil
}

// SetLibraryMatching stores a library's matching behavior whole: the
// PUT is a full replace, so both fields land on every write.
func (l *Library) SetLibraryMatching(ctx context.Context, uc *UserCtx, apiLibraryPID string, matching LibraryMatching) error {
	if !uc.Admin {
		return &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	switch matching.Mode {
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
	// Singles first, deliberately: the flag is inert unless the mode is
	// auto, so if the second write fails (or a drain lands between
	// them) every intermediate state behaves like one the caller asked
	// for. Mode-first could flip an as-is library to auto and stop.
	if matching.SinglesAutoApply {
		if err := l.db.SettingSet(ctx, "matching-singles:"+string(pid), "true", time.Now().UnixNano()); err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
	} else if err := l.db.SettingDelete(ctx, "matching-singles:"+string(pid)); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.SettingSet(ctx, "matching:"+string(pid), matching.Mode, time.Now().UnixNano()); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	l.Audit(ctx, uc, "library.matching",
		AuditTarget{Kind: "library", PID: apiLibraryPID},
		map[string]any{"mode": matching.Mode, "singlesAutoApply": matching.SinglesAutoApply})
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
		if errors.Is(err, errIdentifyStale) {
			// One statement, so the job is never briefly absent: an
			// entry marked identifying with nothing queued never
			// recovers.
			if rerr := l.db.RearmMatch(ctx, row.ID); rerr != nil {
				l.log.Warn("rearming a stale match", "entry", entry.ID, "err", rerr)
			}
			return true
		}
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
	l.notifyIdentified(ctx, entry.ID)
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
		l.notifyIdentified(ctx, entry.ID)
		return nil
	}

	tracks := l.matchTracks(ctx, payload.Tracks)
	// Persist computed fingerprints so a retry does not respawn fpcalc.
	for i := range tracks {
		payload.Tracks[i].Fingerprint = tracks[i].Fingerprint
	}
	// The row as it was leased. The write at the end is conditional on
	// it, so a decision or a re-identify landing mid-run is not
	// overwritten by this one.
	wasPayload := entry.Payload
	applyQueryOverride(tracks, payload.Override)
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
	// Cleared first: a re-run that finds nothing must not leave the
	// previous best advertised, which Approve would then reach for.
	entry.BestMBID, entry.BestTitle, entry.BestArtist = "", "", ""
	entry.BestYear, entry.BestSimilarity = 0, 0
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
	// Conditional on the row this run was handed: the entry stays
	// editable while the engine works, so a full-row write would undo a
	// decision or drop a typed search. A miss re-arms instead.
	entry.Payload = string(raw)
	wrote, err := l.db.UpdateIdentifyResult(ctx, *entry, wasPayload)
	if err != nil {
		return err
	}
	if !wrote {
		return errIdentifyStale
	}

	// Never on the reviewer's own guess: an override is what the scorer
	// measures, so the distance collapses and a locked auto-apply would
	// write the guess into the catalog unseen.
	if payload.Override != nil && proposal.Decision == match.DecisionAutoApply {
		l.log.Info("auto-apply withheld: the query was typed by a reviewer", "entry", entry.ID)
	}
	autoApply := payload.Override == nil && proposal.Decision == match.DecisionAutoApply && mode == matchingAuto
	// A one-file unit auto-applies only where the library opted in: a
	// lone track picking among near-tied releases is a wrong-release
	// risk, so the default queues every single for a person even when
	// the engine is confident. Checked last so the setting is only read
	// when it would decide anything.
	if autoApply && len(unit.Tracks) == 1 && !l.singlesAutoApplyFor(ctx, entry) {
		autoApply = false
		l.log.Info("auto-apply withheld: singles auto-apply is off for the destination library", "entry", entry.ID)
	}
	if autoApply {
		if _, err := l.applyEntry(ctx, entry, &payload, entry.BestMBID, "", true); err != nil {
			// A failed apply leaves the entry pending for a person; the
			// evidence is stored either way.
			l.log.Warn("auto apply failed; leaving entry for review", "entry", entry.ID, "err", err)
		}
	}
	l.notifyReview(ctx, entry.ID, entry.UploadedBy)
	l.notifyIdentified(ctx, entry.ID)
	return nil
}

// errIdentifyStale says the entry was decided or re-queried while the
// engine worked, so the drain re-arms rather than failing the job.
var errIdentifyStale = errors.New("the entry changed while it was being identified")

// applyQueryOverride carries typed values two ways: a complete Query
// for the recording search (half-filled, it re-derives and splits a
// typed title into an artist), and unit-level tags for the album search
// and scoring. Per-track ARTIST and TITLE are left alone - scoring
// pairs on both - and the maps are copied, since the payload is
// re-marshalled after the run.
func applyQueryOverride(tracks []match.Track, o *reviewOverride) {
	if o == nil || o.empty() {
		return
	}
	single := len(tracks) == 1
	for i := range tracks {
		derivedArtist, derivedTitle, _ := match.SuggestedQuery(tracks[i])
		tags := make(map[string]string, len(tracks[i].Tags)+2)
		for k, v := range tracks[i].Tags {
			tags[k] = v
		}
		if o.Artist != "" {
			tags["ALBUMARTIST"] = o.Artist
		}
		if o.Album != "" {
			tags["ALBUM"] = o.Album
		}
		if o.Title != "" && single {
			tags["TITLE"] = o.Title
		}
		tracks[i].Tags = tags
		tracks[i].Query = &match.TrackQuery{
			Artist: firstNonEmpty(o.Artist, derivedArtist),
			Title:  firstNonEmpty(titleFor(o.Title, single), derivedTitle),
		}
	}
}

// titleFor drops a typed track title on a unit of several files, where
// it names none of them in particular.
func titleFor(typed string, single bool) string {
	if !single {
		return ""
	}
	return typed
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
		if _, err := l.lib.EditItemsFields(ctx, batch, waxbin.EditOptions{Lock: model.LockOn, Force: true}); err != nil {
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
	if _, err := l.lib.EditItemsFields(ctx, batch, waxbin.EditOptions{Lock: model.LockOff, Force: true}); err != nil {
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
