package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// feedServer synthesizes real episode audio and serves it plus a
// hand-built RSS document over loopback, the way a podcast host would.
type feedServer struct {
	ts  *httptest.Server
	dir string
	// episode file names by index, for the enclosure URLs.
	files []string
	specs []fixtures.Spec
	// writes counts feed rewrites, so each one can carry a strictly
	// newer modification time; see writeFeed.
	writes int
	// enclosurePrefix goes between the host and the file in every
	// enclosure URL. "/hop/7" routes the audio through seven redirects
	// first, the shape ad-tech prefix chains put on real enclosures.
	enclosurePrefix string
}

func newFeedServer(t *testing.T, episodes int) *feedServer {
	t.Helper()
	fs := &feedServer{dir: t.TempDir()}
	for i := range episodes {
		spec := fixtures.Spec{
			Name:      fmt.Sprintf("episode-%d", i+1),
			Codec:     fixtures.CodecMP3,
			Container: fixtures.ContainerMP3,
			Duration:  time.Duration(3+i) * time.Second,
		}
		fs.specs = append(fs.specs, spec)
	}
	paths, err := fixtures.Generate(fs.dir, fs.specs...)
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range paths {
		fs.files = append(fs.files, filepath.Base(p))
	}
	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.Dir(fs.dir)))
	// /hop/<n>/<file>: n redirect hops before the file answers, the way
	// podtrac-style measurement chains front real enclosures.
	mux.HandleFunc("/hop/", func(w http.ResponseWriter, r *http.Request) {
		rest := strings.TrimPrefix(r.URL.Path, "/hop/")
		slash := strings.IndexByte(rest, '/')
		if slash < 0 {
			http.NotFound(w, r)
			return
		}
		n, err := strconv.Atoi(rest[:slash])
		if err != nil || n < 1 {
			http.NotFound(w, r)
			return
		}
		target := "/" + rest[slash+1:]
		if n > 1 {
			target = fmt.Sprintf("/hop/%d%s", n-1, target)
		}
		http.Redirect(w, r, target, http.StatusFound)
	})
	fs.ts = httptest.NewServer(mux)
	t.Cleanup(fs.ts.Close)
	fs.writeFeed(t, episodes)
	return fs
}

// writeFeed renders feed.xml for the first n episodes; rewriting with
// a larger n simulates a feed publishing new entries.
func (fs *feedServer) writeFeed(t *testing.T, n int) {
	t.Helper()
	var items strings.Builder
	base := time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC)
	for i := 0; i < n && i < len(fs.files); i++ {
		info, err := os.Stat(filepath.Join(fs.dir, fs.files[i]))
		if err != nil {
			t.Fatal(err)
		}
		extra := ""
		if i == 0 {
			extra = `<podcast:transcript url="` + fs.ts.URL + `/transcript.vtt" type="text/vtt"/>` +
				`<podcast:person role="Guest">Guest Star</podcast:person>` +
				`<podcast:soundbite startTime="1.5" duration="1.0">A great moment</podcast:soundbite>`
		}
		// The feed declares a duration, as real feeds do. It is the only
		// length an unfetched episode has: the catalog item is fileless
		// until a fetch lands, so this is what every listing reports and
		// what the played threshold is measured against.
		fmt.Fprintf(&items, `<item>
			<title>Episode %d</title>
			<guid isPermaLink="false">ep-guid-%d</guid>
			<pubDate>%s</pubDate>
			<itunes:duration>%d</itunes:duration>
			<description><![CDATA[<p>Notes for <b>episode %d</b></p><script>alert(1)</script>]]></description>
			%s
			<enclosure url="%s%s/%s" type="audio/mpeg" length="%d"/>
		</item>`, i+1, i+1, base.AddDate(0, 0, i).Format(time.RFC1123Z),
			int(fs.specs[i].Duration.Seconds()), i+1, extra,
			fs.ts.URL, fs.enclosurePrefix, fs.files[i], info.Size())
	}
	doc := `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:podcast="https://podcastindex.org/namespace/1.0">
<channel>
<title>Fixture Cast</title>
<itunes:author>Fixture Author</itunes:author>
<description><![CDATA[A show about <i>fixtures</i>.]]></description>
<podcast:guid>fixture-cast-guid</podcast:guid>
<podcast:medium>podcast</podcast:medium>
<podcast:funding url="https://example.com/support">Support the show</podcast:funding>
<podcast:person role="Host" href="https://example.com/host">Fixture Host</podcast:person>
` + items.String() + `
</channel>
</rss>`
	if err := os.WriteFile(filepath.Join(fs.dir, "feed.xml"), []byte(doc), 0o644); err != nil {
		t.Fatal(err)
	}
	vtt := "WEBVTT\n\n00:00.000 --> 00:01.500\nHello there\n\n00:01.500 --> 00:03.000\nGeneral fixture\n"
	if err := os.WriteFile(filepath.Join(fs.dir, "transcript.vtt"), []byte(vtt), 0o644); err != nil {
		t.Fatal(err)
	}
	// The sync enumerates conditionally on ETag and Last-Modified, and
	// the file server reports Last-Modified at one-second resolution, so
	// two rewrites inside the same second would answer 304 and the feed
	// would look unchanged. A real feed publishing new entries advances
	// its modification time, so this one does too, by a stride per write.
	fs.writes++
	stamp := time.Now().Add(time.Duration(fs.writes) * 2 * time.Second)
	if err := os.Chtimes(filepath.Join(fs.dir, "feed.xml"), stamp, stamp); err != nil {
		t.Fatal(err)
	}
}

// writeEnclosureless rewrites the feed with an item carrying no
// enclosure at all, which is the one episode passthrough cannot serve.
func (fs *feedServer) writeEnclosureless(t *testing.T) {
	t.Helper()
	doc := `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
<title>Fixture Cast</title>
<description>No audio here</description>
<item>
	<title>Announcement only</title>
	<guid isPermaLink="false">ep-guid-noaudio</guid>
	<pubDate>` + time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC).Format(time.RFC1123Z) + `</pubDate>
	<description>Text, no audio.</description>
</item>
</channel></rss>`
	if err := os.WriteFile(filepath.Join(fs.dir, "feed.xml"), []byte(doc), 0o644); err != nil {
		t.Fatal(err)
	}
}

// newPrivateFeedServer is newFeedServer behind HTTP basic auth, the way
// a paid or member-only podcast host works: the feed document and the
// enclosures both refuse an unauthenticated GET.
func newPrivateFeedServer(t *testing.T, episodes int, user, pass string) *feedServer {
	t.Helper()
	fs := newFeedServer(t, episodes)
	files := http.FileServer(http.Dir(fs.dir))
	fs.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotUser, gotPass, ok := r.BasicAuth()
		if !ok || gotUser != user || gotPass != pass {
			w.Header().Set("WWW-Authenticate", `Basic realm="private"`)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		files.ServeHTTP(w, r)
	})
	return fs
}

// newFeedServerWithHeaders is newFeedServer with the host adding
// headers of its own to every response, which is what the relay's
// allowlist has to hold back.
func newFeedServerWithHeaders(t *testing.T, episodes int, extra http.Header) *feedServer {
	t.Helper()
	fs := newFeedServer(t, episodes)
	files := http.FileServer(http.Dir(fs.dir))
	fs.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		for name, vals := range extra {
			for _, v := range vals {
				w.Header().Add(name, v)
			}
		}
		files.ServeHTTP(w, r)
	})
	return fs
}

func (fs *feedServer) feedURL() string { return fs.ts.URL + "/feed.xml" }

// newPodcastHarness is the shared harness plus the podcast surface: a
// download dir outside the library roots and loopback feeds allowed.
func newPodcastHarness(t *testing.T) *harness {
	podcastDir := t.TempDir()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.PodcastDir = podcastDir
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
		// Tests drive checkpoints and sweeps back to back; the in-use
		// deferral would read every touched episode as live playback.
		cfg.RetentionInUseWindow = -1
	})
	h.podcastDir = podcastDir
	return h
}

