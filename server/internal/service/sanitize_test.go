package service

import (
	"strings"
	"testing"
)

func TestSanitizeShowNotesStripsActiveContent(t *testing.T) {
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
