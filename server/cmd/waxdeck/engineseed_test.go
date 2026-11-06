package main

import (
	"slices"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
)

// The seed carries every configured root and the podcast root last.
func TestEngineSeedRootsEndWithPodcasts(t *testing.T) {
	got := engineSeedRoots([]root{{Name: "music", Path: "/music"}, {Name: "books", Path: "/audiobooks"}}, "podcasts", "/podcasts")
	want := []flow.Root{{Name: "music", Path: "/music"}, {Name: "books", Path: "/audiobooks"}, {Name: "podcasts", Path: "/podcasts"}}
	if !slices.Equal(got, want) {
		t.Errorf("seed = %v, want %v", got, want)
	}
	if got := engineSeedRoots(nil, "podcasts", ""); len(got) != 0 {
		t.Errorf("seed with podcasts disabled = %v, want none", got)
	}
}
