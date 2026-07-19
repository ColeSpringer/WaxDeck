package waxtapsource

import (
	"bytes"
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	waxbin "github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/podcast"
	"github.com/colespringer/waxbin/source"
	"github.com/colespringer/waxdeck/fixtures"
	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"
	waxtap "github.com/colespringer/waxtap/v3"
)

// fakeTap is a canned, network-free tap. Its Enumerate honors MaxItems and Stop
// the way the real client documents them (Stop halts before appending the
// matched entry; MaxItems counts appended entries).
type fakeTap struct {
	playlist  waxtap.Playlist
	infos     map[string]*waxtap.Video
	infoErrs  map[string]error
	infoCalls []string

	// workDir is where the provider stages downloads; Download writes payload
	// into the staged fetch file it finds there.
	workDir     string
	payload     []byte
	downloadErr error
	downloads   int
}

var _ tap = (*fakeTap)(nil)

func (f *fakeTap) Enumerate(_ context.Context, _ string, opts waxtap.EnumerateOptions) (*waxtap.Playlist, error) {
	out := &waxtap.Playlist{ID: f.playlist.ID, Title: f.playlist.Title, Author: f.playlist.Author}
	for _, e := range f.playlist.Entries {
		if opts.Stop != nil && opts.Stop(e.VideoID) {
			break
		}
		out.Entries = append(out.Entries, e)
		if opts.MaxItems > 0 && len(out.Entries) >= opts.MaxItems {
			break
		}
	}
	return out, nil
}

func (f *fakeTap) Info(_ context.Context, url string, _ waxtap.InfoDepth, _ ...waxtap.ReadOption) (*waxtap.Video, error) {
	id := strings.TrimPrefix(url, "https://www.youtube.com/watch?v=")
	f.infoCalls = append(f.infoCalls, id)
	if err, ok := f.infoErrs[id]; ok {
		return nil, err
	}
	if v, ok := f.infos[id]; ok {
		return v, nil
	}
	return &waxtap.Video{ID: id, Title: "video " + id}, nil
}

func (f *fakeTap) Download(_ context.Context, req waxtap.Request) (*waxtap.Result, error) {
	f.downloads++
	if f.downloadErr != nil {
		return nil, f.downloadErr
	}
	matches, err := filepath.Glob(filepath.Join(f.workDir, "fetch-*"))
	if err != nil || len(matches) != 1 {
		return nil, fmt.Errorf("fake download: expected one staged fetch file in %s, found %d", f.workDir, len(matches))
	}
	path := matches[0]
	if err := os.WriteFile(path, f.payload, 0o644); err != nil {
		return nil, err
	}
	id := strings.TrimPrefix(req.URL, "https://www.youtube.com/watch?v=")
	return &waxtap.Result{
		VideoID:      id,
		Title:        "video " + id,
		OutputPath:   path,
		OutputFormat: waxtap.Format{Extension: strings.TrimPrefix(filepath.Ext(path), ".")},
	}, nil
}

// vid returns a deterministic 11-character video id for entry n.
func vid(n int) string { return fmt.Sprintf("vid%08d", n) }

// channelFake builds a fake with n uploads, newest first (entry ids vid(n) down
// to vid(1)), each with enrichable metadata.
func channelFake(n int) *fakeTap {
	f := &fakeTap{
		playlist: waxtap.Playlist{ID: "UUexample0123456789abcd", Title: "Example Uploads", Author: "Example"},
		infos:    map[string]*waxtap.Video{},
	}
	for i := n; i >= 1; i-- {
		id := vid(i)
		f.playlist.Entries = append(f.playlist.Entries, waxtap.PlaylistEntry{
			VideoID:  id,
			Title:    "upload " + id,
			Author:   "Example",
			Duration: time.Duration(i) * time.Minute,
			Index:    n - i,
		})
		f.infos[id] = &waxtap.Video{
			ID:          id,
			Title:       "full title " + id,
			Author:      "Example",
			Duration:    time.Duration(i) * time.Minute,
			PublishDate: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC).Add(time.Duration(i) * 24 * time.Hour),
			Description: "description " + id,
			Thumbnails:  []waxtap.Thumbnail{{URL: "https://i.ytimg.com/vi/" + id + "/max.jpg", Width: 1280, Height: 720}},
		}
	}
	return f
}

