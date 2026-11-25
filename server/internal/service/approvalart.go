package service

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/art"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
	"github.com/colespringer/waxbin/waxerr"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/providers"
)

// ReleaseCovers fetches the Cover Art Archive's front covers for an
// approved release: the release's own, and its release group's. Each
// answers the bytes and their media type; the URL methods name the
// address each fetches from, which the cover is attributed to.
type ReleaseCovers interface {
	FrontCover(ctx context.Context, releaseMBID string) ([]byte, string, error)
	GroupFrontCover(ctx context.Context, releaseGroupMBID string) ([]byte, string, error)
	FrontCoverURL(releaseMBID string) string
	GroupFrontCoverURL(releaseGroupMBID string) string
}

// reviewCoverDirName is the data dir folder an approval keeps the
// fronts it replaced in, one folder per entry.
const reviewCoverDirName = "review-covers"

// The cover fetches one decision may wait on, and those one bulk
// decision shares across its entries.
const (
	decideCoverBudget = 5 * time.Second
	bulkCoverBudget   = 10 * time.Second
)

// reviewCoverDoc is the front an approval replaced on one item, its
// bytes kept under reviewCoverDir. Had is false for an item with no
// front of its own, which a revert leaves with none. Locked and Approval
// say the slot was locked and the front an earlier approval's. Applied
// is the hash of the cover the approval set: a revert leaves a front
// that changed since alone.
type reviewCoverDoc struct {
	Had       bool                   `json:"had,omitempty"`
	Format    string                 `json:"format,omitempty"`
	Source    model.ProvenanceSource `json:"source,omitempty"`
	Provider  string                 `json:"provider,omitempty"`
	SourceURL string                 `json:"sourceUrl,omitempty"`
	Locked    bool                   `json:"locked,omitempty"`
	Approval  bool                   `json:"approval,omitempty"`
	Applied   string                 `json:"applied"`
}

// reviewEntityDoc is an album's or release group's id before an
// approval recorded the release on it, attributed as it was. Applied is
// the id the approval gave it: a revert leaves an id that changed since
// alone.
type reviewEntityDoc struct {
	Type     model.MergeEntity      `json:"type"`
	PID      string                 `json:"pid"`
	MBID     string                 `json:"mbid,omitempty"`
	Source   model.ProvenanceSource `json:"source,omitempty"`
	Provider string                 `json:"provider,omitempty"`
	Locked   bool                   `json:"locked,omitempty"`
	Applied  string                 `json:"applied,omitempty"`
}

// coverBudget is the fetching time a decision's covers have left. A bulk
// call shares one across its decisions, which run one after another;
// only the fetches spend it.
type coverBudget struct{ left time.Duration }

type coverBudgetKey struct{}

// withCoverBudget gives every decision made under ctx one shared budget
// for its cover fetches, unless an outer call already set one.
func withCoverBudget(ctx context.Context, d time.Duration) context.Context {
	if _, ok := ctx.Value(coverBudgetKey{}).(*coverBudget); ok {
		return ctx
	}
	return context.WithValue(ctx, coverBudgetKey{}, &coverBudget{left: d})
}

// coverBudgetFor is the budget ctx shares, else one decision's own.
func coverBudgetFor(ctx context.Context) *coverBudget {
	if b, ok := ctx.Value(coverBudgetKey{}).(*coverBudget); ok {
		return b
	}
	return &coverBudget{left: decideCoverBudget}
}

// entityWrite is a release id an approval records on an album or
// group. earlier says its snapshot doc is an earlier attempt's, which
// gave the entity was.
type entityWrite struct {
	et               model.MergeEntity
	pid              model.PID
	album, want, was string
	earlier          bool
}

