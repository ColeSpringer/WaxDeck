package genre_test

import (
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/genre"
)

func mustNew(t *testing.T, tree genre.Tree) *genre.Normalizer {
	t.Helper()
	n, err := genre.New(tree)
	if err != nil {
		t.Fatalf("building the normalizer: %v", err)
	}
	return n
}

func TestDefaultTreeBuilds(t *testing.T) {
	n := mustNew(t, genre.Default())
	if n.Len() < 50 {
		t.Fatalf("the shipped tree holds only %d genres; it is meant to be broad", n.Len())
	}
	// Every parent named by a child must be a top-level genre of the same
	// tree, which New enforces; this asserts the shipped document actually
	// uses the grouping rather than being a flat list.
	children := 0
	for _, node := range n.Tree() {
		if node.Parent != "" {
			children++
		}
	}
	if children == 0 {
		t.Fatal("the shipped tree has no child genres")
	}
}

func TestAliasResolvesSynonyms(t *testing.T) {
	n := mustNew(t, genre.Default())
	// The case no match key can fold: distinct words, one genre.
	for _, raw := range []string{"Rap", "rap", "RAP", "Hip-Hop", "hip hop", "HipHop"} {
		got, ok := n.Normalize(raw)
		if !ok || got != "Hip Hop" {
			t.Fatalf("Normalize(%q) = %q, %v; want \"Hip Hop\", true", raw, got, ok)
		}
	}
	for _, raw := range []string{"DnB", "D&B", "drum and bass", "Drum & Bass"} {
		got, ok := n.Normalize(raw)
		if !ok || got != "Drum & Bass" {
			t.Fatalf("Normalize(%q) = %q, %v; want \"Drum & Bass\", true", raw, got, ok)
		}
	}
	if got, ok := n.Normalize("Alt Rock"); !ok || got != "Alternative Rock" {
		t.Fatalf("Normalize(\"Alt Rock\") = %q, %v", got, ok)
	}
}

func TestUnmappedPassesThrough(t *testing.T) {
	n := mustNew(t, genre.Default())
	got, ok := n.Normalize("  Sea Shanty Revival ")
	if ok {
		t.Fatal("an unknown genre reported as mapped")
	}
	if got != "Sea Shanty Revival" {
		t.Fatalf("an unknown genre came back as %q; it should pass through trimmed", got)
	}
}

func TestNormalizeScalarDeduplicates(t *testing.T) {
	n := mustNew(t, genre.Default())
	// Two raw tags collapsing onto one canonical name must not produce a
	// doubled scalar, which is why the cap in the enrichment path applies
	// after normalization rather than before it.
	scalar, unmapped := n.NormalizeScalar("Rap; Hip-Hop; Trap")
	if scalar != "Hip Hop; Trap" {
		t.Fatalf("NormalizeScalar collapsed to %q", scalar)
	}
	if len(unmapped) != 0 {
		t.Fatalf("unexpected unmapped names: %v", unmapped)
	}
	scalar, unmapped = n.NormalizeScalar("Rock / Sea Shanty Revival")
	if scalar != "Rock; Sea Shanty Revival" {
		t.Fatalf("NormalizeScalar = %q; an unmapped name should survive in place", scalar)
	}
	if len(unmapped) != 1 || unmapped[0] != "Sea Shanty Revival" {
		t.Fatalf("unmapped = %v", unmapped)
	}
}

func TestParentGrouping(t *testing.T) {
	n := mustNew(t, genre.Default())
	if got := n.Parent("thrash"); got != "Metal" {
		t.Fatalf("Parent(\"thrash\") = %q; want \"Metal\"", got)
	}
	if got := n.Parent("Metal"); got != "" {
		t.Fatalf("a top-level genre reported parent %q", got)
	}
	if got := n.Parent("Sea Shanty Revival"); got != "" {
		t.Fatalf("an unknown genre reported parent %q", got)
	}
}

func TestRejectsAmbiguousTrees(t *testing.T) {
	cases := []struct {
		name string
		tree genre.Tree
		want string
	}{
		{
			name: "duplicate names",
			tree: genre.Tree{{Name: "Hip-Hop"}, {Name: "hip hop"}},
			want: "the same genre",
		},
		{
			name: "alias claimed twice",
			tree: genre.Tree{
				{Name: "Hip Hop", Aliases: []string{"Rap"}},
				{Name: "Grime", Aliases: []string{"rap"}},
			},
			want: "already resolves to",
		},
		{
			name: "unknown parent",
			tree: genre.Tree{{Name: "Thrash Metal", Parent: "Metal"}},
			want: "not a genre in this tree",
		},
		{
			name: "three levels",
			tree: genre.Tree{
				{Name: "Metal"},
				{Name: "Thrash Metal", Parent: "Metal"},
				{Name: "Crossover Thrash", Parent: "Thrash Metal"},
			},
			want: "two levels deep",
		},
		{
			name: "empty",
			tree: genre.Tree{},
			want: "empty",
		},
		{
			name: "nameless node",
			tree: genre.Tree{{Name: "  "}},
			want: "no name",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := genre.New(tc.tree); err == nil {
				t.Fatal("the tree was accepted")
			} else if !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("error %q does not mention %q", err, tc.want)
			}
		})
	}
}

// TestDuplicateAliasesCollapse: one alias written twice (or in two
// spellings that fold together) is not a conflict, but it must not
// survive into the stored vocabulary, or a read-edit-write round trip
// through the admin surface would accumulate it.
func TestDuplicateAliasesCollapse(t *testing.T) {
	n := mustNew(t, genre.Tree{
		// "Hip-Hop" folds onto the genre's own name rather than onto
		// another alias: redundant, and kept by design so an editable
		// vocabulary can spell out a variant the match key covers anyway.
		{Name: "Hip Hop", Aliases: []string{"Rap", "rap", "RAP", "Hip-Hop", "Hiphop"}},
	})
	node := n.Tree()[0]
	want := []string{"Rap", "Hip-Hop", "Hiphop"}
	if strings.Join(node.Aliases, ",") != strings.Join(want, ",") {
		t.Fatalf("aliases = %v; want %v (first-seen spelling kept, repeats dropped)", node.Aliases, want)
	}
	// Every spelling still resolves: deduplication is about what is
	// stored, not about what the vocabulary accepts.
	for _, raw := range []string{"Rap", "rap", "RAP", "Hip-Hop", "Hiphop", "hip hop"} {
		if got, ok := n.Normalize(raw); !ok || got != "Hip Hop" {
			t.Fatalf("Normalize(%q) = %q, %v after deduplication", raw, got, ok)
		}
	}
}

func TestTreeIsSortedForDisplay(t *testing.T) {
	n := mustNew(t, genre.Tree{
		{Name: "Thrash Metal", Parent: "Metal"},
		{Name: "Rock"},
		{Name: "Metal"},
		{Name: "Black Metal", Parent: "Metal"},
	})
	var got []string
	for _, node := range n.Tree() {
		got = append(got, node.Name)
	}
	want := []string{"Metal", "Black Metal", "Thrash Metal", "Rock"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("display order %v; want %v", got, want)
	}
}
