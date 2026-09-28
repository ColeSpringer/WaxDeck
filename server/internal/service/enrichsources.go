package service

// Operator control over the enrichment sources: an order and a switch per
// injected provider. The catalog takes its providers once at open, so it gets
// one fixed slot per rank, each answering for whoever holds that rank now.

import (
	"cmp"
	"context"
	"encoding/json"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/colespringer/waxbin/enrich"
)

// EnrichmentSource is one provider's place in the operator's order,
// saved as JSON under these names.
type EnrichmentSource struct {
	Name    string `json:"name"`
	Enabled bool   `json:"enabled"`
}

const settingEnrichmentSources = "enrichment:sources"

// enrichSources is the injected providers in boot order, the operator's
// saved order over them, and the order the catalog's slots answer by, which
// takes the saved one only while no walk runs: a walk keeps its order.
type enrichSources struct {
	registered []enrich.Provider
	// mu orders a save, a load and an apply against one another.
	mu      sync.Mutex
	stored  atomic.Pointer[[]EnrichmentSource]
	applied atomic.Pointer[[]enrich.Provider]
	waiting atomic.Bool
}

func newEnrichSources(registered []enrich.Provider) *enrichSources {
	return &enrichSources{registered: registered}
}

func (s *enrichSources) setStored(list []EnrichmentSource) {
	s.stored.Store(&list)
}

// resolved is every registered provider: the saved order first (names no
// longer registered dropped), then the rest in boot order, enabled.
func (s *enrichSources) resolved() []EnrichmentSource {
	out := make([]EnrichmentSource, 0, len(s.registered))
	placed := map[string]bool{}
	if saved := s.stored.Load(); saved != nil {
		for _, src := range *saved {
			if s.provider(src.Name) != nil && !placed[src.Name] {
				out = append(out, src)
				placed[src.Name] = true
			}
		}
	}
	for _, p := range s.registered {
		if !placed[p.Name()] {
			out = append(out, EnrichmentSource{Name: p.Name(), Enabled: true})
		}
	}
	return out
}

// anyOff reports an injected provider the operator switched off.
func (s *enrichSources) anyOff() bool {
	return slices.ContainsFunc(s.resolved(), func(src EnrichmentSource) bool { return !src.Enabled })
}

func (s *enrichSources) provider(name string) enrich.Provider {
	for _, p := range s.registered {
		if p.Name() == name {
			return p
		}
	}
	return nil
}

// live is the enabled providers in the operator's order.
func (s *enrichSources) live() []enrich.Provider {
	var out []enrich.Provider
	for _, src := range s.resolved() {
		if src.Enabled {
			out = append(out, s.provider(src.Name))
		}
	}
	return out
}

// forCatalog is the order the catalog's slots answer by.
func (s *enrichSources) forCatalog() []enrich.Provider {
	if a := s.applied.Load(); a != nil {
		return *a
	}
	return s.live()
}

// apply puts the saved order in effect unless a walk is running, and
// reports whether it did.
func (s *enrichSources) apply(running func() bool) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if running() {
		return false
	}
	order := s.live()
	s.applied.Store(&order)
	return true
}

// slots are what the catalog is given: one per registered provider.
func (s *enrichSources) slots() []enrich.Provider {
	out := make([]enrich.Provider, len(s.registered))
	for i := range out {
		out[i] = sourceSlot{rank: i, sources: s}
	}
	return out
}

// sourceSlot answers for the provider at its rank. An empty rank (a
// provider switched off) keeps a name, since the catalog drops nameless
// providers at open, and supplies nothing.
type sourceSlot struct {
	rank    int
	sources *enrichSources
}

func (s sourceSlot) current() enrich.Provider {
	if order := s.sources.forCatalog(); s.rank < len(order) {
		return order[s.rank]
	}
	return nil
}

func (s sourceSlot) Name() string {
	if p := s.current(); p != nil {
		return p.Name()
	}
	return "slot-" + strconv.Itoa(s.rank)
}

func (s sourceSlot) Capabilities() enrich.Capability {
	if p := s.current(); p != nil {
		return p.Capabilities()
	}
	return 0
}

func (s sourceSlot) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if p := s.current(); p != nil {
		return p.Enrich(ctx, req)
	}
	return nil, nil
}

