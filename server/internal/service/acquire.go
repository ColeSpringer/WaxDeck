package service

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"
	waxlabel "github.com/colespringer/waxlabel"
	"github.com/oklog/ulid/v2"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/match"
	"github.com/colespringer/waxdeck/server/internal/syncsource"
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

// acquireFetcher is the optional capability a source provider advertises when
// it can honour an acquisition's options: the preferred output format, and
// whether the download is music, for which it may clean the tags the source
// got wrong. A provider without it gets plain Fetch: its default format and
// no cleaning.
type acquireFetcher interface {
	FetchWith(ctx context.Context, req source.FetchRequest, w io.Writer, opts syncsource.FetchOptions) (*source.FetchResult, error)
}

// onceEnumerator is the optional capability a source provider advertises
// when its Enumerate, a subscription's poll, keeps state a one-shot read
// must leave alone: the YouTube provider's poll hands over and forgets
// premieres it was holding for the subscription.
type onceEnumerator interface {
	EnumerateOnce(ctx context.Context, req source.Request, opts syncsource.EnumerateOptions) (*source.Enumeration, error)
}

// acquireProber is the capability every acquisition source has: deciding
// from the link alone whether it reads the link and the shape the link
// names, and checking the link before it is queued, the shape and what the
// source says of it. A provider without it acquires nothing.
type acquireProber interface {
	LinkShape(url string, wantPlaylist bool) (string, error)
	Probe(ctx context.Context, url string, wantPlaylist bool) (syncsource.AcquireTarget, error)
}

// errNoAcquireSource is a server running no source that can acquire.
var errNoAcquireSource = &Error{Kind: KindUnsupported, Msg: "no acquisition source is running; start the server with WAXDECK_YOUTUBE=true to acquire from URLs"}

// acquireOwner is the source that reads a link, the first whose check of
// the link alone accepts it, and the shape it decided. With no source
// that reads it, the first refusal is the answer.
func (l *Ingest) acquireOwner(rawURL string, wantPlaylist bool) (source.Provider, acquireProber, string, error) {
	var refusal error
	for _, p := range l.sourceProviders {
		prober, ok := p.(acquireProber)
		if !ok {
			continue
		}
		shape, err := prober.LinkShape(rawURL, wantPlaylist)
		if err == nil {
			return p, prober, shape, nil
		}
		if refusal == nil {
			refusal = err
		}
	}
	if refusal == nil {
		return nil, nil, "", errNoAcquireSource
	}
	return nil, nil, "", refusal
}

// canAcquire reports whether any source running can acquire.
func (l *Ingest) canAcquire() bool {
	for _, p := range l.sourceProviders {
		if _, ok := p.(acquireProber); ok {
			return true
		}
	}
	return false
}

// acquireProbeTimeout bounds the check of a link before it is queued, well
// inside the client's wait for the answer.
const acquireProbeTimeout = 8 * time.Second

// acquireItemTimeout bounds one item's fetch and transcode. Only a
// backstop: the stall watch ends a download that stops moving, so this
// leaves a long file over a slow link the time it needs.
const acquireItemTimeout = time.Hour

