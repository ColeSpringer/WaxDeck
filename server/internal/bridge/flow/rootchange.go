package flow

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"slices"

	"github.com/colespringer/waxflow/client"
)

// Every runtime change to the roots the bridge maps goes through
// ChangeRoots, whether the engine is answering or not. The sidecar's
// config file is what it opens at its next start, and a root it cannot
// open there stops it starting, so a root reaches that file only through
// a reload that checks it. While the engine is away a removal is written
// at once (letting a root go can never stop a start) and reloaded when it
// answers; an add is held, out of the table and the file, until the
// engine answers and it is offered again through the usual write, reload
// and rollback.

// ErrRootHeld is an add the engine did not answer the reload for while it
// was up: held, as an add made while it is away is, and offered again when
// it next answers.
var ErrRootHeld = errors.New("the streaming engine did not answer the reload of this root; it is offered again when the engine next answers")

// rootsPending is the root changes the engine has not taken yet. Guarded
// by reloadMu.
type rootsPending struct {
	// adds are roots taken while the engine was away (or while a reload
	// could not reach it), kept out of the table and the file until a
	// reload can check them. The engine's next answer has them offered
	// again, one at a time, by the service's re-sync of every root the
	// bridge does not map.
	adds []Root
	// drops are names let go meanwhile, already out of the table and the
	// file, which the engine's next answer reloads.
	drops []string
}

// ChangeRoots is the one way the bridge's root set changes at runtime: it
// takes add in and lets the roots named in drop go, in the bridge's table
// and in the sidecar's config file. While the engine answers, the file is
// rewritten and the sidecar reloaded at once; a refused reload takes the
// adds back out of both and answers why, and a reload that gets no
// answer keeps the change for the engine's next one. While it is away a
// removal is written and its reload left pending, and an add is held
// until the engine answers. A nil error means the change is made, or
// waits for the engine; any other error says what an administrator still
// has to do.
func (b *Bridge) ChangeRoots(ctx context.Context, add []Root, drop []string) error {
	b.reloadMu.Lock()
	defer b.reloadMu.Unlock()
	if b.configPath == "" {
		// No file to write: the change is the bridge's own, and the
		// sidecar's configuration is the operator's to match.
		b.applyRoots(add, drop)
		return byHand(add, "no sidecar config file is configured (set --flow-config), so")
	}
	caps := b.Caps()
	if caps == nil {
		return b.changeWhileAwayLocked(add, drop)
	}
	if !caps.Delivery.RootsReload {
		return b.changeUnreloadableLocked(add, drop)
	}
	return b.changeAndReloadLocked(ctx, add, drop)
}

// byHand is the error for roots added where WaxDeck cannot reach the
// sidecar's configuration, nil when nothing was added: a removal needs no
// hand, since a sidecar serving a root nothing maps any more harms nothing.
func byHand(add []Root, why string) error {
	if len(add) == 0 {
		return nil
	}
	return fmt.Errorf("%s this root has to be added to the sidecar's own configuration and the sidecar restarted before it streams", why)
}

// changeAndReloadLocked makes a change while the engine answers: the
// table, then the file, then the reload, which is what checks an add.
func (b *Bridge) changeAndReloadLocked(ctx context.Context, add []Root, drop []string) error {
	// Offered now, so no longer held.
	b.unholdLocked(rootNames(add), drop)
	if len(add) == 0 && !b.namesAnyLocked(drop) {
		// Neither the table nor the file names a root to let go: there is
		// nothing for the sidecar to reconcile.
		return nil
	}
	added, dropped := b.applyRoots(add, drop)
	err := b.reloadRootsLocked(ctx, drop)
	if err == nil {
		// The reload carried every removal left pending too.
		b.clearDropsLocked()
		return nil
	}
	// The file is back as it was (reloadRootsLocked) and the adds go back
	// out of the table. A removal stands whatever the reload said.
	b.applyRoots(nil, rootNames(added))
	var listed bool
	if len(drop) > 0 {
		listed, _ = b.writeWithoutLocked(drop)
	}
	if notAnswered(err) {
		// The reload got no answer: the change waits for the engine's next
		// one, which the probe asked for here finds. A held add is offered
		// again then, crossing or not (OnHeld), and its caller is told it
		// waits, as a refused add's caller is.
		b.log.Warn("the streaming engine did not answer a root reload; the change waits for its next answer",
			"added", rootNames(added), "removed", rootNames(dropped), "err", err)
		held := b.holdLocked(added)
		if len(dropped) > 0 || listed {
			b.pendDropsLocked(drop)
		}
		b.reloadUnanswered(err)
		if len(held) > 0 {
			return ErrRootHeld
		}
		return nil
	}
	return err
}

// offerHeld hands the adds held for an answer to the OnHeld hooks, to be
// offered again.
func (b *Bridge) offerHeld() {
	b.reloadMu.Lock()
	var held []string
	if b.pending != nil {
		held = rootNames(b.pending.adds)
	}
	b.reloadMu.Unlock()
	if len(held) == 0 {
		return
	}
	b.linkMu.Lock()
	hooks := slices.Clone(b.onHeld)
	b.told = append(b.told, func() {
		for _, fn := range hooks {
			fn(held)
		}
	})
	b.linkMu.Unlock()
	b.runHooks()
}

