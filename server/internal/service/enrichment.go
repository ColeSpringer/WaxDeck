package service

// Enrichment: provider status, the whole-library catalog pass, and the
// synchronous per-item fetch shared by the editor's endpoint and the
// health fix queue.

import (
	"cmp"
	"context"
	"encoding/json"
	"log/slog"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"
	waxlabel "github.com/colespringer/waxlabel"

	"github.com/colespringer/waxdeck/server/internal/genre"
	"github.com/colespringer/waxdeck/server/internal/providers"
)

// enrichAsk dispatches one provider lookup, naming the capability the
// caller will read on the request itself so a multi-capability provider
// stops fetching what would be discarded. The port carries the want
// now, so this is a one-field stamp rather than the type assertion it
// used to be, and the catalog's own whole-library pass stamps its
// passes the same way.
func enrichAsk(ctx context.Context, p enrich.Provider, req enrich.Request, want enrich.Capability) (*enrich.Candidate, error) {
	req.Want = want
	return p.Enrich(ctx, req)
}

// Per-item enrichment want names, shared by the API surface and the
// health fixer.
const (
	enrichWantCover  = "cover"
	enrichWantLyrics = "lyrics"
	enrichWantGenres = "genres"
	enrichWantBook   = "book"
	enrichWantFields = "fields"
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
	// Enabled is the operator's switch.
	Enabled bool
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

// EnrichmentLastRunDTO is what the most recent finished pass did: the
// catalog's own tallies, one for one. Each walk counts what it looked up
// and what some source answered for.
type EnrichmentLastRunDTO struct {
	ArtistsEnriched, ArtistsMatched             int
	ReleaseGroupsEnriched, ReleaseGroupsMatched int
	AlbumsSearched, AlbumsMatched               int
	BooksEnriched, BooksMatched                 int
	LyricsEnriched, LyricsMatched               int
	GroupArtEnriched, GroupArtMatched           int
	ArtistArtEnriched, ArtistArtMatched         int
	AlbumArtEnriched, AlbumArtMatched           int
	TrackFieldsEnriched, TrackFieldsMatched     int
	BookFieldsEnriched, BookFieldsMatched       int
	AlbumFieldsEnriched, AlbumFieldsMatched     int
	// Retried counts re-asks of expired misses, which the walks count too.
	Retried int
	// Deferred counts lookups left owed for a later pass to ask again,
	// which the walks count too.
	Deferred int
	// Images handed to the catalog, and album fronts reused from the group's.
	ArtFetched, AuxArtFetched, ArtReused int
	// Zero unless the run wrote tags.
	TagsWritten, TagsFailed, TagsUnrepresented, TagsSkipped int
	// 0 means no pass has finished, so the zeros above mean "not yet".
	FinishedAtNS int64
}

// lastRunFrom maps a finished pass's tallies onto the status surface.
func lastRunFrom(r enrich.Result, finishedAtNS int64) *EnrichmentLastRunDTO {
	return &EnrichmentLastRunDTO{
		ArtistsEnriched: r.ArtistsEnriched, ArtistsMatched: r.ArtistsMatched,
		ReleaseGroupsEnriched: r.ReleaseGroupsEnriched, ReleaseGroupsMatched: r.ReleaseGroupsMatched,
		AlbumsSearched: r.AlbumsSearched, AlbumsMatched: r.AlbumsMatched,
		BooksEnriched: r.BooksEnriched, BooksMatched: r.BooksMatched,
		LyricsEnriched: r.LyricsEnriched, LyricsMatched: r.LyricsMatched,
		GroupArtEnriched: r.GroupArtEnriched, GroupArtMatched: r.GroupArtMatched,
		ArtistArtEnriched: r.ArtistArtEnriched, ArtistArtMatched: r.ArtistArtMatched,
		AlbumArtEnriched: r.AlbumArtEnriched, AlbumArtMatched: r.AlbumArtMatched,
		TrackFieldsEnriched: r.TrackFieldsEnriched, TrackFieldsMatched: r.TrackFieldsMatched,
		BookFieldsEnriched: r.BookFieldsEnriched, BookFieldsMatched: r.BookFieldsMatched,
		AlbumFieldsEnriched: r.AlbumFieldsEnriched, AlbumFieldsMatched: r.AlbumFieldsMatched,
		Retried: r.Retried, Deferred: r.Deferred,
		ArtFetched: r.ArtFetched, AuxArtFetched: r.AuxArtFetched, ArtReused: r.ArtReused,
		TagsWritten: r.TagsWritten, TagsFailed: r.TagsFailed,
		TagsUnrepresented: r.TagsUnrepresented, TagsSkipped: r.TagsSkipped,
		FinishedAtNS: finishedAtNS,
	}
}

// EnrichmentStatusDTO is the status surface aggregate.
type EnrichmentStatusDTO struct {
	Providers []EnrichmentProviderDTO
	Coverage  EnrichmentCoverageDTO
	Running   bool
	// RunningJob is the API pid of the running pass's job, when one runs.
	RunningJob string
	// Configured reports whether a whole-library pass would do anything:
	// some phase can run. Not a provider's own Configured -- every
	// provider can have its key and no phase still be runnable.
	Configured bool
	// MusicbrainzConfigured reports whether the identity phases can run,
	// which needs the contact and is boot config. The provider-gated
	// phases run without it, so this is the honest half of Configured.
	MusicbrainzConfigured bool
	// Phases names what a run started now would execute.
	Phases []string
	// LastRun is absent until a pass has finished on this catalog.
	LastRun *EnrichmentLastRunDTO
}

// enrichPhaseSpec is one phase as the status surface names it: what opens
// it (the contact when gate is zero), the catalog phases a force of it
// names, and what it needs, in this server's knobs.
type enrichPhaseSpec struct {
	name    string
	gate    enrich.Capability
	match   bool // needs the release match too
	catalog []model.EnrichPhase
	needs   string
}

// enrichPhaseTable is every phase in run order. It copies the gating
// upstream's Run applies, since the facade exports no phase list; the
// phases test pins it phase by phase against the catalog's own check.
var enrichPhaseTable = []enrichPhaseSpec{
	{name: "identity", catalog: []model.EnrichPhase{model.EnrichPhaseArtist, model.EnrichPhaseReleaseGroup, model.EnrichPhaseBook},
		needs: "it needs -enrichment-contact (WAXDECK_ENRICHMENT_CONTACT)"},
	{name: "releases", match: true, catalog: []model.EnrichPhase{model.EnrichPhaseAlbumRelease},
		needs: "it needs -enrichment-contact (WAXDECK_ENRICHMENT_CONTACT) and -enrichment-match-releases (WAXDECK_ENRICHMENT_MATCH_RELEASES)"},
	{name: "aux-art", gate: enrich.CapCover | enrich.CapAuxArt, catalog: []model.EnrichPhase{model.EnrichPhaseGroupArt},
		needs: "it needs -enrichment-contact (WAXDECK_ENRICHMENT_CONTACT) or a provider of covers or auxiliary art"},
	{name: "artist-art", gate: enrich.CapArtistArt, catalog: []model.EnrichPhase{model.EnrichPhaseArtistArt},
		needs: "artist art is off (WAXDECK_ARTIST_ART=false)"},
	{name: "album-art", gate: enrich.CapCover | enrich.CapAuxArt, catalog: []model.EnrichPhase{model.EnrichPhaseAlbumArt},
		needs: "it needs -enrichment-contact (WAXDECK_ENRICHMENT_CONTACT) or a provider of covers or auxiliary art"},
	{name: "lyrics", gate: enrich.CapLyrics, catalog: []model.EnrichPhase{model.EnrichPhaseLyrics},
		needs: "it needs -enrichment-contact (WAXDECK_ENRICHMENT_CONTACT) or a lyrics provider"},
	{name: "track-fields", gate: enrich.CapFields, catalog: []model.EnrichPhase{model.EnrichPhaseTrackFields},
		needs: "no registered provider supplies fields"},
	{name: "book-fields", gate: enrich.CapBookMeta, catalog: []model.EnrichPhase{model.EnrichPhaseBookFields},
		needs: "no registered provider supplies book metadata"},
	{name: "album-fields", gate: enrich.CapFields, catalog: []model.EnrichPhase{model.EnrichPhaseAlbumFields},
		needs: "no registered provider supplies fields"},
}

// catalogBuiltins are the catalog's key-free providers, registered only
// with the contact: what each supplies, and the per-item want it fills.
type catalogBuiltin struct {
	name string
	cap  enrich.Capability
	want string
}

var catalogBuiltins = []catalogBuiltin{
	{"coverartarchive", enrich.CapCover, enrichWantCover},
	{"listenbrainz", enrich.CapGenres, enrichWantGenres},
	{"lrclib", enrich.CapLyrics, enrichWantLyrics},
}

// ReservedEnrichNames are the names the catalog stamps values or labels
// markers with and drops an injected provider for taking, so startup
// refuses a custom provider under one rather than list it here and lose it
// there.
var ReservedEnrichNames = []string{
	enrich.ProviderMusicBrainz, "musicbrainz:edition", enrich.ProviderCoverArt,
	enrich.ProviderListenBrainz, enrich.ProviderLRCLIB, "none",
}

// builtinFor names the built-in that fills a per-item want, if any.
func builtinFor(want string) (string, bool) {
	for _, b := range catalogBuiltins {
		if b.want == want {
			return b.name, true
		}
	}
	return "", false
}

// enrichmentPhases names the phases a run started now would execute.
func (l *Library) enrichmentPhases() []string {
	return l.phasesWith(l.sources.live())
}

// phasesWith names the phases a run over providers would execute.
func (l *Library) phasesWith(providers []enrich.Provider) []string {
	var caps enrich.Capability
	for _, p := range providers {
		caps |= p.Capabilities()
	}
	if l.musicbrainzConfigured {
		for _, b := range catalogBuiltins {
			caps |= b.cap
		}
	}
	phases := []string{}
	for _, p := range enrichPhaseTable {
		runs := caps.Has(p.gate)
		if p.gate == 0 {
			runs = l.musicbrainzConfigured && (!p.match || l.enrichmentMatchReleases)
		}
		if runs {
			phases = append(phases, p.name)
		}
	}
	return phases
}

// fillEnrichmentRoster sets the parts of the status the source order
// decides: the providers as listed, the phases, and whether any runs.
func (l *Library) fillEnrichmentRoster(out *EnrichmentStatusDTO) {
	out.Phases = l.enrichmentPhases()
	// A pass does something exactly when it has a phase to run, which is
	// the same rule the catalog refuses on.
	out.Configured = len(out.Phases) > 0
	out.Providers = []EnrichmentProviderDTO{}
	// This server's own providers first, in the operator's order. They
	// are configured by construction: an injected provider is only wired
	// when its key is set.
	for _, src := range l.sources.resolved() {
		p := l.sources.provider(src.Name)
		out.Providers = append(out.Providers, EnrichmentProviderDTO{
			Name:         p.Name(),
			Capabilities: providers.CapabilityNames(p.Capabilities()),
			Configured:   true,
			Enabled:      src.Enabled,
		})
	}
	// The catalog's key-free built-ins, listed statically: the facade
	// does not enumerate them. The MusicBrainz identity spine is not a
	// port provider and is not listed.
	//
	// Key-free is not the same as unconfigured: they are public
	// services that want an identifying agent, and the catalog does not
	// register them at all without the contact - so that is what
	// decides whether they can run.
	for _, b := range catalogBuiltins {
		out.Providers = append(out.Providers, EnrichmentProviderDTO{
			Name: b.name, Capabilities: providers.CapabilityNames(b.cap),
			Configured: l.musicbrainzConfigured, Builtin: true, Enabled: true,
		})
	}
}

// EnrichmentStatusFor reports the registered providers, the catalog's
// enrichment coverage, and whether a whole-library pass is running.
func (l *Library) EnrichmentStatusFor(ctx context.Context, uc *UserCtx) (EnrichmentStatusDTO, error) {
	if !uc.Admin {
		return EnrichmentStatusDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	out := EnrichmentStatusDTO{MusicbrainzConfigured: l.musicbrainzConfigured}
	l.fillEnrichmentRoster(&out)

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
				out.RunningJob = apiPID(PrefixJob, j.PID)
				continue
			}
			// Newest first, so the first that parses wins; a run with no
			// summary is skipped rather than read as a pass that did nothing.
			if out.LastRun == nil && j.Result != "" {
				var r enrich.Result
				if json.Unmarshal([]byte(j.Result), &r) == nil {
					out.LastRun = lastRunFrom(r, j.FinishedAt)
				}
			}
		}
	}
	// A pass later jobs have pushed out of that window.
	if pid, ok, _ := l.followedJob(ctx, "enrich"); ok && !out.Running {
		out.Running = true
		out.RunningJob = apiPID(PrefixJob, pid)
	}
	return out, nil
}

