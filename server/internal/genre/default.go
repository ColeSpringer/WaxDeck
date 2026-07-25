package genre

import (
	_ "embed"
	"encoding/json"
	"fmt"
	"sync"
)

// defaultJSON is the shipped vocabulary. It is embedded rather than
// built in code so an administrator exporting the tree, editing it, and
// putting it back works on the same document the server started from.
//
//go:embed default.json
var defaultJSON []byte

var (
	defaultOnce sync.Once
	defaultTree Tree
	defaultErr  error
)

// Default is the shipped canonical vocabulary: a broad two-level tree
// covering the genres file tags and metadata providers actually carry,
// with the synonym aliases no match key can fold ("Rap" onto "Hip Hop",
// "DnB" onto "Drum & Bass"). An instance that wants its own vocabulary
// replaces it wholesale; one that wants none leaves normalization off.
//
// It panics on a malformed embedded document, which can only be a build
// defect: the package's own test builds a normalizer over it.
func Default() Tree {
	defaultOnce.Do(func() {
		var t Tree
		if err := json.Unmarshal(defaultJSON, &t); err != nil {
			defaultErr = fmt.Errorf("genre: the embedded default tree is malformed: %w", err)
			return
		}
		defaultTree = t
	})
	if defaultErr != nil {
		panic(defaultErr)
	}
	return defaultTree
}
