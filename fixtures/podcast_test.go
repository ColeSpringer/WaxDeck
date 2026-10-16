package fixtures_test

import (
	"context"
	"encoding/xml"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxlabel"

	"github.com/colespringer/waxdeck/fixtures"
)

// Parse-back structs: local names only, so the decoder's namespace
// resolution of the itunes: and podcast: prefixes does not get in the
// way of matching.
type parsedFeed struct {
	Channel struct {
		Title       string       `xml:"title"`
		Link        string       `xml:"link"`
		Description string       `xml:"description"`
		Author      string       `xml:"author"`
		GUID        string       `xml:"guid"`
		Items       []parsedItem `xml:"item"`
	} `xml:"channel"`
}

type parsedItem struct {
	Title string `xml:"title"`
	GUID  struct {
		IsPermaLink string `xml:"isPermaLink,attr"`
		Value       string `xml:",chardata"`
	} `xml:"guid"`
	PubDate   string `xml:"pubDate"`
	Enclosure struct {
		URL    string `xml:"url,attr"`
		Type   string `xml:"type,attr"`
		Length int64  `xml:"length,attr"`
	} `xml:"enclosure"`
	Duration   string        `xml:"duration"`
	Transcript []parsedPoint `xml:"transcript"`
	Chapters   []parsedPoint `xml:"chapters"`
}

type parsedPoint struct {
	URL  string `xml:"url,attr"`
	Type string `xml:"type,attr"`
}

