package service

// Enrichment: provider status, the whole-library catalog pass, and the
// synchronous per-item fetch shared by the editor's endpoint and the
// health fix queue.

import (
	"context"
	"encoding/json"
	"log/slog"
	"sort"
	"strings"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
	waxlabel "github.com/colespringer/waxlabel"

	"github.com/colespringer/waxdeck/server/internal/genre"
)

// Per-item enrichment want names, shared by the API surface and the
// health fixer.
const (
	enrichWantCover  = "cover"
	enrichWantLyrics = "lyrics"
	enrichWantGenres = "genres"
	enrichWantBook   = "book"
)

// enrichGenreCap bounds how many provider genres a per-item apply joins
// into the genre scalar.
const enrichGenreCap = 3

// enrichJobWindow is how far back the status surface looks for the newest
// finished enrichment pass. The job list is every kind, newest first, so
// scans and analyzes share the window; deep enough that ordinary traffic
// does not push the last pass out, and still one query.
const enrichJobWindow = 200

// EnrichmentProviderDTO is one registered provider.
type EnrichmentProviderDTO struct {
	Name         string
	Capabilities []string
	Configured   bool
	Builtin      bool
}

// CoverageCountDTO is enriched versus total for one entity class.
type CoverageCountDTO struct {
	Enriched int
	Total    int
}

// EnrichmentCoverageDTO is the catalog's enrichment coverage.
type EnrichmentCoverageDTO struct {
	Artists       CoverageCountDTO
	ReleaseGroups CoverageCountDTO
	Books         CoverageCountDTO
	Lyrics        CoverageCountDTO
}

// EnrichmentLastRunDTO is what the most recent finished pass did.
//
// Coverage says how much of the library is enriched; this says whether the
// last pass accomplished anything, which coverage cannot: a pass that matched
// nothing, and one whose every tag write failed, both leave coverage put.
type EnrichmentLastRunDTO struct {
	// The release match: which pressing the library holds, from a barcode
	// or catalog number. Searched without matched is a library whose
	// albums carry no identifiers, not a broken pass.
	AlbumsSearched int
	AlbumsMatched  int
	// Zero unless the run wrote tags. Unrepresented is not a failure: the
	// format cannot store the key and the bytes are unchanged.
	TagsWritten       int
	TagsFailed        int
	TagsUnrepresented int
	TagsSkipped       int
	// 0 means no pass has finished, so the zeros above mean "not yet".
	FinishedAtNS int64
}

// EnrichmentStatusDTO is the status surface aggregate.
type EnrichmentStatusDTO struct {
	Providers []EnrichmentProviderDTO
	Coverage  EnrichmentCoverageDTO
	Running   bool
	// Configured reports whether the whole-library pass can run at all: it
	// needs a MusicBrainz contact, which is boot config. Not a provider's
	// own Configured -- every provider can have its key and the pass still
	// refuse.
	Configured bool
	// LastRun is absent until a pass has finished on this catalog.
	LastRun *EnrichmentLastRunDTO
}

// capabilityStrings renders a provider capability bitset as the API's
// capability names.
func capabilityStrings(c enrich.Capability) []string {
	var out []string
	if c.Has(enrich.CapIdentity) {
		out = append(out, "identity")
	}
	if c.Has(enrich.CapGenres) {
		out = append(out, "genres")
	}
	if c.Has(enrich.CapCover) {
		out = append(out, "cover")
	}
	if c.Has(enrich.CapLyrics) {
		out = append(out, "lyrics")
	}
	if c.Has(enrich.CapBookMeta) {
		out = append(out, "book")
	}
	return out
}