// reqAs is the token-parameterized request helper the two-user tests
// need (the harness postJSON always acts as the admin).
func reqAs(t *testing.T, h *harness, method, path, token string, body any) *http.Response {
	t.Helper()
	var reader io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		reader = bytes.NewReader(raw)
	}
	req, err := http.NewRequest(method, h.ts.URL+path, reader)
	if err != nil {
		t.Fatal(err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

// drainFetches runs the fetch worker inline until idle, then waits for
// the catalog to settle.
func drainFetches(t *testing.T, h *harness) {
	t.Helper()
	ctx := context.Background()
	deadline := time.Now().Add(30 * time.Second)
	for h.svc.DrainFetchQueue(ctx) {
		if time.Now().After(deadline) {
			t.Fatal("fetch queue did not drain")
		}
	}
}

func TestPodcastLifecycle(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 2)

	// A server cursor minted before subscribing, so the subscription
	// event is observable as a delta.
	resp := get(t, h.ts, "/api/v1/sync/server", h.token)
	serverSince := decode[ServerSyncPage](t, resp).NextSince

	// Subscribe; the show is cataloged from the live feed.
	resp = h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)
	if sub.Show.Title != "Fixture Cast" || !strings.HasPrefix(sub.Show.Pid, "pc-") {
		t.Fatalf("subscribed show = %+v", sub.Show)
	}
	if sub.Show.FeedUrl == nil || *sub.Show.FeedUrl != feed.feedURL() {
		t.Fatalf("public show should expose its feed url, got %+v", sub.Show.FeedUrl)
	}
	if sub.Show.DescriptionHtml == nil || !strings.Contains(*sub.Show.DescriptionHtml, "<i>fixtures</i>") {
		t.Fatalf("show description lost markup: %+v", sub.Show.DescriptionHtml)
	}

	// Subscribing again is idempotent: 200, same show.
	resp = h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 200 {
		t.Fatalf("re-subscribe status = %d", resp.StatusCode)
	}
	resp.Body.Close()

	// The subscription reached the caller's server event stream.
	resp = get(t, h.ts, "/api/v1/sync/server?since="+serverSince, h.token)
	events := decode[ServerSyncPage](t, resp).Events
	foundSub := false
	for _, ev := range events {
		if ev.Kind == "subscription" && ev.Subscription != nil && ev.Subscription.Show.Pid == sub.Show.Pid {
			foundSub = true
		}
	}
	if !foundSub {
		t.Fatalf("no subscription event in server delta: %+v", events)
	}

	// Episodes list newest first with the episode dimension.
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	page := decode[EpisodePage](t, resp)
	if len(page.Items) != 2 {
		t.Fatalf("episodes = %d, want 2", len(page.Items))
	}
	if page.Items[0].Title != "Episode 2" || page.Items[1].Title != "Episode 1" {
		t.Fatalf("episode order = %q, %q", page.Items[0].Title, page.Items[1].Title)
	}
	ep := page.Items[1]
	if ep.Downloaded || ep.ShowPid != sub.Show.Pid {
		t.Fatalf("episode row = %+v", ep)
	}
	if ep.HasTranscript == nil || !*ep.HasTranscript {
		t.Fatal("episode 1 should announce a transcript")
	}

	// A not-yet-fetched episode streams by enclosure passthrough: the
	// url relays the feed's own audio through this origin, and the
	// episode still reports itself as not downloaded, because it is not.
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("unfetched episode play-info status = %d, want 200", resp.StatusCode)
	}
	pi := decode[PlayInfo](t, resp)
	if !strings.HasPrefix(pi.Url, "/media/enclosure?") {
		t.Fatalf("unfetched episode play-info url = %q, want the passthrough relay", pi.Url)
	}
	if pi.MimeType != "audio/mpeg" {
		t.Fatalf("passthrough mime = %q, want the feed's declared enclosure type", pi.MimeType)
	}
	if ep.Downloaded {
		t.Fatal("a passthrough episode must still report downloaded false")
	}
	// The pair a client reads to decide whether to offer play: not
	// downloaded, but playable because the feed named audio.
	if ep.HasEnclosure == nil || !*ep.HasEnclosure {
		t.Fatal("an episode the feed named audio for must report hasEnclosure")
	}

	// The skip map is unavailable before the audio exists.
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/skip-map", h.token)
	if sm := decode[SkipMap](t, resp); sm.State != "unavailable" {
		t.Fatalf("skip map before fetch = %q, want unavailable", sm.State)
	}

	// Queue the server-side fetch and drain it inline.
	resp = h.postJSON(t, "/api/v1/episodes/"+ep.Pid+"/fetch", nil)
	if resp.StatusCode != 202 {
		t.Fatalf("fetch status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	drainFetches(t, h)

	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	page = decode[EpisodePage](t, resp)
	if !page.Items[1].Downloaded {
		t.Fatalf("episode still not downloaded after drain: %+v", page.Items[1])
	}
	// The fetch probed the real audio; durations are now measured, not
	// the feed's word (this feed declares none).
	ep = page.Items[1]
	if ep.DurationMs <= 0 {
		t.Fatalf("downloaded episode has no measured duration: %+v", ep)
	}

	// Present episodes stream through the proxy.
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("play-info after fetch = %d", resp.StatusCode)
	}
	info := decode[PlayInfo](t, resp)
	streamResp, err := http.Get(h.ts.URL + info.Url)
	if err != nil {
		t.Fatal(err)
	}
	streamed, _ := io.ReadAll(streamResp.Body)
	streamResp.Body.Close()
	if streamResp.StatusCode != 200 || len(streamed) == 0 {
		t.Fatalf("episode stream = %d with %d bytes", streamResp.StatusCode, len(streamed))
	}

	// Episode detail sanitizes feed HTML: markup survives, scripts die.
	resp = get(t, h.ts, "/api/v1/episodes/"+ep.Pid, h.token)
	det := decode[Episode](t, resp)
	if det.DescriptionHtml == nil ||
		!strings.Contains(*det.DescriptionHtml, "<b>episode 1</b>") ||
		strings.Contains(strings.ToLower(*det.DescriptionHtml), "script") {
		t.Fatalf("sanitized notes = %+v", det.DescriptionHtml)
	}

	// The transcript parses to time-coded cues.
	resp = get(t, h.ts, "/api/v1/episodes/"+ep.Pid+"/transcript", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("transcript status = %d", resp.StatusCode)
	}
	tx := decode[Transcript](t, resp)
	if tx.Format != "vtt" || len(tx.Cues) != 2 || tx.Cues[1].StartMs != 1500 {
		t.Fatalf("transcript = %+v", tx)
	}

	// Skip map: first ask queues analysis, the worker builds it, the
	// second ask serves sample-exact spans in milliseconds.
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/skip-map", h.token)
	if sm := decode[SkipMap](t, resp); sm.State != "pending" {
		t.Fatalf("skip map state = %q, want pending", sm.State)
	}
	for h.svc.DrainAnalysisQueue(context.Background()) {
	}
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/skip-map", h.token)
	sm := decode[SkipMap](t, resp)
	if sm.State != "ready" || sm.Spans == nil || len(*sm.Spans) != 2 {
		t.Fatalf("skip map = %+v", sm)
	}
	if (*sm.Spans)[0].EndMs != 1500 {
		t.Fatalf("first span = %+v, want end 1500ms", (*sm.Spans)[0])
	}
	if sm.Version == nil || *sm.Version != "silence-1" || sm.EssenceHash == nil || *sm.EssenceHash == "" {
		t.Fatalf("skip map keys = %+v", sm)
	}

	// Voice boost: the analysis stored loudness, so a boosted mint
	// engages and the proxied stream carries the DSP parameters.
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info?voiceBoost=true", h.token)
	info = decode[PlayInfo](t, resp)
	if info.VoiceBoost == nil || !*info.VoiceBoost {
		t.Fatalf("voice boost did not engage: %+v", info)
	}
	streamResp, err = http.Get(h.ts.URL + info.Url)
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, streamResp.Body)
	streamResp.Body.Close()
	if h.flowReq.dynamics != "voice" {
		t.Fatalf("proxied dynamics = %q, want voice", h.flowReq.dynamics)
	}
	if h.flowReq.gain != "4.5" {
		t.Fatalf("proxied gain = %q, want 4.5 (target -16 minus measured -20.5)", h.flowReq.gain)
	}

	// Position-derived played threshold: a checkpoint past 90 percent
	// marks the episode played without any listen session.
	target := int64(float64(ep.DurationMs) * 0.95)
	resp = reqAs(t, h, "PUT", "/api/v1/items/"+ep.Pid+"/play-state", h.token, map[string]any{"positionMs": target})
	if resp.StatusCode != 200 && resp.StatusCode != 204 {
		t.Fatalf("checkpoint status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-state", h.token)
	st := decode[PlayState](t, resp)
	if !st.Played {
		t.Fatalf("episode not marked played at 95 percent position: %+v", st)
	}
	if st.PlayCount != 1 {
		t.Fatalf("play count after the played crossing = %d, want 1", st.PlayCount)
	}

	// Reaching the end must not mark a second play: one listen-through
	// is one play, however many checkpoints cross thresholds.
	resp = reqAs(t, h, "PUT", "/api/v1/items/"+ep.Pid+"/play-state", h.token,
		map[string]any{"positionMs": ep.DurationMs})
	resp.Body.Close()
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-state", h.token)
	if st := decode[PlayState](t, resp); st.PlayCount != 1 {
		t.Fatalf("play count after finishing = %d, want 1 (the double-mark bug)", st.PlayCount)
	}

	// The fetch's inverse: removing the download trashes the audio,
	// keeps every user's state, and leaves the episode fetchable.
	resp = reqAs(t, h, "DELETE", "/api/v1/episodes/"+ep.Pid+"/fetch", h.token, nil)
	if resp.StatusCode != 204 {
		t.Fatalf("remove download status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	page = decode[EpisodePage](t, resp)
	if page.Items[1].Downloaded {
		t.Fatal("episode still reads downloaded after removal")
	}
	// Removal takes the local audio, not the ability to play: the feed
	// enclosure is still there, so play-info falls back to passthrough.
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("play-info after removal = %d, want 200 by passthrough", resp.StatusCode)
	}
	if u := decode[PlayInfo](t, resp).Url; !strings.HasPrefix(u, "/media/enclosure?") {
		t.Fatalf("play-info url after removal = %q, want the passthrough relay", u)
	}
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-state", h.token)
	if st := decode[PlayState](t, resp); !st.Played || st.PlayCount != 1 {
		t.Fatalf("removal must archive, not delete: state = %+v", st)
	}
	// Removing again is a no-op success, and the episode fetches back.
	resp = reqAs(t, h, "DELETE", "/api/v1/episodes/"+ep.Pid+"/fetch", h.token, nil)
	if resp.StatusCode != 204 {
		t.Fatalf("second remove status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	resp = h.postJSON(t, "/api/v1/episodes/"+ep.Pid+"/fetch", nil)
	resp.Body.Close()
	drainFetches(t, h)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	page = decode[EpisodePage](t, resp)
	if !page.Items[1].Downloaded {
		t.Fatal("episode did not fetch back after removal")
	}

	// The catalog snapshot carries the show as its own operation (its
	// own page phase) and the episode rows with their episode payloads;
	// mirrors walk every page.
	var sawShow, sawEpisode bool
	snapPath := "/api/v1/sync/catalog"
	for pages := 0; pages < 10; pages++ {
		resp = get(t, h.ts, snapPath, h.token)
		snap := decode[CatalogSyncPage](t, resp)
		for _, e := range snap.Entries {
			if e.Op == "upsert-show" && e.Show != nil && e.Show.Pid == sub.Show.Pid {
				sawShow = true
			}
			if e.Op == "upsert" && e.Episode != nil && e.Episode.Pid == ep.Pid {
				sawEpisode = true
			}
		}
		if snap.NextCursor == nil {
			break
		}
		snapPath = "/api/v1/sync/catalog?cursor=" + *snap.NextCursor
	}
	if !sawShow || !sawEpisode {
		t.Fatalf("snapshot show=%v episode=%v", sawShow, sawEpisode)
	}

	// OPML round trip: the export names the feed; unsubscribing empties
	// it; importing the exported document restores the subscription.
	resp = get(t, h.ts, "/api/v1/podcasts/opml", h.token)
	opml, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.Contains(string(opml), feed.feedURL()) {
		t.Fatalf("opml export lacks the feed: %s", opml)
	}
	req, _ := http.NewRequest("DELETE", h.ts.URL+"/api/v1/podcasts/"+sub.Show.Pid, nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	delResp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	delResp.Body.Close()
	if delResp.StatusCode != 204 {
		t.Fatalf("unsubscribe status = %d", delResp.StatusCode)
	}
	resp = get(t, h.ts, "/api/v1/podcasts/opml", h.token)
	opmlAfter, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if strings.Contains(string(opmlAfter), feed.feedURL()) {
		t.Fatal("opml export still lists an unsubscribed feed")
	}
	resp = h.postJSON(t, "/api/v1/podcasts/opml", map[string]any{"opml": string(opml)})
	if resp.StatusCode != 200 {
		t.Fatalf("opml import status = %d", resp.StatusCode)
	}
	imported := decode[OpmlImportResult](t, resp)
	if len(imported.Results) != 1 || imported.Results[0].Error != nil {
		t.Fatalf("opml import = %+v", imported.Results)
	}
	resp = get(t, h.ts, "/api/v1/podcasts", h.token)
	if subs := decode[SubscriptionPage](t, resp); len(subs.Items) != 1 {
		t.Fatalf("subscriptions after import = %d, want 1", len(subs.Items))
	}
}

// TestPodcastTwoPointOhExtras verifies the Podcasting 2.0 channel and item
// extras (funding, medium, person credits, and soundbites) parse from the feed
// and surface on the show and episode detail reads.
func TestPodcastTwoPointOhExtras(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 2)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)

	// Show detail carries the channel-level extras.
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid, h.token)
	show := decode[PodcastDetail](t, resp).Show
	if show.Medium == nil || *show.Medium != "podcast" {
		t.Fatalf("show medium = %v, want podcast", show.Medium)
	}
	if show.Funding == nil || show.Funding.Url != "https://example.com/support" {
		t.Fatalf("show funding = %+v", show.Funding)
	}
	if show.Funding.Message == nil || *show.Funding.Message != "Support the show" {
		t.Fatalf("funding message = %v", show.Funding.Message)
	}
	if show.Persons == nil || len(*show.Persons) != 1 {
		t.Fatalf("show persons = %+v", show.Persons)
	}
	if host := (*show.Persons)[0]; host.Name != "Fixture Host" ||
		host.Role == nil || *host.Role != "host" ||
		host.Href == nil || *host.Href != "https://example.com/host" {
		t.Fatalf("host credit = %+v", host)
	}

	// Episode 1 (oldest, first published) carries the item-level extras.
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	ep := decode[EpisodePage](t, resp).Items[1] // newest-first; Episode 1 is oldest
	resp = get(t, h.ts, "/api/v1/episodes/"+ep.Pid, h.token)
	epDetail := decode[Episode](t, resp)
	if epDetail.Persons == nil || len(*epDetail.Persons) != 1 {
		t.Fatalf("episode persons = %+v", epDetail.Persons)
	}
	if guest := (*epDetail.Persons)[0]; guest.Name != "Guest Star" ||
		guest.Role == nil || *guest.Role != "guest" {
		t.Fatalf("guest credit = %+v", guest)
	}
	if epDetail.Soundbites == nil || len(*epDetail.Soundbites) != 1 {
		t.Fatalf("episode soundbites = %+v", epDetail.Soundbites)
	}
	if bite := (*epDetail.Soundbites)[0]; bite.StartMs != 1500 || bite.DurationMs != 1000 ||
		bite.Title == nil || *bite.Title != "A great moment" {
		t.Fatalf("soundbite = %+v", bite)
	}
}

func TestPodcastRetentionUnion(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 4)
	ctx := context.Background()

	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)

	resp = h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	admin := decode[Subscription](t, resp)
	show := admin.Show.Pid
	resp = reqAs(t, h, "POST", "/api/v1/podcasts", sam.Token, map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("second subscribe status = %d", resp.StatusCode)
	}
	resp.Body.Close()

	// Fetch all four episodes to the server.
	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	page := decode[EpisodePage](t, resp)
	if len(page.Items) != 4 {
		t.Fatalf("episodes = %d", len(page.Items))
	}
	for _, ep := range page.Items {
		r := h.postJSON(t, "/api/v1/episodes/"+ep.Pid+"/fetch", nil)
		r.Body.Close()
	}
	drainFetches(t, h)

	// The admin keeps only the newest episode; sam keeps everything.
	// The union must keep everything.
	keepOne := 1
	resp = reqAs(t, h, "PUT", "/api/v1/podcasts/"+show+"/settings", h.token,
		map[string]any{"retentionKeep": keepOne})
	if resp.StatusCode != 200 {
		t.Fatalf("settings status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	keepAll := 0
	resp = reqAs(t, h, "PUT", "/api/v1/podcasts/"+show+"/settings", sam.Token,
		map[string]any{"retentionKeep": keepAll})
	resp.Body.Close()

	h.svc.SweepRetention(ctx)
	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	page = decode[EpisodePage](t, resp)
	downloaded := 0
	for _, ep := range page.Items {
		if ep.Downloaded {
			downloaded++
		}
	}
	if downloaded != 4 {
		t.Fatalf("keep-all union still lost files: %d of 4 remain", downloaded)
	}

	// Sam remembers a position on the oldest episode, then tightens to
	// keep-2. The union is keep-2; the two oldest files go, but the
	// archive-preserve guarantee keeps the playback state.
	oldest := page.Items[3]
	resp = reqAs(t, h, "PUT", "/api/v1/items/"+oldest.Pid+"/play-state", sam.Token,
		map[string]any{"positionMs": 1200})
	resp.Body.Close()
	keepTwo := 2
	resp = reqAs(t, h, "PUT", "/api/v1/podcasts/"+show+"/settings", sam.Token,
		map[string]any{"retentionKeep": keepTwo})
	resp.Body.Close()

	h.svc.SweepRetention(ctx)
	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	page = decode[EpisodePage](t, resp)
	downloaded = 0
	for _, ep := range page.Items {
		if ep.Downloaded {
			downloaded++
		}
	}
	if downloaded != 2 {
		t.Fatalf("union keep-2 left %d files, want 2", downloaded)
	}
	if page.Items[0].Downloaded != true || page.Items[1].Downloaded != true {
		t.Fatal("retention removed the wrong (newest) episodes")
	}

	// The invocation guard on the upstream archive-preserve guarantee:
	// removing the file never removed the listening state.
	resp = reqAs(t, h, "GET", "/api/v1/items/"+oldest.Pid+"/play-state", sam.Token, nil)
	if st := decode[PlayState](t, resp); st.PositionMs != 1200 {
		t.Fatalf("position after retention = %d, want 1200 (archive must preserve state)", st.PositionMs)
	}

	// A starred old episode is pinned through the next tightening and
	// keeps its file while an unstarred sibling of the same age would
	// not have.
	third := page.Items[2]
	resp = reqAs(t, h, "POST", "/api/v1/episodes/"+third.Pid+"/fetch", sam.Token, nil)
	resp.Body.Close()
	drainFetches(t, h)
	resp = reqAs(t, h, "PUT", "/api/v1/items/"+third.Pid+"/star", sam.Token, map[string]any{"starred": true})
	resp.Body.Close()
	if err := h.store.EnqueueRetention(ctx, strings.TrimPrefix(show, "pc-"), time.Now().UnixNano()); err != nil {
		t.Fatal(err)
	}
	h.svc.SweepRetention(ctx)
	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	page = decode[EpisodePage](t, resp)
	if !page.Items[2].Downloaded {
		t.Fatal("a starred episode beyond keep-N lost its file; pinning must protect it")
	}
}

func TestPodcastPrivacy(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{
		"url": feed.feedURL(), "username": "member", "password": "tokensecret",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("private subscribe status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)
	if sub.Show.FeedUrl != nil {
		t.Fatalf("private show leaked its feed url: %v", *sub.Show.FeedUrl)
	}
	if sub.Settings.Private == nil || !*sub.Settings.Private {
		t.Fatalf("credentialed subscription should be private: %+v", sub.Settings)
	}

	// The OPML export omits the private show entirely.
	resp = get(t, h.ts, "/api/v1/podcasts/opml", h.token)
	opml, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if strings.Contains(string(opml), feed.ts.URL) {
		t.Fatalf("opml export leaked a private feed url: %s", opml)
	}

	// A second user browsing the show also never sees the URL, and the
	// snapshot's show entry hides it too.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "kim", "password": testPassword})
	resp.Body.Close()
	kim := loginAs(t, h.ts, "kim", testPassword)
	resp = reqAs(t, h, "GET", "/api/v1/podcasts/"+sub.Show.Pid, kim.Token, nil)
	det := decode[PodcastDetail](t, resp)
	if det.Show.FeedUrl != nil {
		t.Fatal("private feed url visible to another user")
	}
	if det.Subscribed {
		t.Fatal("second user reads as subscribed without subscribing")
	}
}

func TestEpisodeVisibilityFollowsSubscription(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 2)

	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)

	// Sam's mirror cursor from before the admin's subscribe stays
	// serviceable: another user's subscription is not sam's business.
	resp = reqAs(t, h, "GET", "/api/v1/sync/catalog", sam.Token, nil)
	samSince := decode[CatalogSyncPage](t, resp).NextSince

	resp = h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	sub := decode[Subscription](t, resp)
	adminSince := ""
	{
		r := get(t, h.ts, "/api/v1/sync/catalog", h.token)
		adminSince = decode[CatalogSyncPage](t, r).NextSince
	}

	countEpisodes := func(token string) int {
		r := reqAs(t, h, "GET", "/api/v1/library/items?mediaType=podcast", token, nil)
		page := decode[ItemPage](t, r)
		return len(page.Items)
	}

	// The subscriber's library lists the episodes; sam's does not.
	if n := countEpisodes(h.token); n != 2 {
		t.Fatalf("subscriber sees %d episodes, want 2", n)
	}
	if n := countEpisodes(sam.Token); n != 0 {
		t.Fatalf("non-subscriber sees %d episodes, want 0", n)
	}

	// Search scopes the same way.
	resp = reqAs(t, h, "GET", "/api/v1/library/search?q=Episode", sam.Token, nil)
	if hits := decode[SearchResults](t, resp).Episodes; len(hits) != 0 {
		t.Fatalf("non-subscriber search found %d episode hits", len(hits))
	}

	// Sam's pre-subscribe cursor still deltas cleanly and carries no
	// episode rows from the admin's subscribe.
	resp = reqAs(t, h, "GET", "/api/v1/sync/catalog?since="+samSince, sam.Token, nil)
	if resp.StatusCode != 200 {
		t.Fatalf("sam's delta status = %d", resp.StatusCode)
	}
	for _, e := range decode[CatalogSyncPage](t, resp).Entries {
		if e.Op == "upsert-show" || (e.Episode != nil) {
			t.Fatalf("another user's subscribe leaked into sam's delta: %+v", e)
		}
	}

	// Unsubscribing empties the caller's own view and retires their
	// catalog cursors so the mirror re-converges.
	req, _ := http.NewRequest("DELETE", h.ts.URL+"/api/v1/podcasts/"+sub.Show.Pid, nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	delResp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	delResp.Body.Close()
	if n := countEpisodes(h.token); n != 0 {
		t.Fatalf("episodes still listed after unsubscribe: %d", n)
	}
	resp = get(t, h.ts, "/api/v1/sync/catalog?since="+adminSince, h.token)
	if resp.StatusCode != 410 {
		t.Fatalf("post-unsubscribe delta status = %d, want 410 sync-reset", resp.StatusCode)
	}
	resp.Body.Close()

	// The fresh snapshot reflects the new membership: no shows, no
	// episodes, and the show stays browsable through its own surface.
	snapPath := "/api/v1/sync/catalog"
	for pages := 0; pages < 10; pages++ {
		r := get(t, h.ts, snapPath, h.token)
		snap := decode[CatalogSyncPage](t, r)
		for _, e := range snap.Entries {
			if e.Op == "upsert-show" || e.Episode != nil {
				t.Fatalf("unsubscribed snapshot still carries podcast rows: %+v", e)
			}
		}
		if snap.NextCursor == nil {
			break
		}
		snapPath = "/api/v1/sync/catalog?cursor=" + *snap.NextCursor
	}
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid, h.token)
	det := decode[PodcastDetail](t, resp)
	if det.Subscribed || det.Show.Title != "Fixture Cast" {
		t.Fatalf("show detail after unsubscribe = %+v", det)
	}
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	if eps := decode[EpisodePage](t, resp); len(eps.Items) != 2 {
		t.Fatalf("show's episode surface should stay browsable, got %d rows", len(eps.Items))
	}
}

func TestUnsubscribeRemovesDownloads(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 2)

	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)

	resp = h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	sub := decode[Subscription](t, resp)
	resp = reqAs(t, h, "POST", "/api/v1/podcasts", sam.Token, map[string]any{"url": feed.feedURL()})
	resp.Body.Close()

	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	eps := decode[EpisodePage](t, resp).Items
	for _, ep := range eps {
		r := h.postJSON(t, "/api/v1/episodes/"+ep.Pid+"/fetch", nil)
		r.Body.Close()
	}
	drainFetches(t, h)

	downloadedCount := func() int {
		r := get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
		n := 0
		for _, ep := range decode[EpisodePage](t, r).Items {
			if ep.Downloaded {
				n++
			}
		}
		return n
	}
	if n := downloadedCount(); n != 2 {
		t.Fatalf("fetched %d episodes, want 2", n)
	}

	// The admin leaves with the flag while sam still subscribes: the
	// files belong to sam's retention now, so the flag is ignored.
	resp = reqAs(t, h, "DELETE", "/api/v1/podcasts/"+sub.Show.Pid+"?removeDownloads=true", h.token, nil)
	if resp.StatusCode != 204 {
		t.Fatalf("admin unsubscribe status = %d, want 204", resp.StatusCode)
	}
	resp.Body.Close()
	if n := downloadedCount(); n != 2 {
		t.Fatalf("files vanished while a subscriber remains: %d downloaded, want 2", n)
	}

	// One episode goes back to remote with a fresh fetch queued, so the
	// cleanup must also cancel the queue: a surviving row would re-land
	// the file right after the last subscriber asked for it gone.
	resp = reqAs(t, h, "DELETE", "/api/v1/episodes/"+eps[0].Pid+"/fetch", sam.Token, nil)
	resp.Body.Close()
	resp = reqAs(t, h, "POST", "/api/v1/episodes/"+eps[0].Pid+"/fetch", sam.Token, nil)
	resp.Body.Close()

	// Sam is the last subscriber; the flag now reclaims the audio. The
	// episodes stay browsable (archive, never delete) but undownloaded,
	// and streaming refuses until fetched again.
	resp = reqAs(t, h, "DELETE", "/api/v1/podcasts/"+sub.Show.Pid+"?removeDownloads=true", sam.Token, nil)
	if resp.StatusCode != 204 {
		t.Fatalf("last unsubscribe status = %d, want 204", resp.StatusCode)
	}
	resp.Body.Close()
	drainFetches(t, h)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	rows := decode[EpisodePage](t, resp).Items
	if len(rows) != 2 {
		t.Fatalf("episode surface after cleanup has %d rows, want 2", len(rows))
	}
	for _, ep := range rows {
		if ep.Downloaded {
			t.Fatalf("episode %s still downloaded after last-subscriber cleanup", ep.Pid)
		}
	}
	// The files are gone; the feed enclosures are not, so the episodes
	// still play, by passthrough rather than from local bytes.
	resp = get(t, h.ts, "/api/v1/items/"+rows[0].Pid+"/play-info", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("play-info after cleanup = %d, want 200 by passthrough", resp.StatusCode)
	}
	if u := decode[PlayInfo](t, resp).Url; !strings.HasPrefix(u, "/media/enclosure?") {
		t.Fatalf("play-info url after cleanup = %q, want the passthrough relay", u)
	}
}

