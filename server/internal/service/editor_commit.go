package service

import (
	"context"
	"sort"
	"strings"
)

// The compound commit of an editor draft, and SetReleaseStatus, which the
// commit calls for its release-status part.

// SetReleaseStatus marks or clears the item's unofficial state (a
// locked RELEASESTATUS custom tag of unofficial).
func (l *Editor) SetReleaseStatus(ctx context.Context, uc *UserCtx, apiPID string, unofficial bool, p MetadataEditParams) (EditOutcomeDTO, error) {
	it, err := l.Grants.getVisibleItem(ctx, uc, apiPID)
	if err != nil {
		return EditOutcomeDTO{}, err
	}
	if p.WriteBack {
		if err := l.Settings.checkPathWritable(ctx, string(it.Path)); err != nil {
			return EditOutcomeDTO{}, err
		}
	}
	return editOutcomeFromWriteBack(l.Ingest.setReleaseStatus(ctx, it.PID, unofficial, p.WriteBack))
}

// MetadataCommitDTO is one editor draft's staged parts. Every part is
// optional; the pointer fields are the ones whose empty form means
// something (an empty chapter list restores the embedded chapters).
type MetadataCommitDTO struct {
	Fields      map[string]string
	Credits     []CommitCreditsDTO
	Lyrics      *CommitLyricsDTO
	ClearLyrics bool
	Chapters    *[]ChapterMark
	TagSets     map[string][]string
	TagRemoves  []string
	Unofficial  *bool
	Params      MetadataEditParams
}

// CommitCreditsDTO is one role's replacement people.
type CommitCreditsDTO struct {
	Role  string
	Names []string
}

// CommitLyricsDTO is a lyrics replacement; at least one block carries
// content.
type CommitLyricsDTO struct {
	LRC   string
	Plain string
}

// The part names and statuses the commit result reports. They are the
// contract's own spellings, so the API layer copies them through.
const (
	CommitPartFields        = "fields"
	CommitPartCredit        = "credit"
	CommitPartLyrics        = "lyrics"
	CommitPartChapters      = "chapters"
	CommitPartTagSet        = "tagSet"
	CommitPartTagRemove     = "tagRemove"
	CommitPartReleaseStatus = "releaseStatus"

	CommitCommitted = "committed"
	CommitRefused   = "refused"
	CommitSkipped   = "skipped"
)

// MetadataCommitPartDTO is what became of one part.
type MetadataCommitPartDTO struct {
	Part   string
	Detail string
	Status string
	// Refusal is the classified error for a refused part, and nil
	// otherwise. It is an error rather than a code so the API layer
	// maps it with the same kind-to-code table every other refusal
	// goes through.
	Refusal error
}

// MetadataCommitOutcomeDTO is a compound commit's whole answer.
type MetadataCommitOutcomeDTO struct {
	Parts    []MetadataCommitPartDTO
	Failures []WriteBackFailureDTO
	Warnings []string
}

// commitStep is one staged part bound to the call that applies it.
//
// details is set by a step that applies several report rows at once:
// the credits go upstream as one atomic batch, so their rows share the
// step's outcome. The first row carries a refusal and the rest read
// skipped, keeping the contract's one-refused-part shape.
type commitStep struct {
	part    string
	detail  string
	details []string
	run     func(context.Context) (EditOutcomeDTO, error)
}

