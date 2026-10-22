package api

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// shareOf mints a share as the harness administrator.
func shareOf(t *testing.T, h *harness, pid string, extra map[string]any) Share {
	t.Helper()
	body := map[string]any{"pid": pid}
	for k, v := range extra {
		body[k] = v
	}
	return decodeStatus[Share](t, h.postJSON(t, "/api/v1/shares", body), 201, "sharing "+pid)
}

// anon fetches a share route as a visitor with no credentials, with a
// Range header when one is given, and answers the body read whole.
func anon(t *testing.T, h *harness, method, path, rangeHeader string) (*http.Response, []byte) {
	t.Helper()
	req, err := http.NewRequest(method, h.ts.URL+path, nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Accept-Language", "en")
	if rangeHeader != "" {
		req.Header.Set("Range", rangeHeader)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, err := io.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	return resp, body
}

// sharePlays reads a link's anonymous play count off its owner's listing.
func sharePlays(t *testing.T, h *harness, sharePID string) int {
	t.Helper()
	for _, s := range decode[SharePage](t, get(t, h.ts, "/api/v1/shares", h.token)).Shares {
		if s.Pid == sharePID {
			return s.Plays
		}
	}
	t.Fatalf("share %s is not listed", sharePID)
	return 0
}

// firstEpisode subscribes the administrator to a feed and answers its
// newest episode.
func firstEpisode(t *testing.T, h *harness, feedURL string, extra map[string]any) (Subscription, EpisodeSummary) {
	t.Helper()
	body := map[string]any{"url": feedURL}
	for k, v := range extra {
		body[k] = v
	}
	sub := decodeStatus[Subscription](t, h.postJSON(t, "/api/v1/podcasts", body), 201, "subscribing to "+feedURL)
	page := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token))
	if len(page.Items) == 0 {
		t.Fatalf("%s listed no episodes", feedURL)
	}
	return sub, page.Items[0]
}

// A public link to an episode the server never fetched plays at once:
// the page draws a player, and its stream relays the feed's own audio
// from the show's host, whole and by range, with the host's own headers
// held back and the media hardening on. A probe, a seek and a HEAD are
// not listens; the play is counted once, after the audio started. There
// is no file to download, and a revoked link stops at once.
func TestSharedUnfetchedEpisodePlaysByPassthrough(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServerWithHeaders(t, 1, http.Header{
		"Set-Cookie": []string{"host_session=leaked; Path=/"},
		"Server":     []string{"PodcastHost/9.9"},
	})
	_, ep := firstEpisode(t, h, feed.feedURL(), nil)
	if ep.Downloaded {
		t.Fatal("the episode should not be fetched for this test")
	}
	share := shareOf(t, h, ep.Pid, map[string]any{"allowDownload": true})

	resp, page := anon(t, h, http.MethodGet, share.Url, "")
	if resp.StatusCode != 200 || !strings.Contains(string(page), "<audio") {
		t.Fatalf("landing page = %d without a player: %.400s", resp.StatusCode, page)
	}
	if strings.Contains(string(page), "/download") {
		t.Error("the page offers a download of an episode that has no file here")
	}

	want, err := os.ReadFile(filepath.Join(feed.dir, feed.files[0]))
	if err != nil {
		t.Fatal(err)
	}
	stream := share.Url + "/stream?i=0"
	resp, whole := anon(t, h, http.MethodGet, stream, "")
	if resp.StatusCode != 200 || !bytes.Equal(whole, want) {
		t.Fatalf("stream = %d with %d bytes, want 200 and the feed's %d", resp.StatusCode, len(whole), len(want))
	}
	if got := resp.Header.Get("Content-Type"); got != "audio/mpeg" {
		t.Errorf("Content-Type = %q, want audio/mpeg", got)
	}
	if got := resp.Header.Get("X-Content-Type-Options"); got != "nosniff" {
		t.Errorf("X-Content-Type-Options = %q, want nosniff", got)
	}
	if got := resp.Header.Get("Content-Security-Policy"); got != "default-src 'none'; sandbox" {
		t.Errorf("Content-Security-Policy = %q", got)
	}
	for _, held := range []string{"Set-Cookie", "Server"} {
		if v := resp.Header.Get(held); v != "" {
			t.Errorf("the podcast host's %s reached the visitor: %q", held, v)
		}
	}

	resp, part := anon(t, h, http.MethodGet, stream, "bytes=10-19")
	if resp.StatusCode != http.StatusPartialContent || !bytes.Equal(part, want[10:20]) {
		t.Fatalf("ranged stream = %d with %q", resp.StatusCode, part)
	}
	if got, want := resp.Header.Get("Content-Range"), fmt.Sprintf("bytes 10-19/%d", len(want)); got != want {
		t.Errorf("Content-Range = %q, want %q", got, want)
	}
	if resp, _ := anon(t, h, http.MethodGet, stream, "bytes=0-1"); resp.StatusCode != http.StatusPartialContent {
		t.Errorf("a probe = %d, want 206", resp.StatusCode)
	}
	if resp, _ := anon(t, h, http.MethodHead, stream, ""); resp.StatusCode != 200 {
		t.Errorf("a HEAD = %d, want 200", resp.StatusCode)
	}
	if got := sharePlays(t, h, share.Pid); got != 1 {
		t.Errorf("plays = %d, want the one listen", got)
	}

	resp, body := anon(t, h, http.MethodGet, share.Url+"/download?i=0", "")
	if resp.StatusCode != 404 || !strings.Contains(string(body), "no file on this server") {
		t.Errorf("download = %d: %s", resp.StatusCode, body)
	}

	wantStatus(t, h.deleteReq(t, "/api/v1/shares/"+share.Pid), 204, "revoking the link")
	if resp, _ := anon(t, h, http.MethodGet, stream, ""); resp.StatusCode != 404 {
		t.Errorf("stream after the revoke = %d, want 404", resp.StatusCode)
	}
}

