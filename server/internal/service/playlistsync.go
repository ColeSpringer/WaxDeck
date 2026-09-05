package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"time"

	waxbin "github.com/colespringer/waxbin"
	waxart "github.com/colespringer/waxbin/art"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/source"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

// Synced external playlists: a manual playlist bound to an external
// source, reconciled on a schedule and on demand. A live source (a
// YouTube playlist) is re-enumerated in full order and new entries are
// downloaded through the normal acquisition path, joining the playlist
// once their review entries resolve into items - eventual consistency
// by design. A matched source (a streaming export) stores its parsed
// portable refs and re-runs the resolve ladder on demand, downloading
// nothing. The binding, its per-run health, the shared entry-to-item
// map, and the per-playlist attach/tombstone bookkeeping live in
// waxdeck.db; membership writes go through ReplacePlaylistItems so the
// optimistic guard keeps a background run from clobbering an owner's
// concurrent edit.

const (
	taskTypePlaylistSync = "playlist-sync"

	playlistSyncModeAppend      = "append"
	playlistSyncModeMirror      = "mirror"
	playlistSyncModeMirrorTrash = "mirror-trash"

	// playlistSyncDisableAfter suspends a binding's schedule after this
	// many consecutive failed runs, feedDisableAfter's parity.
	playlistSyncDisableAfter = 10

	// playlistSyncMaxEntries caps one reconcile's enumeration, well
	// above the provider's own feed default: a mirror diffs against the
	// whole listing, so the cap is a safety rail, not a page size, and
	// hitting it refuses destructive work rather than acting on a
	// window (see the truncation guard in reconcilePlaylistSource).
	playlistSyncMaxEntries = 1000

	// playlistCoverMaxBytes caps a fetched source thumbnail.
	playlistCoverMaxBytes = 8 << 20
)

// errSyncEnumerate marks a reconcile that failed before it learned
// anything: the source did not enumerate. Preview maps it to a 400 -
// it is the validate-before-save affordance and a bad URL is the
// caller's to fix - while a scheduled run keeps it transient.
var errSyncEnumerate = errors.New("enumerating the source")

// playlistSyncIntervals is the closed set of scheduled-run intervals.
var playlistSyncIntervals = map[int]bool{1: true, 3: true, 6: true, 12: true, 24: true}

// PlaylistSourceDTO is a stored binding for the API layer.
type PlaylistSourceDTO struct {
	Source              string
	URL                 string
	Title               string
	Live                bool
	Mode                string
	IntervalHours       int
	RefCount            int
	Disabled            bool
	ConsecutiveFailures int
	LastError           string
	LastAttemptNS       int64
	LastSyncedNS        int64
	HasRun              bool
	LastCounts          wdb.PlaylistSyncCounts
}

// PlaylistSourceUpdateDTO is a binding to store, replacing any previous
// one whole.
type PlaylistSourceUpdateDTO struct {
	URL           string
	Source        string
	Payload       string
	Refs          []PortableRefDTO
	Mode          string
	IntervalHours int
}

// PlaylistSyncPreviewDTO reports what a sync would do right now.
type PlaylistSyncPreviewDTO struct {
	Entries       int
	WouldAdd      int
	WouldDownload int
	WouldRemove   int
	WouldTrash    int
	Pending       int
	Unavailable   int
	Missing       int
	Misses        []ImportMiss
}

// playlistSyncOutcome is one reconcile's result: the counts a run
// records, the preview a dry run answers, and the review entries the
// download step opened.
type playlistSyncOutcome struct {
	counts     wdb.PlaylistSyncCounts
	preview    PlaylistSyncPreviewDTO
	entryIDs   []string
	conflicted bool
	// detached counts trashed members removed before the replace; they
	// are a real membership write, so a conflicted run that already
	// detached must not read as a clean no-op.
	detached int
}

// hasPlaylistSnapshotter reports whether any source provider can list
// a playlist in full order - the gate the sync endpoints and sweeper
// check before doing anything.
func (l *Library) hasPlaylistSnapshotter() bool {
	for _, p := range l.sourceProviders {
		if _, ok := p.(syncsource.Snapshotter); ok {
			return true
		}
	}
	return false
}

// firstSnapshotterSourceType is the source label of the first
// snapshot-capable provider, for the paths that need a label before
// any URL has been probed.
func (l *Library) firstSnapshotterSourceType() string {
	for _, p := range l.sourceProviders {
		if _, ok := p.(syncsource.Snapshotter); ok {
			return string(p.SourceType())
		}
	}
	return ""
}