// CommitItemMetadata applies every staged part of one editor draft in
// the order the client's sequential save uses, stopping at the first
// refusal and reporting what each part did.
//
// It orchestrates the existing per-part functions and holds no edit
// logic of its own: the sequential path and this one must be
// interchangeable, which they only stay if there is one implementation
// of each part. What it adds is the round trip - one instead of N,
// which on a phone reaching a home server through a proxy is the whole
// felt cost of a Save - and one partial-failure window instead of N.
//
// Not a transaction, deliberately: write-back is best effort by design,
// so end-to-end atomicity is unattainable, and the committed parts'
// write-back failures are exactly what the editor's banner is made of.
// A refusal therefore rides the result rather than the error return,
// which is reserved for a request that commits nothing at all.
func (l *Editor) CommitItemMetadata(ctx context.Context, uc *UserCtx, apiPID string, c MetadataCommitDTO) (MetadataCommitOutcomeDTO, error) {
	if err := validateCommit(c); err != nil {
		return MetadataCommitOutcomeDTO{}, err
	}
	// Resolved once up front so an unknown or invisible item is a
	// not-found for the whole request rather than a refused first part.
	if _, err := l.Grants.getVisibleItem(ctx, uc, apiPID); err != nil {
		return MetadataCommitOutcomeDTO{}, err
	}
	steps := l.commitSteps(apiPID, uc, c)
	out := MetadataCommitOutcomeDTO{Parts: make([]MetadataCommitPartDTO, 0, len(steps))}
	seen := map[string]bool{}
	refused := false
	committed := 0
	// rows is a step's report rows: the details it fans over, or the
	// single row a plain step is.
	rows := func(st commitStep) []string {
		if st.details != nil {
			return st.details
		}
		return []string{st.detail}
	}
	for _, st := range steps {
		if refused {
			for _, detail := range rows(st) {
				out.Parts = append(out.Parts, MetadataCommitPartDTO{
					Part: st.part, Detail: detail, Status: CommitSkipped,
				})
			}
			continue
		}
		res, err := st.run(ctx)
		if err != nil {
			// A server-condition failure with nothing committed yet is
			// the whole request failing rather than a part refusing:
			// there is no committed work whose report a status code
			// would discard, and the client's maintenance and retry
			// handling keys on the code rather than on a part. Once
			// something has committed, the same failure rides as a
			// refusal, because losing that report is the worse trade.
			if committed == 0 && retryableServerFailure(KindOf(err)) {
				return MetadataCommitOutcomeDTO{}, err
			}
			refused = true
			for i, detail := range rows(st) {
				status := CommitSkipped
				if i == 0 {
					status = CommitRefused
				}
				part := MetadataCommitPartDTO{Part: st.part, Detail: detail, Status: status}
				if i == 0 {
					part.Refusal = err
				}
				out.Parts = append(out.Parts, part)
			}
			continue
		}
		committed++
		for _, detail := range rows(st) {
			out.Parts = append(out.Parts, MetadataCommitPartDTO{
				Part: st.part, Detail: detail, Status: CommitCommitted,
			})
		}
		// Deduplicated: several parts can report the same file for the
		// same reason, and each line is for a person to read once.
		for _, f := range res.Failures {
			key := f.FilePID + "\x00" + f.Path + "\x00" + f.Reason
			if seen[key] {
				continue
			}
			seen[key] = true
			out.Failures = append(out.Failures, f)
		}
		out.Warnings = append(out.Warnings, res.Warnings...)
	}
	return out, nil
}

// retryableServerFailure reports whether an error says the server is
// temporarily unwell rather than that the edit was wrong. The three
// kinds here are the ones a client answers with a banner and a retry
// instead of showing to the person who typed the value.
func retryableServerFailure(k ErrorKind) bool {
	switch k {
	case KindMaintenance, KindInternal, KindCatalogBusy:
		return true
	default:
		return false
	}
}

