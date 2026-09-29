package waxtapsource

import (
	"bytes"
	"cmp"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	waxbin "github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/config"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/podcast"
	"github.com/colespringer/waxbin/source"
	catalogerr "github.com/colespringer/waxbin/waxerr"
	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/db"
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
	// infoOpts is how many read options each Info call carried, beside
	// infoCalls.
	infoOpts []int
	// beforeInfo, when set, runs as each Info call starts.
	beforeInfo func(id string)

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
	// lastEnum is the options the provider asked enumeration with.
	lastEnum waxtap.EnumerateOptions
	// enumErr, when set, fails every listing.
	enumErr error
}

var _ tap = (*fakeTap)(nil)

func (f *fakeTap) Enumerate(ctx context.Context, _ string, opts waxtap.EnumerateOptions) (*waxtap.Playlist, error) {
	f.lastEnum = opts
	if f.enumErr != nil {
		return nil, f.enumErr
	}
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
	if !opts.Enrich {
		return out, nil
	}
	// Enrichment mirrors the real client's: the leading MaxEnrich entries that
	// are not live get a lookup, a fetched field left empty keeps the listing's,
	// and a failure lands in Errors under the entry's playlist position.
	asked := 0
	for i := range out.Entries {
		if opts.MaxEnrich > 0 && asked == opts.MaxEnrich {
			break
		}
		if s := out.Entries[i].LiveStatus; s == waxtap.LiveNow || s == waxtap.LiveUpcoming {
			continue
		}
		asked++
		v, err := f.Info(ctx, out.Entries[i].VideoID, waxtap.InfoBasic, opts.EnrichOptions...)
		if err != nil {
			out.Errors = append(out.Errors, &waxtap.EnrichError{
				VideoID: out.Entries[i].VideoID,
				Index:   out.Entries[i].Index,
				Err:     err,
			})
			continue
		}
		out.Entries[i].Video = v
		out.Entries[i].Title = cmp.Or(v.Title, out.Entries[i].Title)
		out.Entries[i].Author = cmp.Or(v.Author, out.Entries[i].Author)
		out.Entries[i].Duration = cmp.Or(v.Duration, out.Entries[i].Duration)
	}
	return out, nil
}

func (f *fakeTap) Info(_ context.Context, url string, _ waxtap.InfoDepth, opts ...waxtap.ReadOption) (*waxtap.Video, error) {
	id := strings.TrimPrefix(url, "https://www.youtube.com/watch?v=")
	if f.beforeInfo != nil {
		f.beforeInfo(id)
	}
	f.infoCalls = append(f.infoCalls, id)
	f.infoOpts = append(f.infoOpts, len(opts))
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

// deferredErr is what enumeration reports for an entry it never got to
// prove: the throttle shape relabeled ErrTemporarilyUnavailable, which
// is upstream's word for "the budget ran out, come back".
func deferredErr() error {
	return fmt.Errorf("%w: %w", waxtap.ErrTemporarilyUnavailable, &waxerr.PlayabilityError{
		Status: "UNPLAYABLE", Reason: "Video unavailable",
		Sentinel: waxtap.ErrVideoUnavailable,
	})
}

// deadErr is what a removed, private, or nonexistent video answers:
// ErrVideoUnavailable under status ERROR.
func deadErr() error {
	return &waxerr.PlayabilityError{
		Status: "ERROR", Reason: "Video unavailable",
		Sentinel: waxtap.ErrVideoUnavailable,
	}
}

// provenUnplayableErr is the throttle's own shape arriving unrelabeled:
// enumeration retired the identity that refused it and a fresh one
// refused it again, so it is a verdict about the video.
func provenUnplayableErr() error {
	return &waxerr.PlayabilityError{
		Status: "UNPLAYABLE", Reason: "Video unavailable",
		Sentinel: waxtap.ErrVideoUnavailable,
	}
}

// TestEnumerateAsksEnumerationToEnrich pins where the per-entry budget
// is spent. It has to be inside enumeration: that is the only place the
// metadata throttle is escaped, because escaping it means retiring the
// identity the refusals came from and asking again.
func TestEnumerateAsksEnumerationToEnrich(t *testing.T) {
	f := channelFake(3)
	p := testProvider(t, f, nil)

	if _, err := p.Enumerate(context.Background(), source.Request{URL: "u"}); err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if !f.lastEnum.Enrich {
		t.Error("enumeration was asked without Enrich")
	}
	if f.lastEnum.MaxEnrich != enrichLimit {
		t.Errorf("MaxEnrich = %d, want the budget %d", f.lastEnum.MaxEnrich, enrichLimit)
	}
	if len(f.lastEnum.EnrichOptions) != 1 {
		t.Errorf("EnrichOptions = %d, want the full-metadata pass", len(f.lastEnum.EnrichOptions))
	}
}

func TestEnumerateKeepsDeferredEntriesBare(t *testing.T) {
	f := channelFake(4)
	// Entries are newest first, so vid(4) leads; the second entry is the
	// one enumeration ran out of budget on.
	f.infoErrs = map[string]error{vid(3): deferredErr()}
	var logs bytes.Buffer
	p := testProvider(t, f, &logs)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u"})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	// Every entry survives: a deferral is about the identity asking, not
	// about the videos. This is the regression - the same sentinel under
	// a different status once dropped a third of a catalogue.
	if len(enum.Feed.Episodes) != 4 {
		t.Fatalf("episodes = %d, want all 4 kept", len(enum.Feed.Episodes))
	}
	// The deferred entry keeps the listing's own title rather than the
	// enriched one, which is exactly what "unenriched" means.
	byID := map[string]string{}
	for _, ep := range enum.Feed.Episodes {
		byID[ep.GUID] = ep.Title
	}
	if got := byID[vid(4)]; got != "full title "+vid(4) {
		t.Errorf("first entry title = %q, want the enriched one", got)
	}
	if got := byID[vid(3)]; got != "upload "+vid(3) {
		t.Errorf("deferred entry title = %q, want the listing's", got)
	}
	// The entries after it are enriched all the same: enumeration spent
	// the budget on them under a rotated identity, so there is nothing
	// left for this pass to save by stopping.
	if got := byID[vid(2)]; got != "full title "+vid(2) {
		t.Errorf("entry after the deferral = %q, want it enriched", got)
	}
	if !strings.Contains(logs.String(), "youtube metadata deferred") {
		t.Error("the deferral was not logged")
	}
	if strings.Contains(logs.String(), "skipping unavailable youtube entry") {
		t.Error("a deferred entry was reported as unavailable")
	}
	// The cursor does not move past entries this pass could not enrich.
	// Advancing it would make the gap permanent: the next run's Stop
	// lists nothing at or below the cursor, so those episodes would keep
	// the listing's bare title for the life of the subscription.
	if enum.ETag != "" {
		t.Errorf("ETag = %q on a deferred first sync, want the cursor held", enum.ETag)
	}
}

// TestEnumerateHoldsTheCursorWhenDeferred is the incremental half: a
// later run that defers must leave the stored cursor where it was, so
// the entries it could not enrich are listed again next time.
func TestEnumerateHoldsTheCursorWhenDeferred(t *testing.T) {
	f := channelFake(4)
	f.infoErrs = map[string]error{vid(3): deferredErr()}
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
	f.infoErrs = map[string]error{vid(3): deadErr()}
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
	f.infoErrs = map[string]error{vid(2): deadErr()}
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

// TestEnumerateDropsAProvenUnplayableEntry is the half of the taxonomy
// that changed when enumeration took the budget over. An UNPLAYABLE
// refusal used to be kept on the chance it was the throttle, because a
// lone lookup could not tell; enumeration can, by retiring the identity
// and asking again, so one that arrives unrelabeled has already been
// re-asked under a fresh identity and is a verdict about the video.
func TestEnumerateDropsAProvenUnplayableEntry(t *testing.T) {
	f := channelFake(3)
	f.infoErrs = map[string]error{vid(2): provenUnplayableErr()}
	p := testProvider(t, f, nil)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u"})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if len(enum.Feed.Episodes) != 2 {
		t.Fatalf("episodes = %d, want the proven-unplayable entry dropped", len(enum.Feed.Episodes))
	}
	if enum.ETag != vid(3) {
		t.Errorf("ETag = %q, want the cursor advanced past a settled verdict", enum.ETag)
	}
}

// TestEnumerateKeepsAWhollyRefusedPass is the address the platform has
// flagged: every identity minted from it is refused the same way, and
// WaxTap's rule that a pass recovering nothing proves the failures real
// reports the whole budget as removed videos. A channel does not lose
// twenty-five episodes in one poll; the pass is kept bare and re-listed.
func TestEnumerateKeepsAWhollyRefusedPass(t *testing.T) {
	f := channelFake(30)
	f.infoErrs = map[string]error{}
	for i := 30; i > 5; i-- {
		f.infoErrs[vid(i)] = provenUnplayableErr()
	}
	var logs bytes.Buffer
	p := testProvider(t, f, &logs)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u"})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if len(enum.Feed.Episodes) != 30 {
		t.Fatalf("episodes = %d, want all 30 kept", len(enum.Feed.Episodes))
	}
	if enum.ETag != "" {
		t.Errorf("ETag = %q, want the cursor held so the pass is re-listed", enum.ETag)
	}
	if !strings.Contains(logs.String(), "every youtube entry the budget reached was refused") {
		t.Error("the refused pass was not logged")
	}
	if strings.Contains(logs.String(), "skipping unavailable youtube entry") {
		t.Error("a refused pass was reported as removals")
	}
}

