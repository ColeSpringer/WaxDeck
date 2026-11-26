package service

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"maps"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"
	catalogerr "github.com/colespringer/waxbin/waxerr"
	waxtap "github.com/colespringer/waxtap/v3"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/stubsource"
	"github.com/colespringer/waxdeck/server/internal/syncsource"
	"github.com/colespringer/waxdeck/server/internal/waxtapsource"
)

// The capability is matched by method alone, so a rename on the provider
// would quietly send acquisitions back through the subscription's poll.
var _ onceEnumerator = (*waxtapsource.Provider)(nil)

// So is the check before queuing.
var (
	_ acquireProber = (*waxtapsource.Provider)(nil)
	_ acquireProber = (*stubsource.Provider)(nil)
)

// onceSource answers its subscription listing and its one-shot listing
// with different entries, so a test can tell which one was read.
type onceSource struct{}

func (onceSource) SourceType() model.SourceType { return model.SourceYouTube }

func (onceSource) Resolve(context.Context, source.Request) (*source.Resolved, error) {
	return nil, errors.New("not used")
}

func (onceSource) Enumerate(context.Context, source.Request) (*source.Enumeration, error) {
	return listingOf("subscription poll"), nil
}

func (onceSource) EnumerateOnce(context.Context, source.Request, syncsource.EnumerateOptions) (*source.Enumeration, error) {
	return listingOf("one-shot read"), nil
}

func (onceSource) Fetch(context.Context, source.FetchRequest, io.Writer) (*source.FetchResult, error) {
	return nil, errors.New("not used")
}

func (onceSource) LinkShape(rawURL string, wantPlaylist bool) (string, error) {
	return linkShapeOf(rawURL, wantPlaylist)
}

func (onceSource) Probe(_ context.Context, rawURL string, wantPlaylist bool) (syncsource.AcquireTarget, error) {
	shape, err := linkShapeOf(rawURL, wantPlaylist)
	return syncsource.AcquireTarget{Shape: shape}, err
}

// linkShapeOf decides a link's shape from the link alone, as the bridges
// do: a video id is the video unless the list it also names is asked for.
func linkShapeOf(rawURL string, wantPlaylist bool) (string, error) {
	u, err := url.Parse(rawURL)
	if err != nil {
		return "", &syncsource.Refusal{Reason: syncsource.ReasonUnsupportedURL, Err: err}
	}
	video := u.Query().Get("v") != "" || u.Host == "youtu.be"
	list := u.Query().Get("list") != ""
	switch {
	case video && list && wantPlaylist:
		return syncsource.ShapePlaylist, nil
	case video:
		return syncsource.ShapeVideo, nil
	case list:
		return syncsource.ShapePlaylist, nil
	case strings.HasPrefix(u.Path, "/@") || strings.HasPrefix(u.Path, "/channel/"):
		return syncsource.ShapeChannel, nil
	}
	return "", &syncsource.Refusal{Reason: syncsource.ReasonUnsupportedURL}
}

// unprobedSource is a provider that cannot check a link.
type unprobedSource struct{ inner onceSource }

func (s unprobedSource) SourceType() model.SourceType { return s.inner.SourceType() }

func (s unprobedSource) Resolve(ctx context.Context, req source.Request) (*source.Resolved, error) {
	return s.inner.Resolve(ctx, req)
}

func (s unprobedSource) Enumerate(ctx context.Context, req source.Request) (*source.Enumeration, error) {
	return s.inner.Enumerate(ctx, req)
}

func (s unprobedSource) Fetch(ctx context.Context, req source.FetchRequest, w io.Writer) (*source.FetchResult, error) {
	return s.inner.Fetch(ctx, req, w)
}

func listingOf(title string) *source.Enumeration {
	return &source.Enumeration{Feed: &model.Feed{Episodes: []model.FeedEpisode{
		{Title: title, EnclosureURL: "https://tube.example/watch?v=one"},
	}}}
}

// Acquiring a channel is a one-shot read, so it takes the listing that
// leaves a subscription's state alone where the provider offers one: the
// YouTube poll's listing can hand over, and forget, a premiere the
// subscription is waiting on.
func TestAcquisitionReadsTheOneShotListing(t *testing.T) {
	l := bareLibrary(&core{})
	l.Ingest.sourceProviders = []source.Provider{onceSource{}}
	_, items, _, _, err := l.Ingest.acquireList(context.Background(), "", toolTaskParams{URL: "https://tube.example/@channel", Shape: syncsource.ShapeChannel})
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 1 || items[0].Title != "one-shot read" {
		t.Errorf("items = %+v, want the one-shot read's entry", items)
	}
}

// countedSource counts the listings asked of it.
type countedSource struct {
	onceSource
	listed *atomic.Int32
}

func (s countedSource) EnumerateOnce(ctx context.Context, req source.Request, opts syncsource.EnumerateOptions) (*source.Enumeration, error) {
	s.listed.Add(1)
	return s.onceSource.EnumerateOnce(ctx, req, opts)
}

// An acquisition queued by an account that can no longer sign in, or
// that is gone, fails for good before anything is asked of the source.
func TestAnAcquisitionAsksNothingForAnAccountThatCannotSignIn(t *testing.T) {
	t.Parallel()
	var listed atomic.Int32
	ctx, svc, _ := newCatalogFixtureWith(t, catalogFixtureOptions{sources: []source.Provider{countedSource{listed: &listed}}})
	acct, _ := memberAs(t, ctx, svc, AccountCreate{Username: "digger", UploadEnabled: true})
	off := true
	if _, err := svc.Identity.UpdateAccount(ctx, acct.User.ID, AccountUpdate{Disabled: &off}); err != nil {
		t.Fatal(err)
	}
	for who, id := range map[string]string{"disabled": acct.User.ID, "deleted": "us-nobody"} {
		_, err := svc.Ingest.runAcquire(ctx, &wdb.ToolTask{UserID: id}, toolTaskParams{URL: "https://tube.example/@channel"})
		if !permanentToolErr(err) {
			t.Errorf("an acquisition for a %s account = %v, want a failure no retry is owed", who, err)
		}
	}
	if n := listed.Load(); n != 0 {
		t.Errorf("the source was listed %d times for accounts that cannot sign in", n)
	}
}

