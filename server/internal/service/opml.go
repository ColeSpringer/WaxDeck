package service

import (
	"bytes"
	"context"
	"encoding/xml"
	"io"
	"sort"
	"strings"

	"github.com/colespringer/waxbin/model"
)

// OPML import and export with folder outlines. The catalog ships flat
// OPML helpers; folders are a WaxDeck concern (they live on the
// per-user subscription row), so both directions are implemented here.

// opmlOutline is the recursive OPML outline node: outlines with an
// xmlUrl are feeds, outlines without one are folders.
type opmlOutline struct {
	Text     string        `xml:"text,attr"`
	Title    string        `xml:"title,attr,omitempty"`
	Type     string        `xml:"type,attr,omitempty"`
	XMLURL   string        `xml:"xmlUrl,attr,omitempty"`
	Outlines []opmlOutline `xml:"outline,omitempty"`
}

type opmlDoc struct {
	XMLName xml.Name `xml:"opml"`
	Version string   `xml:"version,attr"`
	Head    struct {
		Title string `xml:"title,omitempty"`
	} `xml:"head"`
	Body struct {
		Outlines []opmlOutline `xml:"outline"`
	} `xml:"body"`
}

// opmlFeed is one parsed feed entry with its folder path (segments
// joined by a slash).
type opmlFeed struct {
	URL    string
	Title  string
	Folder string
}

// parseOpmlFeeds walks the outline tree, collecting feeds with their
// folder paths. Duplicate URLs keep the first occurrence.
func parseOpmlFeeds(data []byte) ([]opmlFeed, error) {
	dec := xml.NewDecoder(bytes.NewReader(data))
	dec.Strict = false
	// Feeds in the wild declare charsets the stdlib does not read;
	// passing bytes through keeps ASCII-compatible documents working.
	dec.CharsetReader = func(charset string, input io.Reader) (io.Reader, error) {
		return input, nil
	}
	var doc opmlDoc
	if err := dec.Decode(&doc); err != nil {
		return nil, errInvalid("not an OPML document: " + err.Error())
	}
	var out []opmlFeed
	seen := map[string]bool{}
	var walk func(nodes []opmlOutline, folder []string)
	walk = func(nodes []opmlOutline, folder []string) {
		for _, n := range nodes {
			if u := strings.TrimSpace(n.XMLURL); u != "" {
				if !seen[u] {
					seen[u] = true
					title := n.Title
					if title == "" {
						title = n.Text
					}
					out = append(out, opmlFeed{URL: u, Title: title, Folder: strings.Join(folder, "/")})
				}
				continue
			}
			name := strings.TrimSpace(n.Title)
			if name == "" {
				name = strings.TrimSpace(n.Text)
			}
			next := folder
			if name != "" {
				next = append(append([]string{}, folder...), name)
			}
			walk(n.Outlines, next)
		}
	}
	walk(doc.Body.Outlines, nil)
	return out, nil
}

// ImportOPML subscribes the caller to every feed in the document,
// honoring folder outlines. Per-feed failures are reported, never
// fatal; already-followed feeds are left unchanged.
func (l *Library) ImportOPML(ctx context.Context, uc *UserCtx, opml []byte) ([]OpmlImportEntry, error) {
	feeds, err := parseOpmlFeeds(opml)
	if err != nil {
		return nil, err
	}
	out := make([]OpmlImportEntry, 0, len(feeds))
	for _, f := range feeds {
		entry := OpmlImportEntry{FeedURL: f.URL, Title: f.Title}
		sub, _, err := l.Subscribe(ctx, uc, SubscribeRequest{URL: f.URL, Folder: f.Folder})
		if err != nil {
			entry.Err = err.Error()
		} else {
			entry.Title = sub.Show.Title
			entry.PID = sub.Show.PID
		}
		out = append(out, entry)
	}
	return out, nil
}

// ExportOPML renders the caller's subscriptions as OPML 2.0 with
// folder paths as nested outlines. Private shows are omitted for every
// exporter (their URLs are secrets), and manual shows have no feed to
// export.
func (l *Library) ExportOPML(ctx context.Context, uc *UserCtx) ([]byte, error) {
	rows, err := l.db.SubscriptionsByUser(ctx, uc.ID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	byFolder := map[string][]opmlFeed{}
	for _, row := range rows {
		pod, err := l.lib.Podcasts().Get(ctx, model.PID(row.ShowPID))
		if err != nil {
			continue
		}
		if l.showIsPrivate(ctx, pod) || pod.SourceType == model.SourceManual || pod.FeedURL == "" {
			continue
		}
		byFolder[row.Folder] = append(byFolder[row.Folder], opmlFeed{
			URL: pod.FeedURL, Title: pod.Title, Folder: row.Folder,
		})
	}
	for _, feeds := range byFolder {
		sort.Slice(feeds, func(i, j int) bool { return feeds[i].Title < feeds[j].Title })
	}

	doc := opmlDoc{Version: "2.0"}
	doc.Head.Title = "WaxDeck subscriptions"
	doc.Body.Outlines = renderOpmlLevel("", byFolder)

	var buf bytes.Buffer
	buf.WriteString(xml.Header)
	enc := xml.NewEncoder(&buf)
	enc.Indent("", "  ")
	if err := enc.Encode(doc); err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	buf.WriteByte('\n')
	return buf.Bytes(), nil
}

// renderOpmlLevel renders one folder level: child folders first (their
// subtrees built recursively), then this level's own feeds.
func renderOpmlLevel(prefix string, byFolder map[string][]opmlFeed) []opmlOutline {
	childNames := map[string]bool{}
	for path := range byFolder {
		rest := path
		if prefix != "" {
			var ok bool
			rest, ok = strings.CutPrefix(path, prefix+"/")
			if !ok {
				continue
			}
		}
		if rest == "" {
			continue
		}
		name := rest
		if i := strings.IndexByte(rest, '/'); i >= 0 {
			name = rest[:i]
		}
		childNames[name] = true
	}
	ordered := make([]string, 0, len(childNames))
	for name := range childNames {
		ordered = append(ordered, name)
	}
	sort.Strings(ordered)

	var out []opmlOutline
	for _, name := range ordered {
		full := name
		if prefix != "" {
			full = prefix + "/" + name
		}
		node := opmlOutline{Text: name, Title: name}
		node.Outlines = renderOpmlLevel(full, byFolder)
		out = append(out, node)
	}
	for _, f := range byFolder[prefix] {
		out = append(out, opmlOutline{Text: f.Title, Title: f.Title, Type: "rss", XMLURL: f.URL})
	}
	return out
}
