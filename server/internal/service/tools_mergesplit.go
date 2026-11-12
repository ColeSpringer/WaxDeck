package service

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"

	"github.com/colespringer/waxbin"
	waxart "github.com/colespringer/waxbin/art"
	"github.com/colespringer/waxbin/identity"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/trash"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// What a merge, a split or a CUE split does when it runs: the engine job,
// tagging and cataloging its outputs, carrying listeners' positions over,
// trashing the sources, and naming the pieces.

// runBookMerge joins a multi-file book into one chaptered M4B, written
// beside the parts in the book's own library, so who can see it does not
// change.
func (l *Tools) runBookMerge(ctx context.Context, t *wdb.ToolTask, p toolTaskParams) ([]string, error) {
	b, err := l.bookToolFor(ctx, t, &p)
	if err != nil {
		return nil, err
	}
	return b.runOnce(ctx, func(ctx context.Context, ws string) ([]string, error) {
		if err := l.engineUp(); err != nil {
			return nil, err
		}
		bd, err := l.lib.Book(ctx, b.book)
		if err != nil {
			return nil, classify(err)
		}
		// Format aac on purpose: any mix of part codecs merges, and the
		// resolved flat MP4 form is the one that carries the chapter
		// track. The cost is a transcode even when every part is already
		// AAC; the bridge documents the trade. The parts are read where
		// the catalog has them now, which follows a move since the queue.
		jobID, err := l.flowJobs.CreateMergeJob(ctx, b.partPaths(ctx), p.Titles, "aac")
		if err != nil {
			return nil, err
		}
		if _, err := l.pollToolJob(ctx, t, jobID, 1); err != nil {
			return nil, err
		}
		merged := filepath.Join(ws, b.names[0])
		if err := l.flowJobs.DownloadJobResult(ctx, jobID, 0, merged, b.mode); err != nil {
			return nil, err
		}
		// The engine deliberately carries no source tags, so the book's
		// richer identity and its cover are stamped in a post-pass.
		if err := l.tagToolBookFile(ctx, merged, bd, b.label, b.label, 0); err != nil {
			return nil, err
		}
		return []string{merged}, nil
	})
}

// runBookSplit cuts a single-file book at its chapter marks and writes
// the pieces as one multi-file book in the book's own library. The pieces
// bypass the import planner on purpose: its audiobook layout renders one
// title-named destination per book, so a second part of the same book
// always collides and quarantines. They are placed with the multi-part
// folder convention (a folder named for the book, parts ordered by file
// name) and cataloged by a scan of the library.
func (l *Tools) runBookSplit(ctx context.Context, t *wdb.ToolTask, p toolTaskParams) ([]string, error) {
	b, err := l.bookToolFor(ctx, t, &p)
	if err != nil {
		return nil, err
	}
	return b.runOnce(ctx, func(ctx context.Context, ws string) ([]string, error) {
		if err := l.engineUp(); err != nil {
			return nil, err
		}
		bd, err := l.lib.Book(ctx, b.book)
		if err != nil {
			return nil, classify(err)
		}
		jobID, err := l.flowJobs.CreateSplitJob(ctx, b.partPaths(ctx)[0], p.Cuts, "", p.Format)
		if err != nil {
			return nil, err
		}
		outs, err := l.pollToolJob(ctx, t, jobID, len(b.names))
		if err != nil {
			return nil, err
		}
		pieces := make([]string, 0, outs)
		for i := range outs {
			dst := filepath.Join(ws, b.names[i])
			if err := l.flowJobs.DownloadJobResult(ctx, jobID, i, dst, b.mode); err != nil {
				return nil, err
			}
			if err := l.tagToolBookFile(ctx, dst, bd, b.label, b.pieceTitle(i), i+1); err != nil {
				return nil, err
			}
			pieces = append(pieces, dst)
		}
		return pieces, nil
	})
}