// A failed read of the account says nothing about it. A run cut off
// there, as by the server stopping, is left to run again rather than
// failed for good as an account that is gone.
func TestAnAcquisitionRunsAgainAfterAFailedAccountRead(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	stopping, stop := context.WithCancel(ctx)
	stop()
	_, err := svc.Ingest.runAcquire(stopping, &wdb.ToolTask{UserID: admin.ID}, toolTaskParams{URL: "https://tube.example/@channel"})
	if err == nil {
		t.Fatal("an acquisition whose account could not be read finished clean")
	}
	if permanentToolErr(err) {
		t.Fatalf("a failed read of the account = %v, which fails the task for good", err)
	}
}

// probeSource checks a link the way the bridges do: a link naming both a
// video and a list is the video unless the list is asked for. It records
// what the check and the run then ask of it.
type probeSource struct {
	onceSource
	// err is what the check answers; block holds the check until its
	// context ends, and probing is closed as it starts to.
	err     error
	block   bool
	probing chan struct{}
	// listErr fails the run's listing.
	listErr error
	// host, when set, is the only host whose links the source reads.
	host string
	// fetchErr, when set, is what every fetch answers.
	fetchErr error

	mu      sync.Mutex
	probes  []bool
	listed  []string
	fetched []string
}

var _ acquireProber = (*probeSource)(nil)

func (s *probeSource) Probe(ctx context.Context, url string, wantPlaylist bool) (syncsource.AcquireTarget, error) {
	s.mu.Lock()
	s.probes = append(s.probes, wantPlaylist)
	s.mu.Unlock()
	target := syncsource.AcquireTarget{Shape: syncsource.ShapeVideo, Title: "One Video"}
	if wantPlaylist {
		target = syncsource.AcquireTarget{Shape: syncsource.ShapePlaylist, Title: "The List"}
	}
	if s.block {
		if s.probing != nil {
			close(s.probing)
		}
		<-ctx.Done()
		return target, catalogerr.FromContext("probe", ctx.Err(), catalogerr.CodeCanceled)
	}
	return target, s.err
}

func (s *probeSource) LinkShape(rawURL string, wantPlaylist bool) (string, error) {
	if u, err := url.Parse(rawURL); s.host != "" && (err != nil || u.Host != s.host) {
		return "", &syncsource.Refusal{Reason: syncsource.ReasonUnsupportedURL}
	}
	return linkShapeOf(rawURL, wantPlaylist)
}

func (s *probeSource) EnumerateOnce(_ context.Context, req source.Request, _ syncsource.EnumerateOptions) (*source.Enumeration, error) {
	s.mu.Lock()
	s.listed = append(s.listed, req.URL)
	s.mu.Unlock()
	if s.listErr != nil {
		return nil, s.listErr
	}
	return &source.Enumeration{Feed: &model.Feed{Title: "The List", Episodes: []model.FeedEpisode{
		{GUID: "one", Title: "first", EnclosureURL: "https://tube.example/watch?v=one"},
		{GUID: "two", Title: "second", EnclosureURL: "https://tube.example/watch?v=two"},
	}}}, nil
}

func (s *probeSource) Fetch(_ context.Context, req source.FetchRequest, _ io.Writer) (*source.FetchResult, error) {
	s.mu.Lock()
	s.fetched = append(s.fetched, req.URL)
	s.mu.Unlock()
	if s.fetchErr != nil {
		return nil, s.fetchErr
	}
	return nil, errors.New("no bytes here")
}

func (s *probeSource) calls() (probes []bool, listed, fetched []string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return slices.Clone(s.probes), slices.Clone(s.listed), slices.Clone(s.fetched)
}

// acquireFixture is a server with a managed library and src as its one
// acquisition source, and an account that may upload.
func acquireFixture(t *testing.T, src source.Provider, opts ...func(*Config)) (context.Context, *Library, *UserCtx) {
	t.Helper()
	ctx, svc, uc := managedUploadFixtureWith(t, func(cfg *Config) {
		cfg.SourceProviders = []source.Provider{src}
		cfg.AllowPrivateFeedHosts = true
		for _, o := range opts {
			o(cfg)
		}
	})
	uc.UploadEnabled = true
	return ctx, svc, uc
}

