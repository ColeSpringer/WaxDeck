package service

import (
	"bytes"
	"cmp"
	"context"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"maps"
	"slices"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/colespringer/waxbin/model"
)

// OPML import and export with folder outlines. The catalog ships flat
// OPML helpers; folders are a WaxDeck concern (they live on the
// per-user subscription row), so both directions are implemented here.

const (
	// folderMaxChars bounds a subscription's folder path, in characters
	// as the spec's maxLength counts them, and folderMaxSegments its depth.
	folderMaxChars    = 512
	folderMaxSegments = 16
	// opmlImportMaxFeeds caps the feeds one import subscribes.
	opmlImportMaxFeeds = 1000
	// opmlMaxDepth caps how deep a document's elements nest, the bound
	// encoding/xml holds its own unmarshalling to.
	opmlMaxDepth = 10_000
	// opmlImportBudget bounds an import's subscribes, which run on when
	// the caller stops waiting.
	opmlImportBudget = 30 * time.Minute
)

// opmlFeed is one parsed feed entry with its folder path (segments
// joined by a slash).
type opmlFeed struct {
	URL    string
	Title  string
	Folder string
}

// subscriptionFolder is the folder a subscribe or a settings write
// stores: its segments, split on a slash, each trimmed, empty ones
// dropped, rejoined. Past folderMaxSegments or folderMaxChars it is
// refused.
func subscriptionFolder(raw string) (string, error) {
	var p folderPath
	p.add(raw)
	if p.full {
		return "", errInvalid(fmt.Sprintf("folder must be at most %d segments and %d characters",
			folderMaxSegments, folderMaxChars))
	}
	return p.String(), nil
}

// folderPath builds a folder path segment by segment the way one is
// stored. Once a segment would take it past folderMaxSegments or
// folderMaxChars it keeps no more, so it holds the longest whole-segment
// prefix that fits.
type folderPath struct {
	buf         []byte
	segs, chars int
	full        bool
}

// folderMark is a folderPath's state to return to.
type folderMark struct {
	n, segs, chars int
	full           bool
}

func (p *folderPath) mark() folderMark { return folderMark{len(p.buf), p.segs, p.chars, p.full} }

func (p *folderPath) reset(m folderMark) {
	p.buf, p.segs, p.chars, p.full = p.buf[:m.n], m.segs, m.chars, m.full
}

// add appends name's segments.
func (p *folderPath) add(name string) {
	for seg := range strings.SplitSeq(name, "/") {
		if p.full {
			return
		}
		seg = strings.TrimSpace(seg)
		if seg == "" {
			continue
		}
		chars := utf8.RuneCountInString(seg)
		if len(p.buf) > 0 {
			chars++
		}
		if p.segs == folderMaxSegments || p.chars+chars > folderMaxChars {
			p.full = true
			return
		}
		if len(p.buf) > 0 {
			p.buf = append(p.buf, '/')
		}
		p.buf = append(p.buf, seg...)
		p.segs++
		p.chars += chars
	}
}

func (p *folderPath) String() string { return string(p.buf) }