// EnrichmentStatusFor reports the registered providers, the catalog's
// enrichment coverage, and whether a whole-library pass is running.
func (l *Library) EnrichmentStatusFor(ctx context.Context, uc *UserCtx) (EnrichmentStatusDTO, error) {
	if !uc.Admin {
		return EnrichmentStatusDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	out := EnrichmentStatusDTO{
		Providers:  []EnrichmentProviderDTO{},
		Configured: l.enrichmentConfigured,
	}
	// This server's own providers first (priority order). They are
	// configured by construction: an injected provider is only wired
	// when its key is set.
	for _, p := range l.enrichProviders {
		out.Providers = append(out.Providers, EnrichmentProviderDTO{
			Name:         p.Name(),
			Capabilities: capabilityStrings(p.Capabilities()),
			Configured:   true,
		})
	}
	// The catalog's key-free built-ins, listed statically: the facade
	// does not enumerate them. The MusicBrainz identity spine is not a
	// port provider and is not listed.
	out.Providers = append(out.Providers,
		EnrichmentProviderDTO{Name: "coverartarchive", Capabilities: []string{"cover"}, Configured: true, Builtin: true},
		EnrichmentProviderDTO{Name: "listenbrainz", Capabilities: []string{"genres"}, Configured: true, Builtin: true},
		EnrichmentProviderDTO{Name: "lrclib", Capabilities: []string{"lyrics"}, Configured: true, Builtin: true},
	)

	cov, err := l.lib.EnrichmentCoverage(ctx)
	if err != nil {
		return EnrichmentStatusDTO{}, classify(err)
	}
	out.Coverage.Artists.Enriched = cov.Artists
	out.Coverage.ReleaseGroups.Enriched = cov.ReleaseGroups
	out.Coverage.Books.Enriched = cov.Books
	// Totals are best-effort from the read side: the coverage read
	// reports enriched rows only. Artists come from the facet bucket
	// count and books from a kind count. The facade exposes no
	// release-group count (that total stays zero, meaning unknown), and
	// per-track lyrics coverage is not reported upstream, so lyrics
	// shows zero enriched over the music track count.
	// Order does not matter to a count of buckets, and no top-N: the
	// whole enumeration is the answer.
	if fr, ferr := l.lib.Facet(ctx, query.New(query.EntityItems).Build(), read.GroupArtist, "", 0, ""); ferr == nil {
		n := 0
		for _, b := range fr.Buckets {
			if !b.IsUnknown {
				n++
			}
		}
		out.Coverage.Artists.Total = n
	}
	if n, cerr := l.lib.Count(ctx, query.New(query.EntityItems).
		Where("kind", query.OpIs, string(model.KindBook)).Build(), ""); cerr == nil {
		out.Coverage.Books.Total = n
	}
	if n, cerr := l.lib.Count(ctx, query.New(query.EntityTracks).Build(), ""); cerr == nil {
		out.Coverage.Lyrics.Total = n
	}

	// One job read answers both: whether a pass is in flight, and what the
	// newest finished one did. The job row's JSON summary is the only place
	// those counters survive the process that produced them.
	if jobs, jerr := l.lib.Jobs(ctx, enrichJobWindow); jerr == nil {
		for _, j := range jobs {
			if j.Kind != "enrich" {
				continue
			}
			if j.State == model.JobRunning {
				out.Running = true
				continue
			}
			// Newest first, so the first that parses wins; a run with no
			// summary is skipped rather than read as a pass that did nothing.
			if out.LastRun == nil && j.Result != "" {
				var r enrich.Result
				if json.Unmarshal([]byte(j.Result), &r) == nil {
					out.LastRun = &EnrichmentLastRunDTO{
						AlbumsSearched:    r.AlbumsSearched,
						AlbumsMatched:     r.AlbumsMatched,
						TagsWritten:       r.TagsWritten,
						TagsFailed:        r.TagsFailed,
						TagsUnrepresented: r.TagsUnrepresented,
						TagsSkipped:       r.TagsSkipped,
						FinishedAtNS:      j.FinishedAt,
					}
				}
			}
		}
	}
	return out, nil
}

// RunEnrichment starts the catalog's whole-library enrichment pass as a
// background job and returns the job pid. The job launches on the
// process context, not the request's, so it survives the 202 that
// reported it (mirroring Rescan).
func (l *Library) RunEnrichment(ctx context.Context, uc *UserCtx, force bool) (string, error) {
	if !uc.Admin {
		return "", &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	// WriteTags rather than the catalog's WriteEnrichmentTags option: that
	// one is fixed at open and the catalog ORs the two, so per-run is what
	// lets the admin toggle work without a restart.
	pid, err := l.lib.StartEnrich(l.procCtx, waxbin.EnrichOptions{
		Force:     force,
		WriteTags: l.currentToggles().enrichWriteTags,
	})
	if err != nil {
		// The catalog's refusal names WAXBIN_ENRICH_CONTACT, a knob a
		// WaxDeck operator does not have.
		if KindOf(classify(err)) == KindUnsupported {
			return "", &Error{
				Kind: KindUnsupported,
				Msg: "the catalog's enrichment pass is not configured on this server. " +
					"MusicBrainz requires an identifying contact before anything is sent, " +
					"so set -enrichment-contact (WAXDECK_ENRICHMENT_CONTACT) to an email " +
					"or a URL and restart",
				Err: err,
			}
		}
		return "", classify(err)
	}
	return apiPID(PrefixJob, pid), nil
}

// EnrichFieldProposalDTO is one field an enrichment provider would
// fill: the editor's diff row, and the commit's instruction.
type EnrichFieldProposalDTO struct {
	Name     string
	Current  string
	Proposed string
	Provider string
}

// EnrichCoverProposalDTO is one cover image a provider would store.
// The bytes ride the proposal both ways so the commit stores exactly
// the picture the preview showed.
type EnrichCoverProposalDTO struct {
	Provider  string
	Format    string
	SourceURL string
	Data      []byte
}

// EnrichPreviewDTO is what a one-item enrichment would change. Fields
// and Cover together are the proposal an apply passes back.
type EnrichPreviewDTO struct {
	Fields  []EnrichFieldProposalDTO
	Cover   *EnrichCoverProposalDTO
	Skipped []string
}

// EnrichProposalDTO is a previewed enrichment handed back to commit.
type EnrichProposalDTO struct {
	Fields []EnrichFieldProposalDTO
	Cover  *EnrichCoverProposalDTO
}

// EnrichPreviewFor is the API's per-item enrichment preview: resolve
// the item through visibility, then run the providers without writing
// anything. The catalog's built-ins cannot be previewed (their fetch
// and write are one engine pass), so they are absent here by design.
func (l *Library) EnrichPreviewFor(ctx context.Context, uc *UserCtx, apiItemPID string, wants []string) (EnrichPreviewDTO, error) {
	if !l.CanCurateItem(ctx, uc, apiItemPID) {
		return EnrichPreviewDTO{}, &Error{Kind: KindForbidden, Msg: "administrators, or the user whose upload brought the item in"}
	}
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return EnrichPreviewDTO{}, err
	}
	return l.enrichProposeNow(ctx, it.PID, wants)
}

// EnrichItemFor is the API's per-item enrichment: resolve the item
// through visibility, then run the synchronous fetch - or, with a
// proposal, commit exactly what the preview answered instead of
// fetching fresh values the user never saw.
func (l *Library) EnrichItemFor(ctx context.Context, uc *UserCtx, apiItemPID string, wants []string, proposal *EnrichProposalDTO) (applied, skipped []string, err error) {
	if !l.CanCurateItem(ctx, uc, apiItemPID) {
		return nil, nil, &Error{Kind: KindForbidden, Msg: "administrators, or the user whose upload brought the item in"}
	}
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return nil, nil, err
	}
	if proposal != nil {
		applied, skipped, err = l.enrichCommitProposal(ctx, it.PID, wants, *proposal)
	} else {
		applied, skipped, err = l.EnrichItemNow(ctx, it.PID, wants)
	}
	if err != nil {
		return applied, skipped, err
	}
	// The interactive button also runs the catalog's key-free built-ins
	// per item, which the injected-provider port cannot reach; the health
	// fixer calls EnrichItemNow one want at a time, so it stays on the
	// injected path rather than re-running the whole item-scoped pass.
	// They run on the proposal path too: fill-when-empty means they can
	// never contradict what was approved, and dropping them would regress
	// every install whose only sources are the built-ins.
	l.enrichItemBuiltins(ctx, it, wants, &applied, &skipped)
	return applied, skipped, nil
}

