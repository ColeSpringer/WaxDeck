package service

import (
	"cmp"
	"context"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/colespringer/waxbin/model"
)

// folderCheckWait bounds a create's look at its folder: a folder on a
// mount that stopped answering fails its own create.
const folderCheckWait = 15 * time.Second

// rootCreates are the console's library creates in flight: the name and
// folder each holds until it lands or fails, and the looks at folders
// still out, one per folder. mu spans only these, never a call into the
// filesystem.
type rootCreates struct {
	mu     sync.Mutex
	claims []*rootClaim
	looks  map[string]*folderLook
	// folders are the stats of libraries' folders still out, one per
	// folder, which every create comparing with that folder shares: one
	// that hangs holds a single worker, however often creates ask.
	folders map[string]*folderStat
	// look, wait and stat stand in for lookAt, folderCheckWait and the
	// stat of a library's folder in tests; free, when set, runs once a
	// create's checks have passed and before it stores anything.
	look func(path string) folderAnswer
	wait time.Duration
	stat func(path string) (fs.FileInfo, error)
	free func()
}

// folderStat is a stat of a library's folder under way; folder is set,
// nil for none there, before done closes.
type folderStat struct {
	done   chan struct{}
	folder fs.FileInfo
}

// rootClaim is a create in flight; probe is its asking that the server can
// write to the folder, and folder is the folder it found there, once it
// has checked no library holds it by another path.
type rootClaim struct {
	name, path string
	probe      bool
	folder     fs.FileInfo
}

// folderLook is a look at a folder under way, which every create at that
// folder waits on. answer, probed, probeErr, folder (the folder found when
// the path answered as one) and resolved (the path with its symlinks
// followed, "" when they cannot be) are set before done closes.
type folderLook struct {
	done     chan struct{}
	answer   folderAnswer
	probed   bool
	probeErr error
	folder   fs.FileInfo
	resolved string
}

// claimRoot answers a path or name that a library or a create in flight
// holds, and otherwise holds both for this create until release, so no
// other create looks at a folder this one is adding. A managed create asks
// for the write probe, unless the server is read-only or the folder is a
// library's own, holds one or lies inside one.
func (l *Library) claimRoot(ctx context.Context, name, path string, managed bool) (*rootClaim, func(), error) {
	c := &l.creates
	c.mu.Lock()
	defer c.mu.Unlock()
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return nil, nil, classify(err)
	}
	if err := l.rootTaken(ctx, name, path, libs); err != nil {
		return nil, nil, err
	}
	for _, other := range c.claims {
		if pathsOverlap(other.path, path) {
			return nil, nil, &Error{Kind: KindConflict, Msg: "a library at " + other.path + " is being added"}
		}
		if other.name == name {
			return nil, nil, &Error{Kind: KindConflict, Msg: "a library named " + name + " is being added"}
		}
	}
	// The probe goes to the typed path, decided before the look resolves
	// it: re-deciding after would take a second look, and a probe file
	// written through a link is removed at once all the same.
	claim := &rootClaim{name: name, path: path, probe: managed && !l.currentToggles().readOnly &&
		!slices.ContainsFunc(libs, func(lib *model.Library) bool { return pathsOverlap(rootKey(lib.DisplayRoot), path) })}
	c.claims = append(c.claims, claim)
	return claim, func() {
		c.mu.Lock()
		defer c.mu.Unlock()
		c.claims = slices.DeleteFunc(c.claims, func(x *rootClaim) bool { return x == claim })
	}, nil
}

// rootStillFree repeats the cheap checks once the folder has answered:
// the CLI may have added the folder, or a root taken the name, meanwhile.
// It also refuses a folder that a library, or another create in flight,
// holds by another path - a symlinked parent or a bind mount names one
// folder twice, and two libraries on it would catalog it twice. Paths
// cannot tell that; only the folders can, and they are looked at off the
// lock, again for a library that landed meanwhile.
func (l *Library) rootStillFree(ctx context.Context, claim *rootClaim, path string, folder fs.FileInfo) error {
	c := &l.creates
	compared := map[string]bool{}
	for {
		libs, err := l.lib.Libraries(ctx)
		if err != nil {
			return classify(err)
		}
		if err := l.folderNotHeld(ctx, folder, libs, compared); err != nil {
			return err
		}
		c.mu.Lock()
		libs, err = l.lib.Libraries(ctx)
		if err != nil {
			c.mu.Unlock()
			return classify(err)
		}
		if err := l.rootTaken(ctx, claim.name, path, libs); err != nil {
			c.mu.Unlock()
			return err
		}
		if slices.ContainsFunc(libs, func(lib *model.Library) bool { return !compared[rootKey(lib.DisplayRoot)] }) {
			c.mu.Unlock()
			continue
		}
		for _, other := range c.claims {
			if other != claim && folder != nil && other.folder != nil && os.SameFile(folder, other.folder) {
				c.mu.Unlock()
				return &Error{Kind: KindConflict, Msg: "a library at " + other.path + " is being added, which is the folder at " + claim.path}
			}
		}
		claim.folder = folder
		c.mu.Unlock()
		return nil
	}
}