// pollToolJob polls one engine job to completion, mirroring the
// task's progress and renewing the lease as it goes. wantOutputs > 0
// asserts the finished output count.
func (l *Tools) pollToolJob(ctx context.Context, t *wdb.ToolTask, jobID string, wantOutputs int) (int, error) {
	lastPct := -1.0
	for {
		state, pct, outs, errMsg, err := l.flowJobs.JobStatus(ctx, jobID)
		if err != nil {
			return 0, err
		}
		switch state {
		case "done":
			if wantOutputs > 0 && outs != wantOutputs {
				return 0, fmt.Errorf("%w: engine job %s produced %d outputs, want %d",
					errToolPermanent, jobID, outs, wantOutputs)
			}
			return outs, nil
		case "queued", "running":
		default:
			if errMsg == "" {
				errMsg = state
			}
			return 0, fmt.Errorf("%w: engine job %s: %s", errToolPermanent, jobID, errMsg)
		}
		// The engine's percent maps onto 0..90; the import and remap
		// tail owns the rest.
		if scaled := pct * 0.9; scaled-lastPct >= 5 {
			lastPct = scaled
			t.ProgressPct = scaled
			if uerr := l.db.UpdateToolTask(ctx, *t); uerr != nil {
				l.log.Warn("recording tool task progress", "task", t.ID, "err", uerr)
			}
			l.notifyToolTaskProgress(ctx, t.ID)
		}
		select {
		case <-ctx.Done():
			return 0, ctx.Err()
		case <-time.After(toolPollInterval):
		}
	}
}

// tagToolBookFile stamps a merge output or split piece with the book's
// identity: album/title, contributors, genre, year, and the cover when
// the catalog resolves one. trackNo > 0 marks a split piece.
func (l *Tools) tagToolBookFile(ctx context.Context, path string, bd *model.BookDetail, album, title string, trackNo int) error {
	doc, err := waxlabel.ParseFile(ctx, path)
	if err != nil {
		return fmt.Errorf("%w: parsing tool output %s: %v", errToolPermanent, filepath.Base(path), err)
	}
	ed := doc.Edit().Set(tag.Album, album).Set(tag.Title, title)
	author := bd.Item.Artist
	if len(bd.Authors) > 0 {
		author = bd.Authors[0]
	}
	if author != "" {
		ed.Set(tag.Artist, author).Set(tag.AlbumArtist, author)
	}
	if len(bd.Narrators) > 0 {
		ed.Set(tag.Narrator, strings.Join(bd.Narrators, "; "))
	}
	if bd.Item.Genre != "" {
		ed.Set(tag.Genre, bd.Item.Genre)
	}
	if bd.Item.Year > 0 {
		ed.Set(tag.RecordingDate, strconv.Itoa(bd.Item.Year))
	}
	if trackNo > 0 {
		ed.Set(tag.TrackNumber, strconv.Itoa(trackNo))
	}
	l.addToolCover(ctx, ed, bd.Item.PID)
	return l.executeToolTagPlan(ctx, ed, path)
}

// tagToolTrackFile stamps one cue split piece from its virtual track's
// metadata.
func (l *Tools) tagToolTrackFile(ctx context.Context, path string, seed *model.ItemView, title, artist string, trackNo int) error {
	doc, err := waxlabel.ParseFile(ctx, path)
	if err != nil {
		return fmt.Errorf("%w: parsing tool output %s: %v", errToolPermanent, filepath.Base(path), err)
	}
	ed := doc.Edit().Set(tag.Title, title).Set(tag.TrackNumber, strconv.Itoa(trackNo))
	if artist != "" {
		ed.Set(tag.Artist, artist)
	}
	if seed.Album != "" {
		ed.Set(tag.Album, seed.Album)
	}
	if aa := firstNonEmpty(seed.AlbumArtist, seed.Artist); aa != "" {
		ed.Set(tag.AlbumArtist, aa)
	}
	if seed.Genre != "" {
		ed.Set(tag.Genre, seed.Genre)
	}
	if seed.Year > 0 {
		ed.Set(tag.RecordingDate, strconv.Itoa(seed.Year))
	}
	l.addToolCover(ctx, ed, seed.PID)
	return l.executeToolTagPlan(ctx, ed, path)
}

// toolCoverRung is the box a non-displayable cover is re-resolved at
// before it goes into a file: [ArtSizeToolCover], the ladder's top
// rung, so the embedded picture is the largest the resolver will
// re-encode rather than a thumbnail.
const toolCoverRung = ArtSizeToolCover

