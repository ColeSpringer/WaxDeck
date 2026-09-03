package waxtapsource

import (
	"bytes"
	"context"
	"errors"
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
	"github.com/colespringer/waxtap/v3/waxerr"
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
	warnings    []waxtap.Warning // emitted as events, and echoed on a successful Result
	// lastReq is the request the provider built, for the tests that are
	// about the spec rather than about the bytes.
	lastReq waxtap.Request
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
	f.lastReq = req
	// Warnings reach the event stream as the conditions occur, ahead of any
	// failure. The real client also copies them onto a successful Result (below),
	// and only onto a successful one -- that asymmetry is the thing under test.
	for i := range f.warnings {
		if req.Events != nil {
			req.Events(waxtap.Event{Stage: waxtap.StageWarning, Warning: &f.warnings[i]})
		}
	}
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
		Warnings:     f.warnings,
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
	return testProviderWith(t, f, logs, nil)
}

// testProviderWith is testProvider with a hand on the configuration, for
// the tests that are about what a config switch puts in the spec.
func testProviderWith(t *testing.T, f *fakeTap, logs *bytes.Buffer, mutate func(*Config)) *Provider {
	t.Helper()
	f.workDir = t.TempDir()
	var log *slog.Logger
	if logs != nil {
		log = slog.New(slog.NewTextHandler(logs, nil))
	}
	cfg := Config{WorkDir: f.workDir}
	if mutate != nil {
		mutate(&cfg)
	}
	return newProvider(f, cfg, log, nil)
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

// throttleErr is the metadata throttle's shape: UNPLAYABLE with the
// "Video unavailable" reason, classified as ErrVideoUnavailable. The
// reason text cannot separate it from a dead video; only the status
// can, which is why the predicate reads the status.
func throttleErr(id string) error {
	return fmt.Errorf("enrich %s: %w", id, &waxerr.PlayabilityError{
		Status: "UNPLAYABLE", Reason: "Video unavailable",
		Sentinel: waxtap.ErrVideoUnavailable,
	})
}

// deadErr is what a removed, private, or nonexistent video answers:
// the same sentinel under status ERROR.
func deadErr(id string) error {
	return fmt.Errorf("enrich %s: %w", id, &waxerr.PlayabilityError{
		Status: "ERROR", Reason: "Video unavailable",
		Sentinel: waxtap.ErrVideoUnavailable,
	})
}

func TestEnumerateKeepsThrottledEntriesAndStopsEnriching(t *testing.T) {
	f := channelFake(4)
	// The newest entry is enriched; the second is throttled, which ends
	// the pass. Entries are newest first, so vid(4) leads.
	f.infoErrs = map[string]error{vid(3): throttleErr(vid(3))}
	var logs bytes.Buffer
	p := testProvider(t, f, &logs)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u"})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	// Every entry survives: the throttle is about the identity asking,
	// not about the videos. This is the regression - the same sentinel
	// under a different status once dropped a third of a catalogue.
	if len(enum.Feed.Episodes) != 4 {
		t.Fatalf("episodes = %d, want all 4 kept", len(enum.Feed.Episodes))
	}
	// The throttled entry keeps the listing's own title rather than the
	// enriched one, which is exactly what "unenriched" means.
	byID := map[string]string{}
	for _, ep := range enum.Feed.Episodes {
		byID[ep.GUID] = ep.Title
	}
	if got := byID[vid(4)]; got != "full title "+vid(4) {
		t.Errorf("first entry title = %q, want the enriched one", got)
	}
	if got := byID[vid(3)]; got != "upload "+vid(3) {
		t.Errorf("throttled entry title = %q, want the listing's", got)
	}
	// The budget stops being spent: no Info call after the refusal.
	if len(f.infoCalls) != 2 {
		t.Errorf("Info calls = %v, want the pass to stop at the throttle", f.infoCalls)
	}
	if !strings.Contains(logs.String(), "youtube metadata throttled") {
		t.Error("the throttle was not logged")
	}
	if strings.Contains(logs.String(), "skipping unavailable youtube entry") {
		t.Error("a throttled entry was reported as unavailable")
	}
	// The cursor does not move past entries this pass could not enrich.
	// Advancing it would make the gap permanent: the next run's Stop
	// lists nothing at or below the cursor, so those episodes would keep
	// the listing's bare title for the life of the subscription.
	if enum.ETag != "" {
		t.Errorf("ETag = %q on a throttled first sync, want the cursor held", enum.ETag)
	}
}

// TestEnumerateHoldsTheCursorWhenThrottled is the incremental half: a
// later run that throttles must leave the stored cursor where it was,
// so the entries it could not enrich are listed again next time.
func TestEnumerateHoldsTheCursorWhenThrottled(t *testing.T) {
	f := channelFake(4)
	f.infoErrs = map[string]error{vid(3): throttleErr(vid(3))}
	p := testProvider(t, f, nil)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u", ETag: vid(2)})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if enum.ETag != vid(2) {
		t.Errorf("ETag = %q, want the incoming cursor %q held", enum.ETag, vid(2))
	}
}