func testProvider(t *testing.T, f *fakeTap, logs *bytes.Buffer) *Provider {
	t.Helper()
	f.workDir = t.TempDir()
	var log *slog.Logger
	if logs != nil {
		log = slog.New(slog.NewTextHandler(logs, nil))
	}
	return newProvider(f, Config{WorkDir: f.workDir}, log, nil)
}

func TestEnumerateFirstSync(t *testing.T) {
	f := channelFake(30)
	p := testProvider(t, f, nil)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "https://www.youtube.com/@example"})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if enum.NotModified {
		t.Fatal("first enumeration reported NotModified")
	}
	if enum.ETag != vid(30) {
		t.Errorf("ETag = %q, want newest id %q", enum.ETag, vid(30))
	}
	if enum.IdentityKey != "youtube:UUexample0123456789abcd" || enum.SourceID != "UUexample0123456789abcd" {
		t.Errorf("identity = %q / %q", enum.IdentityKey, enum.SourceID)
	}
	feed := enum.Feed
	if feed == nil {
		t.Fatal("nil feed")
	}
	if feed.Title != "Example Uploads" || feed.Author != "Example" {
		t.Errorf("feed title/author = %q/%q", feed.Title, feed.Author)
	}
	if want := "https://i.ytimg.com/vi/" + vid(30) + "/max.jpg"; feed.ImageURL != want {
		t.Errorf("feed image = %q, want %q", feed.ImageURL, want)
	}
	if len(feed.Episodes) != 30 {
		t.Fatalf("episodes = %d, want 30", len(feed.Episodes))
	}
	newest := feed.Episodes[0]
	if newest.GUID != vid(30) {
		t.Errorf("newest GUID = %q", newest.GUID)
	}
	if want := "https://www.youtube.com/watch?v=" + vid(30); newest.EnclosureURL != want {
		t.Errorf("enclosure = %q, want %q", newest.EnclosureURL, want)
	}
	if newest.EnclosureType != "audio/mp4" {
		t.Errorf("enclosure type = %q", newest.EnclosureType)
	}
	if newest.Description == "" || newest.PubDateNS == 0 || newest.ImageURL == "" {
		t.Errorf("newest entry not enriched: %+v", newest)
	}
	if newest.Title != "full title "+vid(30) {
		t.Errorf("newest title = %q, want the enriched title", newest.Title)
	}
	// Enrichment is capped: 25 Info calls, so the 5 oldest stay basic.
	if len(f.infoCalls) != 25 {
		t.Errorf("info calls = %d, want 25", len(f.infoCalls))
	}
	oldest := feed.Episodes[29]
	if oldest.Description != "" || oldest.PubDateNS != 0 {
		t.Errorf("oldest entry unexpectedly enriched: %+v", oldest)
	}
	if oldest.Title != "upload "+vid(1) {
		t.Errorf("oldest title = %q, want the listing title", oldest.Title)
	}
	if oldest.DurationMS != time.Minute.Milliseconds() {
		t.Errorf("oldest duration = %d", oldest.DurationMS)
	}
}

func TestEnumerateNotModified(t *testing.T) {
	f := channelFake(5)
	p := testProvider(t, f, nil)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u", ETag: vid(5)})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if !enum.NotModified {
		t.Fatal("want NotModified when the newest id matches the cursor")
	}
	if enum.ETag != vid(5) {
		t.Errorf("ETag = %q, want the cursor echoed back", enum.ETag)
	}
	if enum.Feed != nil {
		t.Error("NotModified enumeration carries a feed")
	}
	if len(f.infoCalls) != 0 {
		t.Errorf("info calls = %d, want 0", len(f.infoCalls))
	}
}