// forcedPhases checks a phase-scoped force against what this server runs
// and names it in the catalog's phases.
func (l *Library) forcedPhases(force bool, names []string) ([]model.EnrichPhase, error) {
	if len(names) == 0 {
		return nil, nil
	}
	if force {
		return nil, errInvalid("force already re-asks every phase; send it or forcePhases, not both")
	}
	runs := l.enrichmentPhases()
	var out []model.EnrichPhase
	for _, name := range names {
		i := slices.IndexFunc(enrichPhaseTable, func(p enrichPhaseSpec) bool { return p.name == name })
		if i < 0 {
			return nil, errInvalid("unknown enrichment phase " + strconv.Quote(name))
		}
		if !slices.Contains(runs, name) {
			needs := enrichPhaseTable[i].needs
			if slices.Contains(l.phasesWith(l.sources.registered), name) {
				needs = "the sources that supply it are switched off"
			}
			return nil, &Error{Kind: KindUnsupported,
				Msg: "the " + name + " phase does not run on this server: " + needs}
		}
		out = append(out, enrichPhaseTable[i].catalog...)
	}
	return out, nil
}

// RunEnrichment starts the whole-library pass as a job on the process
// context, so it outlives the 202 that reported it; forcePhases re-asks
// those phases alone.
func (l *Library) RunEnrichment(ctx context.Context, uc *UserCtx, force bool, forcePhases []string) (string, error) {
	if !uc.Admin {
		return "", &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	// The saved order goes in first, unless a walk holds the one it
	// started with: then this run meets the conflict a second pass does.
	if !l.sources.apply(l.enrichPassRunning(ctx)) {
		return "", &Error{Kind: KindConflict, Msg: "an enrichment pass is already running"}
	}
	phases, err := l.forcedPhases(force, forcePhases)
	if err != nil {
		return "", err
	}
	// WriteTags rather than the catalog's WriteEnrichmentTags option: that
	// one is fixed at open and the catalog ORs the two, so per-run is what
	// lets the admin toggle work without a restart.
	pid, err := l.lib.StartEnrich(l.procCtx, waxbin.EnrichOptions{
		Force:       force,
		ForcePhases: phases,
		WriteTags:   l.currentToggles().enrichWriteTags,
	})
	if err != nil {
		return "", l.explainEnrichRefusal(err, forcePhases)
	}
	l.watchEnrichArtwork(pid)
	return apiPID(PrefixJob, pid), nil
}

// explainEnrichRefusal words the catalog's refusal of a run for a WaxDeck
// operator: the catalog's own names WAXBIN_ENRICH_CONTACT, a knob they do
// not have.
func (l *Library) explainEnrichRefusal(err error, forcePhases []string) error {
	if KindOf(classify(err)) != KindUnsupported {
		return classify(err)
	}
	var msg string
	switch {
	case len(forcePhases) > 0:
		// Every phase passed the mirror above, so the mirror drifted.
		l.log.Warn("enrichment: the catalog refused a forced phase this server lists", "phases", forcePhases, "err", err)
		msg = "the catalog does not run " + strings.Join(forcePhases, ", ") + ", though this server lists it; its phase list is out of date"
	case l.sources.anyOff():
		msg = "this server has nothing for an enrichment pass to do: the " +
			"sources that could run are switched off. Switch one on, or set " +
			"-enrichment-contact (WAXDECK_ENRICHMENT_CONTACT) and restart"
	default:
		msg = "this server has nothing for an enrichment pass to do. " +
			"Set -enrichment-contact (WAXDECK_ENRICHMENT_CONTACT) to an email " +
			"or a URL, which is what MusicBrainz requires before anything is " +
			"sent and what the identity phases need, or configure a provider " +
			"that supplies artwork, lyrics, fields or book metadata; then restart"
	}
	return &Error{Kind: KindUnsupported, Msg: msg, Err: err}
}

// scheduledEnrichLimit caps one nightly pass. A first pass over a large
// library is hours of provider-paced lookups, so it is paid over nights
// rather than in one unattended run, and a limited pass bounds its tag
// write-back to what it looked up. An administrator's own run is
// uncapped: they are watching it.
const scheduledEnrichLimit = 2000

// RunScheduledEnrichment starts the nightly catalog pass. Non-forced,
// so entities already enriched are left alone, and capped; the job row
// carries the outcome the status surface reads.
func (l *Library) RunScheduledEnrichment(ctx context.Context) error {
	// A walk still running keeps its order, and the catalog refuses this.
	l.sources.apply(l.enrichPassRunning(ctx))
	pid, err := l.lib.StartEnrich(l.procCtx, waxbin.EnrichOptions{
		WriteTags: l.currentToggles().enrichWriteTags,
		Limit:     scheduledEnrichLimit,
	})
	if err != nil {
		return classify(err)
	}
	l.watchEnrichArtwork(pid)
	return nil
}

const (
	// enrichArtWatchInterval is how often the artwork watcher asks
	// whether the pass it is following has ended. A whole-library pass
	// runs for minutes to hours, so a slow poll costs nothing and the
	// only thing waiting on it is a mosaic rebuild.
	enrichArtWatchInterval = time.Minute
	// enrichArtWatchLimit bounds the watch, so a job row that never
	// reaches a terminal state does not leave a goroutine polling for
	// the life of the process.
	enrichArtWatchLimit = 12 * time.Hour
)

// watchEnrichArtwork bumps the artwork epoch once a pass that gathered
// pictures ends, so generated playlist covers re-composite: the catalog has
// no completion hook, so this follows the job row. Best effort.
func (l *Library) watchEnrichArtwork(jobPID model.PID) {
	l.workers.GoOnce(l.procCtx, "enrich-artwork-epoch", func(ctx context.Context) error {
		deadline := time.Now().Add(enrichArtWatchLimit)
		tick := time.NewTicker(cmp.Or(l.enrichWatchEvery, enrichArtWatchInterval))
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
			}
			job, err := l.lib.Job(ctx, jobPID)
			if err != nil || job == nil {
				return nil
			}
			if job.State == model.JobRunning {
				if time.Now().After(deadline) {
					l.log.Warn("enrichment artwork epoch: gave up waiting on the pass", "job", string(jobPID))
					return nil
				}
				continue
			}
			var res enrich.Result
			if job.Result == "" || json.Unmarshal([]byte(job.Result), &res) != nil {
				return nil
			}
			if res.ArtFetched > 0 || res.AuxArtFetched > 0 {
				l.noteArtworkChanged(ctx)
			}
			return nil
		}
	})
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
	// They run on the proposal path too, for a want the proposal left
	// unmet, or every install whose only sources are the built-ins would
	// regress.
	l.enrichItemCatalogPass(ctx, it, wants, &applied, &skipped)
	return applied, skipped, nil
}

