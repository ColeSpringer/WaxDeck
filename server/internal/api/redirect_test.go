package api

import "testing"

func TestSafeRedirectPath(t *testing.T) {
	good := []string{
		"/",
		"/library",
		"/a/b/c",
		"/search?q=x&page=2",
		"/path#section",
		"/items/tr-01JZX5N8QW3F4V9T2B7KD3M9R6",
	}
	for _, p := range good {
		if !safeRedirectPath(p) {
			t.Errorf("safeRedirectPath(%q) = false, want true", p)
		}
	}
	bad := []string{
		"",
		"library",
		"https://evil.example",
		"javascript:alert(1)",
		// Scheme-relative and its browser-normalized disguises: tabs and
		// newlines are stripped by browsers, backslash renders as slash.
		"//evil.example",
		"/\\evil.example",
		"/\t/evil.example",
		"/\n/evil.example",
		"/\r/evil.example",
		"/\x00/evil.example",
		"/a\\b",
		"/a\tb",
		// Double-encoded input arrives still-encoded (the router decodes
		// once); it must not pass as a rooted path.
		"%2f%2fevil.example",
	}
	for _, p := range bad {
		if safeRedirectPath(p) {
			t.Errorf("safeRedirectPath(%q) = true, want false", p)
		}
	}
}