func TestEnumerateIncremental(t *testing.T) {
	f := channelFake(6)
	p := testProvider(t, f, nil)

	// The cursor sits at vid(5): exactly one newer upload (vid(6)) exists.
	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u", ETag: vid(5)})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if enum.NotModified {
		t.Fatal("unexpected NotModified with a newer upload present")
	}
	if enum.ETag != vid(6) {
		t.Errorf("ETag = %q, want fresh cursor %q", enum.ETag, vid(6))
	}
	if len(enum.Feed.Episodes) != 1 {
		t.Fatalf("episodes = %d, want exactly the new entry", len(enum.Feed.Episodes))
	}
	ep := enum.Feed.Episodes[0]
	if ep.GUID != vid(6) || ep.Description == "" || ep.PubDateNS == 0 {
		t.Errorf("new entry not enriched: %+v", ep)
	}
	if len(f.infoCalls) != 1 {
		t.Errorf("info calls = %d, want 1", len(f.infoCalls))
	}
}

func TestEnumerateSkipsUnavailableEntry(t *testing.T) {
	f := channelFake(4)
	f.infoErrs = map[string]error{
		vid(3): fmt.Errorf("enrich %s: %w", vid(3), waxtap.ErrMembersOnly),
	}
	var logs bytes.Buffer
	p := testProvider(t, f, &logs)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u"})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if len(enum.Feed.Episodes) != 3 {
		t.Fatalf("episodes = %d, want 3 (members-only entry dropped)", len(enum.Feed.Episodes))
	}
	for _, ep := range enum.Feed.Episodes {
		if ep.GUID == vid(3) {
			t.Error("members-only entry was cataloged")
		}
	}
	if enum.ETag != vid(4) {
		t.Errorf("ETag = %q, want %q", enum.ETag, vid(4))
	}
	if !strings.Contains(logs.String(), "skipping unavailable youtube entry") {
		t.Error("skip was not logged")
	}
}

func TestEnumerateHardInfoErrorFails(t *testing.T) {
	f := channelFake(2)
	f.infoErrs = map[string]error{
		vid(2): fmt.Errorf("enrich %s: %w", vid(2), waxtap.ErrRateLimited),
	}
	p := testProvider(t, f, nil)

	if _, err := p.Enumerate(context.Background(), source.Request{URL: "u"}); err == nil {
		t.Fatal("want a hard enrichment error to fail the sync")
	}
}

func TestResolve(t *testing.T) {
	f := channelFake(3)
	p := testProvider(t, f, nil)

	res, err := p.Resolve(context.Background(), source.Request{URL: "https://www.youtube.com/@example"})
	if err != nil {
		t.Fatalf("Resolve: %v", err)
	}
	if res.IdentityKey != "youtube:UUexample0123456789abcd" || res.SourceID != "UUexample0123456789abcd" {
		t.Errorf("identity = %q / %q", res.IdentityKey, res.SourceID)
	}
	if res.SourceType != model.SourceYouTube {
		t.Errorf("source type = %q", res.SourceType)
	}
	if res.Title != "Example Uploads" {
		t.Errorf("title = %q", res.Title)
	}
	if len(f.infoCalls) != 0 {
		t.Errorf("Resolve made %d info calls, want 0", len(f.infoCalls))
	}
}

// audioFormats is a candidate list whose best-audio row is an m4a AAC stream.
func audioFormats() []waxtap.Format {
	return []waxtap.Format{{
		Itag:     140,
		MIMEType: `audio/mp4; codecs="mp4a.40.2"`,
		Codec:    "mp4a.40.2", Extension: "m4a",
		Bitrate: 128000, Channels: 2,
		AudioQuality: waxtap.QualityMedium,
	}}
}

