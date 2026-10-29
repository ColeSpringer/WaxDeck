package api

import (
	"context"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// The catalog check and its repair.

func (s *Server) GetCatalogConsistency(ctx context.Context, _ GetCatalogConsistencyRequestObject) (GetCatalogConsistencyResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return GetCatalogConsistency403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	rep, err := s.svc.CatalogConsistency(ctx, uc)
	if err != nil {
		return nil, err
	}
	return GetCatalogConsistency200JSONResponse(catalogConsistencyJSON(rep)), nil
}

func catalogConsistencyJSON(c service.CatalogConsistencyDTO) CatalogConsistency {
	return CatalogConsistency{
		ItemsMissingFromSearch:  c.ItemsMissingFromSearch,
		OrphanSearchRows:        c.OrphanSearchRows,
		ArtistRollupDrift:       c.ArtistRollupDrift,
		GenreRollupDrift:        c.GenreRollupDrift,
		ReleaseGroupRollupDrift: c.ReleaseGroupRollupDrift,
		SortKeyDrift:            c.SortKeyDrift,
		BookDurationDrift:       c.BookDurationDrift,
		BookIsbnKeyDrift:        c.BookISBNKeyDrift,
		AlbumYearDrift:          c.AlbumYearDrift,
		ReleaseYearDrift:        c.ReleaseYearDrift,
		PlaylistPositionDrift:   c.PlaylistPositionDrift,
		OrphanArtSources:        c.OrphanArtSources,
		OrphanThumbnails:        c.OrphanThumbnails,
		OrphanTagProvenance:     c.OrphanTagProvenance,
		StrandedTagRows:         c.StrandedTagRows,
		Consistent:              c.Consistent,
		Reclaimable:             c.Reclaimable,
	}
}

func (s *Server) RepairCatalog(ctx context.Context, _ RepairCatalogRequestObject) (RepairCatalogResponseObject, error) {
	uc, p, err := s.requireUserCtx(ctx)
	if err != nil {
		return nil, err
	}
	if !p.IsAdmin() {
		return RepairCatalog403JSONResponse{ForbiddenJSONResponse(errObj("forbidden", "administrators only"))}, nil
	}
	task, err := s.svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		if service.KindOf(err) == service.KindConflict {
			return RepairCatalog409JSONResponse(toolRefusalObj(err)), nil
		}
		return nil, err
	}
	return RepairCatalog202JSONResponse(toolTaskJSON(task)), nil
}