// playlistSnapshotFor lists a playlist URL through whichever snapshot-
// capable provider answers for it, the way acquireList probes each
// provider against the actual URL rather than trusting registration
// order. The provider that answered is returned beside the snapshot,
// since it is the one whose Fetch the download step must use.
func (l *Library) playlistSnapshotFor(ctx context.Context, url string, opts syncsource.SnapshotOptions) (source.Provider, *syncsource.PlaylistSnapshot, error) {
	var firstErr error
	tried := false
	for _, p := range l.sourceProviders {
		s, ok := p.(syncsource.Snapshotter)
		if !ok {
			continue
		}
		tried = true
		snap, err := s.PlaylistSnapshot(ctx, url, opts)
		if err != nil {
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		return p, snap, nil
	}
	if !tried {
		return nil, nil, &Error{Kind: KindUnsupported, Msg: "no acquisition source is running; start the server with WAXDECK_YOUTUBE=true to sync from URLs"}
	}
	return nil, nil, fmt.Errorf("%w: %v", errSyncEnumerate, firstErr)
}

// GetPlaylistSource reads a playlist's binding. Owner only.
func (l *Library) GetPlaylistSource(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (PlaylistSourceDTO, error) {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return PlaylistSourceDTO{}, err
	}
	row, err := l.db.PlaylistSourceFor(ctx, string(pl.PID))
	if errors.Is(err, wdb.ErrNotFound) {
		return PlaylistSourceDTO{}, errNotFound("the playlist has no source binding")
	}
	if err != nil {
		return PlaylistSourceDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	return playlistSourceDTO(row), nil
}

// SetPlaylistSource binds a playlist to an external source, replacing
// any previous binding whole. Owner only; static playlists only;
// selecting mirror-trash needs the delete right.
func (l *Library) SetPlaylistSource(ctx context.Context, uc *UserCtx, apiPlaylistPID string, in PlaylistSourceUpdateDTO) (PlaylistSourceDTO, error) {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return PlaylistSourceDTO{}, err
	}
	if pl.Kind != model.PlaylistStatic {
		return PlaylistSourceDTO{}, errInvalid("a smart playlist's membership is its rule")
	}
	if err := validatePlaylistSourceSettings(in); err != nil {
		return PlaylistSourceDTO{}, err
	}
	if in.Mode == playlistSyncModeMirrorTrash && !uc.Admin && !uc.Delete {
		return PlaylistSourceDTO{}, &Error{Kind: KindForbidden, Msg: "selecting mirror-trash needs the delete right"}
	}
	row, err := l.buildPlaylistSourceRow(ctx, pl, in, true)
	if err != nil {
		return PlaylistSourceDTO{}, err
	}
	now := time.Now().UnixNano()
	prev, prevErr := l.db.PlaylistSourceFor(ctx, string(pl.PID))
	if prevErr == nil {
		row.CreatedAtNS = prev.CreatedAtNS
		// A binding pointed at a different source invalidates the
		// per-entry bookkeeping: the ids name someone else's entries.
		if prev.IdentityKey != row.IdentityKey || prev.Source != row.Source || !row.Live {
			if err := l.db.ClearPlaylistSourceEntries(ctx, string(pl.PID)); err != nil {
				return PlaylistSourceDTO{}, &Error{Kind: KindInternal, Err: err}
			}
		}
	} else if !errors.Is(prevErr, wdb.ErrNotFound) {
		return PlaylistSourceDTO{}, &Error{Kind: KindInternal, Err: prevErr}
	}
	// The first scheduled run comes one interval after the bind; the
	// sync endpoint is the immediate door. Binding must not surprise
	// with downloads - or, under mirror-trash, with trashed files.
	row.LastAttemptNS = now
	row.UpdatedAtNS = now
	if err := l.db.PutPlaylistSource(ctx, row); err != nil {
		return PlaylistSourceDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	if row.CoverURL != "" {
		l.syncSourcePlaylistCover(ctx, pl, row.CoverURL)
	} else if !row.Live {
		// A matched binding has no thumbnail to keep current; a live
		// binding's leftover source cover would otherwise stand frozen
		// with nothing left to refresh it.
		l.releaseSourcePlaylistCover(ctx, pl)
	}
	l.Audit(ctx, uc, "playlist.source.bind",
		AuditTarget{Kind: "playlist", PID: apiPlaylistPID, Name: pl.Name},
		map[string]any{"source": row.Source, "mode": row.Mode, "live": row.Live})
	return playlistSourceDTO(row), nil
}

// UnbindPlaylistSource removes a binding; the playlist and its members
// stay as they are.
func (l *Library) UnbindPlaylistSource(ctx context.Context, uc *UserCtx, apiPlaylistPID string) error {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return err
	}
	if _, err := l.db.PlaylistSourceFor(ctx, string(pl.PID)); errors.Is(err, wdb.ErrNotFound) {
		return errNotFound("the playlist has no source binding")
	} else if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.DeletePlaylistSource(ctx, string(pl.PID)); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	// The source thumbnail was the binding's to keep current; with the
	// binding gone it would stand frozen forever, so the slot goes back
	// to the mosaic. A custom cover is untouched.
	l.releaseSourcePlaylistCover(ctx, pl)
	l.Audit(ctx, uc, "playlist.source.unbind",
		AuditTarget{Kind: "playlist", PID: apiPlaylistPID, Name: pl.Name}, nil)
	return nil
}

// PreviewPlaylistSync dry-runs the reconciler: the same computation a
// sync makes, writing nothing. With an update body it previews those
// prospective settings (the sheet's dry run before a bind commits);
// without one it previews the stored binding.
func (l *Library) PreviewPlaylistSync(ctx context.Context, uc *UserCtx, apiPlaylistPID string, in *PlaylistSourceUpdateDTO) (PlaylistSyncPreviewDTO, error) {
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return PlaylistSyncPreviewDTO{}, err
	}
	var row wdb.PlaylistSourceRow
	if in != nil {
		if pl.Kind != model.PlaylistStatic {
			return PlaylistSyncPreviewDTO{}, errInvalid("a smart playlist's membership is its rule")
		}
		if err := validatePlaylistSourceSettings(*in); err != nil {
			return PlaylistSyncPreviewDTO{}, err
		}
		// No delete-right gate here: previewing what mirror-trash would
		// remove is how someone decides whether to ask for the right.
		row, err = l.buildPlaylistSourceRow(ctx, pl, *in, false)
		if err != nil {
			return PlaylistSyncPreviewDTO{}, err
		}
	} else {
		row, err = l.db.PlaylistSourceFor(ctx, string(pl.PID))
		if errors.Is(err, wdb.ErrNotFound) {
			return PlaylistSyncPreviewDTO{}, errNotFound("the playlist has no source binding")
		}
		if err != nil {
			return PlaylistSyncPreviewDTO{}, &Error{Kind: KindInternal, Err: err}
		}
	}
	out, err := l.reconcilePlaylistSource(ctx, nil, uc, pl, row, true)
	if err != nil {
		// Preview is the validate-before-save affordance: a source that
		// would not enumerate is the caller's URL to fix, not a server
		// fault, so it answers 400 the way the bind's own probe does.
		if errors.Is(err, errSyncEnumerate) {
			return PlaylistSyncPreviewDTO{}, errInvalid(err.Error())
		}
		return PlaylistSyncPreviewDTO{}, err
	}
	return out.preview, nil
}