// planReleaseIdentity picks the albums and groups the edited items now
// belong to that an approval records the release and its group on, and
// keeps in the snapshot what each held for the revert. Only an entity
// the edited items hold alone takes it: one track's match must never
// relabel an album other tracks share. Catalog only: the pinned catalog
// has no way to write either id into the files.
func (l *Ingest) planReleaseIdentity(ctx context.Context, cand *reviewCandidateDoc, order []model.PID, snap *reviewSnapshot) []entityWrite {
	var writes []entityWrite
	seen := map[model.PID]bool{}
	plan := func(et model.MergeEntity, pid model.PID, album, was, want string) {
		if pid == "" || seen[pid] || !isUUID(want) || was == want {
			return
		}
		seen[pid] = true
		if l.entityHoldsOthers(ctx, et, pid, order) {
			l.log.Info("an approved release is not recorded: other items share it", "entity", et, "pid", pid)
			return
		}
		w := entityWrite{et: et, pid: pid, album: album, want: want}
		for i := range snap.Entities {
			if e := &snap.Entities[i]; e.Type == et && e.PID == string(pid) {
				w.was, w.earlier = e.Applied, true
				e.Applied = want
				writes = append(writes, w)
				return
			}
		}
		prior := reviewEntityDoc{Type: et, PID: string(pid), MBID: was, Source: model.SourceTag, Applied: want}
		if row := l.entityMBIDRow(ctx, et, pid); row != nil {
			prior.Source, prior.Provider, prior.Locked = row.Source, row.Provider, row.Locked
		}
		snap.Entities = append(snap.Entities, prior)
		writes = append(writes, w)
	}
	for _, pid := range order {
		it, err := l.lib.Get(ctx, pid)
		if err != nil {
			continue
		}
		plan(model.MergeAlbum, it.AlbumPID, it.Album, it.AlbumMBID, cand.MBID)
		plan(model.MergeReleaseGroup, it.ReleaseGroupPID, it.Album, it.ReleaseGroupMBID, cand.ReleaseGroupMBID)
	}
	return writes
}

// writeReleaseIdentity records the planned release ids, locked, over an
// earlier approval's. An entity the write misses keeps the snapshot doc
// it had before. An id another entity already holds is named in the
// warnings.
func (l *Ingest) writeReleaseIdentity(ctx context.Context, writes []entityWrite, snap *reviewSnapshot) []string {
	var warnings []string
	said := map[string]bool{}
	warn := func(w string) {
		if !said[w] {
			said[w] = true
			warnings = append(warnings, w)
		}
	}
	for _, w := range writes {
		_, err := l.lib.EditEntity(ctx, w.et, w.pid, map[string]string{"mbid": w.want}, waxbin.EntityEditOptions{
			Lock: model.LockOn, Force: true, Source: model.SourceEnrichment, Provider: reviewMatchProvider,
		})
		if err == nil {
			continue
		}
		snap.unplanEntity(w)
		switch {
		case waxerr.Is(err, waxerr.CodeConflict) && w.et == model.MergeAlbum:
			warn(w.album + ": another album in the library already holds this release, so it is not recorded on this one")
		case waxerr.Is(err, waxerr.CodeConflict):
			warn(w.album + ": another release group in the library already holds this release's group, so it is not recorded on this album's")
		default:
			l.log.Warn("recording an approved release", "entity", w.et, "pid", w.pid, "err", err)
		}
	}
	return warnings
}

// unplanEntity puts an entity's snapshot doc back as it was before a
// write that missed: an earlier attempt's applied id, or no doc.
func (s *reviewSnapshot) unplanEntity(w entityWrite) {
	for i := range s.Entities {
		e := &s.Entities[i]
		if e.Type != w.et || e.PID != string(w.pid) {
			continue
		}
		if w.earlier {
			e.Applied = w.was
		} else {
			s.Entities = append(s.Entities[:i], s.Entities[i+1:]...)
		}
		return
	}
}

// entityMBID is an album's or release group's id as it stands; ok is
// false when it cannot be read.
func (l *Ingest) entityMBID(ctx context.Context, et model.MergeEntity, pid model.PID) (string, bool) {
	kind := read.EntityAlbum
	if et == model.MergeReleaseGroup {
		kind = read.EntityReleaseGroup
	}
	info, err := l.lib.EntityByPID(ctx, kind, pid)
	if err != nil || info == nil {
		return "", false
	}
	return info.MBID, true
}

