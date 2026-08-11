package subsonic

import "testing"

// A real client (Feishin's tracks index) dereferences contentType on
// every row without checking, so the fallback is part of the contract:
// every container value - composite label, unknown, or absent - yields
// a mime, and the suffix is an extension, never a probe label. The
// cases are the labels the scan actually stores: WaxLabel's names
// lowercased ("aac (adts)", "aifc", "matroska", "webm"), plus WaxBin's
// extension fallbacks for the vendored exotics ("asf", "ape",
// "wavpack").
func TestFormatFacts(t *testing.T) {
	cases := []struct{ container, suffix, mime string }{
		{"flac", "flac", "audio/flac"},
		{"mp3", "mp3", "audio/mpeg"},
		{"ogg", "ogg", "audio/ogg"},
		{"wav", "wav", "audio/wav"},
		{"mp4", "mp4", "audio/mp4"},
		{"aac (adts)", "aac", "audio/aac"},
		{"aiff", "aiff", "audio/aiff"},
		{"aifc", "aifc", "audio/aiff"},
		{"matroska", "mka", "audio/x-matroska"},
		{"webm", "webm", "audio/webm"},
		{"asf", "wma", "audio/x-ms-wma"},
		{"ape", "ape", "audio/x-ape"},
		{"wavpack", "wv", "audio/x-wavpack"},
		{"MP3", "mp3", "audio/mpeg"},
		{"mysteryformat", "mysteryformat", "application/octet-stream"},
		{"", "", "application/octet-stream"},
	}
	for _, tc := range cases {
		suffix, mime := formatFacts(tc.container)
		if suffix != tc.suffix || mime != tc.mime {
			t.Errorf("formatFacts(%q) = %q, %q; want %q, %q",
				tc.container, suffix, mime, tc.suffix, tc.mime)
		}
	}
}