// builtinProviderFor names the catalog built-in that backfills each
// per-item want. The built-ins (Cover Art Archive, ListenBrainz, LRCLIB)
// are not on the injected-provider port; the engine reaches them, and an
// item-scoped synchronous Enrich runs them per item.
var builtinProviderFor = map[string]string{
	enrichWantCover:  "coverartarchive",
	enrichWantLyrics: "lrclib",
	enrichWantGenres: "listenbrainz",
}

// enrichItemBuiltins backfills the interactive fetch with the catalog's
// key-free built-ins for the wanted artifacts the injected providers left
// empty. Injected providers keep priority: they ran first, so a built-in
// only claims an artifact that was still absent beforehand and is present
// after the item-scoped Enrich. Best-effort - a built-in failure leaves
// the injected result untouched.
func (l *Library) enrichItemBuiltins(ctx context.Context, it *model.ItemView, wants []string, applied, skipped *[]string) {
	var builtinWants []string
	for _, w := range wants {
		if _, ok := builtinProviderFor[w]; ok {
			builtinWants = append(builtinWants, w)
		}
	}
	if len(builtinWants) == 0 {
		return
	}
	before := make(map[string]bool, len(builtinWants))
	for _, w := range builtinWants {
		before[w] = l.artifactPresent(ctx, it, w)
	}
	// Item-scoped, fill-when-empty: the engine enriches this item's own
	// entities and never overwrites, so a built-in only fills real gaps. It
	// runs synchronously under the engine's shared enrich lease.
	if _, err := l.lib.Enrich(ctx, waxbin.EnrichOptions{ItemPID: it.PID}); err != nil {
		if KindOf(classify(err)) == KindConflict {
			// A concurrent enrich (a whole-catalog pass, or another fetch)
			// holds the lease. Report the still-missing built-in artifacts as
			// deferred rather than let the caller read a false success, so the
			// user knows to retry for those.
			for _, w := range builtinWants {
				if !before[w] {
					*skipped = append(*skipped, w+": enrichment is busy; try again")
				}
			}
			return
		}
		l.log.Warn("enrich: item built-ins", "item", it.PID, "err", err)
		return
	}
	for _, w := range builtinWants {
		if before[w] || !l.artifactPresent(ctx, it, w) {
			continue
		}
		*applied = append(*applied, w+": "+builtinProviderFor[w])
		*skipped = dropEntriesWithPrefix(*skipped, w+":")
	}
}

// artifactPresent reports whether the item already carries the wanted
// artifact, using the same presence tests the injected fetch uses: the
// art resolution chain for cover, stored lyrics for lyrics, the genre
// scalar for genres.
func (l *Library) artifactPresent(ctx context.Context, it *model.ItemView, want string) bool {
	switch want {
	case enrichWantCover:
		ref := model.EntityRef{Type: model.ArtTrack, PID: it.PID}
		if it.Kind == model.KindEpisode {
			ref.Type = model.ArtEpisode
		}
		_, err := l.lib.ArtProvenance(ctx, ref, model.ArtRoleFront)
		return err == nil
	case enrichWantLyrics:
		ly, err := l.lib.Lyrics(ctx, it.PID)
		return err == nil && ly.HasContent()
	case enrichWantGenres:
		cur, err := l.lib.Get(ctx, it.PID)
		return err == nil && cur.Genre != ""
	}
	return false
}

// dropEntriesWithPrefix returns entries without those starting with
// prefix, so a built-in that fills an artifact retires the injected
// path's "no provider hit" note for the same want.
func dropEntriesWithPrefix(entries []string, prefix string) []string {
	out := make([]string, 0, len(entries))
	for _, e := range entries {
		if !strings.HasPrefix(e, prefix) {
			out = append(out, e)
		}
	}
	return out
}