func queuedTasks(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) []ToolTaskDTO {
	t.Helper()
	tasks, _, err := svc.Tools.ListToolTasksFor(ctx, uc, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	return tasks
}

// Each verdict the source can give about a link refuses it at once, with
// the reason a client words, and queues nothing.
func TestEachSourceVerdictRefusesTheAcquisition(t *testing.T) {
	t.Parallel()
	asSource := func(err error) error { return catalogerr.Wrap(catalogerr.CodeIO, "probe", err) }
	for _, tc := range []struct {
		err    error
		reason string
	}{
		{&waxtap.PlaylistUnavailableError{Reason: "This playlist is private."}, "playlist-unavailable"},
		{fmt.Errorf("%w: HTTP 404", waxtap.ErrPlaylistUnavailable), "playlist-unavailable"},
		{waxtap.ErrPlaylistEmpty, "playlist-empty"},
		{&waxtap.PlayabilityError{Status: "LOGIN_REQUIRED", Reason: "This video is private", Sentinel: waxtap.ErrVideoRestricted}, "video-private"},
		{waxtap.ErrVideoUnavailable, "video-unavailable"},
		{waxtap.ErrAgeRestricted, "age-restricted"},
		{waxtap.ErrGeoBlocked, "region-blocked"},
		{waxtap.ErrMembersOnly, "members-only"},
		{waxtap.ErrLiveContent, "live"},
		{waxtap.ErrLiveNotStarted, "not-started"},
		{waxtap.ErrNoAudioFormats, "no-audio"},
		{waxtap.ErrShortsPlaylist, "unsupported-url"},
		{waxtap.ErrInvalidPlaylistID, "unsupported-url"},
		{&syncsource.Refusal{Reason: syncsource.ReasonUnsupportedURL}, "unsupported-url"},
		{&syncsource.Refusal{Reason: "playlist-unavailable"}, "playlist-unavailable"},
	} {
		t.Run(tc.reason+"/"+tc.err.Error(), func(t *testing.T) {
			t.Parallel()
			src := &probeSource{err: asSource(tc.err)}
			ctx, svc, uc := acquireFixture(t, src)
			_, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/watch?v=one", false, "music", "", "", nil, nil)
			if KindOf(err) != KindRefused {
				t.Fatalf("acquisition = %v (%s), want source-refused", err, KindOf(err))
			}
			if got := RefusalParams(err)["reason"]; got != tc.reason {
				t.Errorf("reason = %q, want %q", got, tc.reason)
			}
			if msg := err.Error(); msg == "" || strings.Contains(msg, "waxtap") {
				t.Errorf("refusal says %q, want a sentence of the server's own", msg)
			}
			if tasks := queuedTasks(t, ctx, svc, uc); len(tasks) != 0 {
				t.Errorf("a refused link queued %d tasks", len(tasks))
			}
		})
	}
}

// A check that reaches no verdict, the source throttling, the bridge in
// need of mending, the network failing, queues the task anyway: its run
// asks again.
func TestACheckWithoutAVerdictQueues(t *testing.T) {
	t.Parallel()
	for name, err := range map[string]error{
		"rate limited": &waxtap.RateLimitError{RetryAfter: time.Minute, StatusCode: 429},
		"throttled": fmt.Errorf("%w: %w", waxtap.ErrTemporarilyUnavailable, &waxtap.PlayabilityError{
			Status: "UNPLAYABLE", Reason: "Video unavailable", Sentinel: waxtap.ErrVideoUnavailable,
		}),
		"sign-in wall":   &waxtap.PlayabilityError{Status: "LOGIN_REQUIRED", Sentinel: waxtap.ErrLoginRequired},
		"damaged media":  waxtap.ErrUnsupportedInput,
		"extraction":     &waxtap.ExtractionError{Stage: "player-response", Cause: errors.New("bad json")},
		"po token":       waxtap.ErrNeedsPOToken,
		"cipher":         waxtap.ErrCipherSolve,
		"transport":      &net.OpError{Op: "dial", Err: errors.New("connection refused")},
		"something else": errors.New("the bridge said something new"),
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			src := &probeSource{err: catalogerr.Wrap(catalogerr.CodeIO, "probe", err)}
			ctx, svc, uc := acquireFixture(t, src)
			if _, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/watch?v=one", false, "music", "", "", nil, nil); err != nil {
				t.Fatalf("acquisition = %v, want it queued", err)
			}
			if tasks := queuedTasks(t, ctx, svc, uc); len(tasks) != 1 {
				t.Errorf("queued %d tasks, want 1", len(tasks))
			}
		})
	}
}

// A check that runs out of time is no verdict either.
func TestACheckThatRunsOutOfTimeQueues(t *testing.T) {
	t.Parallel()
	src := &probeSource{block: true}
	ctx, svc, uc := acquireFixture(t, src)
	svc.Ingest.acquireProbeBudget = 50 * time.Millisecond
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/watch?v=one", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatalf("acquisition = %v, want it queued", err)
	}
	if task.State != taskStateQueued {
		t.Errorf("task = %+v, want it queued", task)
	}
}

// A client that goes away while the link is being checked queues nothing.
func TestAnAcquisitionCanceledWhileCheckedQueuesNothing(t *testing.T) {
	t.Parallel()
	src := &probeSource{block: true, probing: make(chan struct{})}
	ctx, svc, uc := acquireFixture(t, src)
	req, cancel := context.WithCancel(ctx)
	go func() {
		<-src.probing
		cancel()
	}()
	_, err := svc.Ingest.StartAcquisition(req, uc, "https://tube.example/watch?v=one", false, "music", "", "", nil, nil)
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("acquisition = %v, want the request's cancellation", err)
	}
	if tasks := queuedTasks(t, ctx, svc, uc); len(tasks) != 0 {
		t.Errorf("a canceled request queued %d tasks", len(tasks))
	}
}

// runQueued runs the one queued acquisition as the worker would.
func runQueued(t *testing.T, ctx context.Context, svc *Library, id string) error {
	t.Helper()
	row, err := svc.db.ToolTaskByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	var p toolTaskParams
	if err := json.Unmarshal([]byte(row.Params), &p); err != nil {
		t.Fatal(err)
	}
	_, err = svc.Ingest.runAcquire(ctx, &row, p)
	return err
}

// A link naming a video inside a list downloads the video, and only the
// list when the request asks for it; the run takes the path the check
// decided.
func TestALinkNamingAVideoAndAListTakesThePathAskedFor(t *testing.T) {
	t.Parallel()
	const link = "https://tube.example/watch?v=one&list=PLmix"
	for _, wantList := range []bool{false, true} {
		t.Run(fmt.Sprint("playlist=", wantList), func(t *testing.T) {
			t.Parallel()
			src := &probeSource{}
			ctx, svc, uc := acquireFixture(t, src)
			task, err := svc.Ingest.StartAcquisition(ctx, uc, link, wantList, "music", "", "", nil, nil)
			if err != nil {
				t.Fatal(err)
			}
			_ = runQueued(t, ctx, svc, task.ID)
			probes, listed, fetched := src.calls()
			if !slices.Equal(probes, []bool{wantList}) {
				t.Errorf("checks = %v, want one asking playlist=%v", probes, wantList)
			}
			if !wantList {
				if len(listed) != 0 || !slices.Equal(fetched, []string{link}) {
					t.Errorf("listed %v and fetched %v, want the one video fetched and nothing listed", listed, fetched)
				}
				return
			}
			if !slices.Equal(listed, []string{link}) || len(fetched) == 0 || fetched[0] != "https://tube.example/watch?v=one" {
				t.Errorf("listed %v and fetched %v, want the list read and its entries fetched", listed, fetched)
			}
		})
	}
}

