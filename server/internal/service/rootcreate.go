package service

import (
	"cmp"
	"context"
	"slices"
	"sync"
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
	// look and wait stand in for lookAt and folderCheckWait in tests.
	look func(path string) folderAnswer
	wait time.Duration
}

// rootClaim is a create in flight; probe is its asking that the server can
// write to the folder.
type rootClaim struct {
	name, path string
	probe      bool
}

// folderLook is a look at a folder under way, which every create at that
// folder waits on. answer, probed and probeErr are set before done closes.
type folderLook struct {
	done     chan struct{}
	answer   folderAnswer
	probed   bool
	probeErr error
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
func (l *Library) rootStillFree(ctx context.Context, name, path string) error {
	l.creates.mu.Lock()
	defer l.creates.mu.Unlock()
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return classify(err)
	}
	return l.rootTaken(ctx, name, path, libs)
}

// lookAtFolder answers whether the claimed folder can be the new library,
// and whether the look probed it for writes, waiting on the look within
// the bound. A look that settled before this create could ask it for the
// probe is followed by another.
func (l *Library) lookAtFolder(ctx context.Context, claim *rootClaim, allowAbsent bool) (bool, error) {
	timer := time.NewTimer(cmp.Or(l.creates.wait, folderCheckWait))
	defer timer.Stop()
	for {
		look, err := l.folderLookAt(claim.path)
		if err != nil {
			return false, err
		}
		select {
		case <-look.done:
		case <-timer.C:
			l.log.Warn("a new library's folder did not answer; its create is refused", "path", claim.path)
			return false, errInvalid("the server cannot read the library path: the folder at " + claim.path + " did not answer")
		case <-ctx.Done():
			return false, ctx.Err()
		}
		if claim.probe && look.answer == folderListed && !look.probed {
			continue
		}
		if err := folderRefusal(claim.path, look.answer, allowAbsent); err != nil {
			return false, err
		}
		if claim.probe && look.probeErr != nil {
			return false, errInvalid("the library path is not writable by the server, so it cannot be managed; fix its ownership or add it unmanaged")
		}
		return claim.probe && look.probed, nil
	}
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
