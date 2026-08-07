package service

// Enrichment: provider status, the whole-library catalog pass, and the
// synchronous per-item fetch shared by the editor's endpoint and the
// health fix queue.

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/colespringer/waxbin/read"

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

// EnrichItemFor is the API's per-item enrichment: resolve the item
// through visibility, then run the synchronous fetch.
func (l *Library) EnrichItemFor(ctx context.Context, uc *UserCtx, apiItemPID string, wants []string) (applied, skipped []string, err error) {
	if !l.CanCurateItem(ctx, uc, apiItemPID) {
		return nil, nil, &Error{Kind: KindForbidden, Msg: "administrators, or the user whose upload brought the item in"}
	}
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return nil, nil, err
	}
	applied, skipped, err = l.EnrichItemNow(ctx, it.PID, wants)
	if err != nil {
		return applied, skipped, err
	}
	// The interactive button also runs the catalog's key-free built-ins
	// per item, which the injected-provider port cannot reach; the health
	// fixer calls EnrichItemNow one want at a time, so it stays on the
	// injected path rather than re-running the whole item-scoped pass.
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
		_, err := l.lib.ResolveArt(ctx, ref, model.ArtRoleFront, 0)
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
// "cover: reason".
func (l *Library) EnrichItemNow(ctx context.Context, pid model.PID, wants []string) (applied, skipped []string, err error) {
	applied, skipped = []string{}, []string{}
	for _, w := range wants {
		switch w {
		case enrichWantCover, enrichWantLyrics, enrichWantGenres, enrichWantBook:
		default:
			return nil, nil, errInvalid("unknown enrichment want " + w)
		}
	}
	it, err := l.lib.Get(ctx, pid)
	if err != nil {
		return nil, nil, classify(err)
	}

	// Unofficial content has no canonical release to enrich against.
	tags, err := l.lib.ItemTags(ctx, pid)
	if err != nil {
		return nil, nil, classify(err)
	}
	for _, t := range tags {
		if t.Key != releaseStatusKey {
			continue
		}
		for _, v := range t.Values {
			if v == releaseStatusUnofficial || v == releaseStatusBootleg {
				for _, w := range wants {
					skipped = append(skipped, w+": item is marked unofficial")
				}
				return applied, skipped, nil
			}
		}
	}

	locked := map[string]bool{}
	prov, err := l.lib.Provenance(ctx, pid)
	if err != nil {
		return nil, nil, classify(err)
	}
	for _, p := range prov {
		if p.Locked {
			locked[p.Field] = true
		}
	}

	for _, w := range wants {
		var a, s string
		switch w {
		case enrichWantCover:
			a, s = l.enrichCover(ctx, it, locked)
		case enrichWantGenres:
			a, s = l.enrichGenres(ctx, it, locked)
		case enrichWantLyrics:
			a, s = l.enrichLyrics(ctx, it, locked)
		case enrichWantBook:
			a, s = l.enrichBook(ctx, it, locked)
		}
		if a != "" {
			applied = append(applied, a)
		}
		if s != "" {
			skipped = append(skipped, s)
		}
	}
	return applied, skipped, nil
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

// enrichCover fetches and stores cover art for one item. Presence is
// judged through the art resolution chain, so an item already covered
// by its album's art is left alone.
func (l *Library) enrichCover(ctx context.Context, it *model.ItemView, locked map[string]bool) (appliedEntry, skippedEntry string) {
	if locked["art"] {
		return "", "cover: locked"
	}
	ref := model.EntityRef{Type: model.ArtTrack, PID: it.PID}
	if it.Kind == model.KindEpisode {
		ref.Type = model.ArtEpisode
	}
	if _, err := l.lib.ResolveArt(ctx, ref, model.ArtRoleFront, 0); err == nil {
		return "", "cover: already present"
	}
	providers := l.enrichProvidersWith(enrich.CapCover)
	if len(providers) == 0 {
		return "", "cover: no provider"
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
		if err := l.lib.SetItemArt(ctx, it.PID, model.ArtRoleFront, cand.Cover.Data, false, false, false); err != nil {
			l.log.Warn("enrich: applying cover", "provider", p.Name(), "item", it.PID, "err", err)
			continue
		}
		l.noteArtworkChanged(ctx)
		return "cover: " + p.Name(), ""
	}
	return "", "cover: no provider hit"
}

// enrichGenres fills the item's genre scalar from the first provider
// that answers, joining at most enrichGenreCap names.
func (l *Library) enrichGenres(ctx context.Context, it *model.ItemView, locked map[string]bool) (appliedEntry, skippedEntry string) {
	if locked["genre"] {
		return "", "genres: locked"
	}
	if it.Genre != "" {
		return "", "genres: already present"
	}
	providers := l.enrichProvidersWith(enrich.CapGenres)
	if len(providers) == 0 {
		return "", "genres: no provider"
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
		if err := l.lib.EditFields(ctx, it.PID,
			map[string]string{"genre": genre.Join(genres)},
			waxbin.EditOptions{}); err != nil {
			l.log.Warn("enrich: applying genres", "provider", p.Name(), "item", it.PID, "err", err)
			continue
		}
		return "genres: " + p.Name(), ""
	}
	return "", "genres: no provider hit"
}

// enrichLyrics fetches lyrics for a music item. The catalog's lrclib
// built-in is not on the injected-provider port, so with no registered
// lyrics provider the want reports "no provider" and the whole-library
// pass remains the way to fetch lyrics.
func (l *Library) enrichLyrics(ctx context.Context, it *model.ItemView, locked map[string]bool) (appliedEntry, skippedEntry string) {
	if it.Kind != model.KindTrack {
		return "", "lyrics: music only"
	}
	if locked["lyrics"] {
		return "", "lyrics: locked"
	}
	if ly, err := l.lib.Lyrics(ctx, it.PID); err == nil && ly.HasContent() {
		return "", "lyrics: already present"
	}
	providers := l.enrichProvidersWith(enrich.CapLyrics)
	if len(providers) == 0 {
		return "", "lyrics: no provider"
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
		if err := l.lib.SetLyrics(ctx, it.PID, cand.Lyrics, false, false); err != nil {
			l.log.Warn("enrich: applying lyrics", "provider", p.Name(), "item", it.PID, "err", err)
			continue
		}
		return "lyrics: " + p.Name(), ""
	}
	return "", "lyrics: no provider hit"
}

// enrichBook fills an audiobook's metadata (narrator, publisher,
// description, identifiers) fill-when-empty. Book providers key on the
// ASIN, so an item without one is skipped with the reason.
func (l *Library) enrichBook(ctx context.Context, it *model.ItemView, locked map[string]bool) (appliedEntry, skippedEntry string) {
	if it.Kind != model.KindBook {
		return "", "book: not an audiobook"
	}
	if it.ASIN == "" {
		return "", "book: book metadata needs an ASIN"
	}
	providers := l.enrichProvidersWith(enrich.CapBookMeta)
	if len(providers) == 0 {
		return "", "book: no provider"
	}
	detail, err := l.lib.Book(ctx, it.PID)
	if err != nil {
		l.log.Warn("enrich: reading book detail", "item", it.PID, "err", err)
		return "", "book: unreadable"
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
			return "", "book: nothing new to fill"
		}
		if err := l.lib.EditFields(ctx, it.PID, edits, waxbin.EditOptions{}); err != nil {
			l.log.Warn("enrich: applying book fields", "provider", p.Name(), "item", it.PID, "err", err)
			continue
		}
		return "book: " + p.Name(), ""
	}
	return "", "book: no provider hit"
}