// folderNotHeld refuses folder when it is the folder of one of libs not
// compared yet, marking those it compares. Each library's folder is
// stat'ed on a worker of its own within the create's bound, so one that
// does not answer holds only its own stat, and is not compared.
func (l *Library) folderNotHeld(ctx context.Context, folder fs.FileInfo, libs []*model.Library, compared map[string]bool) error {
	var roots []string
	var stats []*folderStat
	for _, lib := range libs {
		root := rootKey(lib.DisplayRoot)
		if compared[root] {
			continue
		}
		compared[root] = true
		if folder == nil {
			continue
		}
		if st := l.folderStatAt(root); st != nil {
			roots, stats = append(roots, root), append(stats, st)
		}
	}
	timer := time.NewTimer(cmp.Or(l.creates.wait, folderCheckWait))
	defer timer.Stop()
	expired := false
	unanswered := 0
	for i, st := range stats {
		if !expired {
			select {
			case <-st.done:
			case <-timer.C:
				expired = true
			case <-ctx.Done():
				return ctx.Err()
			}
		}
		select {
		case <-st.done:
			if st.folder != nil && os.SameFile(folder, st.folder) {
				return &Error{Kind: KindConflict, Msg: "a library at " + roots[i] + " already holds that folder"}
			}
		default:
			unanswered++
		}
	}
	if unanswered > 0 {
		l.log.Warn("a library's folder did not answer; a new library was not compared with it", "libraries", unanswered)
	}
	return nil
}

// folderStatAt is the stat of a library's folder under way, or a new one
// on a worker; nil when the server is stopping.
func (l *Library) folderStatAt(path string) *folderStat {
	c := &l.creates
	c.mu.Lock()
	defer c.mu.Unlock()
	if st := c.folders[path]; st != nil {
		return st
	}
	stat := c.stat
	if stat == nil {
		stat = os.Stat
	}
	st := &folderStat{done: make(chan struct{})}
	started := l.workers.GoOnce(l.procCtx, "library-folder", func(context.Context) error {
		if info, err := stat(path); err == nil && info.IsDir() {
			st.folder = info
		}
		c.mu.Lock()
		delete(c.folders, path)
		c.mu.Unlock()
		close(st.done)
		return nil
	})
	if !started {
		return nil
	}
	if c.folders == nil {
		c.folders = map[string]*folderStat{}
	}
	c.folders[path] = st
	return st
}

// lookAtFolder answers whether the claimed folder can be the new library,
// whether the look probed it for writes, the folder it found, and the
// path with its symlinks followed ("" when they cannot be), waiting on the
// look within the bound. A look that settled before this create
// could ask it for the probe is followed by another.
func (l *Library) lookAtFolder(ctx context.Context, claim *rootClaim, allowAbsent bool) (bool, fs.FileInfo, string, error) {
	timer := time.NewTimer(cmp.Or(l.creates.wait, folderCheckWait))
	defer timer.Stop()
	for {
		look, err := l.folderLookAt(claim.path)
		if err != nil {
			return false, nil, "", err
		}
		select {
		case <-look.done:
		case <-timer.C:
			l.log.Warn("a new library's folder did not answer; its create is refused", "path", claim.path)
			return false, nil, "", errInvalid("the server cannot read the library path: the folder at " + claim.path + " did not answer")
		case <-ctx.Done():
			return false, nil, "", ctx.Err()
		}
		if claim.probe && look.answer == folderListed && !look.probed {
			continue
		}
		if err := folderRefusal(claim.path, look.answer, allowAbsent); err != nil {
			return false, nil, "", err
		}
		if claim.probe && look.probeErr != nil {
			return false, nil, "", errInvalid("the library path is not writable by the server, so it cannot be managed; fix its ownership or add it unmanaged")
		}
		return claim.probe && look.probed, look.folder, look.resolved, nil
	}
}

// folderLinkHops bounds how many links resolveFolder follows by hand;
// its steps up through absent folders are not counted.
const folderLinkHops = 40

