package service

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/inbox"
	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// A CUE split cuts a rip at its sheet's boundaries into pieces in its
// workspace, imports them as real tracks, and then retires the rip. It
// holds the book tools' invariants: one live split per rip, the lease
// held the whole run, from the cut on a resumable task that waits out
// what passes (for up to toolWaitCap), and parked when its runs keep
// ending with the server. The task records each step before the run
// takes it - the pieces cut, then where the import puts each and the
// audio of each, then the tracks it made, then the rip's trash - so a
// rerun imports no piece twice, and the rip goes only once every piece
// is a track of the catalog.

const (
	// cueStepImporting: the import may have landed pieces at their
	// recorded PieceDests.
	cueStepImporting = "importing"
	// cueStepImported: every piece is a track, PiecePIDs.
	cueStepImported = "imported"
	// cueStepRetired: the rip is in the trash, or stays by request.
	cueStepRetired = "retired"
)

// cueSplit is a CUE split as its task orders it.
type cueSplit struct {
	toolRun
	// seed is the carved track the split was started from.
	seed model.PID
}

// runCueSplit splits a shared album rip into one real file per virtual
// track, from wherever an earlier attempt left it.
func (l *Library) runCueSplit(ctx context.Context, t *wdb.ToolTask, p toolTaskParams) ([]string, error) {
	_, seed, ok := parseAPIPID(t.ItemPID)
	if !ok {
		return nil, fmt.Errorf("%w: bad item pid %q", errToolPermanent, t.ItemPID)
	}
	c := &cueSplit{toolRun: toolRun{l, t, &p}, seed: seed}
	if err := c.begin(ctx, c.whereLeft); err != nil {
		if !errors.Is(err, errToolParked) && c.t.Resumable {
			return nil, c.wait(ctx, err)
		}
		return nil, err
	}
	results, err := c.run(ctx)
	c.end(ctx)
	var wait *toolRetry
	if err != nil && !errors.As(err, &wait) && permanentToolErr(err) {
		// Nothing more comes of the workspace once the run ends for good.
		os.RemoveAll(c.workspace())
	}
	return results, err
}

// run takes the split from wherever an earlier attempt left it.
func (c *cueSplit) run(ctx context.Context) ([]string, error) {
	for {
		var err error
		switch c.p.Step {
		case "":
			err = c.cut(ctx)
		case toolStepStaged, cueStepImporting:
			err = c.importPieces(ctx)
		case cueStepImported, toolStepTrashing:
			err = c.retire(ctx)
		case cueStepRetired:
			return c.complete(ctx)
		default:
			return nil, fmt.Errorf("%w: the task records an unknown step %q", errToolPermanent, c.p.Step)
		}
		if err != nil {
			return nil, err
		}
	}
}

// dest is where the import puts the ith piece, as recorded, or "".
func (c *cueSplit) dest(i int) string {
	if i < len(c.p.PieceDests) {
		return c.p.PieceDests[i]
	}
	return ""
}

// workspace is where the split cuts its pieces, outside the library.
func (c *cueSplit) workspace() string {
	return filepath.Join(c.l.stagingDir, "tools", c.t.ID)
}

// piecePath is where the ith piece waits in the workspace.
func (c *cueSplit) piecePath(i int) string {
	return filepath.Join(c.workspace(), c.p.PieceNames[i])
}

// wait waits out a failure that should pass, unless the run has waited
// toolWaitCap already, when it ends the task with the rip kept.
func (c *cueSplit) wait(ctx context.Context, err error) error {
	if c.waitedOut() {
		e := &Error{Kind: KindInternal, Err: errToolPermanent,
			Msg: fmt.Sprintf("gave up waiting after %s (%s)", toolWaitCap, toolFailure(err).Msg)}
		if where := c.whereLeft(ctx); where != "" {
			e.Msg += "; " + where
		} else {
			e.Msg += ", so nothing was written"
		}
		return e
	}
	return c.toolRun.wait(ctx, err)
}