// TestEnumerateStillDropsAPartlyRefusedPass is the contrast that keeps
// the guard honest: verdicts among successes are verdicts.
func TestEnumerateStillDropsAPartlyRefusedPass(t *testing.T) {
	f := channelFake(30)
	f.infoErrs = map[string]error{vid(30): provenUnplayableErr(), vid(29): provenUnplayableErr()}
	p := testProvider(t, f, nil)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u"})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if len(enum.Feed.Episodes) != 28 {
		t.Fatalf("episodes = %d, want the two verdicts dropped", len(enum.Feed.Episodes))
	}
	if enum.ETag != vid(30) {
		t.Errorf("ETag = %q, want the cursor advanced", enum.ETag)
	}
}

// episodeGUIDs lists a feed's episode ids in order.
func episodeGUIDs(feed *model.Feed) []string {
	var out []string
	for _, ep := range feed.Episodes {
		out = append(out, ep.GUID)
	}
	return out
}

// A live or upcoming broadcast cannot download until it ends, so it is not
// cataloged, and the cursor stays below one at the top of the feed so the
// entry is listed again once it has.
func TestEnumerateDropsLiveAndUpcomingEntries(t *testing.T) {
	f := channelFake(5)
	f.playlist.Entries[0].LiveStatus = waxtap.LiveUpcoming // vid(5), the newest
	f.playlist.Entries[2].LiveStatus = waxtap.LiveNow      // vid(3)
	f.playlist.Entries[3].LiveStatus = waxtap.LiveWasLive  // vid(2), a finished stream
	p := testProvider(t, f, nil)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u"})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if got, want := episodeGUIDs(enum.Feed), []string{vid(4), vid(2), vid(1)}; !slices.Equal(got, want) {
		t.Errorf("episodes = %v, want %v", got, want)
	}
	if enum.ETag != vid(4) {
		t.Errorf("ETag = %q, want the newest entry that is not live, %q", enum.ETag, vid(4))
	}
}

// A long file downloads four 10 MiB chunks at once, and each has to land
// inside the chunk deadline over a slow home link, unattended.
func TestChunkDeadlineFitsASlowLink(t *testing.T) {
	const chunkBits, parallel, linkBitsPerSecond = 10 << 20 * 8, 4, 600_000
	need := time.Duration(chunkBits*parallel/linkBitsPerSecond) * time.Second
	if tapTimeouts.ChunkRetry < need {
		t.Errorf("ChunkRetry = %v, want at least %v for a 600 kbit/s link", tapTimeouts.ChunkRetry, need)
	}
}

// A premiere at the top of a channel has no video to lend the feed its
// image, so the newest entry that does lends it instead.
func TestEnumerateTakesTheImagePastALiveEntry(t *testing.T) {
	f := channelFake(3)
	f.playlist.Entries[0].LiveStatus = waxtap.LiveUpcoming // vid(3)
	p := testProvider(t, f, nil)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u"})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if want := "https://i.ytimg.com/vi/" + vid(2) + "/max.jpg"; enum.Feed.ImageURL != want {
		t.Errorf("feed image = %q, want %q", enum.Feed.ImageURL, want)
	}
}

// examplePlaylist is channelFake's playlist id, which the held entries
// are keyed by.
const examplePlaylist = "UUexample0123456789abcd"

