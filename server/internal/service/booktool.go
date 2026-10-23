package service

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// A book merge or split changes the library in steps: its outputs are
// staged in the folder they go to, under names keyed to the task; the
// files they replace go to the trash; the outputs take their names; and a
// scan catalogs them. Whatever ends a run part way (a crash, a restart, a
// shutdown, a failure), these hold:
//
//   - One live task per book: a second is refused when it is queued.
//   - The run holds its task's lease the whole way (holdToolTask).
//   - Nothing goes to the trash until every output is staged whole.
//   - From then on the task is resumable: a failure that passes on its
//     own is waited out, the attempt not counted, for up to
//     toolWaitCap; only one that will not pass undoes the run, which
//     puts back what its trash took before its outputs go.
//   - Its outputs go only once every source it trashed is back in
//     place: a source gone from the trash for good leaves the run
//     nothing to undo, so it finishes instead.
//   - It removes only files it recorded making, by exact path, and its
//     scan catalogs only its own outputs.
//   - A task whose runs keep ending with the server is parked, not run
//     again.
//
// The task records each step before the run takes it, which tells a
// rerun where it stands and whose files it finds.

const (
	// toolStepStaged: every output is staged whole.
	toolStepStaged = "staged"
	// toolStepTrashing: the trash may have taken sources, from
	// TrashFromNS on.
	toolStepTrashing = "trashing"
	// toolStepPlacing: the outputs may have taken their names, the
	// recorded Names.
	toolStepPlacing = "placing"
	// toolStepCataloged: the scan made the book, ResultPID.
	toolStepCataloged = "cataloged"
	// toolStepUndoing: the run is putting back what its trash took, to
	// end with Failure.
	toolStepUndoing = "undoing"
)

const (
	// toolWaitCap is how long a run waits out a failure that should
	// pass before it ends the task safely for its step: the six hours a
	// health fix may run, the longest a task here is given.
	toolWaitCap = healthFixTimeout
	// toolStrandWaits is how often a run waits for a source missing from
	// where the catalog has it before it stops: a move in progress lands
	// in that time; a file the trash moved without a record does not.
	toolStrandWaits = 3
	// toolCrashRuns is how many runs of a task in a row may end with the
	// server, never coming back, before the task is parked rather than
	// run at the next start again.
	toolCrashRuns = 3
)

// toolSource is a file a book tool works from, which its trash takes:
// the file, and where it was when the task was queued.
type toolSource struct {
	file model.PID
	path string
}

// toolRun is a file tool's run over its task: the params it records as
// it goes, and how it waits.
type toolRun struct {
	l *Library
	t *wdb.ToolTask
	p *toolTaskParams
}

// bookTool is a book merge or split as its task orders it.
type bookTool struct {
	toolRun
	// book is the book worked on, title its title when the task was
	// queued, and label the title the outputs carry: the book's, marked
	// when the original stays.
	book         model.PID
	title, label string
	// verb names the tool in what it says; reason is its task type, the
	// trash's reason for what it takes.
	verb, reason string
	dir          string
	names        []string
	sources      []toolSource
	// mode is the mode of the files the outputs are made from.
	mode os.FileMode
}

// mergeTool is the merge p orders of book, titled title when queued,
// whose parts are at paths now.
func (l *Library) mergeTool(t *wdb.ToolTask, p *toolTaskParams, book model.PID, title string, paths []string) *bookTool {
	label := title
	if p.KeepOriginals {
		label += mergedMark
	}
	b := &bookTool{toolRun: toolRun{l, t, p}, book: book, title: title, label: label, verb: "merge", reason: taskTypeBookMerge,
		dir: cmp.Or(p.Dir, l.mergeFolder(paths, title, p.KeepOriginals)), names: []string{safeFileName(label) + ".m4b"},
		mode: fileModeBeside(paths[0])}
	if !p.KeepOriginals {
		for i, path := range p.PartPaths {
			b.sources = append(b.sources, toolSource{file: model.PID(p.PartFilePIDs[i]), path: path})
		}
	}
	return b
}

// splitTool is the split p orders of book, titled title when queued,
// whose file is at src now.
func (l *Library) splitTool(t *wdb.ToolTask, p *toolTaskParams, book model.PID, title, src string) *bookTool {
	label := title
	if p.KeepOriginals {
		label += splitMark
	}
	b := &bookTool{toolRun: toolRun{l, t, p}, book: book, title: title, label: label, verb: "split", reason: taskTypeBookSplit,
		dir: cmp.Or(p.Dir, l.splitFolder(src, title, p.KeepOriginals)), mode: fileModeBeside(src)}
	// Pieces of an mp4-family split keep the .m4b extension so the scan
	// classifies them as audiobook parts; other codecs rely on the
	// narrator tag stamped on them.
	ext := "." + toolSplitExt(p.Format, true)
	for i := range len(p.Cuts) + 1 {
		b.names = append(b.names, fmt.Sprintf("%02d - %s%s", i+1, safeFileName(b.pieceTitle(i)), ext))
	}
	if !p.KeepOriginals {
		b.sources = []toolSource{{file: model.PID(p.SrcFilePID), path: p.SrcPath}}
	}
	return b
}

// bookToolFor is the run a book tool's task orders.
func (l *Library) bookToolFor(ctx context.Context, t *wdb.ToolTask, p *toolTaskParams) (*bookTool, error) {
	_, book, ok := parseAPIPID(t.ItemPID)
	if !ok {
		return nil, fmt.Errorf("%w: bad item pid %q", errToolPermanent, t.ItemPID)
	}
	title := t.ItemTitle
	if title == "" {
		bd, err := l.lib.Book(ctx, book)
		if err != nil {
			return nil, classify(err)
		}
		title = bd.Item.Title
	}
	// The folder the outputs go in follows the files to where they are
	// now: an organize run or a health fix may have moved them since the
	// task was queued.
	switch {
	case t.Type == taskTypeBookMerge && len(p.PartPaths) > 0 && (p.KeepOriginals || len(p.PartFilePIDs) == len(p.PartPaths)):
		return l.mergeTool(t, p, book, title, l.pathsNow(ctx, p.PartFilePIDs, p.PartPaths)), nil
	case t.Type == taskTypeBookSplit && p.SrcPath != "" && (p.KeepOriginals || p.SrcFilePID != ""):
		return l.splitTool(t, p, book, title, l.pathsNow(ctx, []string{p.SrcFilePID}, []string{p.SrcPath})[0]), nil
	}
	return nil, fmt.Errorf("%w: the task names no files to work from", errToolPermanent)
}

// pieceTitle is the title a split's ith piece carries.
func (b *bookTool) pieceTitle(i int) string {
	if i < len(b.p.PieceTitles) {
		return b.p.PieceTitles[i]
	}
	return chapterTitle("", i)
}

// stagedPath is where the ith output waits for its name, keyed to the
// task: hidden and no audio, so no scan reads it, and the trash's prune
// keeps a folder that holds it.
func (b *bookTool) stagedPath(i int) string {
	return filepath.Join(b.dir, fmt.Sprintf(".waxdeck-tool-%s-%d", b.t.ID, i))
}

// placedPath is where the ith output takes its name: the name recorded
// for it, or its own.
func (b *bookTool) placedPath(i int) string {
	if i < len(b.p.Names) {
		return filepath.Join(b.dir, b.p.Names[i])
	}
	return filepath.Join(b.dir, b.names[i])
}

// onDisk reports whether anything is at path.
func onDisk(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}

// allStaged reports whether every output waits staged.
func (b *bookTool) allStaged() bool {
	for i := range b.names {
		if !onDisk(b.stagedPath(i)) {
			return false
		}
	}
	return true
}

// anyStaged reports whether some output waits staged.
func (b *bookTool) anyStaged() bool {
	for i := range b.names {
		if onDisk(b.stagedPath(i)) {
			return true
		}
	}
	return false
}