// resolveFolder answers path with its symlinks followed as far as they
// go: through the longest part of it that is there, and through a link
// whose target is not there yet, so a folder on a drive mounted later is
// named as it will be once it is. A relative link target is taken from
// the link's own folder.
func resolveFolder(path string) (string, error) {
	at, tail, hops := path, "", 0
	for {
		resolved, err := filepath.EvalSymlinks(at)
		if err == nil {
			return filepath.Join(resolved, tail), nil
		}
		// A part not there, or a file where a folder would be: step up.
		if !errors.Is(err, fs.ErrNotExist) && !errors.Is(err, syscall.ENOTDIR) {
			return "", err
		}
		if target, err := os.Readlink(at); err == nil {
			if hops++; hops > folderLinkHops {
				return "", errors.New("too many links in " + path)
			}
			if !filepath.IsAbs(target) {
				// From the folder the link really is in, as the system
				// follows it: a ".." climbs out of that folder, not out of
				// the path's spelling of it.
				dir, err := filepath.EvalSymlinks(filepath.Dir(at))
				if err != nil {
					return "", err
				}
				target = dir + string(filepath.Separator) + target
			}
			if at, err = climbPhysically(target); err != nil {
				return "", err
			}
			continue
		}
		up := filepath.Dir(at)
		if up == at {
			return filepath.Join(at, tail), nil
		}
		at, tail = up, filepath.Join(filepath.Base(at), tail)
	}
}

// climbPhysically answers an absolute path with its "." and ".." taken
// as the system takes them: each ".." climbs out of the folder the path
// so far really names, its links followed, rather than out of its
// spelling, as filepath.Clean would. Parts not there are taken as spelled.
// A ".." out of a link not followable yet has no answer until it is, and
// errs.
func climbPhysically(path string) (string, error) {
	parts := strings.Split(filepath.ToSlash(path), "/")
	if !slices.Contains(parts, "..") {
		return filepath.Clean(path), nil
	}
	volume := filepath.VolumeName(path)
	if strings.HasPrefix(volume, `\\`) {
		// A UNC share (Windows only): its volume spans parts, so it is
		// not walked part by part.
		return "", errors.New("a \"..\" under a network share in " + path)
	}
	at := volume + string(filepath.Separator)
	var dangling []string
	for _, part := range parts[1:] {
		switch part {
		case "", ".":
		case "..":
			if slices.Contains(dangling, at) {
				return "", errors.New("a \"..\" out of a link not followable yet in " + path)
			}
			at = filepath.Dir(at)
		default:
			at = filepath.Join(at, part)
			if resolved, err := filepath.EvalSymlinks(at); err == nil {
				at = resolved
			} else if st, err := os.Lstat(at); err == nil && st.Mode()&fs.ModeSymlink != 0 {
				dangling = append(dangling, at)
			}
		}
	}
	return at, nil
}

// folderLookAt is the look at the folder under way, or a new one on a
// worker. Once the folder has answered, the look writes the probe only
// while a create still waiting at the folder asks for it: one that gave up
// asks nothing, and by then the folder may be a library's. A look that
// breaks still ends, answering folderBroken.
func (l *Library) folderLookAt(path string) (*folderLook, error) {
	c := &l.creates
	c.mu.Lock()
	defer c.mu.Unlock()
	if look := c.looks[path]; look != nil {
		return look, nil
	}
	look := &folderLook{done: make(chan struct{}), answer: folderBroken}
	at := c.look
	if at == nil {
		at = lookAt
	}
	started := l.workers.GoOnce(l.procCtx, "library-folder", func(context.Context) error {
		defer func() {
			c.mu.Lock()
			delete(c.looks, path)
			c.mu.Unlock()
			close(look.done)
		}()
		answer := at(path)
		if answer == folderListed || answer == folderUnlisted || answer == folderMissing {
			// One resolution, and the folder's identity from it, so a link
			// repointed meanwhile cannot have the checks compare one folder
			// and the create store another.
			if resolved, err := resolveFolder(path); err != nil {
				l.log.Warn("a new library's path could not be followed through its links; it is kept as given",
					"path", path, "err", err)
			} else {
				look.resolved = resolved
			}
			if st, err := os.Stat(cmp.Or(look.resolved, path)); err == nil && st.IsDir() {
				look.folder = st
			}
		}
		if answer == folderListed && l.probeAsked(path) {
			look.probed, look.probeErr = true, probeWritable(path)
		}
		look.answer = answer
		return nil
	})
	if !started {
		return nil, &Error{Kind: KindInternal, Msg: "the server is stopping"}
	}
	if c.looks == nil {
		c.looks = map[string]*folderLook{}
	}
	c.looks[path] = look
	return look, nil
}

// probeAsked reports whether a create still waiting at the folder asks for
// the write probe.
func (l *Library) probeAsked(path string) bool {
	l.creates.mu.Lock()
	defer l.creates.mu.Unlock()
	return slices.ContainsFunc(l.creates.claims, func(x *rootClaim) bool { return x.path == path && x.probe })
}