// heldFeed is a podcast host whose one episode starts its audio and then
// holds the response open until the test lets go, so a test can keep a
// number of listeners on the relay at once.
type heldFeed struct {
	*feedServer
	release chan struct{}
	once    sync.Once
}

func newHeldFeed(t *testing.T) *heldFeed {
	t.Helper()
	hf := &heldFeed{feedServer: newFeedServer(t, 1), release: make(chan struct{})}
	files := http.FileServer(http.Dir(hf.dir))
	audio := "/" + hf.files[0]
	hf.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != audio {
			files.ServeHTTP(w, r)
			return
		}
		w.Header().Set("Content-Type", "audio/mpeg")
		w.WriteHeader(http.StatusOK)
		w.Write(bytes.Repeat([]byte{0xff}, 4096))
		w.(http.Flusher).Flush()
		select {
		case <-hf.release:
		case <-r.Context().Done():
		}
	})
	t.Cleanup(hf.letGo)
	return hf
}

func (hf *heldFeed) letGo() { hf.once.Do(func() { close(hf.release) }) }

// openStream starts a stream and answers it once its headers are in,
// its body still arriving.
func openStream(t *testing.T, ctx context.Context, url string) *http.Response {
	t.Helper()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

// The relay behind a public link is bounded twice: by the link's own
// listener ceiling, and by its owner's relay slots, which an anonymous
// listener spends exactly as the owner's own passthrough listening does.
func TestASharedEpisodeRelayIsBoundedAndBilledToItsOwner(t *testing.T) {
	t.Parallel()
	t.Run("the link's listeners", func(t *testing.T) {
		t.Parallel()
		h := newPodcastHarness(t)
		feed := newHeldFeed(t)
		_, ep := firstEpisode(t, h, feed.feedURL(), nil)
		share := shareOf(t, h, ep.Pid, nil)
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		for i := range maxShareStreams {
			resp := openStream(t, ctx, h.ts.URL+share.Url+"/stream?i=0")
			if resp.StatusCode != 200 {
				t.Fatalf("listener %d = %d, want 200", i+1, resp.StatusCode)
			}
			defer resp.Body.Close()
		}
		resp, body := anon(t, h, http.MethodGet, share.Url+"/stream?i=0", "")
		if resp.StatusCode != http.StatusTooManyRequests || !strings.Contains(string(body), `"rate-limited"`) {
			t.Errorf("one listener past the link's ceiling = %d: %s", resp.StatusCode, body)
		}
	})
	t.Run("the owner's relay slots", func(t *testing.T) {
		t.Parallel()
		h := newPodcastHarness(t)
		feed := newHeldFeed(t)
		_, ep := firstEpisode(t, h, feed.feedURL(), nil)
		share := shareOf(t, h, ep.Pid, nil)
		info := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+ep.Pid+"/play-info", h.token))
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		for i := range maxUserRelays {
			resp := openStream(t, ctx, h.ts.URL+info.Url)
			if resp.StatusCode != 200 {
				t.Fatalf("the owner's relay %d = %d, want 200", i+1, resp.StatusCode)
			}
			defer resp.Body.Close()
		}
		resp, body := anon(t, h, http.MethodGet, share.Url+"/stream?i=0", "")
		if resp.StatusCode != http.StatusTooManyRequests || !strings.Contains(string(body), `"rate-limited"`) {
			t.Errorf("a visitor while the owner's slots are spent = %d: %s", resp.StatusCode, body)
		}
		if got := sharePlays(t, h, share.Pid); got != 0 {
			t.Errorf("plays = %d after a refused listen, want 0", got)
		}
	})
}

