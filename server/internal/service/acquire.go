package service

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/colespringer/waxbin/fingerprint"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"
	waxlabel "github.com/colespringer/waxlabel"
	"github.com/oklog/ulid/v2"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/match"
)

// Acquisition: download audio from a source URL (a single video, or
// every entry of a playlist or channel) through an injected provider,
// stage the files exactly like uploads, and open review entries so the
// content flows through the same identify and review pipeline. The
// source's own metadata arrives embedded by the provider and the
// review decisions (approve, keep as is, mark unofficial) plus the
// uploader's item-scoped editing rights cover the long tail of content
// with no canonical release.

const taskTypeAcquire = "acquire"

// formatFetcher is the optional capability a source provider advertises when it
// can honor a preferred output format for a URL acquisition. The empty format
// means the provider's default (best-audio copy).
type formatFetcher interface {
	FetchFormat(ctx context.Context, req source.FetchRequest, w io.Writer, format string) (*source.FetchResult, error)
}

// acquireMaxItems bounds one acquisition; a channel's full archive is
// a subscription's job, not one task's.
const acquireMaxItems = 200

// acquireItem is one pending download within an acquisition. GUID is
// the source's own entry id (a video id) when the item came from an
// enumeration; it keys the playlist-sync map row, so a synced playlist
// can recognize the entry once its download settles.
type acquireItem struct {
	Title string
	URL   string
	GUID  string
}

// StartAcquisition queues an acquire task. Upload rights gate it, and
// the acquired bytes will count against the caller's upload quota. format
// is the caller's preferred output format ("" or "best" copies the
// source's highest-quality audio; "opus"/"mp3"/"m4a"/"flac" transcode).
// identify is the submission's identification choice, nil for the
// account default.
func (l *Library) StartAcquisition(ctx context.Context, uc *UserCtx, rawURL, mediaType, libraryPID, format string, identify *bool) (ToolTaskDTO, error) {
	if err := l.CheckWritable(ctx, ""); err != nil {
		return ToolTaskDTO{}, err
	}
	if err := l.requireUploader(uc); err != nil {
		return ToolTaskDTO{}, err
	}
	acquireFormat, ok := normalizeAcquireFormat(format)
	if !ok {
		return ToolTaskDTO{}, errInvalid("unknown acquisition format")
	}
	if len(l.sourceProviders) == 0 {
		return ToolTaskDTO{}, &Error{Kind: KindUnsupported, Msg: "no acquisition source is running; start the server with WAXDECK_YOUTUBE=true to acquire from URLs"}
	}
	parsed, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return ToolTaskDTO{}, errInvalid("url must be an http or https URL")
	}
	if err := l.guardAcquireHost(ctx, parsed.Hostname()); err != nil {
		return ToolTaskDTO{}, err
	}
	kind, ok := kindForMediaType(mediaType)
	if !ok {
		return ToolTaskDTO{}, errInvalid("unknown media type")
	}
	// The upload surfaces' own check, rather than a second copy of it:
	// this one used to stop at visibility and let an acquisition name a
	// read-only library the settle would then refuse, which targeted
	// acquisitions make ordinary rather than exotic.
	if err := l.validateUploadTargetLibrary(ctx, uc, libraryPID); err != nil {
		return ToolTaskDTO{}, err
	}
	// Acquired files are placed into the library, which the catalog
	// only does for a managed root. Fail here, before spending a
	// download, rather than staging bytes that would quarantine.
	if kind != model.KindEpisode {
		has, err := l.hasManagedDestination(ctx, uc, kind)
		if err != nil {
			return ToolTaskDTO{}, err
		}
		if !has {
			return ToolTaskDTO{}, errInvalid("no managed " + mediaType +
				" library to receive the files; an administrator must mark a library root managed (WAXDECK_MANAGED_ROOTS)")
		}
	}
	return l.insertToolTask(ctx, uc, taskTypeAcquire, "", toolTaskParams{
		URL:        parsed.String(),
		MediaType:  mediaType,
		LibraryPID: libraryPID,
		Format:     acquireFormat,
		// Stored as the decline rather than the choice, so a task queued
		// before this field existed reads as "identify" instead of
		// silently opting itself out.
		IdentifyDeclined: !l.resolveIdentify(ctx, uc.ID, identify),
	})
}

