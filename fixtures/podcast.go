package fixtures

import (
	"crypto/sha256"
	"encoding/xml"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// EpisodeSpec describes one podcast episode: its synthesized audio plus
// the feed-level fields an aggregator reads. TranscriptVTT and
// ChaptersJSON are optional; when set, the sidecar documents are written
// next to the audio and the feed advertises them via the podcast
// namespace. DeclaredDuration, when set, is the length the feed claims in
// place of the audio's own, as a feed whose host inserts ads can.
type EpisodeSpec struct {
	Title            string
	GUID             string
	Spec             Spec
	PubDate          time.Time
	Description      string
	TranscriptVTT    string
	ChaptersJSON     string
	DeclaredDuration time.Duration
}

// PersonSpec is one <podcast:person> credit. Role and Href are written
// only when set.
type PersonSpec struct {
	Name string
	Role string
	Href string
}

// FeedSpec describes one podcast feed: channel fields plus its episodes.
// Link is the channel's home URL; empty falls back to the base URL the
// feed is generated against. Persons are the show's credits.
// LegacyNamespace declares the Podcasting 2.0 namespace at the address it
// lived at before podcastindex.org, which some feeds still do.
type FeedSpec struct {
	Title           string
	Author          string
	Description     string
	Link            string
	Persons         []PersonSpec
	LegacyNamespace bool
	Episodes        []EpisodeSpec
}

const (
	podcastNS = "https://podcastindex.org/namespace/1.0"
	// legacyPodcastNS is the Podcasting 2.0 namespace's GitHub address.
	legacyPodcastNS = "https://github.com/Podcastindex-org/podcast-namespace/blob/main/docs/1.0.md"
)

// enclosureMIME maps a fixture container to the MIME type a feed
// enclosure declares for it.
var enclosureMIME = map[Container]string{
	ContainerWAV:      "audio/wav",
	ContainerAIFF:     "audio/aiff",
	ContainerFLAC:     "audio/flac",
	ContainerMP3:      "audio/mpeg",
	ContainerMP4:      "audio/mp4",
	ContainerADTS:     "audio/aac",
	ContainerOgg:      "audio/ogg",
	ContainerMatroska: "audio/x-matroska",
}

// RSS structs for feed.xml. Prefixed element names are written literally;
// the xmlns attributes on <rss> make them resolve for any namespace-aware
// reader parsing the feed back.

type rssDoc struct {
	XMLName      xml.Name    `xml:"rss"`
	Version      string      `xml:"version,attr"`
	ITunesNS     string      `xml:"xmlns:itunes,attr"`
	PodcastNS    string      `xml:"xmlns:podcast,attr"`
	ChannelTitle string      `xml:"channel>title"`
	ChannelLink  string      `xml:"channel>link"`
	ChannelDesc  string      `xml:"channel>description"`
	Author       string      `xml:"channel>itunes:author"`
	PodcastGUID  string      `xml:"channel>podcast:guid"`
	Persons      []rssPerson `xml:"channel>podcast:person"`
	Items        []rssItem   `xml:"channel>item"`
}

type rssPerson struct {
	Name string `xml:",chardata"`
	Role string `xml:"role,attr,omitempty"`
	Href string `xml:"href,attr,omitempty"`
}

type rssItem struct {
	Title       string         `xml:"title"`
	GUID        rssGUID        `xml:"guid"`
	PubDate     string         `xml:"pubDate"`
	Description string         `xml:"description"`
	Enclosure   rssEnclosure   `xml:"enclosure"`
	Duration    string         `xml:"itunes:duration"`
	Transcript  *rssPointerDoc `xml:"podcast:transcript,omitempty"`
	Chapters    *rssPointerDoc `xml:"podcast:chapters,omitempty"`
}

type rssGUID struct {
	IsPermaLink string `xml:"isPermaLink,attr"`
	Value       string `xml:",chardata"`
}

type rssEnclosure struct {
	URL    string `xml:"url,attr"`
	Type   string `xml:"type,attr"`
	Length int64  `xml:"length,attr"`
}

// rssPointerDoc is a podcast-namespace pointer element (transcript or
// chapters): a URL plus its MIME type.
type rssPointerDoc struct {
	URL  string `xml:"url,attr"`
	Type string `xml:"type,attr"`
}

// channelGUID derives a stable UUID-shaped identifier from the feed
// title: the first 16 bytes of its SHA-256, rendered 8-4-4-4-12. It is
// not a real UUIDv5, but it is deterministic and unique per title, which
// is all a fixture feed needs.
func channelGUID(title string) string {
	sum := sha256.Sum256([]byte("waxdeck-fixture-feed:" + title))
	hex := fmt.Sprintf("%x", sum[:16])
	return strings.Join([]string{hex[0:8], hex[8:12], hex[12:16], hex[16:20], hex[20:32]}, "-")
}

// GeneratePodcastFeed writes the feed's episode audio (through the same
// Generate machinery every fixture uses), any transcript (<guid>.vtt) and
// chapter (<guid>.chapters.json) sidecar documents, and a feed.xml tying
// them together: RSS 2.0 with the itunes and podcast namespaces,
// enclosure URLs rooted at baseURL. It returns the path of feed.xml.
func GeneratePodcastFeed(dir string, feed FeedSpec, baseURL string) (string, error) {
	base := strings.TrimRight(baseURL, "/")
	doc := rssDoc{
		Version:      "2.0",
		ITunesNS:     "http://www.itunes.com/dtds/podcast-1.0.dtd",
		PodcastNS:    podcastNS,
		ChannelTitle: feed.Title,
		ChannelLink:  feed.Link,
		ChannelDesc:  feed.Description,
		Author:       feed.Author,
		PodcastGUID:  channelGUID(feed.Title),
	}
	if doc.ChannelLink == "" {
		doc.ChannelLink = base
	}
	if feed.LegacyNamespace {
		doc.PodcastNS = legacyPodcastNS
	}
	for _, p := range feed.Persons {
		doc.Persons = append(doc.Persons, rssPerson(p))
	}

	for _, ep := range feed.Episodes {
		spec := ep.Spec
		if spec.Name == "" {
			spec.Name = ep.GUID
		}
		paths, err := Generate(dir, spec)
		if err != nil {
			return "", fmt.Errorf("fixtures: episode %q: %w", ep.GUID, err)
		}
		info, err := os.Stat(paths[0])
		if err != nil {
			return "", fmt.Errorf("fixtures: episode %q: %w", ep.GUID, err)
		}

		s := spec.withDefaults()
		mime, ok := enclosureMIME[s.Container]
		if !ok {
			return "", fmt.Errorf("fixtures: episode %q: no enclosure MIME type for container %q", ep.GUID, s.Container)
		}
		declared := s.LeadSilence + s.Duration + s.TrailSilence
		if ep.DeclaredDuration > 0 {
			declared = ep.DeclaredDuration
		}
		item := rssItem{
			Title:       ep.Title,
			GUID:        rssGUID{IsPermaLink: "false", Value: ep.GUID},
			PubDate:     ep.PubDate.Format(time.RFC1123Z),
			Description: ep.Description,
			Enclosure: rssEnclosure{
				URL:    base + "/" + url.PathEscape(filepath.Base(paths[0])),
				Type:   mime,
				Length: info.Size(),
			},
			Duration: fmt.Sprintf("%d", int64(declared/time.Second)),
		}

		if ep.TranscriptVTT != "" {
			name := ep.GUID + ".vtt"
			if err := os.WriteFile(filepath.Join(dir, name), []byte(ep.TranscriptVTT), 0o644); err != nil {
				return "", fmt.Errorf("fixtures: episode %q transcript: %w", ep.GUID, err)
			}
			item.Transcript = &rssPointerDoc{URL: base + "/" + url.PathEscape(name), Type: "text/vtt"}
		}
		if ep.ChaptersJSON != "" {
			name := ep.GUID + ".chapters.json"
			if err := os.WriteFile(filepath.Join(dir, name), []byte(ep.ChaptersJSON), 0o644); err != nil {
				return "", fmt.Errorf("fixtures: episode %q chapters: %w", ep.GUID, err)
			}
			item.Chapters = &rssPointerDoc{URL: base + "/" + url.PathEscape(name), Type: "application/json+chapters"}
		}
		doc.Items = append(doc.Items, item)
	}

	body, err := xml.MarshalIndent(doc, "", "  ")
	if err != nil {
		return "", fmt.Errorf("fixtures: marshaling feed: %w", err)
	}
	feedPath := filepath.Join(dir, "feed.xml")
	if err := os.WriteFile(feedPath, append([]byte(xml.Header), append(body, '\n')...), 0o644); err != nil {
		return "", fmt.Errorf("fixtures: writing feed: %w", err)
	}
	return feedPath, nil
}

// EarlyFeedDir is the directory EarlyPodcastFeed is written to and served
// from: GeneratePodcastFeed names every feed document feed.xml, so a
// second feed needs a directory of its own.
const EarlyFeedDir = "early"

// EarlyPodcastFeed is a second preset feed whose episode titles sort
// before every other fixture title, so a listing in title order opens on
// its episodes: the shape that once handed an account not following the
// show an empty first page. Its episodes are named apart from the default
// feed's, which gives each its own tone, so no catalog folds two of them
// into one item.
func EarlyPodcastFeed(baseURL string) FeedSpec {
	show := presetShow{
		title:  "The Early Feed",
		host:   "Early Host",
		newest: time.Date(2026, 2, 1, 9, 30, 0, 0, time.UTC),
		lead:   500 * time.Millisecond,
		trail:  500 * time.Millisecond,
	}
	const desc = "An episode that sorts first."
	return show.feed(baseURL, "Two tiny episodes whose titles sort before everything else.",
		show.episode(0, "AAA Before Everything", "wd-early-ep-001", desc, 2*time.Second),
		show.episode(1, "AAA First In Line", "wd-early-ep-002", desc, 3*time.Second),
	)
}

// RelayFeedDir is the directory RelayPodcastFeed is written to and served
// from.
const RelayFeedDir = "relayed"

// relayFeedChapters is the relay feed's episode's Podcasting 2.0 chapters
// document.
const relayFeedChapters = `{"version":"1.2.0","chapters":[{"startTime":0,"title":"Cold open"},{"startTime":2,"title":"Running over"}]}`

// RelayPodcastFeed is a third preset feed, of one chaptered episode whose
// feed declares 3 s for its 5.5 s of audio, past the start of its last
// chapter: a server reading the feed ends that chapter at the declared 3 s.
// No test fetches it, so it is only ever streamed from the feed.
func RelayPodcastFeed(baseURL string) FeedSpec {
	show := presetShow{
		title:  "The Overrun Feed",
		host:   "Overrun Host",
		newest: time.Date(2026, 1, 20, 9, 30, 0, 0, time.UTC),
		lead:   1500 * time.Millisecond,
		trail:  time.Second,
	}
	ep := show.episode(0, "Running Over", "wd-relay-ep-001", "The one that runs past its billing.", 3*time.Second)
	ep.ChaptersJSON = relayFeedChapters
	ep.DeclaredDuration = 3 * time.Second
	return show.feed(baseURL, "One episode that runs longer than its feed says.", ep)
}

// GeneratePresetFeeds writes the three preset feeds under dir: the default
// one at its root, EarlyPodcastFeed in EarlyFeedDir and RelayPodcastFeed in
// RelayFeedDir, each with enclosure URLs under its own directory at
// baseURL. It returns their feed.xml paths in that order.
func GeneratePresetFeeds(dir, baseURL string) ([]string, error) {
	base := strings.TrimRight(baseURL, "/")
	feedPath, err := GeneratePodcastFeed(dir, DefaultPodcastFeed(base), base)
	if err != nil {
		return nil, err
	}
	earlyBase := base + "/" + EarlyFeedDir
	earlyPath, err := GeneratePodcastFeed(filepath.Join(dir, EarlyFeedDir), EarlyPodcastFeed(earlyBase), earlyBase)
	if err != nil {
		return nil, err
	}
	relayBase := base + "/" + RelayFeedDir
	relayPath, err := GeneratePodcastFeed(filepath.Join(dir, RelayFeedDir), RelayPodcastFeed(relayBase), relayBase)
	if err != nil {
		return nil, err
	}
	return []string{feedPath, earlyPath, relayPath}, nil
}

// presetShow is what every episode of one preset feed shares: each is an
// MP3 of a tone between two silences, tagged as the show's, and published
// a day before the one listed above it.
type presetShow struct {
	title, host string
	newest      time.Time
	lead, trail time.Duration
}

// episode is the show's nth episode counting back from the newest.
func (s presetShow) episode(n int, title, guid, desc string, tone time.Duration) EpisodeSpec {
	return EpisodeSpec{
		Title: title,
		GUID:  guid,
		Spec: Spec{
			Name:         guid,
			Codec:        CodecMP3,
			Duration:     tone,
			LeadSilence:  s.lead,
			TrailSilence: s.trail,
			Tags: map[string]string{
				"TITLE":  title,
				"ARTIST": s.host,
				"ALBUM":  s.title,
			},
		},
		PubDate:     s.newest.AddDate(0, 0, -n),
		Description: desc,
	}
}

// feed is the show's feed of episodes, linked to baseURL.
func (s presetShow) feed(baseURL, description string, episodes ...EpisodeSpec) FeedSpec {
	return FeedSpec{
		Title:       s.title,
		Author:      s.host,
		Description: description,
		Link:        strings.TrimRight(baseURL, "/"),
		Episodes:    episodes,
	}
}

// defaultFeedTranscript is episode one's WebVTT transcript: three timed
// cues, enough for a client to prove it fetched and parsed the document.
const defaultFeedTranscript = `WEBVTT

00:00:00.000 --> 00:00:01.500
[intro tone]

00:00:01.500 --> 00:00:03.000
Hello from the fixture feed.

00:00:03.000 --> 00:00:04.500
That is all for today.
`

// defaultFeedChapters is episode one's Podcasting 2.0 chapters document.
const defaultFeedChapters = `{"version":"1.2.0","chapters":[{"startTime":0,"title":"Intro"},{"startTime":2,"title":"Body"}]}`

// DefaultPodcastFeed is the preset feed the end-to-end harness serves:
// four MP3 episodes of silence-padded tones of distinct lengths, on fixed
// descending dates so goldens stay stable, the first with a transcript and
// chapters. The oldest is never fetched by any test, so one test can rely
// on an episode the server has never held. baseURL becomes the channel
// link; the enclosure URLs come from the baseURL passed to
// GeneratePodcastFeed.
func DefaultPodcastFeed(baseURL string) FeedSpec {
	show := presetShow{
		title:  "The Fixture Feed",
		host:   "Fixture Host",
		newest: time.Date(2026, 1, 15, 9, 30, 0, 0, time.UTC),
		lead:   1500 * time.Millisecond,
		trail:  time.Second,
	}
	ep1 := show.episode(0, "Getting Waxy", "wd-fixture-ep-001", "The pilot episode.", 3*time.Second)
	ep1.TranscriptVTT = defaultFeedTranscript
	ep1.ChaptersJSON = defaultFeedChapters
	return show.feed(baseURL, "Four tiny synthesized episodes for WaxDeck tests.",
		ep1,
		show.episode(1, "Second Pressing", "wd-fixture-ep-002", "The difficult second episode.", 4*time.Second),
		show.episode(2, "Deep Grooves", "wd-fixture-ep-003", "The one that found its stride.", 5*time.Second),
		show.episode(3, "Liner Notes", "wd-fixture-ep-004", "The one nobody has fetched.", 2*time.Second),
	)
}
