package service

import (
	"errors"
	"testing"

	"github.com/colespringer/waxbin/model"
)

// watchPage is the enclosure WaxDeck's own YouTube provider stores: the
// video's watch page, which its downloader starts from.
func watchPage(int) (string, string) { return "https://www.youtube.com/watch?v=abc", "audio/mp4" }

// A YouTube show's enclosure is a page, not audio, so its episodes play
// once fetched and are never offered for relay; the same URL in an RSS
// feed is that feed's audio and relays as any other.
func TestAYouTubeEpisodeIsNotRelayed(t *testing.T) {
	t.Parallel()
	youtube := &stubFeed{kind: model.SourceYouTube, n: 1, prefix: "Video", enclosure: watchPage}
	rss := &stubFeed{kind: model.SourceRSS, n: 1, prefix: "Episode", enclosure: watchPage}
	f := openStubFeeds(t, youtube, rss)
	for _, c := range []struct {
		name, url, kind string
		relays          bool
	}{
		{"youtube", "https://www.youtube.com/@stubchannel", "youtube", false},
		{"rss", "https://feeds.example/watch", "rss", true},
	} {
		t.Run(c.name, func(t *testing.T) {
			sub := f.subscribe(t, c.url, c.kind)
			eps, _, err := f.svc.Episodes(f.ctx, f.uc, sub.Show.PID, "", 10)
			if err != nil || len(eps) != 1 {
				t.Fatalf("episodes = %v (%v), want one", eps, err)
			}
			ep := eps[0]
			if ep.HasEnclosure != c.relays {
				t.Errorf("hasEnclosure = %v, want %v", ep.HasEnclosure, c.relays)
			}
			src, err := f.svc.EnclosureStreamSource(f.ctx, f.uc.ID, ep.PID)
			if c.relays && (err != nil || src.URL != "https://www.youtube.com/watch?v=abc") {
				t.Errorf("enclosure source = %+v (%v), want the feed's enclosure", src, err)
			}
			if !c.relays && KindOf(err) != KindNotFound {
				t.Errorf("enclosure source = %+v (%v), want not-found", src, err)
			}
			if _, ok := f.svc.PassthroughEpisode(f.ctx, f.uc.ID, ep.PID); ok != c.relays {
				t.Errorf("passthrough = %v, want %v", ok, c.relays)
			}
			if _, err := f.svc.StreamSource(f.ctx, ep.PID, ""); !errors.Is(err, ErrEpisodeNotFetched) {
				t.Errorf("stream source = %v, want the not-fetched conflict", err)
			}
		})
	}
}

// An enclosure relays when it is a feed's own audio at an http address;
// one its feed calls a playlist or a streaming manifest names further
// addresses instead, and never relays.
func TestRelayableEnclosure(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		source        model.SourceType
		url, declared string
		want          bool
	}{
		{model.SourceRSS, "https://cdn.example/ep.mp3", "audio/mpeg", true},
		{model.SourceRSS, "http://cdn.example/ep.mp3", "audio/mpeg", true},
		{"", "https://cdn.example/ep.mp3", "audio/mpeg", true},
		{model.SourceManual, "https://cdn.example/ep.mp3", "audio/mpeg", true},
		{model.SourceRSS, "https://cdn.example/ep.mp3", "", true},
		{model.SourceRSS, "https://cdn.example/ep.mp3", "text/html", true},
		{model.SourceYouTube, "https://www.youtube.com/watch?v=abc", "audio/mp4", false},
		{model.SourceYouTube, "https://cdn.example/ep.mp3", "audio/mpeg", false},
		{model.SourceRSS, "", "audio/mpeg", false},
		{model.SourceRSS, "ftp://cdn.example/ep.mp3", "audio/mpeg", false},
		{model.SourceRSS, "//cdn.example/ep.mp3", "audio/mpeg", false},
		{model.SourceRSS, "https://cdn.example/live.m3u", "audio/x-mpegurl", false},
		{model.SourceRSS, "https://cdn.example/live.m3u8", "Application/VND.Apple.MPEGURL", false},
		{model.SourceRSS, "https://cdn.example/live.pls", "audio/x-scpls", false},
		{model.SourceRSS, "https://cdn.example/ep.mpd", "application/dash+xml", false},
		{model.SourceRSS, "https://cdn.example/ep.mpd", "video/vnd.mpeg.dash.mpd", false},
	} {
		if got := relayableEnclosure(c.source, c.url, c.declared); got != c.want {
			t.Errorf("relayableEnclosure(%q, %q, %q) = %v, want %v", c.source, c.url, c.declared, got, c.want)
		}
	}
}

// What a feed declares is as untrusted as what its host answers: a
// declared type that is not audio is never what play-info or the relay
// reports.
func TestEnclosureMediaTypeCoercesWhatIsNotAudio(t *testing.T) {
	t.Parallel()
	for declared, want := range map[string]string{
		"audio/mpeg":                   "audio/mpeg",
		"Audio/MPEG":                   "audio/mpeg",
		"audio/mp4; codecs=mp4a.40.2":  "audio/mp4",
		"audio/x-m4a":                  "audio/x-m4a",
		"video/mp4":                    "video/mp4",
		"application/ogg":              "application/ogg",
		"application/mpeg":             "application/mpeg",
		"application/mp4":              "application/mp4",
		"":                             "audio/mpeg",
		"text/html":                    "audio/mpeg",
		"text/html; charset=utf-8":     "audio/mpeg",
		"application/octet-stream":     "audio/mpeg",
		"image/svg+xml":                "audio/mpeg",
		"application/json":             "audio/mpeg",
		"audio":                        "audio/mpeg",
		"audio/mpeg; charset=\"broken": "audio/mpeg",
		"audio/x+xml":                  "audio/mpeg",
		"video/svg+xml":                "audio/mpeg",
		"audio/*":                      "audio/mpeg",
		"audio/x-mpegurl":              "audio/mpeg",
		"audio/x-scpls":                "audio/mpeg",
		"video/vnd.mpeg.dash.mpd":      "audio/mpeg",
		"audio/vnd.wave":               "audio/vnd.wave",
	} {
		if got := EnclosureMediaType(declared); got != want {
			t.Errorf("EnclosureMediaType(%q) = %q, want %q", declared, got, want)
		}
	}
}