// enrichItemCatalogPass runs the catalog's own pass over the item for the unmet
// wants a built-in serves, which reaches the built-ins the injected port cannot.
// That pass asks every provider about every entity the item belongs to, so it
// runs only while a want is still unmet: a met one would buy nothing but the
// pass's other fills, such as the release group's front, a picture its album
// and every sibling show. Who filled an artifact is read back from provenance.
func (l *Library) enrichItemCatalogPass(ctx context.Context, it *model.ItemView, wants []string, applied, skipped *[]string) {
	var builtinWants []string
	for _, w := range wants {
		if _, ok := builtinFor(w); ok && !l.artifactPresent(ctx, it, w) {
			builtinWants = append(builtinWants, w)
		}
	}
	if len(builtinWants) == 0 {
		return
	}
	// Item-scoped, fill-when-empty: the engine enriches this item's own
	// entities and never overwrites, so a provider only fills real gaps. It
	// runs synchronously under the engine's shared enrich lease.
	l.sources.apply(l.enrichPassRunning(ctx))
	_, err := l.lib.Enrich(ctx, waxbin.EnrichOptions{ItemPID: it.PID})
	if err != nil {
		if KindOf(classify(err)) == KindConflict {
			// A concurrent enrich (a whole-catalog pass, or another fetch)
			// holds the lease: the unmet wants read as deferred, not a false
			// success, so the user knows to retry them.
			for _, w := range builtinWants {
				*skipped = append(*skipped, w+": enrichment is busy; try again")
			}
			return
		}
		l.log.Warn("enrich: item catalog pass", "item", it.PID, "err", err)
		return
	}
	for _, w := range builtinWants {
		if !l.artifactPresent(ctx, it, w) {
			continue
		}
		name, _ := builtinFor(w)
		*applied = append(*applied, w+": "+cmp.Or(l.artifactProvider(ctx, it, w), name))
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

// artifactProvider names who filled the item's artifact, from the
// catalog's own provenance: the pass asks every provider, not only the
// built-in a want is named after.
func (l *Library) artifactProvider(ctx context.Context, it *model.ItemView, want string) string {
	switch want {
	case enrichWantCover:
		ref := model.EntityRef{Type: model.ArtTrack, PID: it.PID}
		if it.Kind == model.KindEpisode {
			ref.Type = model.ArtEpisode
		}
		if prov, err := l.lib.ArtProvenance(ctx, ref, model.ArtRoleFront); err == nil {
			return prov.Provider
		}
	case enrichWantLyrics:
		if ly, err := l.lib.Lyrics(ctx, it.PID); err == nil {
			return ly.Provider
		}
	case enrichWantGenres:
		if rows, err := l.lib.Provenance(ctx, it.PID); err == nil {
			for _, r := range rows {
				if r.Field == "genre" {
					return r.Provider
				}
			}
		}
	}
	return ""
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
		case enrichWantCover, enrichWantLyrics, enrichWantGenres, enrichWantBook, enrichWantFields:
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
		case enrichWantFields:
			var ps []EnrichFieldProposalDTO
			ps, s = l.proposeFields(ctx, st.it, st.locked)
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
	case "bpm", "isrc", "composer":
		return enrichWantFields
	case "narrator", "publisher", "description", "year", "subtitle", "edition", "asin", "isbn":
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
	enabled := map[string]bool{}
	for _, p := range l.sources.live() {
		enabled[p.Name()] = true
	}
	// A registered source the operator switched off is called that.
	unusable := func(what, name string) error {
		if l.sources.provider(name) != nil {
			return errInvalid(what + " " + name + " is switched off on this server")
		}
		return errInvalid(what + " " + name + " is not registered on this server")
	}
	if c := proposal.Cover; c != nil {
		if !wanted[enrichWantCover] {
			return errInvalid("the proposal carries a cover the request does not want")
		}
		if !enabled[c.Provider] {
			return unusable("cover provider", c.Provider)
		}
		if err := validateArtworkBytes(c.Data); err != nil {
			// One kind for the caller: a format refusal here is a bad
			// proposal, not an unsupported upload.
			return errInvalid("cover proposal: " + err.Error())
		}
	}
	// The book want commits as one edit, so its rows have to agree on a
	// provider - the shape an honest propose produces, and what keeps
	// the commit from half-failing into a response that says nothing
	// landed. The fields want does not: it merges per key across
	// providers the way the catalog's own walk does, and commits one
	// edit per provider.
	bookProvider := ""
	for _, f := range proposal.Fields {
		w := enrichWantForField(f.Name)
		if w == "" {
			return errInvalid("field " + f.Name + " is not one enrichment proposes")
		}
		if !wanted[w] {
			return errInvalid("the proposal fills " + f.Name + ", which the request does not want")
		}
		if !enabled[f.Provider] {
			return unusable("provider", f.Provider)
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
	// Routed on the want each field belongs to, which enrichWantForField
	// already owns: a second list of names here would let a field added
	// there validate, preview, and then fall through to the wrong
	// committer, where it would be dropped without a word.
	byWant := map[string][]EnrichFieldProposalDTO{}
	for _, f := range proposal.Fields {
		byWant[enrichWantForField(f.Name)] = append(byWant[enrichWantForField(f.Name)], f)
	}
	for _, f := range byWant[enrichWantGenres] {
		record(l.commitGenres(ctx, st.it, f, st.locked))
	}
	for _, f := range byWant[enrichWantLyrics] {
		record(l.commitLyrics(ctx, st.it, f, st.locked))
	}
	if fields := byWant[enrichWantFields]; len(fields) > 0 {
		record(l.commitFields(ctx, st.it, fields, st.locked))
	}
	if books := byWant[enrichWantBook]; len(books) > 0 {
		record(l.commitBook(ctx, st.it, books, st.locked))
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

// enrichProvidersWith returns the enabled providers advertising the
// wanted capability, in the operator's order.
func (l *Library) enrichProvidersWith(want enrich.Capability) []enrich.Provider {
	var out []enrich.Provider
	for _, p := range l.sources.live() {
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
		cand, err := enrichAsk(ctx, p, req, enrich.CapCover)
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
		cand, err := enrichAsk(ctx, p, req, enrich.CapGenres)
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
		cand, err := enrichAsk(ctx, p, req, enrich.CapLyrics)
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

// fieldsGuard is the track-fields want's kind precondition. The walk's
// fill set is a track's (tempo, ISRC, composer); a book's own scalars
// are the book want's, and an episode has neither.
func fieldsGuard(it *model.ItemView) (skippedEntry string) {
	if it.Kind != model.KindTrack {
		return "fields: not a track"
	}
	return ""
}

// trackFieldFillable reports whether one track scalar is still honestly
// fillable: empty now and not locked. The set is upstream's own
// EnrichFillFields(KindTrack), restated because the catalog's walk
// applies it server-side and this is the per-item mirror of it.
func trackFieldFillable(name string, it *model.ItemView, locked map[string]bool) bool {
	if locked[name] {
		return false
	}
	switch name {
	case "bpm":
		return it.BPM == 0
	case "isrc":
		return it.ISRC == ""
	case "composer":
		return it.Composer == ""
	}
	return false
}

// trackValueValid rejects a value the catalog would refuse on write.
//
// This matters more here than on the catalog's own walk. That walk
// validates key by key and drops the failures with a warning; the
// per-item commit hands the whole map to one edit, which the catalog
// fails whole - so one bad number would cost the proposal's other
// fields, and the user would see "could not be stored" after approving
// a sheet that showed them.
func trackValueValid(name, value string) bool {
	if name != "bpm" {
		return true
	}
	// Whole numbers only, which is what the catalog stores and what its
	// edit path accepts: it refuses "120.5" rather than rounding a value
	// nobody typed. A provider whose source is fractional rounds it
	// before it gets here (Deezer does), so this only drops one that
	// did not.
	n, err := strconv.Atoi(value)
	return err == nil && n > 0 && n <= model.MaxBPM
}

// proposeFields asks the fields providers for a track's tempo, ISRC and
// composer, and returns the fill-when-empty edits as one proposal row
// per field, writing nothing.
//
// The first answer per key across every capable provider, rather than
// one provider's whole answer: that is what the catalog's own
// track-fields walk does, and the editor's Fetch is meant to offer what
// a nightly pass would fill. Two providers commonly split the set -
// one knows a tempo, another a composer - and stopping at the first
// would leave the second's field for the nightly pass to find later.
// The walk stops early for the same reason upstream's does: once every
// fillable key is answered there is nothing left to ask about.
func (l *Library) proposeFields(ctx context.Context, it *model.ItemView, locked map[string]bool) (proposals []EnrichFieldProposalDTO, skippedEntry string) {
	if s := fieldsGuard(it); s != "" {
		return nil, s
	}
	providers := l.enrichProvidersWith(enrich.CapFields)
	if len(providers) == 0 {
		return nil, "fields: no provider"
	}
	fillable := 0
	for name := range model.EnrichFillFields(model.KindTrack) {
		if trackFieldFillable(name, it, locked) {
			fillable++
		}
	}
	if fillable == 0 {
		return nil, "fields: nothing new to fill"
	}
	req := enrich.Request{
		Type:        enrich.TargetRecording,
		Title:       it.Title,
		Artist:      it.Artist,
		Album:       it.Album,
		MBID:        it.MBID,
		ISRC:        it.ISRC,
		DurationSec: int(it.DurationMS / 1000),
	}
	answered := false
	edits := map[string]EnrichFieldProposalDTO{}
	for _, p := range providers {
		cand, err := enrichAsk(ctx, p, req, enrich.CapFields)
		if err != nil {
			l.log.Warn("enrich: fields provider", "provider", p.Name(), "err", err)
			continue
		}
		if cand == nil {
			continue
		}
		answered = true
		for name, value := range cand.Fields {
			if value == "" || edits[name].Proposed != "" || !trackFieldFillable(name, it, locked) {
				continue
			}
			if !trackValueValid(name, value) {
				l.log.Debug("enrich: skipping malformed provider value",
					"provider", p.Name(), "item", it.PID, "field", name, "value", value)
				continue
			}
			edits[name] = EnrichFieldProposalDTO{Name: name, Proposed: value, Provider: p.Name()}
		}
		if len(edits) == fillable {
			break
		}
	}
	if len(edits) == 0 {
		if answered {
			return nil, "fields: nothing new to fill"
		}
		return nil, "fields: no provider hit"
	}
	names := make([]string, 0, len(edits))
	for name := range edits {
		names = append(names, name)
	}
	sort.Strings(names)
	out := make([]EnrichFieldProposalDTO, 0, len(edits))
	for _, name := range names {
		out = append(out, edits[name])
	}
	return out, ""
}

// commitFields writes proposed track fields, re-filtered through the
// fill-when-empty rules. One edit per provider named in the proposal,
// so each field carries the provenance the sheet showed for it: the
// propose half merges per key across providers, so the rows here are
// not all one provider's the way the book want's are.
func (l *Library) commitFields(ctx context.Context, it *model.ItemView, proposals []EnrichFieldProposalDTO, locked map[string]bool) (appliedEntry, skippedEntry string) {
	if s := fieldsGuard(it); s != "" {
		return "", s
	}
	byProvider := map[string]map[string]string{}
	for _, p := range proposals {
		if p.Proposed == "" || !trackFieldFillable(p.Name, it, locked) || !trackValueValid(p.Name, p.Proposed) {
			continue
		}
		if byProvider[p.Provider] == nil {
			byProvider[p.Provider] = map[string]string{}
		}
		byProvider[p.Provider][p.Name] = p.Proposed
	}
	if len(byProvider) == 0 {
		return "", "fields: nothing new to fill"
	}
	names := make([]string, 0, len(byProvider))
	for provider := range byProvider {
		names = append(names, provider)
	}
	sort.Strings(names)
	var applied []string
	for _, provider := range names {
		if err := l.lib.EditFields(ctx, it.PID, byProvider[provider], waxbin.EditOptions{
			Source: model.SourceEnrichment, Provider: provider, Lock: model.LockUnchanged,
		}); err != nil {
			// One provider's edit failing leaves the others standing:
			// they are separate writes of separate fields, and taking
			// the whole want down would lose values that did land.
			l.log.Warn("enrich: applying track fields", "provider", provider, "item", it.PID, "err", err)
			continue
		}
		applied = append(applied, provider)
	}
	if len(applied) == 0 {
		return "", "fields: could not be stored"
	}
	return "fields: " + strings.Join(applied, ", "), ""
}

// bookGuard is the book want's kind precondition, shared by the
// propose and commit halves. The identifier requirement lives with
// each half's detail read, which is where the ISBN is known: the
// providers key on an ASIN or an ISBN (Hardcover bridges the first to
// the second, committed one pass and keyed the next).
func bookGuard(it *model.ItemView) (skippedEntry string) {
	if it.Kind != model.KindBook {
		return "book: not an audiobook"
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
	if it.ASIN == "" && detail.ISBN == "" {
		return nil, "book: book metadata needs an ASIN or an ISBN"
	}
	req := enrich.Request{
		Type:   enrich.TargetBook,
		Title:  it.Title,
		Artist: it.Artist,
		ASIN:   it.ASIN,
		ISBN:   detail.ISBN,
	}
	answered := false
	for _, p := range providers {
		cand, err := enrichAsk(ctx, p, req, enrich.CapBookMeta)
		if err != nil {
			l.log.Warn("enrich: book provider", "provider", p.Name(), "err", err)
			continue
		}
		if cand == nil {
			continue
		}
		answered = true
		edits, skipped := bookEnrichEdits(cand, detail, it, locked)
		for field, val := range skipped {
			l.log.Debug("enrich: skipping malformed provider value", "provider", p.Name(), "item", it.PID, "field", field, "value", val)
		}
		if len(edits) == 0 {
			// Nothing this provider offers is honestly fillable - its
			// values are malformed, or name only fields the item already
			// holds. The ladder's providers answer different fields, so
			// the next one may still hold something new; ending the pass
			// here (which the single-provider era did) would silence the
			// rest of the ladder.
			continue
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
	if answered {
		return nil, "book: nothing new to fill"
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
	// The same identifier precondition the propose half enforces. The
	// commit writes client-supplied values, so without this an item no
	// provider could ever have been asked about would still take a
	// proposal stamped with that provider's provenance.
	if it.ASIN == "" && detail.ISBN == "" {
		return "", "book: book metadata needs an ASIN or an ISBN"
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
	case "asin":
		return detail.ASIN == ""
	case "narrator":
		return it.Narrator == ""
	case "description":
		return detail.Description == ""
	case "subtitle":
		return detail.Subtitle == ""
	case "edition":
		return detail.Edition == ""
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
	case "asin":
		return validASIN(value)
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
	consider("asin", cand.ASIN)
	// Generic curated fields ride Candidate.Fields. The accepted set is
	// upstream's own EnrichFillFields(KindBook) minus the two with
	// dedicated slots above, so the per-item fetch fills exactly what
	// the catalog's book walk would.
	for k, v := range cand.Fields {
		switch k {
		case "narrator", "description", "year", "subtitle", "edition", "asin":
			consider(k, v)
		}
	}
	return edits, skipped
}