// validateCommit rejects a body that names nothing to do, or that
// contradicts itself. Everything else is a part's own validation, which
// belongs to the part so the two save paths refuse identically.
func validateCommit(c MetadataCommitDTO) error {
	if c.Fields != nil && len(c.Fields) == 0 {
		return errInvalid("fields must name at least one field when present")
	}
	// The collection bounds the contract declares, enforced here
	// because the generated binding does not enforce them and every
	// sibling edit surface says so at its own door. Without this a
	// caller who may curate one item can hand the orchestrator an
	// arbitrarily long step list, each step a catalog write.
	if len(c.Credits) > 50 {
		return errInvalid("at most 50 credit roles per commit")
	}
	// The credit roles go upstream as one atomic batch, which names
	// each (item, role) slot once. Two entries for a role are a body
	// contradicting itself rather than a second edit, so they are
	// refused here with a sentence instead of upstream with one.
	seenRoles := map[string]bool{}
	for _, cr := range c.Credits {
		role := strings.ToLower(strings.TrimSpace(cr.Role))
		if seenRoles[role] {
			return errInvalid("credit role " + role + " is named twice; a commit sets each role once")
		}
		seenRoles[role] = true
	}
	if len(c.TagSets) > 100 {
		return errInvalid("at most 100 tag sets per commit")
	}
	if len(c.TagRemoves) > 100 {
		return errInvalid("at most 100 tag removals per commit")
	}
	if c.Lyrics != nil && c.ClearLyrics {
		return errInvalid("lyrics and clearLyrics are mutually exclusive")
	}
	if c.Lyrics != nil && c.Lyrics.LRC == "" && c.Lyrics.Plain == "" {
		return errInvalid("lyrics must carry lrc or plain text")
	}
	empty := len(c.Fields) == 0 && len(c.Credits) == 0 && c.Lyrics == nil &&
		!c.ClearLyrics && c.Chapters == nil && len(c.TagSets) == 0 &&
		len(c.TagRemoves) == 0 && c.Unofficial == nil
	if empty {
		return errInvalid("a commit must carry at least one staged part")
	}
	return nil
}

// commitSteps lays the staged parts out in the order the client's
// sequential save runs them, which is what makes the two paths report
// the same thing. Tag sets sort by key: a JSON object carries no order,
// and the parts list has to be reproducible.
func (l *Editor) commitSteps(pid string, uc *UserCtx, c MetadataCommitDTO) []commitStep {
	var steps []commitStep
	if len(c.Fields) > 0 {
		steps = append(steps, commitStep{part: CommitPartFields, run: func(ctx context.Context) (EditOutcomeDTO, error) {
			return l.EditItemMetadata(ctx, uc, pid, c.Fields, c.Params)
		}})
	}
	if len(c.Credits) > 0 {
		roles := make([]string, 0, len(c.Credits))
		for _, cr := range c.Credits {
			roles = append(roles, cr.Role)
		}
		steps = append(steps, commitStep{part: CommitPartCredit, details: roles, run: func(ctx context.Context) (EditOutcomeDTO, error) {
			return l.SetItemCreditsBatch(ctx, uc, pid, c.Credits, c.Params)
		}})
	}
	switch {
	case c.Lyrics != nil:
		steps = append(steps, commitStep{part: CommitPartLyrics, run: func(ctx context.Context) (EditOutcomeDTO, error) {
			return l.SetItemLyrics(ctx, uc, pid, c.Lyrics.LRC, c.Lyrics.Plain, c.Params)
		}})
	case c.ClearLyrics:
		steps = append(steps, commitStep{part: CommitPartLyrics, run: func(ctx context.Context) (EditOutcomeDTO, error) {
			return l.ClearItemLyrics(ctx, uc, pid, c.Params)
		}})
	}
	if c.Chapters != nil {
		steps = append(steps, commitStep{part: CommitPartChapters, run: func(ctx context.Context) (EditOutcomeDTO, error) {
			return l.SetBookChapters(ctx, uc, pid, *c.Chapters, c.Params.Lock, c.Params.Force)
		}})
	}
	for _, key := range sortedKeys(c.TagSets) {
		steps = append(steps, commitStep{part: CommitPartTagSet, detail: key, run: func(ctx context.Context) (EditOutcomeDTO, error) {
			out, err := l.SetItemTag(ctx, uc, pid, key, c.TagSets[key], c.Params)
			return EditOutcomeDTO{Failures: out.Failures}, err
		}})
	}
	for _, key := range c.TagRemoves {
		steps = append(steps, commitStep{part: CommitPartTagRemove, detail: key, run: func(ctx context.Context) (EditOutcomeDTO, error) {
			return l.ClearItemTag(ctx, uc, pid, key, c.Params)
		}})
	}
	if c.Unofficial != nil {
		steps = append(steps, commitStep{part: CommitPartReleaseStatus, run: func(ctx context.Context) (EditOutcomeDTO, error) {
			return l.SetReleaseStatus(ctx, uc, pid, *c.Unofficial, c.Params)
		}})
	}
	return steps
}

// sortedKeys is the deterministic order a JSON object's keys are
// applied in.
func sortedKeys(m map[string][]string) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}