func TestUnsubscribeCleanupSkipsInUse(t *testing.T) {
	podcastDir := t.TempDir()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.PodcastDir = podcastDir
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
		cfg.RetentionInUseWindow = time.Hour
	})
	feed := newFeedServer(t, 1)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	sub := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	ep := decode[EpisodePage](t, resp).Items[0]
	r := h.postJSON(t, "/api/v1/episodes/"+ep.Pid+"/fetch", nil)
	r.Body.Close()
	drainFetches(t, h)

	// A fresh checkpoint reads as live playback even after the listener
	// unsubscribes; the cleanup skips the file instead of cutting the
	// stream, and the unsubscribe itself still succeeds.
	resp = reqAs(t, h, "PUT", "/api/v1/items/"+ep.Pid+"/play-state", h.token,
		map[string]any{"positionMs": 500})
	resp.Body.Close()
	resp = reqAs(t, h, "DELETE", "/api/v1/podcasts/"+sub.Show.Pid+"?removeDownloads=true", h.token, nil)
	if resp.StatusCode != 204 {
		t.Fatalf("unsubscribe status = %d, want 204", resp.StatusCode)
	}
	resp.Body.Close()
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	if !decode[EpisodePage](t, resp).Items[0].Downloaded {
		t.Fatal("cleanup removed a file that reads as actively played")
	}
}

