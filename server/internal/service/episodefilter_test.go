package service

import (
	"strings"
	"testing"
	"unicode/utf8"
)

// TestEpisodeFilterAdmits is the whole matcher: substrings, case
// folding, exclude beating include, and the two ways a filter can be
// nothing at all.
func TestEpisodeFilterAdmits(t *testing.T) {
	cases := []struct {
		name   string
		filter EpisodeFilter
		title  string
		want   bool
	}{
		{"an unset filter admits everything", EpisodeFilter{}, "Episode 12", true},
		{"an include term matches as a substring",
			EpisodeFilter{Include: []string{"mailbag"}}, "The Friday Mailbag", true},
		{"an include list rejects what it does not name",
			EpisodeFilter{Include: []string{"mailbag"}}, "Interview with a guest", false},
		{"matching is case insensitive both ways",
			EpisodeFilter{Include: []string{"MAILBAG"}}, "the friday mailbag", true},
		{"any include term is enough",
			EpisodeFilter{Include: []string{"mailbag", "interview"}}, "Interview with a guest", true},
		{"exclude alone admits the rest",
			EpisodeFilter{Exclude: []string{"bonus"}}, "Episode 12", true},
		{"exclude rejects what it names",
			EpisodeFilter{Exclude: []string{"bonus"}}, "Bonus: outtakes", false},
		{"exclude wins over include",
			EpisodeFilter{Include: []string{"mailbag"}, Exclude: []string{"bonus"}},
			"Bonus Mailbag", false},
		{"terms are trimmed",
			EpisodeFilter{Include: []string{"  mailbag  "}}, "The Friday Mailbag", true},
		{"a blank-only include list is not a filter anyone expressed",
			EpisodeFilter{Include: []string{"", "   "}}, "Episode 12", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.filter.Admits(tc.title); got != tc.want {
				t.Errorf("Admits(%q) = %v, want %v", tc.title, got, tc.want)
			}
		})
	}
}

// TestEpisodeFilterUnion pins the shared-file rule: the downloaded
// episode is one file for every subscriber, so one subscriber wanting
// it is enough, and another's exclude cannot veto that.
func TestEpisodeFilterUnion(t *testing.T) {
	strict := EpisodeFilter{Include: []string{"mailbag"}}
	broad := EpisodeFilter{Exclude: []string{"bonus"}}
	filters := []EpisodeFilter{strict, broad}

	if !anyFilterAdmits(filters, "Episode 12") {
		t.Error("an episode one subscriber wants must be fetched")
	}
	if !anyFilterAdmits(filters, "The Friday Mailbag") {
		t.Error("an episode both subscribers want must be fetched")
	}
	if anyFilterAdmits([]EpisodeFilter{strict}, "Bonus: outtakes") {
		t.Error("the only subscriber's filter excluded it")
	}
	// Excluded by one, admitted by the other: the union takes it.
	if !anyFilterAdmits(filters, "Mailbag Bonus Round") {
		t.Error("strict admits it, so the union must fetch it")
	}
}

// TestNormalizeTerms covers what reaches storage: blanks dropped, terms
// trimmed and capped, and an all-blank list stored as nothing rather
// than as an empty filter.
func TestNormalizeTerms(t *testing.T) {
	if got := normalizeTerms(nil); got != nil {
		t.Errorf("normalizeTerms(nil) = %v, want nil", got)
	}
	if got := normalizeTerms([]string{" ", ""}); got != nil {
		t.Errorf("an all-blank list = %v, want nil", got)
	}
	got := normalizeTerms([]string{" mailbag ", "", "bonus"})
	if len(got) != 2 || got[0] != "mailbag" || got[1] != "bonus" {
		t.Errorf("normalizeTerms = %q, want the two trimmed terms", got)
	}

	long := strings.Repeat("a", maxFilterTermLen+50)
	if got := normalizeTerms([]string{long}); utf8.RuneCountInString(got[0]) != maxFilterTermLen {
		t.Errorf("an over-long term kept %d characters, want %d",
			utf8.RuneCountInString(got[0]), maxFilterTermLen)
	}

	// The cap counts characters, not bytes, so a term of multi-byte
	// runes keeps all of them and stays valid UTF-8. Slicing by bytes
	// would cut the last rune in half and store a replacement
	// character, which is a term that then matches nothing.
	multibyte := strings.Repeat("ま", maxFilterTermLen)
	got = normalizeTerms([]string{multibyte})
	if got[0] != multibyte {
		t.Errorf("a term of %d multi-byte runes was altered", maxFilterTermLen)
	}
	if !utf8.ValidString(got[0]) {
		t.Error("truncation produced invalid UTF-8")
	}
	over := strings.Repeat("ま", maxFilterTermLen+10)
	got = normalizeTerms([]string{over})
	if utf8.RuneCountInString(got[0]) != maxFilterTermLen || !utf8.ValidString(got[0]) {
		t.Errorf("an over-long multi-byte term = %d runes, valid=%v; want %d and valid",
			utf8.RuneCountInString(got[0]), utf8.ValidString(got[0]), maxFilterTermLen)
	}

	many := make([]string, maxFilterTerms+10)
	for i := range many {
		many[i] = "term"
	}
	if got := normalizeTerms(many); len(got) != maxFilterTerms {
		t.Errorf("term count = %d, want it capped at %d", len(got), maxFilterTerms)
	}
}