// A list the source will not read is the answer: the run never fetches
// the link as a single item instead.
func TestAFailedListReadIsTheAnswer(t *testing.T) {
	t.Parallel()
	src := &probeSource{listErr: catalogerr.Wrap(catalogerr.CodeIO, "list", &waxtap.PlaylistUnavailableError{Reason: "This playlist is private."})}
	ctx, svc, uc := acquireFixture(t, src)
	// The check gave no verdict, so the task queued and the run meets it.
	src.err = waxtap.ErrRateLimited
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLmix", true, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	err = runQueued(t, ctx, svc, task.ID)
	if !errors.Is(err, waxtap.ErrPlaylistUnavailable) {
		t.Errorf("run = %v, want the list's own refusal", err)
	}
	if _, _, fetched := src.calls(); len(fetched) != 0 {
		t.Errorf("fetched %v after the list read failed", fetched)
	}
}

// The links a user pastes that are not a plain video or list are refused
// in words or queued, never a server fault: a video inside a list is the
// video, a page that names neither is not the source's, and a Shorts shelf
// is a list the source will not read.
func TestOddLinksRefuseInWordsOrQueue(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		link   string
		probe  error
		reason string
	}{
		{"https://youtu.be/dQw4w9WgXcQ?list=PLmix", nil, ""},
		{"https://example.com/some/page", nil, "unsupported-url"},
		{"https://www.youtube.com/playlist?list=UUSH0123456789012345678901", waxtap.ErrShortsPlaylist, "unsupported-url"},
	} {
		t.Run(tc.link, func(t *testing.T) {
			t.Parallel()
			src := &probeSource{err: tc.probe}
			ctx, svc, uc := acquireFixture(t, src)
			_, err := svc.Ingest.StartAcquisition(ctx, uc, tc.link, false, "music", "", "", nil, nil)
			if tc.reason == "" {
				if err != nil || len(queuedTasks(t, ctx, svc, uc)) != 1 {
					t.Fatalf("acquisition = %v, want it queued", err)
				}
				return
			}
			if KindOf(err) != KindRefused || RefusalParams(err)["reason"] != tc.reason {
				t.Errorf("acquisition = %v (%s, %v), want source-refused for %s", err, KindOf(err), RefusalParams(err), tc.reason)
			}
		})
	}
}

// Every acquisition source checks a link before it is queued: a server
// whose only source cannot is running none to acquire with.
func TestASourceThatCannotCheckALinkAcquiresNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := acquireFixture(t, unprobedSource{})
	_, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLmix", false, "music", "", "", nil, nil)
	if KindOf(err) != KindUnsupported {
		t.Fatalf("acquisition = %v (%s), want source-unavailable", err, KindOf(err))
	}
}

// The run fetches through the source that reads the link, as the check
// chose it, never the first source running.
func TestTheRunFetchesThroughTheSourceThatOwnsTheLink(t *testing.T) {
	t.Parallel()
	tube, stub := &probeSource{host: "tube.example"}, &probeSource{host: "stub.example"}
	ctx, svc, uc := managedUploadFixtureWith(t, func(cfg *Config) {
		cfg.SourceProviders = []source.Provider{tube, stub}
		cfg.AllowPrivateFeedHosts = true
	})
	uc.UploadEnabled = true
	const link = "https://stub.example/watch?v=one"
	task, err := svc.Ingest.StartAcquisition(ctx, uc, link, false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	_ = runQueued(t, ctx, svc, task.ID)
	tubeProbes, _, tubeFetched := tube.calls()
	_, _, stubFetched := stub.calls()
	if len(tubeProbes) != 0 || len(tubeFetched) != 0 || !slices.Equal(stubFetched, []string{link}) {
		t.Errorf("tube checked %v and fetched %v, stub fetched %v; want only the stub asked", tubeProbes, tubeFetched, stubFetched)
	}
}

// What WaxTap says may pass reads so before any availability sentinel it
// wraps, a sign-in wall waits as a private video does not, and a damaged
// download is no verdict about the link.
func TestTheClassifierReadsWhatMayPassFirst(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name      string
		err       error
		reason    string
		permanent bool
	}{
		{"budget ran out", fmt.Errorf("%w: %w", waxtap.ErrTemporarilyUnavailable, &waxtap.PlayabilityError{
			Status: "UNPLAYABLE", Reason: "Video unavailable", Sentinel: waxtap.ErrVideoUnavailable,
		}), reasonRateLimited, false},
		{"sign-in wall", &waxtap.PlayabilityError{Status: "LOGIN_REQUIRED", Sentinel: waxtap.ErrLoginRequired}, reasonVideoPrivate, false},
		{"private", &waxtap.PlayabilityError{Status: "LOGIN_REQUIRED", Reason: "This video is private", Sentinel: waxtap.ErrVideoRestricted}, reasonVideoPrivate, true},
		{"shorts shelf", waxtap.ErrShortsPlaylist, reasonUnsupportedURL, true},
		{"damaged download", fmt.Errorf("remux: %w", waxtap.ErrUnsupportedInput), "", false},
	} {
		reason, permanent := acquireReason(catalogerr.Wrap(catalogerr.CodeIO, "fetch", tc.err))
		if reason != tc.reason || permanent != tc.permanent {
			t.Errorf("%s = %q (permanent %v), want %q (permanent %v)", tc.name, reason, permanent, tc.reason, tc.permanent)
		}
	}
}