// normalizeAcquireFormat validates an acquisition format preference,
// returning the canonical lowercase form. "" and "best" both mean the
// lossless copy path and normalize to "".
func normalizeAcquireFormat(format string) (string, bool) {
	switch strings.ToLower(strings.TrimSpace(format)) {
	case "", "best":
		return "", true
	case "opus", "mp3", "m4a", "flac":
		return strings.ToLower(strings.TrimSpace(format)), true
	}
	return "", false
}

// runAcquire executes one leased acquire task: enumerate, fetch each
// item into upload staging, then open review entries per album unit.
// A failure after files already staged finalizes entries for what
// arrived and fails terminally, so a retry never downloads the same
// bytes twice; only a failure before any byte moved stays transient.
func (l *Library) runAcquire(ctx context.Context, t *wdb.ToolTask, p toolTaskParams) ([]string, error) {
	user, err := l.db.UserByID(ctx, t.UserID)
	if err != nil {
		return nil, fmt.Errorf("%w: the acquiring account is gone", errToolPermanent)
	}
	if !user.UploadEnabled && !hasRole(user.Roles, "admin") {
		return nil, fmt.Errorf("%w: upload rights were revoked", errToolPermanent)
	}

	provider, items, err := l.acquireList(ctx, p.URL)
	if err != nil {
		if kindIsPermanent(KindOf(classify(err))) {
			return nil, fmt.Errorf("%w: %v", errToolPermanent, err)
		}
		return nil, err
	}
	if len(items) == 0 {
		return nil, fmt.Errorf("%w: the source lists no downloadable audio", errToolPermanent)
	}
	if len(items) > acquireMaxItems {
		l.log.Info("acquisition truncated", "task", t.ID, "listed", len(items), "cap", acquireMaxItems)
		items = items[:acquireMaxItems]
	}

	entryIDs, staged, _, fetchErr, entriesErr := l.fetchAcquireBatch(ctx, t, p, provider, items, user, 90, false)
	if entriesErr != nil {
		// The files staged; opening their review entries did not. Plain
		// rather than wrapped permanent, matching the pre-extraction
		// shape: a database that would not answer clears without the
		// caller changing anything, and the already-landed guard keeps
		// a retry from re-importing what staged.
		return nil, entriesErr
	}
	if staged == 0 {
		if fetchErr != nil {
			if errors.Is(fetchErr, errToolPermanent) || kindIsPermanent(KindOf(classify(fetchErr))) {
				return nil, fmt.Errorf("%w: %v", errToolPermanent, fetchErr)
			}
			return nil, fetchErr
		}
		return nil, fmt.Errorf("%w: nothing was downloaded", errToolPermanent)
	}
	if fetchErr != nil {
		// Some files arrived and their entries are open; the task still
		// fails loudly so the truncation is visible, and a retry will
		// not re-download what already staged.
		return nil, fmt.Errorf("%w: %d of %d items staged before: %v",
			errToolPermanent, staged, len(items), fetchErr)
	}
	return entryIDs, nil
}

