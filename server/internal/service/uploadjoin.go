package service

import (
	"context"
	"encoding/json"
	"os"
	"strings"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/inbox"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/scan"
)

// createdFeed follows the catalog's change feed from a point for the
// items created past it. An imported file backing an item created after
// the point is one the import made; one backing any other item joined
// it: a copy of an item the library held, or a further part of its
// book. The feed is read rather than the import's own report because
// the report says only when a file was attached as a copy, not when a
// part folded into a book or a better encoding took an item over.
type createdFeed struct {
	read    func(ctx context.Context, since int64) ([]model.Change, error)
	tail    func(ctx context.Context) (int64, error)
	seq     int64
	created map[model.PID]bool
	// broken is set once the feed cannot be followed (unreadable, or a
	// catalog replaced under it); every file then counts as joined,
	// since a grant wrongly withheld is an administrator's fix and one
	// wrongly given is the defect.
	broken bool
}

// followCreated starts following the feed from its present tail.
func (l *Ingest) followCreated(ctx context.Context) *createdFeed {
	f := &createdFeed{read: l.lib.Changes, tail: l.lib.LatestChangeSeq, created: map[model.PID]bool{}}
	f.restart(ctx)
	if f.broken {
		l.log.Warn("the change feed's tail could not be read before an import")
	}
	return f
}

// restart moves the feed's start to the catalog's present tail, just
// before a file is applied: what it then reports made is what that apply
// made, and not something another import or a scan created while an
// earlier file of the entry was applied. A feed that broke stays broken.
func (f *createdFeed) restart(ctx context.Context) {
	if f.broken {
		return
	}
	seq, err := f.tail(ctx)
	if err != nil {
		f.broken = true
		return
	}
	f.seq = seq
	clear(f.created)
}

// made reports whether the item was created since the feed's start,
// reading what the feed gained since it last looked.
func (f *createdFeed) made(ctx context.Context, pid model.PID) bool {
	for !f.broken {
		rows, err := f.read(ctx, f.seq)
		if err != nil {
			f.broken = true
			break
		}
		// Pages come back strictly after the seq asked for; one that
		// does not advance would spin, so it ends the read.
		if len(rows) == 0 || rows[len(rows)-1].Seq <= f.seq {
			break
		}
		for _, c := range rows {
			f.seq = c.Seq
			switch {
			case c.EntityType == model.ChangeCatalog:
				f.broken = true
			case c.EntityType == "item" && c.Op == model.OpCreate:
				f.created[c.EntityPID] = true
			}
		}
	}
	return !f.broken && f.created[pid]
}

// landedItem names the item an applied import's staged file now backs,
// with the audio essence the import recorded, and whether the file
// joined an item the import did not create. owned holds the items this
// entry's files created in an earlier attempt, which a retried decide
// lands the rest of a book onto.
func (l *Ingest) landedItem(ctx context.Context, res *waxbin.AcquiredResult, report *inbox.Report,
	doc *reviewTrackDoc, feed *createdFeed, owned map[string]bool) (importedFile, error) {
	var action *inbox.Action
	for i := range res.Plan.Actions {
		if res.Plan.Actions[i].Src == doc.Path {
			action = &res.Plan.Actions[i]
			break
		}
	}
	// What the import did decides, and the plan only when the report is
	// silent: a file the plan would attach can start an item of its own
	// once its tags give it another recording.
	var out importedFile
	reported := false
	if action != nil {
		out.essence = action.Essence
		for _, f := range report.Files {
			if f.Path == action.Dst && f.ItemPID != "" {
				out.pid, out.joined, reported = string(f.ItemPID), f.AttachedAsCopy, true
			}
		}
	}
	if !reported {
		out.joined = res.AttachedTo != ""
	}
	if out.pid == "" {
		// A cue rip's file names no one item; the essence finds it.
		pid, essence, err := l.resolveImportedItem(ctx, res.Plan, doc)
		if err != nil {
			return importedFile{joined: true}, err
		}
		out.pid, out.essence = pid, essence
	}
	if !out.joined {
		out.joined = !owned[out.pid] && !feed.made(ctx, model.PID(out.pid))
	}
	return out, nil
}

