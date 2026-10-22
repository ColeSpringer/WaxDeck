package api

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"golang.org/x/text/language"

	"github.com/colespringer/waxdeck/server/internal/pagetext"
	"github.com/colespringer/waxdeck/server/internal/service"
)

func TestCountableShareFetch(t *testing.T) {
	t.Parallel()
	cases := []struct {
		rangeHeader string
		want        bool
		why         string
	}{
		{"", true, "a rangeless GET starts a listen"},
		{"bytes=0-", true, "the open-ended first fetch browsers send"},
		{"bytes=0-52428799", true, "Safari's bounded full-file fetch after its probe"},
		{"bytes=0-1", false, "Safari's two-byte preflight probe is not a listen"},
		{"bytes=0-511", false, "anything under the probe floor stays a probe"},
		{"bytes=0-1023", true, "the floor itself counts"},
		{"bytes=100-", false, "a mid-playback seek"},
		{"bytes=100-200", false, "a bounded seek window"},
		{"bytes=0-1,5-9", false, "multi-range strings count nothing"},
		{"bytes=junk", false, "junk counts nothing"},
	}
	for _, tc := range cases {
		if got := countableShareFetch(tc.rangeHeader); got != tc.want {
			t.Errorf("countableShareFetch(%q) = %v, want %v (%s)", tc.rangeHeader, got, tc.want, tc.why)
		}
	}
}

// renderSharePage draws a resolved share the way the landing page does.
func renderSharePage(t *testing.T, pub *service.SharePublic, lang language.Tag, art bool) string {
	t.Helper()
	var out strings.Builder
	if err := sharePageTmpl.Execute(&out, newSharePage(pub, pagetext.For(lang), "/s/tok", art, "")); err != nil {
		t.Fatal(err)
	}
	return out.String()
}

// mixedShare is a playlist share of a local track, an episode played by
// relay and an episode with nothing to play.
func mixedShare(allowDownload bool) *service.SharePublic {
	return &service.SharePublic{
		Share: service.ShareInfo{TargetKind: "playlist", AllowDownload: allowDownload},
		Title: "Mixed",
		Items: []service.ItemSummary{
			{PID: "tr-1", Title: "A Track"},
			{PID: "ep-2", Title: "Relayed Episode"},
			{PID: "ep-3", Title: "Silent Episode"},
		},
		Audio: map[string]service.ShareAudio{
			"tr-1": service.ShareAudioLocal,
			"ep-2": service.ShareAudioRelay,
		},
	}
}

// Every member with audio draws a player, local or relayed, and the one
// with none draws the note in the reader's language instead.
func TestSharePageDrawsAPlayerOnlyWhereThereIsAudio(t *testing.T) {
	t.Parallel()
	for lang, note := range map[language.Tag]string{
		language.English: "Not available to play yet",
		language.Spanish: "Todavía no se puede reproducir",
	} {
		page := renderSharePage(t, mixedShare(false), lang, false)
		if got := strings.Count(page, "<audio"); got != 2 {
			t.Errorf("%v: players = %d, want 2", lang, got)
		}
		if !strings.Contains(page, `src="/s/tok/stream?i=0"`) || !strings.Contains(page, `src="/s/tok/stream?i=1"`) ||
			strings.Contains(page, `src="/s/tok/stream?i=2"`) {
			t.Errorf("%v: players point at the wrong members:\n%s", lang, page)
		}
		if strings.Count(page, note) != 1 {
			t.Errorf("%v: page does not say %q once:\n%s", lang, note, page)
		}
	}
}

// The page's one download link is the first member's file, so it is
// offered only when that member is a file here.
func TestSharePageOffersADownloadOnlyOfAFileHere(t *testing.T) {
	t.Parallel()
	if page := renderSharePage(t, mixedShare(true), language.English, false); !strings.Contains(page, `href="/s/tok/download"`) {
		t.Error("a local first member offers no download")
	}
	relayedFirst := mixedShare(true)
	relayedFirst.Items = relayedFirst.Items[1:]
	if page := renderSharePage(t, relayedFirst, language.English, false); strings.Contains(page, "/download") {
		t.Error("a relayed first member offers a download it has no file for")
	}
	if page := renderSharePage(t, mixedShare(false), language.English, false); strings.Contains(page, "/download") {
		t.Error("a link without downloads offers one")
	}
}

// The title is the page's heading for a share of one thing; a list's
// rows keep their titles even when the list has one member.
func TestSharePageTitlesListRowsEvenWhenAlone(t *testing.T) {
	t.Parallel()
	for kind, titled := range map[string]bool{"playlist": true, "album": true, "track": false, "episode": false, "book": false} {
		pub := &service.SharePublic{
			Share: service.ShareInfo{TargetKind: kind},
			Title: "The Heading",
			Items: []service.ItemSummary{{PID: "tr-1", Title: "Only Member"}},
			Audio: map[string]service.ShareAudio{"tr-1": service.ShareAudioLocal},
		}
		if got := strings.Contains(renderSharePage(t, pub, language.English, false), "Only Member"); got != titled {
			t.Errorf("%s share of one: row titled = %v, want %v", kind, got, titled)
		}
	}
}

// A cover is drawn only when it resolved: the page runs no script that
// could trade a broken image for the placeholder.
func TestSharePageDrawsTheCoverOnlyWhenItResolved(t *testing.T) {
	t.Parallel()
	pub := mixedShare(false)
	pub.ArtItemPID = "tr-1"
	if page := renderSharePage(t, pub, language.English, true); !strings.Contains(page, `<img class="art" src="/s/tok/art"`) {
		t.Error("a resolved cover is not drawn")
	}
	if page := renderSharePage(t, pub, language.English, false); strings.Contains(page, "<img") {
		t.Error("a cover that did not resolve is drawn")
	}
}

// A play is counted when the audio starts, once, and never for an
// answer that is not audio starting.
func TestSharePlayCounterCountsTheFirstSuccess(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name   string
		write  func(w http.ResponseWriter)
		counts int
	}{
		{"a 200", func(w http.ResponseWriter) { w.WriteHeader(200); w.Write([]byte("x")) }, 1},
		{"a 206", func(w http.ResponseWriter) { w.WriteHeader(206) }, 1},
		{"an implicit 200", func(w http.ResponseWriter) { w.Write([]byte("x")); w.Write([]byte("y")) }, 1},
		{"a refusal", func(w http.ResponseWriter) { w.WriteHeader(404); w.Write([]byte("no")) }, 0},
		{"a bad gateway", func(w http.ResponseWriter) { w.WriteHeader(502) }, 0},
		{"early hints first", func(w http.ResponseWriter) { w.WriteHeader(103); w.WriteHeader(200) }, 1},
	} {
		n := 0
		counter := &sharePlayCounter{ResponseWriter: httptest.NewRecorder(), count: func() { n++ }}
		c.write(counter)
		if n != c.counts {
			t.Errorf("%s: counted %d, want %d", c.name, n, c.counts)
		}
	}
}