// EnrichItemNow runs the server-registered providers for the wanted
// artifacts against one item and applies what they return: fill when
// empty, lock respecting, never touching an unofficial-marked item.
// Applied entries read "cover: providername"; skipped entries read
// "cover: reason". A propose pass followed by a commit of everything
// it proposed - the same halves the preview and apply endpoints use,
// so the blind path cannot drift from the previewed one. The item
// state loads once and both halves share it: the health fixer calls
// this per want across whole-library passes, where re-reading would
// double every facade round trip.
func (l *Library) EnrichItemNow(ctx context.Context, pid model.PID, wants []string) (applied, skipped []string, err error) {
	if err := validateEnrichWants(wants); err != nil {
		return nil, nil, err
	}
	st, err := l.loadEnrichItemState(ctx, pid)
	if err != nil {
		return nil, nil, err
	}
	preview := l.enrichPropose(ctx, st, wants)
	if st.unofficial {
		// The propose half already skipped every want; the commit would
		// only say it again.
		return []string{}, preview.Skipped, nil
	}
	applied, commitSkipped, err := l.enrichCommit(ctx, st, wants, EnrichProposalDTO{
		Fields: preview.Fields, Cover: preview.Cover,
	})
	if err != nil {
		return nil, nil, err
	}
	return applied, append(preview.Skipped, commitSkipped...), nil
}

func validateEnrichWants(wants []string) error {
	for _, w := range wants {
		switch w {
		case enrichWantCover, enrichWantLyrics, enrichWantGenres, enrichWantBook:
		default:
			return errInvalid("unknown enrichment want " + w)
		}
	}
	return nil
}

// enrichItemState is one item's enrichment preconditions, read once
// and shared by the propose and commit halves.
type enrichItemState struct {
	it         *model.ItemView
	unofficial bool
	locked     map[string]bool
}

// loadEnrichItemState reads the item, its release status, and - for
// official content only, mirroring the pre-split order - its field
// locks. Unofficial content skips every want before locks matter.
func (l *Library) loadEnrichItemState(ctx context.Context, pid model.PID) (enrichItemState, error) {
	st := enrichItemState{locked: map[string]bool{}}
	var err error
	if st.it, err = l.lib.Get(ctx, pid); err != nil {
		return st, classify(err)
	}
	tags, err := l.lib.ItemTags(ctx, pid)
	if err != nil {
		return st, classify(err)
	}
	for _, t := range tags {
		if t.Key != releaseStatusKey {
			continue
		}
		for _, v := range t.Values {
			if v == releaseStatusUnofficial || v == releaseStatusBootleg {
				st.unofficial = true
				return st, nil
			}
		}
	}
	prov, err := l.lib.Provenance(ctx, pid)
	if err != nil {
		return st, classify(err)
	}
	for _, p := range prov {
		if p.Locked {
			st.locked[p.Field] = true
		}
	}
	return st, nil
}

// enrichProposeNow runs the registered providers for the wanted
// artifacts and reports what they would change, writing nothing.
func (l *Library) enrichProposeNow(ctx context.Context, pid model.PID, wants []string) (EnrichPreviewDTO, error) {
	if err := validateEnrichWants(wants); err != nil {
		return EnrichPreviewDTO{}, err
	}
	st, err := l.loadEnrichItemState(ctx, pid)
	if err != nil {
		return EnrichPreviewDTO{}, err
	}
	return l.enrichPropose(ctx, st, wants), nil
}

func (l *Library) enrichPropose(ctx context.Context, st enrichItemState, wants []string) EnrichPreviewDTO {
	out := EnrichPreviewDTO{Fields: []EnrichFieldProposalDTO{}, Skipped: []string{}}
	if st.unofficial {
		for _, w := range wants {
			out.Skipped = append(out.Skipped, w+": item is marked unofficial")
		}
		return out
	}
	for _, w := range wants {
		var s string
		switch w {
		case enrichWantCover:
			out.Cover, s = l.proposeCover(ctx, st.it, st.locked)
		case enrichWantGenres:
			var p *EnrichFieldProposalDTO
			p, s = l.proposeGenres(ctx, st.it, st.locked)
			if p != nil {
				out.Fields = append(out.Fields, *p)
			}
		case enrichWantLyrics:
			var p *EnrichFieldProposalDTO
			p, s = l.proposeLyrics(ctx, st.it, st.locked)
			if p != nil {
				out.Fields = append(out.Fields, *p)
			}
		case enrichWantBook:
			var ps []EnrichFieldProposalDTO
			ps, s = l.proposeBook(ctx, st.it, st.locked)
			out.Fields = append(out.Fields, ps...)
		}
		if s != "" {
			out.Skipped = append(out.Skipped, s)
		}
	}
	return out
}

// enrichWantForField names the want a proposal field row answers, or
// "" for a field enrichment never proposes.
func enrichWantForField(name string) string {
	switch name {
	case "genre":
		return enrichWantGenres
	case "lyrics":
		return enrichWantLyrics
	case "narrator", "publisher", "description", "year", "isbn":
		return enrichWantBook
	}
	return ""
}