func TestFetchStreamsBytesAndCleansUp(t *testing.T) {
	f := channelFake(1)
	f.infos[vid(1)].Formats = audioFormats()
	f.payload = []byte("not a real container, just deterministic bytes")
	var logs bytes.Buffer
	p := testProvider(t, f, &logs)

	var sink bytes.Buffer
	res, err := p.Fetch(context.Background(), source.FetchRequest{URL: "https://www.youtube.com/watch?v=" + vid(1)}, &sink)
	if err != nil {
		t.Fatalf("Fetch: %v", err)
	}
	if !bytes.Equal(sink.Bytes(), f.payload) {
		t.Error("streamed bytes differ from the downloaded payload")
	}
	if res.Bytes != int64(len(f.payload)) {
		t.Errorf("Bytes = %d, want %d", res.Bytes, len(f.payload))
	}
	if res.ContentHash == "" {
		t.Error("empty ContentHash")
	}
	if res.ContentType != "audio/mp4" {
		t.Errorf("ContentType = %q, want audio/mp4", res.ContentType)
	}
	if f.downloads != 1 {
		t.Errorf("downloads = %d, want 1", f.downloads)
	}
	// The staged temp file is always removed.
	left, _ := filepath.Glob(filepath.Join(f.workDir, "fetch-*"))
	if len(left) != 0 {
		t.Errorf("temp files left behind: %v", left)
	}
	// Provenance is best effort: the unparseable payload is logged, not fatal.
	if !strings.Contains(logs.String(), "provenance stamp skipped") {
		t.Errorf("expected a best-effort provenance log line, got: %s", logs.String())
	}
}

func TestFetchStampsProvenanceOnRealContainer(t *testing.T) {
	media := t.TempDir()
	paths, err := fixtures.Generate(media, fixtures.Spec{
		Codec: fixtures.CodecAAC, Container: fixtures.ContainerMP4, Duration: 200 * time.Millisecond,
	})
	if err != nil {
		t.Fatalf("fixture: %v", err)
	}
	payload, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatalf("fixture read: %v", err)
	}

	f := channelFake(1)
	f.infos[vid(1)].Formats = audioFormats()
	f.payload = payload
	p := testProvider(t, f, nil)

	var sink bytes.Buffer
	watch := "https://www.youtube.com/watch?v=" + vid(1)
	res, err := p.Fetch(context.Background(), source.FetchRequest{URL: watch}, &sink)
	if err != nil {
		t.Fatalf("Fetch: %v", err)
	}
	if res.Bytes != int64(sink.Len()) {
		t.Errorf("Bytes = %d, sink has %d", res.Bytes, sink.Len())
	}
	doc, err := waxlabel.Parse(context.Background(), waxlabel.BytesSource(sink.Bytes()))
	if err != nil {
		t.Fatalf("parsing streamed output: %v", err)
	}
	if got, _ := doc.Get(tag.SourceURL); len(got) != 1 || got[0] != watch {
		t.Errorf("SOURCE_URL = %v, want %q", got, watch)
	}
	if got, _ := doc.Get(tag.SourceID); len(got) != 1 || got[0] != vid(1) {
		t.Errorf("SOURCE_ID = %v, want %q", got, vid(1))
	}
	if got, _ := doc.Get(tag.AcquisitionDate); len(got) != 1 || got[0] == "" {
		t.Errorf("ACQUISITION_DATE = %v, want a value", got)
	}
}

func TestFetchEnforcesMaxBytes(t *testing.T) {
	f := channelFake(1)
	f.infos[vid(1)].Formats = audioFormats()
	f.payload = bytes.Repeat([]byte("x"), 64)
	p := testProvider(t, f, nil)

	var sink bytes.Buffer
	_, err := p.Fetch(context.Background(), source.FetchRequest{
		URL: "https://www.youtube.com/watch?v=" + vid(1), MaxBytes: 16,
	}, &sink)
	if err == nil {
		t.Fatal("want an over-size error")
	}
	if !strings.Contains(err.Error(), "exceeds 16-byte limit") {
		t.Errorf("error = %v, want the byte-limit refusal", err)
	}
	if sink.Len() != 0 {
		t.Errorf("sink received %d bytes despite the refusal", sink.Len())
	}
	left, _ := filepath.Glob(filepath.Join(f.workDir, "fetch-*"))
	if len(left) != 0 {
		t.Errorf("temp files left behind: %v", left)
	}
}

