package service

import (
	"context"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// The enrichment response cache's admin surface, the thumbnail pair's
// twin. A pruned answer costs one request the next time its target is
// re-asked, never a catalog value.

// EnrichCacheDTO censuses the enrichment response cache.
type EnrichCacheDTO struct {
	Rows  int
	Bytes int64
	// Unix nanoseconds; meaningful only when Rows is nonzero.
	OldestAtNS, NewestAtNS int64
	Kinds                  []EnrichCacheKindDTO // largest first
	// The share a prune leaves alone, counted in Rows and Bytes too.
	ExemptRows  int
	ExemptBytes int64
}

// EnrichCacheKindDTO is one request kind's share of the cache.
type EnrichCacheKindDTO struct {
	Kind   string
	Rows   int
	Bytes  int64
	Exempt bool
}

// EnrichCachePruneDTO reports what a prune dropped.
type EnrichCachePruneDTO struct {
	Removed    int
	FreedBytes int64
}

// EnrichmentCacheStats censuses the enrichment response cache.
// Administrators only.
func (l *Library) EnrichmentCacheStats(ctx context.Context, uc *UserCtx) (EnrichCacheDTO, error) {
	if !uc.Admin {
		return EnrichCacheDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	rep, err := l.lib.EnrichmentCacheStats(ctx)
	if err != nil {
		return EnrichCacheDTO{}, classify(err)
	}
	return enrichCacheFrom(rep), nil
}

func enrichCacheFrom(rep *model.EnrichmentCacheReport) EnrichCacheDTO {
	out := EnrichCacheDTO{
		Rows: rep.Rows, Bytes: rep.Bytes,
		OldestAtNS: rep.OldestAt, NewestAtNS: rep.NewestAt,
		ExemptRows: rep.ExemptRows, ExemptBytes: rep.ExemptBytes,
	}
	for _, k := range rep.Kinds {
		out.Kinds = append(out.Kinds, EnrichCacheKindDTO{Kind: k.Kind, Rows: k.Rows, Bytes: k.Bytes, Exempt: k.Exempt})
	}
	return out
}

// PruneEnrichmentCache drops cached answers to fit the policy, with the
// thumbnail prune's bounds. Administrators only.
func (l *Library) PruneEnrichmentCache(ctx context.Context, uc *UserCtx, olderThanSeconds, maxBytes *int64) (EnrichCachePruneDTO, error) {
	if !uc.Admin {
		return EnrichCachePruneDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	age, budget, err := prunePolicy(olderThanSeconds, maxBytes)
	if err != nil {
		return EnrichCachePruneDTO{}, err
	}
	removed, freed, err := l.lib.PruneEnrichmentCache(ctx, waxbin.EnrichmentCachePrunePolicy{OlderThan: age, MaxBytes: budget})
	if err != nil {
		return EnrichCachePruneDTO{}, classify(err)
	}
	l.Audit(ctx, uc, "enrichment-cache.prune", AuditTarget{Kind: "enrichment-cache"},
		pruneAuditDetail(removed, freed, olderThanSeconds, maxBytes))
	return EnrichCachePruneDTO{Removed: removed, FreedBytes: freed}, nil
}
