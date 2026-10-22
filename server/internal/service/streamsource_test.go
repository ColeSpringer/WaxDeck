package service

import (
	"errors"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
)

// A stream asked for while the catalog is handed off says so in the
// engine's own terms, so the engine can tell a listener to retry rather
// than that the item is gone.
func TestAStreamDuringAHandOffNamesTheCatalog(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _ := openServiceAt(t, t.TempDir(), nil)
	if err := svc.lib.BeginMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	_, err := svc.StreamSource(ctx, "tr-01JZX5N8QW3F4V9T2B7KD3M9R6", "")
	if KindOf(err) != KindMaintenance || !errors.Is(err, flow.ErrCatalogMaintenance) {
		t.Errorf("a stream during a hand-off = %v (%s), want the catalog named as away", err, KindOf(err))
	}
	if err := svc.lib.EndMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.StreamSource(ctx, "tr-01JZX5N8QW3F4V9T2B7KD3M9R6", ""); errors.Is(err, flow.ErrCatalogMaintenance) {
		t.Errorf("a missing item after the hand-off = %v, want it simply missing", err)
	}
}
