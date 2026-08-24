package service

import (
	"context"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"golang.org/x/net/html"
)

// Logo discovery for a station whose row names no logo.
//
// Every By-URL station and every directory entry with a blank, SVG, or
// dead favicon arrives with nothing to draw, which is most of the ways a
// station gets added. The dial then draws a monogram forever, because
// nothing ever goes looking. This does the looking, once, at the same
// points the logo is already fetched.
//
// The whole thing is an SSRF surface and is treated as one. The target
// is a host somebody typed into an add-station box, so every request
// here rides l.radioClient(): private addresses refused at dial time
// after DNS resolution (so rebinding does not help), redirects bounded,
// response headers deadlined. The bytes then go through fetchRadioLogo,
// which caps the read and decides the type from the body rather than
// from what the host claimed - the same path a directory-supplied logo
// URL already takes. Nothing here is a new trust boundary; it is the
// existing one reached from one more direction.

const (
	// radioLogoPageMaxBytes bounds the homepage read. Icon declarations
	// live in <head>, so this is generous for the part that matters and
	// still refuses to buffer a page that never ends.
	radioLogoPageMaxBytes = 512 << 10
	// radioLogoCandidates bounds how many URLs one discovery tries. A
	// station that yields nothing in this many attempts is a monogram,
	// and the dial is not waiting on a longer search.
	radioLogoCandidates = 5
	// radioLogoDiscoveryBudget bounds a whole discovery, which the
	// per-fetch timeout alone does not: a homepage read plus five
	// candidate fetches at radioLogoTimeout each is half a minute of
	// held request for one tile, and the client asks for every station,
	// so a cold hub of twelve logo-less stations would start twelve of
	// them at once. Held under the clients' 15-second artwork receive
	// timeout so even a cold first paint settles as an answer rather
	// than an abort.
	radioLogoDiscoveryBudget = 12 * time.Second
)

// discoverRadioLogo finds and fetches a logo for a station whose row
// names none, answering the first candidate that produces a usable
// image.
func (l *Library) discoverRadioLogo(ctx context.Context, homepage, streamURL string) (RadioLogo, error) {
	ctx, cancel := context.WithTimeout(ctx, radioLogoDiscoveryBudget)
	defer cancel()
	candidates := l.radioLogoCandidates(ctx, homepage, streamURL)
	var lastErr error = errNotFound("no logo could be discovered")
	for _, candidate := range candidates {
		logo, err := l.fetchRadioLogo(ctx, candidate)
		if err == nil {
			return logo, nil
		}
		lastErr = err
		// The caller going away ends the search rather than walking the
		// rest of the list against a dead context.
		if ctx.Err() != nil {
			break
		}
	}
	return RadioLogo{}, lastErr
}

// radioLogoCandidates proposes logo URLs, best first: the icons the
// homepage declares, then the conventional /favicon.ico at the
// homepage's origin, then the same at the stream's host.
//
// The stream host is last and is the weakest guess - a station's audio
// often comes off a shared CDN whose favicon belongs to the CDN - but it
// is the only lead a By-URL station with no website gives, and a wrong
// mark is corrected by editing the station.
func (l *Library) radioLogoCandidates(ctx context.Context, homepage, streamURL string) []string {
	var declared iconLinks
	page := parseRadioHomepage(homepage)
	if page != nil {
		declared = l.declaredIcons(ctx, page)
	}
	stream, err := url.Parse(streamURL)
	if err != nil {
		stream = nil
	}
	return orderedLogoCandidates(declared, page, stream)
}

// orderedLogoCandidates interleaves what a page declared with the
// conventional guesses and truncates to the budget.
//
// Assembled in one pass over the whole priority order rather than tier
// by tier as they are discovered, and that is what the truncation makes
// load-bearing: a page declaring several og:image tags would otherwise
// spend every slot on sharing cards before /favicon.ico was ever
// proposed, which is the reverse of the documented order. Split from the
// fetch above so the ordering is testable without a network.
func orderedLogoCandidates(declared iconLinks, page, stream *url.URL) []string {
	var out []string
	seen := map[string]bool{}
	add := func(raw string) {
		if len(out) >= radioLogoCandidates || raw == "" || seen[raw] {
			return
		}
		u, err := url.Parse(raw)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
			return
		}
		seen[raw] = true
		out = append(out, raw)
	}
	for _, icon := range declared.apple {
		add(icon)
	}
	for _, icon := range declared.icons {
		add(icon)
	}
	if page != nil {
		add(page.ResolveReference(&url.URL{Path: "/favicon.ico"}).String())
	}
	if stream != nil && stream.Host != "" &&
		(stream.Scheme == "http" || stream.Scheme == "https") {
		add(stream.ResolveReference(&url.URL{Path: "/favicon.ico"}).String())
	}
	// Last, and only if anything is left: a sharing card is a banner
	// more often than a mark.
	for _, icon := range declared.og {
		add(icon)
	}
	return out
}