// pendingProvider is testProvider with the second look wired to a real
// store and a clock the test moves.
func pendingProvider(t *testing.T, f *fakeTap, logs *bytes.Buffer) (*Provider, *db.DB, *time.Time) {
	t.Helper()
	store, err := db.Open(context.Background(), filepath.Join(t.TempDir(), "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	p := testProviderWith(t, f, logs, func(c *Config) { c.Pending = store })
	clock := time.Date(2026, 3, 1, 12, 0, 0, 0, time.UTC)
	p.now = func() time.Time { return clock }
	return p, store, &clock
}

// heldIDs lists what the second look holds at the test's clock.
func heldIDs(t *testing.T, store *db.DB, clock *time.Time) []string {
	t.Helper()
	ids, err := store.YouTubePending(context.Background(), examplePlaylist, clock.UnixNano())
	if err != nil {
		t.Fatal(err)
	}
	return ids
}

// infoCallsFor counts the lookups made for one id.
func infoCallsFor(f *fakeTap, id string) int {
	n := 0
	for _, c := range f.infoCalls {
		if c == id {
			n++
		}
	}
	return n
}

// A premiere below a newer upload no longer holds the cursor, so the
// listing never names it again; it is looked at on later polls and
// cataloged on the first one after it airs, with the cursor left where
// the listing put it.
func TestEnumerateCatalogsAPassedOverPremiereOnceItAirs(t *testing.T) {
	f := channelFake(3)
	f.playlist.Entries[1].LiveStatus = waxtap.LiveUpcoming // vid(2), below vid(3)
	f.infoErrs = map[string]error{vid(2): waxtap.ErrLiveNotStarted}
	p, store, clock := pendingProvider(t, f, nil)
	ctx := context.Background()

	first, err := p.Enumerate(ctx, source.Request{URL: "u"})
	if err != nil {
		t.Fatalf("first sync: %v", err)
	}
	if first.ETag != vid(3) {
		t.Fatalf("ETag = %q, want %q", first.ETag, vid(3))
	}
	if got, want := episodeGUIDs(first.Feed), []string{vid(3), vid(1)}; !slices.Equal(got, want) {
		t.Fatalf("episodes = %v, want %v", got, want)
	}

	still, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: vid(3)})
	if err != nil {
		t.Fatalf("poll while upcoming: %v", err)
	}
	if !still.NotModified {
		t.Errorf("poll while upcoming = %+v, want NotModified", still)
	}
	if n := infoCallsFor(f, vid(2)); n != 1 {
		t.Errorf("lookups for the premiere = %d, want 1", n)
	}

	// The premiere airs: a lookup now answers with the video.
	f.playlist.Entries[1].LiveStatus = waxtap.LiveNone
	delete(f.infoErrs, vid(2))
	aired, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: vid(3)})
	if err != nil {
		t.Fatalf("poll after it aired: %v", err)
	}
	if aired.NotModified || aired.Feed == nil {
		t.Fatalf("poll after it aired = %+v, want a feed", aired)
	}
	if got := episodeGUIDs(aired.Feed); !slices.Equal(got, []string{vid(2)}) {
		t.Fatalf("episodes = %v, want the premiere alone", got)
	}
	ep := aired.Feed.Episodes[0]
	if ep.Title != "full title "+vid(2) || ep.Description == "" || ep.PubDateNS == 0 {
		t.Errorf("premiere not built as an enriched entry: %+v", ep)
	}
	if want := "https://www.youtube.com/watch?v=" + vid(2); ep.EnclosureURL != want {
		t.Errorf("enclosure = %q, want %q", ep.EnclosureURL, want)
	}
	// The listing named nothing, so the feed's own fields are what keep
	// the show row from being blanked.
	if aired.Feed.Title != "Example Uploads" || aired.Feed.Author != "Example" {
		t.Errorf("feed title/author = %q/%q", aired.Feed.Title, aired.Feed.Author)
	}
	if want := "https://i.ytimg.com/vi/" + vid(2) + "/max.jpg"; aired.Feed.ImageURL != want {
		t.Errorf("feed image = %q, want %q", aired.Feed.ImageURL, want)
	}

	// The catalog stores the answer's cursor, which still stops where the
	// listing left it and now confirms the hand-over.
	after, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: aired.ETag})
	if err != nil {
		t.Fatalf("poll after cataloging: %v", err)
	}
	if !after.NotModified {
		t.Errorf("poll after cataloging = %+v, want NotModified", after)
	}
	if n := infoCallsFor(f, vid(2)); n != 2 {
		t.Errorf("lookups for the premiere = %d, want no more after it was cataloged", n)
	}
	if held := heldIDs(t, store, clock); len(held) != 0 {
		t.Errorf("held = %v, want nothing", held)
	}
}

// An aired entry is let go only once the catalog has written it, which
// the next poll's cursor says: one whose sync failed, so the catalog
// still holds the old cursor, is offered again.
func TestEnumerateOffersAnAiredEntryAgainUntilTheCatalogHasIt(t *testing.T) {
	f := channelFake(3)
	f.playlist.Entries[1].LiveStatus = waxtap.LiveUpcoming // vid(2)
	f.infoErrs = map[string]error{vid(2): waxtap.ErrLiveNotStarted}
	p, store, clock := pendingProvider(t, f, nil)
	ctx := context.Background()
	first, err := p.Enumerate(ctx, source.Request{URL: "u"})
	if err != nil {
		t.Fatal(err)
	}
	delete(f.infoErrs, vid(2))
	if _, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: first.ETag}); err != nil {
		t.Fatal(err)
	}

	again, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: first.ETag})
	if err != nil {
		t.Fatal(err)
	}
	if again.Feed == nil || !slices.Equal(episodeGUIDs(again.Feed), []string{vid(2)}) {
		t.Fatalf("poll after the lost answer = %+v, want the premiere offered again", again)
	}
	if held := heldIDs(t, store, clock); !slices.Equal(held, []string{vid(2)}) {
		t.Errorf("held = %v, want the premiere until the catalog has it", held)
	}

	done, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: again.ETag})
	if err != nil {
		t.Fatal(err)
	}
	if !done.NotModified {
		t.Errorf("poll after the stored answer = %+v, want NotModified", done)
	}
	if held := heldIDs(t, store, clock); len(held) != 0 {
		t.Errorf("held = %v, want nothing", held)
	}
}

