package service

import "testing"

func TestUserAgentNamesTheBuild(t *testing.T) {
	t.Parallel()
	for version, want := range map[string]string{
		"1.2.3":     "WaxDeck/1.2.3 (+https://github.com/colespringer/waxdeck)",
		"0.1.0-dev": "WaxDeck/0.1.0-dev (+https://github.com/colespringer/waxdeck)",
		"":          "WaxDeck/dev (+https://github.com/colespringer/waxdeck)",
	} {
		if got := (&Library{version: version}).UserAgent(); got != want {
			t.Errorf("version %q: UserAgent() = %q, want %q", version, got, want)
		}
	}
}
