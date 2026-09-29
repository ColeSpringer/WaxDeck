package service

import (
	"context"
	"log/slog"
	"path/filepath"
	"slices"
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
)

// openBareCatalog opens a catalog with no service around it.
func openBareCatalog(t *testing.T, opts waxbin.Options) *waxbin.Library {
	t.Helper()
	opts.DBPath = filepath.Join(t.TempDir(), "waxbin.db")
	opts.Logger = slog.New(slog.DiscardHandler)
	lib, err := waxbin.Open(context.Background(), opts)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { lib.Close() })
	return lib
}

// catalogKeeps reports whether the catalog keeps an injected lyrics
// provider under name, which opens the lyrics phase only if it does.
func catalogKeeps(t *testing.T, name string) bool {
	t.Helper()
	lib := openBareCatalog(t, waxbin.Options{
		EnrichmentProviders: []enrich.Provider{&enrich.Mock{ProviderName: name, Caps: enrich.CapLyrics}},
	})
	return slices.Contains(lib.EnrichmentPhases(), model.EnrichPhaseLyrics)
}

// Startup refuses a custom provider under a name the catalog would drop,
// so the list is checked against the catalog itself: it drops every name
// on the list, keeps one off it, and registers no built-in the list lacks.
func TestReservedEnrichNamesAreTheCatalogs(t *testing.T) {
	t.Parallel()
	for _, name := range ReservedEnrichNames {
		if catalogKeeps(t, name) {
			t.Errorf("the catalog keeps a provider named %q, which startup refuses", name)
		}
	}
	if !catalogKeeps(t, "control") {
		t.Fatal("the catalog dropped a provider under a name nothing reserves")
	}
	var opts waxbin.Options
	opts.Enrichment.Contact = "waxdeck@example.test"
	for _, p := range openBareCatalog(t, opts).EnrichmentBuiltins() {
		if !slices.Contains(ReservedEnrichNames, p.Name()) {
			t.Errorf("the built-in %q is not reserved", p.Name())
		}
	}
}
