package httpcache

import "testing"

func TestETagMatches(t *testing.T) {
	const etag = `"abc123"`
	cases := []struct {
		name   string
		header string
		want   bool
	}{
		{"the validator as issued", `"abc123"`, true},
		{"weak form of the same validator", `W/"abc123"`, true},
		{"one of a list", `"other", "abc123"`, true},
		{"one of a list, weak, unspaced", `W/"other",W/"abc123"`, true},
		{"a different validator", `"abc124"`, false},
		{"a prefix of the validator", `"abc12"`, false},
		{"an unquoted body that happens to match", `abc123`, false},
		{"nothing", "", false},
		{"a wildcard is not honored on a read", `*`, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := ETagMatches(tc.header, etag); got != tc.want {
				t.Fatalf("ETagMatches(%q, %q) = %v, want %v", tc.header, etag, got, tc.want)
			}
		})
	}
	if ETagMatches(`"abc123"`, "") {
		t.Error("an absent validator must never match")
	}
}
