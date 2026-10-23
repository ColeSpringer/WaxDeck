package main

import (
	"path/filepath"
	"testing"
)

// An explicitly empty podcast dir turns podcasts off whichever way it was
// said; saying nothing keeps them on beside the databases.
func TestAnEmptyPodcastDirTurnsPodcastsOff(t *testing.T) {
	data := filepath.Join("srv", "data")
	unset := func(string) (string, bool) { return "", false }
	setTo := func(v string) func(string) (string, bool) {
		return func(key string) (string, bool) { return v, key == "WAXDECK_PODCAST_DIR" }
	}
	for _, tc := range []struct {
		name    string
		value   string
		flagSet bool
		env     func(string) (string, bool)
		want    string
	}{
		{"nothing said", "", false, unset, filepath.Join(data, "podcasts")},
		{"WAXDECK_PODCAST_DIR set and empty", "", false, setTo(""), ""},
		{"WAXDECK_PODCAST_DIR set", "/pods", false, setTo("/pods"), "/pods"},
		{"-podcast-dir empty", "", true, unset, ""},
		{"-podcast-dir set", "/pods", true, setTo(""), "/pods"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := podcastDirFrom(tc.value, tc.flagSet, tc.env, data); got != tc.want {
				t.Fatalf("podcastDirFrom = %q, want %q", got, tc.want)
			}
		})
	}
}