// whereLeft says what of the split is in the library: the tracks it made
// and the folder they are in, and the rip, which stays unless the split's
// trash took it.
func (c *cueSplit) whereLeft(ctx context.Context) string {
	made, folder := 0, ""
	for i, pid := range c.p.PiecePIDs {
		if pid != "" {
			made++
			if folder == "" && c.dest(i) != "" {
				folder = c.l.scrubStoragePaths(filepath.Dir(c.dest(i)))
			}
		}
	}
	if made == 0 {
		return ""
	}
	rip := "the rip stays, with every track it carves,"
	if c.p.Step == toolStepTrashing || c.p.Step == cueStepRetired {
		if _, err := c.l.lib.File(ctx, model.PID(c.p.SrcFilePID)); KindOf(classify(err)) == KindNotFound {
			rip = "the rip went to the trash,"
		}
	}
	said := fmt.Sprintf("%s beside the %d of %d tracks split from it", rip, made, len(c.p.PieceNames))
	if folder != "" {
		said += " in " + folder
	}
	return said
}

// cut has the engine cut the rip and tags each piece from the track it
// becomes, in the workspace, then records the pieces and the run
// resumable from here on.
func (c *cueSplit) cut(ctx context.Context) error {
	if err := c.cutPieces(ctx); err != nil {
		return c.cutFailed(ctx, err)
	}
	return c.l.toolCrashPoint("staged")
}

// cutFailed is a cut that failed. The engine away is waited out, and so
// is any failure that passes once tracks of the split may be in the
// library (the import sends a split back to cutting); a refusal that
// stands then ends it saying what of it the library holds.
func (c *cueSplit) cutFailed(ctx context.Context, err error) error {
	switch {
	case engineAwayErr(err), c.t.Resumable && !permanentToolErr(err) && ctx.Err() == nil:
		return c.wait(ctx, err)
	case c.t.Resumable && permanentToolErr(err):
		if where := c.whereLeft(ctx); where != "" {
			return &Error{Kind: KindInternal, Err: errToolPermanent, Msg: toolFailure(err).Msg + "; " + where}
		}
	}
	return err
}

// locate records where the catalog has the rip now, and its sheet when a
// move since the split was queued took that along: the sheet of the rip's
// own name, the only one the catalog carves the rip by. A rip the catalog
// no longer has keeps what was recorded, and so does one moved without its
// sheet.
func (c *cueSplit) locate(ctx context.Context) {
	src := c.l.pathsNow(ctx, []string{c.p.SrcFilePID}, []string{c.p.SrcPath})[0]
	if src == c.p.SrcPath {
		return
	}
	c.p.SrcPath = src
	if cue, ok := ownCueSheet(src); ok {
		c.p.CuePath = cue
	}
}

// cutPieces is the cut: the engine's pieces, tagged, in the workspace,
// and the run recorded resumable.
func (c *cueSplit) cutPieces(ctx context.Context) error {
	if err := c.l.toolEngineUp(); err != nil {
		return err
	}
	seed, err := c.l.lib.Get(ctx, c.seed)
	if err != nil {
		return classify(err)
	}
	_, sibs, err := c.l.cueRip(ctx, seed)
	if err != nil {
		return err
	}
	c.locate(ctx)
	jobID, err := c.l.flowJobs.CreateSplitJob(ctx, c.p.SrcPath, nil, c.p.CuePath, c.p.Format)
	if err != nil {
		return err
	}
	outs, err := c.l.pollToolJob(ctx, c.t, jobID, 0)
	if err != nil {
		return err
	}
	if outs != len(sibs) {
		// Tag what aligns and log the mismatch rather than failing a
		// finished cut; the extra pieces get generated names.
		c.l.log.Warn("cue split piece count differs from virtual tracks",
			"task", c.t.ID, "pieces", outs, "tracks", len(sibs))
	}
	ws, err := c.l.toolWorkspace(c.t.ID)
	if err != nil {
		return err
	}
	album := safeFileName(firstNonEmpty(seed.Album, "Split Album"))
	if err := os.MkdirAll(filepath.Join(ws, album), 0o755); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	// The pieces read as the rip did.
	mode := fileModeBeside(c.p.SrcPath)
	names := make([]string, 0, outs)
	for i := range outs {
		title := fmt.Sprintf("Track %02d", i+1)
		trackNo := i + 1
		artist := seed.Artist
		if i < len(sibs) {
			title = firstNonEmpty(sibs[i].Title, title)
			if sibs[i].TrackNo > 0 {
				trackNo = sibs[i].TrackNo
			}
			artist = firstNonEmpty(sibs[i].Artist, artist)
		}
		name := filepath.Join(album, fmt.Sprintf("%02d - %s.%s", i+1, safeFileName(title), toolSplitExt(c.p.Format, false)))
		dst := filepath.Join(ws, name)
		if err := c.l.flowJobs.DownloadJobResult(ctx, jobID, i, dst, mode); err != nil {
			return err
		}
		if err := c.l.tagToolTrackFile(ctx, dst, seed, title, artist, trackNo); err != nil {
			return err
		}
		names = append(names, name)
	}
	c.p.PieceNames = names
	if err := c.l.db.MarkToolTaskResumable(context.WithoutCancel(ctx), c.t.ID); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	// The drain decides from the task it leased, not the row.
	c.t.Resumable = true
	return c.mark(ctx, toolStepStaged)
}