// fetchAcquireBatch stages each item with the per-item quota and room
// checks, reporting task progress up to progressCap percent, and opens
// review entries for whatever arrived - even when a fetch failed, so a
// retry never downloads the same bytes twice. skipItemErrors is the
// playlist-sync posture: one entry's failed fetch is skipped and
// counted rather than cutting the batch, so an undeliverable video
// never starves the entries behind it; the systemic checks (context,
// quota, staging room) still stop the batch either way. Returns the
// opened entry ids, how many files staged, how many items were skipped
// over their own errors, the batch-stopping fetch error, and the
// entry-opening error - separately, because the two mean different
// things to the caller's retry policy.
func (l *Library) fetchAcquireBatch(ctx context.Context, t *wdb.ToolTask, p toolTaskParams, provider source.Provider, items []acquireItem, user *wdb.User, progressCap float64, skipItemErrors bool) (entryIDs []string, staged, skipped int, fetchErr, entriesErr error) {
	var (
		docs      []reviewTrackDoc
		rowByPath = map[string]string{}
	)
	for i, item := range items {
		if ctx.Err() != nil {
			fetchErr = ctx.Err()
			break
		}
		if user.UploadQuotaBytes > 0 {
			used, err := l.db.UploadBytesInUse(ctx, t.UserID)
			if err == nil && used >= user.UploadQuotaBytes {
				fetchErr = fmt.Errorf("%w: the pending-upload limit is full (%d bytes waiting for review)", errToolPermanent, user.UploadQuotaBytes)
				break
			}
		}
		// The same volume an upload session is checked against, asked
		// the only question this path can answer: an acquisition never
		// declares a size, so what it can refuse is starting an item
		// with no room left at all. Raised as it is rather than wrapped
		// permanent: a full disk and a database that would not answer
		// are both conditions that clear without the caller changing
		// anything, which is what a retryable task failure means.
		if err := l.checkStagingRoom(ctx, 0); err != nil {
			fetchErr = err
			break
		}
		doc, uploadID, err := l.fetchAcquireItem(ctx, provider, t, p, item, i)
		if err != nil {
			if skipItemErrors {
				skipped++
				l.log.Warn("skipping undeliverable acquisition item", "item", item.URL, "err", err)
				continue
			}
			fetchErr = err
			break
		}
		docs = append(docs, doc)
		rowByPath[doc.Path] = uploadID
		t.ProgressPct = float64(i+1) / float64(len(items)) * progressCap
		if uerr := l.db.UpdateToolTask(ctx, *t); uerr == nil {
			l.notifyToolTask(ctx, t.ID)
		}
	}
	if len(docs) == 0 {
		return nil, 0, skipped, fetchErr, nil
	}
	entryIDs, entriesErr = l.openAcquireEntries(ctx, t, p, docs, rowByPath)
	if entriesErr != nil && fetchErr != nil {
		// Both halves failed; neither may vanish into the other.
		l.log.Warn("acquisition batch failed twice over", "fetch", fetchErr, "entries", entriesErr)
	}
	return entryIDs, len(docs), skipped, fetchErr, entriesErr
}

// guardAcquireHost refuses source URLs pointing at private, loopback,
// link-local, or otherwise internal addresses, the same posture every
// other user-pointed fetch in the server takes. Today's one provider
// never dials the raw host at all (it extracts platform ids and talks
// to the platform's own endpoints), so this is defense in depth for
// the generic provider port, not the load-bearing control; a resolve
// check cannot stop DNS rebinding, which only a per-dial guard inside
// a provider's own client can. The private-feed-hosts flag opts LAN
// sources back in, matching the feed surface.
func (l *Library) guardAcquireHost(ctx context.Context, host string) error {
	if l.allowPrivateFeedHosts {
		return nil
	}
	addrs, err := net.DefaultResolver.LookupIPAddr(ctx, host)
	if err != nil {
		return errInvalid("the url's host does not resolve")
	}
	for _, a := range addrs {
		ip := a.IP
		if ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() ||
			ip.IsLinkLocalMulticast() || ip.IsUnspecified() || ip.IsMulticast() {
			return errInvalid("the url points at a private or internal address")
		}
	}
	return nil
}

