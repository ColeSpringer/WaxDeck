package service

// Operator control over the enrichment sources: an order and a switch per
// source, the catalog's key-free built-ins included. The catalog asks for
// the list at the start of every pass, so a save applies to the next one.

import (
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

// enrichSources is the injected providers in boot order, the built-ins the
// catalog registered, and the operator's saved order over both.
type enrichSources struct {
	registered []enrich.Provider
	// builtins is set once after the catalog opens.
	builtins []enrich.Provider
	// mu orders a save and a load against one another.
	mu     sync.Mutex
	stored atomic.Pointer[[]EnrichmentSource]
}

func newEnrichSources(registered []enrich.Provider) *enrichSources {
	return &enrichSources{registered: registered}
}

func (s *enrichSources) setStored(list []EnrichmentSource) {
	s.stored.Store(&list)
}

func (s *enrichSources) saved() []EnrichmentSource {
	if p := s.stored.Load(); p != nil {
		return *p
	}
	return nil
}

// injected is what the catalog is given as its own providers.
func (s *enrichSources) injected() []enrich.Provider { return s.registered }

// providerList is the catalog's hook: the saved order's enabled entries
// found in fixed, then every provider in fixed the order does not name,
// switched on, so nothing new or upgraded-into is left off unasked.
func (s *enrichSources) providerList(fixed []enrich.Provider) []enrich.Provider {
	saved := s.saved()
	out := make([]enrich.Provider, 0, len(fixed))
	for _, src := range saved {
		if i := indexNamed(fixed, src.Name); i >= 0 && src.Enabled {
			out = append(out, fixed[i])
		}
	}
	for _, p := range fixed {
		if !slices.ContainsFunc(saved, func(src EnrichmentSource) bool { return src.Name == p.Name() }) {
			out = append(out, p)
		}
	}
	return out
}

func indexNamed(ps []enrich.Provider, name string) int {
	return slices.IndexFunc(ps, func(p enrich.Provider) bool { return p.Name() == name })
}

// offered is every orderable name: the injected providers in boot order,
// then the built-ins in the catalog's.
func (s *enrichSources) offered() []string {
	out := make([]string, 0, len(s.registered)+len(catalogBuiltins))
	for _, p := range s.registered {
		out = append(out, p.Name())
	}
	for _, b := range catalogBuiltins {
		out = append(out, b.name)
	}
	return out
}

// resolved is every orderable source: the saved order first (names not
// offered now dropped), then the rest in offered order, enabled.
func (s *enrichSources) resolved() []EnrichmentSource {
	offered := s.offered()
	out := make([]EnrichmentSource, 0, len(offered))
	placed := map[string]bool{}
	for _, src := range s.saved() {
		if slices.Contains(offered, src.Name) && !placed[src.Name] {
			out = append(out, src)
			placed[src.Name] = true
		}
	}
	for _, name := range offered {
		if !placed[name] {
			out = append(out, EnrichmentSource{Name: name, Enabled: true})
		}
	}
	return out
}

func (s *enrichSources) provider(name string) enrich.Provider {
	if i := indexNamed(s.registered, name); i >= 0 {
		return s.registered[i]
	}
	return nil
}

// builtin is the catalog's registered built-in under name, or nil.
func (s *enrichSources) builtin(name string) enrich.Provider {
	if i := indexNamed(s.builtins, name); i >= 0 {
		return s.builtins[i]
	}
	return nil
}

// builtinWired reports whether the catalog registered the built-in.
func (s *enrichSources) builtinWired(name string) bool { return s.builtin(name) != nil }

// live is the enabled injected providers in the operator's order.
func (s *enrichSources) live() []enrich.Provider {
	var out []enrich.Provider
	for _, src := range s.resolved() {
		if p := s.provider(src.Name); p != nil && src.Enabled {
			out = append(out, p)
		}
	}
	return out
}

// loadEnrichSources reads the saved order.
func (l *Library) loadEnrichSources(ctx context.Context) {
	l.sources.mu.Lock()
	defer l.sources.mu.Unlock()
	if raw, err := l.db.SettingGet(ctx, settingEnrichmentSources); err == nil {
		var list []EnrichmentSource
		if json.Unmarshal([]byte(raw), &list) == nil {
			l.sources.setStored(list)
		}
	}
}

// PutEnrichmentSources saves the operator's order and switches, answering
// the status it leaves. The list names every injected provider once and
// may name the built-ins; one not wired now keeps its saved switch.
func (l *Library) PutEnrichmentSources(ctx context.Context, uc *UserCtx, list []EnrichmentSource) (EnrichmentStatusDTO, error) {
	if !uc.Admin {
		return EnrichmentStatusDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	offered := l.sources.offered()
	seen := map[string]bool{}
	for _, src := range list {
		switch {
		case !slices.Contains(offered, src.Name):
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
		return EnrichmentStatusDTO{}, errInvalid("the order must name every provider this server adds; missing " + strings.Join(missing, ", "))
	}
	// Read first, so a status that cannot be answered saves nothing.
	st, err := l.enrichmentProgress(ctx)
	if err != nil {
		return EnrichmentStatusDTO{}, err
	}
	if err := l.saveEnrichSources(ctx, list); err != nil {
		return EnrichmentStatusDTO{}, err
	}
	l.Audit(ctx, uc, "enrichment.sources", AuditTarget{Kind: "settings"}, map[string]any{"sources": list})
	l.fillEnrichmentRoster(&st)
	return st, nil
}

// saveEnrichSources stores list, keeping the saved entries of sources not
// wired now that it leaves out, so each comes back as it was left.
func (l *Library) saveEnrichSources(ctx context.Context, list []EnrichmentSource) error {
	l.sources.mu.Lock()
	defer l.sources.mu.Unlock()
	saved := slices.Clone(list)
	for _, src := range l.sources.saved() {
		named := slices.ContainsFunc(list, func(e EnrichmentSource) bool { return e.Name == src.Name })
		if !named && l.sources.provider(src.Name) == nil && !l.sources.builtinWired(src.Name) {
			saved = append(saved, src)
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