// entityMBIDRow is the attribution an entity's id carries; nil for an
// id as a scan read it.
func (l *Ingest) entityMBIDRow(ctx context.Context, et model.MergeEntity, pid model.PID) *model.EntityCuration {
	rows, err := l.lib.EntityCuration(ctx, et, pid)
	if err != nil {
		return nil
	}
	for i := range rows {
		if rows[i].Field == "mbid" {
			return &rows[i]
		}
	}
	return nil
}

// entityHoldsOthers reports whether an album or release group has
// members besides pids, or whether that cannot be told.
func (l *Ingest) entityHoldsOthers(ctx context.Context, et model.MergeEntity, pid model.PID, pids []model.PID) bool {
	field := "album_pid"
	if et == model.MergeReleaseGroup {
		field = "release_group_pid"
	}
	members, err := l.lib.Query(ctx, visibleItems().Where(field, query.OpIs, string(pid)).Build(), "")
	if err != nil {
		l.log.Warn("reading an approved release's members", "entity", et, "pid", pid, "err", err)
		return true
	}
	ours := make(map[model.PID]bool, len(pids))
	for _, p := range pids {
		ours[p] = true
	}
	for _, it := range members {
		if !ours[it.PID] {
			return true
		}
	}
	return false
}

// approvalCover is one source's answer for the approved release, asked
// at most once per decision.
type approvalCover struct {
	rank                  int
	ask                   func(context.Context) (data []byte, format, provider, url string, err error)
	data                  []byte
	format, provider, url string
	asked, late, failed   bool
}

var errNoApprovalCover = errors.New("no cover for the release")

// approvalWant is an item an approval's cover may replace the front of.
// rank is the bar a cover must rank above; stands is the rank the front
// holds for the warning. An earlier approval's front is replaced by any
// cover the chain finds.
type approvalWant struct {
	pid             model.PID
	rank, stands    int
	locked, earlier bool
}

// approvalCoverWrite is a cover an approval puts on an item. kept is
// where this attempt kept the front it replaces, "" for none; before is
// the snapshot doc an earlier attempt left for the item.
type approvalCoverWrite struct {
	w          approvalWant
	name, kept string
	cover      *approvalCover
	before     *reviewCoverDoc
}

