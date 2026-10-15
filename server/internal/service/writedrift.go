package service

import (
	"context"
	"errors"
	"slices"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// writeDrift is how far an item's files lag the catalog: a write-back
// refused, failed or lost, and the values an edit changed in the catalog
// alone, by key.
type writeDrift struct {
	unsynced bool
	owed     []string
}

func (d writeDrift) any() bool { return d.unsynced || len(d.owed) > 0 }

// itemWriteDrift reads an item's write drift from the diagnostics of the
// files the sweep grades it by, leaving out what a clean-up pass rewrote
// in the catalog alone.
func (l *Library) itemWriteDrift(ctx context.Context, it *model.ItemView) (writeDrift, error) {
	rows, err := l.lib.FileDiagnostics(ctx, model.DiagnosticFilter{ItemPID: it.PID})
	if err != nil {
		return writeDrift{}, classify(err)
	}
	graded := map[model.PID]bool{}
	for _, f := range l.gradedFiles(ctx, it) {
		graded[f.FilePID] = true
	}
	var d writeDrift
	var owed []string
	for _, r := range rows {
		if !graded[r.FilePID] {
			continue
		}
		switch r.Code {
		case model.DiagTagWriteUnsynced, model.DiagTagWriteLost:
			d.unsynced = true
		case model.DiagTagWriteOwed:
			if !slices.Contains(owed, r.TagKey) {
				owed = append(owed, r.TagKey)
			}
		}
	}
	d.owed, err = l.owedBesideNormalized(ctx, it.PID, owed)
	return d, err
}

// fixWriteDrift writes an item's lagging values into its files, counting
// it filled only once nothing is owed: a write the file refused is
// skipped as refused, and a value left owed (an album's, or an origin's,
// which their own editors write) as still out of sync. A refusal from a
// file the item is not graded by, a copy in a read-only library, does
// not hold back a fill.
func (l *Library) fixWriteDrift(ctx context.Context, it *model.ItemView, sum *healthFixSummary) {
	drift, err := l.itemWriteDrift(ctx, it)
	if err != nil {
		sum.Failed++
		return
	}
	if !drift.any() {
		sum.Skipped["already in sync"]++
		return
	}
	paid := l.payWriteDrift(ctx, it, drift)
	if paid != nil && !writeBackRefusedOnly(paid) {
		sum.Failed++
		return
	}
	switch now, err := l.itemWriteDrift(ctx, it); {
	case err != nil:
		sum.Failed++
	case !now.any():
		sum.Filled++
	case paid != nil:
		sum.Skipped["write refused"]++
	default:
		sum.Skipped["still out of sync"]++
	}
}

// writeBackRefusedOnly reports whether err is made of write-back refusals
// alone: a hard failure joined beside them makes the pass a failure.
func writeBackRefusedOnly(err error) bool {
	switch e := err.(type) {
	case *waxbin.WriteBackError:
		return true
	case interface{ Unwrap() []error }:
		parts := e.Unwrap()
		for _, p := range parts {
			if !writeBackRefusedOnly(p) {
				return false
			}
		}
		return len(parts) > 0
	case interface{ Unwrap() error }:
		return writeBackRefusedOnly(e.Unwrap())
	}
	return false
}

// creditTwin is the plain field a role's credit shares its column with on
// an item of kind k, or "": a track's artist and composer, a book's author
// and narrator. A write through either spelling settles the other's owed
// row, and retires its provenance row unless that still describes the
// column.
func creditTwin(k model.Kind, role string) string {
	switch r := model.ContributorRole(role); {
	case k == model.KindTrack && (r == model.RoleArtist || r == model.RoleComposer),
		k == model.KindBook && (r == model.RoleAuthor || r == model.RoleNarrator):
		return role
	}
	return ""
}

// payWriteDrift re-asserts each owed value through the verb that owns
// it, with write-back, under the attribution the value carries so the
// fix does not turn a source's value into a person's: scalar fields,
// credits, custom tags and the item's own front cover. A file that
// refused or lost a write, and that nothing else here writes, is
// rewritten by re-asserting its title.
func (l *Library) payWriteDrift(ctx context.Context, it *model.ItemView, drift writeDrift) error {
	prov, err := l.lib.Provenance(ctx, it.PID)
	if err != nil {
		return err
	}
	attribution := map[string]model.Attribution{}
	for _, p := range prov {
		attribution[p.Field] = p.Attribution
	}
	// A value with no row came from the file's own tags, and an empty
	// source would record it as a person's edit.
	attributionOf := func(field string) model.Attribution {
		if a, ok := attribution[field]; ok {
			return a
		}
		return model.Attribution{Source: model.SourceTag}
	}
	vocabulary := map[string]bool{}
	for _, f := range editorFieldsForKind(it.Kind) {
		vocabulary[f.Name] = true
	}
	values := editorScalarFields(it, prov)
	fields := map[model.Attribution]map[string]string{}
	payField := func(key, value string) {
		a := attributionOf(key)
		if fields[a] == nil {
			fields[a] = map[string]string{}
		}
		fields[a][key] = value
	}
	var roles, tags []string
	var art bool
	for _, key := range drift.owed {
		role, credit := model.CutCreditPrefix(key)
		tagKey, custom := model.CutTagPrefix(key)
		_, hasRow := attribution[key]
		switch twin := creditTwin(it.Kind, role); {
		case credit && twin != "" && !hasRow:
			// A write through the plain twin retired the credit's row, so
			// the twin holds the column: paying it pays both, where the
			// credit would re-assert the names it replaced, or none.
			payField(twin, values[twin])
		case credit:
			roles = append(roles, role)
		case custom:
			tags = append(tags, tagKey)
		case key == model.OwedArt:
			art = true
		case vocabulary[key]:
			payField(key, values[key])
		}
	}
	if drift.unsynced && len(fields) == 0 && len(roles) == 0 && len(tags) == 0 {
		payField("title", it.Title)
	}
	var errs []error
	for a, edit := range fields {
		errs = append(errs, l.lib.EditFields(ctx, it.PID, edit, waxbin.EditOptions{
			WriteBack: true, Force: true, Lock: model.LockUnchanged, Source: a.Source, Provider: a.Provider,
		}))
	}
	if len(roles) > 0 {
		credits, err := l.lib.Credits(ctx, it.PID)
		if err != nil {
			return err
		}
		for _, role := range roles {
			var names []string
			for _, c := range credits {
				if string(c.Role) == role {
					names = append(names, c.Name)
				}
			}
			a := attributionOf(model.CreditField(model.ContributorRole(role)))
			_, _, err := l.lib.SetCredits(ctx, it.PID, model.ContributorRole(role), names, waxbin.CreditEditOptions{
				WriteBack: true, Force: true, Lock: model.LockUnchanged, Source: a.Source, Provider: a.Provider,
			})
			errs = append(errs, err)
		}
	}
	if len(tags) > 0 {
		held, err := l.lib.ItemTags(ctx, it.PID)
		if err != nil {
			return err
		}
		for _, key := range tags {
			var vals []string
			for _, t := range held {
				if t.Key == key {
					vals = t.Values
				}
			}
			a := attributionOf(model.TagLockField(key))
			_, _, err := l.lib.SetItemTag(ctx, it.PID, key, vals, waxbin.TagEditOptions{
				WriteBack: true, Force: true, Lock: model.LockUnchanged, Source: a.Source, Provider: a.Provider,
			})
			errs = append(errs, err)
		}
	}
	if art {
		errs = append(errs, l.payOwedArt(ctx, it, attributionOf(model.OwedArt)))
	}
	return errors.Join(errs...)
}

// payOwedArt embeds the item's own front cover in its files again. A
// cover cleared in the catalog has nothing to embed, and stays owed: the
// catalog's chain would answer with the album's, an artist's or a
// genre's picture, which is not the item's to carry.
func (l *Library) payOwedArt(ctx context.Context, it *model.ItemView, a model.Attribution) error {
	ref := model.EntityRef{Type: model.ArtTrack, PID: it.PID}
	if it.Kind == model.KindEpisode {
		ref.Type = model.ArtEpisode
	}
	if p, err := l.lib.ArtProvenance(ctx, ref, model.ArtRoleFront); err != nil || p.Level != ref.Type || p.Derived {
		return nil
	}
	blob, err := l.lib.ResolveArt(ctx, ref, model.ArtRoleFront, 0)
	if err != nil || blob == nil {
		return err
	}
	return l.lib.SetItemArt(ctx, it.PID, model.ArtRoleFront, blob.Bytes, waxbin.ArtEditOptions{
		WriteBack: true, Force: true, Lock: model.LockUnchanged, Source: a.Source, Provider: a.Provider, SourceURL: a.SourceURL,
	})
}
