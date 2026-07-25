// Package genre owns WaxDeck's canonical genre vocabulary: a two-level
// tree of parent and child genres, each carrying one canonical display
// name and the aliases that resolve to it.
//
// It exists because the catalog deliberately does not decide what a
// genre is called. WaxBin folds spelling variants together — its match
// key lowercases, strips diacritics, and folds punctuation to spaces, so
// "Hip-Hop" and "hip hop" already join one genre row — but the row's
// display name is whichever spelling was scanned first, and true
// synonyms ("Rap" and "Hip Hop", "DnB" and "Drum & Bass") are separate
// rows no folding can merge. This package answers both: an alias list
// maps synonyms onto one canonical name, and that name is the label
// every WaxDeck surface shows.
//
// Resolution keys on the same folding the catalog uses, so this
// vocabulary composes with what the catalog already collapses rather
// than re-deciding it: a variant the match key already folds needs no
// alias entry, and only a spelling the fold cannot reach (a run-together
// "hiphop", whose punctuation would have become a space) does.
//
// A name the tree does not know is reported as a miss, never guessed at:
// an unmapped tag passes through untouched.
package genre

import (
	"errors"
	"fmt"
	"sort"
	"strings"

	"github.com/colespringer/waxbin/identity"
)

// Node is one genre in the canonical tree: its display name, the parent
// it hangs under (empty for a top-level genre), and every alias that
// resolves to it.
type Node struct {
	Name    string   `json:"name"`
	Parent  string   `json:"parent,omitempty"`
	Aliases []string `json:"aliases,omitempty"`
}

// Tree is a whole canonical vocabulary.
type Tree []Node

// Fold reduces a display name to its resolution key. It is the catalog's
// match key verbatim (case, diacritics, and punctuation folded), so a
// variant the catalog already collapses into one genre row also resolves
// here without its own alias entry.
func Fold(s string) string { return identity.MatchKey(s) }

// Split breaks a raw genre tag into its individual display names, using
// the catalog's own in-tag separators so a "Rock; Pop" scalar normalizes
// as two genres rather than one unknown one.
func Split(raw string) []string { return identity.SplitGenres(raw) }

// Separator joins normalized genre names back into the scalar the
// catalog stores. It matches what the enrichment path already writes, so
// a normalized value and an enriched one are the same shape.
const Separator = "; "

// Join renders normalized names back into a genre scalar.
func Join(names []string) string { return strings.Join(names, Separator) }

// Normalizer resolves raw genre names against one tree.
type Normalizer struct {
	// byKey maps a folded name or alias to its canonical display name.
	byKey map[string]string
	// parent maps a canonical name to its parent's canonical name.
	parent map[string]string
	tree   Tree
}