// validateEnrichProposal refuses a malformed proposal whole, before
// anything writes: a partial refusal would land some fields and then
// answer 400 as if nothing had. Field names must be ones enrichment
// proposes, every part must answer a requested want, providers must be
// registered on this server's port (the proposal is the preview's own
// answer passed back, so a foreign name is tampering or a server whose
// providers changed underneath it - either way not a write to make
// under that mark), book fields must share one provider (the shape an
// honest propose produces, and what lets the commit stay one edit),
// and a cover must be a storable image.
func (l *Library) validateEnrichProposal(wants []string, proposal EnrichProposalDTO) error {
	wanted := map[string]bool{}
	for _, w := range wants {
		wanted[w] = true
	}
	registered := map[string]bool{}
	for _, p := range l.enrichProviders {
		registered[p.Name()] = true
	}
	if c := proposal.Cover; c != nil {
		if !wanted[enrichWantCover] {
			return errInvalid("the proposal carries a cover the request does not want")
		}
		if !registered[c.Provider] {
			return errInvalid("cover provider " + c.Provider + " is not registered on this server")
		}
		if err := validateArtworkBytes(c.Data); err != nil {
			// One kind for the caller: a format refusal here is a bad
			// proposal, not an unsupported upload.
			return errInvalid("cover proposal: " + err.Error())
		}
	}
	bookProvider := ""
	for _, f := range proposal.Fields {
		w := enrichWantForField(f.Name)
		if w == "" {
			return errInvalid("field " + f.Name + " is not one enrichment proposes")
		}
		if !wanted[w] {
			return errInvalid("the proposal fills " + f.Name + ", which the request does not want")
		}
		if !registered[f.Provider] {
			return errInvalid("provider " + f.Provider + " is not registered on this server")
		}
		if w == enrichWantBook {
			if bookProvider == "" {
				bookProvider = f.Provider
			} else if bookProvider != f.Provider {
				return errInvalid("book field proposals must name one provider")
			}
		}
	}
	return nil
}

// enrichCommitProposal is the API's apply-with-proposal entry: load the
// item state fresh (this is a separate request from the preview) and
// commit.
func (l *Library) enrichCommitProposal(ctx context.Context, pid model.PID, wants []string, proposal EnrichProposalDTO) (applied, skipped []string, err error) {
	if err := validateEnrichWants(wants); err != nil {
		return nil, nil, err
	}
	st, err := l.loadEnrichItemState(ctx, pid)
	if err != nil {
		return nil, nil, err
	}
	return l.enrichCommit(ctx, st, wants, proposal)
}

// enrichCommit writes a proposal's parts. The whole proposal validates
// before the first write, and the local guards re-run per part: a
// field locked or filled since the propose is skipped with the reason
// rather than overwritten, and nothing is fetched - the values written
// are the proposal's own.
func (l *Library) enrichCommit(ctx context.Context, st enrichItemState, wants []string, proposal EnrichProposalDTO) (applied, skipped []string, err error) {
	if err := l.validateEnrichProposal(wants, proposal); err != nil {
		return nil, nil, err
	}
	applied, skipped = []string{}, []string{}
	if st.unofficial {
		for _, w := range wants {
			skipped = append(skipped, w+": item is marked unofficial")
		}
		return applied, skipped, nil
	}
	record := func(a, s string) {
		if a != "" {
			applied = append(applied, a)
		}
		if s != "" {
			skipped = append(skipped, s)
		}
	}
	if proposal.Cover != nil {
		record(l.commitCover(ctx, st.it, *proposal.Cover, st.locked))
	}
	var bookFields []EnrichFieldProposalDTO
	for _, f := range proposal.Fields {
		switch f.Name {
		case "genre":
			record(l.commitGenres(ctx, st.it, f, st.locked))
		case "lyrics":
			record(l.commitLyrics(ctx, st.it, f, st.locked))
		default:
			// Validated above, so anything else is a book field.
			bookFields = append(bookFields, f)
		}
	}
	if len(bookFields) > 0 {
		record(l.commitBook(ctx, st.it, bookFields, st.locked))
	}
	return applied, skipped, nil
}

// namedEnrichProviders drops an injected provider that reports no name,
// mirroring the guard the catalog's own enrichment service applies to the
// same slice. A provider's name is the provenance mark stamped on
// everything it supplies, and the store refuses an enrichment value that
// names none - so a nameless provider would not degrade to an unmarked
// write, it would fail every enrich-now write it answered, once per
// request, with nothing but a log line to say why.
func namedEnrichProviders(providers []enrich.Provider, log *slog.Logger) []enrich.Provider {
	out := make([]enrich.Provider, 0, len(providers))
	for _, p := range providers {
		if p.Name() == "" {
			log.Warn("enrichment: dropping an injected provider with no name; its values could carry no provenance")
			continue
		}
		out = append(out, p)
	}
	return out
}

// enrichProvidersWith returns the registered providers advertising the
// wanted capability.
func (l *Library) enrichProvidersWith(want enrich.Capability) []enrich.Provider {
	var out []enrich.Provider
	for _, p := range l.enrichProviders {
		if p.Capabilities().Has(want) {
			out = append(out, p)
		}
	}
	return out
}

// coverGuard is the cover want's local preconditions, shared by the
// propose and commit halves so a slot that locked or filled between a
// preview and its apply is skipped, never overwritten. Presence is
// judged through the art resolution chain, so an item already covered
// by its album's art is left alone.
func (l *Library) coverGuard(ctx context.Context, it *model.ItemView, locked map[string]bool) (skippedEntry string) {
	// The catalog holds item-level art for tracks and books only, so an
	// episode write is refused whatever the bytes are. Without this the
	// want fetches a cover from every provider first and reports "no
	// provider hit", which reads as a lookup that missed rather than one
	// that could never have landed - and re-fetches on the next request.
	// An episode's picture is the feed's, resolved from its show.
	if it.Kind == model.KindEpisode {
		return "cover: an episode's cover comes from its feed"
	}
	if locked["art"] {
		return "cover: locked"
	}
	ref := model.EntityRef{Type: model.ArtTrack, PID: it.PID}
	if _, err := l.lib.ArtProvenance(ctx, ref, model.ArtRoleFront); err == nil {
		return "cover: already present"
	}
	return ""
}