func TestRemoveDownloadGuards(t *testing.T) {
	podcastDir := t.TempDir()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.PodcastDir = podcastDir
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
		// A real window, so an actively played episode refuses removal.
		cfg.RetentionInUseWindow = time.Hour
	})
	feed := newFeedServer(t, 1)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	sub := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	ep := decode[EpisodePage](t, resp).Items[0]
	r := h.postJSON(t, "/api/v1/episodes/"+ep.Pid+"/fetch", nil)
	r.Body.Close()
	drainFetches(t, h)

	// A non-subscriber may not reclaim the shared file.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)
	resp = reqAs(t, h, "DELETE", "/api/v1/episodes/"+ep.Pid+"/fetch", sam.Token, nil)
	if resp.StatusCode != 403 {
		t.Fatalf("non-subscriber remove status = %d, want 403", resp.StatusCode)
	}
	resp.Body.Close()

	// A fresh checkpoint reads as live playback; removal refuses
	// instead of killing the stream.
	resp = reqAs(t, h, "PUT", "/api/v1/items/"+ep.Pid+"/play-state", h.token,
		map[string]any{"positionMs": 500})
	resp.Body.Close()
	resp = reqAs(t, h, "DELETE", "/api/v1/episodes/"+ep.Pid+"/fetch", h.token, nil)
	if resp.StatusCode != 409 {
		t.Fatalf("in-use remove status = %d, want 409", resp.StatusCode)
	}
	// The removal path answers 409 for two unrelated reasons: this one,
	// and a busy file-mutation job lease. They mean opposite things to a
	// caller (wait for the listener, versus retry shortly), so only the
	// message tells them apart and this one must not read as the other.
	inUse := decode[Error](t, resp)
	if !strings.Contains(inUse.Message, "listening") ||
		strings.Contains(inUse.Message, "conflicting catalog job") {
		t.Fatalf("in-use refusal message = %q, want it to name the listener", inUse.Message)
	}
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	if !decode[EpisodePage](t, resp).Items[0].Downloaded {
		t.Fatal("refused removal must leave the file in place")
	}
}

// Queued analysis outliving its audio is what an archived episode leaves
// behind. Spending its attempts bars that audio for good, so a re-fetch
// of the identical file would never get a skip map. Both shapes of gone:
// an item cataloged without bytes, and an item that is not there at all.
func TestAnalysisWithNoAudioIsDroppedNotFailed(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	ctx := context.Background()

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	sub := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	ep := decode[EpisodePage](t, resp).Items[0]
	if ep.Downloaded {
		t.Fatal("this test wants the episode's bytes absent")
	}

	// Queued straight into the store, the state a fetch then an archive
	// arrives at. Not through an archive here, because the located-path
	// cache would answer the pre-archive path until its next poll.
	now := time.Now().UnixNano()
	if err := h.store.EnqueueAnalysis(ctx, "sha256/mp3-frames-v1:cataloged-but-absent", ep.Pid, now); err != nil {
		t.Fatal(err)
	}
	if err := h.store.EnqueueAnalysis(ctx, "sha256/mp3-frames-v1:no-such-item", "ep-01K0000000000000000000000", now+1); err != nil {
		t.Fatal(err)
	}

	for h.svc.DrainAnalysisQueue(ctx) {
	}

	// A year on, with an unexhaustable attempt budget: an entry still here
	// spent its attempts instead of being dropped.
	future := time.Now().Add(365 * 24 * time.Hour).UnixNano()
	if row, err := h.store.LeaseAnalysis(ctx, future, 0, 1000); !errors.Is(err, db.ErrNotFound) {
		t.Fatalf("analysis queue still holds %+v (err %v); work with no audio must be dropped", row, err)
	}
}

// The third shape of gone: a path the catalog still names whose bytes
// left the disk behind the server's back. Absent bytes under a live root
// are dropped; an absent root is storage that has not arrived, and its
// backlog has to survive it, which is the pair this covers.
func TestAnalysisWithMissingFileIsDropped(t *testing.T) {
	for _, tc := range []struct {
		name    string
		wipe    func(t *testing.T, podcastDir string)
		dropped bool
	}{
		{"the audio alone is gone", removeEpisodeAudio, true},
		{"the whole root is gone", func(t *testing.T, dir string) {
			t.Helper()
			if err := os.RemoveAll(dir); err != nil {
				t.Fatal(err)
			}
		}, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			podcastDir := t.TempDir()
			h := newHarnessWith(t, func(cfg *service.Config) {
				cfg.PodcastDir = podcastDir
				cfg.PodcastRootName = "podcasts"
				cfg.AllowPrivateFeedHosts = true
				cfg.RetentionInUseWindow = -1
			})
			feed := newFeedServer(t, 1)
			ctx := context.Background()

			resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
			sub := decode[Subscription](t, resp)
			resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
			ep := decode[EpisodePage](t, resp).Items[0]

			// The fetch queues the analysis; the audio goes away before the
			// worker runs, with the catalog still naming its path.
			r := h.postJSON(t, "/api/v1/episodes/"+ep.Pid+"/fetch", nil)
			r.Body.Close()
			drainFetches(t, h)
			tc.wipe(t, podcastDir)

			for h.svc.DrainAnalysisQueue(ctx) {
			}

			future := time.Now().Add(365 * 24 * time.Hour).UnixNano()
			row, err := h.store.LeaseAnalysis(ctx, future, 0, 1000)
			if tc.dropped {
				if !errors.Is(err, db.ErrNotFound) {
					t.Fatalf("analysis queue still holds %+v (err %v); a missing file must be dropped", row, err)
				}
				// Dropped, not measured: a map from audio the server cannot
				// read would be a fiction, so the engine is never asked.
				resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/skip-map", h.token)
				if sm := decode[SkipMap](t, resp); sm.State == "ready" {
					t.Fatalf("skip map = %+v; a missing file must not produce one", sm)
				}
				return
			}
			if err != nil {
				t.Fatalf("leasing after an absent root = %v; the entry must outlive the mount", err)
			}
		})
	}
}