// changeUnreloadableLocked takes a change for a sidecar that serves no
// reloads. A removal is written to its config, which takes effect at its
// next start, whether or not the bridge mapped the root. An add is not:
// the reload is what proves the sidecar can see a path, and a config it
// cannot open is a boot failure. The bridge keeps the root either way:
// its table is WaxDeck's own view, and an operator who adds the root to
// the sidecar and restarts it gets streaming without restarting WaxDeck
// too.
func (b *Bridge) changeUnreloadableLocked(add []Root, drop []string) error {
	b.unholdLocked(rootNames(add), drop)
	b.applyRoots(add, drop)
	if len(drop) > 0 {
		if _, err := b.writeWithoutLocked(drop); err != nil {
			return err
		}
	}
	return byHand(add, fmt.Sprintf("the sidecar at %s does not accept root reloads, so", b.base))
}

// changeWhileAwayLocked takes a change while the engine is away. A removal
// leaves the table and the file at once, the file whether or not the
// bridge mapped the root (a start maps only the catalog's roots), and its
// reload is left pending; an add is held, out of both, until the engine
// answers.
func (b *Bridge) changeWhileAwayLocked(add []Root, drop []string) error {
	// A path this server cannot see as a directory is refused now, in
	// words the administrator can act on, rather than at the engine's
	// answer.
	for _, r := range add {
		if info, err := os.Stat(r.Path); err != nil || !info.IsDir() {
			return fmt.Errorf("%s is not a directory this server can see, so the streaming sidecar could not open it either", r.Path)
		}
	}
	b.unholdLocked(drop)
	_, dropped := b.applyRoots(nil, drop)
	var listed bool
	if len(drop) > 0 {
		// The removal stands in the table whatever the file says, so
		// nothing mints a stream under the root; the caller makes it again.
		var err error
		if listed, err = b.writeWithoutLocked(drop); err != nil {
			return err
		}
	}
	var removed []string
	if len(dropped) > 0 || listed {
		removed = drop
		b.pendDropsLocked(drop)
	}
	held := b.holdLocked(add)
	if len(held) > 0 || len(removed) > 0 {
		b.log.Info("waxflow roots changed while it is away; removals are written for its next start, adds wait to be checked when it answers",
			"held", rootNames(held), "removed", removed)
	}
	return nil
}

// reloadPending reloads the removals made while the engine was away, once,
// on an answer: the one that ends the outage, before it is taken, so the
// crossing's hooks see the table settled, and again just after, for a
// removal made while it was being taken. A reload that gets no answer is
// returned, and the removals wait for the next answer; a refused one is
// said once and let go, since the file already lacks them.
func (b *Bridge) reloadPending(ctx context.Context, caps *client.Caps) error {
	b.reloadMu.Lock()
	defer b.reloadMu.Unlock()
	if b.pending == nil || len(b.pending.drops) == 0 {
		return nil
	}
	drops := b.pending.drops
	if !caps.Delivery.RootsReload {
		b.log.Info("the streaming sidecar serves no root reloads; the roots removed from its config while it was away go when it next starts",
			"removed", drops)
		b.clearDropsLocked()
		return nil
	}
	err := b.reloadRootsLocked(ctx, drops)
	switch {
	case err == nil:
	case notAnswered(err):
		return err
	default:
		b.log.Warn("the streaming sidecar refused a reload of the roots removed while it was away; its config no longer names them, so they go when it next starts",
			"removed", drops, "err", err)
	}
	b.clearDropsLocked()
	return nil
}

// notAnswered reports whether err is a call to the engine that got no
// answer at all (a connection refused, dropped or reset, or none in
// time), which is no refusal: the engine never said.
func notAnswered(err error) bool {
	var transport *url.Error
	return errors.As(err, &transport)
}

// reloadUnanswered is a reload that got no answer: one cut off finds the
// engine gone, one that ran out of time asks for a probe, as a stream
// does.
func (b *Bridge) reloadUnanswered(err error) {
	var transport *url.Error
	if errors.As(err, &transport) && transport.Timeout() {
		b.probeSoon()
		return
	}
	b.lost(err)
}

// holdLocked holds adds for the engine's next answer, unless one of that
// name is mapped already, and answers what it now holds anew.
func (b *Bridge) holdLocked(add []Root) (held []Root) {
	mapped := b.RootNames()
	for _, r := range add {
		if slices.Contains(mapped, r.Name) {
			continue
		}
		if b.pending == nil {
			b.pending = &rootsPending{}
		}
		i := slices.IndexFunc(b.pending.adds, func(have Root) bool { return have.Name == r.Name })
		switch {
		case i < 0:
			b.pending.adds = append(b.pending.adds, r)
			held = append(held, r)
		case b.pending.adds[i] != r:
			b.pending.adds[i] = r
			held = append(held, r)
		}
	}
	return held
}

