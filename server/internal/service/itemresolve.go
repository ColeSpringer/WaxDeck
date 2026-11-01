package service

import (
	"context"
	"fmt"

	"github.com/colespringer/waxbin/model"
)

// maxItemLookup bounds one item lookup; a longer list, a queue for one, is
// read back in pieces of it.
const maxItemLookup = 100

// ResolveItems answers the summaries behind a list of item pids, each as
// GET /items/{pid} answers it, in request order and once per occurrence,
// and names the pids no item answers to.
//
// A pid the caller cannot be answered for is left out rather than erroring.
// Departed is the subset gone for everyone: the catalog holds no item under
// its ULID (a kind change folded it into another), the one it holds is of a
// kind the prefix never reaches, or its item lost its files for good
// (purged from the trash, deleted permanently, or its library removed),
// which this lookup leaves out though the item's own read still answers it.
// An item in the trash, which a restore brings back, is answered as that
// read answers it. One out of the caller's sight, a grant or a content rule
// away, is left out unnamed, because each of those can end with the item
// back, and a client dropping it would turn that into a loss.
func (l *Library) ResolveItems(ctx context.Context, uc *UserCtx, apiPIDs []string) ([]ItemSummary, []string, error) {
	if len(apiPIDs) > maxItemLookup {
		return nil, nil, errInvalid(fmt.Sprintf("at most %d pids", maxItemLookup))
	}
	type ask struct {
		api, prefix string
		pid         model.PID
	}
	asks := make([]ask, 0, len(apiPIDs))
	pids := make([]model.PID, 0, len(apiPIDs))
	for _, api := range apiPIDs {
		// parseAPIPID answers the ULID in its stored spelling, whatever
		// case was asked; departed names the pid as it was asked.
		prefix, pid, ok := parseAPIPID(api)
		if !ok || !itemPrefix(prefix) {
			return nil, nil, errInvalid("not an item pid: " + api)
		}
		asks = append(asks, ask{api: api, prefix: prefix, pid: pid})
		pids = append(pids, pid)
	}
	views, err := l.readItems(ctx, pids)
	if err != nil {
		return nil, nil, classify(err)
	}
	read := make([]*model.ItemView, 0, len(views))
	for _, v := range views {
		read = append(read, v)
	}
	verdicts, err := l.tagVerdicts(ctx, uc, read)
	if err != nil {
		return nil, nil, err
	}
	shown := make(map[model.PID]bool, len(views))
	for pid, v := range views {
		shown[pid] = l.viewVisible(ctx, uc, v) && l.contentAllows(ctx, uc, verdicts, v)
	}
	final := l.deletedForGood(ctx, views)

	out := make([]ItemSummary, 0, len(asks))
	var departed []string
	named := map[string]bool{}
	for _, a := range asks {
		v := views[a.pid]
		if v == nil || !prefixFitsKind(a.prefix, v.Kind) || final[a.pid] {
			if !named[a.api] {
				named[a.api] = true
				departed = append(departed, a.api)
			}
			continue
		}
		if shown[a.pid] {
			out = append(out, summary(v))
		}
	}
	return out, departed, nil
}

// deletedForGood names the archived items among views that nothing in the
// trash can restore. An item is archived when it loses its last file (a
// delete, its library removed, a prune), so one with no active trash entry
// lost its files for good, the distinction a catalog sync tombstone draws
// too (tombstoneReason). A trash read that fails names none, the safe answer
// for a caller that drops what departs.
func (l *Library) deletedForGood(ctx context.Context, views map[model.PID]*model.ItemView) map[model.PID]bool {
	var gone []model.PID
	for pid, v := range views {
		if archived(v) {
			gone = append(gone, pid)
		}
	}
	if len(gone) == 0 {
		return nil
	}
	restorable, err := l.lib.RestorableTrash(ctx, gone)
	if err != nil {
		l.log.Warn("reading the trash for an item lookup", "err", err)
		return nil
	}
	out := make(map[model.PID]bool, len(gone))
	for _, pid := range gone {
		if len(restorable[pid]) == 0 {
			out[pid] = true
		}
	}
	return out
}