// A host answering a link's episode with a page, or with a playlist that
// would send the visitor's player to a host of the feed's choosing, is
// refused from the public route too, with none of its bytes reaching the
// visitor.
func TestASharedEpisodeFromAPageServingHostIsRefused(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	for _, c := range []struct{ name, served, body, mark string }{
		{"a page", "text/html; charset=utf-8", "<!doctype html><html><script>alert(1)</script></html>", "<script>"},
		{"a playlist", "audio/x-mpegurl", hlsPlaylist, "tracker.example"},
	} {
		t.Run(c.name, func(t *testing.T) {
			_, ep := firstEpisode(t, h, typedEnclosureHost(t, "audio/mpeg", c.served, c.body), nil)
			share := shareOf(t, h, ep.Pid, nil)
			resp, body := anon(t, h, http.MethodGet, share.Url+"/stream?i=0", "")
			if resp.StatusCode != http.StatusBadGateway || strings.Contains(string(body), c.mark) {
				t.Errorf("stream = %d: %s", resp.StatusCode, body)
			}
			if got := resp.Header.Get("X-Content-Type-Options"); got != "nosniff" {
				t.Errorf("X-Content-Type-Options = %q, want nosniff", got)
			}
			if got := sharePlays(t, h, share.Pid); got != 0 {
				t.Errorf("plays = %d after a refused stream, want 0", got)
			}
		})
	}
}

// watchPages is a stand-in YouTube provider: its one video's enclosure
// is the watch page, as WaxDeck's own provider stores it.
type watchPages struct{}

func (watchPages) SourceType() model.SourceType { return model.SourceYouTube }

func (watchPages) Resolve(_ context.Context, req source.Request) (*source.Resolved, error) {
	return &source.Resolved{IdentityKey: "youtube:" + req.URL, SourceID: req.URL, SourceType: model.SourceYouTube, Title: "Watch Pages"}, nil
}

func (watchPages) Enumerate(_ context.Context, req source.Request) (*source.Enumeration, error) {
	return &source.Enumeration{IdentityKey: "youtube:" + req.URL, Feed: &model.Feed{
		Title: "Watch Pages",
		Episodes: []model.FeedEpisode{{
			GUID: "watch-1", Title: "A Video", DurationMS: 60_000,
			PubDateNS:    time.Date(2026, 6, 1, 8, 0, 0, 0, time.UTC).UnixNano(),
			EnclosureURL: "https://www.youtube.com/watch?v=abc", EnclosureType: "audio/mp4",
		}},
	}}, nil
}