// A throttled pass holds the cursor, and a hand-over in the same poll
// still rides it: the next poll re-lists the deferred upload and lets
// the premiere the listing cataloged go.
func TestEnumerateHandsOverBesideADeferredPass(t *testing.T) {
	f := channelFake(3)
	f.playlist.Entries[0].LiveStatus = waxtap.LiveUpcoming // vid(3), at the top
	p, store, clock := pendingProvider(t, f, nil)
	ctx := context.Background()
	first, err := p.Enumerate(ctx, source.Request{URL: "u"})
	if err != nil {
		t.Fatal(err)
	}

	// The premiere airs as a newer upload lands whose enrichment is deferred.
	f.playlist.Entries[0].LiveStatus = waxtap.LiveNone
	f.playlist.Entries = append([]waxtap.PlaylistEntry{{VideoID: vid(4), Title: "upload " + vid(4)}}, f.playlist.Entries...)
	f.infoErrs = map[string]error{vid(4): deferredErr()}
	both, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: first.ETag})
	if err != nil {
		t.Fatal(err)
	}
	if got, want := episodeGUIDs(both.Feed), []string{vid(4), vid(3)}; !slices.Equal(got, want) {
		t.Fatalf("episodes = %v, want %v", got, want)
	}

	delete(f.infoErrs, vid(4))
	next, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: both.ETag})
	if err != nil {
		t.Fatal(err)
	}
	if next.Feed == nil || !slices.Equal(episodeGUIDs(next.Feed), []string{vid(4), vid(3)}) {
		t.Fatalf("next poll = %+v, want the held cursor's page listed again", next)
	}
	if held := heldIDs(t, store, clock); len(held) != 0 {
		t.Errorf("held = %v, want the premiere let go", held)
	}
}

// The horizon runs from the last listing that showed an entry live, so
// one passed over late in a long wait still gets all of it.
func TestEnumerateCountsTheHorizonFromTheLastLiveListing(t *testing.T) {
	f := channelFake(3)
	f.playlist.Entries[0].LiveStatus = waxtap.LiveUpcoming // vid(3), at the top
	f.infoErrs = map[string]error{vid(3): waxtap.ErrLiveNotStarted}
	p, _, clock := pendingProvider(t, f, nil)
	ctx := context.Background()
	first, err := p.Enumerate(ctx, source.Request{URL: "u"})
	if err != nil {
		t.Fatal(err)
	}

	// 89 days on it is still listed at the top when an upload passes it.
	*clock = clock.Add(89 * 24 * time.Hour)
	f.playlist.Entries = append([]waxtap.PlaylistEntry{{VideoID: vid(4), Title: "upload " + vid(4)}}, f.playlist.Entries...)
	passed, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: first.ETag})
	if err != nil {
		t.Fatal(err)
	}

	*clock = clock.Add(2 * 24 * time.Hour)
	f.infoCalls = nil
	if _, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: passed.ETag}); err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(f.infoCalls, []string{vid(3)}) {
		t.Errorf("lookups two days after it was passed over = %v, want the premiere", f.infoCalls)
	}
}

// A stream that starts and ends between two polls lists as an ordinary
// video, and its lookup can still say live or not started. That is "not
// yet", so the entry is held like a live one rather than dropped while
// the cursor passes it.
func TestEnumerateHoldsAnEntryWhoseLookupFindsItLive(t *testing.T) {
	f := channelFake(3)
	f.infoErrs = map[string]error{vid(3): fmt.Errorf("enrich: %w", waxtap.ErrLiveNotStarted)}
	p, store, clock := pendingProvider(t, f, nil)
	ctx := context.Background()
	first, err := p.Enumerate(ctx, source.Request{URL: "u"})
	if err != nil {
		t.Fatal(err)
	}
	if got, want := episodeGUIDs(first.Feed), []string{vid(2), vid(1)}; !slices.Equal(got, want) {
		t.Fatalf("episodes = %v, want %v", got, want)
	}
	if held := heldIDs(t, store, clock); !slices.Equal(held, []string{vid(3)}) {
		t.Fatalf("held = %v, want the stream", held)
	}

	delete(f.infoErrs, vid(3))
	ready, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: first.ETag})
	if err != nil {
		t.Fatal(err)
	}
	if ready.Feed == nil || !slices.Equal(episodeGUIDs(ready.Feed), []string{vid(3)}) {
		t.Errorf("poll once it is ready = %+v, want the stream", ready)
	}
}

// A held stream that ends lists as an ordinary video while its
// recording is still processing, and a lookup then answers in ways that
// are not a verdict. It stays held, and is cataloged once it is ready.
func TestEnumerateKeepsAHeldEntryTheListingCouldNotSettle(t *testing.T) {
	for _, tc := range []struct {
		name string
		err  error
	}{
		{"still live", waxtap.ErrLiveNotStarted},
		{"removed-shaped", deadErr()},
		{"no audio yet", waxtap.ErrNoAudioFormats},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := channelFake(3)
			f.playlist.Entries[0].LiveStatus = waxtap.LiveNow // vid(3), at the top
			p, store, clock := pendingProvider(t, f, nil)
			ctx := context.Background()
			first, err := p.Enumerate(ctx, source.Request{URL: "u"})
			if err != nil {
				t.Fatal(err)
			}

			f.playlist.Entries[0].LiveStatus = waxtap.LiveNone
			f.infoErrs = map[string]error{vid(3): fmt.Errorf("enrich: %w", tc.err)}
			ended, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: first.ETag})
			if err != nil {
				t.Fatal(err)
			}
			if ended.Feed != nil && slices.Contains(episodeGUIDs(ended.Feed), vid(3)) {
				t.Fatalf("episodes = %v, want the stream left out until it is ready", episodeGUIDs(ended.Feed))
			}
			if held := heldIDs(t, store, clock); !slices.Equal(held, []string{vid(3)}) {
				t.Fatalf("held = %v, want the stream kept", held)
			}

			delete(f.infoErrs, vid(3))
			ready, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: ended.ETag})
			if err != nil {
				t.Fatal(err)
			}
			if ready.Feed == nil || !slices.Equal(episodeGUIDs(ready.Feed), []string{vid(3)}) {
				t.Errorf("poll once it is ready = %+v, want the stream", ready)
			}
		})
	}
}

