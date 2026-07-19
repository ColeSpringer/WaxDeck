package gpodder

// Wire shapes and format helpers: the JSON DTOs the protocol
// exchanges, the three subscription list encodings (json, txt, opml),
// and the URL sanitizer the upload endpoints share.

import (
	"bytes"
	"encoding/json"
	"encoding/xml"
	"errors"
	"io"
	"net/url"
	"strconv"
	"strings"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// deviceJSON is one row of the device listing.
type deviceJSON struct {
	ID            string `json:"id"`
	Caption       string `json:"caption"`
	Type          string `json:"type"`
	Subscriptions int    `json:"subscriptions"`
}

// uploadAckJSON acknowledges an upload. UpdateURLs is always present,
// one [original, sanitized] pair per rewritten URL.
type uploadAckJSON struct {
	Timestamp  int64       `json:"timestamp"`
	UpdateURLs [][2]string `json:"update_urls"`
}

// subDeltaJSON is the subscription-change download.
type subDeltaJSON struct {
	Add       []string `json:"add"`
	Remove    []string `json:"remove"`
	Timestamp int64    `json:"timestamp"`
}

// episodeActionJSON is one episode action, upload and download alike.
type episodeActionJSON struct {
	Podcast   string `json:"podcast"`
	Episode   string `json:"episode"`
	Action    string `json:"action"`
	Device    string `json:"device,omitempty"`
	Timestamp string `json:"timestamp,omitempty"`
	Started   *int64 `json:"started,omitempty"`
	Position  *int64 `json:"position,omitempty"`
	Total     *int64 `json:"total,omitempty"`
}

// actionsPageJSON is the episode-action download.
type actionsPageJSON struct {
	Actions   []episodeActionJSON `json:"actions"`
	Timestamp int64               `json:"timestamp"`
}

// actionJSON renders a stored action back onto the wire; empty device
// and timestamp fields and unset integers stay omitted.
func actionJSON(a wdb.GpodderAction) episodeActionJSON {
	return episodeActionJSON{
		Podcast: a.PodcastURL, Episode: a.EpisodeURL, Action: a.Action,
		Device: a.DeviceID, Timestamp: a.ActionTS,
		Started: a.StartedSec, Position: a.PositionSec, Total: a.TotalSec,
	}
}

// splitExt splits a path segment on its last dot: "phone.json" gives
// ("phone", "json"). Device ids may themselves contain dots, so only
// the last one is the format suffix.
func splitExt(seg string) (base, ext string) {
	i := strings.LastIndexByte(seg, '.')
	if i < 0 {
		return seg, ""
	}
	return seg[:i], seg[i+1:]
}

// knownFormat reports whether the suffix names a subscription list
// encoding this surface speaks.
func knownFormat(format string) bool {
	return format == "json" || format == "txt" || format == "opml"
}

// parseSince reads the since cursor: absent means everything, and
// anything but a non-negative integer is malformed.
func parseSince(s string) (int64, bool) {
	if s == "" {
		return 0, true
	}
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil || n < 0 {
		return 0, false
	}
	return n, true
}

// normalizeDeviceType folds unknown device types to "other", per the
// protocol's enum.
func normalizeDeviceType(t string) string {
	switch t {
	case "desktop", "laptop", "mobile", "server", "other":
		return t
	}
	return "other"
}

// sanitizeFeedURL trims whitespace and rejects anything that is not an
// absolute http or https URL, folding it to the empty string; callers
// report the rewrite through update_urls and drop the entry.
func sanitizeFeedURL(raw string) string {
	s := strings.TrimSpace(raw)
	u, err := url.Parse(s)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return ""
	}
	return s
}

// parseSubscriptionList decodes a full-list upload body in the named
// format into feed URLs.
func parseSubscriptionList(body []byte, format string) ([]string, error) {
	switch format {
	case "json":
		if len(bytes.TrimSpace(body)) == 0 {
			return nil, nil
		}
		var urls []string
		if err := json.Unmarshal(body, &urls); err != nil {
			return nil, err
		}
		return urls, nil
	case "txt":
		var urls []string
		for _, line := range strings.Split(string(body), "\n") {
			if line = strings.TrimSpace(line); line != "" {
				urls = append(urls, line)
			}
		}
		return urls, nil
	case "opml":
		return parseOpmlURLs(body)
	}
	return nil, errors.New("unknown format " + format)
}

// parseOpmlURLs walks an OPML document collecting every outline's
// xmlUrl. Structure beyond that (folders, titles) is ignored; this
// surface only syncs the flat URL set.
func parseOpmlURLs(body []byte) ([]string, error) {
	dec := xml.NewDecoder(bytes.NewReader(body))
	dec.Strict = false
	// Feeds in the wild declare charsets the stdlib does not read;
	// passing bytes through keeps ASCII-compatible documents working.
	dec.CharsetReader = func(charset string, input io.Reader) (io.Reader, error) {
		return input, nil
	}
	var urls []string
	for {
		tok, err := dec.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}
		start, ok := tok.(xml.StartElement)
		if !ok || start.Name.Local != "outline" {
			continue
		}
		for _, attr := range start.Attr {
			if strings.EqualFold(attr.Name.Local, "xmlUrl") {
				if u := strings.TrimSpace(attr.Value); u != "" {
					urls = append(urls, u)
				}
			}
		}
	}
	return urls, nil
}

// renderOPML builds a minimal flat OPML 2.0 document over the feed
// URLs. The first-party export carries titles and folders; gpodder
// clients read only xmlUrl, so the URL doubles as the text.
func renderOPML(urls []string) []byte {
	type outline struct {
		Text   string `xml:"text,attr"`
		Type   string `xml:"type,attr"`
		XMLURL string `xml:"xmlUrl,attr"`
	}
	type opmlDoc struct {
		XMLName xml.Name `xml:"opml"`
		Version string   `xml:"version,attr"`
		Head    struct {
			Title string `xml:"title"`
		} `xml:"head"`
		Body struct {
			Outlines []outline `xml:"outline"`
		} `xml:"body"`
	}
	doc := opmlDoc{Version: "2.0"}
	doc.Head.Title = "WaxDeck subscriptions"
	for _, u := range urls {
		doc.Body.Outlines = append(doc.Body.Outlines, outline{Text: u, Type: "rss", XMLURL: u})
	}
	out, err := xml.MarshalIndent(doc, "", "  ")
	if err != nil {
		// Marshaling a static struct cannot fail in practice; degrade
		// to an empty document rather than panic.
		return []byte(xml.Header + `<opml version="2.0"/>`)
	}
	return append([]byte(xml.Header), out...)
}