// New builds a normalizer over the tree, rejecting a vocabulary that
// could not resolve deterministically: a duplicate name, an alias
// claimed twice, an alias that collides with a different genre's name,
// a parent that is not itself a declared top-level genre, or a node that
// is its own parent. The tree is two levels deep by design — a genre
// browse is a list with optional grouping, not an outline — so a parent
// may not itself have a parent.
func New(t Tree) (*Normalizer, error) {
	if len(t) == 0 {
		return nil, errors.New("genre: the tree is empty")
	}
	n := &Normalizer{
		byKey:  make(map[string]string, len(t)*2),
		parent: make(map[string]string, len(t)),
		tree:   make(Tree, 0, len(t)),
	}
	// Names first, so an alias colliding with any name is caught whatever
	// order the nodes arrive in.
	names := make(map[string]string, len(t))
	for _, node := range t {
		name := strings.TrimSpace(node.Name)
		if name == "" {
			return nil, errors.New("genre: a node has no name")
		}
		key := Fold(name)
		if key == "" {
			return nil, fmt.Errorf("genre: %q folds to nothing and cannot be resolved", name)
		}
		if prev, dup := names[key]; dup {
			return nil, fmt.Errorf("genre: %q and %q are the same genre", prev, name)
		}
		names[key] = name
		n.byKey[key] = name
	}
	for _, node := range t {
		name := strings.TrimSpace(node.Name)
		aliases := make([]string, 0, len(node.Aliases))
		// Two aliases of one genre that fold together ("Rap" and "rap")
		// are one alias written twice, not a conflict. Keeping both would
		// resolve identically but survive a read-edit-write round trip
		// through the admin surface, so the duplicate is dropped here and
		// the first-seen spelling is the one stored -- the same
		// first-seen-casing rule the catalog's own genre dedup follows.
		seenAlias := make(map[string]bool, len(node.Aliases))
		for _, raw := range node.Aliases {
			alias := strings.TrimSpace(raw)
			if alias == "" {
				continue
			}
			key := Fold(alias)
			if key == "" {
				return nil, fmt.Errorf("genre: alias %q of %q folds to nothing", alias, name)
			}
			if owner, taken := n.byKey[key]; taken && owner != name {
				return nil, fmt.Errorf("genre: alias %q of %q already resolves to %q", alias, name, owner)
			}
			if seenAlias[key] {
				continue
			}
			seenAlias[key] = true
			// An alias the fold already maps onto its own genre is
			// redundant, not an error: the vocabulary stays legible when
			// someone spells out a variant the match key covers anyway.
			n.byKey[key] = name
			aliases = append(aliases, alias)
		}
		parent := strings.TrimSpace(node.Parent)
		if parent != "" {
			canon, ok := names[Fold(parent)]
			if !ok {
				return nil, fmt.Errorf("genre: %q hangs under %q, which is not a genre in this tree", name, parent)
			}
			if canon == name {
				return nil, fmt.Errorf("genre: %q is its own parent", name)
			}
			parent = canon
			n.parent[name] = parent
		}
		n.tree = append(n.tree, Node{Name: name, Parent: parent, Aliases: aliases})
	}
	for name, parent := range n.parent {
		if grand, deep := n.parent[parent]; deep {
			return nil, fmt.Errorf("genre: %q hangs under %q, which already hangs under %q; the tree is two levels deep",
				name, parent, grand)
		}
	}
	sort.Slice(n.tree, func(i, j int) bool {
		a, b := n.tree[i], n.tree[j]
		ak, bk := a.Parent, b.Parent
		if ak == "" {
			ak = a.Name
		}
		if bk == "" {
			bk = b.Name
		}
		if ak != bk {
			return ak < bk
		}
		// A parent sorts ahead of its own children.
		if (a.Parent == "") != (b.Parent == "") {
			return a.Parent == ""
		}
		return a.Name < b.Name
	})
	return n, nil
}

// Normalize resolves one raw genre name to its canonical spelling. The
// second result is false when the tree does not know the name, in which
// case the trimmed input comes back unchanged: an unmapped tag passes
// through rather than being guessed at or dropped.
func (n *Normalizer) Normalize(raw string) (string, bool) {
	name := strings.TrimSpace(raw)
	if name == "" {
		return "", false
	}
	if canon, ok := n.byKey[Fold(name)]; ok {
		return canon, true
	}
	return name, false
}

// NormalizeScalar resolves a whole genre scalar ("Rock; hiphop") into
// its canonical form, deduplicating by fold so two raw tags that
// normalize to one name collapse. Unmapped names survive in place.
// The second result names them, in first-seen order, for a caller that
// reports what its vocabulary does not cover.
func (n *Normalizer) NormalizeScalar(raw string) (scalar string, unmapped []string) {
	var out []string
	seen := make(map[string]bool)
	for _, name := range Split(raw) {
		canon, ok := n.Normalize(name)
		if canon == "" {
			continue
		}
		key := Fold(canon)
		if seen[key] {
			continue
		}
		seen[key] = true
		out = append(out, canon)
		if !ok {
			unmapped = append(unmapped, canon)
		}
	}
	return Join(out), unmapped
}

// Parent reports the canonical parent of a canonical genre name, empty
// for a top-level genre or a name the tree does not know.
func (n *Normalizer) Parent(name string) string {
	canon, ok := n.Normalize(name)
	if !ok {
		return ""
	}
	return n.parent[canon]
}

// Tree returns the vocabulary in display order: each top-level genre
// followed by its children, alphabetically throughout.
func (n *Normalizer) Tree() Tree { return n.tree }

// Len reports how many genres the vocabulary holds.
func (n *Normalizer) Len() int { return len(n.tree) }