// removeEpisodeAudio deletes the audio a fetch wrote, leaving the root.
func removeEpisodeAudio(t *testing.T, podcastDir string) {
	t.Helper()
	removed := 0
	if err := filepath.WalkDir(podcastDir, func(p string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() || filepath.Ext(p) != ".mp3" {
			return err
		}
		if err := os.Remove(p); err != nil {
			return err
		}
		removed++
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if removed == 0 {
		t.Fatal("the fetch wrote no audio to delete")
	}
}

// Fetch, archive, re-fetch is ordinary podcast life, and the bytes come
// back where the located-path cache saw none: until it polls, the episode
// reports downloaded while everything resolving its path answers
// not-found.
func TestRefetchedEpisodePlaysAtOnce(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	ctx := context.Background()

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	sub := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	ep := decode[EpisodePage](t, resp).Items[0]

	fetch := func() {
		t.Helper()
		r := h.postJSON(t, "/api/v1/episodes/"+ep.Pid+"/fetch", nil)
		r.Body.Close()
		if r.StatusCode != 202 {
			t.Fatalf("fetch status = %d, want 202", r.StatusCode)
		}
		drainFetches(t, h)
	}

	fetch()
	resp = h.deleteReq(t, "/api/v1/episodes/"+ep.Pid+"/fetch")
	if resp.StatusCode != 204 {
		t.Fatalf("archive status = %d, want 204", resp.StatusCode)
	}
	resp.Body.Close()

	// The same bytes land again: playable now, not when a cache next
	// polls, and analyzable, which takes the fetch resolving the file it
	// just wrote rather than the absence it remembers.
	fetch()
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("play-info right after a re-fetch = %d, want 200", resp.StatusCode)
	}
	for h.svc.DrainAnalysisQueue(ctx) {
	}
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/skip-map", h.token)
	sm := decode[SkipMap](t, resp)
	if sm.State != "ready" || sm.Spans == nil || len(*sm.Spans) == 0 {
		t.Fatalf("skip map after re-fetch and analysis = %+v", sm)
	}
}

// TestEnclosurePassthrough covers the relay an unfetched episode plays
// through: the URL is minted from the episode rather than taken from the
// caller, ranges pass both ways, and the podcast host's own headers stay
// on the host's side of the relay.
func TestEnclosurePassthrough(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServerWithHeaders(t, 1, http.Header{
		"Set-Cookie":     []string{"host_session=leaked; Path=/"},
		"Server":         []string{"PodcastHost/9.9"},
		"X-Host-Tracker": []string{"listener-42"},
	})

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	sub := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	ep := decode[EpisodePage](t, resp).Items[0]
	if ep.Downloaded {
		t.Fatal("the episode should not be fetched for this test")
	}

	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)
	info := decode[PlayInfo](t, resp)
	if !strings.HasPrefix(info.Url, "/media/enclosure?") {
		t.Fatalf("play-info url = %q, want the passthrough relay", info.Url)
	}

	// A whole-file read: the feed's audio arrives, with the allowlisted
	// headers and nothing the host tried to add alongside them.
	whole := get(t, h.ts, info.Url, "")
	body, err := io.ReadAll(whole.Body)
	whole.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	if whole.StatusCode != 200 {
		t.Fatalf("passthrough status = %d, want 200", whole.StatusCode)
	}
	if len(body) == 0 {
		t.Fatal("passthrough served no bytes")
	}
	if got := whole.Header.Get("Content-Type"); got != "audio/mpeg" {
		t.Errorf("Content-Type = %q, want the enclosure type", got)
	}
	if whole.Header.Get("Accept-Ranges") != "bytes" {
		t.Errorf("Accept-Ranges = %q, want bytes", whole.Header.Get("Accept-Ranges"))
	}
	for _, blocked := range []string{"Set-Cookie", "Server", "X-Host-Tracker"} {
		if v := whole.Header.Get(blocked); v != "" {
			t.Errorf("the podcast host's %s reached the client: %q", blocked, v)
		}
	}

	// A range request: forwarded upstream, and the 206 comes back with
	// the window the client asked for.
	req, _ := http.NewRequest("GET", h.ts.URL+info.Url, nil)
	req.Header.Set("Range", "bytes=10-19")
	ranged, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	part, err := io.ReadAll(ranged.Body)
	ranged.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	if ranged.StatusCode != http.StatusPartialContent {
		t.Fatalf("ranged passthrough status = %d, want 206", ranged.StatusCode)
	}
	if len(part) != 10 {
		t.Fatalf("ranged passthrough served %d bytes, want 10", len(part))
	}
	if !bytes.Equal(part, body[10:20]) {
		t.Error("the ranged window is not the same bytes as the whole-file read")
	}
	wantRange := fmt.Sprintf("bytes 10-19/%d", len(body))
	if got := ranged.Header.Get("Content-Range"); got != wantRange {
		t.Errorf("Content-Range = %q, want %q", got, wantRange)
	}

	// The token binds one episode. A token minted for something else
	// cannot borrow this relay, which is what keeps it from being a
	// general-purpose proxy.
	swapped := strings.Replace(info.Url, "pid="+ep.Pid, "pid="+sub.Show.Pid, 1)
	denied := get(t, h.ts, swapped, "")
	denied.Body.Close()
	if denied.StatusCode != 401 {
		t.Errorf("a token for another pid = %d, want 401", denied.StatusCode)
	}
}

// TestEnclosurePassthroughFollowsTrackerChains holds the relay to what
// real enclosures look like: measurement prefixes stack several
// redirects in front of the audio (a verified show walks seven hops -
// podtrac, claritas, pdst, mgln, pscrb, then art19 and its CDN), and a
// cap tighter than that turned every one of its episodes into a bad
// gateway. The cap still exists; past ten hops is refused as the loop
// guard it is.
func TestEnclosurePassthroughFollowsTrackerChains(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	feed.enclosurePrefix = "/hop/7"
	feed.writeFeed(t, 1)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	sub := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	ep := decode[EpisodePage](t, resp).Items[0]
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)
	info := decode[PlayInfo](t, resp)

	whole := get(t, h.ts, info.Url, "")
	body, err := io.ReadAll(whole.Body)
	whole.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	if whole.StatusCode != 200 {
		t.Fatalf("chained passthrough status = %d, want 200", whole.StatusCode)
	}
	if len(body) == 0 {
		t.Fatal("chained passthrough served no bytes")
	}

	runaway := newFeedServer(t, 1)
	runaway.enclosurePrefix = "/hop/12"
	runaway.writeFeed(t, 1)
	resp = h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": runaway.feedURL()})
	sub2 := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub2.Show.Pid+"/episodes", h.token)
	ep2 := decode[EpisodePage](t, resp).Items[0]
	resp = get(t, h.ts, "/api/v1/items/"+ep2.Pid+"/play-info", h.token)
	info2 := decode[PlayInfo](t, resp)

	blocked := get(t, h.ts, info2.Url, "")
	blocked.Body.Close()
	if blocked.StatusCode != http.StatusBadGateway {
		t.Fatalf("runaway chain status = %d, want 502", blocked.StatusCode)
	}
}

// TestEnclosurePassthroughNeedsAnEnclosure keeps the conflict for the
// one population passthrough cannot serve: an episode whose feed named
// no audio at all.
func TestEnclosurePassthroughNeedsAnEnclosure(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	feed.writeEnclosureless(t)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	sub := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	page := decode[EpisodePage](t, resp)
	if len(page.Items) == 0 {
		t.Fatal("the enclosureless feed produced no episodes")
	}
	// The one episode nothing can play, and the field that says so
	// before a client offers the affordance.
	if hs := page.Items[0].HasEnclosure; hs != nil && *hs {
		t.Fatal("an episode with no enclosure must not report hasEnclosure")
	}
	resp = get(t, h.ts, "/api/v1/items/"+page.Items[0].Pid+"/play-info", h.token)
	defer resp.Body.Close()
	if resp.StatusCode != 409 {
		t.Fatalf("enclosureless episode play-info status = %d, want 409", resp.StatusCode)
	}
}

// TestAutoDownloadFilterUnion is the filter at the only place it is
// consulted: a feed refresh deciding what to fetch of what it just
// added. Two subscribers with different filters mean the decision is per
// subscriber and per episode, and the union takes an episode either one
// wants, because the downloaded file is shared.
func TestAutoDownloadFilterUnion(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 5)
	feed.writeFeed(t, 2) // the show starts with two episodes published
	ctx := context.Background()

	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)

	resp = h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	show := decode[Subscription](t, resp).Show.Pid
	resp = reqAs(t, h, "POST", "/api/v1/podcasts", sam.Token, map[string]any{"url": feed.feedURL()})
	resp.Body.Close()

	// The admin wants episode 3 only; sam wants everything except
	// episodes 3 and 5. Between them, 3 and 4 are wanted and 5 is not.
	resp = reqAs(t, h, "PUT", "/api/v1/podcasts/"+show+"/settings", h.token, map[string]any{
		"autoDownload":       true,
		"autoDownloadFilter": map[string]any{"include": []string{"episode 3"}},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("admin settings status = %d", resp.StatusCode)
	}
	settings := decode[Subscription](t, resp).Settings
	if settings.AutoDownloadFilter == nil || settings.AutoDownloadFilter.Include == nil ||
		len(*settings.AutoDownloadFilter.Include) != 1 {
		t.Fatalf("the filter did not round-trip: %+v", settings.AutoDownloadFilter)
	}
	resp = reqAs(t, h, "PUT", "/api/v1/podcasts/"+show+"/settings", sam.Token, map[string]any{
		"autoDownload":       true,
		"autoDownloadFilter": map[string]any{"exclude": []string{"Episode 3", "EPISODE 5"}},
	})
	resp.Body.Close()

	// The feed publishes three more; the refresh decides what to fetch.
	feed.writeFeed(t, 5)
	h.svc.RefreshDueFeeds(ctx, 0)
	drainFetches(t, h)

	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	byTitle := map[string]bool{}
	for _, ep := range decode[EpisodePage](t, resp).Items {
		byTitle[ep.Title] = ep.Downloaded
	}
	for _, want := range []string{"Episode 3", "Episode 4"} {
		if !byTitle[want] {
			t.Errorf("%s was wanted by a subscriber and not fetched", want)
		}
	}
	if byTitle["Episode 5"] {
		t.Error("Episode 5 was excluded by the only filter that could admit it")
	}
	// The two that were already published are untouched: a filter
	// applies to what a refresh adds, never to the backlog.
	for _, old := range []string{"Episode 1", "Episode 2"} {
		if byTitle[old] {
			t.Errorf("%s is backlog and must not be fetched by a filter change", old)
		}
	}
}

// TestEnclosurePassthroughCarriesFeedCredentials is the private-feed
// half of passthrough. A paid host refuses an unauthenticated GET, so a
// relay that forgot the show's stored credentials would 401 on exactly
// the feeds a listener paid for, while fetching the same episode works:
// WaxBin's download passes the same pair, and so does the transcript
// fetch.
func TestEnclosurePassthroughCarriesFeedCredentials(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newPrivateFeedServer(t, 1, "member", "s3cret")

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{
		"url": feed.feedURL(), "username": "member", "password": "s3cret",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe to a private feed status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	ep := decode[EpisodePage](t, resp).Items[0]
	if ep.Downloaded {
		t.Fatal("the episode should not be fetched for this test")
	}

	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("private-feed play-info status = %d, want 200", resp.StatusCode)
	}
	relay := decode[PlayInfo](t, resp).Url
	if !strings.HasPrefix(relay, "/media/enclosure?") {
		t.Fatalf("play-info url = %q, want the passthrough relay", relay)
	}

	streamed := get(t, h.ts, relay, "")
	body, err := io.ReadAll(streamed.Body)
	streamed.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	if streamed.StatusCode != 200 {
		t.Fatalf("private-feed passthrough status = %d, want 200; the relay dropped the show's credentials", streamed.StatusCode)
	}
	if len(body) == 0 {
		t.Fatal("private-feed passthrough served no bytes")
	}
	// The credentials are the server's to spend, never the listener's to
	// see: nothing about them may reach the client.
	if v := streamed.Header.Get("Www-Authenticate"); v != "" {
		t.Errorf("the host's auth challenge reached the client: %q", v)
	}
}