// A settled verdict says the entry will never download here, whoever
// asks, so it is let go whether the listing or a lookup gives it.
func TestEnumerateLetsAHeldEntryGoOnASettledVerdict(t *testing.T) {
	settled := []struct {
		name string
		err  error
	}{
		{"members only", waxtap.ErrMembersOnly},
		{"geo blocked", waxtap.ErrGeoBlocked},
		{"age restricted", waxtap.ErrAgeRestricted},
		{"private", waxtap.ErrVideoRestricted},
	}
	for _, tc := range settled {
		t.Run("lookup, "+tc.name, func(t *testing.T) {
			f := channelFake(3)
			f.playlist.Entries[1].LiveStatus = waxtap.LiveNow // vid(2), below vid(3)
			p, store, clock := pendingProvider(t, f, nil)
			ctx := context.Background()
			first, err := p.Enumerate(ctx, source.Request{URL: "u"})
			if err != nil {
				t.Fatal(err)
			}
			f.infoErrs = map[string]error{vid(2): tc.err}
			if _, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: first.ETag}); err != nil {
				t.Fatal(err)
			}
			if held := heldIDs(t, store, clock); len(held) != 0 {
				t.Errorf("held = %v, want the entry let go", held)
			}
		})
	}
	t.Run("listing, members only", func(t *testing.T) {
		f := channelFake(3)
		f.playlist.Entries[0].LiveStatus = waxtap.LiveNow // vid(3), at the top
		p, store, clock := pendingProvider(t, f, nil)
		ctx := context.Background()
		first, err := p.Enumerate(ctx, source.Request{URL: "u"})
		if err != nil {
			t.Fatal(err)
		}
		f.playlist.Entries[0].LiveStatus = waxtap.LiveNone
		f.infoErrs = map[string]error{vid(3): fmt.Errorf("enrich: %w", waxtap.ErrMembersOnly)}
		if _, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: first.ETag}); err != nil {
			t.Fatal(err)
		}
		if held := heldIDs(t, store, clock); len(held) != 0 {
			t.Errorf("held = %v, want the entry let go", held)
		}
	})
}

// A held entry a full listing reaches past its enrichment budget is
// cataloged bare, which would leave it undated for good; it stays held,
// so the next poll looks it up and fills it in.
func TestEnumerateLooksUpAHeldEntryTheListingLeftBare(t *testing.T) {
	f := channelFake(30)
	p, store, clock := pendingProvider(t, f, nil)
	ctx := context.Background()
	if err := store.RememberYouTubePending(ctx, examplePlaylist, []string{vid(2)}, clock.UnixNano()); err != nil {
		t.Fatal(err)
	}
	full, err := p.Enumerate(ctx, source.Request{URL: "u"})
	if err != nil {
		t.Fatal(err)
	}
	var bare model.FeedEpisode
	for _, ep := range full.Feed.Episodes {
		if ep.GUID == vid(2) {
			bare = ep
		}
	}
	if bare.GUID == "" || bare.PubDateNS != 0 {
		t.Fatalf("held entry in the full listing = %+v, want it cataloged bare", bare)
	}

	next, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: full.ETag})
	if err != nil {
		t.Fatal(err)
	}
	if next.Feed == nil || !slices.Equal(episodeGUIDs(next.Feed), []string{vid(2)}) {
		t.Fatalf("next poll = %+v, want the bare entry again", next)
	}
	if ep := next.Feed.Episodes[0]; ep.PubDateNS == 0 || ep.Title != "full title "+vid(2) {
		t.Errorf("entry after its lookup = %+v, want it dated and titled", ep)
	}
}

// A subscribe or a re-add is an unconditional request, not a poll: it
// leaves the lookups to the polls, which auto-download what they add.
func TestEnumerateLeavesLookupsToThePolls(t *testing.T) {
	f := channelFake(3)
	p, store, clock := pendingProvider(t, f, nil)
	ctx := context.Background()
	if err := store.RememberYouTubePending(ctx, examplePlaylist, []string{"aired000001"}, clock.UnixNano()); err != nil {
		t.Fatal(err)
	}
	sub, err := p.Enumerate(ctx, source.Request{URL: "u"})
	if err != nil {
		t.Fatal(err)
	}
	if n := infoCallsFor(f, "aired000001"); n != 0 {
		t.Errorf("the subscribe looked the held entry up %d times", n)
	}

	poll, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: sub.ETag})
	if err != nil {
		t.Fatal(err)
	}
	if poll.Feed == nil || !slices.Equal(episodeGUIDs(poll.Feed), []string{"aired000001"}) {
		t.Errorf("first poll = %+v, want the held entry", poll)
	}
}

// A listing the throttle deferred says the session is being refused;
// lookups then would only be refused too, and spend what the next
// show's enrichment needs. They wait for a poll that was not.
func TestEnumerateSkipsLookupsAfterAThrottledListing(t *testing.T) {
	f := channelFake(3)
	p, store, clock := pendingProvider(t, f, nil)
	ctx := context.Background()
	if err := store.RememberYouTubePending(ctx, examplePlaylist, []string{"aired000001"}, clock.UnixNano()); err != nil {
		t.Fatal(err)
	}
	f.playlist.Entries = append([]waxtap.PlaylistEntry{{VideoID: vid(4), Title: "upload " + vid(4)}}, f.playlist.Entries...)
	f.infoErrs = map[string]error{vid(4): deferredErr()}
	throttled, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: vid(3)})
	if err != nil {
		t.Fatal(err)
	}
	if n := infoCallsFor(f, "aired000001"); n != 0 {
		t.Errorf("the held entry was looked up %d times after a throttled listing", n)
	}

	delete(f.infoErrs, vid(4))
	next, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: throttled.ETag})
	if err != nil {
		t.Fatal(err)
	}
	if next.Feed == nil || !slices.Equal(episodeGUIDs(next.Feed), []string{vid(4), "aired000001"}) {
		t.Errorf("next poll = %+v, want the upload and the held entry", next)
	}
}

// A lookup that cannot settle the entry leaves it held: still live,
// still upcoming, the throttle's removed-shaped refusal, and even a
// removal, which a recording still being processed can look like.
func TestEnumerateKeepsAnEntryALookupCannotSettle(t *testing.T) {
	for _, tc := range []struct {
		name string
		err  error
	}{
		{"live", waxtap.ErrLiveContent},
		{"upcoming", waxtap.ErrLiveNotStarted},
		{"throttled", provenUnplayableErr()},
		{"removed", deadErr()},
		{"no audio yet", waxtap.ErrNoAudioFormats},
		{"sign-in wall", waxtap.ErrLoginRequired},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := channelFake(3)
			f.playlist.Entries[1].LiveStatus = waxtap.LiveNow // vid(2)
			p, store, clock := pendingProvider(t, f, nil)
			ctx := context.Background()
			if _, err := p.Enumerate(ctx, source.Request{URL: "u"}); err != nil {
				t.Fatal(err)
			}

			f.infoErrs = map[string]error{vid(2): tc.err}
			enum, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: vid(3)})
			if err != nil {
				t.Fatalf("Enumerate = %v, want the refusal absorbed", err)
			}
			if !enum.NotModified {
				t.Errorf("enumeration = %+v, want NotModified", enum)
			}
			if n := infoCallsFor(f, vid(2)); n != 1 {
				t.Errorf("lookups = %d, want 1", n)
			}
			if held := heldIDs(t, store, clock); !slices.Equal(held, []string{vid(2)}) {
				t.Errorf("held = %v, want the entry kept", held)
			}
		})
	}
}