// hasManagedDestination reports whether a managed library the caller
// can see accepts the given item kind, which is the precondition for
// importing an acquired or uploaded file (the catalog places files
// only into managed roots). Podcast episodes ingest into the internal
// podcast library and are not checked here.
func (l *Library) hasManagedDestination(ctx context.Context, uc *UserCtx, kind model.Kind) (bool, error) {
	roots := l.libraryRoots()
	managed := make(map[string]bool, len(roots))
	for _, r := range roots {
		if r.Managed {
			managed[cleanRootPath(r.Path)] = true
		}
	}
	if len(managed) == 0 {
		return false, nil
	}
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return false, classify(err)
	}
	for _, lib := range libs {
		if lib.DisplayRoot == "" || !managed[cleanRootPath(lib.DisplayRoot)] {
			continue
		}
		if lib.Media != "" && !lib.Media.Accepts(kind) {
			continue
		}
		if !uc.AllLibraries && !uc.Libraries[string(lib.PID)] {
			continue
		}
		return true, nil
	}
	return false, nil
}

// cleanRootPath normalizes a root path for comparison across the
// config and catalog spellings.
func cleanRootPath(p string) string {
	return strings.TrimSuffix(filepath.Clean(p), string(filepath.Separator))
}

// kindIsPermanent classifies service error kinds retrying cannot fix.
func kindIsPermanent(k ErrorKind) bool {
	switch k {
	case KindInvalid, KindNotFound, KindUnsupported, KindFormat, KindQuota:
		return true
	default:
		return false
	}
}