// loadEnrichSources reads the saved order; the first load, before any
// walk, puts it in effect.
func (l *Library) loadEnrichSources(ctx context.Context) {
	l.sources.mu.Lock()
	defer l.sources.mu.Unlock()
	if raw, err := l.db.SettingGet(ctx, settingEnrichmentSources); err == nil {
		var list []EnrichmentSource
		if json.Unmarshal([]byte(raw), &list) == nil {
			l.sources.setStored(list)
		}
	}
	if l.sources.applied.Load() == nil {
		order := l.sources.live()
		l.sources.applied.Store(&order)
	}
}

// enrichPassRunning answers whether an enrich job is in flight, whoever
// started it (the IPC socket's included); a read that fails answers yes.
func (l *Library) enrichPassRunning(ctx context.Context) func() bool {
	return func() bool {
		_, running, err := l.runningJob(ctx, "enrich", enrichJobWindow)
		return err != nil || running
	}
}

// applyEnrichSources puts the saved order in effect now, or, while a walk
// runs, once none does; a walk started here applies it first anyway.
func (l *Library) applyEnrichSources() {
	if l.sources.apply(l.enrichPassRunning(l.procCtx)) || !l.sources.waiting.CompareAndSwap(false, true) {
		return
	}
	started := l.workers.GoOnce(l.procCtx, "enrich-sources-apply", func(ctx context.Context) error {
		defer l.sources.waiting.Store(false)
		deadline := time.Now().Add(enrichArtWatchLimit)
		tick := time.NewTicker(cmp.Or(l.enrichWatchEvery, enrichArtWatchInterval))
		defer tick.Stop()
		for time.Now().Before(deadline) {
			select {
			case <-ctx.Done():
				return nil
			case <-tick.C:
			}
			if l.sources.apply(l.enrichPassRunning(ctx)) {
				return nil
			}
		}
		return nil
	})
	if !started {
		l.sources.waiting.Store(false)
	}
}

// PutEnrichmentSources saves the operator's order and switches, answering
// the status it leaves. The list names every orderable provider once; one
// not wired now keeps its saved switch.
func (l *Library) PutEnrichmentSources(ctx context.Context, uc *UserCtx, list []EnrichmentSource) (EnrichmentStatusDTO, error) {
	if !uc.Admin {
		return EnrichmentStatusDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	seen := map[string]bool{}
	for _, src := range list {
		switch {
		case slices.ContainsFunc(catalogBuiltins, func(b catalogBuiltin) bool { return b.name == src.Name }):
			return EnrichmentStatusDTO{}, errInvalid(src.Name + " is one of the catalog's own sources and cannot be reordered")
		case l.sources.provider(src.Name) == nil:
			return EnrichmentStatusDTO{}, errInvalid("no enrichment source named " + strconv.Quote(src.Name))
		case seen[src.Name]:
			return EnrichmentStatusDTO{}, errInvalid(src.Name + " is listed twice")
		}
		seen[src.Name] = true
	}
	var missing []string
	for _, p := range l.sources.registered {
		if !seen[p.Name()] {
			missing = append(missing, p.Name())
		}
	}
	if len(missing) > 0 {
		return EnrichmentStatusDTO{}, errInvalid("the order must name every source; missing " + strings.Join(missing, ", "))
	}
	// Read first, so a status that cannot be answered saves nothing.
	st, err := l.EnrichmentStatusFor(ctx, uc)
	if err != nil {
		return EnrichmentStatusDTO{}, err
	}
	if err := l.saveEnrichSources(ctx, list); err != nil {
		return EnrichmentStatusDTO{}, err
	}
	l.applyEnrichSources()
	l.Audit(ctx, uc, "enrichment.sources", AuditTarget{Kind: "settings"}, map[string]any{"sources": list})
	l.fillEnrichmentRoster(&st)
	return st, nil
}

// saveEnrichSources stores list, keeping the saved entries of providers
// not wired now so each comes back as it was left.
func (l *Library) saveEnrichSources(ctx context.Context, list []EnrichmentSource) error {
	l.sources.mu.Lock()
	defer l.sources.mu.Unlock()
	saved := slices.Clone(list)
	if prev := l.sources.stored.Load(); prev != nil {
		for _, src := range *prev {
			if l.sources.provider(src.Name) == nil {
				saved = append(saved, src)
			}
		}
	}
	raw, err := json.Marshal(saved)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.SettingSet(ctx, settingEnrichmentSources, string(raw), time.Now().UnixNano()); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	l.sources.setStored(saved)
	return nil
}