// TestWaxBinIntegration wires the provider into a real WaxBin library:
// subscribing a channel creates a youtube show whose episodes match the fake
// uploads, and downloading an episode pulls bytes through Fetch and flips it to
// downloaded.
func TestWaxBinIntegration(t *testing.T) {
	ctx := context.Background()
	f := channelFake(3)
	// Keep the catalog offline: no thumbnails or feed image means WaxBin never
	// tries to fetch artwork over the network.
	for _, v := range f.infos {
		v.Thumbnails = nil
	}
	for id := range f.infos {
		f.infos[id].Formats = audioFormats()
	}
	f.payload = []byte("episode payload bytes for the integration test")
	p := testProvider(t, f, nil)

	dir := t.TempDir()
	lib, err := waxbin.Open(ctx, waxbin.Options{
		DBPath:          filepath.Join(dir, "waxbin.db"),
		Podcasts:        config.PodcastConfig{Dir: filepath.Join(dir, "podcasts")},
		SourceProviders: []source.Provider{p},
	})
	if err != nil {
		t.Fatalf("waxbin.Open: %v", err)
	}
	defer lib.Close()

	pod, err := lib.Podcasts().AddSource(ctx, "https://www.youtube.com/@example", model.SourceYouTube, podcast.AddOptions{})
	if err != nil {
		t.Fatalf("AddSource: %v", err)
	}
	if pod.SourceType != model.SourceYouTube {
		t.Errorf("show source type = %q", pod.SourceType)
	}
	if pod.IdentityKey != "youtube:UUexample0123456789abcd" {
		t.Errorf("show identity = %q", pod.IdentityKey)
	}
	if pod.Title != "Example Uploads" {
		t.Errorf("show title = %q", pod.Title)
	}
	if pod.ETag != vid(3) {
		t.Errorf("stored ETag = %q, want the sync cursor %q", pod.ETag, vid(3))
	}

	eps, err := lib.Podcasts().Episodes(ctx, pod.PID, 0)
	if err != nil {
		t.Fatalf("Episodes: %v", err)
	}
	if len(eps) != 3 {
		t.Fatalf("episodes = %d, want 3", len(eps))
	}
	byGUID := map[string]bool{}
	for _, ep := range eps {
		byGUID[ep.GUID] = true
		if want := "https://www.youtube.com/watch?v=" + ep.GUID; ep.EnclosureURL != want {
			t.Errorf("episode %s enclosure = %q, want %q", ep.GUID, ep.EnclosureURL, want)
		}
	}
	for i := 1; i <= 3; i++ {
		if !byGUID[vid(i)] {
			t.Errorf("missing episode for %s", vid(i))
		}
	}

	// A cursor-honoring re-sync is a no-op: the provider answers NotModified.
	if res, err := lib.Podcasts().Sync(ctx, pod.PID); err != nil {
		t.Fatalf("Sync: %v", err)
	} else if res.EpisodesAdded != 0 || res.EpisodesUpdated != 0 {
		t.Errorf("unchanged channel re-sync touched episodes: %+v", res)
	}

	dl, err := lib.Podcasts().Download(ctx, eps[0].PID)
	if err != nil {
		t.Fatalf("Download: %v", err)
	}
	if dl.Bytes != int64(len(f.payload)) {
		t.Errorf("downloaded %d bytes, want %d", dl.Bytes, len(f.payload))
	}
	got, err := os.ReadFile(dl.Path)
	if err != nil {
		t.Fatalf("reading downloaded file: %v", err)
	}
	if !bytes.Equal(got, f.payload) {
		t.Error("downloaded file differs from the provider payload")
	}
	detail, err := lib.Podcasts().Episode(ctx, eps[0].PID)
	if err != nil {
		t.Fatalf("Episode: %v", err)
	}
	if !detail.Episode.Downloaded {
		t.Error("episode did not flip to downloaded")
	}
}