// parseOpmlFeeds reads a document's feeds with their folder paths,
// duplicate URLs keeping the first. It keeps one small frame per open
// element over a single folder path, fitted as a stored folder is, so its
// memory follows the document's depth and never the square of it. Past
// opmlImportMaxFeeds feeds it refuses the document.
func parseOpmlFeeds(data []byte) ([]opmlFeed, error) {
	dec := xml.NewDecoder(bytes.NewReader(data))
	dec.Strict = false
	// Feeds in the wild declare charsets the stdlib does not read;
	// passing bytes through keeps ASCII-compatible documents working.
	dec.CharsetReader = func(charset string, input io.Reader) (io.Reader, error) {
		return input, nil
	}
	notOPML := func(err error) error { return &Error{Kind: KindInvalid, Msg: "not an OPML document", Err: err} }
	// What each open element is: the root, the body, a folder outline,
	// or anything whose content is not read (a feed outline's included).
	const (
		inOther = iota
		inRoot
		inBody
		inFolder
	)
	type frame struct {
		kind int
		mark folderMark
	}
	var (
		out    []opmlFeed
		seen   = map[string]bool{}
		folder folderPath
		open   []frame
	)
	for {
		tok, err := dec.Token()
		if err != nil {
			return nil, notOPML(err)
		}
		switch t := tok.(type) {
		case xml.StartElement:
			if len(open) == 0 {
				if t.Name.Local != "opml" {
					return nil, notOPML(fmt.Errorf("expected element type <opml> but have <%s>", t.Name.Local))
				}
				open = append(open, frame{kind: inRoot})
				continue
			}
			if len(open) == opmlMaxDepth {
				return nil, notOPML(errors.New("elements nest too deep"))
			}
			at := frame{kind: inOther, mark: folder.mark()}
			switch parent := open[len(open)-1].kind; {
			case parent == inRoot && t.Name.Local == "body":
				at.kind = inBody
			case (parent == inBody || parent == inFolder) && t.Name.Local == "outline":
				var text, title, xmlURL string
				for _, a := range t.Attr {
					switch a.Name.Local {
					case "text":
						text = a.Value
					case "title":
						title = a.Value
					case "xmlUrl":
						xmlURL = a.Value
					}
				}
				if u := strings.TrimSpace(xmlURL); u != "" {
					if !seen[u] {
						if len(out) == opmlImportMaxFeeds {
							return nil, &Error{Kind: KindInvalid,
								Msg: fmt.Sprintf("an OPML import takes at most %d feeds", opmlImportMaxFeeds)}
						}
						seen[u] = true
						out = append(out, opmlFeed{URL: u, Title: cmp.Or(title, text), Folder: folder.String()})
					}
					break
				}
				at.kind = inFolder
				name := strings.TrimSpace(title)
				if name == "" {
					name = strings.TrimSpace(text)
				}
				folder.add(name)
			}
			open = append(open, at)
		case xml.EndElement:
			closed := open[len(open)-1]
			open = open[:len(open)-1]
			folder.reset(closed.mark)
			if len(open) == 0 {
				return out, nil
			}
		}
	}
}

// ImportOPML subscribes the caller to every feed in the document,
// honoring folder outlines. Per-feed failures are reported, never
// fatal; already-followed feeds are left unchanged. The account's
// permission, and that the server keeps podcasts at all, are checked
// before the document is parsed, and the subscribes keep running for up
// to opmlImportBudget after the caller stops waiting.
func (l *Library) ImportOPML(ctx context.Context, uc *UserCtx, opml []byte) ([]OpmlImportEntry, error) {
	if err := requirePodcastManagement(uc); err != nil {
		return nil, err
	}
	if err := l.requirePodcastsOn(); err != nil {
		return nil, err
	}
	feeds, err := parseOpmlFeeds(opml)
	if err != nil {
		l.log.Debug("reading an OPML import", "err", err)
		return nil, err
	}
	work, cancel := context.WithTimeout(context.WithoutCancel(ctx), opmlImportBudget)
	defer cancel()
	if l.procCtx != nil {
		defer context.AfterFunc(l.procCtx, cancel)()
	}
	out := make([]OpmlImportEntry, 0, len(feeds))
	for _, f := range feeds {
		entry := OpmlImportEntry{FeedURL: f.URL, Title: f.Title}
		sub, _, err := l.Subscribe(work, uc, SubscribeRequest{URL: f.URL, Folder: f.Folder})
		if err != nil {
			entry.Err, entry.Reason = subscribeFailure(err)
		} else {
			entry.Title = sub.Show.Title
			entry.PID = sub.Show.PID
		}
		out = append(out, entry)
	}
	return out, nil
}

// subscribeFailure is what an import entry or an inbox row says about a
// subscribe that failed: the service's own words as a sentence, and the
// feed's reason when it was the feed's, never a wrapped error's text,
// which can name the server's internals.
func subscribeFailure(err error) (sentence, reason string) {
	var se *Error
	if !errors.As(err, &se) || se.Msg == "" {
		return "The feed could not be subscribed.", ""
	}
	msg := se.Msg
	if rest, ok := strings.CutPrefix(msg, "url "); ok {
		msg = "URL " + rest
	} else {
		first, size := utf8.DecodeRuneInString(msg)
		msg = string(unicode.ToUpper(first)) + msg[size:]
	}
	if !strings.HasSuffix(msg, ".") {
		msg += "."
	}
	return msg, FeedFailureReason(err)
}

