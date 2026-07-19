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
// namespace.
type EpisodeSpec struct {
	Title         string
	GUID          string
	Spec          Spec
	PubDate       time.Time
	Description   string
	TranscriptVTT string
	ChaptersJSON  string
}

// FeedSpec describes one podcast feed: channel fields plus its episodes.
// Link is the channel's home URL; empty falls back to the base URL the
// feed is generated against.
type FeedSpec struct {
	Title       string
	Author      string
	Description string
	Link        string
	Episodes    []EpisodeSpec
}

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
	XMLName      xml.Name  `xml:"rss"`
	Version      string    `xml:"version,attr"`
	ITunesNS     string    `xml:"xmlns:itunes,attr"`
	PodcastNS    string    `xml:"xmlns:podcast,attr"`
	ChannelTitle string    `xml:"channel>title"`
	ChannelLink  string    `xml:"channel>link"`
	ChannelDesc  string    `xml:"channel>description"`
	Author       string    `xml:"channel>itunes:author"`
	PodcastGUID  string    `xml:"channel>podcast:guid"`
	Items        []rssItem `xml:"channel>item"`
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
		PodcastNS:    "https://podcastindex.org/namespace/1.0",
		ChannelTitle: feed.Title,
		ChannelLink:  feed.Link,
		ChannelDesc:  feed.Description,
		Author:       feed.Author,
		PodcastGUID:  channelGUID(feed.Title),
	}
	if doc.ChannelLink == "" {
		doc.ChannelLink = base
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
		total := s.LeadSilence + s.Duration + s.TrailSilence
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
			Duration: fmt.Sprintf("%d", int64(total/time.Second)),
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
// three MP3 episodes with silence-padded audio and distinct tone lengths
// (so essence dedup cannot merge them), descending publish dates from a
// fixed base so goldens stay stable, and a transcript plus chapters
// document on the first episode. baseURL becomes the channel link; the
// enclosure URLs come from the baseURL passed to GeneratePodcastFeed.
func DefaultPodcastFeed(baseURL string) FeedSpec {
	base := time.Date(2026, 1, 15, 9, 30, 0, 0, time.UTC)
	episode := func(n int, title, guid, desc string, tone time.Duration) EpisodeSpec {
		return EpisodeSpec{
			Title: title,
			GUID:  guid,
			Spec: Spec{
				Name:         guid,
				Codec:        CodecMP3,
				Duration:     tone,
				LeadSilence:  1500 * time.Millisecond,
				TrailSilence: time.Second,
				Tags: map[string]string{
					"TITLE":  title,
					"ARTIST": "Fixture Host",
					"ALBUM":  "The Fixture Feed",
				},
			},
			PubDate:     base.AddDate(0, 0, -n),
			Description: desc,
		}
	}
	ep1 := episode(0, "Getting Waxy", "wd-fixture-ep-001", "The pilot episode.", 3*time.Second)
	ep1.TranscriptVTT = defaultFeedTranscript
	ep1.ChaptersJSON = defaultFeedChapters
	return FeedSpec{
		Title:       "The Fixture Feed",
		Author:      "Fixture Host",
		Description: "Three tiny synthesized episodes for WaxDeck tests.",
		Link:        strings.TrimRight(baseURL, "/"),
		Episodes: []EpisodeSpec{
			ep1,
			episode(1, "Second Pressing", "wd-fixture-ep-002", "The difficult second episode.", 4*time.Second),
			episode(2, "Deep Grooves", "wd-fixture-ep-003", "The one that found its stride.", 5*time.Second),
		},
	}
}