// A source that could not be reached, or broke off, is named for what it
// is, retryable and no verdict on the link.
func TestASourceThatCannotBeReachedIsUnreachable(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name string
		err  error
	}{
		{"dns", &url.Error{Op: "Get", URL: "https://tube.example", Err: &net.OpError{Op: "dial", Net: "tcp",
			Err: &net.DNSError{Err: "no such host", Name: "tube.example", IsNotFound: true}}}},
		{"refused", &net.OpError{Op: "dial", Net: "tcp", Err: os.NewSyscallError("connect", syscall.ECONNREFUSED)}},
		{"reset", &net.OpError{Op: "read", Net: "tcp", Err: os.NewSyscallError("read", syscall.ECONNRESET)}},
		{"tls", &url.Error{Op: "Get", URL: "https://tube.example", Err: &tls.CertificateVerificationError{Err: x509.UnknownAuthorityError{}}}},
		{"tls record", tls.RecordHeaderError{Msg: "first record does not look like a TLS handshake"}},
		{"broke off", fmt.Errorf("reading the body: %w", io.ErrUnexpectedEOF)},
		{"incomplete stream", fmt.Errorf("%w: chunk at offset 0", waxtap.ErrIncompleteStream)},
		{"url expired", fmt.Errorf("%w: stream refresh", waxtap.ErrURLExpired)},
		{"server error", &waxtap.HTTPStatusError{StatusCode: 503, URL: "https://tube.example/watch"}},
	} {
		reason, permanent := acquireReason(catalogerr.Wrap(catalogerr.CodeIO, "fetch", tc.err))
		if reason != reasonUnreachable || permanent {
			t.Errorf("%s = %q (permanent %v), want %q and no verdict", tc.name, reason, permanent, reasonUnreachable)
		}
	}
	if reason, _ := acquireReason(&url.Error{Op: "Get", URL: "https://tube.example", Err: context.Canceled}); reason != "" {
		t.Errorf("a canceled request = %q, want no reason", reason)
	}
	if reason, _ := acquireReason(&waxtap.HTTPStatusError{StatusCode: 404}); reason != "" {
		t.Errorf("a 404 = %q, want it unnamed as before", reason)
	}
	// The session sidecar is the server's own bridge, not the source.
	sidecar := &waxtap.SidecarError{Label: "session sidecar", Endpoint: "http://waxseal:8080",
		Err: &net.OpError{Op: "dial", Net: "tcp", Err: os.NewSyscallError("connect", syscall.ECONNREFUSED)}}
	if reason, permanent := acquireReason(catalogerr.Wrap(catalogerr.CodeIO, "fetch", sidecar)); reason != reasonSourceBroken || permanent {
		t.Errorf("a refused sidecar = %q (permanent %v), want %q and no verdict", reason, permanent, reasonSourceBroken)
	}
	timeout := &net.OpError{Op: "dial", Net: "tcp", Err: os.ErrDeadlineExceeded}
	if reason, permanent := acquireReason(timeout); reason != reasonTimedOut || permanent {
		t.Errorf("a dial out of time = %q (permanent %v), want %q", reason, permanent, reasonTimedOut)
	}
}

// storedTask reads a task's row as the store has it.
func storedTask(t *testing.T, ctx context.Context, svc *Library, id string) wdb.ToolTask {
	t.Helper()
	row, err := svc.db.ToolTaskByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	return row
}

// drainTaskAt leases and works one task as the worker would at now.
func drainTaskAt(t *testing.T, ctx context.Context, svc *Library, now time.Time) {
	t.Helper()
	if !drainShortAt(ctx, svc, now.UnixNano()) {
		t.Fatal("the worker found no task to run")
	}
}

// A verdict the source gives once the run asks fails the task on that
// run, with the code and reason a client words it by.
func TestASourceVerdictFailsTheAcquisitionAtOnce(t *testing.T) {
	t.Parallel()
	for reason, err := range map[string]error{
		"video-unavailable": waxtap.ErrVideoUnavailable,
		"unsupported-url":   waxtap.ErrIsPlaylist,
	} {
		t.Run(reason, func(t *testing.T) {
			t.Parallel()
			src := &probeSource{fetchErr: catalogerr.Wrap(catalogerr.CodeIO, "fetch", err)}
			ctx, svc, uc := acquireFixture(t, src)
			task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/watch?v=one", false, "music", "", "", nil, nil)
			if err != nil {
				t.Fatal(err)
			}
			drainOnce(t, ctx, svc)
			row := storedTask(t, ctx, svc, task.ID)
			if row.State != taskStateFailed || row.Attempts != 1 || row.ErrorCode != "source-refused" ||
				row.ErrorParams != `{"reason":"`+reason+`"}` {
				t.Fatalf("task = %s after %d attempts, code %q %s (error %q); want it failed for %s on the first",
					row.State, row.Attempts, row.ErrorCode, row.ErrorParams, row.Error, reason)
			}
			dto := queuedTasks(t, ctx, svc, uc)[0]
			if dto.ErrorCode != "source-refused" || dto.ErrorParams["reason"] != reason {
				t.Errorf("the task reads %q %v, want source-refused for %s", dto.ErrorCode, dto.ErrorParams, reason)
			}
		})
	}
}

