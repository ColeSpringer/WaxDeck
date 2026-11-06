package main

import (
	"slices"
	"testing"
)

// Cutting defaults to sponsors and non-music sections; a variable set
// empty turns it off, and the flag beats the variable.
func TestSponsorBlockFrom(t *testing.T) {
	env := func(vars map[string]string) func(string) (string, bool) {
		return func(k string) (string, bool) { v, ok := vars[k]; return v, ok }
	}
	cases := []struct {
		name    string
		flag    string
		flagSet bool
		env     map[string]string
		want    []string
	}{
		{"nothing set", "", false, nil, []string{"sponsor", "music_offtopic"}},
		{"variable empty", "", false, map[string]string{"WAXDECK_YOUTUBE_SPONSORBLOCK": ""}, nil},
		{"variable set", "sponsor", false, map[string]string{"WAXDECK_YOUTUBE_SPONSORBLOCK": "sponsor"}, []string{"sponsor"}},
		{"spaces trimmed", " intro , outro ", false, map[string]string{"WAXDECK_YOUTUBE_SPONSORBLOCK": " intro , outro "}, []string{"intro", "outro"}},
		{"flag beats variable", "intro", true, map[string]string{"WAXDECK_YOUTUBE_SPONSORBLOCK": "sponsor"}, []string{"intro"}},
		{"flag empty disables", "", true, map[string]string{"WAXDECK_YOUTUBE_SPONSORBLOCK": "sponsor"}, nil},
	}
	for _, c := range cases {
		if got := sponsorBlockFrom(c.flag, c.flagSet, env(c.env)); !slices.Equal(got, c.want) {
			t.Errorf("%s: categories = %v, want %v", c.name, got, c.want)
		}
	}
}
