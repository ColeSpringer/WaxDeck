package service

import (
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strings"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/waxerr"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// maxKindItems is the most items one kind change names.
const maxKindItems = 500

// KindTallyDTO is what a kind change did, its pids in their current form
// once nameJobTargets shapes them: Converted changed kind in place,
// Absorbed maps each pid folded away to the item that took it in,
// Created are the parts a book split minted, and WriteBackFailures name
// the files whose tags could not be written.
type KindTallyDTO struct {
	Converted         []string
	Absorbed          map[string]string
	Created           []string
	WriteBackFailures []WriteBackFailureDTO
}

// SetItemsKind starts the job that turns the named items into tracks or
// a book. Every item must be one the caller can see and may curate, or
// nothing starts; a kind someone pinned before is replaced, since the
// caller may edit the item. With writeBack the kind is also written into
// the files, which every item's library must then allow.
func (l *Library) SetItemsKind(ctx context.Context, uc *UserCtx, apiPIDs []string, mediaType string, writeBack bool) (Job, error) {
	if len(apiPIDs) == 0 || len(apiPIDs) > maxKindItems {
		return Job{}, errInvalid(fmt.Sprintf("name between 1 and %d items", maxKindItems))
	}
	var kind model.Kind
	switch mediaType {
	case "music":
		kind = model.KindTrack
	case "audiobook":
		kind = model.KindBook
	default:
		return Job{}, errInvalid("items become music or an audiobook")
	}
	pids := make([]model.PID, 0, len(apiPIDs))
	var target string
	for _, apiPID := range apiPIDs {
		it, err := l.getVisibleItem(ctx, uc, apiPID)
		if err != nil {
			return Job{}, err
		}
		if it.Kind == model.KindEpisode {
			return Job{}, errInvalid("a podcast episode is what its feed says it is")
		}
		may, err := l.MayCurateItem(ctx, uc, apiPID)
		if err != nil {
			return Job{}, &Error{Kind: KindInternal, Err: err}
		}
		if !may {
			return Job{}, &Error{Kind: KindForbidden,
				Msg: "administrators, or the user whose upload brought every one of these items in"}
		}
		if writeBack {
			if err := l.checkPathWritable(ctx, string(it.Path)); err != nil {
				return Job{}, err
			}
		}
		pids = append(pids, it.PID)
		if target == "" {
			target = itemAPIPID(it)
		}
	}
	jobPID, err := l.lib.StartSetItemKind(l.procCtx, pids, kind, waxbin.KindOptions{WriteBack: writeBack, Force: true})
	if err != nil {
		return Job{}, l.kindRefusal(err)
	}
	// Audited before its starter is recorded: the follow-up that record
	// settles then finds the entry to give the item's new prefix.
	l.Audit(ctx, uc, "item.kind", AuditTarget{Kind: "item", PID: target}, map[string]any{
		"pids": apiPIDs, "mediaType": mediaType, "writeBack": writeBack, "job": apiPID(PrefixJob, jobPID),
	})
	l.followStarted(ctx, jobPID, uc.ID)
	// The job is the caller's whether or not the record of who started it
	// landed, so its answer reads it directly, narrowed as JobStatusFor
	// narrows it for a starter who is not an administrator.
	job, err := l.JobStatus(ctx, apiPID(PrefixJob, jobPID))
	if err != nil || uc.Admin {
		return job, err
	}
	l.narrowJob(ctx, uc, &job)
	return job, nil
}

// kindRefusal words a refused kind change. WaxBin's refusals name display
// paths and bare pids, which are not every caller's to read, so each is
// logged and answered in WaxDeck's words; its two conflicts, a lease
// another job holds and a part not on disk, are told apart by the message.
func (l *Library) kindRefusal(err error) error {
	msg := err.Error()
	switch waxerr.CodeOf(err) {
	case waxerr.CodeConflict:
		if strings.Contains(msg, "another job holds scope") {
			return classifyMutation(err)
		}
		l.log.Info("a kind change was refused", "err", err)
		return &Error{Kind: KindConflict, Err: err,
			Msg: "a file of one of these items is not on disk, so it cannot be read as the new kind"}
	case waxerr.CodeInvalid:
		l.log.Info("a kind change was refused", "err", err)
		var why string
		switch {
		case strings.Contains(msg, "is a cue track"):
			why = "one of these items is a cue track, whose kind follows the file it is cut from"
		case strings.Contains(msg, "shares the file"):
			why = "one of these items shares its file with another item"
		case strings.Contains(msg, "cue sheet beside"):
			why = "one of these items has a cue sheet beside its file, which would cut it into cue tracks; move the sheet aside first"
		default:
			why = "these items cannot change kind"
		}
		return &Error{Kind: KindInvalid, Msg: why, Err: err}
	}
	return classify(err)
}

// kindTally reads a finished kind change's report, its pids still bare
// for nameJobTargets to shape.
func kindTally(raw string) *KindTallyDTO {
	var r waxbin.KindReport
	if json.Unmarshal([]byte(raw), &r) != nil {
		return nil
	}
	out := &KindTallyDTO{}
	for _, p := range r.Converted {
		out.Converted = append(out.Converted, string(p))
	}
	for _, p := range r.Created {
		out.Created = append(out.Created, string(p))
	}
	if len(r.Absorbed) > 0 {
		out.Absorbed = make(map[string]string, len(r.Absorbed))
		for from, to := range r.Absorbed {
			out.Absorbed[string(from)] = string(to)
		}
	}
	for _, f := range r.WriteBackFailures {
		out.WriteBackFailures = append(out.WriteBackFailures,
			WriteBackFailureDTO{FilePID: string(f.FilePID), Path: f.Path, Reason: f.Reason})
	}
	return out
}

// kindTallyPIDs lists the items a kind change's report names that may
// still be there: the converted, the created, and those others folded
// into.
func kindTallyPIDs(t *KindTallyDTO) []model.PID {
	out := make([]model.PID, 0, len(t.Converted)+len(t.Created)+len(t.Absorbed))
	for _, p := range t.Converted {
		out = append(out, model.PID(p))
	}
	for _, p := range t.Created {
		out = append(out, model.PID(p))
	}
	for _, to := range t.Absorbed {
		out = append(out, model.PID(to))
	}
	return out
}

// shapeKindTally gives a kind change's pids their current prefix from
// items, the items read for them: an item still there takes its kind's,
// and an absorbed one, which is gone, the kind it had, the other of the
// item that took it in.
func shapeKindTally(t *KindTallyDTO, items map[model.PID]*model.ItemView) {
	current := func(bare string) string {
		if it := items[model.PID(bare)]; it != nil {
			return itemAPIPID(it)
		}
		return bare
	}
	for i, p := range t.Converted {
		t.Converted[i] = current(p)
	}
	for i, p := range t.Created {
		t.Created[i] = current(p)
	}
	if len(t.Absorbed) > 0 {
		shaped := make(map[string]string, len(t.Absorbed))
		for from, to := range t.Absorbed {
			survivor := current(to)
			was := PrefixTrack
			if strings.HasPrefix(survivor, PrefixTrack+"-") {
				was = PrefixBook
			}
			shaped[apiPID(was, model.PID(from))] = survivor
		}
		t.Absorbed = shaped
	}
}

// readItems reads the items pids name, each once, keyed by pid: from the
// catalog in one batch, which a long list spreads over a few statements.
// One the catalog no longer has is absent.
func (l *Library) readItems(ctx context.Context, pids []model.PID) (map[model.PID]*model.ItemView, error) {
	out := make(map[model.PID]*model.ItemView, len(pids))
	uniq := make([]model.PID, 0, len(pids))
	seen := make(map[model.PID]bool, len(pids))
	for _, p := range pids {
		if p != "" && !seen[p] {
			seen[p] = true
			uniq = append(uniq, p)
		}
	}
	if len(uniq) == 0 {
		return out, nil
	}
	if l.kindReadHook != nil {
		for _, p := range uniq {
			it, err := l.kindReadHook(ctx, p)
			switch {
			case err == nil:
				out[p] = it
			case KindOf(classify(err)) != KindNotFound:
				return out, err
			}
		}
		return out, nil
	}
	views, err := l.lib.GetMany(ctx, uniq)
	if err != nil {
		return out, err
	}
	for _, v := range views {
		out[v.PID] = v
	}
	return out, nil
}

// followKindChange brings WaxDeck's own rows to a finished kind change:
// rows keyed by a pid folded away move to the item that took it in,
// rows holding a pid's prefixed form take the prefix its kind has now,
// and the parts a book split minted are granted to whoever could edit
// the book. Run again it finds nothing left to move, so a restart
// repeating it is harmless; a failure is answered, for the caller to
// keep the job's origin and try again at the next start.
func (l *Library) followKindChange(ctx context.Context, j *model.Job) error {
	if j.Result == "" {
		return nil
	}
	var r waxbin.KindReport
	if err := json.Unmarshal([]byte(j.Result), &r); err != nil {
		l.log.Warn("reading a kind change's report", "job", string(j.PID), "err", err)
		return nil
	}
	// A bounded transaction: a stop asked for mid-way must not cut it.
	ctx = context.WithoutCancel(ctx)
	moves := wdb.KindMoves{Absorbed: map[string]string{}, Kinds: map[string]string{}, Created: map[string]string{},
		Grants: map[string]string{}}
	albums := map[model.PID]model.PID{}
	// An item gone since has nothing to move; a catalog that could not
	// answer fails the follow-up, which keeps it for a repeat.
	pids := slices.Concat(r.Converted, r.Created)
	for _, to := range r.Absorbed {
		pids = append(pids, to)
	}
	items, readErr := l.readItems(ctx, pids)
	kindOf := func(p model.PID) {
		if it := items[p]; it != nil {
			moves.Kinds[string(p)] = mediaTypeForKind(it.Kind)
			albums[p] = it.AlbumPID
		}
	}
	for _, p := range r.Converted {
		kindOf(p)
	}
	for from, to := range r.Absorbed {
		moves.Absorbed[string(from)] = string(to)
		kindOf(to)
	}
	// A split part came from the converted item on its album: the book
	// keeps its pid on its first part, and the others land beside it.
	// One on no such album is the split book's only when the change
	// split that one book and folded no other, which could have minted
	// it too.
	var split []model.PID
	for _, p := range r.Converted {
		if moves.Kinds[string(p)] == "music" {
			split = append(split, p)
		}
	}
	for _, c := range r.Created {
		it := items[c]
		if it == nil {
			continue
		}
		for _, p := range split {
			if albums[p] != "" && albums[p] == it.AlbumPID {
				moves.Created[string(c)] = string(p)
				break
			}
		}
		if _, ok := moves.Created[string(c)]; !ok && len(split) == 1 && len(r.Absorbed) == 0 {
			moves.Created[string(c)] = string(split[0])
		}
	}
	// A part no book can be named for is still its starter's when they
	// are not an administrator: they could edit every item they named,
	// so whichever it came from, they may edit the part too.
	if unplaced := len(r.Created) - len(moves.Created); unplaced > 0 {
		starter, err := l.jobStarter(ctx, j.PID)
		if err != nil {
			readErr = cmp.Or(readErr, err)
		} else if starter != "" && !l.userIsAdmin(ctx, starter) {
			for _, c := range r.Created {
				if _, ok := moves.Created[string(c)]; !ok {
					moves.Grants[string(c)] = starter
				}
			}
		}
	}
	if readErr != nil {
		l.log.Warn("reading a kind change's items", "job", string(j.PID), "err", readErr)
		return readErr
	}
	if len(moves.Absorbed) == 0 && len(moves.Kinds) == 0 && len(moves.Created) == 0 && len(moves.Grants) == 0 {
		return nil
	}
	remap := l.db.RemapItems
	if l.remapHook != nil {
		remap = l.remapHook
	}
	if err := remap(ctx, moves); err != nil {
		l.log.Warn("moving WaxDeck's rows after a kind change", "job", string(j.PID), "err", err)
		return err
	}
	return nil
}

// userIsAdmin reports whether an account holds the administrator role; one
// that cannot be read does not.
func (l *Library) userIsAdmin(ctx context.Context, userID string) bool {
	u, err := l.db.UserByID(ctx, userID)
	return err == nil && hasRole(u.Roles, "admin")
}