// A source that asks the run to slow down is waited out for as long as it
// asks, in view and without spending an attempt; after three waits the
// task fails, saying why.
func TestARateLimitedSourceIsWaitedOutAsItAsks(t *testing.T) {
	t.Parallel()
	src := &probeSource{fetchErr: catalogerr.Wrap(catalogerr.CodeIO, "fetch",
		&waxtap.RateLimitError{RetryAfter: 90 * time.Second, StatusCode: 429})}
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/watch?v=one", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	before := time.Now()
	drainOnce(t, ctx, svc)
	after := time.Now()
	row := storedTask(t, ctx, svc, task.ID)
	if row.State != taskStateRunning || row.WaitReason != "rate-limited" || row.Attempts != 0 || row.Error == "" {
		t.Fatalf("task = %s waiting on %q after %d attempts (error %q); want it waiting as rate-limited, no attempt spent",
			row.State, row.WaitReason, row.Attempts, row.Error)
	}
	if lo, hi := before.Add(90*time.Second).UnixNano(), after.Add(90*time.Second).UnixNano(); row.LeaseUntilNS < lo || row.LeaseUntilNS > hi {
		t.Errorf("next try at %v, want 90s after the run", time.Unix(0, row.LeaseUntilNS).Sub(after))
	}
	if dto := queuedTasks(t, ctx, svc, uc)[0]; dto.WaitReason != "rate-limited" || dto.RetryAtNS != row.LeaseUntilNS {
		t.Errorf("the task reads waiting on %q until %d, want rate-limited until %d", dto.WaitReason, dto.RetryAtNS, row.LeaseUntilNS)
	}
	later := time.Now().Add(time.Hour)
	for wait := 2; wait <= 3; wait++ {
		drainTaskAt(t, ctx, svc, later)
		if row := storedTask(t, ctx, svc, task.ID); row.WaitReason != "rate-limited" {
			t.Fatalf("wait %d: task = %s waiting on %q (error %q), want it waiting again", wait, row.State, row.WaitReason, row.Error)
		}
		later = later.Add(time.Hour)
	}
	drainTaskAt(t, ctx, svc, later)
	row = storedTask(t, ctx, svc, task.ID)
	if row.State != taskStateFailed || row.ErrorCode != "source-refused" || row.ErrorParams != `{"reason":"rate-limited"}` {
		t.Fatalf("after three waits task = %s, code %q %s (error %q); want it failed as rate-limited",
			row.State, row.ErrorCode, row.ErrorParams, row.Error)
	}
	if _, _, fetched := src.calls(); len(fetched) != 4 {
		t.Errorf("fetched %d times, want the first try and one after each wait", len(fetched))
	}
}

// stagingSource lists three videos and fetches each as a few bytes; the
// stalling one's fetch hangs until its bound runs out while stall is set,
// and atThree, when set, runs first in the third video's fetch, an error
// answering it.
type stagingSource struct {
	onceSource
	stall atomic.Bool

	mu      sync.Mutex
	fetches map[string]int
	atThree func(ctx context.Context) error
	// cut has the listing say it stopped at the source's own cap.
	cut bool
}

func (s *stagingSource) answerThree(answer func(ctx context.Context) error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.atThree = answer
}

func (s *stagingSource) EnumerateOnce(_ context.Context, _ source.Request, opts syncsource.EnumerateOptions) (*source.Enumeration, error) {
	if s.cut && opts.OnCut != nil {
		opts.OnCut()
	}
	feed := &model.Feed{Title: "Three"}
	for _, id := range []string{"one", "two", "three"} {
		feed.Episodes = append(feed.Episodes, model.FeedEpisode{GUID: id, Title: id, EnclosureURL: "https://tube.example/watch?v=" + id})
	}
	return &source.Enumeration{Feed: feed}, nil
}

func (s *stagingSource) Fetch(ctx context.Context, req source.FetchRequest, w io.Writer) (*source.FetchResult, error) {
	s.mu.Lock()
	if s.fetches == nil {
		s.fetches = map[string]int{}
	}
	s.fetches[req.URL]++
	atThree := s.atThree
	s.mu.Unlock()
	if strings.HasSuffix(req.URL, "=three") && s.stall.Load() {
		<-ctx.Done()
		return nil, ctx.Err()
	}
	if strings.HasSuffix(req.URL, "=three") && atThree != nil {
		if err := atThree(ctx); err != nil {
			return nil, err
		}
	}
	n, err := io.WriteString(w, "a few bytes of "+req.URL)
	return &source.FetchResult{Bytes: int64(n), ContentType: "audio/mpeg"}, err
}

func (s *stagingSource) fetchCounts() map[string]int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return maps.Clone(s.fetches)
}

// A fetch that hangs to its own bound costs only that item: what staged
// before it keeps its review entries, the task waits, and the next try
// fetches only what is left.
func TestAHungFetchKeepsWhatStagedAndTheRetrySkipsIt(t *testing.T) {
	t.Parallel()
	src := &stagingSource{}
	src.stall.Store(true)
	ctx, svc, uc := acquireFixture(t, src)
	svc.Ingest.acquireItemBound = 300 * time.Millisecond
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	drainOnce(t, ctx, svc)
	row := storedTask(t, ctx, svc, task.ID)
	if row.State != taskStateRunning || row.WaitReason != "source-retry" {
		t.Fatalf("task = %s waiting on %q (error %q), want it waiting to try again", row.State, row.WaitReason, row.Error)
	}
	var withEntries int
	if err := svc.db.Reader().QueryRowContext(ctx, `SELECT COUNT(*) FROM uploads WHERE review_entry_id <> ''`).Scan(&withEntries); err != nil {
		t.Fatal(err)
	}
	if withEntries != 2 {
		t.Fatalf("%d staged downloads have review entries, want the two that staged", withEntries)
	}
	src.stall.Store(false)
	drainTaskAt(t, ctx, svc, time.Now().Add(time.Hour))
	row = storedTask(t, ctx, svc, task.ID)
	if row.State != taskStateDone {
		t.Fatalf("the retry left the task %s (error %q), want it done", row.State, row.Error)
	}
	want := map[string]int{"https://tube.example/watch?v=one": 1, "https://tube.example/watch?v=two": 1, "https://tube.example/watch?v=three": 2}
	if got := src.fetchCounts(); !maps.Equal(got, want) {
		t.Errorf("fetches = %v, want %v: the retry fetched only what was left", got, want)
	}
	var entries []string
	if err := json.Unmarshal([]byte(row.ResultPIDs), &entries); err != nil || len(entries) == 0 {
		t.Fatalf("results %s, want the entries of both tries", row.ResultPIDs)
	}
	var linked int
	if err := svc.db.Reader().QueryRowContext(ctx, `SELECT COUNT(DISTINCT review_entry_id) FROM uploads WHERE review_entry_id <> ''`).Scan(&linked); err != nil {
		t.Fatal(err)
	}
	if linked != len(entries) {
		t.Errorf("the task lists %d entries, the downloads sit in %d", len(entries), linked)
	}
}