// proposeCover asks the cover providers for one item's front cover and
// returns the first answer as a proposal, writing nothing.
func (l *Library) proposeCover(ctx context.Context, it *model.ItemView, locked map[string]bool) (proposal *EnrichCoverProposalDTO, skippedEntry string) {
	if s := l.coverGuard(ctx, it, locked); s != "" {
		return nil, s
	}
	providers := l.enrichProvidersWith(enrich.CapCover)
	if len(providers) == 0 {
		return nil, "cover: no provider"
	}
	req := enrich.Request{
		Type:   enrich.TargetReleaseGroup,
		Title:  firstNonEmpty(it.Album, it.Title),
		Artist: firstNonEmpty(it.AlbumArtist, it.Artist),
	}
	for _, p := range providers {
		cand, err := p.Enrich(ctx, req)
		if err != nil {
			l.log.Warn("enrich: cover provider", "provider", p.Name(), "err", err)
			continue
		}
		if cand == nil || cand.Cover == nil || len(cand.Cover.Data) == 0 {
			continue
		}
		// Validated at the fetch, so an oversized or undecodable answer
		// falls through to the next provider rather than ending the want
		// - the fall-through the pre-split write loop had - and the
		// preview never shows an image the commit would then refuse.
		if err := validateArtworkBytes(cand.Cover.Data); err != nil {
			l.log.Warn("enrich: cover provider returned an unusable image", "provider", p.Name(), "err", err)
			continue
		}
		return &EnrichCoverProposalDTO{
			Provider: p.Name(), Format: cand.Cover.Format,
			SourceURL: cand.Cover.SourceURL, Data: cand.Cover.Data,
		}, ""
	}
	return nil, "cover: no provider hit"
}

// commitCover stores a proposed cover. The bytes were validated with
// the whole proposal before any write.
func (l *Library) commitCover(ctx context.Context, it *model.ItemView, proposal EnrichCoverProposalDTO, locked map[string]bool) (appliedEntry, skippedEntry string) {
	if s := l.coverGuard(ctx, it, locked); s != "" {
		return "", s
	}
	// The cover is stamped with the provider that supplied it, so a
	// fetched picture is not reported as one a person chose. The lock is
	// left alone: enrichment forms no pin intent, and an unlocked slot is
	// already the only one it reaches. The format is what the provider
	// read off the transport, and it is a fallback the bytes beat: it
	// only decides for a picture that neither decodes nor sniffs, which
	// is otherwise stored with no name for what it is.
	if err := l.lib.SetItemArt(ctx, it.PID, model.ArtRoleFront, proposal.Data, waxbin.ArtEditOptions{
		Source: model.SourceEnrichment, Provider: proposal.Provider, SourceURL: proposal.SourceURL,
		Format: proposal.Format, Lock: model.LockUnchanged,
	}); err != nil {
		l.log.Warn("enrich: applying cover", "provider", proposal.Provider, "item", it.PID, "err", err)
		return "", "cover: could not be stored"
	}
	l.noteArtworkChanged(ctx)
	return "cover: " + proposal.Provider, ""
}

// genresGuard is the genre want's local preconditions, shared by the
// propose and commit halves.
func genresGuard(it *model.ItemView, locked map[string]bool) (skippedEntry string) {
	if locked["genre"] {
		return "genres: locked"
	}
	if it.Genre != "" {
		return "genres: already present"
	}
	return ""
}

// proposeGenres asks the genre providers and returns the first
// answer's normalized, capped join as a proposal, writing nothing.
func (l *Library) proposeGenres(ctx context.Context, it *model.ItemView, locked map[string]bool) (proposal *EnrichFieldProposalDTO, skippedEntry string) {
	if s := genresGuard(it, locked); s != "" {
		return nil, s
	}
	providers := l.enrichProvidersWith(enrich.CapGenres)
	if len(providers) == 0 {
		return nil, "genres: no provider"
	}
	req := enrich.Request{
		Type:   enrich.TargetReleaseGroup,
		Title:  firstNonEmpty(it.Album, it.Title),
		Artist: firstNonEmpty(it.AlbumArtist, it.Artist),
	}
	for _, p := range providers {
		cand, err := p.Enrich(ctx, req)
		if err != nil {
			l.log.Warn("enrich: genre provider", "provider", p.Name(), "err", err)
			continue
		}
		if cand == nil || len(cand.Genres) == 0 {
			continue
		}
		// Normalize, then cap, then join. Two raw provider tags routinely
		// name one genre ("Rap" and "Hip-Hop"), so capping first would
		// spend slots on duplicates; normalizing first also keeps this
		// path from writing a value the continuous sweeper would rewrite
		// on its next pass.
		genres := l.normalizeProviderGenres(ctx, cand.Genres)
		if len(genres) == 0 {
			continue
		}
		if len(genres) > enrichGenreCap {
			genres = genres[:enrichGenreCap]
		}
		return &EnrichFieldProposalDTO{
			Name: "genre", Current: it.Genre, Proposed: genre.Join(genres), Provider: p.Name(),
		}, ""
	}
	return nil, "genres: no provider hit"
}

