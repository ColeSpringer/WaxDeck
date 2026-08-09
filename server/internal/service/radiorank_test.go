package service

import "testing"

func names(entries []RadioDirectoryEntry) []string {
	out := make([]string, 0, len(entries))
	for _, e := range entries {
		out = append(out, e.Name)
	}
	return out
}

func equalNames(got []RadioDirectoryEntry, want []string) bool {
	names := names(got)
	if len(names) != len(want) {
		return false
	}
	for i := range names {
		if names[i] != want[i] {
			return false
		}
	}
	return true
}

func TestRankRadioByRegion(t *testing.T) {
	t.Parallel()
	// The directory answers in vote order. Ranking may reorder across
	// the two halves and must not reorder inside either, or it would be
	// overruling the directory's own judgement rather than adding to it.
	base := func() []RadioDirectoryEntry {
		return []RadioDirectoryEntry{
			{Name: "Global 1", CountryCode: "US"},
			{Name: "Local 1", CountryCode: "NL"},
			{Name: "Global 2", CountryCode: "DE"},
			{Name: "Local 2", CountryCode: "NL"},
			{Name: "Global 3", CountryCode: "US"},
		}
	}

	t.Run("local first, vote order kept inside each half", func(t *testing.T) {
		entries := base()
		rankRadioByRegion(entries, "NL")
		want := []string{"Local 1", "Local 2", "Global 1", "Global 2", "Global 3"}
		if !equalNames(entries, want) {
			t.Fatalf("ranked = %v, want %v", names(entries), want)
		}
	})

	// No region is the common case, not an edge one: a locale is
	// optional and `en` carries no region. Today's behaviour is the
	// right answer there, so the list must come back untouched.
	t.Run("no region leaves vote order alone", func(t *testing.T) {
		entries := base()
		rankRadioByRegion(entries, "")
		want := []string{"Global 1", "Local 1", "Global 2", "Local 2", "Global 3"}
		if !equalNames(entries, want) {
			t.Fatalf("ranked = %v, want the untouched list %v", names(entries), want)
		}
	})

	// A region nothing matches is the same as no region: nothing is
	// hidden, because this partitions rather than filters.
	t.Run("an unmatched region keeps every entry", func(t *testing.T) {
		entries := base()
		rankRadioByRegion(entries, "KE")
		want := []string{"Global 1", "Local 1", "Global 2", "Local 2", "Global 3"}
		if !equalNames(entries, want) {
			t.Fatalf("ranked = %v, want %v", names(entries), want)
		}
	})

	// Directories are not consistent about case, and a station that
	// sorted differently because of it would be a bug nobody could see.
	t.Run("country codes match case-insensitively", func(t *testing.T) {
		entries := []RadioDirectoryEntry{
			{Name: "Global", CountryCode: "us"},
			{Name: "Local", CountryCode: "nl"},
		}
		rankRadioByRegion(entries, "NL")
		if !equalNames(entries, []string{"Local", "Global"}) {
			t.Fatalf("ranked = %v", names(entries))
		}
	})
}

func TestListenerRegionRefusesAnInferredOne(t *testing.T) {
	t.Parallel()
	// The guard that matters: x/text resolves `en` to `US` at low
	// confidence, and acting on that would put American stations first
	// for everyone who picked English. Only a region the listener wrote
	// counts.
	for _, tc := range []struct {
		locale string
		want   string
	}{
		{"en-US", "US"},
		{"nl-NL", "NL"},
		{"pt-BR", "BR"},
		{"en", ""},
		{"nl", ""},
		{"", ""},
		{"not a tag", ""},
	} {
		if got := regionOfLocale(tc.locale); got != tc.want {
			t.Errorf("region of %q = %q, want %q", tc.locale, got, tc.want)
		}
	}
}
