package service

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/colespringer/waxbin/organize"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// A library moved to the default profile at start is audited under its
// name, not its folder's, though the root table is not built yet.
func TestAStartsProfileMoveNamesTheLibrary(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	books := filepath.Join(dataDir, "audiobooks")
	if err := os.Mkdir(books, 0o755); err != nil {
		t.Fatal(err)
	}
	withBooks := func(c *Config) { c.Roots = append(c.Roots, Root{Name: "books", Path: books, Managed: true}) }
	ctx, svc, uc, stop := openServiceAt(t, dataDir, withBooks)
	if _, err := svc.PutOrganizeProfile(ctx, uc, "flat", OrganizeProfileInput{Music: "{title}.{ext}"}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SetLibraryProfile(ctx, uc, libraryAt(t, ctx, svc, books).PID, "flat"); err != nil {
		t.Fatal(err)
	}
	stop()
	store, err := wdb.Open(context.Background(), filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.OrganizeProfilesDelete(context.Background(), "flat"); err != nil {
		t.Fatal(err)
	}
	store.Close()

	ctx, svc, _, _ = openServiceAt(t, dataDir, withBooks)
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "library.profile"}, "", 10)
	if err != nil || len(page.Events) == 0 {
		t.Fatalf("no library.profile audit (%v)", err)
	}
	if e := page.Events[0]; e.TargetName != "books" || e.Detail["profile"] != organize.DefaultProfileName {
		t.Errorf("audit = %+v, want the move of books to the default", e)
	}
}

// A root taken out of the configuration keeps the name it went by, which
// is the name the streaming sidecar mounts it under, rather than taking
// its folder's at the next start.
func TestARootTakenOutOfTheConfigurationKeepsItsName(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	books := filepath.Join(dataDir, "audiobooks")
	if err := os.Mkdir(books, 0o755); err != nil {
		t.Fatal(err)
	}
	ctx, svc, _, stop := openServiceAt(t, dataDir, func(c *Config) {
		c.Roots = append(c.Roots, Root{Name: "books", Path: books})
	})
	if lib := libraryAt(t, ctx, svc, books); lib.Name != "books" || !lib.Configured {
		t.Fatalf("the configured root lists %+v, want books, configured", lib)
	}
	stop()
	ctx, svc, _, _ = openServiceAt(t, dataDir, nil)
	if lib := libraryAt(t, ctx, svc, books); lib.Name != "books" || lib.Configured {
		t.Errorf("out of the configuration the root lists %+v, want books, not configured", lib)
	}
}