// current is where the catalog has the ith source now, which follows a
// move by organize or a health fix since the task was queued; where it
// was then when the catalog no longer has it.
func (b *bookTool) current(ctx context.Context, i int) string {
	if f, err := b.l.lib.File(ctx, b.sources[i].file); err == nil {
		return string(f.Path)
	}
	return b.sources[i].path
}

// partPaths are the files the engine works from, where the catalog has
// them now.
func (b *bookTool) partPaths(ctx context.Context) []string {
	if b.reason == taskTypeBookSplit {
		return b.l.pathsNow(ctx, []string{b.p.SrcFilePID}, []string{b.p.SrcPath})
	}
	return b.l.pathsNow(ctx, b.p.PartFilePIDs, b.p.PartPaths)
}

// pathsNow is where the catalog has each of the files pids names now, or
// where it was queued from (paths) for one it does not have.
func (l *Library) pathsNow(ctx context.Context, pids, paths []string) []string {
	out := slices.Clone(paths)
	for i, pid := range pids {
		if pid == "" || i >= len(out) {
			continue
		}
		if f, err := l.lib.File(ctx, model.PID(pid)); err == nil {
			out[i] = string(f.Path)
		}
	}
	return out
}

// runOnce is run counted: a task whose runs keep ending with the server
// is parked at the next start instead of run again.
func (b *bookTool) runOnce(ctx context.Context, produce func(ctx context.Context, ws string) ([]string, error)) ([]string, error) {
	if err := b.begin(ctx, b.whereEnded); err != nil {
		if errors.Is(err, errToolParked) {
			// Parked is failed: a run whose trash took the book is on the
			// record, as a failed one is, before the task can be cleared.
			b.auditFailed(ctx, err)
			return nil, err
		}
		if b.t.Resumable || b.p.Step != "" {
			return nil, b.wait(ctx, err)
		}
		return nil, err
	}
	results, err := b.run(ctx, produce)
	b.end(ctx)
	return results, err
}

// run takes the task from wherever an earlier attempt left it to its
// end; produce has the engine make the outputs, answering them in order,
// finished, in a workspace.
func (b *bookTool) run(ctx context.Context, produce func(ctx context.Context, ws string) ([]string, error)) ([]string, error) {
	for {
		var err error
		switch b.p.Step {
		case "":
			err = b.produceOutputs(ctx, produce)
		case toolStepStaged, toolStepTrashing:
			err = b.makeRoom(ctx)
		case toolStepPlacing:
			err = b.place(ctx)
		case toolStepCataloged:
			return b.complete(ctx)
		case toolStepUndoing:
			err = b.undo(ctx)
		default:
			return nil, fmt.Errorf("%w: the task records an unknown step %q", errToolPermanent, b.p.Step)
		}
		if err != nil {
			return nil, err
		}
	}
}

// produceOutputs stages every output not staged yet, the engine making
// them, then records the run staged and, from here on, resumable.
func (b *bookTool) produceOutputs(ctx context.Context, produce func(context.Context, string) ([]string, error)) error {
	if !b.allStaged() {
		if err := b.check(ctx); err != nil {
			return b.refused(ctx, err)
		}
		if err := b.stage(ctx, produce); err != nil {
			return err
		}
	}
	if err := b.l.db.MarkToolTaskResumable(context.WithoutCancel(ctx), b.t.ID); err != nil {
		return b.wait(ctx, &Error{Kind: KindInternal, Err: err})
	}
	// The drain decides from the task it leased, not the row.
	b.t.Resumable = true
	if err := b.mark(ctx, toolStepStaged); err != nil {
		return b.wait(ctx, err)
	}
	return b.l.toolCrashPoint("staged")
}

// stage has the engine make the outputs and copies each not staged yet
// into the folder it goes to under its staged name, written whole and
// synced before it takes that name, so a staged output found there is
// complete. Each file it makes, and the folder when it makes that, is
// recorded first, so the run removes only what it made.
func (b *bookTool) stage(ctx context.Context, produce func(context.Context, string) ([]string, error)) error {
	ws, err := b.l.toolWorkspace(b.t.ID)
	if err != nil {
		return b.waitIfStaged(ctx, err)
	}
	defer os.RemoveAll(ws)
	if err := b.l.toolCrashPoint("producing"); err != nil {
		return err
	}
	outs, err := produce(ctx, ws)
	if err == nil && len(outs) != len(b.names) {
		err = fmt.Errorf("%w: the engine made %d files, want %d", errToolPermanent, len(outs), len(b.names))
	}
	// The folder is the run's from its first staging on, wherever the
	// files go after.
	if err == nil && (b.p.Dir == "" || !onDisk(b.dir)) {
		b.p.Dir = b.dir
		if !onDisk(b.dir) {
			b.p.MadeDir = b.dir
		}
		if serr := b.save(ctx); serr != nil {
			return b.waitIfStaged(ctx, serr)
		}
	}
	if err == nil {
		if mkErr := os.MkdirAll(b.dir, 0o755); mkErr != nil {
			err = b.l.toolWriteErr(mkErr)
		}
	}
	if err != nil {
		return b.refused(ctx, err)
	}
	fresh := 0
	for i, out := range outs {
		staged := b.stagedPath(i)
		if onDisk(staged) {
			continue
		}
		b.made(staged, staged+".part")
		if err := b.save(ctx); err != nil {
			return b.waitIfStaged(ctx, err)
		}
		if err := copyToolFile(out, staged, b.mode); err != nil {
			return b.refused(ctx, b.l.toolWriteErr(err))
		}
		b.remember(staged, staged)
		if fresh++; fresh == 1 && !b.allStaged() {
			if err := b.l.toolCrashPoint("staging"); err != nil {
				return err
			}
		}
	}
	return nil
}

// made records paths as files the run makes.
func (b *bookTool) made(paths ...string) {
	for _, p := range paths {
		if !slices.Contains(b.p.Created, p) {
			b.p.Created = append(b.p.Created, p)
		}
	}
}

// remember records, under path, what the file at from is: the file the
// run will find at path, to know it again before removing it.
func (b *bookTool) remember(path, from string) {
	id, ok := identOf(from)
	if !ok {
		return
	}
	if b.p.Idents == nil {
		b.p.Idents = map[string]fileIdent{}
	}
	b.p.Idents[path] = id
}

// forget lets go of a name the run recorded giving an output and never
// gave it.
func (b *bookTool) forget(path string) {
	b.p.Placed = slices.DeleteFunc(b.p.Placed, func(p string) bool { return p == path })
	delete(b.p.Idents, path)
}