// TestEnclosurePassthroughWithheldFromNonSubscribers is the other half
// of the same decision. An episode read stays open to anyone who can see
// the podcast library, so without a check any account on the server
// would stream a paid feed on the strength of somebody else's
// subscription. The credentials are the show's and every subscriber
// shares them, but a non-subscriber is not one of them.
func TestEnclosurePassthroughWithheldFromNonSubscribers(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newPrivateFeedServer(t, 1, "member", "s3cret")

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{
		"url": feed.feedURL(), "username": "member", "password": "s3cret",
	})
	sub := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	ep := decode[EpisodePage](t, resp).Items[0]

	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)

	// Sam can see the episode but does not subscribe, so passthrough is
	// not minted for them: play-info reports the same conflict an
	// episode with no audio anywhere would.
	resp = reqAs(t, h, "GET", "/api/v1/items/"+ep.Pid+"/play-info", sam.Token, nil)
	samStatus := resp.StatusCode
	samURL := ""
	if samStatus == 200 {
		samURL = decode[PlayInfo](t, resp).Url
	} else {
		resp.Body.Close()
	}
	if samStatus == 200 && strings.HasPrefix(samURL, "/media/enclosure?") {
		t.Fatal("a non-subscriber was handed a relay URL for a credentialed feed")
	}

	// Sam asking the relay directly is refused the same way, so the
	// check is on the endpoint rather than only on the mint: a media
	// token names its user, and the relay resolves credentials for that
	// user, so sam's own token buys sam nothing here.
	token, _ := h.media.MintFor(sam.User.Id, ep.Pid, time.Hour)
	direct := get(t, h.ts, "/media/enclosure?pid="+ep.Pid+"&mt="+token, "")
	direct.Body.Close()
	if direct.StatusCode != 403 {
		t.Errorf("a non-subscriber at the relay = %d, want 403", direct.StatusCode)
	}

	// Not asserted, and worth naming: a relay URL minted for the
	// subscriber streams the paid feed for anyone holding it until the
	// token expires, because the token is the capability. That is what
	// a media token is everywhere in this server, not something this
	// endpoint introduces.
}

// TestOneSidedFilterHasNoNullsOnTheWire pins the wire form of a filter
// that names only one side, which is the common shape: a listener
// excluding trailers writes no include list at all.
//
// The trap is Go's own: `omitempty` on a *[]string omits a nil pointer,
// not a pointer to a nil slice, so guarding the pair rather than each
// field puts `"include": null` on the wire. The schema declares both
// sides as plain arrays and neither as nullable, so that answer is off
// contract for anything that validates it.
func TestOneSidedFilterHasNoNullsOnTheWire(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	show := decode[Subscription](t, resp).Show.Pid

	for _, tc := range []struct {
		name   string
		filter map[string]any
	}{
		{"exclude only", map[string]any{"exclude": []string{"bonus"}}},
		{"include only", map[string]any{"include": []string{"mailbag"}}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			resp := reqAs(t, h, "PUT", "/api/v1/podcasts/"+show+"/settings", h.token,
				map[string]any{"autoDownload": true, "autoDownloadFilter": tc.filter})
			body, err := io.ReadAll(resp.Body)
			resp.Body.Close()
			if err != nil {
				t.Fatal(err)
			}
			if resp.StatusCode != 200 {
				t.Fatalf("settings status = %d: %s", resp.StatusCode, body)
			}
			if strings.Contains(string(body), "null") {
				t.Errorf("a one-sided filter put a null on the wire: %s", body)
			}
			// The side that was set still round-trips; the fix must not
			// have dropped both.
			var got struct {
				Settings struct {
					AutoDownloadFilter map[string][]string `json:"autoDownloadFilter"`
				} `json:"settings"`
			}
			if err := json.Unmarshal(body, &got); err != nil {
				t.Fatal(err)
			}
			for key, want := range tc.filter {
				terms := want.([]string)
				if len(got.Settings.AutoDownloadFilter[key]) != len(terms) {
					t.Errorf("%s did not round-trip: %s", key, body)
				}
			}
			// And the unset side is absent rather than present-and-empty.
			for _, key := range []string{"include", "exclude"} {
				if _, set := tc.filter[key]; set {
					continue
				}
				if _, present := got.Settings.AutoDownloadFilter[key]; present {
					t.Errorf("the unset %s side is on the wire: %s", key, body)
				}
			}
		})
	}
}

// TestEnclosureRelayProbesAndDegrades covers the three shapes a real
// podcast host and a real client produce that the happy path does not:
// a HEAD probe, a host that ignores ranges, and the header allowlist on
// a ranged answer rather than only on a whole-file one.
func TestEnclosureRelayProbesAndDegrades(t *testing.T) {
	h := newPodcastHarness(t)

	// A host that answers every request whole, ignoring Range, and adds
	// headers of its own to both shapes.
	var sawRange, sawMethod string
	feed := newFeedServer(t, 1)
	files := http.FileServer(http.Dir(feed.dir))
	feed.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, ".mp3") {
			sawRange, sawMethod = r.Header.Get("Range"), r.Method
			w.Header().Set("Set-Cookie", "host_session=leaked; Path=/")
			w.Header().Set("X-Host-Tracker", "listener-42")
			// Deliberately no 206 and no Accept-Ranges: the host does
			// not do ranges, which the spec's seekable caveat exists for.
			r.Header.Del("Range")
		}
		files.ServeHTTP(w, r)
	})

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	sub := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	ep := decode[EpisodePage](t, resp).Items[0]
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)
	relay := decode[PlayInfo](t, resp).Url

	// A range the host ignores degrades to a whole 200 rather than
	// failing: play-info promised seekable as best effort, not as a fact.
	req, _ := http.NewRequest("GET", h.ts.URL+relay, nil)
	req.Header.Set("Range", "bytes=10-19")
	ranged, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, err := io.ReadAll(ranged.Body)
	ranged.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	if ranged.StatusCode != 200 {
		t.Fatalf("a host that ignores ranges = %d, want the whole 200 relayed", ranged.StatusCode)
	}
	if len(body) <= 10 {
		t.Fatalf("the degraded answer served %d bytes, want the whole file", len(body))
	}
	if sawRange != "bytes=10-19" {
		t.Errorf("the host saw Range %q, want the client's own", sawRange)
	}
	// The allowlist holds on this shape too, which the whole-file test
	// alone would not show.
	for _, blocked := range []string{"Set-Cookie", "X-Host-Tracker"} {
		if v := ranged.Header.Get(blocked); v != "" {
			t.Errorf("the host's %s reached the client on a ranged read: %q", blocked, v)
		}
	}

	if sawMethod != http.MethodGet {
		t.Errorf("the upstream request was %q", sawMethod)
	}
}

// TestEnclosureHeadDoesNotPullTheEpisode is the cast and Safari probe.
// Go's ServeMux routes HEAD to a GET pattern, so it reaches the relay,
// and net/http discards whatever a handler writes for one -- which is
// why the body a client sees proves nothing here and the assertion is
// on what the podcast host was made to serve. Without a HEAD branch the
// relay reads the whole episode and throws it away.
func TestEnclosureHeadDoesNotPullTheEpisode(t *testing.T) {
	h := newPodcastHarness(t)

	// The enclosure is large enough that pulling it is unmistakable
	// against whatever the transport buffers ahead of the first read.
	const size = 8 << 20
	var served atomic.Int64
	feed := newFeedServer(t, 1)
	files := http.FileServer(http.Dir(feed.dir))
	feed.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasSuffix(r.URL.Path, ".mp3") {
			files.ServeHTTP(w, r)
			return
		}
		w.Header().Set("Content-Type", "audio/mpeg")
		w.Header().Set("Content-Length", strconv.Itoa(size))
		w.WriteHeader(http.StatusOK)
		buf := make([]byte, 32<<10)
		for sent := 0; sent < size; sent += len(buf) {
			n, err := w.Write(buf)
			served.Add(int64(n))
			if err != nil {
				return
			}
		}
	})

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	sub := decode[Subscription](t, resp)
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	ep := decode[EpisodePage](t, resp).Items[0]
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)
	relay := decode[PlayInfo](t, resp).Url

	req, _ := http.NewRequest("HEAD", h.ts.URL+relay, nil)
	head, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, err := io.ReadAll(head.Body)
	head.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	if head.StatusCode != 200 {
		t.Fatalf("HEAD on the relay = %d, want 200", head.StatusCode)
	}
	if len(body) != 0 {
		t.Errorf("HEAD returned %d body bytes", len(body))
	}
	// The headers are the whole point of a probe, so they still have to
	// be the episode's.
	if ct := head.Header.Get("Content-Type"); ct != "audio/mpeg" {
		t.Errorf("HEAD Content-Type = %q, want the episode's", ct)
	}
	if cl := head.Header.Get("Content-Length"); cl != strconv.Itoa(size) {
		t.Errorf("HEAD Content-Length = %q, want %d", cl, size)
	}
	// The host may have pushed some bytes before the relay let go; what
	// must not happen is the whole episode moving for a probe.
	//
	// The residue is not the relay reading ahead: it is the loopback
	// socket buffers between the two, which the fixture handler counts
	// as served the moment the kernel accepts them. Linux autotunes
	// those into the megabytes, so a tight fraction here measures
	// `tcp_wmem` rather than this handler and fails on a box whose
	// buffers have warmed up. Half the episode is the honest line: no
	// socket buffer reaches it, and a relay missing its HEAD branch
	// moves all 8 MB straight past it.
	if got := served.Load(); got > size/2 {
		t.Errorf("a HEAD probe pulled %d bytes of a %d byte episode", got, size)
	}
}

