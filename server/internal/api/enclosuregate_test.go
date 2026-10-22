package api

import "testing"

// The relay passes a host's type only when it names audio; a host that
// does not say takes the feed's declared type, and anything else (a page,
// a playlist) never goes out.
func TestEnclosureContentType(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		upstream, declared string
		want               string
		ok                 bool
	}{
		{"audio/mpeg", "audio/mpeg", "audio/mpeg", true},
		{"audio/mp4; codecs=mp4a.40.2", "audio/mpeg", "audio/mp4", true},
		{"Audio/X-M4A", "audio/mpeg", "audio/x-m4a", true},
		{"video/mp4", "audio/mpeg", "video/mp4", true},
		{"application/ogg", "audio/mpeg", "application/ogg", true},
		{"application/mpeg", "audio/mpeg", "application/mpeg", true},
		{"application/mp4", "audio/mpeg", "application/mp4", true},
		{"", "audio/mp4", "audio/mp4", true},
		{"application/octet-stream", "audio/mpeg", "audio/mpeg", true},
		{"APPLICATION/OCTET-STREAM", "video/mp4", "video/mp4", true},
		{"binary/octet-stream", "audio/mpeg", "audio/mpeg", true},
		// The declared type is the feed's word and is held to the same
		// rule before it stands in for the host's.
		{"application/octet-stream", "text/html", "audio/mpeg", true},
		{"", "", "audio/mpeg", true},
		{"text/html; charset=utf-8", "audio/mpeg", "", false},
		{"text/plain", "audio/mpeg", "", false},
		{"application/json", "audio/mpeg", "", false},
		{"application/xml", "audio/mpeg", "", false},
		{"image/svg+xml", "audio/mpeg", "", false},
		{"application/pdf", "audio/mpeg", "", false},
		{"audio", "audio/mpeg", "", false},
		// A structured-syntax suffix says the bytes are XML or JSON, and
		// a wildcard names no type at all, whatever comes before them.
		{"audio/x+xml", "audio/mpeg", "", false},
		{"video/svg+xml", "audio/mpeg", "", false},
		{"audio/mpeg+json", "audio/mpeg", "", false},
		{"audio/*", "audio/mpeg", "", false},
		{"video/*", "audio/mpeg", "", false},
		{"", "audio/x+xml", "audio/mpeg", true},
		// A playlist or a streaming manifest is a list of further
		// addresses, which a player would fetch from wherever it says.
		{"audio/x-mpegurl", "audio/mpeg", "", false},
		{"Audio/MPEGURL; charset=utf-8", "audio/mpeg", "", false},
		{"audio/x-mpequrl", "audio/mpeg", "", false},
		{"video/x-mpegurl", "audio/mpeg", "", false},
		{"video/vnd.mpegurl", "audio/mpeg", "", false},
		{"application/vnd.apple.mpegurl", "audio/mpeg", "", false},
		{"application/x-mpegurl", "audio/mpeg", "", false},
		{"audio/x-scpls", "audio/mpeg", "", false},
		{"audio/scpls", "audio/mpeg", "", false},
		{"video/x-ms-asx", "audio/mpeg", "", false},
		{"audio/x-ms-wax", "audio/mpeg", "", false},
		{"video/x-ms-wvx", "audio/mpeg", "", false},
		{"audio/x-pn-realaudio", "audio/mpeg", "", false},
		{"application/dash+xml", "audio/mpeg", "", false},
		{"video/vnd.mpeg.dash.mpd", "audio/mpeg", "", false},
		// Real types keep passing, odd punctuation and all.
		{"audio/vnd.wave", "audio/mpeg", "audio/vnd.wave", true},
		{"audio/3gpp", "audio/mpeg", "audio/3gpp", true},
		{"audio/x-ms-wma", "audio/mpeg", "audio/x-ms-wma", true},
		{"audio/mp4a-latm", "audio/mpeg", "audio/mp4a-latm", true},
	} {
		got, ok := enclosureContentType(c.upstream, c.declared)
		if got != c.want || ok != c.ok {
			t.Errorf("enclosureContentType(%q, %q) = %q, %v; want %q, %v",
				c.upstream, c.declared, got, ok, c.want, c.ok)
		}
	}
}
