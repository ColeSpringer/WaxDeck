package service

import (
	"context"
	"strings"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// SetItemCredits replaces one contributor role's people. A book
// translator or editor credit has no tag form: a write-back request for
// those still edits the catalog and answers with a warning.
func (l *Editor) SetItemCredits(ctx context.Context, uc *UserCtx, apiPID, role string, names []string, p MetadataEditParams) (EditOutcomeDTO, error) {
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	r := model.ContributorRole(strings.ToLower(strings.TrimSpace(role)))
	if !model.RoleValidForKind(r, it.Kind) {
		return EditOutcomeDTO{}, errInvalid("role " + role + " does not apply to a " + mediaTypeForKind(it.Kind) + " item" +
			bookOnlyHint(it.Kind, model.RoleValidForKind(r, model.KindBook)))
	}
	if len(names) > 100 {
		return EditOutcomeDTO{}, errInvalid("at most 100 names per role")
	}
	var warnings []string
	writeBack := p.WriteBack
	if writeBack && (r == model.RoleTranslator || r == model.RoleEditor) {
		// No round-trippable tag exists for these roles; the catalog edit
		// still lands and the caller learns why the files stay untouched.
		writeBack = false
		warnings = append(warnings, "role "+string(r)+" has no on-disk tag form; the credit is database-only")
	}
	if writeBack {
		if err := l.Settings.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	// The skipped bool only ever reports true under SkipLocked, which this
	// path does not pass: a locked credit is refused here, not skipped.
	_, _, err = l.lib.SetCredits(ctx, it.PID, r, names, waxbin.CreditEditOptions{
		WriteBack: writeBack, Lock: model.LockOf(p.Lock), Force: p.Force,
	})
	out, err := editOutcomeFromWriteBack(err)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	out.Warnings = append(out.Warnings, warnings...)
	return out, nil
}

// SetItemCreditsBatch replaces several roles' contributors on one item
// in a single upstream transaction. The compound commit uses it where
// the sequential path calls SetItemCredits per role, because gathering
// the roles lets upstream's rename pre-pass see every reference before
// the first write: an artist the whole batch moves is renamed in place,
// keeping its pid, art, curation and stars, instead of being left
// behind while a fresh row takes the credits.
//
// SkipLocked stays off, so a locked credit refuses the batch exactly as
// it refuses a single role. The batch is atomic, so the refusal takes
// every role with it; the caller's report says so.
func (l *Editor) SetItemCreditsBatch(ctx context.Context, uc *UserCtx, apiPID string, credits []CommitCreditsDTO, p MetadataEditParams) (EditOutcomeDTO, error) {
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	edits := make([]model.ItemCreditEdit, 0, len(credits))
	var warnings []string
	for _, cr := range credits {
		r := model.ContributorRole(strings.ToLower(strings.TrimSpace(cr.Role)))
		if !model.RoleValidForKind(r, it.Kind) {
			return EditOutcomeDTO{}, errInvalid("role " + cr.Role + " does not apply to a " + mediaTypeForKind(it.Kind) + " item" +
				bookOnlyHint(it.Kind, model.RoleValidForKind(r, model.KindBook)))
		}
		if len(cr.Names) > 100 {
			return EditOutcomeDTO{}, errInvalid("at most 100 names per role, and " + cr.Role + " carries more")
		}
		// Named, not switched off: upstream mirrors the batch one pass
		// per file and refuses only the roles with no round-trippable
		// tag, so the author beside a translator still reaches the file.
		// Turning write-back off for the whole batch would leave that
		// author on disk as it was, and the next scan would read the old
		// value back over the edit.
		if p.WriteBack && (r == model.RoleTranslator || r == model.RoleEditor) {
			warnings = append(warnings, "role "+string(r)+" has no on-disk tag form; that credit is database-only")
		}
		edits = append(edits, model.ItemCreditEdit{ItemPID: it.PID, Role: r, Names: cr.Names})
	}
	if p.WriteBack {
		if err := l.Settings.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	res, err := l.lib.SetCreditsBatch(ctx, edits, waxbin.CreditEditOptions{
		WriteBack: p.WriteBack, Lock: model.LockOf(p.Lock), Force: p.Force,
	})
	if err != nil {
		return EditOutcomeDTO{}, classify(err)
	}
	out := EditOutcomeDTO{Warnings: warnings}
	for _, wbe := range res.WriteBackErrors {
		out.Failures = append(out.Failures, writeBackFailures(wbe)...)
	}
	return out, nil
}