// SyncPlaylistSourceNow queues a sync run for the stored binding,
// answering a run already in flight with that task rather than a second
// one.
func (l *Library) SyncPlaylistSourceNow(ctx context.Context, uc *UserCtx, apiPlaylistPID string) (ToolTaskDTO, error) {
	if err := l.CheckWritable(ctx, ""); err != nil {
		return ToolTaskDTO{}, err
	}
	pl, err := l.resolveOwnedPlaylist(ctx, uc, apiPlaylistPID)
	if err != nil {
		return ToolTaskDTO{}, err
	}
	row, err := l.db.PlaylistSourceFor(ctx, string(pl.PID))
	if errors.Is(err, wdb.ErrNotFound) {
		return ToolTaskDTO{}, errNotFound("the playlist has no source binding")
	}
	if err != nil {
		return ToolTaskDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	if row.Live && !l.hasPlaylistSnapshotter() {
		return ToolTaskDTO{}, &Error{Kind: KindUnsupported, Msg: "no acquisition source is running; start the server with WAXDECK_YOUTUBE=true to sync from URLs"}
	}
	if t, err := l.db.ActiveToolTask(ctx, taskTypePlaylistSync, apiPlaylistPID); err == nil {
		return toolTaskDTO(t), nil
	} else if !errors.Is(err, wdb.ErrNotFound) {
		return ToolTaskDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	return l.insertToolTask(ctx, uc, taskTypePlaylistSync, apiPlaylistPID, toolTaskParams{
		PlaylistPID: apiPlaylistPID,
	})
}

// SyncDuePlaylistSources queues a sync task for every live binding
// whose interval elapsed. Called by the playlist-sync sweeper; it
// self-gates, so the worker spawns unconditionally at the composition
// root and a music-only or bridge-less instance simply idles.
func (l *Library) SyncDuePlaylistSources(ctx context.Context) {
	if !l.hasPlaylistSnapshotter() {
		return
	}
	if err := l.CheckWritable(ctx, ""); err != nil {
		return
	}
	rows, err := l.db.DuePlaylistSources(ctx, time.Now().UnixNano())
	if err != nil {
		l.log.Warn("listing due playlist sources", "err", err)
		return
	}
	for _, b := range rows {
		if ctx.Err() != nil {
			return
		}
		pl, err := l.lib.Playlists().Get(ctx, model.PID(b.PlaylistPID))
		if err != nil {
			if KindOf(classify(err)) == KindNotFound {
				// An orphaned binding: the playlist is gone, so the
				// bookkeeping goes too.
				if derr := l.db.DeletePlaylistSource(ctx, b.PlaylistPID); derr != nil {
					l.log.Warn("dropping orphaned playlist source", "playlist", b.PlaylistPID, "err", derr)
				}
			} else {
				l.log.Warn("reading synced playlist", "playlist", b.PlaylistPID, "err", err)
			}
			continue
		}
		// The catalog's OwnerName column carries the account id.
		uc := l.taskUserCtx(ctx, pl.OwnerName)
		if uc == nil {
			l.log.Warn("synced playlist owner is gone or disabled", "playlist", b.PlaylistPID)
			continue
		}
		apiPlaylistPID := apiPID(PrefixPlaylist, pl.PID)
		if _, err := l.db.ActiveToolTask(ctx, taskTypePlaylistSync, apiPlaylistPID); err == nil {
			continue
		} else if !errors.Is(err, wdb.ErrNotFound) {
			l.log.Warn("checking for a running playlist sync", "playlist", b.PlaylistPID, "err", err)
			continue
		}
		if _, err := l.insertToolTask(ctx, uc, taskTypePlaylistSync, apiPlaylistPID, toolTaskParams{
			PlaylistPID: apiPlaylistPID,
		}); err != nil {
			l.log.Warn("queuing playlist sync", "playlist", b.PlaylistPID, "err", err)
		}
	}
}

// runPlaylistSync executes one leased sync task: enumerate, reconcile
// membership, then download what is new. Failure accounting rides the
// binding row (feedwork pattern), and the auto-disable edge notifies
// exactly once.
func (l *Library) runPlaylistSync(ctx context.Context, t *wdb.ToolTask, p toolTaskParams) ([]string, error) {
	uc := l.taskUserCtx(ctx, t.UserID)
	if uc == nil {
		return nil, fmt.Errorf("%w: the playlist owner's account is gone or disabled", errToolPermanent)
	}
	pl, err := l.resolveOwnedPlaylist(ctx, uc, p.PlaylistPID)
	if err != nil {
		if KindOf(err) == KindNotFound {
			_, bare, _ := parseAPIPID(p.PlaylistPID)
			if derr := l.db.DeletePlaylistSource(ctx, string(bare)); derr != nil {
				l.log.Warn("dropping orphaned playlist source", "playlist", p.PlaylistPID, "err", derr)
			}
			return nil, fmt.Errorf("%w: the playlist is gone", errToolPermanent)
		}
		return nil, err
	}
	b, err := l.db.PlaylistSourceFor(ctx, string(pl.PID))
	if errors.Is(err, wdb.ErrNotFound) {
		return nil, fmt.Errorf("%w: the binding was removed", errToolPermanent)
	}
	if err != nil {
		return nil, err
	}
	now := time.Now().UnixNano()
	if err := l.db.RecordPlaylistSyncAttempt(ctx, string(pl.PID), now); err != nil {
		l.log.Warn("recording playlist sync attempt", "playlist", pl.PID, "err", err)
	}
	out, rerr := l.reconcilePlaylistSource(ctx, t, uc, pl, b, false)
	if rerr != nil {
		permanent := errors.Is(rerr, errToolPermanent) || kindIsPermanent(KindOf(classify(rerr)))
		// One recorded failure per run, not per attempt: the task
		// worker retries a transient failure up to its attempts budget,
		// and charging each attempt would reach disable-after-ten in
		// four runs against the ten the constant promises. The run's
		// first attempt is the one that records - exactly once per run,
		// whatever the retries behind it do - and the rest only log.
		if t.Attempts <= 1 {
			st, ferr := l.db.RecordPlaylistSyncFailure(ctx, string(pl.PID), rerr.Error(), time.Now().UnixNano(), playlistSyncDisableAfter)
			if ferr != nil {
				l.log.Warn("recording playlist sync failure", "playlist", pl.PID, "err", ferr)
			} else if st.Disabled && st.ConsecutiveFailures == playlistSyncDisableAfter {
				// == and not >=: the notification fires once, on the edge.
				l.notifyPlaylistSyncDisabled(ctx, uc.ID, pl)
			}
		} else {
			l.log.Warn("playlist sync attempt failed; the task will retry", "playlist", pl.PID, "attempt", t.Attempts, "err", rerr)
		}
		if permanent {
			return out.entryIDs, fmt.Errorf("%w: %v", errToolPermanent, rerr)
		}
		return out.entryIDs, rerr
	}
	if out.conflicted {
		// The owner edited the playlist while the run computed; the
		// replace backed off whole and nothing is wrong with the
		// source. The next scheduled run retries against the fresh
		// membership. Trashed members detached before the backoff are
		// a real write and say so.
		t.Summary = marshalJSON(map[string]any{"conflicted": true, "detached": out.detached})
		l.log.Info("playlist sync backed off a concurrent edit", "playlist", pl.PID, "detached", out.detached)
		return out.entryIDs, nil
	}
	if err := l.db.RecordPlaylistSyncSuccess(ctx, string(pl.PID), time.Now().UnixNano(), out.counts); err != nil {
		l.log.Warn("recording playlist sync success", "playlist", pl.PID, "err", err)
	}
	t.Summary = marshalJSON(map[string]any{
		"added": out.counts.Added, "removed": out.counts.Removed,
		"trashed": out.counts.Trashed, "queued": out.counts.Queued,
		"unavailable": out.counts.Unavailable, "missing": out.counts.Missing,
	})
	if out.counts.Added+out.counts.Removed+out.counts.Trashed > 0 {
		l.notifyPlaylistSynced(ctx, uc.ID, pl, out.counts)
	}
	return out.entryIDs, nil
}

// validatePlaylistSourceSettings checks the shape of an update: which
// form it takes, the mode vocabulary, and the interval set.
func validatePlaylistSourceSettings(in PlaylistSourceUpdateDTO) error {
	switch in.Mode {
	case playlistSyncModeAppend, playlistSyncModeMirror, playlistSyncModeMirrorTrash:
	default:
		return errInvalid("mode must be append, mirror, or mirror-trash")
	}
	live := strings.TrimSpace(in.URL) != ""
	matched := in.Source != "" || in.Payload != "" || len(in.Refs) > 0
	switch {
	case live && matched:
		return errInvalid("bind either a url or a source export, not both")
	case live:
		if !playlistSyncIntervals[in.IntervalHours] {
			return errInvalid("intervalHours must be 1, 3, 6, 12, or 24")
		}
	case matched:
		if in.Source == "" {
			return errInvalid("a source export needs its source named")
		}
		if in.IntervalHours != 0 {
			return errInvalid("a matched source syncs on demand only; no interval")
		}
		if in.Mode == playlistSyncModeMirrorTrash {
			return errInvalid("a matched source downloads nothing and never removes files; append or mirror only")
		}
	default:
		return errInvalid("bind a url or a source export")
	}
	return nil
}

// buildPlaylistSourceRow turns a validated update into the stored row.
// resolveLive probes a live source over the network for its identity,
// title, and cover; a preview skips it, since the reconcile that
// follows enumerates anyway.
func (l *Library) buildPlaylistSourceRow(ctx context.Context, pl *model.Playlist, in PlaylistSourceUpdateDTO, resolveLive bool) (wdb.PlaylistSourceRow, error) {
	now := time.Now().UnixNano()
	row := wdb.PlaylistSourceRow{
		PlaylistPID: string(pl.PID),
		Mode:        in.Mode,
		CreatedAtNS: now,
		UpdatedAtNS: now,
	}
	if strings.TrimSpace(in.URL) != "" {
		if !l.hasPlaylistSnapshotter() {
			return row, &Error{Kind: KindUnsupported, Msg: "no acquisition source is running; start the server with WAXDECK_YOUTUBE=true to sync from URLs"}
		}
		parsed, err := url.Parse(strings.TrimSpace(in.URL))
		if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
			return row, errInvalid("url must be an http or https URL")
		}
		if err := l.guardAcquireHost(ctx, parsed.Hostname()); err != nil {
			return row, err
		}
		row.Live = true
		// The label a prospective (unprobed) binding assumes, so a
		// preview's map reads still land; the bind probe below
		// replaces it with the answering provider's own.
		row.Source = l.firstSnapshotterSourceType()
		row.URL = parsed.String()
		row.IntervalHours = in.IntervalHours
		if resolveLive {
			// The cheap probe: identity, title, and the cover the
			// bind-time rung stores - and, by probing, the provider
			// whose source label the binding records. A URL that is
			// not a playlist any provider knows fails here, before
			// anything is stored.
			provider, snap, err := l.playlistSnapshotFor(ctx, row.URL, syncsource.SnapshotOptions{MaxEntries: 8, EnrichLimit: 4})
			if err != nil {
				if KindOf(err) != "" {
					return row, err
				}
				return row, errInvalid("the url does not enumerate as a playlist: " + err.Error())
			}
			row.Source = string(provider.SourceType())
			row.IdentityKey = snap.IdentityKey
			row.SourceID = snap.ID
			row.Title = snap.Title
			row.CoverURL = snap.CoverURL
		}
		return row, nil
	}
	refs, _, err := parsePlaylistExport(in.Source, in.Payload, in.Refs)
	if err != nil {
		return row, err
	}
	row.Source = in.Source
	row.RefsJSON = marshalJSON(refs)
	return row, nil
}

// playlistSourceDTO maps a stored row onto the API shape.
func playlistSourceDTO(b wdb.PlaylistSourceRow) PlaylistSourceDTO {
	out := PlaylistSourceDTO{
		Source:              b.Source,
		URL:                 b.URL,
		Title:               b.Title,
		Live:                b.Live,
		Mode:                b.Mode,
		IntervalHours:       b.IntervalHours,
		Disabled:            b.Disabled,
		ConsecutiveFailures: b.ConsecutiveFailures,
		LastError:           b.LastError,
		LastAttemptNS:       b.LastAttemptNS,
		LastSyncedNS:        b.LastSyncedNS,
		HasRun:              b.LastSyncedNS > 0,
		LastCounts:          b.LastCounts,
	}
	if b.RefsJSON != "" {
		var refs []PortableRefDTO
		if json.Unmarshal([]byte(b.RefsJSON), &refs) == nil {
			out.RefCount = len(refs)
		}
	}
	return out
}

// syncedSourceEntry is one source entry as the reconciler sees it:
// identity, order, and what the library holds for it.
type syncedSourceEntry struct {
	id          string
	title       string
	fetchURL    string // "" for matched refs
	unavailable bool
	pending     bool
	rejected    bool      // a person discarded its download in review
	pid         model.PID // resolved item, "" when none
}

// reconcilePlaylistSource is the one reconciler both preview and sync
// run: enumerate (or re-match), verify the map, compute the mode's
// target membership, and - unless dryRun - replace, trash, and queue
// downloads. dryRun writes nothing at all.
func (l *Library) reconcilePlaylistSource(ctx context.Context, t *wdb.ToolTask, uc *UserCtx, pl *model.Playlist, b wdb.PlaylistSourceRow, dryRun bool) (playlistSyncOutcome, error) {
	var out playlistSyncOutcome
	apiPlaylistPID := apiPID(PrefixPlaylist, pl.PID)
	if !dryRun && t == nil {
		// Defense in depth: every non-dry caller is a task run, and the
		// download step keys on the task - a nil-task live call would
		// replace membership while silently downloading nothing.
		return out, errors.New("a live reconcile needs its task")
	}

	states, err := l.db.PlaylistSourceEntryStates(ctx, string(pl.PID))
	if err != nil {
		return out, &Error{Kind: KindInternal, Err: err}
	}

	var (
		entries      []syncedSourceEntry
		mapRows      map[string]wdb.PlaylistSourceMapRow
		views        map[model.PID]*model.ItemView
		provider     source.Provider
		sourceTitle  string
		sourceCover  string
		missingCount int
		misses       []ImportMiss
	)
	if b.Live {
		var snap *syncsource.PlaylistSnapshot
		provider, snap, err = l.playlistSnapshotFor(ctx, b.URL, syncsource.SnapshotOptions{MaxEntries: playlistSyncMaxEntries})
		if err != nil {
			return out, err
		}
		// A truncated listing is a window, not the playlist. Append only
		// ever adds, so acting on the window is safe; the mirror modes
		// remove and trash whatever the window does not show, which on a
		// 250-entry source means dropping real members - and, one step
		// worse, adding a video at the top slides the window and trashes
		// another track every run. Refuse instead.
		if snap.Truncated && b.Mode != playlistSyncModeAppend {
			return out, fmt.Errorf("the source lists more than %d entries; a truncated listing cannot be mirrored safely", playlistSyncMaxEntries)
		}
		// The degenerate cousin: an enumeration that answered cleanly
		// with nothing, on a binding that has synced before (a playlist
		// turned private, a rate-limited page served empty). Mirroring
		// it would empty the playlist and trash every attached file on
		// one bad answer. A source the owner really emptied stays
		// refusable here - emptying the playlist by hand or unbinding
		// is one deliberate action, where this path runs unattended.
		if len(snap.Entries) == 0 && len(states) > 0 && b.Mode != playlistSyncModeAppend {
			return out, errors.New("the source listed no entries; refusing to empty a synced playlist on an empty answer")
		}
		sourceTitle, sourceCover = snap.Title, snap.CoverURL
		// The map is read for the snapshot's entries plus every entry
		// the per-playlist state still remembers, so an entry that left
		// the source can still name the item mirror-trash owes a trash.
		idSet := map[string]bool{}
		ids := make([]string, 0, len(snap.Entries)+len(states))
		for _, e := range snap.Entries {
			if !idSet[e.ID] {
				idSet[e.ID] = true
				ids = append(ids, e.ID)
			}
		}
		for id := range states {
			if !idSet[id] {
				idSet[id] = true
				ids = append(ids, id)
			}
		}
		mapRows, err = l.db.PlaylistSourceMapFor(ctx, b.Source, ids)
		if err != nil {
			return out, &Error{Kind: KindInternal, Err: err}
		}
		views, err = l.verifySourceMap(ctx, b.Source, mapRows, dryRun)
		if err != nil {
			return out, err
		}
		for _, se := range snap.Entries {
			e := syncedSourceEntry{
				id:          se.ID,
				title:       se.Title,
				fetchURL:    se.URL,
				unavailable: se.Unavailable,
			}
			if m, ok := mapRows[se.ID]; ok {
				switch {
				case m.ItemPID != "":
					e.pid = model.PID(m.ItemPID)
				default:
					switch l.sourceDownloadState(ctx, b.Source, se.ID, m, dryRun) {
					case syncDownloadPending:
						e.pending = true
					case syncDownloadRejected:
						// A person discarded the download in review.
						// That is a decision about the content, so the
						// entry is tombstoned for this playlist rather
						// than downloaded again every interval.
						e.rejected = true
					}
				}
			}
			entries = append(entries, e)
		}
	} else {
		var refs []PortableRefDTO
		if err := json.Unmarshal([]byte(b.RefsJSON), &refs); err != nil {
			return out, fmt.Errorf("%w: the stored refs do not parse: %v", errToolPermanent, err)
		}
		res, err := l.resolvePlaylistImportRefs(ctx, refs)
		if err != nil {
			return out, err
		}
		var matched []model.PID
		for _, r := range res {
			if r.Rung != model.MatchNone {
				matched = append(matched, r.PID)
			}
		}
		views, err = l.itemViewsByPID(ctx, matched)
		if err != nil {
			return out, err
		}
		for i, r := range res {
			e := syncedSourceEntry{
				id:    fmt.Sprintf("ref-%d", i),
				title: refs[i].Title,
			}
			if r.Rung != model.MatchNone && views[r.PID] != nil {
				e.pid = r.PID
			} else {
				missingCount++
				misses = append(misses, ImportMiss{
					Artist: refs[i].Artist, Title: refs[i].Title,
					Album: refs[i].Album, DurationMs: refs[i].DurationMs,
				})
			}
			entries = append(entries, e)
		}
	}

	// Current membership, archived members included: the catalog keeps
	// trashed members in place, and they are exactly what the replace
	// guard refuses over, so they are detached first below.
	stored, err := l.lib.Playlists().Items(ctx, pl.PID, pl.OwnerPID)
	if err != nil {
		return out, classify(err)
	}
	if views == nil {
		views = map[model.PID]*model.ItemView{}
	}
	var currentOrder []model.PID
	var archivedMembers []model.PID
	currentSet := map[model.PID]bool{}
	for _, it := range stored {
		views[it.PID] = it
		currentOrder = append(currentOrder, it.PID)
		currentSet[it.PID] = true
		if archived(it) {
			archivedMembers = append(archivedMembers, it.PID)
		}
	}

	// Per-entry dispositions, in source order. An entry attaches as
	// "attached" only when this playlist's own sync queued its download
	// (the fetching record below) - that ownership is what licenses
	// mirror-trash to trash the file later. An entry resolved through
	// the shared map without a fetching record was somebody else's
	// download (a hand acquisition, another binding), so it attaches as
	// "linked": a member like any other, whose file is never this
	// sync's to trash.
	var downloads []acquireItem
	type entryStateWrite struct{ id, state string }
	var toAttach []entryStateWrite // entry ids gaining attached/linked
	var toTombstone []string       // do-not-re-add / do-not-re-download memory
	sourceIDs := map[string]bool{}
	pendingCount, unavailableCount := 0, 0
	var resolvedOrder []model.PID // resolved, live, in source order
	resolvedSet := map[model.PID]bool{}
	for _, e := range entries {
		sourceIDs[e.id] = true
		st := states[e.id]
		inList := st == wdb.PlaylistEntryAttached || st == wdb.PlaylistEntryLinked
		switch {
		case e.pid != "" && archived(views[e.pid]):
			// The owner trashed this one; re-adding it or downloading
			// it again would fight them.
			continue
		case e.pid != "":
			if b.Mode == playlistSyncModeAppend {
				if st == wdb.PlaylistEntryTombstoned {
					continue
				}
				if !currentSet[e.pid] && inList {
					// A sync attached it and it is gone: the owner
					// removed it by hand, so append must not re-add.
					toTombstone = append(toTombstone, e.id)
					continue
				}
			}
			if resolvedSet[e.pid] {
				// The same item twice (a re-uploaded video, a shared
				// recording): membership holds one row per item.
				continue
			}
			resolvedSet[e.pid] = true
			resolvedOrder = append(resolvedOrder, e.pid)
			if !inList {
				state := wdb.PlaylistEntryLinked
				if st == wdb.PlaylistEntryFetching {
					state = wdb.PlaylistEntryAttached
				}
				toAttach = append(toAttach, entryStateWrite{e.id, state})
			}
		case e.rejected:
			toTombstone = append(toTombstone, e.id)
		case e.pending:
			pendingCount++
		case e.unavailable:
			unavailableCount++
		case e.fetchURL != "":
			// Tombstones gate the download arm in every mode: mirror
			// re-adds a hand-removed member by design, but re-adding is
			// membership over an existing item - re-downloading content
			// a review decision discarded is a different act.
			if st == wdb.PlaylistEntryTombstoned {
				continue
			}
			downloads = append(downloads, acquireItem{Title: e.title, URL: e.fetchURL, GUID: e.id})
		}
	}

	// The mode's target membership over a given current order.
	computeTarget := func(current []model.PID) []model.PID {
		if b.Mode == playlistSyncModeAppend {
			var target []model.PID
			for _, pid := range current {
				if !archived(views[pid]) {
					target = append(target, pid)
				}
			}
			for _, pid := range resolvedOrder {
				if !currentSet[pid] {
					target = append(target, pid)
				}
			}
			return target
		}
		return slices.Clone(resolvedOrder)
	}
	target := computeTarget(currentOrder)
	targetSet := map[model.PID]bool{}
	for _, pid := range target {
		targetSet[pid] = true
	}
	addCount, removeCount := 0, 0
	for _, pid := range target {
		if !currentSet[pid] {
			addCount++
		}
	}
	for _, pid := range currentOrder {
		if !targetSet[pid] {
			removeCount++
		}
	}

	// What mirror-trash owes the trash: files this sync's own downloads
	// brought in ("attached", never "linked" - a linked file existed
	// before the sync and is not its to take) whose entries left the
	// source. Computed from the attach records rather than from
	// membership, so a run that replaced but failed before trashing
	// still owes them next time. Only tracks reach the trash here:
	// attach records are only ever written for entries the sync
	// resolved, and those are acquisition tracks.
	var toTrash []model.PID
	var trashEntryIDs []string
	var trashSpentIDs []string // states to drop without trashing
	if b.Live && b.Mode == playlistSyncModeMirrorTrash {
		trashSeen := map[model.PID]bool{}
		for id, st := range states {
			if st != wdb.PlaylistEntryAttached || sourceIDs[id] {
				continue
			}
			m, ok := mapRows[id]
			if !ok || m.ItemPID == "" {
				continue
			}
			pid := model.PID(m.ItemPID)
			// Two entry ids can map to one item (a re-uploaded video, a
			// shared recording). While any surviving entry still
			// resolves the item it stays a member, so trashing it would
			// take a file the source still lists - the gone entry's
			// record is merely spent.
			if resolvedSet[pid] || trashSeen[pid] {
				trashSpentIDs = append(trashSpentIDs, id)
				continue
			}
			it := views[pid]
			if it == nil || archived(it) {
				continue
			}
			trashSeen[pid] = true
			toTrash = append(toTrash, pid)
			trashEntryIDs = append(trashEntryIDs, id)
		}
	}

	out.preview = PlaylistSyncPreviewDTO{
		Entries:       len(entries),
		WouldAdd:      addCount,
		WouldDownload: len(downloads),
		WouldRemove:   removeCount,
		WouldTrash:    len(toTrash),
		Pending:       pendingCount,
		Unavailable:   unavailableCount,
		Missing:       missingCount,
		Misses:        misses,
	}
	out.counts = wdb.PlaylistSyncCounts{
		Added: addCount, Removed: removeCount,
		Unavailable: unavailableCount, Missing: missingCount,
	}
	if dryRun {
		return out, nil
	}

	// The trash arm's permission is re-checked per run, not only at
	// mode selection: a Delete right revoked after the bind must stop
	// the trashing, scheduled runs and sync-now alike.
	if len(toTrash) > 0 && !uc.Admin && !uc.Delete {
		return out, fmt.Errorf("%w: the owner no longer holds the delete right, so mirror-trash cannot move files to the trash", errToolPermanent)
	}

	if b.Live && (sourceTitle != b.Title || sourceCover != b.CoverURL) {
		if err := l.db.SetPlaylistSourceEnumerated(ctx, string(pl.PID), sourceTitle, sourceCover); err != nil {
			l.log.Warn("recording source enumeration", "playlist", pl.PID, "err", err)
		}
	}
	if b.Live {
		l.syncSourcePlaylistCover(ctx, pl, sourceCover)
	}

	membershipChanged := false
	if !slices.Equal(currentOrder, target) {
		// Trashed members block the replace guard by design; the sync
		// detaches them first (they are invisible in every listing
		// already), then rebuilds against the fresh row. The detach is
		// a real membership write, so it announces itself even when the
		// replace behind it then backs off.
		if len(archivedMembers) > 0 {
			for _, pid := range archivedMembers {
				if err := l.lib.Playlists().Remove(ctx, pl.PID, pid); err != nil {
					return out, classify(err)
				}
			}
			out.detached = len(archivedMembers)
			membershipChanged = true
			l.emitPlaylistEvent(ctx, uc, pl.Visibility == model.VisibilityShared, string(pl.PID))
			fresh, err := l.lib.Playlists().Get(ctx, pl.PID)
			if err != nil {
				return out, classify(err)
			}
			pl = fresh
			freshStored, err := l.lib.Playlists().Items(ctx, pl.PID, pl.OwnerPID)
			if err != nil {
				return out, classify(err)
			}
			currentOrder = currentOrder[:0]
			for _, it := range freshStored {
				views[it.PID] = it
				currentOrder = append(currentOrder, it.PID)
			}
			target = computeTarget(currentOrder)
		}
		if !slices.Equal(currentOrder, target) {
			apiPIDs := make([]string, 0, len(target))
			for _, pid := range target {
				it := views[pid]
				if it == nil {
					return out, fmt.Errorf("no view for member %s", pid)
				}
				apiPIDs = append(apiPIDs, itemAPIPID(it))
			}
			base := time.Unix(0, pl.UpdatedAt).UTC()
			if err := l.ReplacePlaylistItems(ctx, uc, apiPlaylistPID, apiPIDs, &base); err != nil {
				if KindOf(err) == KindConflict {
					out.conflicted = true
					if membershipChanged {
						l.refreshPlaylistCover(ctx, pl)
					}
					return out, nil
				}
				return out, err
			}
			membershipChanged = true
		}
	}
	if membershipChanged {
		// The read-path cover sync assumes the caller re-reads the
		// list immediately; a sweeper has no reader, so the grid tile
		// would otherwise show the old mosaic until somebody opened the
		// playlist. A custom or source cover is left alone inside.
		l.refreshPlaylistCover(ctx, pl)
	}

	now := time.Now().UnixNano()
	for _, w := range toAttach {
		if err := l.db.SetPlaylistSourceEntryState(ctx, string(pl.PID), w.id, w.state, now); err != nil {
			l.log.Warn("recording playlist entry attach", "entry", w.id, "err", err)
		}
	}
	for _, id := range toTombstone {
		if err := l.db.SetPlaylistSourceEntryState(ctx, string(pl.PID), id, wdb.PlaylistEntryTombstoned, now); err != nil {
			l.log.Warn("recording playlist entry tombstone", "entry", id, "err", err)
		}
	}
	for _, id := range trashSpentIDs {
		if err := l.db.DeletePlaylistSourceEntryState(ctx, string(pl.PID), id); err != nil {
			l.log.Warn("clearing spent entry state", "entry", id, "err", err)
		}
	}

	if len(toTrash) > 0 {
		if err := l.trashToolItems(ctx, toTrash); err != nil {
			return out, fmt.Errorf("trashing removed entries: %w", err)
		}
		out.counts.Trashed = len(toTrash)
		for _, id := range trashEntryIDs {
			if err := l.db.DeletePlaylistSourceEntryState(ctx, string(pl.PID), id); err != nil {
				l.log.Warn("clearing trashed entry state", "entry", id, "err", err)
			}
		}
	} else if b.Live && b.Mode == playlistSyncModeMirror {
		// Plain mirror keeps the files; the records of entries that
		// left the source are spent (the map still remembers what the
		// entry became, so a return re-attaches without downloading).
		for id, st := range states {
			spent := st == wdb.PlaylistEntryAttached || st == wdb.PlaylistEntryLinked
			if spent && !sourceIDs[id] {
				if err := l.db.DeletePlaylistSourceEntryState(ctx, string(pl.PID), id); err != nil {
					l.log.Warn("clearing spent entry state", "entry", id, "err", err)
				}
			}
		}
	}

	if len(downloads) > 0 {
		user, err := l.db.UserByID(ctx, uc.ID)
		if err != nil {
			return out, fmt.Errorf("%w: the playlist owner's account is gone", errToolPermanent)
		}
		if !user.UploadEnabled && !hasRole(user.Roles, "admin") {
			return out, fmt.Errorf("%w: the playlist owner cannot upload, so new entries cannot be downloaded", errToolPermanent)
		}
		has, err := l.hasManagedDestination(ctx, uc, model.KindTrack)
		if err != nil {
			return out, err
		}
		if !has {
			return out, fmt.Errorf("%w: no managed music library to receive the downloads", errToolPermanent)
		}
		if len(downloads) > acquireMaxItems {
			l.log.Info("playlist sync download batch truncated", "playlist", pl.PID, "want", len(downloads), "cap", acquireMaxItems)
			downloads = downloads[:acquireMaxItems]
		}
		// The fetching record is the ownership claim behind the
		// attach-vs-linked split above: written before the fetch, so
		// even a batch cut short remembers which entries this sync was
		// bringing in itself. A failed fetch leaves the record with no
		// map row, which re-queues the entry next run, still owned.
		for _, d := range downloads {
			if err := l.db.SetPlaylistSourceEntryState(ctx, string(pl.PID), d.GUID, wdb.PlaylistEntryFetching, now); err != nil {
				l.log.Warn("recording playlist entry fetch claim", "entry", d.GUID, "err", err)
			}
		}
		dp := toolTaskParams{
			MediaType:        "music",
			IdentifyDeclined: !l.resolveIdentify(ctx, uc.ID, nil),
		}
		// Per-item fetch failures skip rather than fail the run: one
		// age-gated video past the enrichment budget must not starve
		// the entries behind it forever. A skipped entry has no map
		// row, so the next run simply tries it again.
		entryIDs, staged, skipped, fetchErr, entriesErr := l.fetchAcquireBatch(ctx, t, dp, provider, downloads, user, 95, true)
		out.entryIDs = entryIDs
		out.counts.Queued = staged
		out.counts.Unavailable += skipped
		if entriesErr != nil {
			return out, fmt.Errorf("opening review entries: %w", entriesErr)
		}
		if fetchErr != nil {
			return out, fmt.Errorf("downloading new entries: %d of %d staged before: %w", staged, len(downloads), fetchErr)
		}
	}
	return out, nil
}

// verifySourceMap checks that every resolved map row still names a live
// item, healing moved ones through the essence rung (a merge keeps the
// audio essence, so the portable-ref ladder finds the survivor) and
// forgetting rows nothing resolves, so their entries read as new.
// Returns the item views for everything that resolved, keyed by pid.
func (l *Library) verifySourceMap(ctx context.Context, sourceKind string, mapRows map[string]wdb.PlaylistSourceMapRow, dryRun bool) (map[model.PID]*model.ItemView, error) {
	var pids []model.PID
	for _, m := range mapRows {
		if m.ItemPID != "" {
			pids = append(pids, model.PID(m.ItemPID))
		}
	}
	views, err := l.itemViewsByPID(ctx, pids)
	if err != nil {
		return nil, err
	}
	now := time.Now().UnixNano()
	for id, m := range mapRows {
		if m.ItemPID == "" {
			continue
		}
		if views[model.PID(m.ItemPID)] != nil {
			continue
		}
		healed := false
		if m.Essence != "" {
			if it, _, err := l.lib.ResolveRef(ctx, model.PortableRef{Kind: model.KindTrack, Essence: m.Essence}); err == nil && it != nil {
				m.ItemPID = string(it.PID)
				mapRows[id] = m
				views[it.PID] = it
				healed = true
				if !dryRun {
					if err := l.db.SetPlaylistSourceMapItem(ctx, sourceKind, id, m.ItemPID, m.Essence, now); err != nil {
						l.log.Warn("healing source map row", "entry", id, "err", err)
					}
				}
			}
		}
		if !healed {
			m.ItemPID = ""
			m.UploadID = ""
			mapRows[id] = m
			if !dryRun {
				if err := l.db.DeletePlaylistSourceMap(ctx, sourceKind, id); err != nil {
					l.log.Warn("forgetting dead source map row", "entry", id, "err", err)
				}
			}
		}
	}
	return views, nil
}

// syncDownloadState is what an unresolved map row means for its entry.
type syncDownloadState int

const (
	// syncDownloadGone: the download is gone (upload pruned, expired,
	// reclaimed) with no decision behind it; the entry reads as new.
	syncDownloadGone syncDownloadState = iota
	// syncDownloadPending: staged and waiting - in review, or imported
	// but not yet resolvable. Neither wants a second download; upload
	// retention is the backstop that eventually frees a stuck one.
	syncDownloadPending
	// syncDownloadRejected: a person discarded the download in review.
	// Re-downloading what somebody threw away would refill their queue
	// with the same decision every interval.
	syncDownloadRejected
)

// sourceDownloadState classifies an unresolved map row. A gone or
// rejected row is forgotten so the map stops naming a download that no
// longer exists; the rejected verdict is the caller's cue to tombstone
// the entry for its playlist.
func (l *Library) sourceDownloadState(ctx context.Context, sourceKind, entryID string, m wdb.PlaylistSourceMapRow, dryRun bool) syncDownloadState {
	if m.UploadID == "" {
		return syncDownloadGone
	}
	forget := func() {
		if dryRun {
			return
		}
		if derr := l.db.DeletePlaylistSourceMap(ctx, sourceKind, entryID); derr != nil {
			l.log.Warn("forgetting dead source download", "entry", entryID, "err", derr)
		}
	}
	up, err := l.db.UploadByID(ctx, m.UploadID)
	if err != nil {
		forget()
		return syncDownloadGone
	}
	if up.State == uploadDiscarded {
		forget()
		// A discard with a person behind it is a decision about the
		// content; the janitor's (an expired upload reclaimed, empty
		// DecidedBy) is housekeeping, and the entry downloads again.
		if entry, rerr := l.db.ReviewEntryByID(ctx, up.ReviewEntryID); rerr == nil &&
			entry.Status == reviewDiscarded && entry.DecidedBy != "" {
			return syncDownloadRejected
		}
		return syncDownloadGone
	}
	return syncDownloadPending
}

// itemViewsByPID batch-reads item views by pid, archived items
// included: the reconciler must see a trashed member as "the owner
// removed this", never as "vanished, download it again".
func (l *Library) itemViewsByPID(ctx context.Context, pids []model.PID) (map[model.PID]*model.ItemView, error) {
	out := make(map[model.PID]*model.ItemView, len(pids))
	for start := 0; start < len(pids); start += 400 {
		chunk := pids[start:min(start+400, len(pids))]
		vals := make([]string, len(chunk))
		for i, pid := range chunk {
			vals[i] = string(pid)
		}
		q := query.New(query.EntityItems).
			WhereValues("pid", query.OpIn, query.Values(vals)...).
			Limit(len(chunk)).Build()
		items, err := l.lib.Query(ctx, q, "")
		if err != nil {
			return nil, classify(err)
		}
		for _, it := range items {
			out[it.PID] = it
		}
	}
	return out, nil
}

// syncSourcePlaylistCover stores the source's own thumbnail as the
// playlist cover, preferred over the member mosaic and yielding to a
// user's upload. Best-effort: a fetch failure leaves whatever cover
// stands.
func (l *Library) syncSourcePlaylistCover(ctx context.Context, pl *model.Playlist, coverURL string) {
	rec, err := l.db.PlaylistCoverFor(ctx, string(pl.PID))
	switch {
	case err == nil:
	case errors.Is(err, wdb.ErrNotFound):
		rec = wdb.PlaylistCover{}
	default:
		l.log.Warn("reading playlist cover state", "playlist", pl.PID, "err", err)
		return
	}
	// A user's upload always wins.
	if rec.Origin == wdb.CoverCustom {
		return
	}
	if coverURL == "" {
		// The source lost its thumbnail; hand the slot back to the
		// mosaic rather than serving a stale source cover forever.
		if rec.Origin == wdb.CoverSource {
			l.releaseSourcePlaylistCover(ctx, pl)
		}
		return
	}
	// The fingerprint carries the URL the stored bytes came from, so an
	// unchanged thumbnail costs nothing on every sync.
	if rec.Origin == wdb.CoverSource && rec.Fingerprint == coverURL {
		return
	}
	raw, mime, err := l.fetchSyncedCoverImage(ctx, coverURL)
	if err != nil {
		l.log.Warn("fetching source playlist cover", "playlist", pl.PID, "err", err)
		return
	}
	if err := validateArtworkBytes(raw); err != nil {
		l.log.Warn("unusable source playlist cover", "playlist", pl.PID, "err", err)
		return
	}
	if err := l.lib.SetEntityArt(ctx, model.ArtPlaylist, pl.PID, model.ArtRoleFront, raw, waxbin.ArtEditOptions{
		Lock: model.LockOff, Force: true,
		Source: model.SourceFeed, SourceURL: coverURL,
		Format: waxart.NormalizeFormat(mime),
	}); err != nil {
		l.log.Warn("storing source playlist cover", "playlist", pl.PID, "err", err)
		return
	}
	pl.HasArt = true
	if err := l.db.PutPlaylistCover(ctx, wdb.PlaylistCover{
		PlaylistPID: string(pl.PID),
		Origin:      wdb.CoverSource,
		Fingerprint: coverURL,
		UpdatedAtNS: time.Now().UnixNano(),
	}); err != nil {
		l.log.Warn("recording source cover state", "playlist", pl.PID, "err", err)
	}
}

// releaseSourcePlaylistCover hands a source-origin cover's slot back to
// the mosaic: the provenance row goes, then the regeneration paints
// over the stored image. Any other origin is left exactly as it is.
func (l *Library) releaseSourcePlaylistCover(ctx context.Context, pl *model.Playlist) {
	rec, err := l.db.PlaylistCoverFor(ctx, string(pl.PID))
	if err != nil || rec.Origin != wdb.CoverSource {
		return
	}
	if err := l.db.DeletePlaylistCover(ctx, string(pl.PID)); err != nil {
		l.log.Warn("clearing source cover state", "playlist", pl.PID, "err", err)
		return
	}
	l.refreshPlaylistCover(ctx, pl)
}

// fetchSyncedCoverImage downloads a source thumbnail. HTTPS only (the
// URL comes from the provider, not the user, but an image fetch has no
// business downgrading), bounded, image-typed, and over the hardened
// outbound client: the URL is third-party data, and a redirect must
// not walk the sweeper onto a private address the front door refused.
func (l *Library) fetchSyncedCoverImage(ctx context.Context, rawURL string) ([]byte, string, error) {
	u, err := url.Parse(rawURL)
	if err != nil || u.Scheme != "https" {
		return nil, "", fmt.Errorf("cover url must be https")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, "", err
	}
	resp, err := l.transcriptClient().Do(req)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, "", fmt.Errorf("cover fetch answered %d", resp.StatusCode)
	}
	mime := resp.Header.Get("Content-Type")
	if i := strings.IndexByte(mime, ';'); i >= 0 {
		mime = mime[:i]
	}
	mime = strings.TrimSpace(strings.ToLower(mime))
	if !strings.HasPrefix(mime, "image/") {
		return nil, "", fmt.Errorf("cover fetch answered %q, not an image", mime)
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, playlistCoverMaxBytes+1))
	if err != nil {
		return nil, "", err
	}
	if len(raw) > playlistCoverMaxBytes {
		return nil, "", fmt.Errorf("cover exceeds %d bytes", playlistCoverMaxBytes)
	}
	return raw, mime, nil
}