func (watchPages) Fetch(context.Context, source.FetchRequest, io.Writer) (*source.FetchResult, error) {
	return nil, errors.New("no media in this test")
}

func newWatchPageHarness(t *testing.T) *harness {
	return newPodcastHarnessWith(t, func(cfg *service.Config) {
		cfg.SourceProviders = append(cfg.SourceProviders, watchPages{})
	})
}

// A link is never minted for an episode nobody could hear through it:
// one the server has not fetched whose feed names no audio it relays.
func TestAnEpisodeWithNoAudioToRelayCannotBeShared(t *testing.T) {
	t.Parallel()
	h := newWatchPageHarness(t)
	_, video := firstEpisode(t, h, "https://www.youtube.com/@watchpages", map[string]any{"sourceType": "youtube"})
	quiet := newFeedServer(t, 1)
	quiet.writeEnclosureless(t)
	_, silent := firstEpisode(t, h, quiet.feedURL(), nil)
	for name, pid := range map[string]string{"a YouTube video": video.Pid, "an episode with no enclosure": silent.Pid} {
		resp := h.postJSON(t, "/api/v1/shares", map[string]any{"pid": pid})
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != http.StatusConflict || !strings.Contains(string(body), `"conflict"`) ||
			!strings.Contains(string(body), "fetch it first") {
			t.Errorf("sharing %s = %d: %s", name, resp.StatusCode, body)
		}
	}
}

// A shared playlist plays every member that has audio somewhere this
// server can reach, local or relayed, and names the one that has none
// rather than drawing a player that cannot play.
func TestASharedPlaylistPlaysWhatItCanAndSaysWhatItCannot(t *testing.T) {
	t.Parallel()
	h := newWatchPageHarness(t)
	track := h.items(t, "?mediaType=music").Items[0]
	_, episode := firstEpisode(t, h, newFeedServer(t, 1).feedURL(), nil)
	_, video := firstEpisode(t, h, "https://www.youtube.com/@watchpages", map[string]any{"sourceType": "youtube"})
	pl := decodeStatus[Playlist](t, h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Mixed", "kind": "static", "itemPids": []string{track.Pid, episode.Pid, video.Pid},
	}), 201, "creating the playlist")
	share := shareOf(t, h, pl.Pid, map[string]any{"allowDownload": true})

	resp, page := anon(t, h, http.MethodGet, share.Url, "")
	if resp.StatusCode != 200 {
		t.Fatalf("landing page = %d", resp.StatusCode)
	}
	if got := strings.Count(string(page), "<audio"); got != 2 {
		t.Errorf("players = %d, want the track's and the episode's", got)
	}
	if got := strings.Count(string(page), "Not available to play yet"); got != 1 {
		t.Errorf("notes = %d, want one for the video", got)
	}
	if !strings.Contains(string(page), share.Url+"/download") {
		t.Error("the first member is a file here, and the page offers no download of it")
	}
	for i, want := range []int{200, 200, 404} {
		if resp, _ := anon(t, h, http.MethodGet, fmt.Sprintf("%s/stream?i=%d", share.Url, i), "bytes=0-"); resp.StatusCode != want && !(want == 200 && resp.StatusCode == 206) {
			t.Errorf("member %d = %d, want %d", i, resp.StatusCode, want)
		}
	}
}

// A capability URL never leaks a private feed: a playlist share leaves
// out its owner's episodes of a credentialed show, fetched or not,
// exactly as an episode share of one is refused.
func TestASharedPlaylistLeavesOutPrivateEpisodes(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	track := h.items(t, "?mediaType=music").Items[0]
	feed := newPrivateFeedServer(t, 1, "member", "secret")
	_, private := firstEpisode(t, h, feed.feedURL(), map[string]any{"username": "member", "password": "secret"})
	wantStatus(t, h.postJSON(t, "/api/v1/episodes/"+private.Pid+"/fetch", nil), 202, "fetching the private episode")
	drainFetches(t, h)
	pl := decodeStatus[Playlist](t, h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Paid", "kind": "static", "itemPids": []string{track.Pid, private.Pid},
	}), 201, "creating the playlist")
	share := shareOf(t, h, pl.Pid, nil)

	_, page := anon(t, h, http.MethodGet, share.Url, "")
	if got := strings.Count(string(page), "<audio"); got != 1 {
		t.Errorf("players = %d, want the track's alone", got)
	}
	if strings.Contains(string(page), private.Title) {
		t.Errorf("the page names the private episode %q", private.Title)
	}
	if resp, _ := anon(t, h, http.MethodGet, share.Url+"/stream?i=1", ""); resp.StatusCode != 404 {
		t.Errorf("the private episode's slot = %d, want 404", resp.StatusCode)
	}
}