// TestEnumerateAdvancesTheCursorWhenOnlySkipping is the contrast: a
// dropped entry is genuinely gone, so the cursor moves past it.
func TestEnumerateAdvancesTheCursorWhenOnlySkipping(t *testing.T) {
	f := channelFake(4)
	f.infoErrs = map[string]error{vid(3): deadErr(vid(3))}
	p := testProvider(t, f, nil)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u"})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if enum.ETag != vid(4) {
		t.Errorf("ETag = %q, want the newest listed id %q", enum.ETag, vid(4))
	}
}

func TestEnumerateStillSkipsAnErrorStatusVideo(t *testing.T) {
	f := channelFake(3)
	f.infoErrs = map[string]error{vid(2): deadErr(vid(2))}
	var logs bytes.Buffer
	p := testProvider(t, f, &logs)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u"})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if len(enum.Feed.Episodes) != 2 {
		t.Fatalf("episodes = %d, want the removed video dropped", len(enum.Feed.Episodes))
	}
	for _, ep := range enum.Feed.Episodes {
		if ep.GUID == vid(2) {
			t.Error("a status-ERROR video was cataloged")
		}
	}
	// And the pass carries on: a verdict about one video says nothing
	// about the next.
	if len(f.infoCalls) != 3 {
		t.Errorf("Info calls = %v, want every entry probed", f.infoCalls)
	}
	if !strings.Contains(logs.String(), "skipping unavailable youtube entry") {
		t.Error("the skip was not logged")
	}
}