// commitGenres writes a proposed genre scalar.
func (l *Library) commitGenres(ctx context.Context, it *model.ItemView, proposal EnrichFieldProposalDTO, locked map[string]bool) (appliedEntry, skippedEntry string) {
	if s := genresGuard(it, locked); s != "" {
		return "", s
	}
	if proposal.Proposed == "" {
		return "", "genres: the proposal carries no value"
	}
	if err := l.lib.EditFields(ctx, it.PID,
		map[string]string{"genre": proposal.Proposed},
		waxbin.EditOptions{
			Source: model.SourceEnrichment, Provider: proposal.Provider, Lock: model.LockUnchanged,
		}); err != nil {
		l.log.Warn("enrich: applying genres", "provider", proposal.Provider, "item", it.PID, "err", err)
		return "", "genres: could not be stored"
	}
	return "genres: " + proposal.Provider, ""
}

// lyricsGuard is the lyrics want's local preconditions, shared by the
// propose and commit halves.
func (l *Library) lyricsGuard(ctx context.Context, it *model.ItemView, locked map[string]bool) (skippedEntry string) {
	if it.Kind != model.KindTrack {
		return "lyrics: music only"
	}
	if locked["lyrics"] {
		return "lyrics: locked"
	}
	if ly, err := l.lib.Lyrics(ctx, it.PID); err == nil && ly.HasContent() {
		return "lyrics: already present"
	}
	return ""
}

// proposeLyrics asks the lyrics providers and returns the first answer
// as a proposal, writing nothing. A timed candidate is rendered as LRC
// text (the proposal is one string both ways); its plain shadow, when
// a provider sends both, is dropped for the richer form. The catalog's
// lrclib built-in is not on the injected-provider port, so with no
// registered lyrics provider the want reports "no provider" and the
// whole-library pass remains the way to fetch lyrics.
func (l *Library) proposeLyrics(ctx context.Context, it *model.ItemView, locked map[string]bool) (proposal *EnrichFieldProposalDTO, skippedEntry string) {
	if s := l.lyricsGuard(ctx, it, locked); s != "" {
		return nil, s
	}
	providers := l.enrichProvidersWith(enrich.CapLyrics)
	if len(providers) == 0 {
		return nil, "lyrics: no provider"
	}
	req := enrich.Request{
		Type:        enrich.TargetRecording,
		Title:       it.Title,
		Artist:      it.Artist,
		Album:       it.Album,
		DurationSec: int(it.DurationMS / 1000),
	}
	for _, p := range providers {
		cand, err := p.Enrich(ctx, req)
		if err != nil {
			l.log.Warn("enrich: lyrics provider", "provider", p.Name(), "err", err)
			continue
		}
		if cand == nil || !cand.Lyrics.HasContent() {
			continue
		}
		proposed := cand.Lyrics.Unsynced
		if len(cand.Lyrics.Synced) > 0 {
			lines := make([]waxlabel.SyncedLine, 0, len(cand.Lyrics.Synced))
			for _, ln := range cand.Lyrics.Synced {
				lines = append(lines, waxlabel.SyncedLine{
					Time: time.Duration(ln.TimeMS) * time.Millisecond, Text: ln.Text,
				})
			}
			proposed = waxlabel.FormatLRC(lines)
		}
		return &EnrichFieldProposalDTO{
			Name: "lyrics", Proposed: proposed, Provider: p.Name(),
		}, ""
	}
	return nil, "lyrics: no provider hit"
}

// commitLyrics stores proposed lyrics, parsing the proposal's one
// string back into timed lines when it is LRC.
func (l *Library) commitLyrics(ctx context.Context, it *model.ItemView, proposal EnrichFieldProposalDTO, locked map[string]bool) (appliedEntry, skippedEntry string) {
	if s := l.lyricsGuard(ctx, it, locked); s != "" {
		return "", s
	}
	ly := &model.Lyrics{Source: model.SourceEnrichment, Provider: proposal.Provider}
	// Synced only when the whole text is LRC. A plain block with one
	// stray stamp parses to one timed line and everything else dropped -
	// storing that as synced would silently discard the lyric. A propose
	// round trip is clean by construction (FormatLRC emits only stamped
	// lines, and blank lines and ID tags do not count as drops).
	lines, dropped := waxlabel.ParseLRCReportFull(proposal.Proposed)
	if len(lines) > 0 && len(dropped) == 0 {
		ly.Synced = make([]model.SyncedLine, 0, len(lines))
		for _, ln := range lines {
			ly.Synced = append(ly.Synced, model.SyncedLine{TimeMS: ln.Time.Milliseconds(), Text: ln.Text})
		}
	} else {
		ly.Unsynced = proposal.Proposed
	}
	if !ly.HasContent() {
		return "", "lyrics: the proposal carries no text"
	}
	if err := l.lib.SetLyrics(ctx, it.PID, ly, model.LockUnchanged, false); err != nil {
		l.log.Warn("enrich: applying lyrics", "provider", proposal.Provider, "item", it.PID, "err", err)
		return "", "lyrics: could not be stored"
	}
	return "lyrics: " + proposal.Provider, ""
}

// bookGuard is the book want's local preconditions, shared by the
// propose and commit halves. Book providers key on the ASIN, so an
// item without one is skipped with the reason.
func bookGuard(it *model.ItemView) (skippedEntry string) {
	if it.Kind != model.KindBook {
		return "book: not an audiobook"
	}
	if it.ASIN == "" {
		return "book: book metadata needs an ASIN"
	}
	return ""
}