// importPieces imports the pieces not tracks yet and makes each piece's
// track known. A piece an earlier import landed is found at its recorded
// place, a track of the catalog, and not imported again; a piece neither
// landed nor in the workspace any more sends the run back to cutting,
// which the rip still allows, keeping the record of what landed. Only
// once every piece is a track does the run go on to the rip.
func (c *cueSplit) importPieces(ctx context.Context) error {
	n := len(c.p.PieceNames)
	pids := make([]model.PID, n)
	var rest []int
	for i := range n {
		pid, err := c.landed(ctx, i)
		if err != nil {
			return c.wait(ctx, err)
		}
		if pid != "" {
			pids[i] = pid
			// A copy cut again after it landed is not imported twice.
			os.Remove(c.piecePath(i))
			continue
		}
		if !onDisk(c.piecePath(i)) {
			c.p.Step, c.p.Waits = "", 0
			if err := c.save(ctx); err != nil {
				return c.wait(ctx, err)
			}
			return nil
		}
		rest = append(rest, i)
	}
	if len(rest) > 0 {
		missing, standing, err := c.importRest(ctx, rest, pids)
		if err != nil {
			return err
		}
		c.recordTracks(pids)
		if len(missing) > 0 {
			// The rip stays, and with it every track it carves, until each
			// piece is a track: the rerun imports the rest.
			if err := c.save(ctx); err != nil {
				c.l.log.Warn("recording a cue split's tracks", "task", c.t.ID, "err", err)
			}
			if standing {
				// Nothing waiting would land them: the import's plan
				// refused each for good.
				e := &Error{Kind: KindConflict, Err: errToolPermanent, Msg: fmt.Sprintf(
					"%d of %d pieces cannot become tracks (%s)", len(missing), n, strings.Join(missing, "; "))}
				if where := c.whereLeft(ctx); where != "" {
					e.Msg += "; " + where
				} else {
					e.Msg += ", so the rip stays as it was"
				}
				return e
			}
			why := fmt.Errorf("%d of %d pieces did not become tracks (%s); the rip stays, and the split tries them again",
				len(missing), n, strings.Join(missing, "; "))
			if slices.ContainsFunc(missing, refusedReadOnly) {
				// Waited out as the flag it is.
				return c.wait(ctx, &Error{Kind: KindReadOnly, Msg: why.Error()})
			}
			return c.wait(ctx, why)
		}
	}
	c.recordTracks(pids)
	if err := c.mark(ctx, cueStepImported); err != nil {
		return c.wait(ctx, err)
	}
	return c.l.toolCrashPoint("imported")
}

// recordTracks records the tracks the pieces became, those known.
func (c *cueSplit) recordTracks(pids []model.PID) {
	c.p.PiecePIDs = make([]string, len(pids))
	for i, pid := range pids {
		c.p.PiecePIDs[i] = string(pid)
	}
}