// TestSubscribedEpisodesAndUnplayedCount covers the two reads the hub is
// built on. Both exist because nothing else on the wire answers them: a
// discovery list is over the whole library and returns generic summary
// rows, and an unplayed backlog is an aggregate a client holding one
// page of episodes cannot compute without claiming a window is the whole.
func TestSubscribedEpisodesAndUnplayedCount(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 3)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	show := decode[Subscription](t, resp).Show.Pid

	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	episodes := decode[EpisodePage](t, resp).Items
	if len(episodes) != 3 {
		t.Fatalf("episodes = %d, want 3", len(episodes))
	}

	// Nothing played yet: the whole feed is the backlog.
	if got := unplayedFor(t, h, show); got != 3 {
		t.Fatalf("unplayedCount = %d before any listening, want 3", got)
	}

	// The tile's other two numbers come from the same view of the show,
	// so a subscription row can order by recency and say how big a show
	// is. Both were absent before, which made the hub's default sort a
	// no-op.
	resp = get(t, h.ts, "/api/v1/podcasts", h.token)
	row := decode[SubscriptionPage](t, resp).Items[0]
	if row.Show.EpisodeCount == nil || *row.Show.EpisodeCount != 3 {
		t.Errorf("subscription row episodeCount = %v, want 3", row.Show.EpisodeCount)
	}
	if row.Show.LastPublishedAt == nil {
		t.Error("a subscription row carries no lastPublishedAt to sort by")
	}

	// Absent, not zero, where nothing computed it: the response to
	// subscribing would otherwise tell a client that just followed a
	// backlog it has nothing waiting.
	resp = h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	if again := decode[Subscription](t, resp).UnplayedCount; again != nil {
		t.Errorf("subscribe answered unplayedCount %d; it computes none", *again)
	}
	resp = reqAs(t, h, "PUT", "/api/v1/podcasts/"+show+"/settings", h.token,
		map[string]any{"autoDownload": false})
	if saved := decode[Subscription](t, resp).UnplayedCount; saved != nil {
		t.Errorf("saving settings answered unplayedCount %d; it computes none", *saved)
	}

	// Newest first, and every row carries the two fields a hub row needs
	// and a generic summary has not got.
	resp = get(t, h.ts, "/api/v1/podcasts/episodes?filter=latest", h.token)
	latest := decode[EpisodePage](t, resp).Items
	if len(latest) != 3 {
		t.Fatalf("latest = %d, want 3", len(latest))
	}
	for _, ep := range latest {
		if ep.ShowPid != show {
			t.Errorf("row %s carries showPid %q, want %q", ep.Pid, ep.ShowPid, show)
		}
		if ep.HasEnclosure == nil || !*ep.HasEnclosure {
			t.Errorf("row %s should report an enclosure the relay can serve", ep.Pid)
		}
	}
	for i := 1; i < len(latest); i++ {
		if latest[i-1].PublishedAt.Before(latest[i].PublishedAt) {
			t.Fatalf("latest is not newest first: %v then %v",
				latest[i-1].PublishedAt, latest[i].PublishedAt)
		}
	}

	// Finish one and start another. Played is derived from the position
	// reached against the item's duration, and none of these have been
	// fetched. The catalog coalesces to the length the feed declared,
	// which is what makes a backlog markable without downloading it.
	finished, started := latest[0], latest[1]
	putPlayState(t, h, finished.Pid, finished.DurationMs)
	putPlayState(t, h, started.Pid, 1_000)

	if got := unplayedFor(t, h, show); got != 2 {
		t.Errorf("unplayedCount = %d after finishing one, want 2", got)
	}

	resp = get(t, h.ts, "/api/v1/podcasts/episodes?filter=unplayed", h.token)
	for _, ep := range decode[EpisodePage](t, resp).Items {
		if ep.Pid == finished.Pid {
			t.Error("a finished episode is still in the unplayed listing")
		}
	}

	resp = get(t, h.ts, "/api/v1/podcasts/episodes?filter=in-progress", h.token)
	inProgress := decode[EpisodePage](t, resp).Items
	if len(inProgress) != 1 || inProgress[0].Pid != started.Pid {
		t.Fatalf("in-progress = %+v, want only the started episode", inProgress)
	}

	// An unknown filter is refused rather than silently answered as
	// latest, since a client asking for one it invented is a bug.
	resp = get(t, h.ts, "/api/v1/podcasts/episodes?filter=whatever", h.token)
	resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Errorf("unknown filter status = %d, want 400", resp.StatusCode)
	}

	// A cursor carries the filter it was issued under. The two orders
	// interleave differently (publication time against last-played time),
	// so resuming one from the other's boundary would answer a page
	// that looks right and is not.
	resp = get(t, h.ts, "/api/v1/podcasts/episodes?filter=latest&limit=1", h.token)
	page := decode[EpisodePage](t, resp)
	if page.NextCursor == nil {
		t.Fatal("a capped page should carry a cursor")
	}
	resp = get(t, h.ts,
		"/api/v1/podcasts/episodes?filter=in-progress&cursor="+*page.NextCursor, h.token)
	resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Errorf("a cursor reused under another filter = %d, want 400", resp.StatusCode)
	}
	// Under its own filter it pages, rather than being refused for the
	// sake of it.
	resp = get(t, h.ts,
		"/api/v1/podcasts/episodes?filter=latest&cursor="+*page.NextCursor, h.token)
	rest := decode[EpisodePage](t, resp).Items
	if len(rest) != 2 || rest[0].Pid == page.Items[0].Pid {
		t.Errorf("paging under the issuing filter answered %d rows starting at %v",
			len(rest), rest)
	}

	// Unfollowing empties the listing: it is over what the caller
	// follows, not over what the catalog holds.
	resp = reqAs(t, h, "DELETE", "/api/v1/podcasts/"+show, h.token, nil)
	resp.Body.Close()
	resp = get(t, h.ts, "/api/v1/podcasts/episodes?filter=latest", h.token)
	if got := decode[EpisodePage](t, resp).Items; len(got) != 0 {
		t.Errorf("an unfollowed show still lists %d episodes", len(got))
	}
}

// The cross-show listing is a keyset browse of the catalog, so what it
// must prove is what a Go sort over every followed show used to make
// trivially true: rows from different shows interleave by publication
// date and page across a show boundary without a duplicate or a gap.
func TestSubscribedEpisodesInterleaveAcrossShows(t *testing.T) {
	h := newPodcastHarness(t)
	// Two feeds a day out of step with each other, so the merged order
	// alternates between them and every page of two straddles a show
	// boundary.
	dayOne := time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC)
	odd := newCountsFeedAs(t, countsChannel{firstPublished: dayOne},
		[]countsEpisode{{title: "A1"}, {title: "A2"}, {title: "A3"}})
	even := newCountsFeedAs(t, countsChannel{firstPublished: dayOne.Add(12 * time.Hour)},
		[]countsEpisode{{title: "B1"}, {title: "B2"}, {title: "B3"}})
	for _, f := range []*countsFeed{odd, even} {
		resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": f.feedURL()})
		wantStatus(t, resp, 201, "subscribe")
	}

	resp := get(t, h.ts, "/api/v1/podcasts/episodes?filter=latest", h.token)
	all := decode[EpisodePage](t, resp).Items
	if len(all) != 6 {
		t.Fatalf("latest = %d rows, want all 6", len(all))
	}
	for i := 1; i < len(all); i++ {
		if all[i-1].ShowPid == all[i].ShowPid {
			t.Fatalf("rows %d and %d are from the same show; the two feeds should alternate", i-1, i)
		}
		if all[i-1].PublishedAt.Before(all[i].PublishedAt) {
			t.Fatalf("latest is not newest first at row %d", i)
		}
	}

	// Page it two at a time and rebuild the same list.
	var paged []EpisodeSummary
	cursor := ""
	for range 5 {
		path := "/api/v1/podcasts/episodes?filter=latest&limit=2"
		if cursor != "" {
			path += "&cursor=" + cursor
		}
		resp = get(t, h.ts, path, h.token)
		page := decode[EpisodePage](t, resp)
		paged = append(paged, page.Items...)
		if page.NextCursor == nil {
			break
		}
		cursor = *page.NextCursor
	}
	if len(paged) != len(all) {
		t.Fatalf("paged %d rows, want the same %d", len(paged), len(all))
	}
	seen := map[string]bool{}
	for i, ep := range paged {
		if seen[ep.Pid] {
			t.Errorf("row %d (%s) is a duplicate across pages", i, ep.Pid)
		}
		seen[ep.Pid] = true
		if ep.Pid != all[i].Pid {
			t.Errorf("paged row %d = %s, want %s (paging reordered the listing)", i, ep.Pid, all[i].Pid)
		}
	}
}

// The keyset the listing rides on is the publication date, so an episode
// without one cannot appear in it. Its own show still lists it: the
// exclusion is the cross-show order's, not a disappearance.
func TestSubscribedEpisodesExcludeUndated(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newCountsFeed(t, []countsEpisode{
		{title: "Dated"},
		{title: "Undated", undated: true},
	})
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	show := decode[Subscription](t, resp).Show.Pid

	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	own := decode[EpisodePage](t, resp).Items
	if len(own) != 2 {
		t.Fatalf("the show's own listing = %d rows, want both", len(own))
	}
	var undated string
	for _, ep := range own {
		if ep.Title == "Undated" {
			undated = ep.Pid
		}
	}
	if undated == "" {
		t.Fatal("no undated episode in the show's listing")
	}

	for _, filter := range []string{"latest", "unplayed"} {
		resp = get(t, h.ts, "/api/v1/podcasts/episodes?filter="+filter, h.token)
		rows := decode[EpisodePage](t, resp).Items
		if len(rows) != 1 {
			t.Errorf("%s = %d rows, want only the dated one", filter, len(rows))
		}
		for _, ep := range rows {
			if ep.Pid == undated {
				t.Errorf("%s carries the undated episode", filter)
			}
		}
	}

	// The tile still counts it: the backlog is what is waiting, whatever
	// the feed declared about dates.
	if got := unplayedFor(t, h, show); got != 2 {
		t.Errorf("unplayedCount = %d, want both episodes", got)
	}
}

// The gate rides in the query now, so it holds on the cross-show listing
// exactly as it holds on a show's own.
func TestSubscribedEpisodesHideExplicitFromRestricted(t *testing.T) {
	h := newPodcastHarness(t)
	flagged := newCountsFeed(t, []countsEpisode{
		{title: "Clean"},
		{title: "Explicit", explicit: true},
	})
	explicitShow := newCountsFeedAs(t, countsChannel{explicit: true}, []countsEpisode{
		{title: "Unflagged Of A Flagged Show"},
	})

	id, listener := listenerAccount(t, h, "cross-shielded", true)
	for _, f := range []*countsFeed{flagged, explicitShow} {
		resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": f.feedURL()})
		wantStatus(t, resp, 201, "admin subscribe")
		resp = reqAs(t, h, "POST", "/api/v1/podcasts", listener, map[string]any{"url": f.feedURL()})
		wantStatus(t, resp, 201, "listener subscribe while allowed")
	}
	resp := h.patchJSON(t, "/api/v1/users/"+id, map[string]any{
		"permissions": map[string]any{
			"download": true, "delete": false, "explicitContent": false,
			"sharedOutputs": true, "managePodcasts": true,
		},
	})
	wantStatus(t, resp, 200, "revoke explicit content")

	resp = get(t, h.ts, "/api/v1/podcasts/episodes?filter=latest", h.token)
	if got := decode[EpisodePage](t, resp).Items; len(got) != 3 {
		t.Fatalf("open latest = %d rows, want all 3", len(got))
	}
	resp = reqAs(t, h, "GET", "/api/v1/podcasts/episodes?filter=latest", listener, nil)
	rows := decode[EpisodePage](t, resp).Items
	if len(rows) != 1 {
		t.Fatalf("restricted latest = %d rows, want only the clean one", len(rows))
	}
	if rows[0].Title != "Clean" {
		t.Errorf("restricted latest kept %q, want Clean", rows[0].Title)
	}
}

