package fixtures_test

import (
	"os"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

const (
	currentPodcastNS = `xmlns:podcast="https://podcastindex.org/namespace/1.0"`
	legacyPodcastNS  = `xmlns:podcast="https://github.com/Podcastindex-org/podcast-namespace/blob/main/docs/1.0.md"`
)

func legacyFeedSpec(legacy bool) fixtures.FeedSpec {
	return fixtures.FeedSpec{
		Title:           "Namespace Cast",
		Author:          "Namespace Host",
		Description:     "A show with credits.",
		LegacyNamespace: legacy,
		Persons: []fixtures.PersonSpec{
			{Name: "Old Host", Role: "Host", Href: "https://example.com/old-host"},
			{Name: "Quiet Producer"},
		},
		Episodes: []fixtures.EpisodeSpec{{
			Title:   "Pilot",
			GUID:    "wd-namespace-ep-001",
			PubDate: time.Date(2026, 1, 15, 9, 30, 0, 0, time.UTC),
			Spec:    fixtures.Spec{Codec: fixtures.CodecMP3, Duration: time.Second},
		}},
	}
}

func generatedFeed(t *testing.T, feed fixtures.FeedSpec) string {
	t.Helper()
	path, err := fixtures.GeneratePodcastFeed(t.TempDir(), feed, "http://x")
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

// A feed declares the Podcasting 2.0 namespace once, on its root, and the
// generator can declare it at the address it lived at before
// podcastindex.org, which some feeds in the wild still do.
func TestPodcastFeedDeclaresTheNamespaceItIsAskedTo(t *testing.T) {
	t.Run("current", func(t *testing.T) {
		doc := generatedFeed(t, legacyFeedSpec(false))
		if !strings.Contains(doc, currentPodcastNS) || strings.Contains(doc, "github.com") {
			t.Errorf("feed does not declare only the current namespace:\n%s", doc)
		}
	})
	t.Run("legacy", func(t *testing.T) {
		doc := generatedFeed(t, legacyFeedSpec(true))
		if !strings.Contains(doc, legacyPodcastNS) || strings.Contains(doc, "podcastindex.org/namespace") {
			t.Errorf("feed does not declare only the legacy namespace:\n%s", doc)
		}
	})
}

// The show's credits are channel-level podcast:person elements, with the
// role and link as the credit gives them and neither when it gives none.
func TestPodcastFeedWritesTheShowsPersons(t *testing.T) {
	doc := generatedFeed(t, legacyFeedSpec(false))
	for _, want := range []string{
		`<podcast:person role="Host" href="https://example.com/old-host">Old Host</podcast:person>`,
		`<podcast:person>Quiet Producer</podcast:person>`,
	} {
		if !strings.Contains(doc, want) {
			t.Errorf("feed lacks %s:\n%s", want, doc)
		}
	}
	if channel := strings.Index(doc, "<channel>"); channel > strings.Index(doc, "<podcast:person") ||
		strings.Index(doc, "<podcast:person") > strings.Index(doc, "<item>") {
		t.Errorf("the credits are not channel-level, ahead of the items:\n%s", doc)
	}
}