// planApprovalArt picks the cover each edited item takes where its own
// front ranks below the one found, and keeps the front it replaces for
// the revert: the release's front, else its group's, else a cover
// provider's answer for the release. A cover an earlier approval wrote
// gives way; a cover set by hand, any other locked one, and a file's own
// art are kept. Fetches stop when the decision's budget is spent; an
// item left with no cover better than a thumbnail is named in the
// warnings. It never fails the approval.
func (l *Ingest) planApprovalArt(ctx context.Context, entryID string, cand *reviewCandidateDoc, order []model.PID, items map[model.PID]*model.ItemView, snap *reviewSnapshot) ([]approvalCoverWrite, []string) {
	if l.releaseCovers == nil || len(order) == 0 {
		return nil, nil
	}
	var wanting []approvalWant
	for _, pid := range order {
		ref := model.EntityRef{Type: model.ArtTrack, PID: pid}
		locked, err := l.lib.ArtLocked(ctx, model.ArtTrack, pid, model.ArtRoleFront)
		if err != nil {
			continue
		}
		if prov, ok := l.approvalFront(ctx, ref); ok {
			if prov.SourceURL != l.releaseCovers.FrontCoverURL(cand.MBID) {
				wanting = append(wanting, approvalWant{pid: pid, rank: artRankNone, stands: artRank(prov, false, ""), locked: locked, earlier: true})
			}
			continue
		}
		rank := l.frontArtRank(ctx, ref, locked)
		if rank == artRankHeld || rank == artRankFile || rank <= artRankRelease {
			continue
		}
		wanting = append(wanting, approvalWant{pid: pid, rank: rank, stands: rank, locked: locked})
	}
	if len(wanting) == 0 {
		return nil, nil
	}

	release := &approvalCover{rank: artRankRelease, ask: func(ctx context.Context) ([]byte, string, string, string, error) {
		if !isUUID(cand.MBID) {
			return nil, "", "", "", errNoApprovalCover
		}
		data, mime, err := l.releaseCovers.FrontCover(ctx, cand.MBID)
		return data, mime, enrich.ProviderCoverArt, l.releaseCovers.FrontCoverURL(cand.MBID), err
	}}
	group := &approvalCover{rank: artRankGroup, ask: func(ctx context.Context) ([]byte, string, string, string, error) {
		if !isUUID(cand.ReleaseGroupMBID) {
			return nil, "", "", "", errNoApprovalCover
		}
		data, mime, err := l.releaseCovers.GroupFrontCover(ctx, cand.ReleaseGroupMBID)
		return data, mime, enrich.ProviderCoverArt, l.releaseCovers.GroupFrontCoverURL(cand.ReleaseGroupMBID), err
	}}
	provided := &approvalCover{rank: artRankGroup, ask: func(ctx context.Context) ([]byte, string, string, string, error) {
		req := enrich.Request{
			Type: enrich.TargetRelease, MBID: cand.MBID, ReleaseGroupMBID: cand.ReleaseGroupMBID,
			Title: cand.Title, Artist: cand.Artist,
		}
		for _, p := range l.Enrichment.enrichProvidersWith(enrich.CapCover, enrich.TargetRelease) {
			if err := ctx.Err(); err != nil {
				return nil, "", "", "", err
			}
			got, err := enrichAsk(ctx, p, req, enrich.CapCover)
			if err != nil || got == nil || got.Cover == nil || validateArtworkBytes(got.Cover.Data) != nil {
				continue
			}
			return got.Cover.Data, got.Cover.Format, p.Name(), got.Cover.SourceURL, nil
		}
		return nil, "", "", "", errNoApprovalCover
	}}
	chain := []*approvalCover{release, group, provided}

	budget := coverBudgetFor(ctx)
	fetch := func(c *approvalCover) {
		if c.asked {
			return
		}
		c.asked = true
		if budget.left <= 0 {
			c.late = true
			return
		}
		start := time.Now()
		fctx, cancel := context.WithTimeout(ctx, budget.left)
		data, format, provider, url, err := c.ask(fctx)
		late := errors.Is(fctx.Err(), context.DeadlineExceeded)
		cancel()
		budget.left -= time.Since(start)
		switch {
		case err == nil && validateArtworkBytes(data) == nil:
			c.data, c.format, c.provider, c.url = data, format, provider, url
		case late:
			c.late = true
		case errors.Is(err, providers.ErrNoCover), errors.Is(err, errNoApprovalCover):
		default:
			if err == nil {
				err = validateArtworkBytes(data)
			}
			l.log.Warn("fetching an approval's cover", "release", cand.MBID, "err", err)
			c.failed = true
		}
	}

	var writes []approvalCoverWrite
	var warnings []string
	for _, w := range wanting {
		name := string(w.pid)
		if it := items[w.pid]; it != nil {
			name = filepath.Base(string(it.Path))
		}
		var cover *approvalCover
		late, failed := false, false
		for _, c := range chain {
			// Only a cover that ranks above the item's own replaces it.
			if c.rank >= w.rank {
				break
			}
			fetch(c)
			late, failed = late || c.late, failed || c.failed
			if c.data != nil {
				cover = c
				break
			}
		}
		if cover == nil {
			// One keeping a cover better than a thumbnail lost nothing.
			switch {
			case w.stands < artRankDownload:
			case late:
				warnings = append(warnings, name+": the release's cover could not be fetched in time; it keeps the cover it had")
			case failed:
				warnings = append(warnings, name+": the cover could not be fetched; it keeps the cover it had")
			default:
				warnings = append(warnings, name+": no cover found for the release; it keeps the cover it had")
			}
			continue
		}
		write, ok := l.keepApprovalFront(ctx, entryID, w, name, cover, snap)
		if !ok {
			warnings = append(warnings, name+": the cover it had could not be kept for a revert, so it was not replaced")
			continue
		}
		writes = append(writes, write)
	}
	return writes, warnings
}