// importRest imports the pieces rest names, recording where the import
// puts each and the audio of each before it runs, fills the tracks they
// became into pids, and answers the pieces that did not become one, each
// with why, and whether every one of them was refused for good by the
// import's plan, which no wait changes.
func (c *cueSplit) importRest(ctx context.Context, rest []int, pids []model.PID) ([]string, bool, error) {
	dir := filepath.Dir(c.piecePath(rest[0]))
	plan, err := c.l.lib.PlanImport(ctx, waxbin.ImportRequest{Source: dir, DupPolicy: model.DupAllow})
	if err != nil {
		return nil, false, c.wait(ctx, classify(err))
	}
	n := len(c.p.PieceNames)
	if len(c.p.PieceDests) != n || len(c.p.PieceEssences) != n {
		c.p.PieceDests, c.p.PieceEssences = make([]string, n), make([]string, n)
	}
	refused := map[int]string{}
	for _, i := range rest {
		refused[i] = "the import has no place for it"
		for _, a := range plan.Actions {
			if a.Src != c.piecePath(i) {
				continue
			}
			if a.Outcome == inbox.OutcomeImport {
				c.p.PieceDests[i], c.p.PieceEssences[i] = a.Dst, a.Essence
				delete(refused, i)
			} else if a.Reason != "" {
				refused[i] = c.l.scrubStoragePaths(a.Reason)
			}
		}
	}
	if err := c.mark(ctx, cueStepImporting); err != nil {
		return nil, false, c.wait(ctx, err)
	}
	if err := c.l.toolCrashPoint("importing"); err != nil {
		return nil, false, err
	}
	report, err := c.l.toolImport(ctx, plan)
	if err != nil {
		// What landed before the failure is found at its recorded place
		// by the rerun, which imports the rest.
		return nil, false, c.wait(ctx, classifyMutation(err))
	}
	if err := c.l.toolCrashPoint("import"); err != nil {
		return nil, false, err
	}
	failed := map[string]string{}
	for _, f := range report.Failures {
		failed[f.Src] = c.l.failureCause(f.Err)
	}
	var missing []string
	standing := true
	for _, i := range rest {
		if why, ok := refused[i]; ok {
			missing = append(missing, filepath.Base(c.p.PieceNames[i])+": "+why)
			standing = standing && !refusalPasses(why)
			continue
		}
		pid, err := c.landed(ctx, i)
		if err != nil || pid == "" {
			why := cmp.Or(failed[c.piecePath(i)], "it did not become a track")
			if err != nil {
				why = c.l.failureCause(err.Error())
			}
			missing = append(missing, filepath.Base(c.p.PieceNames[i])+": "+why)
			standing = false
			continue
		}
		pids[i] = pid
	}
	return missing, len(missing) > 0 && standing, nil
}

// refusalPasses reports whether an import plan's refusal of a file may
// pass by waiting: a check of the catalog that failed, or a library the
// file goes to flagged read-only, rather than a place another file holds
// or a file the plan cannot read or place. The plan says which only in
// its words.
func refusalPasses(why string) bool {
	return strings.Contains(why, "check failed") || refusedReadOnly(why)
}

// refusedReadOnly reports an import plan's refusal of a file for the
// read-only flag of the library it goes to.
func refusedReadOnly(why string) bool {
	return strings.Contains(why, "is read-only")
}

// landed answers the track a piece became. One the run recorded is the
// piece's for good, wherever the library moved it since and whatever its
// owner did with it: a landed piece is never imported again. Else it is a
// real track of the catalog whose file is at the piece's recorded place,
// cataloging the place first when the import's own record of it did not
// land; "" for a piece the import did not move there. A piece still in
// the workspace was not moved, so a file at its place is another's, which
// the run neither claims nor scans.
func (c *cueSplit) landed(ctx context.Context, i int) (model.PID, error) {
	if i < len(c.p.PiecePIDs) && c.p.PiecePIDs[i] != "" {
		return model.PID(c.p.PiecePIDs[i]), nil
	}
	dest, essence := c.dest(i), ""
	if i < len(c.p.PieceEssences) {
		essence = c.p.PieceEssences[i]
	}
	if dest == "" || !onDisk(dest) || (i < len(c.p.PieceNames) && onDisk(c.piecePath(i))) {
		return "", nil
	}
	for range 2 {
		items, err := c.l.lib.ItemsByEssence(ctx, essence)
		if err != nil {
			return "", classify(err)
		}
		for _, it := range items {
			if it.Virtual || it.Kind != model.KindTrack {
				continue
			}
			if f, err := c.l.lib.File(ctx, it.FilePID); err == nil && samePath(string(f.Path), dest) {
				return it.PID, nil
			}
		}
		req := waxbin.ScanRequest{SubPath: dest}
		if lib, err := c.l.libraryForPath(ctx, dest); err == nil && lib != "" {
			req.LibraryPID = model.PID(lib)
		}
		if err := c.l.toolScan(ctx, req); err != nil {
			return "", classifyMutation(err)
		}
	}
	return "", fmt.Errorf("%s is in the library, but the catalog has no track of it", c.l.scrubStoragePaths(dest))
}