// TestEnumerateTreatsAnyUnplayableAsThrottled pins the edge of the
// predicate. Upstream classifies only "members" and "country" reasons
// specially, so an UNPLAYABLE blocked for anything else - a copyright
// claim, a policy takedown - also folds to ErrVideoUnavailable and
// matches the throttle shape. That is deliberate and it is the safe
// direction: a false throttle defers enrichment to the next run, while
// a false skip drops the episode from the feed for good.
func TestEnumerateTreatsAnyUnplayableAsThrottled(t *testing.T) {
	f := channelFake(3)
	f.infoErrs = map[string]error{
		vid(2): fmt.Errorf("enrich %s: %w", vid(2), &waxerr.PlayabilityError{
			Status: "UNPLAYABLE", Reason: "This video is no longer available due to a copyright claim",
			Sentinel: waxtap.ErrVideoUnavailable,
		}),
	}
	p := testProvider(t, f, nil)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u"})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	// Kept, not dropped: the entry is cataloged bare and the cursor
	// holds, so the next run re-lists it and can settle the question.
	if len(enum.Feed.Episodes) != 3 {
		t.Fatalf("episodes = %d, want the entry kept for a later pass", len(enum.Feed.Episodes))
	}
	if enum.ETag != "" {
		t.Errorf("ETag = %q, want the cursor held so the entry is re-listed", enum.ETag)
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

// opusFormats is a candidate list whose best-audio row is YouTube's highest
// quality Opus stream, which the platform delivers in a WebM container.
func opusFormats() []waxtap.Format {
	return []waxtap.Format{{
		Itag:     251,
		MIMEType: `audio/webm; codecs="opus"`,
		Codec:    "opus", Extension: "webm",
		Bitrate: 160000, Channels: 2,
		AudioQuality: waxtap.QualityHigh,
	}}
}

// TestContainerExtForCodec locks the codec-to-container mapping: YouTube's best
// audio (Opus in WebM) must stage as .opus, never .webm, so the catalog imports
// it and cover art can be embedded.
func TestContainerExtForCodec(t *testing.T) {
	cases := []struct {
		codec, native, want string
	}{
		{"opus", "webm", "opus"},     // the reported bug: Opus-in-WebM
		{"vorbis", "webm", "ogg"},    // legacy Vorbis-in-WebM
		{"mp4a.40.2", "m4a", "m4a"},  // AAC-LC
		{"mp4a.40.5", "m4a", "m4a"},  // HE-AAC
		{"mp4a.40.34", "m4a", "mp3"}, // MP3 in an MP4 descriptor
		{"mp3", "mp3", "mp3"},
		{"flac", "flac", "flac"},
		{"", "m4a", "m4a"},   // unknown codec, recognized native container
		{"", "webm", "opus"}, // unknown codec, unrecognized native: Ogg-Opus fallback
	}
	for _, c := range cases {
		if got := containerExtForCodec(c.codec, c.native); got != c.want {
			t.Errorf("containerExtForCodec(%q, %q) = %q, want %q", c.codec, c.native, got, c.want)
		}
	}
}

// TestTranscodeFor locks the format-preference mapping: "best"/empty is the
// lossless copy (container from the codec), and each named format transcodes
// into its own recognized, picture-capable container.
func TestTranscodeFor(t *testing.T) {
	best := opusFormats()
	cases := []struct {
		format  string
		wantF   waxtap.TranscodeFormat
		wantExt string
	}{
		{"", waxtap.FormatCopy, "opus"},
		{"best", waxtap.FormatCopy, "opus"},
		{"opus", waxtap.FormatOpus, "opus"},
		{"mp3", waxtap.FormatMP3, "mp3"},
		{"m4a", waxtap.FormatAAC, "m4a"},
		{"flac", waxtap.FormatFLAC, "flac"},
		{"weird", waxtap.FormatCopy, "opus"}, // unknown falls back to best
	}
	for _, c := range cases {
		spec, ext := transcodeFor(c.format, best)
		if spec.Format != c.wantF || ext != c.wantExt {
			t.Errorf("transcodeFor(%q) = (%v, %q), want (%v, %q)", c.format, spec.Format, ext, c.wantF, c.wantExt)
		}
	}
}

// TestFetchFormatTranscodesToRequestedContainer checks a named format delivers
// its own container through the acquisition capability path.
func TestFetchFormatTranscodesToRequestedContainer(t *testing.T) {
	f := channelFake(1)
	f.infos[vid(1)].Formats = opusFormats()
	f.payload = []byte("stand-in for transcoded mp3 bytes")
	p := testProvider(t, f, nil)

	var sink bytes.Buffer
	res, err := p.FetchFormat(context.Background(), source.FetchRequest{URL: "https://www.youtube.com/watch?v=" + vid(1)}, &sink, "mp3")
	if err != nil {
		t.Fatalf("FetchFormat: %v", err)
	}
	if res.ContentType != "audio/mpeg" {
		t.Errorf("ContentType = %q, want audio/mpeg", res.ContentType)
	}
}

// TestFetchDeliversOpusInRecognizedContainer is the end-to-end guard for the
// same bug through Fetch: an Opus best-audio row must surface as audio/opus.
func TestFetchDeliversOpusInRecognizedContainer(t *testing.T) {
	f := channelFake(1)
	f.infos[vid(1)].Formats = opusFormats()
	f.payload = []byte("deterministic bytes standing in for an ogg-opus container")
	p := testProvider(t, f, nil)

	var sink bytes.Buffer
	res, err := p.Fetch(context.Background(), source.FetchRequest{URL: "https://www.youtube.com/watch?v=" + vid(1)}, &sink)
	if err != nil {
		t.Fatalf("Fetch: %v", err)
	}
	if res.ContentType != "audio/opus" {
		t.Errorf("ContentType = %q, want audio/opus (never audio/webm)", res.ContentType)
	}
}

// The cover-art mode rides the thumbnail switch and cannot be set
// without it: a mode with no embed to shape is ErrIncompatibleSpec,
// which would fail every acquisition rather than shape none of them.
func TestFetchCoverArtFollowsEmbedThumbnail(t *testing.T) {
	for _, tc := range []struct {
		name  string
		embed bool
		want  waxtap.CoverArtMode
	}{
		{name: "embedding", embed: true, want: waxtap.CoverArtSquare},
		{name: "not embedding", embed: false, want: waxtap.CoverArtFrame},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := channelFake(1)
			f.infos[vid(1)].Formats = audioFormats()
			f.payload = []byte("deterministic bytes")
			p := testProviderWith(t, f, nil, func(c *Config) { c.EmbedThumbnail = tc.embed })

			var sink bytes.Buffer
			if _, err := p.Fetch(context.Background(),
				source.FetchRequest{URL: "https://www.youtube.com/watch?v=" + vid(1)}, &sink); err != nil {
				t.Fatalf("Fetch: %v", err)
			}
			if got := f.lastReq.EmbedThumbnail; got != tc.embed {
				t.Fatalf("EmbedThumbnail = %v, want %v", got, tc.embed)
			}
			if got := f.lastReq.CoverArt; got != tc.want {
				t.Errorf("CoverArt = %v, want %v", got, tc.want)
			}
		})
	}
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

// TestFetchLogsWarningsOnFailedDownload is the reason the provider reads the
// event stream instead of Result.Warnings. WaxTap copies its accumulated warnings
// onto the Result only when the job succeeds, so a failed download returns a nil
// Result and takes them with it -- losing them from exactly the run that needed
// explaining (a Seal sidecar answering 401 warns about the context fallback, then
// fails). The error still propagates untouched.
func TestFetchLogsWarningsOnFailedDownload(t *testing.T) {
	f := channelFake(1)
	f.infos[vid(1)].Formats = audioFormats()
	f.downloadErr = errors.New("player-context sidecar: 401")
	f.warnings = []waxtap.Warning{
		{Code: waxtap.WarnWebContextFallback, Detail: "set or verify --api-key"},
	}
	var logs bytes.Buffer
	p := testProvider(t, f, &logs)

	var sink bytes.Buffer
	_, err := p.Fetch(context.Background(), source.FetchRequest{URL: "https://www.youtube.com/watch?v=" + vid(1)}, &sink)
	if err == nil {
		t.Fatal("Fetch succeeded, want the download error")
	}
	if !strings.Contains(err.Error(), "401") {
		t.Errorf("err = %v, want the download error unwrapped through", err)
	}
	for _, want := range []string{`level=WARN msg="youtube download degraded"`, `code=web-context-fallback`} {
		if !strings.Contains(logs.String(), want) {
			t.Errorf("missing %q in logs:\n%s", want, logs.String())
		}
	}
}

// TestFetchLogsDownloadWarnings pins the split: WaxTap reports its non-fatal
// conditions rather than failing, so a degraded delivery is indistinguishable
// from a clean one unless the provider surfaces them. A condition WaxTap
// recovered from is informational; one that changed what was delivered warns.
func TestFetchLogsDownloadWarnings(t *testing.T) {
	f := channelFake(1)
	f.infos[vid(1)].Formats = audioFormats()
	f.payload = []byte("deterministic bytes")
	f.warnings = []waxtap.Warning{
		{Code: waxtap.WarnSessionRotated, Detail: "continuing with a new session"},
		{Code: waxtap.WarnProceedUncut, Detail: "sponsorblock unreachable"},
		// A code this build's WaxTap added: the recovered set is a
		// closed list and everything else warns, so a new one describing
		// a worse delivery lands on the right side without being named.
		{Code: waxtap.WarnImplicitLossy, Detail: "opus re-encoded into m4a"},
	}
	var logs bytes.Buffer
	p := testProvider(t, f, &logs)

	var sink bytes.Buffer
	if _, err := p.Fetch(context.Background(), source.FetchRequest{URL: "https://www.youtube.com/watch?v=" + vid(1)}, &sink); err != nil {
		t.Fatalf("Fetch: %v", err)
	}
	for _, want := range []string{
		`level=INFO msg="youtube download recovered" url=`,
		`code=session-rotated`,
		`level=WARN msg="youtube download degraded" url=`,
		`code=proceed-uncut`,
		`code=implicit-lossy`,
	} {
		if !strings.Contains(logs.String(), want) {
			t.Errorf("missing %q in logs:\n%s", want, logs.String())
		}
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

// The committed-with-error quadrant is driven by a post-commit fsync, which
// no integration test can provoke, so this table is the only pin the
// decision gets. Duplicated from the service package, which this one cannot
// import.
func TestWriteLanded(t *testing.T) {
	t.Parallel()
	postCommit := errors.New("syncing directory: input/output error")
	for _, tc := range []struct {
		name string
		res  waxlabel.SaveResult
		err  error
		want bool
	}{
		{"the bytes landed", waxlabel.SaveResult{Committed: true}, nil, true},
		{"a no-op plan wrote nothing by contract", waxlabel.SaveResult{}, nil, true},
		{"the write landed and a step after it failed", waxlabel.SaveResult{Committed: true}, postCommit, true},
		{"nothing was written", waxlabel.SaveResult{}, postCommit, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			if got := writeLanded(tc.res, tc.err); got != tc.want {
				t.Errorf("writeLanded(%+v, %v) = %v, want %v", tc.res, tc.err, got, tc.want)
			}
		})
	}
}