// approvalFront answers an item's own front when it is the one an
// approval wrote, known by the hash recorded when it was set.
func (l *Ingest) approvalFront(ctx context.Context, ref model.EntityRef) (*model.ArtProvenance, bool) {
	prov, err := l.lib.ArtProvenance(ctx, ref, model.ArtRoleFront)
	if err != nil || prov.Level != ref.Type || prov.Derived || prov.Source != model.SourceEnrichment || prov.SourceHash == "" {
		return nil, false
	}
	if hash, err := l.db.ApprovalArt(ctx, string(ref.PID)); err != nil || hash != prov.SourceHash {
		return nil, false
	}
	return prov, true
}

// forgetApprovalFront makes an item's front no approval's: a person set,
// cleared or pinned it, so no later approval may replace it.
func (c *core) forgetApprovalFront(ctx context.Context, pid model.PID) {
	if err := c.db.ForgetApprovalArt(ctx, string(pid)); err != nil {
		c.log.Warn("forgetting an approval's cover", "item", pid, "err", err)
	}
}

// keepApprovalFront keeps the front an approval's cover replaces on an
// item, for the revert, and records it in the snapshot under the hash of
// the cover going in. An earlier attempt's doc for the item stands: the
// front it kept is the one from before. ok is false when the front
// could not be kept.
func (l *Ingest) keepApprovalFront(ctx context.Context, entryID string, w approvalWant, name string, c *approvalCover, snap *reviewSnapshot) (approvalCoverWrite, bool) {
	pid := w.pid
	write := approvalCoverWrite{w: w, name: name, cover: c}
	if snap.Covers == nil {
		snap.Covers = map[string]reviewCoverDoc{}
	}
	if doc, ok := snap.Covers[string(pid)]; ok {
		before := doc
		write.before = &before
		doc.Applied = art.Hash(c.data)
		snap.Covers[string(pid)] = doc
		return write, true
	}
	ref := model.EntityRef{Type: model.ArtTrack, PID: pid}
	prior := reviewCoverDoc{Applied: art.Hash(c.data)}
	resolve := l.lib.ResolveArt
	if l.resolveArtHook != nil {
		resolve = l.resolveArtHook
	}
	blob, err := resolve(ctx, ref, model.ArtRoleFront, 0)
	if err != nil && KindOf(err) != KindNotFound {
		// The item was ranked from a front just now: an error is no
		// proof it has none, and a revert would delete it.
		l.log.Warn("reading the front an approval replaces", "item", pid, "err", err)
		return write, false
	}
	if err == nil && blob.Level == model.ArtTrack && !blob.Derived {
		kept := l.keptCoverPath(entryID, pid)
		err := os.MkdirAll(filepath.Dir(kept), 0o755)
		if err == nil {
			err = writeFileCrashSafe(kept, blob.Bytes, 0o600)
		}
		if err != nil {
			// Without the old front the revert could not put it back.
			l.log.Warn("keeping the front an approval replaces", "item", pid, "err", err)
			return write, false
		}
		write.kept = kept
		prior.Had, prior.Format, prior.Source, prior.Provider, prior.SourceURL = true, blob.Format, blob.Source, blob.Provider, blob.SourceURL
		prior.Locked, prior.Approval = w.locked, w.earlier
	}
	snap.Covers[string(pid)] = prior
	return write, true
}

