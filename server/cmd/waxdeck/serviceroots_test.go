package main

import (
	"slices"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A root named in WAXDECK_AUDIOBOOK_ROOTS is declared to hold audiobooks
// and one named in WAXDECK_MANAGED_ROOTS takes files placed into it. A
// name may sit in both lists, and the lists forgive spaces and empty
// entries.
func TestRootListsMarkTheRootsTheyName(t *testing.T) {
	roots := []root{
		{Name: "lib", Path: "/music"}, {Name: "books", Path: "/books"},
		{Name: "both", Path: "/both"}, {Name: "plain", Path: "/plain"},
	}
	got, err := serviceRoots(roots, " lib , both,", ", books , both")
	if err != nil {
		t.Fatal(err)
	}
	want := []service.Root{
		{Name: "lib", Path: "/music", Managed: true},
		{Name: "books", Path: "/books", Media: "audiobook"},
		{Name: "both", Path: "/both", Managed: true, Media: "audiobook"},
		{Name: "plain", Path: "/plain"},
	}
	if !slices.Equal(got, want) {
		t.Fatalf("roots = %+v, want %+v", got, want)
	}
	if got, err := serviceRoots(roots, "", ""); err != nil || slices.ContainsFunc(got, func(r service.Root) bool { return r.Managed || r.Media != "" }) {
		t.Fatalf("with both lists empty: %+v, %v; want every root left as configured", got, err)
	}
}

// A name in either list that is no configured root fails the start,
// naming the variable and the name: skipped, a typo would leave a root
// unmanaged, or its books cataloged as music, and look like a working
// setup.
func TestARootListNamingNoRootIsRefused(t *testing.T) {
	roots := []root{{Name: "lib", Path: "/music"}}
	for _, c := range []struct {
		name, managed, books, says string
		roots                      []root
	}{
		{"an audiobook root that is not configured", "", "bookz", `WAXDECK_AUDIOBOOK_ROOTS names "bookz", which is not a configured library root`, roots},
		{"an audiobook root beside a configured one", "", "lib, bookz", `WAXDECK_AUDIOBOOK_ROOTS names "bookz", which is not a configured library root`, roots},
		{"a managed root that is not configured", "libb", "", `WAXDECK_MANAGED_ROOTS names "libb", which is not a configured library root`, roots},
		{"an audiobook root with no roots configured", "", "books", `WAXDECK_AUDIOBOOK_ROOTS names "books", which is not a configured library root`, nil},
	} {
		t.Run(c.name, func(t *testing.T) {
			got, err := serviceRoots(c.roots, c.managed, c.books)
			if err == nil || err.Error() != c.says {
				t.Fatalf("serviceRoots = %+v, %v; want the refusal %q", got, err, c.says)
			}
		})
	}
}
