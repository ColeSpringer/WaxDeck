package api

import (
	"fmt"
	"net/http"
	"strings"
	"testing"
)

// An import's body is read through a cap, and the import needs the
// account's podcast permission and a document of at most 1,000 feeds,
// each refused in the API's own words.
func TestAnOpmlImportIsBoundedAtTheDoor(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	refused := func(resp *http.Response, status int, code, says string) {
		t.Helper()
		body := decodeStatus[Error](t, resp, status, "the import")
		if body.Code != code || !strings.Contains(body.Message, says) {
			t.Errorf("import = %+v, want %s saying %q", body, code, says)
		}
	}
	padded := `<opml version="2.0"><body><!--` + strings.Repeat("x", 5<<20) + `--></body></opml>`
	refused(h.postJSON(t, "/api/v1/podcasts/opml", map[string]any{"opml": padded}), 400, "invalid-request", "too large")

	var many strings.Builder
	many.WriteString(`<opml version="2.0"><body>`)
	for i := range 1001 {
		fmt.Fprintf(&many, `<outline text="f" xmlUrl="ftp://feeds.example/%d.xml"/>`, i)
	}
	many.WriteString(`</body></opml>`)
	refused(h.postJSON(t, "/api/v1/podcasts/opml", map[string]any{"opml": many.String()}), 400, "invalid-request", "1000")

	id, listener := listenerAccount(t, h, "no-podcasts", true)
	wantStatus(t, h.patchJSON(t, "/api/v1/users/"+id, map[string]any{
		"permissions": map[string]any{
			"download": true, "delete": false, "explicitContent": true,
			"sharedOutputs": true, "managePodcasts": false,
		},
	}), 200, "withdrawing podcast management")
	refused(reqAs(t, h, "POST", "/api/v1/podcasts/opml", listener, map[string]any{"opml": "<opml><body><outline"}),
		403, "forbidden", "cannot manage podcasts")
}

// A folder past 512 characters is refused on both doors that write one.
func TestALongFolderIsRefused(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	long := strings.Repeat("x/", 32000)
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL(), "folder": long})
	if body := decodeStatus[Error](t, resp, 400, "subscribing"); body.Code != "invalid-request" || !strings.Contains(body.Message, "512") {
		t.Errorf("subscribe = %+v, want the folder refused", body)
	}
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL(), "folder": "/News/"}), 201, "subscribing")
	if sub.Settings.Folder == nil || *sub.Settings.Folder != "News" {
		t.Errorf("folder = %v, want News", sub.Settings.Folder)
	}
	resp = h.putJSON(t, "/api/v1/podcasts/"+sub.Show.Pid+"/settings", map[string]any{"folder": long})
	if body := decodeStatus[Error](t, resp, 400, "the settings"); body.Code != "invalid-request" || !strings.Contains(body.Message, "512") {
		t.Errorf("settings = %+v, want the folder refused", body)
	}
}