// writeApprovalArt puts the planned covers in place, written into the
// files and locked. A cover the write misses leaves the item's snapshot
// doc as it was before.
func (l *Ingest) writeApprovalArt(ctx context.Context, writes []approvalCoverWrite, order []model.PID, snap *reviewSnapshot, reader *UserCtx) []string {
	if len(writes) == 0 {
		return nil
	}
	writeBack := l.unitWritable(ctx, order)
	var warnings []string
	changed := false
	for _, cw := range writes {
		pid, c := cw.w.pid, cw.cover
		err := l.lib.SetItemArt(ctx, pid, model.ArtRoleFront, c.data, waxbin.ArtEditOptions{
			Source: model.SourceEnrichment, Provider: c.provider, SourceURL: c.url, Format: c.format,
			Lock: model.LockOn, Force: cw.w.locked, WriteBack: writeBack,
		})
		var wbe *waxbin.WriteBackError
		if err != nil && !errors.As(err, &wbe) {
			l.log.Warn("storing an approval's cover", "item", pid, "err", err)
			if cw.before != nil {
				snap.Covers[string(pid)] = *cw.before
			} else {
				delete(snap.Covers, string(pid))
			}
			if cw.kept != "" {
				_ = os.Remove(cw.kept)
			}
			warnings = append(warnings, cw.name+": the release's cover could not be stored")
			continue
		}
		changed = true
		if wbe != nil {
			for _, f := range wbe.Failures {
				if l.mayReadFailure(ctx, reader, f) {
					warnings = append(warnings, cw.name+": cover not written: "+l.failureWords(f.Reason))
				}
			}
		}
		if prov, err := l.lib.ArtProvenance(ctx, model.EntityRef{Type: model.ArtTrack, PID: pid}, model.ArtRoleFront); err == nil {
			doc := snap.Covers[string(pid)]
			doc.Applied = prov.SourceHash
			snap.Covers[string(pid)] = doc
			if err := l.db.RecordApprovalArt(ctx, string(pid), prov.SourceHash); err != nil {
				l.log.Warn("recording an approval's cover", "item", pid, "err", err)
			}
		}
	}
	if changed {
		l.Playlists.noteArtworkChanged(ctx)
	}
	return warnings
}

// keptCoverPath is where an approval keeps the front it replaced on pid.
func (l *Ingest) keptCoverPath(entryID string, pid model.PID) string {
	return filepath.Join(l.reviewCoverDir, entryID, string(pid))
}

// revertApprovalExtras undoes what an approval did beyond the fields:
// the release identity it recorded, put back as it was on an entity no
// other items have joined since, and the fronts it replaced, each put
// back as it was, or removed where the item had none. An id or front
// that changed since the approval is left as it is. Failures are
// logged: the field revert already stands.
func (l *Ingest) revertApprovalExtras(ctx context.Context, entryID string, snap reviewSnapshot, pids []model.PID) {
	for _, e := range snap.Entities {
		if id, ok := l.entityMBID(ctx, e.Type, model.PID(e.PID)); !ok || id != e.Applied {
			l.log.Info("reverting an approved release: the id changed since; left as it is", "entity", e.Type, "pid", e.PID)
			continue
		}
		if l.entityHoldsOthers(ctx, e.Type, model.PID(e.PID), pids) {
			l.log.Info("reverting an approved release: other items share it; left as it is", "entity", e.Type, "pid", e.PID)
			continue
		}
		src, lock := e.Source, model.LockOff
		if src == "" {
			src = model.SourceTag
		}
		if e.Locked {
			lock = model.LockOn
		}
		if _, err := l.lib.EditEntity(ctx, e.Type, model.PID(e.PID), map[string]string{"mbid": e.MBID}, waxbin.EntityEditOptions{
			Lock: lock, Force: true, Source: src, Provider: e.Provider,
		}); err != nil {
			l.log.Warn("reverting an approved release", "entity", e.Type, "pid", e.PID, "err", err)
		}
	}
	if len(snap.Covers) == 0 {
		return
	}
	writeBack := l.unitWritable(ctx, pids)
	changed := false
	for p, c := range snap.Covers {
		pid := model.PID(p)
		prov, err := l.lib.ArtProvenance(ctx, model.EntityRef{Type: model.ArtTrack, PID: pid}, model.ArtRoleFront)
		if err != nil || prov.Level != model.ArtTrack || prov.SourceHash != c.Applied {
			l.log.Info("reverting an approval's cover: the front changed since; left as it is", "item", pid)
			continue
		}
		var data []byte
		opts := waxbin.ArtEditOptions{Lock: model.LockOff, Force: true, WriteBack: writeBack}
		if c.Locked {
			opts.Lock = model.LockOn
		}
		if c.Had {
			if data, err = os.ReadFile(l.keptCoverPath(entryID, pid)); err != nil {
				l.log.Warn("reverting an approval's cover: the kept front is unreadable", "item", pid, "err", err)
				continue
			}
			opts.Source, opts.Provider, opts.SourceURL, opts.Format = c.Source, c.Provider, c.SourceURL, c.Format
		}
		err = l.lib.SetItemArt(ctx, pid, model.ArtRoleFront, data, opts)
		var wbe *waxbin.WriteBackError
		switch {
		case err == nil:
		case errors.As(err, &wbe):
			l.log.Info("reverting an approval's cover: files not written", "item", pid, "err", err)
		default:
			l.log.Warn("reverting an approval's cover", "item", pid, "err", err)
			continue
		}
		changed = true
		l.reRecordApprovalFront(ctx, pid, c)
	}
	if changed {
		l.Playlists.noteArtworkChanged(ctx)
	}
}