// addToolCover attaches the item's resolved cover art, best effort.
//
// The stored original is what goes in when a player can paint it. When
// it cannot - a TIFF, which the catalog decodes and no player draws -
// the resolve is asked for a rung instead, because a sized resolve
// re-encodes a non-displayable source into one that paints. What comes
// back still unpaintable is an exotic nothing could decode either, and
// that stays out of the file: a frame holding bytes the player renders
// as a broken image is worse than a file with no cover.
//
// Which of the two to ask for is decided before either is asked for.
// `ArtProvenance` answers what a resolve would return without loading
// the picture, and follows the same fallback chain, so the format is a
// row read rather than a stored original - up to sixteen megabytes -
// pulled and decoded only to be thrown away. This runs once per file a
// split writes, so on a library of TIFF covers that discarded read was
// per track.
func (l *Tools) addToolCover(ctx context.Context, ed *waxlabel.Editor, pid model.PID) {
	ref := model.EntityRef{Type: model.ArtTrack, PID: pid}
	prov, err := l.lib.ArtProvenance(ctx, ref, model.ArtRoleFront)
	if err != nil || prov == nil {
		return
	}
	// Zero asks for the stored bytes; a rung asks for the re-encode.
	size := 0
	if !waxart.Displayable(prov.Format) {
		size = toolCoverRung
	}
	blob, err := l.lib.ResolveArt(ctx, ref, model.ArtRoleFront, size)
	if err != nil || blob == nil || len(blob.Bytes) == 0 {
		return
	}
	// Re-checked on what came back rather than trusted from the
	// provenance: a source the resolver could not re-encode comes back
	// as itself, and that is the exotic nothing can decode.
	if !waxart.Displayable(blob.Format) {
		return
	}
	// A cover artMime cannot name (an SVG a provider slipped in) stays
	// out of the file: octet-stream in a picture frame helps nobody.
	mime := artMime(blob.Format)
	if mime == "application/octet-stream" {
		return
	}
	ed.AddPicture(waxlabel.Picture{
		Type: waxlabel.PicFrontCover, MIME: mime,
		Width: blob.Width, Height: blob.Height, Data: blob.Bytes,
	})
}

// writeLanded says whether a SaveBack write reached the file. Committed is
// what answers that, not the error: an error with Committed set is a landed
// write whose post-commit step failed, so the bytes are in place and the plan
// is spent. A clean run with Committed clear is a no-op plan, which writes
// nothing by contract and is not a failure either.
func writeLanded(res waxlabel.SaveResult, err error) bool {
	return err == nil || res.Committed
}

func (l *Tools) executeToolTagPlan(ctx context.Context, ed *waxlabel.Editor, path string) error {
	plan, err := ed.Prepare()
	if err != nil {
		return fmt.Errorf("%w: preparing tags for %s: %v", errToolPermanent, filepath.Base(path), err)
	}
	if _, res, err := plan.Execute(ctx, waxlabel.SaveBack()); err != nil {
		if !writeLanded(res, err) {
			return fmt.Errorf("%w: writing tags to %s: %v", errToolPermanent, filepath.Base(path), err)
		}
		// The tags are on disk and the plan is spent, so wrapping this in
		// errToolPermanent would report a durable success as a dead task.
		l.log.Warn("tool tags written; post-commit step failed",
			"file", filepath.Base(path), "err", err)
	}
	return nil
}