// iconLinks is what a page declared, kept in tiers so the caller can
// interleave them with the conventional guesses in true priority order.
type iconLinks struct {
	apple []string
	icons []string
	og    []string
}

// parseRadioHomepage answers the homepage as a URL, or nil when there is
// not a usable one.
func parseRadioHomepage(homepage string) *url.URL {
	if homepage == "" {
		return nil
	}
	u, err := url.Parse(homepage)
	if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
		return nil
	}
	return u
}

// declaredIcons reads the icon URLs a page declares, resolved absolute
// and kept in tiers. A page that will not load answers nothing, which
// leaves the conventional guesses to carry the discovery.
func (l *Library) declaredIcons(ctx context.Context, page *url.URL) iconLinks {
	callCtx, cancel := context.WithTimeout(ctx, radioLogoTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(callCtx, http.MethodGet, page.String(), nil)
	if err != nil {
		return iconLinks{}
	}
	req.Header.Set("User-Agent", "WaxDeck")
	req.Header.Set("Accept", "text/html")
	resp, err := l.radioClient().Do(req)
	if err != nil {
		return iconLinks{}
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return iconLinks{}
	}
	declared, _, _ := strings.Cut(resp.Header.Get("Content-Type"), ";")
	if ct := strings.ToLower(strings.TrimSpace(declared)); ct != "" &&
		ct != "text/html" && ct != "application/xhtml+xml" {
		return iconLinks{}
	}
	// Redirects are followed by the client, so the base for resolving a
	// relative icon is where the page actually came from, not where it
	// was asked for.
	base := page
	if resp.Request != nil && resp.Request.URL != nil {
		base = resp.Request.URL
	}
	return iconLinksIn(io.LimitReader(resp.Body, radioLogoPageMaxBytes), base)
}

// iconLinksIn extracts icon URLs from an HTML document, best first.
//
// Tokenized rather than pattern-matched: the markup real stations ship
// is not reliably well formed, and a regex over it finds the wrong
// attribute of the wrong tag often enough to matter. The tokenizer
// stops at </head>, which is where every declaration this looks for is
// required to be, so a long page costs the head and not the body.
func iconLinksIn(r io.Reader, base *url.URL) iconLinks {
	var found iconLinks
	z := html.NewTokenizer(r)
	for {
		switch z.Next() {
		case html.ErrorToken:
			return found
		case html.EndTagToken:
			if name, _ := z.TagName(); string(name) == "head" {
				return found
			}
		case html.StartTagToken, html.SelfClosingTagToken:
			name, hasAttr := z.TagName()
			tag := string(name)
			if !hasAttr || (tag != "link" && tag != "meta") {
				continue
			}
			attrs := map[string]string{}
			for {
				key, val, more := z.TagAttr()
				attrs[strings.ToLower(string(key))] = string(val)
				if !more {
					break
				}
			}
			switch tag {
			case "link":
				rel := strings.ToLower(strings.TrimSpace(attrs["rel"]))
				href := absoluteAgainst(base, attrs["href"])
				if href == "" {
					continue
				}
				// apple-touch-icon first: it is required to be a square
				// raster of a usable size, where a favicon is routinely
				// a 16px ICO that draws as mush on a station tile.
				switch {
				case strings.Contains(rel, "apple-touch-icon"):
					found.apple = append(found.apple, href)
				case slicesContainsField(rel, "icon"):
					found.icons = append(found.icons, href)
				}
			case "meta":
				// og:image is a last resort: it is the sharing card
				// rather than the mark, so it is often a wide banner.
				// Better than a monogram, worse than an icon.
				prop := strings.ToLower(strings.TrimSpace(attrs["property"]))
				if prop != "og:image" {
					prop = strings.ToLower(strings.TrimSpace(attrs["name"]))
				}
				if prop != "og:image" {
					continue
				}
				if href := absoluteAgainst(base, attrs["content"]); href != "" {
					found.og = append(found.og, href)
				}
			}
		}
	}
}

// slicesContainsField reports whether a space-separated token list holds
// an exact token. `rel="icon"` and `rel="shortcut icon"` both qualify;
// `rel="apple-touch-icon-precomposed"` is handled above and must not
// match here by substring.
func slicesContainsField(list, want string) bool {
	for _, field := range strings.Fields(list) {
		if field == want {
			return true
		}
	}
	return false
}

// absoluteAgainst resolves a possibly relative reference, answering
// empty for anything that is not http or https - which is what drops
// the `data:` icons some pages inline, since there is nothing to fetch.
func absoluteAgainst(base *url.URL, ref string) string {
	ref = strings.TrimSpace(ref)
	if ref == "" {
		return ""
	}
	parsed, err := url.Parse(ref)
	if err != nil {
		return ""
	}
	resolved := base.ResolveReference(parsed)
	if resolved.Scheme != "http" && resolved.Scheme != "https" {
		return ""
	}
	if resolved.Host == "" {
		return ""
	}
	return resolved.String()
}