// heldWhereItGoes reports whether an import plan stopped a file because
// its place is taken by the library's own copy of it: the plan refused
// a taken place, the item holding the audio is what the file's tags
// describe, as it reads now or as the entry that landed it delivered it,
// and its file in the library the plan targets plays from
// disk. Importing it would add nothing the library lacks. Anything else
// - another file in its place, a holder elsewhere or gone, a refusal of
// another kind - leaves the plan's refusal standing, and the staged
// bytes wait for another try.
//
// The plan does not say whose file takes the place (a refused action
// keeps no destination), so the holder's details stand in for it: a
// file tagged as another item would land on that one's place. A place
// is rendered from the tags a file arrived with, which an edit since (a
// suggestion taken, a single's album) leaves behind, so the tags of the
// staged copy that landed it count as well.
func (l *Ingest) heldWhereItGoes(ctx context.Context, res *waxbin.AcquiredResult, doc *reviewTrackDoc) bool {
	if !res.AlreadyPresent || res.Plan == nil || len(res.Plan.Actions) == 0 {
		return false
	}
	a := res.Plan.Actions[0]
	if a.Outcome != inbox.OutcomeQuarantine || !placeTaken(a.Reason) || a.Library == nil || a.Essence == "" {
		return false
	}
	it, err := l.lib.Get(ctx, res.AlreadyPresentPID)
	if err != nil || (!describes(doc, it) && !l.landedAs(ctx, it.PID, doc)) {
		return false
	}
	refs, err := l.lib.ItemFiles(ctx, res.AlreadyPresentPID)
	if err != nil {
		return false
	}
	for _, ref := range refs {
		if ref.LibraryPID != a.Library.PID {
			continue
		}
		if f, err := l.lib.File(ctx, ref.FilePID); err != nil || f.EssenceHash != a.Essence {
			continue
		}
		if _, err := os.Stat(string(ref.Path)); err == nil {
			return true
		}
	}
	return false
}

// placeTaken reports the planner refusing a file because its place is
// taken, in the planner's words; any other refusal, or a reworded one,
// is not a taken place.
func placeTaken(reason string) bool {
	return strings.HasPrefix(reason, "destination already exists") ||
		strings.HasPrefix(reason, "destination case-collides")
}

// describes reports whether a staged file's tags are an item's details
// as a place is rendered from them: a track by title, album, artist and
// numbers, a book by its title and author.
func describes(doc *reviewTrackDoc, it *model.ItemView) bool {
	t := doc.Tags
	same := func(a, b string) bool { return strings.EqualFold(strings.TrimSpace(a), strings.TrimSpace(b)) }
	author := firstNonEmpty(t["ALBUMARTIST"], t["ARTIST"])
	if it.Kind == model.KindBook {
		return same(it.Title, scan.BookTitle(model.Tags{Album: t["ALBUM"], Title: t["TITLE"]})) &&
			same(firstNonEmpty(it.AlbumArtist, it.Artist), author)
	}
	return same(it.Title, t["TITLE"]) && same(it.Album, t["ALBUM"]) &&
		same(firstNonEmpty(it.AlbumArtist, it.Artist), author) &&
		it.TrackNo == doc.TrackNo && it.DiscNo == doc.DiscNo
}

// landedAs reports whether item's file landed from a staged copy
// carrying doc's tags, as an entry that brought it in recorded them.
func (l *Ingest) landedAs(ctx context.Context, item model.PID, doc *reviewTrackDoc) bool {
	ids, err := l.db.ReviewEntryIDsForItem(ctx, string(item))
	if err != nil {
		return false
	}
	for _, id := range ids {
		e, err := l.db.ReviewEntryByID(ctx, id)
		if err != nil {
			continue
		}
		var p reviewPayload
		if json.Unmarshal([]byte(e.Payload), &p) != nil {
			continue
		}
		for _, landed := range p.Tracks {
			if landed.PID == string(item) && !landed.heldBefore() && sameDelivered(doc, &landed) {
				return true
			}
		}
	}
	return false
}

// sameDelivered reports whether two staged copies carry the tags a
// place is rendered from alike.
func sameDelivered(a, b *reviewTrackDoc) bool {
	if a.Tags == nil || b.Tags == nil {
		return false
	}
	same := func(key string) bool {
		return strings.EqualFold(strings.TrimSpace(a.Tags[key]), strings.TrimSpace(b.Tags[key]))
	}
	return same("TITLE") && same("ALBUM") && same("ALBUMARTIST") && same("ARTIST") &&
		a.TrackNo == b.TrackNo && a.DiscNo == b.DiscNo
}