// scanToolOutputs catalogs a book tool's outputs, placed in dir, each by
// its own path, so the scan catalogs them and nothing else, then resolves
// the book they formed: the one holding the first's exact bytes, else the
// original item when the identity key revived it (the kept-originals
// marker changes the key, so the copy stays its own book), else the book
// the (possibly marked) title names. A shutdown or a busy catalog ends it
// as it found it; any other failure comes after the files are in place,
// which no retry should repeat, since their sources may be in the trash.
func (l *Tools) scanToolOutputs(ctx context.Context, dir string, files []string, oldPID model.PID, title string) (model.PID, error) {
	for _, file := range files {
		req := waxbin.ScanRequest{SubPath: file}
		if libPID, err := l.Grants.libraryForPath(ctx, file); err == nil && libPID != "" {
			req.LibraryPID = model.PID(libPID)
		}
		if err := l.scan(ctx, req); err != nil {
			if e := classifyMutation(err); catalogWaits(e) || ctx.Err() != nil {
				return "", e
			}
			return "", l.uncataloged(dir, "and the next scan of the library will catalog them: "+l.failureCause(classify(err).Error()))
		}
	}
	if hash, err := identity.ContentHash(files[0]); err == nil {
		if items, err := l.lib.ItemsByContentHash(ctx, hash); err == nil {
			for _, it := range items {
				if it.Kind == model.KindBook {
					return it.PID, nil
				}
			}
		}
	}
	if bd, err := l.lib.Book(ctx, oldPID); err == nil && len(bd.Files) == len(files) {
		return oldPID, nil
	}
	// Visible books only: the original the run trashed carries the same
	// title and is no answer.
	b := visibleItems().
		Where("kind", query.OpIs, string(model.KindBook)).
		Where("title", query.OpIs, title).Limit(1)
	items, err := l.lib.Query(ctx, b.Build(), "")
	if err != nil {
		if e := classify(err); catalogWaits(e) || ctx.Err() != nil {
			return "", e
		}
		return "", l.uncataloged(dir, "and were scanned, but their book could not be found: "+l.failureCause(classify(err).Error()))
	}
	if len(items) == 0 {
		return "", l.uncataloged(dir, "but the scan made no book of them")
	}
	return items[0].PID, nil
}

// itemFiles is a tool's read of an item's files, or what a test's
// mutateHook answers in its place.
func (l *Tools) itemFiles(ctx context.Context, item model.PID) ([]model.ItemFileRef, error) {
	if l.mutateHook != nil {
		if err := l.mutateHook("files"); err != nil {
			return nil, err
		}
	}
	return l.lib.ItemFiles(ctx, item)
}

// scan is a tool's scan of a library, or what a test's mutateHook
// answers in its place.
func (l *Tools) scan(ctx context.Context, req waxbin.ScanRequest) error {
	if l.mutateHook != nil {
		if err := l.mutateHook("scan"); err != nil {
			return err
		}
	}
	_, err := l.lib.Scan(ctx, req)
	return err
}

// catalogWaits reports whether a catalog failure passes on its own: a
// conflicting job holding the catalog, the catalog suspended for
// maintenance, or the attempt's own deadline or stop.
func catalogWaits(err error) bool {
	switch KindOf(err) {
	case KindCatalogBusy, KindMaintenance:
		return true
	}
	return errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded)
}

// uncataloged is a failure after a tool's files took their names in dir,
// saying what became of them.
func (l *Tools) uncataloged(dir, what string) error {
	return fmt.Errorf("%w: the new files are in %s, %s", errToolPermanent, l.Ingest.scrubStoragePaths(dir), what)
}

// crashPoint is where a test may end a book tool's run, as a crash
// or a shutdown would.
func (l *Tools) crashPoint(step string) error {
	if l.toolStepHook != nil {
		return l.toolStepHook(step)
	}
	return nil
}

// writeErr is a failed write of a tool's output into the library: a
// folder that refused it is the library's to fix, else the server's.
// Nothing was placed, so neither is worth a retry.
func (l *Tools) writeErr(err error) error {
	if cause := l.Roots.storageRefused(err.Error()); cause != "" {
		e := errStorageUnwritable(cause)
		e.Err = errToolPermanent
		return e
	}
	return &Error{Kind: KindInternal, Msg: "writing into the library failed: " + l.failureCause(err.Error()), Err: errToolPermanent}
}

// toolPosition is one account's saved place in an item, with the time
// the catalog last recorded progress there. The carry writes the place
// back at that time rather than now, so a merged or split book keeps
// its rank on the in-progress shelf instead of jumping to the top.
type toolPosition struct {
	positionMS int64
	atNS       int64
}

// collectToolPositions reads every account's saved position for the
// given items; zero positions are omitted.
func (l *Tools) collectToolPositions(ctx context.Context, items []model.PID) map[model.PID]map[model.PID]toolPosition {
	out := map[model.PID]map[model.PID]toolPosition{}
	l.forEachCatalogUser(ctx, func(userPID model.PID) {
		for _, item := range items {
			st, err := l.lib.Playback().State(ctx, userPID, item)
			if err != nil || st == nil || st.PositionMS <= 0 {
				continue
			}
			m := out[userPID]
			if m == nil {
				m = map[model.PID]toolPosition{}
				out[userPID] = m
			}
			m[item] = toolPosition{positionMS: st.PositionMS, atNS: st.LastProgressAt}
		}
	})
	return out
}