// proposeBook asks the book providers for an audiobook's metadata
// (narrator, publisher, description, identifiers) and returns the
// first useful answer's fill-when-empty edits as one proposal row per
// field, writing nothing.
func (l *Library) proposeBook(ctx context.Context, it *model.ItemView, locked map[string]bool) (proposals []EnrichFieldProposalDTO, skippedEntry string) {
	if s := bookGuard(it); s != "" {
		return nil, s
	}
	providers := l.enrichProvidersWith(enrich.CapBookMeta)
	if len(providers) == 0 {
		return nil, "book: no provider"
	}
	detail, err := l.lib.Book(ctx, it.PID)
	if err != nil {
		l.log.Warn("enrich: reading book detail", "item", it.PID, "err", err)
		return nil, "book: unreadable"
	}
	req := enrich.Request{
		Type:   enrich.TargetBook,
		Title:  it.Title,
		Artist: it.Artist,
		ASIN:   it.ASIN,
	}
	for _, p := range providers {
		cand, err := p.Enrich(ctx, req)
		if err != nil {
			l.log.Warn("enrich: book provider", "provider", p.Name(), "err", err)
			continue
		}
		if cand == nil {
			continue
		}
		edits, skipped := bookEnrichEdits(cand, detail, it, locked)
		for field, val := range skipped {
			l.log.Debug("enrich: skipping malformed provider value", "provider", p.Name(), "item", it.PID, "field", field, "value", val)
		}
		if len(edits) == 0 {
			if len(skipped) > 0 {
				// This provider offered only values WaxBin would reject, so the
				// item is unchanged; try the next provider instead of ending the
				// pass here (the pre-skip code fell through via the edit error).
				continue
			}
			return nil, "book: nothing new to fill"
		}
		names := make([]string, 0, len(edits))
		for name := range edits {
			names = append(names, name)
		}
		sort.Strings(names)
		out := make([]EnrichFieldProposalDTO, 0, len(edits))
		for _, name := range names {
			out = append(out, EnrichFieldProposalDTO{Name: name, Proposed: edits[name], Provider: p.Name()})
		}
		return out, ""
	}
	return nil, "book: no provider hit"
}

// commitBook writes proposed book fields, re-filtered through the
// fill-when-empty rules, as one edit: validation pinned the proposals
// to a single provider, so there is no second write to half-fail into
// a response that says nothing landed.
func (l *Library) commitBook(ctx context.Context, it *model.ItemView, proposals []EnrichFieldProposalDTO, locked map[string]bool) (appliedEntry, skippedEntry string) {
	if s := bookGuard(it); s != "" {
		return "", s
	}
	detail, err := l.lib.Book(ctx, it.PID)
	if err != nil {
		l.log.Warn("enrich: reading book detail", "item", it.PID, "err", err)
		return "", "book: unreadable"
	}
	edits := map[string]string{}
	for _, p := range proposals {
		if p.Proposed == "" || !bookFieldFillable(p.Name, detail, it, locked) || !bookValueValid(p.Name, p.Proposed) {
			continue
		}
		edits[p.Name] = p.Proposed
	}
	if len(edits) == 0 {
		return "", "book: nothing new to fill"
	}
	provider := proposals[0].Provider
	if err := l.lib.EditFields(ctx, it.PID, edits, waxbin.EditOptions{
		Source: model.SourceEnrichment, Provider: provider, Lock: model.LockUnchanged,
	}); err != nil {
		l.log.Warn("enrich: applying book fields", "provider", provider, "item", it.PID, "err", err)
		return "", "book: could not be stored"
	}
	return "book: " + provider, ""
}

// bookFieldFillable reports whether one book scalar is still honestly
// fillable: currently empty and not locked. The two identifier-bearing
// halves live on different reads, which is why both come in.
func bookFieldFillable(name string, detail *model.BookDetail, it *model.ItemView, locked map[string]bool) bool {
	if locked[name] {
		return false
	}
	switch name {
	case "publisher":
		return detail.Publisher == ""
	case "isbn":
		return detail.ISBN == ""
	case "narrator":
		return it.Narrator == ""
	case "description":
		return detail.Description == ""
	case "year":
		return it.Year == 0
	}
	return false
}

// bookValueValid rejects a value WaxBin would refuse on write - a
// malformed ISBN or a non-numeric year - because one bad value fails
// the whole edit and costs the proposal's other fields.
func bookValueValid(name, value string) bool {
	switch name {
	case "isbn":
		return validISBN(value)
	case "year":
		return validYear(value)
	}
	return true
}

// bookEnrichEdits maps a book provider candidate to the fill-when-empty edits it
// can honestly supply: only fields the item currently lacks and has not locked.
// A provider value that WaxBin would reject on write is dropped rather than
// added; dropped values are returned keyed by field so the caller can log them.
func bookEnrichEdits(cand *enrich.Candidate, detail *model.BookDetail, it *model.ItemView, locked map[string]bool) (edits, skipped map[string]string) {
	edits = map[string]string{}
	skipped = map[string]string{}
	consider := func(name, value string) {
		if value == "" || !bookFieldFillable(name, detail, it, locked) {
			return
		}
		if bookValueValid(name, value) {
			edits[name] = value
		} else {
			skipped[name] = value
		}
	}
	consider("publisher", cand.Publisher)
	consider("isbn", cand.ISBN)
	// Generic curated fields ride Candidate.Fields; only the book
	// scalars this path can honestly fill-when-empty are accepted.
	for k, v := range cand.Fields {
		switch k {
		case "narrator", "description", "year":
			consider(k, v)
		}
	}
	return edits, skipped
}