// acquireStallTimeout is how long a download may show no activity before
// it is stopped, well inside WaxTap's own ten-minute chunk retry.
const acquireStallTimeout = 3 * time.Minute

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
// identify and acceptBest are the submission's identification and
// accept-best choices, nil for the account defaults. playlist takes the
// list over the video for a link naming both. The link is checked with the
// source first: a verdict refuses it and queues nothing.
func (l *Ingest) StartAcquisition(ctx context.Context, uc *UserCtx, rawURL string, playlist bool, mediaType, libraryPID, format string, identify, acceptBest *bool) (ToolTaskDTO, error) {
	if err := l.Settings.CheckWritable(ctx, ""); err != nil {
		return ToolTaskDTO{}, err
	}
	if err := l.requireUploader(uc); err != nil {
		return ToolTaskDTO{}, err
	}
	acquireFormat, ok := normalizeAcquireFormat(format)
	if !ok {
		return ToolTaskDTO{}, errInvalid("unknown acquisition format")
	}
	kind, err := requireUploadMediaType(mediaType)
	if err != nil {
		return ToolTaskDTO{}, err
	}
	if !l.canAcquire() {
		return ToolTaskDTO{}, errNoAcquireSource
	}
	parsed, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return ToolTaskDTO{}, addressRefusal(reasonInvalidAddress, "the address must start with http:// or https://")
	}
	if err := l.guardAcquireHost(ctx, parsed.Hostname()); err != nil {
		return ToolTaskDTO{}, err
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
	has, err := l.hasManagedDestination(ctx, uc, kind)
	if err != nil {
		return ToolTaskDTO{}, err
	}
	if !has {
		return ToolTaskDTO{}, errInvalid("no managed " + mediaType +
			" library to receive the files; an administrator must mark a library root managed (WAXDECK_MANAGED_ROOTS)")
	}
	target, err := l.checkAcquireLink(ctx, parsed.String(), playlist)
	if err != nil {
		return ToolTaskDTO{}, err
	}
	link := parsed.String()
	summary := map[string]any{"url": link}
	if target.Shape != "" {
		summary["source"] = target.Shape
	}
	t := newToolTask(uc, taskTypeAcquire, "", toolTaskParams{
		URL:        link,
		MediaType:  mediaType,
		LibraryPID: libraryPID,
		Format:     acquireFormat,
		// Stored as the decline rather than the choice, so a task queued
		// before this field existed reads as "identify" instead of
		// silently opting itself out.
		IdentifyDeclined: !l.resolveIdentify(ctx, uc.ID, identify),
		AcceptBest:       l.resolveAcceptBest(ctx, uc.ID, acceptBest),
		Shape:            target.Shape,
		Playlist:         playlist,
		SourceTitle:      target.Title,
	}, marshalJSON(summary))
	t.ItemTitle = strings.TrimSpace(target.Title)
	return l.Tools.queueToolTask(ctx, t)
}

// checkAcquireLink asks the source that reads a link about it before it is
// queued, within the probe budget. A verdict refuses the link, as does no
// source reading it. A check that reaches none (out of time, throttled, the
// bridge failing) answers the shape and lets the task queue, since its run
// asks again; a request that ended meanwhile answers its own error.
func (l *Ingest) checkAcquireLink(ctx context.Context, rawURL string, playlist bool) (syncsource.AcquireTarget, error) {
	_, prober, shape, err := l.acquireOwner(rawURL, playlist)
	if err != nil {
		if reason, verdict := acquireReason(err); verdict {
			return syncsource.AcquireTarget{}, sourceRefused(reason, err)
		}
		return syncsource.AcquireTarget{}, err
	}
	budget := cmp.Or(l.acquireProbeBudget, acquireProbeTimeout)
	probeCtx, cancel := context.WithTimeout(ctx, budget)
	defer cancel()
	target, err := prober.Probe(probeCtx, rawURL, playlist)
	target.Shape = cmp.Or(target.Shape, shape)
	if ctx.Err() != nil {
		return target, ctx.Err()
	}
	if err == nil {
		return target, nil
	}
	reason, verdict := acquireReason(err)
	if verdict && probeCtx.Err() == nil {
		return target, sourceRefused(reason, err)
	}
	l.log.Info("acquisition link check reached no verdict; queuing", "reason", reason, "err", err)
	return target, nil
}

