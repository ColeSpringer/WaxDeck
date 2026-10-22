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
	"math"
	"net/url"
	"strconv"
	"strings"
	"time"

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
// An upload's guid is not kept; a download names one only where the
// server made the action up and named the episode by a bare link.
type episodeActionJSON struct {
	Podcast   string    `json:"podcast"`
	Episode   string    `json:"episode"`
	GUID      looseGUID `json:"guid,omitempty"`
	Action    string    `json:"action"`
	Device    string    `json:"device,omitempty"`
	Timestamp string    `json:"timestamp,omitempty"`
	Started   *int64    `json:"started,omitempty"`
	Position  *int64    `json:"position,omitempty"`
	Total     *int64    `json:"total,omitempty"`
}

// looseGUID is an action's guid. One that is not a string reads as none
// rather than costing the upload its action, the guid being kept nowhere.
type looseGUID string

func (g *looseGUID) UnmarshalJSON(raw []byte) error {
	var s string
	if json.Unmarshal(raw, &s) == nil {
		*g = looseGUID(s)
	}
	return nil
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
		Podcast: a.PodcastURL, Episode: a.EpisodeURL, GUID: looseGUID(a.GUID), Action: a.Action,
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

// maxSince is the latest second a cursor can name and still be turned
// into the nanoseconds a stamp is kept in.
const maxSince = math.MaxInt64/int64(time.Second) - 2

// parseSince reads the since cursor: absent means everything, anything
// but a non-negative integer is malformed, and a second past any this
// server can stamp is the latest it can.
func parseSince(s string) (int64, bool) {
	if s == "" {
		return 0, true
	}
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil || n < 0 {
		return 0, false
	}
	return min(n, maxSince), true
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

// The most an upload carries. A subscription upload names at most
// maxUploadFeeds feeds, adds and removes together: a large library is a
// few hundred, and each feed new to the server costs a fetch inside the
// request. An episode upload carries at most maxUploadActions actions:
// AntennaPod sends 30 at a time, gPodder its queue since the last sync.
// A feed or episode URL runs to maxURLLen bytes, as browsers keep them,
// and a play's start, position or length to maxPlaySeconds, thirty days,
// past any episode's.
const (
	maxUploadFeeds   = 2000
	maxUploadActions = 10_000
	maxURLLen        = 2048
	maxPlaySeconds   = 30 * 24 * 60 * 60
)

// sanitizeFeedURL trims whitespace and rejects anything that is not an
// absolute http or https URL naming a host, of a sane length, folding it
// to the empty string; callers report the rewrite through update_urls and
// drop the entry. A port or credentials without a host name no host.
func sanitizeFeedURL(raw string) string {
	s := strings.TrimSpace(raw)
	if len(s) > maxURLLen {
		return ""
	}
	u, err := url.Parse(s)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" {
		return ""
	}
	return s
}

// feedList is an uploaded list of feed URLs as the service takes it:
// sanitized, without what is not an http(s) URL, each spelling once.
func feedList(raw []string) []string {
	out := make([]string, 0, len(raw))
	seen := make(map[string]bool, len(raw))
	for _, r := range raw {
		if s := sanitizeFeedURL(r); s != "" && !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
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