// Premieres are scheduled weeks out, so an entry is looked for over
// months; one first seen more than 90 days ago is let go unasked.
func TestEnumerateForgetsAPassedOverEntryAfterNinetyDays(t *testing.T) {
	f := channelFake(3)
	f.playlist.Entries[1].LiveStatus = waxtap.LiveUpcoming // vid(2)
	f.infoErrs = map[string]error{vid(2): waxtap.ErrLiveNotStarted}
	p, store, clock := pendingProvider(t, f, nil)
	ctx := context.Background()
	if _, err := p.Enumerate(ctx, source.Request{URL: "u"}); err != nil {
		t.Fatal(err)
	}

	*clock = clock.Add(89 * 24 * time.Hour)
	if _, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: vid(3)}); err != nil {
		t.Fatal(err)
	}
	if n := infoCallsFor(f, vid(2)); n != 1 {
		t.Fatalf("lookups at 89 days = %d, want 1", n)
	}

	*clock = clock.Add(2 * 24 * time.Hour)
	if _, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: vid(3)}); err != nil {
		t.Fatal(err)
	}
	if n := infoCallsFor(f, vid(2)); n != 1 {
		t.Errorf("lookups at 91 days = %d, want none after the first", n)
	}
	if held := heldIDs(t, store, clock); len(held) != 0 {
		t.Errorf("held = %v, want the entry forgotten", held)
	}
}

// A poll looks at five held entries at most, the ones looked at longest
// ago, so a handful that never resolve cannot starve the rest.
func TestEnumerateLooksAtFiveHeldEntriesPerPollInTurn(t *testing.T) {
	f := channelFake(1)
	f.infoErrs = map[string]error{}
	var held []string
	for i := 1; i <= 7; i++ {
		id := fmt.Sprintf("held%07d", i)
		held = append(held, id)
		f.infoErrs[id] = waxtap.ErrLiveContent
	}
	p, store, clock := pendingProvider(t, f, nil)
	ctx := context.Background()
	if err := store.RememberYouTubePending(ctx, examplePlaylist, held, clock.UnixNano()); err != nil {
		t.Fatal(err)
	}

	*clock = clock.Add(time.Hour)
	if _, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: vid(1)}); err != nil {
		t.Fatal(err)
	}
	if want := held[:5]; !slices.Equal(f.infoCalls, want) {
		t.Errorf("first poll looked at %v, want %v", f.infoCalls, want)
	}

	f.infoCalls = nil
	*clock = clock.Add(time.Hour)
	if _, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: vid(1)}); err != nil {
		t.Fatal(err)
	}
	if want := []string{held[5], held[6], held[0], held[1], held[2]}; !slices.Equal(f.infoCalls, want) {
		t.Errorf("second poll looked at %v, want %v", f.infoCalls, want)
	}
}

// An entry the listing catalogs with its video rides the same receipt
// as one a lookup found: held until the catalog's next cursor says it
// was written, and not looked up once it has.
func TestEnumerateLetsTheListingTakeAHeldEntry(t *testing.T) {
	f := channelFake(3)
	f.playlist.Entries[0].LiveStatus = waxtap.LiveUpcoming // vid(3), at the top
	p, store, clock := pendingProvider(t, f, nil)
	ctx := context.Background()
	first, err := p.Enumerate(ctx, source.Request{URL: "u"})
	if err != nil {
		t.Fatal(err)
	}
	if held := heldIDs(t, store, clock); !slices.Equal(held, []string{vid(3)}) {
		t.Fatalf("held = %v, want the premiere", held)
	}

	// It airs above the cursor, so the listing names it again.
	f.playlist.Entries[0].LiveStatus = waxtap.LiveNone
	aired, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: first.ETag})
	if err != nil {
		t.Fatal(err)
	}
	if got := episodeGUIDs(aired.Feed); !slices.Equal(got, []string{vid(3)}) {
		t.Fatalf("episodes = %v, want the premiere from the listing", got)
	}
	if held := heldIDs(t, store, clock); !slices.Equal(held, []string{vid(3)}) {
		t.Errorf("held = %v, want the premiere until the catalog has it", held)
	}

	f.infoCalls = nil
	after, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: aired.ETag})
	if err != nil {
		t.Fatal(err)
	}
	if !after.NotModified || len(f.infoCalls) != 0 {
		t.Errorf("next poll = %+v with lookups %v, want NotModified and none", after, f.infoCalls)
	}
	if held := heldIDs(t, store, clock); len(held) != 0 {
		t.Errorf("held = %v, want nothing once the receipt came back", held)
	}
}

// A rate limit is about the address, not the entry, and WaxTap has
// already waited it out once, so the poll stops looking and keeps
// everything it holds.
func TestEnumerateStopsLookingWhenRateLimited(t *testing.T) {
	f := channelFake(1)
	held := []string{"held0000001", "held0000002", "held0000003"}
	f.infoErrs = map[string]error{held[0]: fmt.Errorf("probe: %w", waxtap.ErrRateLimited)}
	p, store, clock := pendingProvider(t, f, nil)
	ctx := context.Background()
	if err := store.RememberYouTubePending(ctx, examplePlaylist, held, clock.UnixNano()); err != nil {
		t.Fatal(err)
	}

	*clock = clock.Add(time.Hour)
	enum, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: vid(1)})
	if err != nil {
		t.Fatalf("Enumerate = %v, want the rate limit absorbed", err)
	}
	if !enum.NotModified {
		t.Errorf("enumeration = %+v, want NotModified", enum)
	}
	if !slices.Equal(f.infoCalls, held[:1]) {
		t.Errorf("lookups = %v, want only %v", f.infoCalls, held[:1])
	}
	if got := heldIDs(t, store, clock); len(got) != 3 {
		t.Errorf("held = %v, want all three kept", got)
	}

	// The refused lookup counts as a look, so the next poll starts past it.
	for _, id := range held {
		f.infoErrs[id] = waxtap.ErrLiveContent
	}
	f.infoCalls = nil
	*clock = clock.Add(time.Hour)
	if _, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: vid(1)}); err != nil {
		t.Fatal(err)
	}
	if want := []string{held[1], held[2], held[0]}; !slices.Equal(f.infoCalls, want) {
		t.Errorf("next poll looked at %v, want %v", f.infoCalls, want)
	}
}