// reRecordApprovalFront records a restored front that an earlier
// approval wrote as that approval's again, and forgets the reverted one.
func (l *Ingest) reRecordApprovalFront(ctx context.Context, pid model.PID, c reviewCoverDoc) {
	err := l.db.DropApprovalArt(ctx, string(pid), c.Applied)
	if err == nil && c.Had && c.Approval {
		var prov *model.ArtProvenance
		if prov, err = l.lib.ArtProvenance(ctx, model.EntityRef{Type: model.ArtTrack, PID: pid}, model.ArtRoleFront); err == nil {
			err = l.db.RecordApprovalArt(ctx, string(pid), prov.SourceHash)
		}
	}
	if err != nil {
		l.log.Warn("recording a reverted approval's cover", "item", pid, "err", err)
	}
}

// dropUnrecordedCovers removes the fronts an attempt kept for covers it
// could not record on its entry, and so will not write.
func (l *Ingest) dropUnrecordedCovers(writes []approvalCoverWrite) {
	for _, cw := range writes {
		if cw.kept != "" {
			_ = os.Remove(cw.kept)
		}
	}
}

// dropKeptCovers removes the fronts an entry's approval kept.
func (l *Ingest) dropKeptCovers(entryID string) {
	if l.reviewCoverDir == "" || entryID == "" {
		return
	}
	if err := os.RemoveAll(filepath.Join(l.reviewCoverDir, entryID)); err != nil {
		l.log.Warn("dropping an entry's kept covers", "entry", entryID, "err", err)
	}
}

// sweepReviewCovers removes the kept fronts of entries no revert can
// reach any more: reverted, decided otherwise, or gone (a restored
// database holds other entries than the folder). A pending entry keeps
// what an apply that failed part way kept, for its retry's revert.
func (l *Ingest) sweepReviewCovers(ctx context.Context) {
	if l.reviewCoverDir == "" {
		return
	}
	dirs, err := os.ReadDir(l.reviewCoverDir)
	if err != nil {
		return
	}
	for _, d := range dirs {
		e, err := l.db.ReviewEntryByID(ctx, d.Name())
		switch {
		case err == nil && (e.Status == reviewApplied || e.Status == reviewAutoApplied || e.Status == reviewPending):
			continue
		case err != nil && !errors.Is(err, wdb.ErrNotFound):
			continue
		}
		l.dropKeptCovers(d.Name())
	}
}
