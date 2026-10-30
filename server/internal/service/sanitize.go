package service

import (
	"strings"
	"sync"
	"unicode"

	"github.com/microcosm-cc/bluemonday"
	"golang.org/x/net/html"
)

// showNotesPolicy is the allowlist for feed-controlled HTML (show
// descriptions, episode show notes). Feeds are hostile input rendered
// into every client's UI, so this is deny-by-default: structural and
// inline text markup, links, and images survive; scripts, styles,
// frames, forms, event handlers, and every URL scheme except http,
// https, and mailto are stripped. Links are forced to carry
// rel="nofollow noopener" and target="_blank" so a feed can never
// window-hijack the app that renders it.
var showNotesPolicy = sync.OnceValue(func() *bluemonday.Policy {
	p := bluemonday.NewPolicy()
	p.AllowStandardURLs()
	p.AllowElements(
		"p", "br", "hr", "span", "div",
		"b", "strong", "i", "em", "u", "s", "small", "sub", "sup", "mark",
		"h1", "h2", "h3", "h4", "h5", "h6",
		"ul", "ol", "li", "dl", "dt", "dd",
		"blockquote", "pre", "code",
		"table", "thead", "tbody", "tr", "th", "td",
		"figure", "figcaption",
	)
	p.AllowAttrs("href").OnElements("a")
	p.AllowAttrs("src", "alt", "title", "width", "height").OnElements("img")
	p.AllowAttrs("start").OnElements("ol")
	p.RequireNoFollowOnLinks(true)
	p.RequireNoReferrerOnLinks(true)
	p.AddTargetBlankToFullyQualifiedLinks(true)
	return p
})

// sanitizeShowNotes reduces feed-controlled HTML to the allowlist. The
// input may also be plain text (many feeds ship bare paragraphs);
// bluemonday passes text through and escapes stray angle brackets, so
// the output is always safe to render as HTML.
func sanitizeShowNotes(s string) string {
	if strings.TrimSpace(s) == "" {
		return ""
	}
	return strings.TrimSpace(showNotesPolicy().Sanitize(s))
}

// plainTextSkipped are the elements whose content is no text a reader
// sees, true for those the tokenizer reads to their end tag as raw text
// even when written self-closing, as a browser does.
var plainTextSkipped = map[string]bool{
	"script": true, "style": true, "noscript": true, "title": true,
	"iframe": true, "noembed": true, "noframes": true,
	"template": false, "object": false,
}

// invisibleFormat is a character that changes how text reads without
// being seen: the direction overrides, embeddings and isolates, which can
// turn words around on the page, a stray byte-order mark and the zero
// width space. Joiners stay, for the emoji and scripts that need them.
func invisibleFormat(r rune) bool {
	return (r >= '\u202a' && r <= '\u202e') || (r >= '\u2066' && r <= '\u2069') || r == '\ufeff' || r == '\u200b'
}

// plainTextBreaks are the elements that keep the words either side of
// them apart; inline markup joins them, as it does on the page.
var plainTextBreaks = map[string]bool{
	"br": true, "hr": true, "p": true, "div": true, "blockquote": true, "pre": true,
	"ul": true, "ol": true, "li": true, "dl": true, "dt": true, "dd": true,
	"h1": true, "h2": true, "h3": true, "h4": true, "h5": true, "h6": true,
	"table": true, "caption": true, "thead": true, "tbody": true, "tfoot": true, "tr": true, "th": true, "td": true,
	"section": true, "article": true, "aside": true, "header": true, "footer": true, "nav": true, "main": true,
	"figure": true, "figcaption": true, "address": true, "details": true, "summary": true,
}

// feedPlainText is feed-given markup as the text a reader sees, for a
// surface that carries text only: tags, comments and the content of
// non-text elements dropped, entities decoded, every run of whitespace one
// space, control and invisible format characters gone, cut as a feed
// title is.
func feedPlainText(s string) string {
	z := html.NewTokenizer(strings.NewReader(s))
	var b strings.Builder
	n, gap, skip := 0, false, 0
	// Read to one character past the cut, so the cut is clipFeedTitle's own.
read:
	for n <= feedTitleMaxChars {
		switch tt := z.Next(); tt {
		case html.ErrorToken:
			break read
		case html.TextToken:
			if skip > 0 {
				continue
			}
			for _, r := range string(z.Text()) {
				switch {
				case n > feedTitleMaxChars:
					break read
				case unicode.IsSpace(r):
					gap = true
				case unicode.IsControl(r), invisibleFormat(r):
				default:
					if gap && n > 0 {
						b.WriteByte(' ')
						n++
					}
					gap = false
					b.WriteRune(r)
					n++
				}
			}
		case html.StartTagToken, html.EndTagToken, html.SelfClosingTagToken:
			name, _ := z.TagName()
			tag := string(name)
			raw, skipped := plainTextSkipped[tag]
			switch {
			case skipped && (tt == html.StartTagToken || tt == html.SelfClosingTagToken && raw):
				skip++
			case skipped && tt == html.EndTagToken && skip > 0:
				skip--
			}
			if plainTextBreaks[tag] {
				gap = true
			}
		}
	}
	return strings.TrimRight(clipFeedTitle(b.String()), " ")
}