// bookEnrichEdits maps a book provider candidate to the fill-when-empty edits it
// can honestly supply: only fields the item currently lacks and has not locked.
// A provider value that WaxBin would reject on write - a malformed ISBN or a
// non-numeric year - is dropped rather than added, because one bad value fails
// the whole edit and costs the provider's other fields. Dropped values are
// returned keyed by field so the caller can log them.
func bookEnrichEdits(cand *enrich.Candidate, detail *model.BookDetail, it *model.ItemView, locked map[string]bool) (edits, skipped map[string]string) {
	edits = map[string]string{}
	skipped = map[string]string{}
	if cand.Publisher != "" && detail.Publisher == "" && !locked["publisher"] {
		edits["publisher"] = cand.Publisher
	}
	if cand.ISBN != "" && detail.ISBN == "" && !locked["isbn"] {
		if validISBN(cand.ISBN) {
			edits["isbn"] = cand.ISBN
		} else {
			skipped["isbn"] = cand.ISBN
		}
	}
	// Generic curated fields ride Candidate.Fields; only the book
	// scalars this path can honestly fill-when-empty are accepted.
	for k, v := range cand.Fields {
		if v == "" || locked[k] {
			continue
		}
		switch k {
		case "narrator":
			if it.Narrator == "" {
				edits[k] = v
			}
		case "description":
			if detail.Description == "" {
				edits[k] = v
			}
		case "year":
			if it.Year != 0 {
				continue
			}
			if validYear(v) {
				edits[k] = v
			} else {
				skipped[k] = v
			}
		}
	}
	return edits, skipped
}