// notifyPlaylistSynced announces a run that changed the playlist: one
// notification to the owner plus the sync-event marker of the same
// name.
func (l *Library) notifyPlaylistSynced(ctx context.Context, ownerID string, pl *model.Playlist, c wdb.PlaylistSyncCounts) {
	var parts []string
	if c.Added > 0 {
		parts = append(parts, fmt.Sprintf("%d added", c.Added))
	}
	if c.Removed > 0 {
		parts = append(parts, fmt.Sprintf("%d removed", c.Removed))
	}
	if c.Trashed > 0 {
		parts = append(parts, fmt.Sprintf("%d moved to the trash", c.Trashed))
	}
	if c.Queued > 0 {
		parts = append(parts, fmt.Sprintf("%d downloading", c.Queued))
	}
	body := fmt.Sprintf("%q synced from its source: %s.", pl.Name, strings.Join(parts, ", "))
	l.EmitNotificationFor(ctx, "playlist-synced", "Playlist synced", body,
		apiPID(PrefixPlaylist, pl.PID), []string{ownerID})
	l.emitUserEvent(ctx, ownerID, eventPlaylistSynced, apiPID(PrefixPlaylist, pl.PID))
}

// notifyPlaylistSyncDisabled announces the auto-disable edge, once.
func (l *Library) notifyPlaylistSyncDisabled(ctx context.Context, ownerID string, pl *model.Playlist) {
	body := fmt.Sprintf("%q kept failing to sync from its source, so its schedule was suspended. A successful manual sync turns it back on.", pl.Name)
	l.EmitNotificationFor(ctx, "playlist-synced", "Playlist sync suspended", body,
		apiPID(PrefixPlaylist, pl.PID), []string{ownerID})
	l.emitUserEvent(ctx, ownerID, eventPlaylistSynced, apiPID(PrefixPlaylist, pl.PID))
}
