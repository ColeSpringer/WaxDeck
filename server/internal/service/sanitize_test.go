package service

import (
	"strings"
	"testing"
	"unicode/utf8"
)

func TestSanitizeShowNotesStripsActiveContent(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name    string
		in      string
		mustNot []string
		must    []string
	}{
		{
			name:    "script and handler",
			in:      `<p onclick="x()">hi</p><script>alert(1)</script>`,
			mustNot: []string{"script", "onclick", "alert"},
			must:    []string{"<p>hi</p>"},
		},
		{
			name:    "javascript scheme",
			in:      `<a href="javascript:alert(1)">x</a>`,
			mustNot: []string{"javascript"},
		},
		{
			name:    "iframe and style",
			in:      `<iframe src="https://evil.example"></iframe><style>p{}</style><p>ok</p>`,
			mustNot: []string{"iframe", "style"},
			must:    []string{"<p>ok</p>"},
		},
		{
			name: "links forced safe",
			in:   `<a href="https://example.com/x">x</a>`,
			must: []string{`rel="nofollow noreferrer noopener"`, `target="_blank"`},
		},
		{
			name: "structure survives",
			in:   `<ul><li>one</li><li><strong>two</strong></li></ul><img src="https://example.com/a.jpg" alt="art">`,
			must: []string{"<ul>", "<li>one</li>", "<strong>two</strong>", `src="https://example.com/a.jpg"`},
		},
		{
			name: "plain text passes",
			in:   "just words < brackets",
			must: []string{"just words"},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			out := sanitizeShowNotes(tc.in)
			for _, bad := range tc.mustNot {
				if strings.Contains(strings.ToLower(out), bad) {
					t.Fatalf("sanitized output still contains %q: %s", bad, out)
				}
			}
			for _, good := range tc.must {
				if !strings.Contains(out, good) {
					t.Fatalf("sanitized output lost %q: %s", good, out)
				}
			}
		})
	}
}

// A feed's description as text alone: tags and what script-like elements
// hold dropped, words either side of a block or a break kept apart and
// inline markup joined, entities decoded, whitespace one space, control
// characters gone. Text that only looks like markup is text.
func TestFeedPlainText(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{
		`<p>Notes for <b>episode 1</b></p><script>alert(1)</script>`:               "Notes for episode 1",
		`<p>One</p><p>Two</p>Three<br>Four<br/>Five<ul><li>a</li><li>b</li></ul>c`: "One Two Three Four Five a b c",
		`Visit <a href="https://example.com/x" rel="nofollow">our site</a>.`:       "Visit our site.",
		`Fish &amp; Chips &lt;3 &nbsp; and&#160;more &eacute;t&eacute;`:            "Fish & Chips <3 and more \u00e9t\u00e9",
		"  spaced\n\n\tout  ": "spaced out",
		`<style>p{color:red}</style><!-- a note --><noscript>x</noscript><p>kept</p>`: "kept",
		"just words < brackets, a<3 and Vec&lt;T&gt;":                                 "just words < brackets, a<3 and Vec<T>",
		"bell\x07 and nul\x00 gone":                                                   "bell and nul gone",
		"":                                                                            "",
		" \n ":                                                                        "",
		"<p></p><br>":                                                                 "",
		`<script/>alert(1)</script>After`:                                             "After",
		`<iframe src="x" width="560"/>fallback</iframe><p>Episode <em>notes</em></p>`: "Episode notes",
		`<style/>.x{color:red}</style>After`:                                          "After",
		`<object data="x.swf"/><p>Episode notes</p>`:                                  "Episode notes",
		`<template/>kept`: "kept",
		"a\u202eevil\u202c b\u2067c\u2069 \ufeffd\u200be": "aevil bc de",
		"family \U0001F468\u200d\U0001F469 joined":        "family \U0001F468\u200d\U0001F469 joined",
	} {
		if got := feedPlainText(in); got != want {
			t.Errorf("feedPlainText(%q) = %q, want %q", in, got, want)
		}
	}
}

// The text is cut as a feed title is, to its first thousand characters,
// never partway through one and never on a trailing space.
func TestFeedPlainTextIsCutLikeATitle(t *testing.T) {
	t.Parallel()
	got := feedPlainText(strings.Repeat("<p>\u00e9\u00e9n</p>", 5000))
	if n := utf8.RuneCountInString(got); n > feedTitleMaxChars || n < feedTitleMaxChars-1 || !utf8.ValidString(got) {
		t.Fatalf("a long description reads %d characters (valid %v), want the first %d", n, utf8.ValidString(got), feedTitleMaxChars)
	}
	if want := strings.TrimRight(clipFeedTitle(strings.Repeat("\u00e9\u00e9n ", 1000)), " "); got != want {
		t.Errorf("the cut = %q..., want %q...", got[:40], want[:40])
	}
	if strings.HasSuffix(got, " ") || strings.HasPrefix(got, " ") {
		t.Errorf("the cut keeps an edge space: %q", got[len(got)-10:])
	}
}