// The lookup asks for what the listing's enrichment asks for, so the
// episode carries its publish date: the show lists, and retention keeps,
// episodes by date, and an undated one sorts last.
func TestEnumerateLooksAHeldEntryUpInFull(t *testing.T) {
	f := channelFake(3)
	f.playlist.Entries[1].LiveStatus = waxtap.LiveUpcoming // vid(2)
	p, _, _ := pendingProvider(t, f, nil)
	ctx := context.Background()
	if _, err := p.Enumerate(ctx, source.Request{URL: "u"}); err != nil {
		t.Fatal(err)
	}
	f.infoCalls, f.infoOpts = nil, nil
	if _, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: vid(3)}); err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(f.infoCalls, []string{vid(2)}) {
		t.Fatalf("lookups = %v, want the held entry", f.infoCalls)
	}
	if f.infoOpts[0] != len(f.lastEnum.EnrichOptions) {
		t.Errorf("lookup carried %d read options, want the enrichment's %d", f.infoOpts[0], len(f.lastEnum.EnrichOptions))
	}
}

// Acquiring a channel is a one-shot read: it must not hand a held
// premiere to a download and forget it before the subscription sees
// it, nor hold entries for a listing nobody polls.
func TestEnumerateOnceLeavesTheHeldEntriesAlone(t *testing.T) {
	f := channelFake(3)
	f.playlist.Entries[1].LiveStatus = waxtap.LiveNow // vid(2)
	p, store, clock := pendingProvider(t, f, nil)
	ctx := context.Background()
	if err := store.RememberYouTubePending(ctx, examplePlaylist, []string{"aired000001"}, clock.UnixNano()); err != nil {
		t.Fatal(err)
	}

	once, err := p.EnumerateOnce(ctx, source.Request{URL: "u"})
	if err != nil {
		t.Fatal(err)
	}
	if got, want := episodeGUIDs(once.Feed), []string{vid(3), vid(1)}; !slices.Equal(got, want) {
		t.Errorf("episodes = %v, want %v", got, want)
	}
	if n := infoCallsFor(f, "aired000001"); n != 0 {
		t.Errorf("the held entry was looked up %d times", n)
	}
	if held := heldIDs(t, store, clock); !slices.Equal(held, []string{"aired000001"}) {
		t.Errorf("held = %v, want only the subscription's entry", held)
	}

	sub, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: vid(3)})
	if err != nil {
		t.Fatal(err)
	}
	if sub.Feed == nil {
		t.Fatalf("subscription poll = %+v, want a feed", sub)
	}
	if got := episodeGUIDs(sub.Feed); !slices.Equal(got, []string{"aired000001"}) {
		t.Errorf("subscription poll episodes = %v, want the held entry", got)
	}
}

// The second look is best effort: a store that fails is logged, and the
// listing's own episodes still reach the catalog.
func TestEnumerateCatalogsTheListingWhenTheStoreFails(t *testing.T) {
	f := channelFake(3)
	f.playlist.Entries[1].LiveStatus = waxtap.LiveNow // vid(2)
	var logs bytes.Buffer
	p, store, _ := pendingProvider(t, f, &logs)
	store.Close()

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u"})
	if err != nil {
		t.Fatalf("Enumerate = %v, want the store's failure absorbed", err)
	}
	if got, want := episodeGUIDs(enum.Feed), []string{vid(3), vid(1)}; !slices.Equal(got, want) {
		t.Errorf("episodes = %v, want %v", got, want)
	}
	if !strings.Contains(logs.String(), "level=WARN") {
		t.Errorf("the store's failure was not logged:\n%s", logs.String())
	}
}

// A sync being torn down stops looking rather than spending lookups
// whose answers nothing will write, whether the cancel lands before the
// second look or between two of its lookups.
func TestEnumerateStopsLookingWhenTheSyncIsCanceled(t *testing.T) {
	held := []string{"aired000001", "aired000002"}
	for _, tc := range []struct {
		name     string
		cancelAt string // the lookup that cancels; "" cancels up front
		want     []string
	}{
		{name: "before the look", want: nil},
		{name: "between lookups", cancelAt: held[0], want: held[:1]},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := channelFake(1)
			p, store, clock := pendingProvider(t, f, nil)
			if err := store.RememberYouTubePending(context.Background(), examplePlaylist, held, clock.UnixNano()); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithCancel(context.Background())
			defer cancel()
			if tc.cancelAt == "" {
				cancel()
			}
			f.beforeInfo = func(id string) {
				if id == tc.cancelAt {
					cancel()
				}
			}

			if _, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: vid(1)}); !errors.Is(err, context.Canceled) {
				t.Errorf("Enumerate = %v, want context.Canceled", err)
			}
			if !slices.Equal(f.infoCalls, tc.want) {
				t.Errorf("lookups = %v, want %v", f.infoCalls, tc.want)
			}
		})
	}
}

// contractViolation names what an answer does that source.Provider's
// Enumerate rules out, which the catalog refuses as a failed sync.
func contractViolation(req source.Request, enum *source.Enumeration) string {
	switch {
	case enum == nil:
		return "a nil enumeration with a nil error"
	case enum.NotModified && enum.Feed != nil:
		return "not-modified with a feed"
	case !enum.NotModified && enum.Feed == nil:
		return "neither a feed nor not-modified"
	case enum.NotModified && req.ETag == "" && req.LastModified == "":
		return "not-modified to a request with no cursor"
	}
	return ""
}

func TestEnumerateAnswersOnlyWhatTheContractAllows(t *testing.T) {
	premieres := func() *fakeTap {
		f := channelFake(2)
		for i := range f.playlist.Entries {
			f.playlist.Entries[i].LiveStatus = waxtap.LiveUpcoming
		}
		return f
	}
	uploads := func(n int) func() *fakeTap { return func() *fakeTap { return channelFake(n) } }
	for _, c := range []struct {
		name string
		fake func() *fakeTap
		etag string
	}{
		{"a first sync", uploads(3), ""},
		{"a first sync of an empty channel", uploads(0), ""},
		{"a first sync of nothing but premieres", premieres, ""},
		{"a receipt with no listing cursor", uploads(0), "@7"},
		{"an unchanged channel", uploads(3), vid(3)},
	} {
		for _, second := range []bool{false, true} {
			var p *Provider
			if second {
				p, _, _ = pendingProvider(t, c.fake(), nil)
			} else {
				p = testProvider(t, c.fake(), nil)
			}
			req := source.Request{URL: "u", ETag: c.etag}
			enum, err := p.Enumerate(context.Background(), req)
			if err != nil {
				t.Fatalf("%s: %v", c.name, err)
			}
			if v := contractViolation(req, enum); v != "" {
				t.Errorf("%s (second look %v): %s", c.name, second, v)
			}
		}
	}
}