// notReadable reports a provider's answer that a link is not one it reads.
func notReadable(err error) bool {
	reason, _ := acquireReason(err)
	return reason == reasonUnsupportedURL
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
// What staged keeps its entries whatever stops the run, and is recorded,
// so a later run fetches only what is left. A source's verdict fails the
// task; its other failures wait, at most toolSourceWaits times.
func (l *Ingest) runAcquire(ctx context.Context, t *wdb.ToolTask, p toolTaskParams) ([]string, error) {
	// However the run ends, its summary names what it opened.
	defer func() { t.Summary = l.acquireSummary(ctx, t) }()
	uc, err := l.Tools.taskAccount(ctx, t.UserID, "the acquiring account")
	if err != nil {
		return nil, err
	}
	if err := l.openStrandedEntries(ctx, t); err != nil {
		return nil, entriesFailure(err)
	}
	if !uc.UploadEnabled {
		return nil, finalFailure(KindForbidden, "upload rights were revoked", nil)
	}

	provider, items, listTitle, cut, err := l.acquireList(ctx, t.ID, p)
	if err != nil {
		return nil, l.acquireFailure(ctx, t, err)
	}
	l.Tools.nameToolTask(ctx, t, listTitle)
	if len(items) == 0 {
		return nil, finalFailure(KindRefused, "the source lists no downloadable audio", map[string]string{"reason": reasonPlaylistEmpty})
	}
	limit := cmp.Or(l.acquireItemCap, acquireMaxItems)
	truncated := cut || len(items) > limit
	if truncated {
		l.log.Info("acquisition truncated", "task", t.ID, "listed", len(items), "cap", limit, "source cut", cut)
		items = items[:min(len(items), limit)]
	}
	if truncated != taskParamsOf(t).Truncated {
		if err := l.Tools.editTaskParams(ctx, t, func(p *toolTaskParams) { p.Truncated = truncated }); err != nil {
			l.log.Warn("recording an acquisition's cut", "task", t.ID, "err", err)
		}
	}

	_, _, _, fetchErr, entriesErr := l.fetchAcquireBatch(ctx, t, p, provider, items, listTitle, uc, 90, false)
	if entriesErr != nil {
		// The files staged; opening their review entries did not. Plain:
		// a database that would not answer clears without the caller
		// changing anything, and what has no entry is fetched again.
		return nil, entriesFailure(entriesErr)
	}
	if fetchErr != nil {
		err := l.acquireFailure(ctx, t, fetchErr)
		if n := stillStaged(taskParamsOf(t).Fetched); n > 0 && len(items) > 1 && permanentToolErr(err) {
			err = stagedBefore(n, len(items), err)
		}
		return nil, err
	}
	// A download the person removed since is still one this run made.
	entries := taskParamsOf(t).Entries
	if len(taskParamsOf(t).Fetched) == 0 && len(entries) == 0 {
		return nil, fmt.Errorf("%w: nothing was downloaded", errToolPermanent)
	}
	return entries, nil
}

// entriesFailure is a failure to open review entries, said as that, of
// its cause's kind.
func entriesFailure(err error) error {
	return &Error{Kind: KindOf(err), Msg: "opening review entries: " + taskFailureText(err), Err: err, Params: RefusalParams(err)}
}

// acquireSummary is an acquisition's summary with what its runs did: the
// titles of the review entries they opened, in order, and whether the
// listing was cut at the cap.
func (l *Ingest) acquireSummary(ctx context.Context, t *wdb.ToolTask) string {
	ctx = context.WithoutCancel(ctx)
	sum := map[string]any{}
	if t.Summary != "" {
		_ = json.Unmarshal([]byte(t.Summary), &sum)
	}
	p := taskParamsOf(t)
	titles := make([]string, 0, len(p.Entries))
	for _, id := range p.Entries {
		e, err := l.db.ReviewEntryByID(ctx, id)
		if err != nil {
			l.log.Warn("reading an acquisition's entry", "task", t.ID, "entry", id, "err", err)
			continue
		}
		titles = append(titles, e.Title)
	}
	sum["entries"], sum["truncated"] = titles, p.Truncated
	return marshalJSON(sum)
}

// acquireFailure is how a run takes a failure: the source's go through
// sourceWait, one retrying cannot fix fails the task, and the rest are
// the drain's to wait out. A run the server stopped is left as it is.
func (l *Ingest) acquireFailure(ctx context.Context, t *wdb.ToolTask, err error) error {
	var fault *sourceFault
	switch {
	case ctx.Err() != nil:
		return err
	case errors.As(err, &fault):
		return l.Tools.sourceWait(ctx, t, err)
	case errors.Is(err, errToolPermanent):
		return err
	case kindIsPermanent(KindOf(err)):
		return fmt.Errorf("%w: %w", errToolPermanent, err)
	}
	return err
}

// fetchAcquireBatch stages each item with the per-item quota and room
// checks, each fetch within its own bound and stopped when its download
// stalls, reporting task progress up to progressCap percent and what it
// is doing as it goes, and opens review entries for whatever arrived -
// even when a fetch failed or the run was stopped. Each item staged is
// recorded in the task's params as it stages, and skipped by a later run;
// the entries opened are recorded too. skipItemErrors is the playlist-sync
// posture: one entry's failed fetch is skipped and counted rather than
// cutting the batch, so an undeliverable video never starves the entries
// behind it; the systemic checks (context, quota, staging room) and a
// stalled download, which is the link's trouble and not the video's,
// still stop the batch either way. Returns the opened entry ids, how many files
// staged, how many items were skipped over their own errors, the
// batch-stopping fetch error, and the entry-opening error - separately,
// because the two mean different things to the caller's retry policy.
func (l *Ingest) fetchAcquireBatch(ctx context.Context, t *wdb.ToolTask, p toolTaskParams, provider source.Provider, items []acquireItem, listTitle string, uc *UserCtx, progressCap float64, skipItemErrors bool) (entryIDs []string, staged, skipped int, fetchErr, entriesErr error) {
	var (
		docs      []reviewTrackDoc
		rowByPath = map[string]string{}
		fetched   = map[string]bool{}
		bound     = cmp.Or(l.acquireItemBound, acquireItemTimeout)
		window    = cmp.Or(l.acquireStallWindow, acquireStallTimeout)
		// A book listed as several items is one book, whichever of its
		// parts a try stages.
		listedBook = isBookMedia(p.MediaType) && len(items) > 1
		listTotal  int
	)
	if listedBook {
		listTotal = len(items)
	}
	// What an earlier run staged is skipped below; the run's start opened
	// its entry.
	for _, f := range taskParamsOf(t).Fetched {
		fetched[f.Key] = true
	}
	for i, item := range items {
		key := cmp.Or(item.GUID, item.URL)
		if fetched[key] {
			continue
		}
		if ctx.Err() != nil {
			fetchErr = ctx.Err()
			break
		}
		if uc.UploadQuotaBytes > 0 {
			used, err := l.db.UploadBytesInUse(ctx, t.UserID)
			if err == nil && used >= uc.UploadQuotaBytes {
				fetchErr = finalFailure(KindQuota, fmt.Sprintf("the pending-upload limit is full (%d bytes waiting for review)", uc.UploadQuotaBytes), nil)
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
		title := cmp.Or(item.Title, p.SourceTitle)
		l.Tools.noteActivity(ctx, t.ID, func(a *ToolTaskActivity) {
			*a = ToolTaskActivity{Phase: activityDownloading, ItemsDone: i, ItemsTotal: len(items), ItemTitle: title, pctShare: progressCap}
		})
		stallCtx, stall := context.WithCancelCause(ctx)
		itemCtx, cancel := context.WithTimeout(stallCtx, bound)
		watch := &stallWatch{window: window, stop: func() { stall(errFetchStalled) }}
		doc, uploadID, err := l.fetchAcquireItem(itemCtx, provider, t, p, item, i, listTotal, func(ev syncsource.FetchEvent) {
			watch.event(ev.Phase)
			l.Tools.noteSourceActivity(ctx, t.ID, func(a *ToolTaskActivity) { a.fetchEvent(ev) })
		})
		watch.done()
		stalled := errors.Is(context.Cause(stallCtx), errFetchStalled)
		cancel()
		stall(nil)
		if err != nil {
			if stalled {
				// The fetch's own error is the stop the watch caused.
				l.log.Info("acquisition download stalled", "task", t.ID, "item", item.URL, "after", window, "err", err)
				err = &sourceFault{errFetchStalled}
			}
			if skipItemErrors && ctx.Err() == nil && !stalled {
				skipped++
				l.log.Warn("skipping undeliverable acquisition item", "item", item.URL, "err", err)
				continue
			}
			fetchErr = err
			break
		}
		docs = append(docs, doc)
		rowByPath[doc.Path] = uploadID
		if t.Type == taskTypeAcquire && len(items) == 1 {
			// A lone video is named by what it carries once fetched.
			l.Tools.nameToolTask(ctx, t, firstNonEmpty(doc.Tags["TITLE"], item.Title))
		}
		if err := l.Tools.editTaskParams(ctx, t, func(p *toolTaskParams) {
			p.Fetched = append(p.Fetched, fetchedItem{Key: key, Upload: uploadID})
			p.ListTitle = listTitle
		}); err != nil {
			l.log.Warn("recording a staged acquisition item", "task", t.ID, "item", key, "err", err)
		}
		t.ProgressPct = float64(i+1) / float64(len(items)) * progressCap
		if uerr := l.db.UpdateToolTask(ctx, *t); uerr == nil {
			l.Tools.notifyToolTaskProgress(ctx, t.ID)
		}
		l.Tools.noteActivity(ctx, t.ID, func(a *ToolTaskActivity) { a.ItemsDone, a.BytesDone, a.BytesTotal = i+1, 0, 0 })
	}
	if len(docs) == 0 {
		return nil, 0, skipped, fetchErr, nil
	}
	// Whatever stopped the batch, what staged gets its entries.
	ctx = context.WithoutCancel(ctx)
	l.Tools.noteActivity(ctx, t.ID, func(a *ToolTaskActivity) {
		*a = ToolTaskActivity{Phase: activityImporting, ItemsDone: a.ItemsDone, ItemsTotal: a.ItemsTotal, pctShare: a.pctShare}
	})
	// What gets no entry here gets it at the start of the next run.
	entryIDs, entriesErr = l.openAcquireEntries(ctx, t, p, docs, listTitle, rowByPath, listedBook)
	l.recordAcquireEntries(ctx, t, entryIDs)
	if entriesErr != nil && fetchErr != nil {
		// Both halves failed; neither may vanish into the other.
		l.log.Warn("acquisition batch failed twice over", "fetch", fetchErr, "entries", entriesErr)
	}
	// A download the person removed meanwhile is no longer staged.
	batch := make(map[string]bool, len(rowByPath))
	for _, up := range rowByPath {
		batch[up] = true
	}
	staged = len(docs)
	for _, f := range taskParamsOf(t).Fetched {
		if f.Dropped && batch[f.Upload] {
			staged--
		}
	}
	return entryIDs, staged, skipped, fetchErr, entriesErr
}

// stillStaged counts the items a task staged that the person has not
// removed since.
func stillStaged(fetched []fetchedItem) int {
	n := 0
	for _, f := range fetched {
		if !f.Dropped {
			n++
		}
	}
	return n
}

// recordAcquireEntries adds the review entries a run opened to the task's.
func (l *Ingest) recordAcquireEntries(ctx context.Context, t *wdb.ToolTask, entryIDs []string) {
	if len(entryIDs) == 0 {
		return
	}
	if err := l.Tools.editTaskParams(ctx, t, func(p *toolTaskParams) { p.Entries = append(p.Entries, entryIDs...) }); err != nil {
		l.log.Warn("recording an acquisition's entries", "task", t.ID, "err", err)
	}
}

// openStrandedEntries opens the review entries of what an earlier run of
// the task staged and recorded but never gave an entry (a run that ended
// with the process, or a panic), so nothing a run skips as fetched is left
// without one; takes as the task's an entry a run opened and died before
// recording; and forgets an item whose upload is gone, which a later run
// fetches again.
func (l *Ingest) openStrandedEntries(ctx context.Context, t *wdb.ToolTask) error {
	p := taskParamsOf(t)
	var (
		docs      []reviewTrackDoc
		rowByPath = map[string]string{}
		gone      = map[string]bool{}
		entry     toolTaskParams
		known     = map[string]bool{}
		adopted   []string
		// declined are the adopted entries to land unreviewed.
		declined []string
	)
	for _, id := range p.Entries {
		known[id] = true
	}
	for _, f := range p.Fetched {
		if f.Dropped {
			continue
		}
		row, err := l.db.UploadByID(ctx, f.Upload)
		if errors.Is(err, wdb.ErrNotFound) {
			gone[f.Key] = true
			continue
		}
		if err != nil {
			return err
		}
		if row.ReviewEntryID != "" {
			if !known[row.ReviewEntryID] {
				known[row.ReviewEntryID] = true
				adopted = append(adopted, row.ReviewEntryID)
				if !row.Identify {
					declined = append(declined, row.ReviewEntryID)
				}
			}
			continue
		}
		var doc reviewTrackDoc
		if row.State != uploadStaged || json.Unmarshal([]byte(row.TrackDoc), &doc) != nil || doc.Path != row.StagingPath {
			gone[f.Key] = true
			continue
		}
		if _, err := os.Stat(row.StagingPath); err != nil {
			gone[f.Key] = true
			continue
		}
		if len(docs) == 0 {
			entry = toolTaskParams{MediaType: row.MediaType, LibraryPID: row.LibraryPID, IdentifyDeclined: !row.Identify, AcceptBest: row.AcceptBest}
		}
		docs = append(docs, doc)
		rowByPath[doc.Path] = row.ID
	}
	// The run that opened them died before their import, which answers
	// at once for one that is no longer pending. Imported before they are
	// recorded, as a run's own are: a stop between the two adopts them
	// again.
	for _, id := range declined {
		l.importDeclinedEntry(context.WithoutCancel(ctx), id)
	}
	if len(gone) > 0 || len(adopted) > 0 {
		if len(adopted) > 0 {
			l.log.Info("taking an earlier run's unrecorded entries", "task", t.ID, "entries", len(adopted))
		}
		if err := l.Tools.editTaskParams(ctx, t, func(p *toolTaskParams) {
			p.Fetched = slices.DeleteFunc(p.Fetched, func(f fetchedItem) bool { return gone[f.Key] })
			p.Entries = append(p.Entries, adopted...)
		}); err != nil {
			return err
		}
	}
	if len(docs) == 0 {
		return nil
	}
	l.log.Info("opening the review entries of an earlier run's downloads", "task", t.ID, "files", len(docs))
	book := !slices.ContainsFunc(docs, func(d reviewTrackDoc) bool { return d.ListPosition == 0 })
	ctx = context.WithoutCancel(ctx)
	entryIDs, err := l.openAcquireEntries(ctx, t, entry, docs, p.ListTitle, rowByPath, book)
	l.recordAcquireEntries(ctx, t, entryIDs)
	return err
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
func (l *Ingest) guardAcquireHost(ctx context.Context, host string) error {
	if l.Podcasts.allowPrivateFeedHosts {
		return nil
	}
	// Stricter than the write-time courtesy check (hostResolvesPrivate)
	// over the same lookup: a name that does not resolve is refused here.
	ips, err := l.hostAddrs(ctx, host)
	if err != nil {
		return addressRefusal(reasonInvalidAddress, "the url's host does not resolve")
	}
	for _, ip := range ips {
		if privateIP(ip) || ip.IsMulticast() {
			return addressRefusal(reasonBlockedAddress, "the url points at a private or internal address")
		}
	}
	return nil
}

// reasonInvalidAddress is a link that is no web address the server can
// reach: not http or https, or a host that does not resolve.
const reasonInvalidAddress = "invalid-address"

// addressRefusal refuses a link for its address, naming the reason a
// client places it by.
func addressRefusal(reason, msg string) error {
	return &Error{Kind: KindInvalid, Msg: msg, Params: map[string]string{"reason": reason}}
}

// hasManagedDestination reports whether a managed library the caller
// can see accepts the given item kind, which is the precondition for
// importing an acquired or uploaded file (the catalog places files
// only into managed roots).
func (l *Ingest) hasManagedDestination(ctx context.Context, uc *UserCtx, kind model.Kind) (bool, error) {
	roots := l.Roots.libraryRoots()
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

// acquireList resolves the task's link to the source that reads it, its
// download list, the list's own title and whether the source stopped
// listing at its own cap. A video is one item; a playlist or channel
// enumerates within the enumeration bound, reporting as it reads, and a
// failed listing is the answer. A source failure comes back as a
// sourceFault.
func (l *Ingest) acquireList(ctx context.Context, taskID string, p toolTaskParams) (provider source.Provider, items []acquireItem, title string, cut bool, err error) {
	provider, _, shape, err := l.acquireOwner(p.URL, p.Playlist)
	if err != nil {
		return nil, nil, "", false, &sourceFault{err}
	}
	if cmp.Or(p.Shape, shape) == syncsource.ShapeVideo {
		return provider, []acquireItem{{URL: p.URL}}, "", false, nil
	}
	ctx, cancel := context.WithTimeout(ctx, toolRunTimeout)
	defer cancel()
	progress := l.Tools.listingActivity(ctx, taskID)
	enumerate := provider.Enumerate
	if o, ok := provider.(onceEnumerator); ok {
		enumerate = func(ctx context.Context, req source.Request) (*source.Enumeration, error) {
			return o.EnumerateOnce(ctx, req, syncsource.EnumerateOptions{Progress: progress, OnCut: func() { cut = true }})
		}
	}
	en, err := enumerate(ctx, source.Request{URL: p.URL})
	if err != nil {
		return nil, nil, "", false, &sourceFault{err}
	}
	if en.Feed == nil {
		return provider, nil, "", false, nil
	}
	items = make([]acquireItem, 0, len(en.Feed.Episodes))
	for _, ep := range en.Feed.Episodes {
		if ep.EnclosureURL == "" {
			continue
		}
		items = append(items, acquireItem{Title: ep.Title, URL: ep.EnclosureURL, GUID: ep.GUID})
	}
	return provider, items, strings.TrimSpace(en.Feed.Title), cut, nil
}

// fetchAcquireItem downloads one item into upload staging with the
// crash-safe write discipline and records its upload session, telling
// onEvent what the fetch does and then that it imports what arrived. A
// listTotal is a book part's list, of which the item is index.
func (l *Ingest) fetchAcquireItem(ctx context.Context, provider source.Provider, t *wdb.ToolTask, p toolTaskParams, item acquireItem, index, listTotal int, onEvent func(syncsource.FetchEvent)) (reviewTrackDoc, string, error) {
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
	// facade, so the acquisition's options ride a WaxDeck-owned capability
	// rather than the source.FetchRequest port.
	freq := source.FetchRequest{URL: item.URL}
	var res *source.FetchResult
	if af, ok := provider.(acquireFetcher); ok {
		// Downloading from the call, which a hang before the transfer's
		// first report stalls too.
		onEvent(syncsource.FetchEvent{Phase: activityDownloading})
		res, err = af.FetchWith(ctx, freq, f, syncsource.FetchOptions{Format: p.Format, Music: p.MediaType == "music", OnEvent: onEvent})
	} else {
		res, err = provider.Fetch(ctx, freq, f)
	}
	if err != nil {
		err = &sourceFault{err}
	} else {
		onEvent(syncsource.FetchEvent{Phase: activityImporting})
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
		Path:       final,
		Title:      firstNonEmpty(item.Title, strings.TrimSuffix(name, filepath.Ext(name))),
		SourceType: provider.SourceType(),
		SourceURL:  item.URL,
	}
	if listTotal > 0 {
		doc.ListPosition, doc.ListTotal = index+1, listTotal
	}
	// The provider embeds the source metadata; read it back so the
	// identify pipeline and the review diff see what the file carries.
	var length time.Duration
	if tags, dur, err := parseFileTags(ctx, final); err == nil {
		doc.Tags = tags
		doc.Title = firstNonEmpty(tags["TITLE"], doc.Title)
		doc.Artist = tags["ARTIST"]
		doc.TrackNo = match.ParseOrdinal(tags["TRACKNUMBER"])
		length = dur
	}
	fp, fpSecs := l.fingerprintFile(ctx, final, length)
	doc.Fingerprint = fp
	doc.DurationMS = cmp.Or(length.Milliseconds(), int64(fpSecs)*1000)

	now := time.Now()
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
		Identify:     !p.IdentifyDeclined,
		AcceptBest:   p.AcceptBest,
		CreatedAtNS:  now.UnixNano(),
		ReceivedAtNS: now.UnixNano(),
		ExpiresAtNS:  now.Add(l.uploadRetention).UnixNano(),
		// What the entry would hold, for a run that opens it later.
		TrackDoc: marshalJSON(doc),
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

// suggestedQueryFor reads the artist and title a loose acquisition's
// source title is judged as (match.SuggestedQuery: upload notes dropped,
// what names the recording kept, where the search asks for the song
// alone), so the review surface can offer it as a starting point rather
// than making somebody retype a video title they can see.
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
// opens one review entry per unit, linking the upload sessions. An
// audiobook listed as several items (book) is one book, in list order,
// titled by the list.
func (l *Ingest) openAcquireEntries(ctx context.Context, t *wdb.ToolTask, p toolTaskParams, docs []reviewTrackDoc, listTitle string, rowByPath map[string]string, book bool) ([]string, error) {
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
	units := []match.Unit{{Tracks: tracks}}
	if !book {
		units = match.Cluster(tracks)
	}
	var entryIDs []string
	for _, unit := range units {
		id, err := l.openAcquireUnit(ctx, t, p, unit, docByPath, listTitle, rowByPath, book)
		if err != nil {
			return entryIDs, err
		}
		if id == "" {
			continue
		}
		entryIDs = append(entryIDs, id)
		if p.IdentifyDeclined {
			// After the links, so settling can find the sessions.
			l.importDeclinedEntry(ctx, id)
		}
	}
	return entryIDs, nil
}

// openAcquireUnit opens one unit's review entry, linking its downloads. A
// download the person removed while the run went on is left out, marked so
// no later run fetches it again, and a unit left with none opens nothing.
func (l *Ingest) openAcquireUnit(ctx context.Context, t *wdb.ToolTask, p toolTaskParams, unit match.Unit, docByPath map[string]reviewTrackDoc, listTitle string, rowByPath map[string]string, book bool) (string, error) {
	for len(unit.Tracks) > 0 {
		unitDocs := make([]reviewTrackDoc, 0, len(unit.Tracks))
		var uploadIDs []string
		for _, tr := range unit.Tracks {
			d := docByPath[tr.Path]
			unitDocs = append(unitDocs, d)
			if id := rowByPath[d.Path]; id != "" {
				uploadIDs = append(uploadIDs, id)
			}
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
		if book {
			entry.ID = newReviewID()
			entry.Title = bookUnitTitle(nil, unitDocs, listTitle, entry.ID)
		}
		id, err := l.openLinkedReviewEntry(ctx, entry, reviewPayload{
			Tracks: unitDocs, Suggested: suggestedQueryFor(p.MediaType, unit), List: listTitle,
			AcceptBest: p.AcceptBest,
		}, !p.IdentifyDeclined, uploadIDs)
		var gone *wdb.UnlinkableUploadError
		if !errors.As(err, &gone) {
			return id, err
		}
		kept := slices.DeleteFunc(slices.Clone(unit.Tracks), func(tr match.Track) bool { return rowByPath[tr.Path] == gone.UploadID })
		if len(kept) == len(unit.Tracks) {
			return "", err
		}
		l.log.Info("leaving a removed download out of its entry", "task", t.ID, "upload", gone.UploadID)
		if err := l.Tools.editTaskParams(ctx, t, func(p *toolTaskParams) {
			for i := range p.Fetched {
				if p.Fetched[i].Upload == gone.UploadID {
					p.Fetched[i].Dropped = true
				}
			}
		}); err != nil {
			l.log.Warn("recording a removed download", "task", t.ID, "upload", gone.UploadID, "err", err)
		}
		unit.Tracks = kept
	}
	return "", nil
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
func parseFileTags(ctx context.Context, path string) (map[string]string, time.Duration, error) {
	doc, err := waxlabel.ParseFile(ctx, path)
	if err != nil {
		return nil, 0, err
	}
	return flatTags(doc), doc.Properties().Duration(), nil
}