// retire carries each account's place in the rip's tracks onto the
// pieces while the rip still carves them, and, unless the rip stays,
// moves it to the trash with every track it carves. The trash takes the
// rip's sheet along, restorable with it, and leaves one another encoding
// of the rip still uses. A rip someone else deleted since leaves nothing
// to carry or retire.
func (c *cueSplit) retire(ctx context.Context) error {
	for _, pid := range c.p.PiecePIDs {
		if pid == "" {
			// Every piece a track first; the import tries the rest.
			c.p.Step = cueStepImporting
			return c.save(ctx)
		}
	}
	if c.p.Step == cueStepImported {
		if err := c.carry(ctx); err != nil {
			return c.wait(ctx, err)
		}
	}
	if !c.p.KeepOriginals {
		if err := c.mark(ctx, toolStepTrashing); err != nil {
			return c.wait(ctx, err)
		}
		if err := c.l.toolCrashPoint("trashing"); err != nil {
			return err
		}
		rip := model.PID(c.p.SrcFilePID)
		if rip == "" {
			if r, err := c.l.ripFileOf(ctx, c.seed); err == nil {
				rip = r
			}
		}
		// A rip the catalog no longer has went with an earlier attempt,
		// or with somebody's delete.
		if rip != "" {
			switch _, err := c.l.lib.File(ctx, rip); {
			case err == nil:
				if err := c.l.trashRip(context.WithoutCancel(ctx), rip); err != nil {
					// A read-only flag is waited out, as the book tools
					// wait it out; a folder refusing the server ends the
					// split with the rip beside its tracks.
					if KindOf(err) != KindReadOnly && permanentToolErr(err) {
						return err
					}
					return c.wait(ctx, err)
				}
			case KindOf(classify(err)) != KindNotFound:
				return c.wait(ctx, classify(err))
			}
		}
		if err := c.l.toolCrashPoint("trashed"); err != nil {
			return err
		}
	}
	if err := c.mark(ctx, cueStepRetired); err != nil {
		return c.wait(ctx, err)
	}
	return nil
}

// carry copies each account's place in a carved track onto the piece it
// became, while the rip still carves them. A rip whose tracks are gone
// leaves nothing to carry.
func (c *cueSplit) carry(ctx context.Context) error {
	seed, err := c.l.lib.Get(ctx, c.seed)
	if err != nil {
		if KindOf(classify(err)) == KindNotFound {
			return nil
		}
		return classify(err)
	}
	_, sibs, err := c.l.cueRip(ctx, seed)
	if err != nil {
		if errors.Is(err, errToolPermanent) {
			// No longer cut from a rip: nothing carves the tracks to carry.
			return nil
		}
		return err
	}
	sibPIDs := make([]model.PID, len(sibs))
	for i, s := range sibs {
		sibPIDs[i] = s.PID
	}
	for userPID, byItem := range c.l.collectToolPositions(ctx, sibPIDs) {
		for i, sib := range sibPIDs {
			if pos := byItem[sib]; pos.positionMS > 0 && i < len(c.p.PiecePIDs) && c.p.PiecePIDs[i] != "" {
				if err := c.l.lib.Playback().Checkpoint(ctx, userPID, model.PID(c.p.PiecePIDs[i]), pos.positionMS, pos.asOf()); err != nil {
					c.l.log.Warn("carrying cue split position", "user", string(userPID), "err", err)
				}
			}
		}
	}
	return nil
}

// complete records the split once and answers its tracks.
func (c *cueSplit) complete(ctx context.Context) ([]string, error) {
	ctx = context.WithoutCancel(ctx)
	results := make([]string, 0, len(c.p.PiecePIDs))
	for _, pid := range c.p.PiecePIDs {
		if pid != "" {
			results = append(results, apiPID(PrefixTrack, model.PID(pid)))
		}
	}
	c.l.auditToolOnce(ctx, c.t, "item.split-cue", AuditTarget{Kind: "item", PID: c.t.ItemPID, Name: c.t.ItemTitle},
		map[string]any{"result": results, "pieces": len(results), "keepOriginals": c.p.KeepOriginals, "library": c.l.libraryNameOf(c.p.SrcPath)})
	if err := c.l.toolCrashPoint("audited"); err != nil {
		return nil, err
	}
	os.RemoveAll(c.workspace())
	return results, nil
}

// toolImport is a tool's import apply, or what a test's mutateHook
// answers in its place.
func (l *Library) toolImport(ctx context.Context, plan *inbox.Plan) (*inbox.Report, error) {
	if l.mutateHook != nil {
		if err := l.mutateHook("import"); err != nil {
			return nil, err
		}
	}
	return l.lib.ApplyImport(ctx, plan)
}