// removeOwn removes a file the run recorded, when it is the file the run
// wrote: the one whose identity it recorded with the name, or one under a
// name only this run gives (its hidden, task-keyed names). Anything else
// at the name is another's, and stays. It answers a removal the folder
// refused, which leaves the run's file where it was.
func (b *bookTool) removeOwn(path string) error {
	id, known := b.p.Idents[path]
	own := strings.HasPrefix(filepath.Base(path), ".waxdeck-tool-"+b.t.ID+"-")
	switch now, there := identOf(path); {
	case !there:
		// Nothing under the name, or nothing the run writes (a folder, a
		// link): nothing of the run's to remove.
		return nil
	case known && !sameFile(id, now, own):
		b.l.log.Warn("a book tool leaves a file it did not write", "task", b.t.ID, "file", b.l.scrubStoragePaths(path))
		return nil
	case !known && !own:
		b.l.log.Warn("a book tool leaves a file it has no record of", "task", b.t.ID, "file", b.l.scrubStoragePaths(path))
		return nil
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

// sameFile reports whether now is the file recorded as was: by its size
// and modification time, and by its inode too where both have one. The
// run's own task-named files go by size and time alone: no other writer
// gives those names, and a mount whose inode numbers do not hold (a CIFS
// mount without server inodes, some FUSE filesystems) would otherwise
// disown them.
func sameFile(was, now fileIdent, own bool) bool {
	if !sameSizeAndTime(was, now) {
		return false
	}
	return own || was.Ino == 0 || now.Ino == 0 || was.Ino == now.Ino
}

// refused ends a run refused before its trash took anything: for good,
// its outputs gone, when the refusal stands; otherwise it is waited out
// once an output is staged or while the engine is away, and with none
// staged the attempt is the lease's to count.
func (b *bookTool) refused(ctx context.Context, err error) error {
	if !permanentToolErr(err) {
		if engineAwayErr(err) {
			return b.wait(ctx, err)
		}
		return b.waitIfStaged(ctx, err)
	}
	b.discard()
	if merr := b.mark(ctx, ""); merr != nil {
		b.l.log.Warn("recording a book tool's stop", "task", b.t.ID, "err", merr)
	}
	e := toolFailure(err)
	e.Msg += ", so nothing was written"
	return e
}

// waitIfStaged waits out a passing failure once an output is staged, so
// the engine's work is kept.
func (b *bookTool) waitIfStaged(ctx context.Context, err error) error {
	if b.anyStaged() {
		return b.wait(ctx, err)
	}
	return err
}

// wait waits out a failure that should pass, unless the run has waited
// toolWaitCap already, when it ends the task safely for its step.
func (b *bookTool) wait(ctx context.Context, err error) error {
	if b.waitedOut() {
		return b.endWaits(ctx, err)
	}
	return b.toolRun.wait(ctx, err)
}

// endWaits ends a task whose run waited as long as it may, safely for
// how far it went: before its trash it removes its outputs and frees the
// book; after, it puts the sources back, or where that is blocked ends
// keeping every file and saying where each one is; once its outputs have
// their names it ends with them in place, for the next scan.
func (b *bookTool) endWaits(ctx context.Context, cause error) error {
	ctx = context.WithoutCancel(ctx)
	why := fmt.Sprintf("gave up waiting after %s (%s)", toolWaitCap, toolFailure(cause).Msg)
	if b.p.Step == toolStepPlacing && b.allPlaced() {
		e := &Error{Kind: KindInternal, Err: errToolPermanent, Msg: fmt.Sprintf(
			"%s; the new files are in %s, and the next scan of the library will catalog them", why, b.l.scrubStoragePaths(b.dir))}
		// The new files have their names and hold what the trash took.
		b.settleTrashOrLog(ctx)
		b.auditFailed(ctx, e)
		return e
	}
	ours, err := b.ourTrash(ctx, false)
	if err == nil && len(ours) > 0 && !b.p.Forward {
		if left, _ := b.putBack(ctx); left == 0 {
			ours = nil
		}
	}
	if back, berr := b.backInPlace(ctx); err == nil && len(ours) == 0 && berr == nil && back {
		moved := b.moved(ctx)
		e := &Error{Kind: KindInternal, Err: errToolPermanent, Msg: why + ", so nothing was written"}
		if moved {
			e.Msg = why + "; what went to the trash was put back, so nothing was written"
			b.auditFailed(ctx, e)
		}
		b.discard()
		b.settleTrashOrLog(ctx)
		if merr := b.mark(ctx, ""); merr != nil {
			b.l.log.Warn("recording a book tool's stop", "task", b.t.ID, "err", merr)
		}
		return e
	}
	e := &Error{Kind: KindInternal, Err: errToolPermanent, Msg: why}
	if where := b.whereEnded(ctx); where != "" {
		e.Msg += "; " + where
	}
	b.auditFailed(ctx, e)
	return e
}

// moved reports whether the run's trash took anything at all, put back
// since or not.
func (b *bookTool) moved(ctx context.Context) bool {
	all, err := b.ourTrash(ctx, true)
	return err != nil || len(all) > 0
}

// check refuses a run that could not finish: a library that is
// read-only, a folder it writes in that will not take a file, before its
// trash starts a name it gives that another file holds, or a book whose
// files are no longer the ones the task was queued with. Once the run's
// outputs are staged a read-only flag is waited out rather than refused,
// and once the run can only go on, the book's other files are not its
// concern.
func (b *bookTool) check(ctx context.Context) error {
	paths := []string{b.dir}
	folders := []string{b.dir}
	for i := range b.sources {
		path := b.current(ctx, i)
		paths = append(paths, path)
		folders = append(folders, filepath.Dir(path))
		// The trash is made in the root of the library a source is in.
		if root := b.l.storageRootFor(path); root != "" {
			folders = append(folders, filepath.Join(root, model.TrashDirName))
		}
	}
	for _, path := range paths {
		if err := b.l.checkPathWritable(ctx, path); err != nil {
			if KindOf(err) == KindReadOnly && b.p.Step == "" {
				return &Error{Kind: KindReadOnly, Err: errToolPermanent, Msg: err.Error()}
			}
			return err
		}
	}
	if err := b.l.probeToolFolders(folders...); err != nil {
		return err
	}
	if b.p.Step == "" || b.p.Step == toolStepStaged {
		for _, name := range b.names {
			if b.heldByAnother(ctx, filepath.Join(b.dir, name)) {
				folder := b.l.scrubStoragePaths(b.dir)
				e := toolRefusal(refusalNameTaken, fmt.Sprintf(
					"%s is already in %s; move it away to %s the book", name, folder, b.verb),
					"name", name, "folder", folder)
				e.Err = errToolPermanent
				return e
			}
		}
	}
	if b.p.Forward {
		return nil
	}
	return b.unchanged(ctx)
}

// heldByAnother reports whether a file other than a source the run
// trashes first holds path.
func (b *bookTool) heldByAnother(ctx context.Context, path string) bool {
	st, err := os.Lstat(path)
	if err != nil {
		return false
	}
	for i := range b.sources {
		if src, err := os.Lstat(b.current(ctx, i)); err == nil && os.SameFile(st, src) {
			return false
		}
	}
	return true
}

// unchanged refuses a book whose files are no longer the ones the task was
// queued with. The trash takes the files the engine worked from and
// nothing else: a file the book gained would stay beside the outputs as
// one more part of the book, and a copy would be left as the book. Before
// the run's trash starts, every source is still the book's.
func (b *bookTool) unchanged(ctx context.Context) error {
	if len(b.sources) == 0 {
		return nil
	}
	refs, err := b.l.lib.ItemFiles(ctx, b.book)
	if err != nil {
		return classify(err)
	}
	ours := make(map[model.PID]bool, len(b.sources))
	for _, s := range b.sources {
		ours[s.file] = true
	}
	held := make(map[model.PID]bool, len(refs))
	for _, r := range refs {
		held[r.FilePID] = true
		switch {
		case ours[r.FilePID]:
		case r.Role == fileRoleAlternate:
			place, lib := b.l.scrubStoragePaths(r.DisplayPath), b.l.libraryNameOf(r.DisplayPath)
			where := place
			if lib != "" {
				where += " in the " + lib + " library"
			}
			e := toolRefusal(refusalCopyElsewhere, fmt.Sprintf(
				"the book has a copy, %s, which would be left as the book; delete the copy, or keep the originals", where),
				"copy", place, "library", lib)
			e.Err = errToolPermanent
			return e
		default:
			return b.changed(r.DisplayPath + " is not one of the files it was queued with")
		}
	}
	if b.p.Step == "" || b.p.Step == toolStepStaged {
		for _, s := range b.sources {
			if !held[s.file] {
				return b.changed(s.path + " is gone")
			}
		}
	}
	return nil
}

// changed is the refusal of a book that changed since its task was
// queued.
func (b *bookTool) changed(what string) error {
	return &Error{Kind: KindConflict, Err: errToolPermanent,
		Msg: fmt.Sprintf("the book changed since the %s was queued: %s", b.verb, b.l.scrubStoragePaths(what))}
}

// present are the indexes of the sources the book still holds, each
// pointed at the file that holds it now (pairs): a source an undo put
// back is cataloged anew, and a run that then goes on trashes it again.
// A source whose own file the catalog has where the disk does not is
// present too, for stranded to find.
func (b *bookTool) present(ctx context.Context) ([]int, error) {
	refs, err := b.l.lib.ItemFiles(ctx, b.book)
	if err != nil {
		return nil, classify(err)
	}
	cataloged := make(map[model.PID]bool, len(refs))
	for _, r := range refs {
		cataloged[r.FilePID] = true
	}
	var out []int
	for i, j := range b.pairs(refs) {
		switch {
		case j >= 0:
			b.pointAt(i, refs[j].FilePID)
			out = append(out, i)
		case cataloged[b.sources[i].file]:
			out = append(out, i)
		}
	}
	return out, nil
}

// makeRoom moves the sources still in place to the trash, once every
// output is staged whole and before any takes its name: an output shares
// its sources' identity key, so a scan finding both would make it one
// more part of the old book. A shutdown does not cut the trash short; the
// attempt ends after it instead, and the rerun places. A run that can only
// go on waits out what it meets rather than undo.
func (b *bookTool) makeRoom(ctx context.Context) error {
	if !b.allStaged() {
		return b.restage(ctx)
	}
	if err := b.check(ctx); err != nil {
		if permanentToolErr(err) && !b.p.Forward {
			return b.fail(ctx, err)
		}
		return b.wait(ctx, err)
	}
	present, err := b.present(ctx)
	if err != nil {
		return b.wait(ctx, err)
	}
	if i, ok := b.stranded(ctx, present); ok {
		return b.strand(ctx, i)
	}
	if len(present) > 0 {
		if b.p.TrashFromNS == 0 {
			b.p.TrashFromNS = time.Now().UnixNano()
		}
		if len(b.p.TrashedFrom) != len(b.sources) {
			b.p.TrashedFrom = make([]string, len(b.sources))
		}
		files := make([]model.PID, 0, len(present))
		froms := make([]string, 0, len(present))
		for _, i := range present {
			b.p.TrashedFrom[i] = b.current(ctx, i)
			b.recordIdent(i, b.p.TrashedFrom[i])
			files = append(files, b.sources[i].file)
			froms = append(froms, b.p.TrashedFrom[i])
		}
		if err := b.mark(ctx, toolStepTrashing); err != nil {
			return b.wait(ctx, err)
		}
		// Noted before they go, and kept past the task: until the run
		// finishes or puts them back, a merge or split of what remains of
		// the book is refused.
		if err := b.l.db.RecordToolTrash(ctx, string(b.book), b.t.ID, froms); err != nil {
			return b.wait(ctx, &Error{Kind: KindInternal, Err: err})
		}
		if err := b.l.toolCrashPoint("trashing"); err != nil {
			return err
		}
		if _, err := b.l.trashToolFiles(context.WithoutCancel(ctx), files, b.reason); err != nil {
			// A library flagged read-only since the check is waited out:
			// the flag is lifted, or the run undoes once it is.
			if KindOf(err) != KindReadOnly && permanentToolErr(err) && !b.p.Forward {
				return b.fail(ctx, err)
			}
			return b.wait(ctx, err)
		}
	}
	if err := b.l.toolCrashPoint("trashed"); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return b.wait(ctx, err)
	}
	b.p.Names = b.placeNames(ctx)
	if err := b.mark(ctx, toolStepPlacing); err != nil {
		return b.wait(ctx, err)
	}
	return nil
}

// restage takes a run whose outputs are not all staged back to producing
// them: what its trash took comes back first, since the engine reads the
// sources, and the run starts over from the sources as they are. A run
// whose trash lost a source for good cannot make its outputs again, and
// says where the rest is.
func (b *bookTool) restage(ctx context.Context) error {
	if left, err := b.putBack(ctx); left > 0 {
		return b.wait(ctx, b.puttingBack(err))
	}
	if b.p.TrashFromNS != 0 {
		back, err := b.backInPlace(ctx)
		if err != nil {
			return b.wait(ctx, err)
		}
		if !back {
			e := &Error{Kind: KindInternal, Err: errToolPermanent,
				Msg: fmt.Sprintf("the %s's output went from %s, and a file its trash took is gone from the trash", b.verb, b.l.scrubStoragePaths(b.dir))}
			if where := b.whereEnded(ctx); where != "" {
				e.Msg += "; " + where
			}
			b.auditFailed(ctx, e)
			return e
		}
	}
	if err := b.settleTrash(ctx); err != nil {
		return b.wait(ctx, err)
	}
	if err := b.recapture(ctx); err != nil {
		return b.wait(ctx, err)
	}
	if err := b.mark(ctx, ""); err != nil {
		return b.wait(ctx, err)
	}
	return nil
}

// settleTrash forgets what the run's trash took, which its new files now
// hold or which is back in place.
func (b *bookTool) settleTrash(ctx context.Context) error {
	if b.p.TrashFromNS == 0 {
		return nil
	}
	if err := b.l.db.SettleToolTrash(ctx, string(b.book), b.t.ID); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// settleTrashOrLog is settleTrash for a run that ends whatever: a note
// left behind refuses a merge only while the trash still holds the file.
func (b *bookTool) settleTrashOrLog(ctx context.Context) {
	if err := b.settleTrash(ctx); err != nil {
		b.l.log.Warn("settling a book tool's trash", "task", b.t.ID, "err", err)
	}
}

// stranded answers the index of a source the catalog still has that is
// not on disk where it has it now.
func (b *bookTool) stranded(ctx context.Context, present []int) (int, bool) {
	for _, i := range present {
		if !onDisk(b.current(ctx, i)) {
			return i, true
		}
	}
	return 0, false
}

// strand stops a run a source of which is missing from where the catalog
// has it now: after the run's trash started, the catalog's own trash
// leaves that when a crash cuts it between a move and its record. A few
// waits, counted apart from others, give a move in progress time to
// land; then the run puts back what its trash took and ends keeping its
// outputs, which hold that source's audio, saying where to look.
func (b *bookTool) strand(ctx context.Context, i int) error {
	path := b.current(ctx, i)
	why := fmt.Sprintf("%s is not where the catalog has it", b.l.scrubStoragePaths(path))
	if b.p.TrashFromNS != 0 {
		why += fmt.Sprintf("; if the trash moved it without a record, it is in the %s folder of the %s library",
			model.TrashDirName, cmp.Or(b.l.libraryNameOf(path), "book's"))
	}
	if b.p.StrandWaits < toolStrandWaits {
		b.p.StrandWaits++
		return b.wait(ctx, &strandErr{msg: why})
	}
	if left, err := b.putBack(ctx); left > 0 {
		return b.wait(ctx, b.puttingBack(err))
	}
	b.settleTrashOrLog(ctx)
	e := &Error{Kind: KindConflict, Err: errToolPermanent, Msg: why}
	if left := b.whereEnded(ctx); left != "" {
		e.Msg += "; " + left
	}
	b.auditFailed(ctx, e)
	if err := b.mark(ctx, ""); err != nil {
		b.l.log.Warn("recording a book tool's stop", "task", b.t.ID, "err", err)
	}
	return e
}

// strandErr is a source missing from its place, which a run waits on.
type strandErr struct{ msg string }

func (e *strandErr) Error() string { return e.msg }

// fail ends a run a failure that will not pass stopped once its outputs
// were staged. With nothing taken by its trash its outputs go and the run
// fails; otherwise it undoes, putting back what its trash took before its
// outputs go.
func (b *bookTool) fail(ctx context.Context, cause error) error {
	ctx = context.WithoutCancel(ctx)
	if b.p.TrashFromNS == 0 {
		b.discard()
		if err := b.mark(ctx, ""); err != nil {
			b.l.log.Warn("recording a book tool's stop", "task", b.t.ID, "err", err)
		}
		e := toolFailure(cause)
		e.Msg += ", so nothing was written"
		return e
	}
	b.p.Failure = toolFailure(cause).Msg
	if err := b.mark(ctx, toolStepUndoing); err != nil {
		return b.wait(ctx, err)
	}
	return b.undo(ctx)
}

// undo puts back what the run's trash took, and only once every source
// it took is back in place, on disk where it was and the book's again,
// removes its outputs and ends the run with the failure that started the
// undo. A put-back that fails is waited out, the outputs kept. A source
// gone from the trash for good leaves nothing to undo: the run keeps its
// outputs, which hold that source's audio, and goes on to finish, its
// trash taking again what it put back.
func (b *bookTool) undo(ctx context.Context) error {
	ctx = context.WithoutCancel(ctx)
	if left, err := b.putBack(ctx); left > 0 {
		return b.wait(ctx, b.puttingBack(err))
	}
	back, err := b.backInPlace(ctx)
	if err != nil {
		return b.wait(ctx, err)
	}
	if !back {
		b.l.log.Warn("a book tool cannot be undone, so it finishes", "task", b.t.ID, "failure", b.p.Failure)
		b.p.Forward, b.p.Failure = true, ""
		if err := b.mark(ctx, toolStepTrashing); err != nil {
			return b.wait(ctx, err)
		}
		return nil
	}
	e := &Error{Kind: KindInternal, Err: errToolPermanent, Msg: b.p.Failure + ", so nothing was written"}
	if b.moved(ctx) {
		e.Msg = b.p.Failure + "; what went to the trash was put back, so nothing was written"
	}
	b.auditFailed(ctx, e)
	b.discard()
	b.settleTrashOrLog(ctx)
	if err := b.mark(ctx, ""); err != nil {
		b.l.log.Warn("recording a book tool's undo", "task", b.t.ID, "err", err)
	}
	if err := b.l.toolCrashPoint("undone"); err != nil {
		return err
	}
	return e
}

// backInPlace reports whether every source the run's trash took is back:
// a file of the book again, on disk, where it was taken from or wherever
// the catalog moved it since. A catalog that cannot be read is no answer:
// the error, for the run to wait out.
func (b *bookTool) backInPlace(ctx context.Context) (bool, error) {
	refs, err := b.l.toolItemFiles(ctx, b.book)
	if err != nil {
		return false, classify(err)
	}
	held := b.held(refs)
	for i := range b.sources {
		if b.trashedFrom(i) != "" && !held[i] {
			return false, nil
		}
	}
	return true, nil
}

// held reports which sources refs, a book's files, hold (pairs).
func (b *bookTool) held(refs []model.ItemFileRef) []bool {
	out := make([]bool, len(b.sources))
	for i, j := range b.pairs(refs) {
		out[i] = j >= 0
	}
	return out
}

// pairs answers, for each source, the index in refs, a book's files, of
// the file on disk where the catalog has it that holds the source, or -1;
// each file stands for one source at most. A source is held by its own
// file, or, whatever the catalog calls the file now, by one of the book's
// that is the source by what was recorded of it: its size and
// modification time, and its inode where both have one. A file put back
// from the trash is cataloged anew, and organize or a health fix may move
// it after; a copy elsewhere is not the source. With nothing recorded,
// the source is the book's file at the place the run knows it by.
func (b *bookTool) pairs(refs []model.ItemFileRef) []int {
	// The files each source may be: its own alone while it is there, so
	// no other source can take it.
	may := make([][]int, len(b.sources))
	for i := range b.sources {
		id := b.sourceIdent(i)
		from := cmp.Or(b.trashedFrom(i), b.sources[i].path)
		for j, r := range refs {
			path := string(r.Path)
			if !onDisk(path) {
				continue
			}
			if r.FilePID == b.sources[i].file {
				may[i] = []int{j}
				break
			}
			switch {
			case r.Role == fileRoleAlternate:
			case id.ModNS == 0:
				if path == from {
					may[i] = append(may[i], j)
				}
			default:
				if now, ok := identOf(path); ok && sameFile(id, now, false) {
					may[i] = append(may[i], j)
				}
			}
		}
	}
	// Pairs sources and files one to one, the most sources it can.
	owner := make([]int, len(refs))
	for j := range owner {
		owner[j] = -1
	}
	var pair func(i int, seen []bool) bool
	pair = func(i int, seen []bool) bool {
		for _, j := range may[i] {
			if seen[j] {
				continue
			}
			seen[j] = true
			if owner[j] < 0 || pair(owner[j], seen) {
				owner[j] = i
				return true
			}
		}
		return false
	}
	for i := range b.sources {
		pair(i, make([]bool, len(refs)))
	}
	out := make([]int, len(b.sources))
	for i := range out {
		out[i] = -1
	}
	for j, i := range owner {
		if i >= 0 {
			out[i] = j
		}
	}
	return out
}

// pointAt points the ith source at file, as the task's params record it
// for a rerun.
func (b *bookTool) pointAt(i int, file model.PID) {
	b.sources[i].file = file
	if b.reason == taskTypeBookMerge {
		b.p.PartFilePIDs[i] = string(file)
	} else {
		b.p.SrcFilePID = string(file)
	}
}

// sourceIdent is what the run recorded of the ith source, or the zero
// identity.
func (b *bookTool) sourceIdent(i int) fileIdent {
	if i < len(b.p.SourceIdents) {
		return b.p.SourceIdents[i]
	}
	return fileIdent{}
}

// recordIdent records the file at path as the ith source, keeping what
// was recorded before when nothing is there.
func (b *bookTool) recordIdent(i int, path string) {
	id, ok := identOf(path)
	if !ok {
		return
	}
	for len(b.p.SourceIdents) < len(b.sources) {
		b.p.SourceIdents = append(b.p.SourceIdents, fileIdent{})
	}
	b.p.SourceIdents[i] = id
}

// trashedFrom is where the run's trash took the ith source from, or "".
func (b *bookTool) trashedFrom(i int) string {
	if i < len(b.p.TrashedFrom) {
		return b.p.TrashedFrom[i]
	}
	return ""
}

// puttingBack is a put-back that left files in the trash, for the wait.
func (b *bookTool) puttingBack(cause error) error {
	why := "a file would not come back"
	if cause != nil {
		why = b.l.failureCause(cause.Error())
	}
	return &putBackErr{msg: fmt.Sprintf("putting back what the %s moved to the trash: %s", b.verb, why)}
}

// putBackErr is a put-back a run waits on.
type putBackErr struct{ msg string }

func (e *putBackErr) Error() string { return e.msg }

// ourTrash is what the run's trash took: the trash's entries for the
// run's sources, from where it took them, under its reason since its
// trash started, with those put back already when includeRestored.
func (b *bookTool) ourTrash(ctx context.Context, includeRestored bool) ([]model.TrashEntry, error) {
	if b.p.TrashFromNS == 0 {
		return nil, nil
	}
	var entries []model.TrashEntry
	if includeRestored {
		all, err := b.l.lib.Trash(ctx, true, 0)
		if err != nil {
			return nil, classify(err)
		}
		entries = all
	} else {
		byItem, err := b.l.lib.RestorableTrash(ctx, []model.PID{b.book})
		if err != nil {
			return nil, classify(err)
		}
		entries = byItem[b.book]
	}
	ours := make(map[string]bool, len(b.sources))
	for i, s := range b.sources {
		ours[s.path] = true
		if from := b.trashedFrom(i); from != "" {
			ours[from] = true
		}
	}
	var out []model.TrashEntry
	for _, e := range entries {
		if e.ItemPID == b.book && e.Reason == b.reason && ours[string(e.OrigPath)] && e.TrashedAt >= b.p.TrashFromNS {
			out = append(out, e)
		}
	}
	return out, nil
}

// putBack restores what the run's trash took and is still in the trash,
// and answers how many files are left there, with the first failure.
func (b *bookTool) putBack(ctx context.Context) (int, error) {
	ours, err := b.ourTrash(ctx, false)
	if err != nil {
		return 1, err
	}
	left := 0
	var first error
	for _, e := range ours {
		if err := b.l.lib.RestoreTrash(ctx, e.PID); err != nil {
			left++
			first = cmp.Or(first, err)
		}
	}
	return left, first
}

// recapture points the task at its sources as the catalog has them now
// (pairs): a file put back from the trash is cataloged anew, and organize
// may have moved it since.
func (b *bookTool) recapture(ctx context.Context) error {
	if len(b.sources) == 0 {
		return nil
	}
	refs, err := b.l.lib.ItemFiles(ctx, b.book)
	if err != nil {
		return classify(err)
	}
	for i, j := range b.pairs(refs) {
		if j >= 0 {
			b.pointAt(i, refs[j].FilePID)
			b.recordIdent(i, string(refs[j].Path))
		}
	}
	return nil
}

// placeNames are the names the outputs take: each its own, or the next
// free one where another file took it since the run checked.
func (b *bookTool) placeNames(ctx context.Context) []string {
	out := make([]string, len(b.names))
	for i, name := range b.names {
		out[i] = name
		if b.heldByAnother(ctx, filepath.Join(b.dir, name)) {
			out[i] = freeName(b.dir, name)
		}
	}
	return out
}

// freeName is name in dir, or "name (2)" and on where a file holds it.
func freeName(dir, name string) string {
	ext := filepath.Ext(name)
	stem := strings.TrimSuffix(name, ext)
	for n := 2; ; n++ {
		if !onDisk(filepath.Join(dir, name)) {
			return name
		}
		name = fmt.Sprintf("%s (%d)%s", stem, n, ext)
	}
}

// allPlaced reports whether every output has taken its name.
func (b *bookTool) allPlaced() bool {
	for i := range b.names {
		if !slices.Contains(b.p.Placed, b.placedPath(i)) {
			return false
		}
	}
	return true
}

// place gives each staged output its recorded name, recording each as it
// takes it, and scans the outputs into the catalog, them alone. A name
// another file took since it was recorded is not taken from that file:
// the output takes the next free one. An output gone before it took its
// name undoes the run, or where nothing can be undone, ends it saying
// where everything is.
func (b *bookTool) place(ctx context.Context) error {
	if len(b.p.Names) != len(b.names) {
		b.p.Names = b.placeNames(ctx)
		if err := b.save(ctx); err != nil {
			return b.wait(ctx, err)
		}
	}
	stuck, cause := 0, ""
	for i := range b.names {
		staged, final := b.stagedPath(i), b.placedPath(i)
		if slices.Contains(b.p.Placed, final) && !onDisk(staged) {
			continue
		}
		if !onDisk(staged) {
			gone := &Error{Kind: KindInternal, Err: errToolPermanent, Msg: fmt.Sprintf(
				"%s went from %s before it took its name", filepath.Base(staged), b.l.scrubStoragePaths(b.dir))}
			if b.p.Forward {
				if where := b.whereEnded(ctx); where != "" {
					gone.Msg += "; " + where
				}
				b.auditFailed(ctx, gone)
				return gone
			}
			return b.fail(ctx, gone)
		}
		if onDisk(final) {
			// The output never took this name (it is still staged), so the
			// file holding it is another's: the record lets it go.
			b.forget(final)
			b.p.Names[i] = freeName(b.dir, b.p.Names[i])
			final = b.placedPath(i)
		}
		// Recorded before the rename, with the name checked free and what
		// the file is: after a crash, the file under it is the run's own
		// only if it is that file.
		if !slices.Contains(b.p.Placed, final) {
			b.p.Placed = append(b.p.Placed, final)
		}
		b.remember(final, staged)
		if err := b.save(ctx); err != nil {
			return b.wait(ctx, err)
		}
		if err := os.Rename(staged, final); err != nil {
			stuck, cause = stuck+1, cmp.Or(cause, b.l.failureCause(err.Error()))
			b.forget(final)
			if serr := b.save(ctx); serr != nil {
				b.l.log.Warn("recording a book tool's names", "task", b.t.ID, "err", serr)
			}
		}
	}
	backupFsyncDir(b.dir)
	if stuck > 0 {
		msg := fmt.Sprintf("%d of %d files could not take their names in %s (%s)", stuck, len(b.names), b.l.scrubStoragePaths(b.dir), cause)
		if where := b.whereLeft(ctx); where != "" {
			msg += "; " + where
		}
		return b.wait(ctx, errors.New(msg))
	}
	if err := b.l.toolCrashPoint("placed"); err != nil {
		return err
	}
	placed := make([]string, len(b.names))
	for i := range b.names {
		placed[i] = b.placedPath(i)
	}
	pid, err := b.l.scanToolOutputs(ctx, b.dir, placed, b.book, b.label)
	if err != nil {
		if !permanentToolErr(err) {
			return b.wait(ctx, err)
		}
		// The outputs have their names: the next scan of the library
		// catalogs them, which the failure says, and they hold what the
		// trash took.
		b.settleTrashOrLog(ctx)
		b.auditFailed(ctx, err)
		return err
	}
	b.p.ResultPID = string(pid)
	if err := b.mark(ctx, toolStepCataloged); err != nil {
		return b.wait(ctx, err)
	}
	return b.l.toolCrashPoint("cataloged")
}

// complete carries every account's place in the book onto the book the
// run made, and records the run once, with any file of the book that is
// not the run's own.
func (b *bookTool) complete(ctx context.Context) ([]string, error) {
	ctx = context.WithoutCancel(ctx)
	// The new files hold what the run's trash took.
	if err := b.settleTrash(ctx); err != nil {
		return nil, b.wait(ctx, err)
	}
	pid := model.PID(b.p.ResultPID)
	// A book's position is a book-timeline millisecond whatever its files,
	// so each account's carries onto the new book unchanged. It is read
	// from the book worked on, which the trash archives, not forgets.
	for userPID, byItem := range b.l.collectToolPositions(ctx, []model.PID{b.book}) {
		if pos := byItem[b.book]; pos.positionMS > 0 {
			if err := b.l.lib.Playback().Checkpoint(ctx, userPID, pid, pos.positionMS, pos.asOf()); err != nil {
				b.l.log.Warn("carrying a book tool's resume position", "user", string(userPID), "err", err)
			}
		}
	}
	result := apiPID(PrefixBook, pid)
	detail := map[string]any{"result": result, "keepOriginals": b.p.KeepOriginals,
		"library": b.l.libraryNameOf(b.dir), "trashed": len(b.sources)}
	if b.reason == taskTypeBookMerge {
		detail["parts"] = len(b.p.PartPaths)
	} else {
		detail["pieces"] = len(b.names)
	}
	if others := b.others(ctx, pid); len(others) > 0 {
		// The book took a file the run did not make, which the scan of
		// the run's outputs alone did not bring: one cataloged beside
		// them, of the same book.
		detail["alsoHolds"] = others
	}
	b.l.auditToolOnce(ctx, b.t, b.action(), b.target(), detail)
	if err := b.l.toolCrashPoint("audited"); err != nil {
		return nil, err
	}
	os.RemoveAll(b.workspace())
	return []string{result}, nil
}

// others are the files of book that are not the run's outputs, by their
// place in their library.
func (b *bookTool) others(ctx context.Context, book model.PID) []string {
	refs, err := b.l.lib.ItemFiles(ctx, book)
	if err != nil {
		return nil
	}
	var out []string
	for _, r := range refs {
		if !slices.Contains(b.p.Placed, string(r.Path)) {
			out = append(out, b.l.scrubStoragePaths(r.DisplayPath))
		}
	}
	return out
}

// begin counts a run started, unless the task's runs kept ending with
// the server, when it parks the task: finished and failed, saying so and
// where every file it made or moved is, for whoever clears it.
func (r *toolRun) begin(ctx context.Context, whereLeft func(context.Context) string) error {
	if crashed := r.p.RunsStarted - r.p.RunsEnded; crashed >= toolCrashRuns {
		why := fmt.Sprintf("stopped: its last %d runs ended with the server and never came back", crashed)
		if where := whereLeft(ctx); where != "" {
			why += "; " + where
		}
		ctx = context.WithoutCancel(ctx)
		if err := r.l.db.ParkToolTask(ctx, r.t.ID, why, time.Now().UnixNano()); err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
		r.l.log.Warn("a tool task is parked", "task", r.t.ID, "type", r.t.Type, "runs", crashed)
		// Nothing more comes of its workspace, outside the library.
		os.RemoveAll(filepath.Join(r.l.stagingDir, "tools", r.t.ID))
		r.l.notifyToolTask(ctx, r.t.ID)
		r.t.State, r.t.Error = taskStateParked, why
		r.l.notifyFileToolEnd(ctx, r.t)
		return fmt.Errorf("%w: %s", errToolParked, why)
	}
	r.p.RunsStarted++
	return r.save(ctx)
}

// end counts a run that came back.
func (r *toolRun) end(ctx context.Context) {
	r.p.RunsEnded++
	if err := r.save(ctx); err != nil {
		r.l.log.Warn("recording a tool's run", "task", r.t.ID, "err", err)
	}
}

// wait is a failure a run waits out: the task comes back after a delay
// that grows with each wait in a row, the attempt not counted, and
// nothing the run put in the library is undone.
func (r *toolRun) wait(ctx context.Context, err error) error {
	r.p.Waits++
	if r.p.WaitFromNS == 0 {
		r.p.WaitFromNS = time.Now().UnixNano()
	}
	if serr := r.save(ctx); serr != nil {
		r.l.log.Warn("recording a tool's wait", "task", r.t.ID, "err", serr)
	}
	// A folder that refused the write has the libraries probed again.
	r.l.storageRefused(err.Error())
	return &toolRetry{after: toolBackoff(r.p.Waits), err: err, reason: waitReasonOf(err)}
}

// waitedOut reports whether the run has waited as long as it may.
func (r *toolRun) waitedOut() bool {
	return r.p.WaitFromNS != 0 && time.Since(time.Unix(0, r.p.WaitFromNS)) >= toolWaitCap
}

// waitReasonOf names what a run waits on, for a client to word.
func waitReasonOf(err error) string {
	var strand *strandErr
	var putBack *putBackErr
	switch {
	case errors.As(err, &strand):
		return "part-missing"
	case errors.As(err, &putBack):
		return "put-back-blocked"
	case engineAwayErr(err):
		return "engine-unavailable"
	case errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded):
		return "stopped"
	}
	switch KindOf(err) {
	case KindCatalogBusy:
		return "catalog-busy"
	case KindMaintenance:
		return "catalog-maintenance"
	case KindReadOnly:
		return "read-only"
	case KindStorageUnwritable:
		return "storage-unwritable"
	}
	if storageRefusal(err.Error()) != "" {
		return "storage-unwritable"
	}
	return "other"
}

// mark records the step a run is about to take, before it takes it. A
// new step is progress, which ends a run of waits; a step back to the
// start drops what the run recorded on its way.
func (r *toolRun) mark(ctx context.Context, step string) error {
	if step != r.p.Step {
		r.p.Waits, r.p.WaitFromNS, r.p.StrandWaits = 0, 0, 0
	}
	r.p.Step = step
	if step == "" {
		r.p.TrashFromNS, r.p.Names, r.p.ResultPID, r.p.Failure = 0, nil, "", ""
		r.p.TrashedFrom, r.p.Placed, r.p.Forward = nil, nil, false
		r.p.PieceNames, r.p.PieceDests, r.p.PieceEssences, r.p.PiecePIDs = nil, nil, nil, nil
	}
	return r.save(ctx)
}

// save records the run's params as they stand.
func (r *toolRun) save(ctx context.Context) error {
	raw := marshalJSON(*r.p)
	if err := r.l.db.UpdateToolTaskParams(context.WithoutCancel(ctx), r.t.ID, raw); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	r.t.Params = raw
	return nil
}

// whereLeft says where a run that cannot go on left the book: what of it
// the trash holds, and where its outputs are.
func (b *bookTool) whereLeft(ctx context.Context) string {
	var said, waiting []string
	if ours, err := b.ourTrash(ctx, false); err == nil && len(ours) > 0 {
		names := make([]string, len(ours))
		for i, e := range ours {
			names[i] = b.l.scrubStoragePaths(e.OrigDisplay)
		}
		said = append(said, fmt.Sprintf("the trash holds %d of the book's files under %s: %s",
			len(ours), b.reason, strings.Join(names, ", ")))
	}
	for i := range b.names {
		if staged := b.stagedPath(i); slices.Contains(b.p.Created, staged) && onDisk(staged) {
			waiting = append(waiting, filepath.Base(staged))
		}
	}
	where := b.l.scrubStoragePaths(b.dir)
	if len(waiting) > 0 {
		what := fmt.Sprintf("%d pieces wait", len(waiting))
		if b.reason == taskTypeBookMerge {
			what = "the merged book waits"
		}
		said = append(said, fmt.Sprintf("%s in %s as %s", what, where, strings.Join(waiting, ", ")))
	}
	var placed []string
	for _, p := range b.p.Placed {
		if onDisk(p) {
			placed = append(placed, filepath.Base(p))
		}
	}
	if len(placed) > 0 {
		said = append(said, fmt.Sprintf("%s in %s, which the next scan of the library will catalog", strings.Join(placed, ", "), where))
	}
	return strings.Join(said, "; ")
}

// whereEnded is whereLeft for a task that ends: with its outputs still
// hidden, it also says what clearing the task does with them.
func (b *bookTool) whereEnded(ctx context.Context) string {
	where := b.whereLeft(ctx)
	if len(b.hiddenOutputs()) == 0 {
		return where
	}
	note := "clearing the task gives the hidden files their names, for the next scan to catalog, not every part being in place"
	if b.partsInPlace(ctx) {
		note = "clearing the task removes the hidden files, every part being in place"
	}
	if where == "" {
		return note
	}
	return where + "; " + note
}

// hiddenOutputs are the outputs the run made that wait, whole, under the
// hidden names it gives them.
func (b *bookTool) hiddenOutputs() []int {
	var out []int
	for i := range b.names {
		if staged := b.stagedPath(i); slices.Contains(b.p.Created, staged) && onDisk(staged) {
			out = append(out, i)
		}
	}
	return out
}

// partsInPlace reports whether the book holds every file the run works
// from, on disk where the catalog has it: the originals kept, none gone
// to the trash, or each put back. A catalog that cannot be read says no,
// which keeps what the run made.
func (b *bookTool) partsInPlace(ctx context.Context) bool {
	if len(b.sources) == 0 {
		return true
	}
	refs, err := b.l.toolItemFiles(ctx, b.book)
	if err != nil {
		return false
	}
	return !slices.Contains(b.held(refs), false)
}

// clearOutcome is what settling a cleared run did with what it had left
// hidden: removed, or named (with the names taken), and any file that
// could not be removed or take its name, with why.
type clearOutcome struct {
	outputs string
	named   []string
	stuck   []string
	cause   string
}

// settleCleared leaves nothing hidden of a finished run behind as its
// task is cleared: with every part in place its hidden outputs go (its
// own files only); otherwise each takes its name, a free one where
// another file holds it, for the next scan to catalog, so nothing is lost,
// and then holds what the trash took. Incomplete copies go either way. A
// file that cannot take its name stays hidden, which the outcome says.
func (b *bookTool) settleCleared(ctx context.Context) clearOutcome {
	hidden := b.hiddenOutputs()
	for i := range b.names {
		_ = b.removeOwn(b.stagedPath(i) + ".part")
	}
	if len(hidden) == 0 {
		return clearOutcome{}
	}
	if b.partsInPlace(ctx) {
		out := clearOutcome{outputs: "removed"}
		for _, i := range hidden {
			if err := b.removeOwn(b.stagedPath(i)); err != nil {
				out.stuck = append(out.stuck, filepath.Base(b.stagedPath(i)))
				out.cause = cmp.Or(out.cause, b.l.failureCause(err.Error()))
			}
		}
		if len(out.stuck) == 0 && b.p.MadeDir != "" && !samePath(b.p.MadeDir, b.l.storageRootFor(b.p.MadeDir)) {
			os.Remove(b.p.MadeDir)
		}
		return out
	}
	out := clearOutcome{outputs: "named"}
	for _, i := range hidden {
		final := filepath.Join(b.dir, freeName(b.dir, b.names[i]))
		if err := os.Rename(b.stagedPath(i), final); err != nil {
			out.stuck = append(out.stuck, filepath.Base(b.stagedPath(i)))
			out.cause = cmp.Or(out.cause, b.l.failureCause(err.Error()))
			continue
		}
		out.named = append(out.named, b.l.scrubStoragePaths(final))
	}
	backupFsyncDir(b.dir)
	if len(out.stuck) == 0 {
		// Every new file has its name and holds what the trash took.
		b.settleTrashOrLog(ctx)
	}
	return out
}

// discard removes the files the run recorded making, and nothing else:
// its staged outputs and their temporaries, the outputs that took their
// names, the folder it made when that is left empty, and its workspace.
func (b *bookTool) discard() {
	// A file the folder will not let go stays where it is; the run's
	// account of where its files are names it.
	for _, p := range b.p.Created {
		_ = b.removeOwn(p)
	}
	for _, p := range b.p.Placed {
		_ = b.removeOwn(p)
	}
	if b.p.MadeDir != "" && !samePath(b.p.MadeDir, b.l.storageRootFor(b.p.MadeDir)) {
		os.Remove(b.p.MadeDir)
	}
	os.RemoveAll(b.workspace())
	b.p.Created, b.p.Placed, b.p.MadeDir, b.p.Idents = nil, nil, "", nil
}

// workspace is where the engine's outputs are made, outside the library.
func (b *bookTool) workspace() string {
	return filepath.Join(b.l.stagingDir, "tools", b.t.ID)
}

// auditFailed records a run that failed once some of the book had gone
// to the trash: who moved it, what went and what came back. Once the task
// is cleared, the trash's reason would be all that is left of the run.
func (b *bookTool) auditFailed(ctx context.Context, cause error) {
	ours, err := b.ourTrash(context.WithoutCancel(ctx), true)
	if err != nil || len(ours) == 0 {
		return
	}
	restored := 0
	for _, e := range ours {
		if e.RestoredAt > 0 {
			restored++
		}
	}
	b.l.auditToolOnce(ctx, b.t, b.action(), b.target(), map[string]any{
		"result": "failed", "trashed": len(ours), "restored": restored, "keepOriginals": b.p.KeepOriginals,
		"library": b.l.libraryNameOf(b.dir), "error": b.l.failureWords(taskFailureText(cause)),
	})
}

// action is the audit action of the tool's runs.
func (b *bookTool) action() string {
	if b.reason == taskTypeBookMerge {
		return "book.merge"
	}
	return "book.split"
}

// target is the book a run is audited against.
func (b *bookTool) target() AuditTarget {
	return AuditTarget{Kind: "book", PID: b.t.ItemPID, Name: b.title}
}

// auditToolOnce records a tool task's run under the account that queued
// it, with the task in its detail, unless the run is on the record
// already: a rerun after a crash past the record does not record it
// twice.
func (l *Library) auditToolOnce(ctx context.Context, t *wdb.ToolTask, action string, target AuditTarget, detail map[string]any) {
	ctx = context.WithoutCancel(ctx)
	detail["task"] = t.ID
	rows, err := l.db.ListAudit(ctx, wdb.AuditFilter{Action: action, TargetPID: target.PID}, 0, 50)
	if err == nil {
		for _, r := range rows {
			var d map[string]any
			if json.Unmarshal([]byte(r.Detail), &d) == nil && d["task"] == t.ID {
				return
			}
		}
	}
	l.auditToolTask(ctx, t, action, target, detail)
}

// toolFailure is a run's failure as one more can be said of: a copy of a
// service error, else one in the failure's own words.
func toolFailure(cause error) *Error {
	var se *Error
	if errors.As(cause, &se) {
		c := *se
		if c.Msg == "" {
			c.Msg = taskFailureText(se)
		}
		return &c
	}
	return &Error{Kind: KindOf(cause), Err: cause, Msg: taskFailureText(cause)}
}

// settleRetired settles a file tool its attempts ran out on before it
// put anything into the library that only finishing settles: what it
// made goes. A run past that is resumable, and the retire pass never
// takes it.
func (l *Library) settleRetired(ctx context.Context, t *wdb.ToolTask) {
	var p toolTaskParams
	if err := json.Unmarshal([]byte(t.Params), &p); err != nil || p.Step != "" {
		return
	}
	switch t.Type {
	case taskTypeBookMerge, taskTypeBookSplit:
		if b, err := l.bookToolFor(ctx, t, &p); err == nil {
			b.discard()
		}
	case taskTypeCueSplit:
		os.RemoveAll(filepath.Join(l.stagingDir, "tools", t.ID))
	}
}

// recordToolTaskDone records a task done with its results.
func (l *Library) recordToolTaskDone(ctx context.Context, t *wdb.ToolTask, results []string) {
	t.State = taskStateDone
	t.ProgressPct = 100
	t.Error = ""
	t.ResultPIDs = marshalJSON(results)
	t.FinishedAtNS = time.Now().UnixNano()
	if err := l.db.UpdateToolTask(context.WithoutCancel(ctx), *t); err != nil {
		l.log.Warn("recording tool task completion", "task", t.ID, "err", err)
	}
}

// trashToolFiles moves a book tool's sources to the trash under its
// reason, every one, or the failure says which stayed and why; it answers
// how many went.
func (l *Library) trashToolFiles(ctx context.Context, files []model.PID, reason string) (int, error) {
	plan, err := l.lib.PlanDeleteFiles(ctx, files, model.DeleteTrash, waxbin.DeleteReason(reason))
	if err != nil {
		return 0, classify(err)
	}
	n, e := l.applyToolTrash(ctx, plan)
	if e != nil {
		return n, e
	}
	return n, nil
}

// copyToolFile copies src to dst with the repo's crash-safe write
// discipline, in mode, the mode of the file it was made from: written to
// dst's ".part" beside it, checked whole and synced, then renamed. A
// workspace may sit on another filesystem, so a plain rename cannot carry
// it.
func copyToolFile(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp := dst + ".part"
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	fail := func(err error) error {
		out.Close()
		os.Remove(tmp)
		return err
	}
	n, err := io.Copy(out, in)
	if err != nil {
		return fail(err)
	}
	if st, err := in.Stat(); err != nil || st.Size() != n {
		return fail(fmt.Errorf("copied %d bytes of %s, which no longer reads whole", n, filepath.Base(src)))
	}
	// The mode is best effort, as the tag writer's is: a mount that
	// refuses it still takes the file.
	_ = out.Chmod(mode)
	if err := out.Sync(); err != nil {
		return fail(err)
	}
	if err := out.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	if err := os.Rename(tmp, dst); err != nil {
		os.Remove(tmp)
		return err
	}
	backupFsyncDir(filepath.Dir(dst))
	return nil
}