// An episode the server holds plays from its own copy, never from the
// show's host, with the same media hardening the relay carries.
func TestAFetchedSharedEpisodeStreamsFromTheServer(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	var hostHits atomic.Int64
	files := http.FileServer(http.Dir(feed.dir))
	audio := "/" + feed.files[0]
	feed.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == audio {
			hostHits.Add(1)
		}
		files.ServeHTTP(w, r)
	})
	_, ep := firstEpisode(t, h, feed.feedURL(), nil)
	wantStatus(t, h.postJSON(t, "/api/v1/episodes/"+ep.Pid+"/fetch", nil), 202, "fetching the episode")
	drainFetches(t, h)
	share := shareOf(t, h, ep.Pid, nil)
	before := hostHits.Load()

	resp, body := anon(t, h, http.MethodGet, share.Url+"/stream?i=0", "")
	if resp.StatusCode != 200 || len(body) == 0 {
		t.Fatalf("stream = %d with %d bytes", resp.StatusCode, len(body))
	}
	if got := hostHits.Load(); got != before {
		t.Errorf("the show's host was asked for the audio %d times, want none", got-before)
	}
	if got := resp.Header.Get("Content-Type"); !strings.HasPrefix(got, "audio/") {
		t.Errorf("Content-Type = %q, want an audio type", got)
	}
	if got := resp.Header.Get("X-Content-Type-Options"); got != "nosniff" {
		t.Errorf("X-Content-Type-Options = %q, want nosniff", got)
	}
	if got := resp.Header.Get("Content-Security-Policy"); got != "default-src 'none'; sandbox" {
		t.Errorf("Content-Security-Policy = %q", got)
	}
	if got := sharePlays(t, h, share.Pid); got != 1 {
		t.Errorf("plays = %d, want 1", got)
	}
}

// A link to an episode of a feed that turns private after it was minted
// stops at once, page and stream.
func TestASharedEpisodeStopsWhenItsFeedTurnsPrivate(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 1)
	_, ep := firstEpisode(t, h, feed.feedURL(), nil)
	share := shareOf(t, h, ep.Pid, nil)
	if resp, _ := anon(t, h, http.MethodGet, share.Url+"/stream?i=0", ""); resp.StatusCode != 200 {
		t.Fatalf("stream while the feed is open = %d", resp.StatusCode)
	}
	// Subscribing again with credentials is how a show gains them.
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{
		"url": feed.feedURL(), "username": "member", "password": "secret",
	})
	resp.Body.Close()
	for _, route := range []string{share.Url, share.Url + "/stream?i=0"} {
		if resp, _ := anon(t, h, http.MethodGet, route, ""); resp.StatusCode != 404 {
			t.Errorf("%s after the feed turned private = %d, want 404", route, resp.StatusCode)
		}
	}
}