// unholdLocked lets go of held adds by name: offered now, or removed
// before they ever were.
func (b *Bridge) unholdLocked(names ...[]string) {
	if b.pending == nil {
		return
	}
	for _, set := range names {
		b.pending.adds = slices.DeleteFunc(b.pending.adds, func(r Root) bool { return slices.Contains(set, r.Name) })
	}
	b.prunePendingLocked()
}

// pendDropsLocked notes removals for the next answer to reload.
func (b *Bridge) pendDropsLocked(drops []string) {
	if b.pending == nil {
		b.pending = &rootsPending{}
	}
	for _, name := range drops {
		if !slices.Contains(b.pending.drops, name) {
			b.pending.drops = append(b.pending.drops, name)
		}
	}
}

// clearDropsLocked forgets the removals left pending, which a reload has
// carried.
func (b *Bridge) clearDropsLocked() {
	if b.pending != nil {
		b.pending.drops = nil
		b.prunePendingLocked()
	}
}

// prunePendingLocked drops a pending set with nothing left in it.
func (b *Bridge) prunePendingLocked() {
	if b.pending != nil && len(b.pending.adds) == 0 && len(b.pending.drops) == 0 {
		b.pending = nil
	}
}

// writeWithoutLocked takes the named roots out of the config file, every
// other entry and key left as it was, answering whether it listed any; a
// file that lists none is left as it is.
func (b *Bridge) writeWithoutLocked(drop []string) (bool, error) {
	raw, perm, err := readRootsConfig(b.configPath)
	var listed bool
	if err == nil {
		var out []byte
		if out, listed, err = withoutRoots(raw, b.configPath, drop); err == nil && listed {
			err = writeRootsConfig(b.configPath, out, perm, nil)
		}
	}
	if err != nil {
		b.log.Warn("taking removed roots out of the sidecar config", "path", b.configPath, "removed", drop, "err", err)
	}
	return listed, err
}

// namesAnyLocked reports whether the table maps, or the config file lists,
// a root of one of the names. A file that cannot be read counts, so the
// change that meets it says why.
func (b *Bridge) namesAnyLocked(names []string) bool {
	if slices.ContainsFunc(b.RootNames(), func(name string) bool { return slices.Contains(names, name) }) {
		return true
	}
	raw, _, err := readRootsConfig(b.configPath)
	if err != nil {
		return true
	}
	_, listed, err := withoutRoots(raw, b.configPath, names)
	return listed || err != nil
}

// applyRoots changes the bridge's table: the roots named in drop go, then
// the ones in add come in unless one of that name is there. It answers
// what changed.
func (b *Bridge) applyRoots(add []Root, drop []string) (added, dropped []Root) {
	b.rootsMu.Lock()
	defer b.rootsMu.Unlock()
	roots := make([]Root, 0, len(b.roots)+len(add))
	for _, r := range b.roots {
		if slices.Contains(drop, r.Name) {
			dropped = append(dropped, r)
			continue
		}
		roots = append(roots, r)
	}
	for _, r := range add {
		if !slices.ContainsFunc(roots, func(have Root) bool { return have.Name == r.Name }) {
			roots = append(roots, r)
			added = append(added, r)
		}
	}
	sortRoots(roots)
	b.roots = roots
	return added, dropped
}

// rootNames lists the roots' names.
func rootNames(roots []Root) []string {
	names := make([]string, len(roots))
	for i, r := range roots {
		names[i] = r.Name
	}
	return names
}

// writeRootSet writes the config file's roots as the bridge has them:
// the names in drop taken out, then every root in roots the file lacks
// merged in, every other key left as it was.
func writeRootSet(path string, raw []byte, perm os.FileMode, roots []Root, drop []string) error {
	if len(drop) > 0 {
		var err error
		if raw, _, err = withoutRoots(raw, path, drop); err != nil {
			return err
		}
	}
	return writeRootsConfig(path, raw, perm, roots)
}

// withoutRoots takes the named roots out of the config file's bytes, the
// way mergeRootsConfig puts them in: by name, every other entry and key
// left as it was. It answers whether the file listed any of them, and the
// bytes as they were when it listed none.
func withoutRoots(raw []byte, path string, drop []string) ([]byte, bool, error) {
	cfg := map[string]any{}
	if len(bytes.TrimSpace(raw)) > 0 {
		if err := json.Unmarshal(raw, &cfg); err != nil {
			return nil, false, fmt.Errorf("flow: sidecar config %s is not a JSON object: %w", path, err)
		}
	}
	existing, _ := cfg["roots"].([]any)
	kept := make([]any, 0, len(existing))
	for _, e := range existing {
		if obj, ok := e.(map[string]any); ok {
			if name, _ := obj["name"].(string); slices.Contains(drop, name) {
				continue
			}
		}
		kept = append(kept, e)
	}
	if len(kept) == len(existing) {
		return raw, false, nil
	}
	cfg["roots"] = kept
	out, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return nil, false, fmt.Errorf("flow: encoding sidecar config: %w", err)
	}
	return append(out, '\n'), true, nil
}