// acquireList resolves the URL to its download list: a playlist or
// channel enumerates, anything else is a single item for the first
// provider that will fetch it.
func (l *Library) acquireList(ctx context.Context, rawURL string) (source.Provider, []acquireItem, error) {
	var firstErr error
	for _, p := range l.sourceProviders {
		en, err := p.Enumerate(ctx, source.Request{URL: rawURL})
		if err != nil {
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		if en.Feed == nil {
			continue
		}
		items := make([]acquireItem, 0, len(en.Feed.Episodes))
		for _, ep := range en.Feed.Episodes {
			if ep.EnclosureURL == "" {
				continue
			}
			items = append(items, acquireItem{Title: ep.Title, URL: ep.EnclosureURL, GUID: ep.GUID})
		}
		return p, items, nil
	}
	// Not a playlist or channel any provider recognizes: treat it as a
	// single item and let the first provider's fetch decide.
	if len(l.sourceProviders) > 0 {
		return l.sourceProviders[0], []acquireItem{{URL: rawURL}}, nil
	}
	if firstErr != nil {
		return nil, nil, firstErr
	}
	return nil, nil, errors.New("no acquisition source is running")
}

// fetchAcquireItem downloads one item into upload staging with the
// crash-safe write discipline and records its upload session.
func (l *Library) fetchAcquireItem(ctx context.Context, provider source.Provider, t *wdb.ToolTask, p toolTaskParams, item acquireItem, index int) (reviewTrackDoc, string, error) {
	uploadID := "up-" + ulid.Make().String()
	dir := filepath.Join(l.stagingDir, uploadID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return reviewTrackDoc{}, "", err
	}
	tmp := filepath.Join(dir, "download.part")
	f, err := os.Create(tmp)
	if err != nil {
		return reviewTrackDoc{}, "", err
	}
	// WaxDeck drives the acquisition fetch directly, not through the WaxBin
	// facade, so a format preference rides a WaxDeck-owned capability rather than
	// the source.FetchRequest port. A provider that does not advertise it (or an
	// empty preference) gets the default best-audio copy.
	freq := source.FetchRequest{URL: item.URL}
	var res *source.FetchResult
	if ff, ok := provider.(formatFetcher); ok && p.Format != "" {
		res, err = ff.FetchFormat(ctx, freq, f, p.Format)
	} else {
		res, err = provider.Fetch(ctx, freq, f)
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err == nil {
		if sf, serr := os.Open(tmp); serr == nil {
			_ = sf.Sync()
			sf.Close()
		}
	}
	if err != nil {
		_ = os.RemoveAll(dir)
		return reviewTrackDoc{}, "", err
	}

	name := acquireFileName(item.Title, res.ContentType, index)
	final := filepath.Join(dir, name)
	if err := os.Rename(tmp, final); err != nil {
		_ = os.RemoveAll(dir)
		return reviewTrackDoc{}, "", err
	}
	if d, err := os.Open(dir); err == nil {
		_ = d.Sync()
		d.Close()
	}

	doc := reviewTrackDoc{
		Path:  final,
		Title: firstNonEmpty(item.Title, strings.TrimSuffix(name, filepath.Ext(name))),
	}
	// The provider embeds the source metadata; read it back so the
	// identify pipeline and the review diff see what the file carries.
	if tags, err := parseFileTags(ctx, final); err == nil {
		doc.Tags = tags
		doc.Title = firstNonEmpty(tags["TITLE"], doc.Title)
		doc.Artist = tags["ARTIST"]
		doc.TrackNo = parseIntTag(tags["TRACKNUMBER"])
	}
	if l.fpcalcPath != "" {
		if fp, dur, err := fingerprint.ChromaprintCompressed(ctx, l.fpcalcPath, final, 0); err == nil {
			doc.Fingerprint = fp
			doc.DurationMS = int64(dur) * 1000
		}
	}

	row := wdb.Upload{
		ID:            uploadID,
		UserID:        t.UserID,
		FileName:      name,
		SizeBytes:     res.Bytes,
		ReceivedBytes: res.Bytes,
		MediaType:     p.MediaType,
		LibraryPID:    p.LibraryPID,
		State:         uploadStaged,
		StagingPath:   final,
		// Carried even though this path opens its own entries: an unset
		// field writes 0, so the row would read "declined" later.
		Identify:    !p.IdentifyDeclined,
		CreatedAtNS: time.Now().UnixNano(),
		ExpiresAtNS: time.Now().Add(l.uploadRetention).UnixNano(),
	}
	if err := l.db.InsertUpload(ctx, row); err != nil {
		_ = os.RemoveAll(dir)
		return reviewTrackDoc{}, "", err
	}
	// Every enumerated download feeds the playlist-sync map, manual
	// acquisitions included: what a video became in the library is a
	// fact about the library, and a later binding over the same source
	// dedups against it instead of downloading the video again.
	if item.GUID != "" {
		if err := l.db.PutPlaylistSourceMapPending(ctx, string(provider.SourceType()), item.GUID, uploadID, time.Now().UnixNano()); err != nil {
			l.log.Warn("recording source map row", "entry", item.GUID, "err", err)
		}
	}
	l.emitUserEvent(ctx, t.UserID, eventUpload, uploadID)
	return doc, uploadID, nil
}

// suggestedQueryFor reads what the matcher would search for out of a
// loose acquisition's source title, so the review surface can offer it
// as a starting point rather than making somebody retype a video title
// they can see.
//
// Single-file units only. An album-shaped unit arrived with real ALBUM
// and ARTIST tags, so a guess derived from one member's title would be
// worse than what is already there - and the derivation is built for
// exactly the shape a lone video has.
func suggestedQueryFor(mediaType string, unit match.Unit) *reviewOverride {
	// Music only: identification never runs for anything else, so an
	// episode title would be split into a performer nobody can search.
	if mediaType != "music" || len(unit.Tracks) != 1 {
		return nil
	}
	artist, title, ok := match.SuggestedQuery(unit.Tracks[0])
	if !ok {
		return nil
	}
	s := reviewOverride{Artist: artist, Title: title}
	if s.empty() {
		return nil
	}
	return &s
}

// openAcquireEntries groups the staged files into album units and
// opens one review entry per unit, linking the upload sessions.
func (l *Library) openAcquireEntries(ctx context.Context, t *wdb.ToolTask, p toolTaskParams, docs []reviewTrackDoc, rowByPath map[string]string) ([]string, error) {
	tracks := make([]match.Track, 0, len(docs))
	docByPath := make(map[string]reviewTrackDoc, len(docs))
	for _, d := range docs {
		docByPath[d.Path] = d
		tags := d.Tags
		if tags == nil {
			tags = map[string]string{}
		}
		tracks = append(tracks, match.Track{
			Path: d.Path, Tags: tags, DurationSec: float64(d.DurationMS) / 1000,
		})
	}
	var entryIDs []string
	for _, unit := range match.Cluster(tracks) {
		unitDocs := make([]reviewTrackDoc, 0, len(unit.Tracks))
		for _, tr := range unit.Tracks {
			unitDocs = append(unitDocs, docByPath[tr.Path])
		}
		first := unitDocs[0]
		entry := wdb.ReviewEntry{
			Kind:       reviewKindImport,
			MediaType:  p.MediaType,
			Origin:     reviewOriginAcquire,
			LibraryPID: p.LibraryPID,
			UploadedBy: t.UserID,
			Title:      firstNonEmpty(first.Tags["ALBUM"], first.Title),
			Artist:     firstNonEmpty(first.Tags["ALBUMARTIST"], first.Artist),
		}
		id, err := l.openReviewEntry(ctx, entry, reviewPayload{
			Tracks: unitDocs, Suggested: suggestedQueryFor(p.MediaType, unit),
		}, !p.IdentifyDeclined)
		if err != nil {
			return entryIDs, err
		}
		entryIDs = append(entryIDs, id)
		for _, d := range unitDocs {
			uploadID := rowByPath[d.Path]
			if uploadID == "" {
				continue
			}
			if row, err := l.db.UploadByID(ctx, uploadID); err == nil {
				row.ReviewEntryID = id
				if err := l.db.UpdateUpload(ctx, row); err != nil {
					l.log.Warn("linking acquired upload", "upload", uploadID, "err", err)
				}
			}
		}
		if p.IdentifyDeclined {
			// After the links, so settling can find the sessions.
			l.importDeclinedEntry(ctx, id)
		}
	}
	return entryIDs, nil
}

// acquireFileName builds a safe staged file name from the source title
// and the delivered content type.
func acquireFileName(title, contentType string, index int) string {
	base := strings.Map(func(r rune) rune {
		switch {
		case r == '/' || r == '\\' || r == 0:
			return '-'
		case r < 0x20:
			return -1
		default:
			return r
		}
	}, strings.TrimSpace(title))
	if len(base) > 120 {
		base = base[:120]
	}
	if base == "" || base == "." || base == ".." {
		base = fmt.Sprintf("acquired-%02d", index+1)
	}
	ext := "m4a"
	ct := contentType
	if i := strings.IndexByte(ct, ';'); i >= 0 {
		ct = ct[:i]
	}
	switch strings.TrimSpace(strings.ToLower(ct)) {
	case "audio/opus":
		ext = "opus"
	case "audio/ogg", "application/ogg":
		ext = "ogg"
	case "audio/mpeg", "audio/mp3":
		ext = "mp3"
	case "audio/mp4", "audio/aac", "audio/x-m4a":
		ext = "m4a"
	case "audio/flac", "audio/x-flac":
		ext = "flac"
	case "audio/webm", "video/webm":
		ext = "webm"
	case "audio/x-matroska", "video/x-matroska":
		ext = "mka"
	}
	return base + "." + ext
}

// parseFileTags reads a file's embedded tags as the engine's canonical
// map; a parse failure just yields no tags.
func parseFileTags(ctx context.Context, path string) (map[string]string, error) {
	doc, err := waxlabel.ParseFile(ctx, path)
	if err != nil {
		return nil, err
	}
	return flatTags(doc), nil
}