// asOf projects a carried position's recorded time onto the catalog's
// as-of argument; a state with no recorded progress stamps now.
func (p toolPosition) asOf() *int64 {
	if p.atNS <= 0 {
		return nil
	}
	return &p.atNS
}

// forEachCatalogUser pages every WaxDeck account and hands the catalog
// user pid of each to fn.
func (l *Tools) forEachCatalogUser(ctx context.Context, fn func(model.PID)) {
	err := l.db.EachUser(ctx, func(u *wdb.User) error {
		if pid := l.Identity.catalogPID(u); pid != "" {
			fn(model.PID(pid))
		}
		return nil
	})
	if err != nil {
		l.log.Warn("listing users for position carry-over", "err", err)
	}
}

// ripFileOf answers the file a carved track plays a window of.
func (l *Tools) ripFileOf(ctx context.Context, track model.PID) (model.PID, error) {
	files, err := l.lib.ItemFiles(ctx, track)
	if err != nil {
		return "", classify(err)
	}
	for _, f := range files {
		if f.Virtual && f.Role == fileRolePrimary {
			return f.FilePID, nil
		}
	}
	return "", &Error{Kind: KindConflict, Err: errToolPermanent, Msg: "the track is no longer cut from a rip"}
}

// cueRip answers the file a carved track plays a window of and every
// track the catalog carves from it, in start order, which a delete plan of
// that file lists.
func (l *Tools) cueRip(ctx context.Context, seed *model.ItemView) (model.PID, []*model.ItemView, error) {
	file, err := l.ripFileOf(ctx, seed.PID)
	if err != nil {
		return "", nil, err
	}
	plan, err := l.lib.PlanDeleteFiles(ctx, []model.PID{file}, model.DeleteTrash)
	if err != nil {
		return "", nil, classify(err)
	}
	var pids []model.PID
	for _, a := range plan.Actions {
		pids = append(pids, a.Tracks...)
	}
	items, err := l.lib.GetMany(ctx, pids)
	if err != nil {
		return "", nil, classify(err)
	}
	byPID := map[model.PID]*model.ItemView{}
	for _, it := range items {
		if it != nil {
			byPID[it.PID] = it
		}
	}
	sibs := make([]*model.ItemView, 0, len(pids))
	for _, pid := range pids {
		if it := byPID[pid]; it != nil {
			sibs = append(sibs, it)
		}
	}
	return file, sibs, nil
}

// trashRip moves a cue rip's file to the catalog's trash with the tracks
// it carves as they stand now, under the cue split's reason.
func (l *Tools) trashRip(ctx context.Context, file model.PID) error {
	plan, err := l.lib.PlanDeleteFiles(ctx, []model.PID{file}, model.DeleteTrash, waxbin.DeleteReason(taskTypeCueSplit))
	if err != nil {
		return classify(err)
	}
	if _, e := l.applyToolTrash(ctx, plan); e != nil {
		e.Msg += ", so the rip stays beside the tracks split from it"
		return e
	}
	return nil
}

// trashSyncedItems moves the tracks a mirror sync dropped to the trash
// and answers the items a file of which stayed: a run that moved nothing
// and failed is refused as a delete is, and a file the plan skips (a copy
// a read-only library holds, one under no known root) keeps its item, as
// a delete leaves one.
func (l *Tools) trashSyncedItems(ctx context.Context, pids []model.PID) (map[model.PID]bool, error) {
	plan, err := l.lib.PlanDeletePIDs(ctx, pids, model.DeleteTrash)
	if err != nil {
		return nil, classify(err)
	}
	rep, stayedFiles, err := l.applyDeletion(ctx, plan)
	if err != nil {
		return nil, err
	}
	if refused := l.deletionRefused(plan, rep, stayedFiles); refused != nil {
		return nil, refused
	}
	stayed := map[model.PID]bool{}
	for _, a := range plan.Actions {
		if _, ok := stayedFiles[a.FilePID]; ok || a.Skip {
			stayed[a.ItemPID] = true
		}
	}
	return stayed, nil
}