// A download whose source drops the connection waits to try again, and
// once its waits run out fails as a source that could not be reached.
func TestADroppedConnectionWaitsThenFailsUnreachable(t *testing.T) {
	t.Parallel()
	src := &stagingSource{}
	src.answerThree(func(context.Context) error {
		return &net.OpError{Op: "read", Net: "tcp", Err: os.NewSyscallError("read", syscall.ECONNRESET)}
	})
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	drainOnce(t, ctx, svc)
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateRunning || row.WaitReason != "source-retry" {
		t.Fatalf("task = %s waiting on %q (error %q, code %q), want it waiting to try again", row.State, row.WaitReason, row.Error, row.ErrorCode)
	}
	at := time.Now()
	for range toolSourceWaits {
		at = at.Add(24 * time.Hour)
		drainTaskAt(t, ctx, svc, at)
		if storedTask(t, ctx, svc, task.ID).State != taskStateRunning {
			break
		}
	}
	row := storedTask(t, ctx, svc, task.ID)
	var params map[string]string
	_ = json.Unmarshal([]byte(row.ErrorParams), &params)
	if row.State != taskStateFailed || row.ErrorCode != "source-refused" || params["reason"] != reasonUnreachable {
		t.Errorf("task = %s, code %q %v (error %q), want it failed as source-refused for unreachable", row.State, row.ErrorCode, params, row.Error)
	}
}

// uploadsWithoutEntry counts the staged downloads no review entry holds.
func uploadsWithoutEntry(t *testing.T, ctx context.Context, svc *Library) int {
	t.Helper()
	var n int
	if err := svc.db.Reader().QueryRowContext(ctx, `SELECT COUNT(*) FROM uploads WHERE review_entry_id = ''`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

// A run that dies after some items staged and before their entries open
// (the process killed, a panic the worker recovers) loses nothing: the
// next run opens their entries without fetching them again, and fetches
// again what is gone since.
func TestARunThatDiesAfterStagingOpensTheirEntriesNextTime(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name string
		gone bool
		want map[string]int
	}{
		{"staged", false, map[string]int{"https://tube.example/watch?v=one": 1, "https://tube.example/watch?v=two": 1, "https://tube.example/watch?v=three": 2}},
		{"gone", true, map[string]int{"https://tube.example/watch?v=one": 2, "https://tube.example/watch?v=two": 1, "https://tube.example/watch?v=three": 2}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			src := &stagingSource{}
			src.answerThree(func(context.Context) error { panic("the run died") })
			ctx, svc, uc := acquireFixture(t, src)
			task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
			if err != nil {
				t.Fatal(err)
			}
			func() {
				defer func() {
					if recover() == nil {
						t.Fatal("the run did not die")
					}
				}()
				drainOnce(t, ctx, svc)
			}()
			if n := uploadsWithoutEntry(t, ctx, svc); n != 2 {
				t.Fatalf("%d staged downloads without an entry after the run died, want the two it staged", n)
			}
			if tc.gone {
				var path string
				if err := svc.db.Reader().QueryRowContext(ctx, `SELECT staging_path FROM uploads WHERE file_name = 'one.mp3'`).Scan(&path); err != nil {
					t.Fatal(err)
				}
				if _, err := svc.db.Writer().ExecContext(ctx, `DELETE FROM uploads WHERE file_name = 'one.mp3'`); err != nil {
					t.Fatal(err)
				}
				_ = os.RemoveAll(filepath.Dir(path))
			}
			src.answerThree(nil)
			drainTaskAt(t, ctx, svc, time.Now().Add(time.Hour))
			row := storedTask(t, ctx, svc, task.ID)
			if row.State != taskStateDone {
				t.Fatalf("the next run left the task %s (error %q), want it done", row.State, row.Error)
			}
			if n := uploadsWithoutEntry(t, ctx, svc); n != 0 {
				t.Errorf("%d staged downloads have no review entry, want none", n)
			}
			if got := src.fetchCounts(); !maps.Equal(got, tc.want) {
				t.Errorf("fetches = %v, want %v", got, tc.want)
			}
			var entries []string
			if err := json.Unmarshal([]byte(row.ResultPIDs), &entries); err != nil {
				t.Fatal(err)
			}
			var linked int
			if err := svc.db.Reader().QueryRowContext(ctx, `SELECT COUNT(DISTINCT review_entry_id) FROM uploads WHERE review_entry_id <> ''`).Scan(&linked); err != nil {
				t.Fatal(err)
			}
			if linked == 0 || linked != len(entries) {
				t.Errorf("the task lists %d entries, the downloads sit in %d", len(entries), linked)
			}
		})
	}
}

// A run the server stops mid-fetch still opens the entries of what staged
// before, and is not failed for it: it runs again once the server is back.
func TestAStoppedRunStillOpensWhatStaged(t *testing.T) {
	t.Parallel()
	src := &stagingSource{}
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	stopping, stop := context.WithCancel(ctx)
	defer stop()
	src.answerThree(func(ctx context.Context) error {
		stop()
		<-ctx.Done()
		return ctx.Err()
	})
	svc.Tools.drainToolTasksAt(stopping, sourceDrain, time.Now().UnixNano())
	var withEntries int
	if err := svc.db.Reader().QueryRowContext(ctx, `SELECT COUNT(*) FROM uploads WHERE review_entry_id <> ''`).Scan(&withEntries); err != nil {
		t.Fatal(err)
	}
	if withEntries != 2 {
		t.Errorf("%d staged downloads have review entries, want the two that staged before the stop", withEntries)
	}
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateRunning || row.WaitReason != "" {
		t.Errorf("the stopped task = %s waiting on %q (error %q), want it left to run again", row.State, row.WaitReason, row.Error)
	}
}

