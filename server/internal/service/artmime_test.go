package service

import "testing"

// The media type a picture is served under is derived from its stored
// format rather than looked up, so the derivation is what has to be
// right about the two things a header decides: what a client draws, and
// what a browser executes.
func TestArtMime(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		format string
		want   string
	}{
		// The ordinary set, including the two BMP and TIFF spellings a
		// tag or a remote can arrive under.
		{"jpeg", "image/jpeg"},
		{"jpg", "image/jpeg"},
		{"image/jpeg", "image/jpeg"},
		{"png", "image/png"},
		{"webp", "image/webp"},
		{"gif", "image/gif"},
		{"bmp", "image/bmp"},
		{"x-ms-bmp", "image/bmp"},
		{"tif", "image/tiff"},
		{"image/tiff", "image/tiff"},
		// Held without decoding, and mislabelled as jpeg by the table
		// this derivation replaced.
		{"avif", "image/avif"},
		{"heic", "image/heic"},
		{"heif", "image/heic"},
		// Markup, however it is spelled. A provider naming svg is enough
		// to store one, and serving it as its own type from this origin
		// would run it as the reader.
		{"svg", "application/octet-stream"},
		{"svg+xml", "application/octet-stream"},
		{"image/svg+xml", "application/octet-stream"},
		// Not a format at all. The store refuses to hold one, so this is
		// the unreachable case rather than the common one.
		{"", "application/octet-stream"},
		{"text/html", "application/octet-stream"},
		{"application/octet-stream", "application/octet-stream"},
	} {
		if got := artMime(tc.format); got != tc.want {
			t.Errorf("artMime(%q) = %q, want %q", tc.format, got, tc.want)
		}
	}
}