// applyToolTrash applies a tool's trash plan and answers how many files
// went, or why one stayed, which ends the task: a file that stayed would
// join what the tool writes beside it as one more part of the same book.
// A plan that would leave a file refuses before anything moves. The run
// is not cut short between files, which would move files no failure then
// names.
func (l *Tools) applyToolTrash(ctx context.Context, plan *trash.Plan) (int, *Error) {
	for _, a := range plan.Actions {
		if a.Skip {
			return 0, &Error{Kind: KindConflict, Err: errToolPermanent,
				Msg: fmt.Sprintf("%s would stay where it is (%s)", libraryPath(a), a.Reason)}
		}
	}
	rep, stayed, err := l.applyDeletion(ctx, plan)
	if err != nil {
		// A busy or suspended catalog refused the run before it moved
		// anything, which a later attempt gets past.
		e := &Error{Kind: KindOf(err), Msg: "the move to the trash failed: " + l.failureCause(err.Error()), Err: err}
		if !catalogWaits(err) {
			e.Err = errToolPermanent
		}
		return 0, e
	}
	if len(stayed) == 0 {
		return rep.Trashed, nil
	}
	first, cause := "", ""
	for _, a := range plan.Actions {
		if why, ok := stayed[a.FilePID]; ok {
			first, cause = libraryPath(a), why
			break
		}
	}
	kind := KindInternal
	switch refusal := storageRefusal(cause); {
	case refusal != "":
		kind, cause = KindStorageUnwritable, refusal
	case cause == "library is read-only":
		kind = KindReadOnly
	case strings.HasPrefix(cause, "the cue rip's tracks changed"):
		kind = KindConflict
	}
	return rep.Trashed, &Error{Kind: kind, Err: errToolPermanent, Msg: fmt.Sprintf(
		"%d of %d files could not be moved to the trash (%s: %s)", len(stayed), len(plan.Actions), first, cause)}
}

// chapterTitle falls back to a generated name for an unnamed chapter.
func chapterTitle(title string, index int) string {
	if strings.TrimSpace(title) != "" {
		return title
	}
	return fmt.Sprintf("Chapter %d", index+1)
}

// toolSplitFormat picks the engine output format that keeps a split as
// faithful as possible: the source codec when the engine can write it,
// else FLAC (lossless in the decoded samples for any source).
//
// WavPack and Monkey's Audio are here even though neither streams: a
// split is a job that writes a file, and APE's want of a live form only
// rules it out of the delivery ladder.
func toolSplitFormat(codec string) string {
	switch c := strings.ToLower(codec); c {
	case "flac", "alac", "aac", "mp3", "opus", "wav", "wavpack", "ape":
		return c
	default:
		return "flac"
	}
}

// toolSplitExt is the file extension a split piece takes for one output
// format. Most format names are the extension, but not all - WavPack
// writes .wv - and a piece named for the format instead lands outside
// the scanner's extension set, so the import that follows finds nothing
// and the whole job fails permanently after encoding every piece.
//
// The mp4 family is the other exception, in the other direction: aac
// and alac pieces of a book take .m4b so the rescan classifies them as
// audiobook parts. Callers splitting a track pass that off.
func toolSplitExt(format string, mp4AsBook bool) string {
	if mp4AsBook && (format == "aac" || format == "alac") {
		return "m4b"
	}
	switch format {
	case "wavpack":
		return "wv"
	default:
		return format
	}
}

// ownCueSheet is the sheet of a rip's own name beside it, the only one
// the catalog carves the rip by, and whether it is there.
func ownCueSheet(rip string) (string, bool) {
	cue := strings.TrimSuffix(rip, filepath.Ext(rip)) + ".cue"
	_, err := os.Stat(cue)
	return cue, err == nil
}

// safeFileName keeps a display title usable as a file name.
func safeFileName(s string) string {
	s = strings.Map(func(r rune) rune {
		switch r {
		case '/', '\\', ':', '*', '?', '"', '<', '>', '|':
			return '_'
		}
		if r < 0x20 {
			return -1
		}
		return r
	}, s)
	s = strings.TrimSpace(s)
	if s == "" {
		return "untitled"
	}
	const maxName = 120
	if len(s) > maxName {
		s = s[:maxName]
	}
	return s
}