// The listing gate and the per-item gate are separate code paths: a
// listing filters in the query, while play-info decides one item through
// allowedByContent. Both flags have to hold on the second path too, or a
// restricted listener who cannot see an episode in any list can still
// mint a stream URL for it by pid.
func TestPlayInfoRefusesExplicitEpisodesForRestricted(t *testing.T) {
	h := newPodcastHarness(t)
	flagged := newCountsFeed(t, []countsEpisode{
		{title: "Clean"},
		{title: "Explicit", explicit: true},
	})
	explicitShow := newCountsFeedAs(t, countsChannel{explicit: true}, []countsEpisode{
		{title: "Unflagged Of A Flagged Show"},
	})

	id, listener := listenerAccount(t, h, "playinfo-shielded", true)
	for _, f := range []*countsFeed{flagged, explicitShow} {
		resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": f.feedURL()})
		wantStatus(t, resp, 201, "admin subscribe")
		resp = reqAs(t, h, "POST", "/api/v1/podcasts", listener, map[string]any{"url": f.feedURL()})
		wantStatus(t, resp, 201, "listener subscribe while allowed")
	}

	// Collected while still permitted, so the pids are the ones the
	// listener legitimately held before the permission was revoked.
	resp := reqAs(t, h, "GET", "/api/v1/podcasts/episodes?filter=latest", listener, nil)
	byTitle := map[string]string{}
	for _, ep := range decode[EpisodePage](t, resp).Items {
		byTitle[ep.Title] = ep.Pid
	}
	if len(byTitle) != 3 {
		t.Fatalf("episodes before revocation = %v, want all 3", byTitle)
	}

	resp = h.patchJSON(t, "/api/v1/users/"+id, map[string]any{
		"permissions": map[string]any{
			"download": true, "delete": false, "explicitContent": false,
			"sharedOutputs": true, "managePodcasts": true,
		},
	})
	wantStatus(t, resp, 200, "revoke explicit content")

	for _, tc := range []struct {
		title string
		want  int
	}{
		{"Clean", 200},
		{"Explicit", 404},                    // the episode's own flag
		{"Unflagged Of A Flagged Show", 404}, // the show's flag
	} {
		t.Run(tc.title, func(t *testing.T) {
			resp := reqAs(t, h, "GET", "/api/v1/items/"+byTitle[tc.title]+"/play-info", listener, nil)
			wantStatus(t, resp, tc.want, "restricted play-info for "+tc.title)
		})
	}
}

// Audio deleted behind the server's back is discovered by the analysis
// worker and recorded, so the skip map stops answering pending forever.
//
// The GET used to resolve the path itself to avoid that - a stat and
// possibly a relocate inside the request, which blocked on an unmounted
// network root. The catalog takes the correction now: first GET queues,
// the worker finds nothing and marks the item missing, second GET reads
// the state. That is what pending has always promised.
func TestSkipMapReportsAudioDeletedBehindTheServersBack(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)

	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	show := decode[Subscription](t, resp).Show.Pid

	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	eps := decode[EpisodePage](t, resp).Items
	if len(eps) == 0 {
		t.Fatal("feed produced no episodes")
	}
	ep := eps[0]
	resp = h.postJSON(t, "/api/v1/episodes/"+ep.Pid+"/fetch", nil)
	wantStatus(t, resp, 202, "queue the fetch")
	drainFetches(t, h)

	// The file is really there, so the first ask genuinely queues work.
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/skip-map", h.token)
	if sm := decode[SkipMap](t, resp); sm.State != "pending" {
		t.Fatalf("skip map before the deletion = %q, want pending", sm.State)
	}

	// Delete the audio without telling the catalog, which is the whole
	// scenario: a rescan has not run and the item still reads present.
	var removed int
	err := filepath.Walk(h.podcastDir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return err
		}
		if err := os.Remove(path); err != nil {
			return err
		}
		removed++
		return nil
	})
	if err != nil {
		t.Fatalf("removing the downloaded audio: %v", err)
	}
	if removed == 0 {
		t.Fatalf("no downloaded file under %s to remove", h.podcastDir)
	}

	// The worker resolves the path off the request, finds nothing, and
	// tells the catalog rather than dropping the entry silently.
	for h.svc.DrainAnalysisQueue(context.Background()) {
	}

	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/skip-map", h.token)
	if sm := decode[SkipMap](t, resp); sm.State != "unavailable" {
		t.Fatalf("skip map after the worker ran = %q, want unavailable", sm.State)
	}

	// And the correction is in the catalog, not just in this endpoint's
	// answer: that is the difference between recording the discovery and
	// papering over it per request.
	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	after := decode[EpisodePage](t, resp).Items
	if len(after) == 0 {
		t.Fatal("episode listing came back empty")
	}
	if after[0].Downloaded {
		t.Errorf("episode still reports downloaded after its file was deleted: %+v", after[0])
	}
}

// A follower of no shows gets an empty strip, not the whole catalog.
// The scope is an `in` over the subscribed set, and an empty `in`
// compiles to 1=0 - the opposite mistake (an empty set read as "no
// filter") would hand every listener every episode on the server.
func TestSubscribedEpisodesEmptyForAFollowerOfNothing(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newCountsFeed(t, []countsEpisode{{title: "First"}, {title: "Second"}})

	// The admin subscribes and starts one, so the catalog genuinely holds
	// episodes and in-progress state that the listener must not see.
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	show := decode[Subscription](t, resp).Show.Pid
	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	eps := decode[EpisodePage](t, resp).Items
	if len(eps) != 2 {
		t.Fatalf("admin episodes = %d, want 2", len(eps))
	}
	putPlayState(t, h, eps[0].Pid, 1_000)

	_, listener := listenerAccount(t, h, "follows-nothing", true)
	for _, filter := range []string{"latest", "unplayed", "in-progress"} {
		t.Run(filter, func(t *testing.T) {
			resp := reqAs(t, h, "GET", "/api/v1/podcasts/episodes?filter="+filter, listener, nil)
			page := decode[EpisodePage](t, resp)
			if len(page.Items) != 0 {
				t.Errorf("%s = %d rows for a follower of no shows, want 0", filter, len(page.Items))
			}
			if page.NextCursor != nil {
				t.Errorf("%s handed back a cursor: %v", filter, page.NextCursor)
			}
		})
	}
}

// The in-progress strip ranks on the last progress write, so a
// checkpoint counts. It is a keyset browse of the catalog now rather
// than a ranking in Go, and this pins that the order did not move with
// the mechanism.
func TestSubscribedEpisodesInProgressRecency(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newCountsFeed(t, []countsEpisode{
		{title: "First"}, {title: "Second"}, {title: "Third"},
	})
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	show := decode[Subscription](t, resp).Show.Pid
	resp = get(t, h.ts, "/api/v1/podcasts/"+show+"/episodes", h.token)
	eps := decode[EpisodePage](t, resp).Items
	if len(eps) != 3 {
		t.Fatalf("episodes = %d, want 3", len(eps))
	}

	// Start the oldest first and the newest last, so publication order and
	// recency order disagree and only the second can be right.
	for _, ep := range []EpisodeSummary{eps[2], eps[1], eps[0]} {
		putPlayState(t, h, ep.Pid, 1_000)
	}
	// Finishing one drops it: in-progress is started and unfinished.
	putPlayState(t, h, eps[1].Pid, eps[1].DurationMs)

	resp = get(t, h.ts, "/api/v1/podcasts/episodes?filter=in-progress", h.token)
	rows := decode[EpisodePage](t, resp).Items
	if len(rows) != 2 {
		t.Fatalf("in-progress = %d rows, want the two still started", len(rows))
	}
	if rows[0].Pid != eps[0].Pid || rows[1].Pid != eps[2].Pid {
		t.Errorf("in-progress order = %s, %s; want most recently played first (%s, %s)",
			rows[0].Pid, rows[1].Pid, eps[0].Pid, eps[2].Pid)
	}

	// It pages under its own cursor, and the second page resumes rather
	// than restarting.
	resp = get(t, h.ts, "/api/v1/podcasts/episodes?filter=in-progress&limit=1", h.token)
	first := decode[EpisodePage](t, resp)
	if len(first.Items) != 1 || first.NextCursor == nil {
		t.Fatalf("capped in-progress page = %d rows, cursor %v", len(first.Items), first.NextCursor)
	}
	resp = get(t, h.ts,
		"/api/v1/podcasts/episodes?filter=in-progress&cursor="+*first.NextCursor, h.token)
	rest := decode[EpisodePage](t, resp).Items
	if len(rest) != 1 || rest[0].Pid == first.Items[0].Pid {
		t.Errorf("resumed in-progress page = %+v, want the other row", rest)
	}

	// Walked one row at a time, the pages rebuild the unpaged listing
	// exactly. The resume is a search for the first row strictly after
	// the cursor's own, and getting that boundary wrong reads as a row
	// served twice and a cursor that never advances rather than as an
	// error, so it is pinned rather than reasoned about.
	var paged []EpisodeSummary
	cursor := ""
	for range len(rows) + 1 {
		path := "/api/v1/podcasts/episodes?filter=in-progress&limit=1"
		if cursor != "" {
			path += "&cursor=" + cursor
		}
		page := decode[EpisodePage](t, get(t, h.ts, path, h.token))
		paged = append(paged, page.Items...)
		if page.NextCursor == nil {
			break
		}
		if *page.NextCursor == cursor {
			t.Fatalf("the in-progress cursor did not advance past %q", cursor)
		}
		cursor = *page.NextCursor
	}
	if len(paged) != len(rows) {
		t.Fatalf("paging one at a time drew %d rows, want the same %d", len(paged), len(rows))
	}
	for i, ep := range paged {
		if ep.Pid != rows[i].Pid {
			t.Errorf("paged row %d = %s, want %s", i, ep.Pid, rows[i].Pid)
		}
	}
}

func unplayedFor(t *testing.T, h *harness, show string) int {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/podcasts", h.token)
	for _, sub := range decode[SubscriptionPage](t, resp).Items {
		if sub.Show.Pid != show {
			continue
		}
		if sub.UnplayedCount == nil {
			t.Fatal("a subscription answered no unplayedCount")
		}
		return *sub.UnplayedCount
	}
	t.Fatalf("no subscription for %s", show)
	return 0
}

func putPlayState(t *testing.T, h *harness, pid string, positionMs int64) {
	t.Helper()
	resp := reqAs(t, h, "PUT", "/api/v1/items/"+pid+"/play-state", h.token,
		map[string]any{"positionMs": positionMs})
	resp.Body.Close()
	if resp.StatusCode != 204 {
		t.Fatalf("play-state for %s = %d", pid, resp.StatusCode)
	}
}