// ExportOPML renders the caller's subscriptions as OPML 2.0 with
// folder paths as nested outlines, each feed under the URL the caller
// subscribed it by, a private show's included: that address is the
// caller's own, and a stored login is never written. Manual shows have no
// feed to export.
func (l *Library) ExportOPML(ctx context.Context, uc *UserCtx) ([]byte, error) {
	rows, err := l.db.SubscriptionsByUser(ctx, uc.ID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if !l.podcastsVisible(ctx, uc) {
		rows = nil
	}
	byFolder := map[string][]opmlFeed{}
	for _, row := range rows {
		if row.FeedURL == "" {
			continue
		}
		pod, err := l.lib.Podcasts().Get(ctx, model.PID(row.ShowPID))
		if err != nil || pod.SourceType == model.SourceManual {
			continue
		}
		byFolder[row.Folder] = append(byFolder[row.Folder], opmlFeed{
			URL: row.FeedURL, Title: pod.Title, Folder: row.Folder,
		})
	}
	return renderOPML(byFolder)
}

// renderOPML writes the export of feeds by the folder they were stored
// under, each folder fitted as a stored one is written.
func renderOPML(byFolder map[string][]opmlFeed) ([]byte, error) {
	root := &opmlFolder{}
	for stored, feeds := range byFolder {
		var path folderPath
		path.add(stored)
		node := root.at(path.String())
		node.feeds = append(node.feeds, feeds...)
	}
	var w opmlWriter
	w.document(root)
	if w.err != nil {
		return nil, &Error{Kind: KindInternal, Err: w.err}
	}
	return w.buf.Bytes(), nil
}

// opmlFolder is one folder of the export, built once from every stored
// folder path, each fitted as a stored folder is written.
type opmlFolder struct {
	children map[string]*opmlFolder
	feeds    []opmlFeed
}

// at is the folder path names, making the ones missing on the way.
func (f *opmlFolder) at(path string) *opmlFolder {
	if path == "" {
		return f
	}
	for seg := range strings.SplitSeq(path, "/") {
		child := f.children[seg]
		if child == nil {
			child = &opmlFolder{}
			if f.children == nil {
				f.children = map[string]*opmlFolder{}
			}
			f.children[seg] = child
		}
		f = child
	}
	return f
}

// opmlWriter writes the export as encoding/xml indents a document, two
// spaces a level.
type opmlWriter struct {
	buf bytes.Buffer
	enc *xml.Encoder
	err error
}

func (w *opmlWriter) document(root *opmlFolder) {
	w.buf.WriteString(xml.Header)
	w.enc = xml.NewEncoder(&w.buf)
	w.start(0, "opml", "version", "2.0")
	w.start(1, "head")
	w.start(2, "title")
	w.token(xml.CharData("WaxDeck subscriptions"))
	w.end(-1, "title")
	w.end(1, "head")
	w.start(1, "body")
	if len(root.children) == 0 && len(root.feeds) == 0 {
		w.end(-1, "body")
	} else {
		w.outlines(root, 2)
		w.end(1, "body")
	}
	w.end(0, "opml")
	if w.err == nil {
		w.err = w.enc.Flush()
	}
	w.buf.WriteByte('\n')
}

// outlines writes a folder's own: its child folders first, by name, then
// its feeds, by title.
func (w *opmlWriter) outlines(f *opmlFolder, depth int) {
	for _, name := range slices.Sorted(maps.Keys(f.children)) {
		w.start(depth, "outline", "text", name, "title", name)
		w.outlines(f.children[name], depth+1)
		w.end(depth, "outline")
	}
	slices.SortStableFunc(f.feeds, func(a, b opmlFeed) int {
		return cmp.Or(strings.Compare(a.Title, b.Title), strings.Compare(a.URL, b.URL))
	})
	for _, feed := range f.feeds {
		title := clipFeedTitle(feed.Title)
		attrs := []string{"text", title}
		if title != "" {
			attrs = append(attrs, "title", title)
		}
		w.start(depth, "outline", append(attrs, "type", "rss", "xmlUrl", feed.URL)...)
		w.end(-1, "outline")
	}
}

// start opens an element on a line of its own at depth, the document's
// first element on the first line; attrs alternate name and value.
func (w *opmlWriter) start(depth int, name string, attrs ...string) {
	if depth > 0 {
		w.indent(depth)
	}
	el := xml.StartElement{Name: xml.Name{Local: name}}
	for i := 0; i+1 < len(attrs); i += 2 {
		el.Attr = append(el.Attr, xml.Attr{Name: xml.Name{Local: attrs[i]}, Value: attrs[i+1]})
	}
	w.token(el)
}

// end closes an element, on a line of its own at depth, or right after
// its content for a negative depth.
func (w *opmlWriter) end(depth int, name string) {
	if depth >= 0 {
		w.indent(depth)
	}
	w.token(xml.EndElement{Name: xml.Name{Local: name}})
}

func (w *opmlWriter) indent(depth int) {
	w.token(xml.CharData("\n" + strings.Repeat("  ", depth)))
}

func (w *opmlWriter) token(t xml.Token) {
	if w.err == nil {
		w.err = w.enc.EncodeToken(t)
	}
}