// A link's relay resolves the episode for no account, so the feed login
// its owner stored is never spent on a visitor, whoever the owner is and
// whatever the show has become since the link last resolved.
func TestAShareRelayNeverSpendsTheOwnersFeedLogin(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newPrivateFeedServer(t, 1, "member", "secret")
	var spent atomic.Int64
	gate := feed.ts.Config.Handler
	feed.ts.Config.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if user, pass, ok := r.BasicAuth(); ok && user == "member" && pass == "secret" && strings.HasSuffix(r.URL.Path, ".mp3") {
			spent.Add(1)
		}
		gate.ServeHTTP(w, r)
	})
	_, ep := firstEpisode(t, h, feed.feedURL(), map[string]any{"username": "member", "password": "secret"})
	owner := adminUserID(t, h)
	if src, err := h.svc.EnclosureStreamSource(context.Background(), owner, ep.Pid); err != nil || src.AuthUser != "member" {
		t.Fatalf("the owner's own source = %+v, %v; want it to carry the show's login", src, err)
	}

	rec := httptest.NewRecorder()
	h.srv.relayShareEpisode(rec, httptest.NewRequest(http.MethodGet, "/s/link/stream?i=0", nil), owner, ep.Pid)
	if rec.Code != http.StatusNotFound {
		t.Errorf("a visitor to the owner's credentialed show = %d with %d bytes, want 404", rec.Code, rec.Body.Len())
	}
	if got := spent.Load(); got != 0 {
		t.Errorf("the owner's login reached the show's host %d times for a visitor", got)
	}
}

// A trashed member of a list whose rule asks about state is listed and
// has nothing to play, page, stream and download alike, and the download
// refusal names no episode it is not.
func TestASharedTrashedMemberSaysItHasNothingToPlay(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	doomed := h.items(t, "?mediaType=music").Items[0]
	pl := decodeStatus[Playlist](t, h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Deleted Music", "kind": "smart", "rule": map[string]any{
			"root": map[string]any{
				"type": "all",
				"nodes": []any{
					map[string]any{"type": "condition", "field": "mediaType", "op": "is", "value": "music"},
					map[string]any{"type": "condition", "field": "state", "op": "is", "value": "archived"},
				},
			},
			"sorts": []any{map[string]any{"field": "title"}},
		},
	}), 201, "creating the smart playlist")
	wantStatus(t, h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{doomed.Pid}, "mode": "trash",
	}), 200, "trashing the track")
	for deadline := time.Now().Add(30 * time.Second); !samePids(entryPids(playlistItems(t, h, h.token, pl.Pid)), []string{doomed.Pid}); {
		if time.Now().After(deadline) {
			t.Fatal("the trashed track never joined the state rule's list")
		}
		time.Sleep(100 * time.Millisecond)
	}
	share := shareOf(t, h, pl.Pid, map[string]any{"allowDownload": true})

	_, page := anon(t, h, http.MethodGet, share.Url, "")
	if strings.Contains(string(page), "<audio") || !strings.Contains(string(page), "Not available to play yet") {
		t.Errorf("the page draws the trashed track as playable: %.600s", page)
	}
	if resp, _ := anon(t, h, http.MethodGet, share.Url+"/stream?i=0", ""); resp.StatusCode != 404 {
		t.Errorf("stream = %d, want 404", resp.StatusCode)
	}
	resp, body := anon(t, h, http.MethodGet, share.Url+"/download?i=0", "")
	if resp.StatusCode != 404 || !strings.Contains(string(body), "no file on this server") || strings.Contains(string(body), "episode") {
		t.Errorf("download = %d: %s", resp.StatusCode, body)
	}
}

// A list whose every member is a private feed's episode leaves nothing
// a link could serve, so its link answers as if it did not exist.
func TestASharedListOfPrivateEpisodesIsGone(t *testing.T) {
	t.Parallel()
	h := newPodcastHarness(t)
	feed := newPrivateFeedServer(t, 1, "member", "secret")
	_, private := firstEpisode(t, h, feed.feedURL(), map[string]any{"username": "member", "password": "secret"})
	pl := decodeStatus[Playlist](t, h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Paid Only", "kind": "static", "itemPids": []string{private.Pid},
	}), 201, "creating the playlist")
	share := shareOf(t, h, pl.Pid, nil)
	for _, route := range []string{share.Url, share.Url + "/stream?i=0"} {
		if resp, _ := anon(t, h, http.MethodGet, route, ""); resp.StatusCode != http.StatusNotFound {
			t.Errorf("%s = %d, want 404", route, resp.StatusCode)
		}
	}
}
