package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
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
		fmt.Fprintf(&items, `<item>
			<title>Episode %d</title>
			<guid isPermaLink="false">ep-guid-%d</guid>
			<pubDate>%s</pubDate>
			<description><![CDATA[<p>Notes for <b>episode %d</b></p><script>alert(1)</script>]]></description>
			%s
			<enclosure url="%s/%s" type="audio/mpeg" length="%d"/>
		</item>`, i+1, i+1, base.AddDate(0, 0, i).Format(time.RFC1123Z), i+1, extra, fs.ts.URL, fs.files[i], info.Size())
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
}

func (fs *feedServer) feedURL() string { return fs.ts.URL + "/feed.xml" }

// newPodcastHarness is the shared harness plus the podcast surface: a
// download dir outside the library roots and loopback feeds allowed.
func newPodcastHarness(t *testing.T) *harness {
	podcastDir := t.TempDir()
	return newHarnessWith(t, func(cfg *service.Config) {
		cfg.PodcastDir = podcastDir
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
		// Tests drive checkpoints and sweeps back to back; the in-use
		// deferral would read every touched episode as live playback.
		cfg.RetentionInUseWindow = -1
	})
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

	// A not-yet-fetched episode cannot stream: typed conflict.
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)
	if resp.StatusCode != 409 {
		t.Fatalf("remote episode play-info status = %d, want 409", resp.StatusCode)
	}
	resp.Body.Close()

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
	resp = get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token)
	if resp.StatusCode != 409 {
		t.Fatalf("play-info after removal = %d, want 409", resp.StatusCode)
	}
	resp.Body.Close()
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
	resp = get(t, h.ts, "/api/v1/items/"+rows[0].Pid+"/play-info", h.token)
	if resp.StatusCode != 409 {
		t.Fatalf("play-info after cleanup = %d, want 409", resp.StatusCode)
	}
	resp.Body.Close()
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
	resp.Body.Close()
	resp = get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token)
	if !decode[EpisodePage](t, resp).Items[0].Downloaded {
		t.Fatal("refused removal must leave the file in place")
	}
}