// The preset feeds are two: the default one at the served root, and one
// whose episodes sort before every other fixture title, in a directory of
// its own because a feed document is always feed.xml. Every episode's
// audio is its own, so no catalog folds two of them into one item.
func TestPresetFeedsIncludeOneThatSortsFirst(t *testing.T) {
	dir := t.TempDir()
	const baseURL = "http://x"
	paths, err := fixtures.GeneratePresetFeeds(dir, baseURL)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{filepath.Join(dir, "feed.xml"), filepath.Join(dir, fixtures.EarlyFeedDir, "feed.xml")}
	if !slices.Equal(paths, want) {
		t.Fatalf("feeds = %v, want %v", paths, want)
	}
	raw, err := os.ReadFile(paths[1])
	if err != nil {
		t.Fatal(err)
	}
	var early parsedFeed
	if err := xml.Unmarshal(raw, &early); err != nil {
		t.Fatalf("parsing the early feed: %v", err)
	}
	if len(early.Channel.Items) < 2 {
		t.Fatalf("the early feed has %d episodes, want several", len(early.Channel.Items))
	}

	var others []string
	for _, s := range slices.Concat(fixtures.DefaultLibrary(), fixtures.DemoLibrary(), fixtures.LongTrack()) {
		title := s.Tags["TITLE"]
		if title == "" {
			title = strings.TrimSuffix(s.Filename(), filepath.Ext(s.Filename()))
		}
		others = append(others, title)
	}
	for _, ep := range fixtures.DefaultPodcastFeed(baseURL).Episodes {
		others = append(others, ep.Title)
	}
	for _, item := range early.Channel.Items {
		for _, other := range others {
			if strings.ToLower(item.Title) >= strings.ToLower(other) {
				t.Errorf("episode %q does not sort before %q", item.Title, other)
			}
		}
		prefix := baseURL + "/" + fixtures.EarlyFeedDir + "/"
		if !strings.HasPrefix(item.Enclosure.URL, prefix) {
			t.Errorf("episode %q enclosure %s, want it under %s", item.Title, item.Enclosure.URL, prefix)
		}
		if _, err := os.Stat(filepath.Join(dir, fixtures.EarlyFeedDir, strings.TrimPrefix(item.Enclosure.URL, prefix))); err != nil {
			t.Errorf("episode %q audio missing: %v", item.Title, err)
		}
	}

	// The audio's own identity, tags aside, as a catalog compares it: the
	// files differ by their titles whatever their audio.
	seen := map[string]string{}
	audio, _ := filepath.Glob(filepath.Join(dir, "*.mp3"))
	more, _ := filepath.Glob(filepath.Join(dir, fixtures.EarlyFeedDir, "*.mp3"))
	for _, path := range append(audio, more...) {
		doc, err := waxlabel.ParseFile(context.Background(), path)
		if err != nil {
			t.Fatal(err)
		}
		digest, err := doc.HashAudioEssence(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		if first, dup := seen[digest.String()]; dup {
			t.Errorf("%s holds the same audio as %s", path, first)
		}
		seen[digest.String()] = path
	}
	if len(seen) != 3+len(early.Channel.Items) {
		t.Errorf("%d distinct episode audios, want %d", len(seen), 3+len(early.Channel.Items))
	}
}

func TestGeneratePodcastFeed(t *testing.T) {
	dir := t.TempDir()
	const baseURL = "http://x"
	feed := fixtures.DefaultPodcastFeed(baseURL)
	feedPath, err := fixtures.GeneratePodcastFeed(dir, feed, baseURL)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(feedPath)
	if err != nil {
		t.Fatal(err)
	}
	var parsed parsedFeed
	if err := xml.Unmarshal(raw, &parsed); err != nil {
		t.Fatalf("parsing feed.xml back: %v", err)
	}

	ch := parsed.Channel
	if ch.Title != feed.Title || ch.Author != feed.Author || ch.Description != feed.Description {
		t.Errorf("channel = %q/%q/%q, want %q/%q/%q",
			ch.Title, ch.Author, ch.Description, feed.Title, feed.Author, feed.Description)
	}
	if ch.GUID == "" || strings.Count(ch.GUID, "-") != 4 {
		t.Errorf("channel podcast:guid = %q, want a UUID-shaped value", ch.GUID)
	}
	if len(ch.Items) != 3 {
		t.Fatalf("items = %d, want 3", len(ch.Items))
	}

	for i, item := range ch.Items {
		ep := feed.Episodes[i]
		if item.Title != ep.Title || item.GUID.Value != ep.GUID {
			t.Errorf("item %d = %q/%q, want %q/%q", i, item.Title, item.GUID.Value, ep.Title, ep.GUID)
		}
		if item.GUID.IsPermaLink != "false" {
			t.Errorf("item %d guid isPermaLink = %q, want false", i, item.GUID.IsPermaLink)
		}
		if want := ep.PubDate.Format(time.RFC1123Z); item.PubDate != want {
			t.Errorf("item %d pubDate = %q, want %q", i, item.PubDate, want)
		}
		if item.Enclosure.Type != "audio/mpeg" {
			t.Errorf("item %d enclosure type = %q, want audio/mpeg", i, item.Enclosure.Type)
		}
		wantURL := baseURL + "/" + ep.GUID + ".mp3"
		if item.Enclosure.URL != wantURL {
			t.Errorf("item %d enclosure url = %q, want %q", i, item.Enclosure.URL, wantURL)
		}
		info, err := os.Stat(filepath.Join(dir, ep.GUID+".mp3"))
		if err != nil {
			t.Fatalf("item %d audio missing: %v", i, err)
		}
		if item.Enclosure.Length != info.Size() {
			t.Errorf("item %d enclosure length = %d, want file size %d", i, item.Enclosure.Length, info.Size())
		}
	}

	// Episode 1 advertises its transcript and chapters; the others do not.
	first := ch.Items[0]
	if len(first.Transcript) != 1 || first.Transcript[0].URL != baseURL+"/wd-fixture-ep-001.vtt" ||
		first.Transcript[0].Type != "text/vtt" {
		t.Errorf("episode 1 transcript = %+v, want %s/wd-fixture-ep-001.vtt as text/vtt", first.Transcript, baseURL)
	}
	if len(first.Chapters) != 1 || first.Chapters[0].URL != baseURL+"/wd-fixture-ep-001.chapters.json" ||
		first.Chapters[0].Type != "application/json+chapters" {
		t.Errorf("episode 1 chapters = %+v, want %s/wd-fixture-ep-001.chapters.json", first.Chapters, baseURL)
	}
	for i, item := range ch.Items[1:] {
		if len(item.Transcript) != 0 || len(item.Chapters) != 0 {
			t.Errorf("episode %d advertises transcript/chapters it does not have", i+2)
		}
	}

	// The sidecar documents landed on disk with the given content.
	vtt, err := os.ReadFile(filepath.Join(dir, "wd-fixture-ep-001.vtt"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(string(vtt), "WEBVTT") || strings.Count(string(vtt), "-->") != 3 {
		t.Errorf("transcript is not a 3-cue WebVTT document:\n%s", vtt)
	}
	chapters, err := os.ReadFile(filepath.Join(dir, "wd-fixture-ep-001.chapters.json"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(chapters), `"version":"1.2.0"`) {
		t.Errorf("chapters document lacks the version field:\n%s", chapters)
	}
}