// A run's failure no retry changes says what kind it is, so no row
// headlines one as the server's fault; one that cut a list short says how
// much of it staged before.
func TestAFinalRunFailureSaysWhatKindItIs(t *testing.T) {
	t.Parallel()
	t.Run("upload rights revoked", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc := acquireFixture(t, &stagingSource{})
		task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		member, _ := memberAs(t, ctx, svc, AccountCreate{Username: "revoked"})
		if _, err := svc.db.Writer().ExecContext(ctx, `UPDATE tool_tasks SET user_id = ? WHERE id = ?`, member.User.ID, task.ID); err != nil {
			t.Fatal(err)
		}
		drainOnce(t, ctx, svc)
		if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateFailed || row.ErrorCode != "forbidden" {
			t.Errorf("task = %s, code %q (error %q), want it failed as forbidden", row.State, row.ErrorCode, row.Error)
		}
	})
	t.Run("pending-upload limit full", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc := acquireFixture(t, &stagingSource{})
		quota := int64(1)
		if _, err := svc.Identity.UpdateAccount(ctx, uc.ID, AccountUpdate{UploadQuotaBytes: &quota}); err != nil {
			t.Fatal(err)
		}
		task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		drainOnce(t, ctx, svc)
		row := storedTask(t, ctx, svc, task.ID)
		if row.State != taskStateFailed || row.ErrorCode != "quota-exceeded" || !strings.Contains(row.Error, "1 of 3 items staged before") {
			t.Errorf("task = %s, code %q (error %q), want it failed as quota-exceeded saying one of three staged", row.State, row.ErrorCode, row.Error)
		}
	})
	t.Run("nothing to download", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc := acquireFixture(t, emptySource{})
		task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLnone", false, "music", "", "", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		drainOnce(t, ctx, svc)
		if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateFailed || row.ErrorCode != "source-refused" || row.ErrorParams != `{"reason":"playlist-empty"}` {
			t.Errorf("task = %s, code %q %s (error %q), want it failed as source-refused, playlist-empty", row.State, row.ErrorCode, row.ErrorParams, row.Error)
		}
	})
	t.Run("a verdict mid-list", func(t *testing.T) {
		t.Parallel()
		src := &stagingSource{}
		src.answerThree(func(context.Context) error {
			return catalogerr.Wrap(catalogerr.CodeIO, "fetch", waxtap.ErrVideoUnavailable)
		})
		ctx, svc, uc := acquireFixture(t, src)
		task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		drainOnce(t, ctx, svc)
		row := storedTask(t, ctx, svc, task.ID)
		if row.State != taskStateFailed || row.ErrorCode != "source-refused" || row.ErrorParams != `{"reason":"video-unavailable"}` ||
			!strings.Contains(row.Error, "2 of 3 items staged before") {
			t.Errorf("task = %s, code %q %s (error %q), want it failed as video-unavailable saying two of three staged",
				row.State, row.ErrorCode, row.ErrorParams, row.Error)
		}
	})
}

// emptySource lists a playlist with nothing in it to download.
type emptySource struct{ onceSource }

func (emptySource) EnumerateOnce(context.Context, source.Request, syncsource.EnumerateOptions) (*source.Enumeration, error) {
	return &source.Enumeration{Feed: &model.Feed{Title: "Nothing"}}, nil
}

// A source wait keeps the reason it was for, so a task its attempts later
// retire (its runs ending with the process) fails with that reason rather
// than as the server's fault.
func TestASourceWaitRetiredByItsAttemptsKeepsItsReason(t *testing.T) {
	t.Parallel()
	src := &probeSource{fetchErr: catalogerr.Wrap(catalogerr.CodeIO, "fetch",
		&waxtap.RateLimitError{RetryAfter: 90 * time.Second, StatusCode: 429})}
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/watch?v=one", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	drainOnce(t, ctx, svc)
	row := storedTask(t, ctx, svc, task.ID)
	if row.WaitReason != "rate-limited" || row.ErrorCode != "source-refused" || row.ErrorParams != `{"reason":"rate-limited"}` {
		t.Fatalf("the wait = %q, code %q %s, want rate-limited recorded as source-refused for rate-limited", row.WaitReason, row.ErrorCode, row.ErrorParams)
	}
	now := time.Now().Add(time.Hour)
	for range toolTaskMaxAttempts {
		if _, err := svc.db.LeaseToolTask(ctx, now.UnixNano(), toolTaskLease.Nanoseconds(), toolTaskMaxAttempts, wdb.TaskTypes{}); err != nil {
			t.Fatal(err)
		}
		now = now.Add(toolTaskLease + time.Second)
	}
	svc.Tools.drainToolTasksAt(ctx, sourceDrain, now.UnixNano())
	row = storedTask(t, ctx, svc, task.ID)
	if row.State != taskStateFailed || row.ErrorCode != "source-refused" || row.ErrorParams != `{"reason":"rate-limited"}` {
		t.Errorf("retired task = %s, code %q %s (error %q), want it failed as source-refused for rate-limited",
			row.State, row.ErrorCode, row.ErrorParams, row.Error)
	}
}

// A source asking for a longer pause than the waits' own longest gets that
// longest, so no row waits a day on one answer.
func TestASourcesRetryAfterIsCapped(t *testing.T) {
	t.Parallel()
	src := &probeSource{fetchErr: catalogerr.Wrap(catalogerr.CodeIO, "fetch",
		&waxtap.RateLimitError{RetryAfter: 24 * time.Hour, StatusCode: 429})}
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/watch?v=one", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	before := time.Now()
	drainOnce(t, ctx, svc)
	after := time.Now()
	row := storedTask(t, ctx, svc, task.ID)
	if lo, hi := before.Add(30*time.Minute).UnixNano(), after.Add(30*time.Minute).UnixNano(); row.WaitReason != "rate-limited" || row.LeaseUntilNS < lo || row.LeaseUntilNS > hi {
		t.Errorf("waiting on %q until %v after the run, want rate-limited for thirty minutes", row.WaitReason, time.Unix(0, row.LeaseUntilNS).Sub(after))
	}
}