// A failure reaches the catalog classed as the source's, which is how a
// sync tells it from the catalog's own, cause kept; a canceled one stays so.
func TestAFailedListingIsClassedTheSources(t *testing.T) {
	boom := errors.New("youtube answered 503")
	f := channelFake(2)
	f.enumErr = boom
	p := testProvider(t, f, nil)
	for name, call := range map[string]func(context.Context) error{
		"a poll": func(ctx context.Context) error {
			_, err := p.Enumerate(ctx, source.Request{URL: "u", ETag: vid(1)})
			return err
		},
		"a resolve": func(ctx context.Context) error { _, err := p.Resolve(ctx, source.Request{URL: "u"}); return err },
	} {
		err := call(context.Background())
		if catalogerr.CodeOf(err) != catalogerr.CodeIO || !errors.Is(err, boom) {
			t.Errorf("%s failed with %v (class %q), want the cause classed io", name, err, catalogerr.CodeOf(err))
		}
		ctx, cancel := context.WithCancel(context.Background())
		cancel()
		f.enumErr = context.Canceled
		if err := call(ctx); catalogerr.CodeOf(err) != catalogerr.CodeCanceled {
			t.Errorf("%s canceled failed with %v (class %q), want canceled", name, err, catalogerr.CodeOf(err))
		}
		f.enumErr = boom
	}
}

// Only a live entry is new, so the feed is unchanged: the answer is
// NotModified rather than an empty feed written every poll.
func TestEnumerateHoldsTheCursorUnderOnlyLiveEntries(t *testing.T) {
	f := channelFake(4)
	f.playlist.Entries[0].LiveStatus = waxtap.LiveNow // vid(4)
	p := testProvider(t, f, nil)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u", ETag: vid(3)})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if !enum.NotModified || enum.Feed != nil {
		t.Errorf("enumeration = %+v, want NotModified", enum)
	}
	if enum.ETag != vid(3) {
		t.Errorf("ETag = %q, want the incoming cursor %q held", enum.ETag, vid(3))
	}
}

// The wholesale rule counts what WaxTap reports it attempted, not a copy
// of its selection rule: five refusals are the whole pass when only five
// entries were asked about.
func TestEnrichFailuresCountsWhatThePassAttempted(t *testing.T) {
	pl := &waxtap.Playlist{}
	for i := range 10 {
		pl.Entries = append(pl.Entries, waxtap.PlaylistEntry{VideoID: vid(i), Index: i})
	}
	for i := range 5 {
		pl.Errors = append(pl.Errors, &waxtap.EnrichError{VideoID: vid(i), Index: i, Err: provenUnplayableErr()})
	}
	p := testProvider(t, channelFake(1), nil)
	if _, wholesale := p.enrichFailures(pl); !wholesale {
		t.Error("five refusals out of five attempts did not read as a refused pass")
	}
}

// A live entry is not one the budget reached, so it cannot mask a wholly
// refused pass.
func TestEnumerateKeepsAWhollyRefusedPassBesideALiveEntry(t *testing.T) {
	f := channelFake(6)
	f.playlist.Entries[0].LiveStatus = waxtap.LiveNow // vid(6)
	f.infoErrs = map[string]error{}
	for i := 5; i >= 1; i-- {
		f.infoErrs[vid(i)] = provenUnplayableErr()
	}
	p := testProvider(t, f, nil)

	enum, err := p.Enumerate(context.Background(), source.Request{URL: "u"})
	if err != nil {
		t.Fatalf("Enumerate: %v", err)
	}
	if len(enum.Feed.Episodes) != 5 {
		t.Fatalf("episodes = %v, want the five refused entries kept", episodeGUIDs(enum.Feed))
	}
	if enum.ETag != "" {
		t.Errorf("ETag = %q, want the cursor held", enum.ETag)
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
		{Code: waxtap.WarnInputNote, Detail: "ignored a data stream"},
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
		`code=input-note`,
	} {
		if !strings.Contains(logs.String(), want) {
			t.Errorf("missing %q in logs:\n%s", want, logs.String())
		}
	}
	// A remark about a well-formed file is not a degraded delivery.
	for _, line := range strings.Split(logs.String(), "\n") {
		if strings.Contains(line, "code=input-note") && !strings.Contains(line, "level=INFO") {
			t.Errorf("input note logged as degraded: %s", line)
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

// TestWaxBinCatalogsAPremiereAfterItAirs is the catalog's half of the
// second look: a feed that carries only the premiere, under a cursor that
// did not move, is written like any other, and the cursor stored with it
// lets the premiere go on the next sync.
func TestWaxBinCatalogsAPremiereAfterItAirs(t *testing.T) {
	ctx := context.Background()
	f := channelFake(3)
	for _, v := range f.infos {
		v.Thumbnails = nil // keeps the catalog off the network
	}
	f.playlist.Entries[1].LiveStatus = waxtap.LiveUpcoming // vid(2)
	f.infoErrs = map[string]error{vid(2): waxtap.ErrLiveNotStarted}
	p, store, clock := pendingProvider(t, f, nil)

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
	if res, err := lib.Podcasts().Sync(ctx, pod.PID); err != nil || res.EpisodesAdded != 0 {
		t.Fatalf("sync while upcoming = (%+v, %v), want nothing added", res, err)
	}

	delete(f.infoErrs, vid(2))
	res, err := lib.Podcasts().Sync(ctx, pod.PID)
	if err != nil {
		t.Fatalf("Sync: %v", err)
	}
	if res.EpisodesAdded != 1 {
		t.Errorf("episodes added = %d, want the premiere", res.EpisodesAdded)
	}
	eps, err := lib.Podcasts().Episodes(ctx, pod.PID, 0)
	if err != nil {
		t.Fatal(err)
	}
	titles := map[string]string{}
	for _, ep := range eps {
		titles[ep.GUID] = ep.Title
	}
	if got := titles[vid(2)]; got != "full title "+vid(2) {
		t.Errorf("premiere title = %q, want the enriched one (episodes %v)", got, titles)
	}
	after, err := lib.Podcasts().Get(ctx, pod.PID)
	if err != nil {
		t.Fatal(err)
	}
	if after.Title != "Example Uploads" {
		t.Errorf("show title = %q, want the channel's", after.Title)
	}
	if held := heldIDs(t, store, clock); !slices.Equal(held, []string{vid(2)}) {
		t.Fatalf("held = %v, want the premiere until the catalog's cursor confirms it", held)
	}

	res, err = lib.Podcasts().Sync(ctx, pod.PID)
	if err != nil || res.EpisodesAdded != 0 || res.EpisodesUpdated != 0 {
		t.Errorf("next sync = (%+v, %v), want nothing touched", res, err)
	}
	if held := heldIDs(t, store, clock); len(held) != 0 {
		t.Errorf("held = %v, want nothing once the catalog had it", held)
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
