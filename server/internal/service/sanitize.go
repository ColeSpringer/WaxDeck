package service

import (
	"strings"
	"sync"

	"github.com/microcosm-cc/bluemonday"
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
func sanitizeShowNotes(html string) string {
	if strings.TrimSpace(html) == "" {
		return ""
	}
	return strings.TrimSpace(showNotesPolicy().Sanitize(html))
}
