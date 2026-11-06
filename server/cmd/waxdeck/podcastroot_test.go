package main

import (
	"strings"
	"testing"
)

// The podcast root is its own engine root, so its name may not be a
// library root's: the engine refuses duplicate names at start.
func TestPodcastRootNameMustNotBeALibraryRoot(t *testing.T) {
	roots := []root{{Name: "music", Path: "/music"}, {Name: "books", Path: "/audiobooks"}}
	if err := checkPodcastRootName(roots, "podcasts"); err != nil {
		t.Fatal(err)
	}
	err := checkPodcastRootName(roots, "books")
	if err == nil || !strings.Contains(err.Error(), "WAXDECK_PODCAST_ROOT_NAME") || !strings.Contains(err.Error(), "books") {
		t.Fatalf("checkPodcastRootName = %v, want an error naming the variable and the root", err)
	}
}
