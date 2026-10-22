package service

// Service-layer support for the gpodder compatibility adapter: Basic
// authentication against app passwords, the subscription bridges that
// key on feed URLs instead of PIDs, the playback write-through for
// uploaded play actions, and thin pass-throughs to the adapter's own
// device and event tables. The adapter sits above the ownership line
// and calls only these methods; every catalog access happens here.

import (
	"cmp"
	"context"
	"crypto/subtle"
	"errors"
	"fmt"
	"log/slog"
	"net/url"
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/colespringer/waxbin/identity"
	"github.com/colespringer/waxbin/model"
	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxdeck/server/internal/auth"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// VerifyAppPasswordBasic authenticates the HTTP Basic scheme: username
// plus an app password secret presented in the clear. The login
// password never works here. It returns the account and the id of the
// app password that matched, or nil on any failure (unknown user,
// disabled account, no matching password), never distinguishing them;
// the secret comparison is constant time per candidate.
func (l *Library) VerifyAppPasswordBasic(ctx context.Context, username, password string) (*wdb.User, string, error) {
	u, err := l.db.UserByUsername(ctx, username)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, "", nil
		}
		return nil, "", &Error{Kind: KindInternal, Err: err}
	}
	if u.Disabled {
		return nil, "", nil
	}
	for _, entry := range l.userAppSecrets(ctx, u.ID) {
		if subtle.ConstantTimeCompare([]byte(entry.secret), []byte(password)) == 1 {
			l.touchAppPassword(ctx, entry)
			return u, entry.id, nil
		}
	}
	return nil, "", nil
}

// Gpodder sessions: the sessionid cookie is an opaque token naming one
// session row, opened by a login or by a request signed with Basic
// credentials, which goes with the app password that opened it and with
// its account, so a revoke, a logout, or a recreated username leaves
// the cookie naming nothing.
const (
	gpodderSessionTTL = 14 * 24 * time.Hour
	// gpodderSessionsPerPassword bounds the rows of each kind one app
	// password holds: a client that logs in on every sync, or signs every
	// request and keeps no cookie, replaces its oldest.
	gpodderSessionsPerPassword = 20
)

// GpodderLogin verifies Basic credentials against the account's app
// passwords and opens a session for them, answering the account, the
// cookie value and when the session ends (the cookie's own expiry, so
// the two cannot drift); nil when the credentials do not verify, or
// verify as an account other than the one the client named (compared
// without case), which opens nothing.
func (l *Library) GpodderLogin(ctx context.Context, account, username, secret string) (*wdb.User, string, time.Time, error) {
	u, apID, err := l.VerifyAppPasswordBasic(ctx, username, secret)
	if err != nil || u == nil || !strings.EqualFold(u.Username, account) {
		return nil, "", time.Time{}, err
	}
	token, expires, err := l.openGpodderSession(ctx, u, apID, false, false)
	if err != nil {
		return nil, "", time.Time{}, err
	}
	return u, token, expires, nil
}

// GpodderOpenSession opens a session for a request the account's app
// password signed with Basic credentials, answering its cookie and when it
// ends, so a client that keeps cookies is not asked for the credentials
// again. These are held apart from the logins.
func (l *Library) GpodderOpenSession(ctx context.Context, u *wdb.User, appPasswordID string) (string, time.Time, error) {
	return l.openGpodderSession(ctx, u, appPasswordID, true, false)
}

func (l *Library) openGpodderSession(ctx context.Context, u *wdb.User, appPasswordID string, basic, presented bool) (string, time.Time, error) {
	token, hash, err := auth.NewOpaqueToken()
	if err != nil {
		return "", time.Time{}, &Error{Kind: KindInternal, Err: err}
	}
	now := time.Now()
	expires := now.Add(gpodderSessionTTL)
	if err := l.db.InsertGpodderSession(ctx, wdb.GpodderSession{
		ID: ulid.Make().String(), UserID: u.ID, AppPasswordID: appPasswordID, TokenHash: hash,
		CreatedAtNS: now.UnixNano(), ExpiresAtNS: expires.UnixNano(), Basic: basic, Presented: presented,
	}, gpodderSessionsPerPassword); err != nil {
		return "", time.Time{}, &Error{Kind: KindInternal, Err: err}
	}
	return token, expires, nil
}

// GpodderSessionUser resolves a session cookie to its account: nil when
// the cookie names no live session, or its account can no longer sign
// in.
func (l *Library) GpodderSessionUser(ctx context.Context, token string) (*wdb.User, error) {
	u, _, err := l.GpodderSession(ctx, token)
	return u, err
}

// GpodderSession is GpodderSessionUser answering the session too.
func (l *Library) GpodderSession(ctx context.Context, token string) (*wdb.User, *wdb.GpodderSession, error) {
	if token == "" {
		return nil, nil, nil
	}
	s, err := l.db.GpodderSessionByHash(ctx, auth.TokenHash(token))
	if errors.Is(err, wdb.ErrNotFound) {
		return nil, nil, nil
	}
	if err != nil {
		return nil, nil, &Error{Kind: KindInternal, Err: err}
	}
	if time.Now().UnixNano() >= s.ExpiresAtNS {
		return nil, nil, nil
	}
	u, err := l.db.UserByID(ctx, s.UserID)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, nil, nil
		}
		return nil, nil, &Error{Kind: KindInternal, Err: err}
	}
	if u.Disabled || u.Pending {
		return nil, nil, nil
	}
	return u, s, nil
}

// GpodderSessionUsed records that a session's cookie authenticated a
// request: the first time, it is marked presented, so an app password
// with too many sessions lets go of those whose cookies never came back
// first. A session a signed request opened with less than half its life
// left is renewed: it answers a fresh cookie, presented from the start,
// and ends, so a client that keeps syncing is never asked for its
// password again. "" when there is nothing to renew.
func (l *Library) GpodderSessionUsed(ctx context.Context, s *wdb.GpodderSession) (string, time.Time, error) {
	if !s.Presented {
		if err := l.db.MarkGpodderSessionPresented(ctx, s.ID); err != nil {
			return "", time.Time{}, &Error{Kind: KindInternal, Err: err}
		}
	}
	if !s.Basic || time.Until(time.Unix(0, s.ExpiresAtNS)) >= gpodderSessionTTL/2 {
		return "", time.Time{}, nil
	}
	token, expires, err := l.openGpodderSession(ctx, &wdb.User{ID: s.UserID}, s.AppPasswordID, true, true)
	if err != nil {
		return "", time.Time{}, err
	}
	if err := l.db.DeleteGpodderSessionByHash(ctx, s.TokenHash); err != nil {
		return "", time.Time{}, &Error{Kind: KindInternal, Err: err}
	}
	return token, expires, nil
}

// GpodderLogout ends the session a cookie names.
func (l *Library) GpodderLogout(ctx context.Context, token string) error {
	if token == "" {
		return nil
	}
	if err := l.db.DeleteGpodderSessionByHash(ctx, auth.TokenHash(token)); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// EndGpodderSessions ends every gpodder session of the account: a
// disable, and signing the account out everywhere.
func (l *Library) EndGpodderSessions(ctx context.Context, userID string) error {
	if err := l.db.DeleteGpodderSessionsForUser(ctx, userID); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// GpodderFeedURLs returns a URL for every show the user follows that
// gpodder clients sync, private shows included: the one the device calls
// the show by, else the one the account subscribed it by, never the
// catalog's, which can be another subscriber's own. A device calls a show
// by what it was told from then on.
func (l *Library) GpodderFeedURLs(ctx context.Context, uc *UserCtx, device string) ([]string, error) {
	if !l.podcastsVisible(ctx, uc) {
		return []string{}, nil
	}
	subs, err := l.db.SubscriptionURLs(ctx, uc.ID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	own, removed, registered, err := l.gpodderReader(ctx, uc, device)
	if err != nil {
		return nil, err
	}
	out := make([]string, 0, len(subs))
	var told []wdb.ShowURL
	for _, sub := range subs {
		pod, err := l.readShow(ctx, model.PID(sub.ShowPID))
		if err != nil {
			// A show removed out from under a subscription row is a
			// dangling reference, skipped; any other failure fails the
			// read, whose answer would say the account follows nothing.
			if err := classify(err); KindOf(err) != KindNotFound {
				return nil, err
			}
			continue
		}
		if !gpodderSyncs(pod) {
			continue
		}
		u := own[sub.ShowPID]
		if u == "" || removed[sub.ShowPID] > 0 {
			if u = sub.FeedURL; u == "" {
				continue
			}
			told = append(told, wdb.ShowURL{ShowPID: sub.ShowPID, FeedURL: u})
		}
		out = append(out, u)
	}
	if !registered {
		return out, nil
	}
	// The list tells the device what it holds: what it no longer carries,
	// or was told the account left, is gone to the device, and what it
	// carries by no URL of the device's own is called what the device was
	// told.
	if err := l.db.ForgetUnfollowedGpodderDeviceURLs(ctx, uc.ID, device); err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.FillGpodderDeviceURLs(ctx, uc.ID, device, told); err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	return out, nil
}

// gpodderReader is what a read for a device knows of it: what it calls
// each show, the removals it was told under those URLs, and whether
// anybody registered it, without which it keeps no URLs and its reads
// write nothing.
func (l *Library) gpodderReader(ctx context.Context, uc *UserCtx, device string) (own map[string]string, removed map[string]int64, registered bool, err error) {
	if device == "" {
		return nil, nil, false, nil
	}
	if registered, err = l.db.GpodderDeviceExists(ctx, uc.ID, device); err != nil {
		return nil, nil, false, &Error{Kind: KindInternal, Err: err}
	}
	if !registered {
		return nil, nil, false, nil
	}
	own, removed, err = l.gpodderDeviceURLs(ctx, uc, device)
	return own, removed, true, err
}

// gpodderSyncs reports whether gpodder clients sync a show: a feed, not a
// manual show or a YouTube channel, which no podcast app can follow.
func gpodderSyncs(pod *model.Podcast) bool {
	return (pod.SourceType == model.SourceRSS || pod.SourceType == "") && pod.FeedURL != ""
}

// gpodderEventURL is the URL the change log records a subscription change
// of the show under: the account's, or none for a show gpodder clients do
// not sync.
func gpodderEventURL(pod *model.Podcast, accountURL string) string {
	if !gpodderSyncs(pod) {
		return ""
	}
	return accountURL
}

// gpodderDeviceURLs answers what one device calls each show, by show, and
// the second marked on each it was told the show's removal under; nil for
// no device.
func (l *Library) gpodderDeviceURLs(ctx context.Context, uc *UserCtx, device string) (map[string]string, map[string]int64, error) {
	if device == "" {
		return nil, nil, nil
	}
	urls, err := l.db.GpodderDeviceURLs(ctx, uc.ID, device)
	if err != nil {
		return nil, nil, &Error{Kind: KindInternal, Err: err}
	}
	out, removed := make(map[string]string, len(urls)), map[string]int64{}
	for _, u := range urls {
		out[u.ShowPID] = u.FeedURL
		if u.RemovedSec > 0 {
			removed[u.ShowPID] = u.RemovedSec
		}
	}
	return out, removed, nil
}

// accountFeedURLs answers the URL the account subscribed each show it
// follows by, by show.
func (l *Library) accountFeedURLs(ctx context.Context, userID string) (map[string]string, error) {
	urls, err := l.db.SubscriptionURLs(ctx, userID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	out := make(map[string]string, len(urls))
	for _, u := range urls {
		out[u.ShowPID] = u.FeedURL
	}
	return out, nil
}

// The gpodder surface's bounds: what one account can keep of it.
const (
	gpodderMaxDevices    = 50
	gpodderMaxCaptionLen = 256
	// gpodderMaxHostLen bounds the host an inbox title names.
	gpodderMaxHostLen      = 253
	gpodderActionsPerUser  = 20_000
	gpodderActionRetention = 365 * 24 * time.Hour
	// gpodderRemovalsPerUser bounds the removals the change log keeps,
	// for the same year; a show keeps only its latest change.
	gpodderRemovalsPerUser = 10_000
	gpodderPendingPerUser  = 200
	gpodderPendingLifetime = 7 * 24 * time.Hour
	// gpodderNoticeWindow is how long the account, once told of a device's
	// failed add, is not told of it again.
	gpodderNoticeWindow = 30 * 24 * time.Hour
	// gpodderEvictionsNamed is how many devices let go for room the inbox
	// names in any gpodderEvictionWindow; one row more says others went.
	gpodderEvictionsNamed = 3
	gpodderEvictionWindow = 24 * time.Hour
)

// GpodderMaxDeviceIDLen is the longest device id, in bytes, the surface
// keeps.
const GpodderMaxDeviceIDLen = 128

// GpodderOwnDevice is the device id the actions of WaxDeck's own apps
// carry, which no client may take.
const GpodderOwnDevice = "waxdeck"

// gpodderPaging bounds the stamp reads behind one episodes download: the
// stamps one read takes, the most one download reads, and the plays past
// which it stops at the end of a second.
type gpodderPaging struct{ page, budget, plays int }

// gpodderDownloadPaging reads a long history in one download: a year of
// heavy listening is tens of thousands of stamps, most of them music.
var gpodderDownloadPaging = gpodderPaging{page: 5000, budget: 50_000, plays: 5000}

// gpodderRetryBackoff spaces the tries at a parked feed: five minutes,
// a quarter hour, an hour, six hours, then daily until it lands or its
// week is up.
var gpodderRetryBackoff = []time.Duration{5 * time.Minute, 15 * time.Minute, time.Hour, 6 * time.Hour, 24 * time.Hour}

func gpodderRetryDelay(attempts int) time.Duration {
	return gpodderRetryBackoff[min(attempts, len(gpodderRetryBackoff)-1)]
}

// GpodderOutcome is what became of a feed a device asked for.
type GpodderOutcome string

const (
	// GpodderLanded: the account subscribes to the show, and the device
	// holds it.
	GpodderLanded GpodderOutcome = "landed"
	// GpodderParked: the feed could not be fetched for a reason that may
	// pass and is tried again for a week; no list carries it meanwhile.
	GpodderParked GpodderOutcome = "parked"
	// GpodderRefused: the feed will not land as asked, and the account's
	// inbox says so: why for the first few of one request it has not said
	// yet, the rest counted.
	GpodderRefused GpodderOutcome = "refused"
)

// GpodderListResult is what one device's full-list upload changed.
type GpodderListResult struct {
	Outcomes map[string]GpodderOutcome
	// Released counts the shows the account left because the device let
	// go of the last hold on them.
	Released int
}

// gpodderShowKey is a feed URL without its spelling, the way the catalog
// tells two of them apart: scheme and host case, http against https and
// a trailing slash are all one feed.
func gpodderShowKey(feedURL string) string { return identity.PodcastKey("", feedURL) }

// gpodderNames resolves the feed URLs a client sends to the shows they
// name, without a fetch: by what the device calls a show, then what the
// account does, then the catalog's current URL for it, then the URL a
// feed without a guid is keyed by. Only shows gpodder clients sync are
// named.
type gpodderNames struct {
	shows   map[string]*model.Podcast
	account map[string]*model.Podcast
	catalog map[string]*model.Podcast
	keyed   map[string]*model.Podcast
	// accountURLs is what the account calls each show it follows, by show.
	accountURLs map[string]string
	devices     map[string]*gpodderDeviceNames
}

// gpodderDeviceNames is what one device calls the shows it knows.
type gpodderDeviceNames struct {
	byKey  map[string]*model.Podcast
	byShow map[string]string
}

func (l *Library) gpodderNames(ctx context.Context, uc *UserCtx) (*gpodderNames, error) {
	pods, err := l.lib.Podcasts().List(ctx)
	if err != nil {
		return nil, classify(err)
	}
	n := &gpodderNames{shows: make(map[string]*model.Podcast, len(pods)), account: map[string]*model.Podcast{},
		catalog: make(map[string]*model.Podcast, len(pods)), keyed: map[string]*model.Podcast{},
		devices: map[string]*gpodderDeviceNames{}}
	for _, pod := range pods {
		n.learn(pod)
	}
	if n.accountURLs, err = l.accountFeedURLs(ctx, uc.ID); err != nil {
		return nil, err
	}
	for show, u := range n.accountURLs {
		if pod := n.shows[show]; pod != nil && u != "" {
			n.account[gpodderShowKey(u)] = pod
		}
	}
	return n, nil
}

// learn indexes a show the catalog holds under its feed URL, and under the
// spelling it was first added by, which still names it after the catalog
// took up another.
func (n *gpodderNames) learn(pod *model.Podcast) {
	if !gpodderSyncs(pod) {
		return
	}
	n.shows[string(pod.PID)] = pod
	n.catalog[gpodderShowKey(pod.FeedURL)] = pod
	if strings.HasPrefix(pod.IdentityKey, "feed:") {
		if _, taken := n.keyed[pod.IdentityKey]; !taken {
			n.keyed[pod.IdentityKey] = pod
		}
	}
}

// device reads what a device calls each show, once per request; nil for
// no device.
func (n *gpodderNames) device(ctx context.Context, l *Library, uc *UserCtx, device string) (*gpodderDeviceNames, error) {
	if device == "" {
		return nil, nil
	}
	if d, ok := n.devices[device]; ok {
		return d, nil
	}
	urls, _, err := l.gpodderDeviceURLs(ctx, uc, device)
	if err != nil {
		return nil, err
	}
	d := &gpodderDeviceNames{byKey: make(map[string]*model.Podcast, len(urls)), byShow: urls}
	for show, u := range urls {
		if pod := n.shows[show]; pod != nil {
			d.byKey[gpodderShowKey(u)] = pod
		}
	}
	n.devices[device] = d
	return d, nil
}

// resolve answers the show a URL names for a device, nil for one only a
// fetch can tell.
func (n *gpodderNames) resolve(d *gpodderDeviceNames, feedURL string) *model.Podcast {
	key := gpodderShowKey(feedURL)
	if d != nil {
		if pod := d.byKey[key]; pod != nil {
			return pod
		}
	}
	for _, names := range []map[string]*model.Podcast{n.account, n.catalog, n.keyed} {
		if pod := names[key]; pod != nil {
			return pod
		}
	}
	return nil
}

// gpodderBatch is one request's view of the account, read once: the
// names of its shows, what the account follows, what the device holds
// and what the account has parked, with what the request settled so far
// and the refusals it has to say.
type gpodderBatch struct {
	uc     *UserCtx
	device string
	names  *gpodderNames
	// own is what the batch's device calls each show.
	own        *gpodderDeviceNames
	subscribed map[string]bool
	held       map[string]bool
	parked     map[string]bool
	// givenUp are the keys of the feeds whose park ran out its week in the
	// last month, which no ask parks again meanwhile.
	givenUp map[string]bool
	settled map[string]gpodderSettled
	notices []gpodderNotice
	// visible is whether the account can see the podcast library; one
	// that cannot lets go of nothing it follows.
	visible bool
}

// gpodderSettled is how one feed of a request turned out, so a request
// naming it again, in any spelling, resolves it once.
type gpodderSettled struct {
	outcome GpodderOutcome
	show    string
}

func (l *Library) gpodderBatch(ctx context.Context, uc *UserCtx, device string) (*gpodderBatch, error) {
	names, err := l.gpodderNames(ctx, uc)
	if err != nil {
		return nil, err
	}
	own, err := names.device(ctx, l, uc, device)
	if err != nil {
		return nil, err
	}
	b := &gpodderBatch{uc: uc, device: device, names: names, own: own,
		subscribed: make(map[string]bool, len(names.accountURLs)),
		held:       map[string]bool{}, parked: map[string]bool{}, settled: map[string]gpodderSettled{},
		visible: l.podcastsVisible(ctx, uc)}
	for show := range names.accountURLs {
		b.subscribed[show] = true
	}
	if device != "" {
		held, err := l.db.GpodderHeldBy(ctx, uc.ID, device)
		if err != nil {
			return nil, &Error{Kind: KindInternal, Err: err}
		}
		for _, show := range held {
			b.held[show] = true
		}
	}
	parks, err := l.db.GpodderParks(ctx, uc.ID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	for _, p := range parks {
		b.parked[p.FeedURL] = true
	}
	givenUp, err := l.db.GpodderNoticeFeeds(ctx, uc.ID, "", gpodderGaveUp, time.Now().Add(-gpodderNoticeWindow).UnixNano())
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	b.givenUp = make(map[string]bool, len(givenUp))
	for _, key := range givenUp {
		b.givenUp[key] = true
	}
	return b, nil
}

// resolve answers the show a URL names for the batch's device.
func (b *gpodderBatch) resolve(feedURL string) *model.Podcast { return b.names.resolve(b.own, feedURL) }

// calls records that the batch's device, and the account when its URL
// changed, now call a show by the URL an add attached it under.
func (b *gpodderBatch) calls(show, feedURL string, account bool) {
	key := gpodderShowKey(feedURL)
	pod := b.names.shows[show]
	if account {
		b.names.accountURLs[show] = feedURL
		if pod != nil {
			b.names.account[key] = pod
		}
	}
	if b.own != nil {
		b.own.byShow[show] = feedURL
		if pod != nil {
			b.own.byKey[key] = pod
		}
	}
}

// rememberDeviceURL records the URL the batch's device sent for a show as
// what it calls the show.
func (l *Library) rememberDeviceURL(ctx context.Context, b *gpodderBatch, show, feedURL string) error {
	if b.own == nil || b.own.byShow[show] == feedURL {
		return nil
	}
	if err := l.db.RememberGpodderDeviceURLs(ctx, b.uc.ID, b.device, []wdb.ShowURL{{ShowPID: show, FeedURL: feedURL}}); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	b.own.byShow[show] = feedURL
	if pod := b.names.shows[show]; pod != nil {
		b.own.byKey[gpodderShowKey(feedURL)] = pod
	}
	return nil
}

// forgetDeviceURL drops what the batch's device called a show it let go
// of, so a show the account follows again by another URL is told to it by
// that one.
func (l *Library) forgetDeviceURL(ctx context.Context, b *gpodderBatch, show string) error {
	if b.own == nil || b.own.byShow[show] == "" {
		return nil
	}
	if err := l.db.ForgetGpodderDeviceURL(ctx, b.uc.ID, b.device, show); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if pod := b.own.byKey[gpodderShowKey(b.own.byShow[show])]; pod != nil && string(pod.PID) == show {
		delete(b.own.byKey, gpodderShowKey(b.own.byShow[show]))
	}
	delete(b.own.byShow, show)
	return nil
}

// GpodderApplyChanges applies one device's incremental upload. An add is
// that device's hold on the show; a remove is a deliberate unsubscribe for
// the whole account, every hold on the show going with it. Each add's
// outcome comes back by its URL.
func (l *Library) GpodderApplyChanges(ctx context.Context, uc *UserCtx, device string, add, remove []string) (map[string]GpodderOutcome, error) {
	out := make(map[string]GpodderOutcome, len(add))
	if err := requirePodcastManagement(uc); err != nil {
		l.notifyGpodderRefusal(ctx, uc, device, err)
		for _, u := range add {
			out[u] = GpodderRefused
		}
		return out, nil
	}
	b, err := l.gpodderBatch(ctx, uc, device)
	if err != nil {
		return nil, err
	}
	defer func() { l.fileGpodderNotices(ctx, uc, b.notices) }()
	now := time.Now()
	landed := map[string]bool{}
	for _, u := range add {
		outcome, show, err := l.gpodderAdd(ctx, b, u, now)
		if err != nil {
			return nil, err
		}
		out[u] = outcome
		if outcome == GpodderLanded && show != "" {
			landed[show] = true
		}
	}
	for _, u := range remove {
		// A remove naming a show this change's add landed or kept is the
		// device moving the show to the add's address, which it calls the
		// show by now: the show stays.
		if pod := b.resolve(u); pod != nil && landed[string(pod.PID)] {
			if b.parked[u] {
				if err := l.dropPark(ctx, uc.ID, u); err != nil {
					return nil, err
				}
				delete(b.parked, u)
			}
			continue
		}
		if err := l.gpodderRemove(ctx, b, u); err != nil {
			return nil, err
		}
	}
	return out, nil
}

// GpodderReplaceDeviceList applies one device's full-list upload: it
// holds what the list names and lets go of what it held and no longer
// names by any URL. A show leaves the account only with its last hold, so
// what the apps or another device keep stays, and an empty or first-ever
// list removes nothing; nor does any list of an account that cannot see
// the podcast library, or one naming a feed that parks, since which show
// that feed is stays unknown until it lands and the next list decides.
func (l *Library) GpodderReplaceDeviceList(ctx context.Context, uc *UserCtx, device string, urls []string) (GpodderListResult, error) {
	res := GpodderListResult{Outcomes: make(map[string]GpodderOutcome, len(urls))}
	if err := requirePodcastManagement(uc); err != nil {
		l.notifyGpodderRefusal(ctx, uc, device, err)
		for _, u := range urls {
			res.Outcomes[u] = GpodderRefused
		}
		return res, nil
	}
	b, err := l.gpodderBatch(ctx, uc, device)
	if err != nil {
		return res, err
	}
	defer func() { l.fileGpodderNotices(ctx, uc, b.notices) }()
	now := time.Now()
	named := map[string]bool{}
	parked := false
	for _, u := range urls {
		outcome, show, err := l.gpodderAdd(ctx, b, u, now)
		if err != nil {
			return res, err
		}
		res.Outcomes[u] = outcome
		if show != "" {
			named[show] = true
		}
		parked = parked || outcome == GpodderParked
	}
	for show := range b.held {
		if named[show] || parked || !b.visible {
			continue
		}
		gone, err := l.releaseHold(ctx, uc, show, device)
		if err != nil {
			return res, err
		}
		if err := l.forgetDeviceURL(ctx, b, show); err != nil {
			return res, err
		}
		if gone {
			res.Released++
		}
	}
	// What the device parked and no longer lists, it no longer wants.
	if err := func() error {
		defer l.lockMembership(uc.ID)()
		return l.db.DropGpodderPendingFor(ctx, uc.ID, device, urls)
	}(); err != nil {
		return res, &Error{Kind: KindInternal, Err: err}
	}
	return res, nil
}

// dropPark withdraws every device's ask for one parked feed, under the
// account lock a retry's landing reads the park under.
func (l *Library) dropPark(ctx context.Context, userID, feedURL string) error {
	defer l.lockMembership(userID)()
	if err := l.db.DeleteGpodderPending(ctx, userID, feedURL); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// gpodderAdd lands one feed for the batch's device, answering the show it
// names, landed or not, when that is known without a fetch or a fetch
// told it. A show the URL names is attached without a fetch, unless it is
// private and the account does not follow it yet: then the fetch is what
// proves the account may have it. Attaching never respells the catalog;
// the account and the device call the show by the URL they sent. A parked
// feed is not fetched again: the device's ask joins the park, which keeps
// its schedule.
func (l *Library) gpodderAdd(ctx context.Context, b *gpodderBatch, feedURL string, now time.Time) (GpodderOutcome, string, error) {
	key := gpodderShowKey(feedURL)
	if done, ok := b.settled[key]; ok {
		return done.outcome, done.show, nil
	}
	pod := b.resolve(feedURL)
	show := ""
	if pod != nil {
		show = string(pod.PID)
	}
	settle := func(outcome GpodderOutcome) (GpodderOutcome, string, error) {
		b.settled[key] = gpodderSettled{outcome: outcome, show: show}
		return outcome, show, nil
	}
	meta := subChangeMeta{deviceID: b.device, failureLog: slog.LevelDebug}
	// What the account calls the show changes only by a fetch of the URL,
	// or when the account had no URL for it.
	respelled := pod == nil || !b.subscribed[show]
	var err error
	switch {
	case pod != nil && b.subscribed[show] && b.held[show] && !b.parked[feedURL]:
		if err := l.rememberDeviceURL(ctx, b, show, feedURL); err != nil {
			return "", "", err
		}
		return settle(GpodderLanded)
	case pod != nil && (b.subscribed[show] || !l.showIsPrivate(ctx, pod)):
		// Through subscribe, so what it checks of the account applies to
		// a show the catalog already holds as to a new one. A park of the
		// feed lands with it, for every device that asked.
		known := meta
		known.known = pod
		if b.parked[feedURL] {
			known.park = feedURL
		}
		_, _, err = l.subscribe(ctx, b.uc, SubscribeRequest{URL: feedURL}, known)
	default:
		if b.parked[feedURL] {
			joined, err := l.joinGpodderPark(ctx, b.uc.ID, feedURL, b.device, now)
			if err != nil {
				return "", "", err
			}
			if joined {
				return settle(GpodderParked)
			}
			// The park landed or went while this request decided, so this
			// is an add like any other.
			delete(b.parked, feedURL)
		}
		if b.givenUp[key] {
			// Its week of tries ran out lately, and the inbox said so: it is
			// neither fetched nor parked again until the month is over.
			return settle(GpodderRefused)
		}
		respelled = true
		var sub Subscription
		if sub, _, err = l.subscribe(ctx, b.uc, SubscribeRequest{URL: feedURL}, meta); err == nil {
			_, bare, _ := parseAPIPID(sub.Show.PID)
			show = string(bare)
			if landed, getErr := l.lib.Podcasts().Get(ctx, bare); getErr == nil {
				b.names.learn(landed)
			}
		}
	}
	if err != nil {
		outcome, notice, err := l.gpodderAddFailed(ctx, b.uc, feedURL, b.device, err, now)
		if err != nil {
			return "", "", err
		}
		if outcome == GpodderParked {
			b.parked[feedURL] = true
		}
		if notice != nil {
			b.notices = append(b.notices, *notice)
		}
		return settle(outcome)
	}
	b.subscribed[show], b.held[show] = true, true
	b.calls(show, feedURL, respelled)
	delete(b.parked, feedURL)
	return settle(GpodderLanded)
}

// joinGpodderPark adds the device's ask to a parked feed, under the
// account lock a retry's landing reads the asks under; false when the
// park is gone.
func (l *Library) joinGpodderPark(ctx context.Context, userID, feedURL, device string, now time.Time) (bool, error) {
	if testHookMembership != nil {
		testHookMembership("park")
	}
	defer l.lockMembership(userID)()
	joined, err := l.db.JoinGpodderPark(ctx, wdb.GpodderPending{
		UserID: userID, FeedURL: feedURL, DeviceID: device, CreatedAtNS: now.UnixNano(),
	})
	if err != nil {
		return false, &Error{Kind: KindInternal, Err: err}
	}
	return joined, nil
}

// errParkWithdrawn is a retry's landing of a parked feed that found no
// device asking for it any more.
var errParkWithdrawn = errors.New("no device asks for the parked feed any more")

// landingHolders is who holds a show an add attaches: the add's own
// device, and every device still asking for a parked feed it lands. An ask
// made no later than the account last left the show went with that
// leave, as asks for the show's known URLs did then. The caller holds the
// account lock.
func (l *Library) landingHolders(ctx context.Context, userID, show string, meta subChangeMeta) ([]string, error) {
	if meta.park == "" {
		return []string{meta.deviceID}, nil
	}
	asks, err := l.db.GpodderParkAsks(ctx, userID, meta.park)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	change, changed, err := l.db.GpodderShowChange(ctx, userID, show)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	var asking []string
	for _, a := range asks {
		if changed && change.Action == "remove" && a.CreatedAtNS/int64(time.Second) <= change.TsSec {
			continue
		}
		asking = append(asking, a.DeviceID)
	}
	if meta.parkOnly {
		if len(asking) == 0 {
			if len(asks) > 0 {
				if err := l.db.DeleteGpodderPending(ctx, userID, meta.park); err != nil {
					return nil, &Error{Kind: KindInternal, Err: err}
				}
			}
			return nil, errParkWithdrawn
		}
		return asking, nil
	}
	holders := []string{meta.deviceID}
	for _, device := range asking {
		if device != meta.deviceID {
			holders = append(holders, device)
		}
	}
	return holders, nil
}

// dropShowParks withdraws the account's parked asks for a show under any
// URL it is known by: the catalog's in either spelling, the account's,
// and its devices'. The caller holds the account lock.
func (l *Library) dropShowParks(ctx context.Context, userID string, pod *model.Podcast, accountURL string) error {
	parks, err := l.db.GpodderParks(ctx, userID)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if len(parks) == 0 {
		return nil
	}
	keys := map[string]bool{gpodderShowKey(pod.FeedURL): true}
	if strings.HasPrefix(pod.IdentityKey, "feed:") {
		keys[pod.IdentityKey] = true
	}
	known, err := l.db.GpodderShowDeviceURLs(ctx, userID, string(pod.PID))
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	for _, u := range append(known, accountURL) {
		if u != "" {
			keys[gpodderShowKey(u)] = true
		}
	}
	for _, p := range parks {
		if !keys[gpodderShowKey(p.FeedURL)] {
			continue
		}
		if err := l.db.DeleteGpodderPending(ctx, userID, p.FeedURL); err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
	}
	return nil
}

// gpodderRemove unsubscribes the account from the show a feed URL names,
// keeping its downloads, and drops a park of the feed. An unknown feed is
// a no-op: not subscribed is the state asked for. So is any feed for an
// account that cannot see the podcast library, whose shows wait for it.
func (l *Library) gpodderRemove(ctx context.Context, b *gpodderBatch, feedURL string) error {
	if b.parked[feedURL] {
		if err := l.dropPark(ctx, b.uc.ID, feedURL); err != nil {
			return err
		}
		delete(b.parked, feedURL)
	}
	pod := b.resolve(feedURL)
	if pod == nil || !b.visible {
		return nil
	}
	show := string(pod.PID)
	if err := l.forgetDeviceURL(ctx, b, show); err != nil {
		return err
	}
	delete(b.subscribed, show)
	delete(b.held, show)
	delete(b.settled, gpodderShowKey(feedURL))
	return l.unsubscribe(ctx, b.uc, apiPID(PrefixPodcast, pod.PID), false, subChangeMeta{deviceID: b.device})
}

// releaseHold lets go of one device's hold on a show; with the last hold
// gone the account leaves the show, as an unsubscribe would and keeping
// its downloads.
func (l *Library) releaseHold(ctx context.Context, uc *UserCtx, show, device string) (bool, error) {
	defer l.lockMembership(uc.ID)()
	gone, feedURL, err := l.db.ReleaseGpodderHold(ctx, uc.ID, show, device)
	if err != nil {
		return false, &Error{Kind: KindInternal, Err: err}
	}
	if !gone {
		return false, nil
	}
	if pod, err := l.lib.Podcasts().Get(ctx, model.PID(show)); err == nil {
		feedURL = gpodderEventURL(pod, feedURL)
	}
	l.afterSubscriptionChange(ctx, uc, show, feedURL, "remove", subChangeMeta{deviceID: device})
	return true, nil
}

// gpodderAddFailed settles an add that did not land: refused when asking
// again cannot change the answer or the account has no room to park it,
// parked for retries when it may; a refusal comes back with what the
// inbox will say about it. The park is written under the account lock a
// retry's landing reads the asks under.
func (l *Library) gpodderAddFailed(ctx context.Context, uc *UserCtx, feedURL, device string, err error, now time.Time) (GpodderOutcome, *gpodderNotice, error) {
	why, reason := subscribeFailure(err)
	if !gpodderAddCanPass(err) {
		// The inbox is the record of a refusal; the log keeps no line per
		// sync of it, and never the feed.
		l.log.Debug("gpodder add refused", "user", uc.ID, "device", device, "reason", cmp.Or(reason, string(KindOf(err))))
		if err := l.dropPark(ctx, uc.ID, feedURL); err != nil {
			return "", nil, err
		}
		return GpodderRefused, &gpodderNotice{feedURL: feedURL, device: device, why: why,
			account: gpodderRefusesEveryFeed(err), off: errors.Is(err, ErrPodcastsOff)}, nil
	}
	if testHookMembership != nil {
		testHookMembership("park")
	}
	parked, perr := func() (bool, error) {
		defer l.lockMembership(uc.ID)()
		return l.db.ParkGpodderPending(ctx, wdb.GpodderPending{
			UserID: uc.ID, FeedURL: feedURL, DeviceID: device, CreatedAtNS: now.UnixNano(),
			NextTryNS: now.Add(gpodderRetryDelay(0)).UnixNano(), LastError: cmp.Or(reason, string(KindOf(err))),
		}, gpodderPendingPerUser)
	}()
	if perr != nil {
		return "", nil, &Error{Kind: KindInternal, Err: perr}
	}
	if !parked {
		l.log.Warn("gpodder add refused: the account already has the most parked feeds this server keeps",
			"user", uc.ID, "device", device, "cap", gpodderPendingPerUser)
		return GpodderRefused, &gpodderNotice{feedURL: feedURL, device: device, why: fmt.Sprintf(
			"This account already has %d feeds waiting for another try, the most this server keeps; add this one again once some of them have landed.",
			gpodderPendingPerUser)}, nil
	}
	return GpodderParked, nil, nil
}

// giveUpGpodderPark drops the asks of a parked feed a retry read before
// its try, under the account lock an ask joins a park under, answering the
// notice to file for the first of them still standing, if any: an ask
// made since stays parked, and an expiry counts from the first ask still
// standing.
func (l *Library) giveUpGpodderPark(ctx context.Context, uc *UserCtx, feedURL string, read []wdb.GpodderPending, now time.Time, expiry bool, n gpodderNotice) *gpodderNotice {
	defer l.lockMembership(uc.ID)()
	asks, err := l.db.GpodderParkAsks(ctx, uc.ID, feedURL)
	if err != nil {
		l.log.Warn("reading a parked gpodder feed", "err", err)
		return nil
	}
	var standing []wdb.GpodderPending
	for _, a := range asks {
		if slices.ContainsFunc(read, func(r wdb.GpodderPending) bool {
			return r.DeviceID == a.DeviceID && r.CreatedAtNS == a.CreatedAtNS
		}) {
			standing = append(standing, a)
		}
	}
	if len(standing) == 0 || (expiry && now.Sub(time.Unix(0, standing[0].CreatedAtNS)) < gpodderPendingLifetime) {
		return nil
	}
	if err := l.db.DropGpodderParkAsks(ctx, uc.ID, feedURL, standing); err != nil {
		l.log.Warn("dropping a parked gpodder feed", "err", err)
		return nil
	}
	if expiry {
		gaveUp := wdb.GpodderNotice{FeedKey: gpodderShowKey(feedURL), Reason: gpodderGaveUp}
		if err := l.db.NoteGpodderNotices(ctx, uc.ID, []wdb.GpodderNotice{gaveUp}, now.UnixNano()); err != nil {
			l.log.Warn("noting a gpodder feed given up", "err", err)
		}
	}
	n.device = standing[0].DeviceID
	return &n
}

// gpodderGaveUp is what the account is told, by no device, of a feed whose
// park ran out its week: an ask of it in the month after is refused rather
// than parked again, so a list naming it still lets go of what it no
// longer names.
const gpodderGaveUp = "gave up"

// gpodderAddCanPass reports whether asking again later can land an add
// that failed now: a host's error or a host out of reach can pass, and so
// can the server's own trouble; a feed the server will not take, a host
// that refuses or has nothing there, a refusal of the account, and
// podcasts being off on this server cannot.
func gpodderAddCanPass(err error) bool {
	if reason := FeedFailureReason(err); reason != "" {
		return !feedReasonPermanent(reason)
	}
	switch KindOf(err) {
	case KindForbidden, KindInvalid, KindFeature:
		return false
	}
	return true
}

// gpodderRefusesEveryFeed reports a refusal the account is told of once
// rather than per feed: of the account, or of podcasts on this server.
func gpodderRefusesEveryFeed(err error) bool {
	kind := KindOf(err)
	return kind == KindForbidden || kind == KindFeature
}

// gpodderNotice is one failed add the account's inbox is to say.
type gpodderNotice struct {
	feedURL, device, why string
	// expired marks a parked feed whose week of tries ran out.
	expired bool
	// account marks a refusal of every feed rather than of this one (of
	// the account, or of podcasts on this server), said once for all;
	// off marks it as podcasts being turned off on this server.
	account, off bool
	// changes marks a refusal of every change the device asked for.
	changes bool
}

// said is what the account, once told of the notice, is not told of again
// for a month: the device, the feed by its key (none for a refusal of the
// account) and why.
func (n gpodderNotice) said() wdb.GpodderNotice {
	switch {
	case n.changes:
		return wdb.GpodderNotice{DeviceID: n.device, Reason: "changes: " + n.why}
	case n.account:
		return wdb.GpodderNotice{DeviceID: n.device, Reason: "account: " + n.why}
	case n.expired:
		return wdb.GpodderNotice{DeviceID: n.device, FeedKey: gpodderShowKey(n.feedURL), Reason: "expired: " + n.why}
	}
	return wdb.GpodderNotice{DeviceID: n.device, FeedKey: gpodderShowKey(n.feedURL), Reason: n.why}
}

// text is the notice's inbox row, the device named as given. It names a
// feed by its host and never by its URL, whose credentials, path or query
// can be the feed's own secret, and the reason the same way.
func (n gpodderNotice) text(device string) (title, body string) {
	why := hostOnly(n.why)
	switch {
	case n.changes:
		return "Podcasts not changed", fmt.Sprintf("%s asked to change this account's podcast subscriptions. %s", device, why)
	case n.off:
		return "Podcasts not added", fmt.Sprintf("%s asked to subscribe to podcasts, which are turned off on this server.", device)
	case n.account:
		return "Podcasts not added", fmt.Sprintf("%s asked to subscribe to podcasts this account cannot have. %s", device, why)
	}
	host := gpodderNoticeHost(n.feedURL)
	failed := "which was not added"
	if n.expired {
		failed = "which still could not be fetched a week later and was not added"
	}
	return "Podcast not added: " + host, fmt.Sprintf("%s asked to subscribe to the feed at %s, %s. %s", device, host, failed, why)
}

// gpodderNoticeHost is the host a notice names a feed by, or what it says
// of an address with none.
func gpodderNoticeHost(feedURL string) string {
	if u, err := url.Parse(feedURL); err == nil && u.Hostname() != "" {
		return truncateUTF8(u.Hostname(), gpodderMaxHostLen)
	}
	return "an address with no host"
}

// gpodderNoticesEach is how many failed adds one request, or one pass of
// retries, files a row of its own for; the rest are counted in one more.
const gpodderNoticesEach = 5

// fileGpodderNotices files what one request or one pass of retries could
// not land: the first few the account was not told of in the last month
// each in a row of its own, and the rest counted in one row, a feed once,
// so a list of a thousand dead feeds files a handful of rows and each
// later sync names a few more. What the account was told of, by device,
// feed and reason, takes no place among the few and is not told again for
// the month, whatever became of the inbox row that told it, which keeps a
// device that lists the feed on every sync from repeating it; the
// account's lock makes that check and the filing one step.
func (l *Library) fileGpodderNotices(ctx context.Context, uc *UserCtx, notices []gpodderNotice) {
	if len(notices) == 0 {
		return
	}
	defer l.lockMembership(uc.ID)()
	keys := make([]wdb.GpodderNotice, len(notices))
	for i, n := range notices {
		keys[i] = n.said()
	}
	now := time.Now()
	said, err := l.db.GpodderNoticesSaid(ctx, uc.ID, keys, now.Add(-gpodderNoticeWindow).UnixNano())
	if err != nil {
		l.log.Warn("reading what a gpodder notice said", "err", err)
		return
	}
	if testHookMembership != nil {
		testHookMembership("notice")
	}
	names := map[string]string{}
	name := func(device string) string {
		if n, ok := names[device]; ok {
			return n
		}
		n := l.gpodderDeviceName(ctx, uc, device)
		names[device] = n
		return n
	}
	var told []wdb.GpodderNotice
	named := 0
	rest, askers := map[string]bool{}, map[string]bool{}
	for i, n := range notices {
		if said[keys[i]] {
			continue
		}
		said[keys[i]] = true
		feed := !n.account && !n.changes
		if feed && named == gpodderNoticesEach {
			rest[keys[i].FeedKey], askers[n.device] = true, true
			continue
		}
		if feed {
			named++
		}
		title, body := n.text(name(n.device))
		l.EmitNotificationFor(ctx, "subscription-failed", title, body, "", []string{uc.ID})
		told = append(told, keys[i])
	}
	if len(rest) > 0 {
		asker := "This account's podcast apps"
		if len(askers) == 1 {
			for device := range askers {
				asker = name(device)
			}
		}
		more := fmt.Sprintf("%d more feeds that were not added", len(rest))
		if len(rest) == 1 {
			more = "1 more feed that was not added"
		}
		l.EmitNotificationFor(ctx, "subscription-failed", "Podcasts not added",
			fmt.Sprintf("%s asked to subscribe to %s.", asker, more), "", []string{uc.ID})
	}
	if err := l.db.NoteGpodderNotices(ctx, uc.ID, told, now.UnixNano()); err != nil {
		l.log.Warn("noting what a gpodder notice said", "err", err)
	}
}

// notifyGpodderRefusal files, once per device, that the account may not
// change its subscriptions, which every add and remove it sent would
// otherwise each say.
func (l *Library) notifyGpodderRefusal(ctx context.Context, uc *UserCtx, device string, err error) {
	why, _ := subscribeFailure(err)
	l.fileGpodderNotices(ctx, uc, []gpodderNotice{{device: device, why: why, changes: true}})
}

// gpodderDeviceName is how the inbox names a device: the caption it gave
// itself, else its id.
func (l *Library) gpodderDeviceName(ctx context.Context, uc *UserCtx, device string) string {
	if devs, err := l.db.GpodderDevicesByUser(ctx, uc.ID); err == nil {
		for _, d := range devs {
			if d.DeviceID == device && d.Caption != "" {
				return d.Caption
			}
		}
	}
	return cmp.Or(device, "A podcast app")
}

// --- episode actions -------------------------------------------------------------

// GpodderRecordActions stores one uploaded batch of episode actions,
// stamped with the second it is stored in, and writes their play
// positions through to WaxDeck's playback state, so a gpodder client's
// progress survives into the first-party apps. The log keeps each
// account's newest actions, each once. A stored batch is the client's no
// more: the write-through after it is best effort, uploads naming feeds
// and episodes WaxDeck may not carry, and what it meets is the log's to
// say, never the client's to retry.
func (l *Library) GpodderRecordActions(ctx context.Context, uc *UserCtx, actions []wdb.GpodderAction) error {
	now := time.Now()
	untimed := make([]bool, len(actions))
	for i := range actions {
		actions[i].UserID, actions[i].UploadedSec = uc.ID, now.Unix()
		if actions[i].ActionTS == "" {
			// The protocol's time is optional, and gPodder cannot read an
			// action back without one: it is stored at its upload's.
			actions[i].ActionTS, untimed[i] = now.UTC().Format(gpodderTimeLayout), true
		}
	}
	if testHookMembership != nil {
		testHookMembership("record")
	}
	ids, err := l.db.AppendGpodderActions(ctx, actions, gpodderActionsPerUser)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if testHookMembership != nil {
		testHookMembership("recorded")
	}
	if err := l.gpodderWriteThrough(ctx, uc, actions, ids, untimed); err != nil {
		// The kind only: an episode's URL can carry a feed's token.
		l.log.Warn("gpodder play write-through", "user", uc.ID, "kind", string(KindOf(err)))
	}
	return nil
}

// gpodderWriteThrough checkpoints the play actions of a stored batch, ids
// the rows that keep them and untimed those uploaded with no time, which
// land as live checkpoints. An account that cannot see the podcast library
// moves none of its episodes; the log keeps the actions for the grant's
// return.
func (l *Library) gpodderWriteThrough(ctx context.Context, uc *UserCtx, actions []wdb.GpodderAction, ids []int64, untimed []bool) error {
	if !l.podcastsVisible(ctx, uc) {
		return nil
	}
	var names *gpodderNames
	episodes := map[model.PID]map[string]*model.Episode{}
	for i, a := range actions {
		if a.Action != "play" || a.PositionSec == nil {
			continue
		}
		if names == nil {
			var err error
			if names, err = l.gpodderNames(ctx, uc); err != nil {
				return err
			}
		}
		if untimed[i] {
			a.ActionTS = ""
		}
		if err := l.gpodderApplyPlay(ctx, uc, names, episodes, a, ids[i]); err != nil {
			l.log.Warn("gpodder play write-through", "user", uc.ID, "kind", string(KindOf(err)))
		}
	}
	return nil
}

// gpodderApplyPlay checkpoints one play action's position on the episode
// it names, the show by the uploading device's URL for it or any other
// the account knows, and the episode by its enclosure, the newest of the
// show's when two share one. The action's time, when it has one, makes
// the checkpoint an offline replay, so the per-medium reconciliation
// applies; without one it lands as a live checkpoint. played and finished
// derive from the catalog's own episode duration.
func (l *Library) gpodderApplyPlay(ctx context.Context, uc *UserCtx, names *gpodderNames, episodes map[model.PID]map[string]*model.Episode, a wdb.GpodderAction, id int64) error {
	device, err := names.device(ctx, l, uc, a.DeviceID)
	if err != nil {
		return err
	}
	pod := names.resolve(device, a.PodcastURL)
	if pod == nil {
		return nil
	}
	byURL, ok := episodes[pod.PID]
	if !ok {
		eps, err := l.lib.Podcasts().Episodes(ctx, pod.PID, 0)
		if err != nil {
			return nil
		}
		// Newest first, so the first of an enclosure is its newest episode.
		byURL = make(map[string]*model.Episode, len(eps))
		for _, ep := range eps {
			if _, taken := byURL[ep.EnclosureURL]; !taken {
				byURL[ep.EnclosureURL] = ep
			}
		}
		episodes[pod.PID] = byURL
	}
	ep := byURL[a.EpisodeURL]
	if ep == nil {
		return nil
	}
	var recordedAt *time.Time
	if t, err := parseGpodderTime(a.ActionTS); err == nil {
		recordedAt = &t
	}
	// The protocol has no way to report a skipped replay, and a skip is a
	// success there as it is everywhere else. The change is the stored
	// action's, so the gpodder surface does not say it again as the
	// server's own while the log keeps that action.
	_, err = l.checkpoint(ctx, uc, apiPID(PrefixEpisode, ep.PID), *a.PositionSec*1000, recordedAt, playChange(id))
	return err
}

// gpodderTimeLayout is the protocol's timestamp: zoneless ISO 8601,
// read as UTC.
const gpodderTimeLayout = "2006-01-02T15:04:05"

// parseGpodderTime reads an action's timestamp, zoneless or RFC 3339.
func parseGpodderTime(s string) (time.Time, error) {
	if t, err := time.Parse(gpodderTimeLayout, s); err == nil {
		return t, nil
	}
	t, err := time.Parse(time.RFC3339, s)
	return t.UTC(), err
}

// NormalizeGpodderTime checks an uploaded action's timestamp and spells it
// the protocol's way; empty stays empty, and anything unreadable, before
// 2000 or more than a day ahead is an error.
func NormalizeGpodderTime(s string) (string, error) {
	if s == "" {
		return "", nil
	}
	t, err := parseGpodderTime(s)
	if err != nil {
		return "", errInvalid("timestamp " + strconv.Quote(s) + " is not an ISO 8601 time")
	}
	if t.Before(time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC)) || t.After(time.Now().Add(24*time.Hour)) {
		return "", errInvalid("timestamp " + strconv.Quote(s) + " is not a time an action can have")
	}
	return t.Format(gpodderTimeLayout), nil
}

// GpodderCursorLag is how far behind the clock every gpodder cursor
// trails. A change takes its stamp a moment before it counts as in
// flight, and a read answering a few seconds back loses none of them; a
// client that reads those seconds twice loses nothing.
const GpodderCursorLag = 5 * time.Second

// gpodderCursor is the cursor a read of the account starting now answers:
// the clock less the lag, and before the oldest write still in flight,
// however long that write waits for the writer.
func (l *Library) gpodderCursor(userID string) (cursor, clock int64) {
	return l.gpodderCursorAt(userID, time.Now())
}

// gpodderCursorAt is gpodderCursor for a read that started at at, clock
// its answer without the writes in flight.
func (l *Library) gpodderCursorAt(userID string, at time.Time) (cursor, clock int64) {
	clock = at.Add(-GpodderCursorLag).Unix()
	cursor = clock
	if sec, ok := l.db.GpodderWriteInFlight(userID); ok {
		cursor = min(cursor, sec-1)
	}
	return cursor, clock
}

// GpodderEpisodesUploadCursor is the timestamp an episodes upload that
// arrived at arrived answers, taken before the upload's own work. A
// client keeps it as the since of its next download, and the endpoint
// names no device, so it is no later than the lowest any episodes
// download signed in with the same app password answered in the last
// gpodderAnswersFor: a client that downloads, then uploads for a while,
// skips nothing another device stored meanwhile, and one stuck reading
// from a low point holds back no other client's answers. Nor is it later
// than the cursor of a read starting when the upload arrived. appPassword
// is the app password the request signed in with, directly or through
// the session its cookie names; "" keys the account's other reads.
func (l *Library) GpodderEpisodesUploadCursor(uc *UserCtx, appPassword string, arrived time.Time) int64 {
	cursor, _ := l.gpodderCursorAt(uc.ID, arrived)
	if read, ok := l.gpodderDownloads.lowest(gpodderReaderKey(uc, appPassword), time.Now()); ok {
		cursor = min(cursor, read)
	}
	return max(cursor, 0)
}

// gpodderReaderKey is what the episodes downloads of one client of the
// account are remembered by: its app password.
func gpodderReaderKey(uc *UserCtx, appPassword string) string {
	return uc.ID + " " + appPassword
}

// gpodderAnswersFor is how long an episodes upload answers no later than
// what a download answered: longer than any client's sync, which
// downloads and then uploads.
const gpodderAnswersFor = 10 * time.Minute

// gpodderAnswersKept bounds the answers one client keeps; past it the
// newest two merge into one, the lower answer kept the longer.
const gpodderAnswersKept = 64

// gpodderAnswer is one download's answer and when it was given.
type gpodderAnswer struct {
	cursor int64
	at     time.Time
}

// gpodderDownloads keeps, by client (gpodderReaderKey), what episodes
// downloads answered in the last gpodderAnswersFor, in memory: after a
// restart an upload answers by the clock until the next download. A
// client's answers are kept oldest first with rising cursors, each new
// answer dropping the later ones it is no higher than, so the first is
// the lowest.
type gpodderDownloads struct {
	mu   sync.Mutex
	held map[string][]gpodderAnswer
}

func (h *gpodderDownloads) note(key string, cursor int64, at time.Time) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.held == nil {
		h.held = map[string][]gpodderAnswer{}
	}
	for k := range h.held {
		h.expire(k, at)
	}
	kept := h.held[key]
	for len(kept) > 0 && kept[len(kept)-1].cursor >= cursor {
		kept = kept[:len(kept)-1]
	}
	kept = append(kept, gpodderAnswer{cursor: cursor, at: at})
	if n := len(kept); n > gpodderAnswersKept {
		kept[n-2].at = kept[n-1].at
		kept = kept[:n-1]
	}
	h.held[key] = kept
}

func (h *gpodderDownloads) lowest(key string, at time.Time) (int64, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if kept := h.expire(key, at); len(kept) > 0 {
		return kept[0].cursor, true
	}
	return 0, false
}

// expire drops a client's answers given gpodderAnswersFor or longer
// before at, and the client with its last. The caller holds mu.
func (h *gpodderDownloads) expire(key string, at time.Time) []gpodderAnswer {
	kept := h.held[key]
	for len(kept) > 0 && at.Sub(kept[0].at) >= gpodderAnswersFor {
		kept = kept[1:]
	}
	if len(kept) == 0 {
		delete(h.held, key)
	} else {
		h.held[key] = kept
	}
	return kept
}

// GpodderActionsSince lists the account's episode actions uploaded after
// sinceSec, oldest first, with the cursor the download answers: the
// stored actions, and play actions from device waxdeck for the positions
// the first-party apps moved, each naming its show by the account's URL
// for it. Filtering by podcast narrows both, the stored ones by the
// spelling they were uploaded with and the first-party ones by the show
// the URL names; filtering by any other device leaves the first-party
// ones out. An account that cannot see the podcast library reads none and
// is answered sinceSec back, so it skips nothing once the grant returns.
// The answer is remembered for the uploads of the same app password
// (GpodderEpisodesUploadCursor).
func (l *Library) GpodderActionsSince(ctx context.Context, uc *UserCtx, appPassword string, sinceSec int64, podcastURL, deviceID string) ([]wdb.GpodderAction, int64, error) {
	cursor, _ := l.gpodderCursor(uc.ID)
	reader := gpodderReaderKey(uc, appPassword)
	if !l.podcastsVisible(ctx, uc) {
		l.gpodderDownloads.note(reader, sinceSec, time.Now())
		return nil, sinceSec, nil
	}
	stored, err := l.db.GpodderActionsSince(ctx, uc.ID, sinceSec, podcastURL, deviceID)
	if err != nil {
		return nil, 0, &Error{Kind: KindInternal, Err: err}
	}
	var made []wdb.GpodderAction
	if deviceID == "" || deviceID == GpodderOwnDevice {
		var through int64
		made, through, err = l.gpodderFirstPartyPlays(ctx, uc, sinceSec, podcastURL, gpodderDownloadPaging)
		if err != nil {
			return nil, 0, err
		}
		if through > 0 {
			cursor = min(cursor, through)
		}
	}
	rows := append(stored, made...)
	sort.SliceStable(rows, func(i, j int) bool { return rows[i].UploadedSec < rows[j].UploadedSec })
	cursor = max(cursor, 0)
	l.gpodderDownloads.note(reader, cursor, time.Now())
	return rows, cursor, nil
}

// gpodderFirstPartyPlays reads the positions the server saw move after
// sinceSec as play actions: an episode of a show the account follows,
// with an enclosure a client can match and a known length, its position
// in whole seconds and at the end once finished. A change a stored gpodder
// action made is that action's to tell, however the server read it (a
// position past the end of the catalog's copy finishes the episode here),
// and is said here once the log has let the action go; the next change
// WaxDeck's own surfaces make is said.
// through is nonzero when the read stopped short of the present, the last
// second it covers whole.
func (l *Library) gpodderFirstPartyPlays(ctx context.Context, uc *UserCtx, sinceSec int64, podcastURL string, paging gpodderPaging) ([]wdb.GpodderAction, int64, error) {
	r := &gpodderPlayReader{l: l, uc: uc, shows: map[model.PID]gpodderPlayShow{}}
	if podcastURL != "" {
		names, err := l.gpodderNames(ctx, uc)
		if err != nil {
			return nil, 0, err
		}
		pod := names.resolve(nil, podcastURL)
		if pod == nil {
			return nil, 0, nil
		}
		r.wantShow = pod.PID
	}
	afterNS, afterPID := (sinceSec+1)*int64(time.Second), ""
	var out []wdb.GpodderAction
	for read := 0; ; {
		stamps, err := l.db.PositionStampsAfter(ctx, uc.ID, afterNS, afterPID, paging.page)
		if err != nil {
			return nil, 0, &Error{Kind: KindInternal, Err: err}
		}
		made, err := r.plays(ctx, stamps)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, made...)
		if len(stamps) < paging.page {
			return out, 0, nil
		}
		read += len(stamps)
		last := stamps[len(stamps)-1]
		afterNS, afterPID = last.SeenNS, last.ItemPID
		lastSec := last.SeenNS / int64(time.Second)
		whole := lastSec-1 > sinceSec
		switch {
		case read >= paging.budget && !whole:
			// Everything read sits in one second: answer it, the rest of
			// that second unsaid, rather than the same page for ever.
			return out, lastSec, nil
		case read >= paging.budget || (whole && len(out) >= paging.plays):
			return out, lastSec - 1, nil
		}
	}
}

// gpodderPlayReader turns pages of stamps into first-party play actions,
// keeping what it looked up across the pages of one download.
type gpodderPlayReader struct {
	l        *Library
	uc       *UserCtx
	wantShow model.PID
	// followed is the account's URL for each show it follows.
	followed map[string]string
	shows    map[model.PID]gpodderPlayShow
}

// gpodderPlayShow is what a show's plays need of it: the feed URL they
// name, "" for a show gpodder clients do not sync, and whether its links
// go out bare.
type gpodderPlayShow struct {
	feed string
	bare bool
}

func (r *gpodderPlayReader) plays(ctx context.Context, stamps []wdb.PositionStamp) ([]wdb.GpodderAction, error) {
	pids := make([]model.PID, 0, len(stamps))
	for _, st := range stamps {
		if !st.FromGpodder {
			pids = append(pids, model.PID(st.ItemPID))
		}
	}
	if len(pids) == 0 {
		return nil, nil
	}
	eps, err := r.l.lib.Podcasts().EpisodesByPIDs(ctx, pids)
	if err != nil {
		return nil, classify(err)
	}
	if len(eps) == 0 {
		return nil, nil
	}
	if r.followed == nil {
		if r.followed, err = r.l.accountFeedURLs(ctx, r.uc.ID); err != nil {
			return nil, err
		}
	}
	byPID := make(map[model.PID]*model.Episode, len(eps))
	statePIDs := make([]model.PID, 0, len(eps))
	for _, ep := range eps {
		if _, followed := r.followed[string(ep.PodcastPID)]; ep.EnclosureURL == "" || !followed {
			continue
		}
		byPID[ep.PID] = ep
		statePIDs = append(statePIDs, ep.PID)
	}
	if len(statePIDs) == 0 {
		return nil, nil
	}
	states, err := r.l.lib.PlayStatesForItems(ctx, statePIDs)
	if err != nil {
		return nil, classify(err)
	}
	var out []wdb.GpodderAction
	for _, st := range stamps {
		ep := byPID[model.PID(st.ItemPID)]
		if ep == nil || st.FromGpodder {
			continue
		}
		show := r.showOf(ctx, ep.PodcastPID)
		if show.feed == "" || (r.wantShow != "" && ep.PodcastPID != r.wantShow) {
			continue
		}
		episodeURL, guid := ep.EnclosureURL, ""
		if show.bare {
			if episodeURL, guid = bareEpisodeURL(ep.EnclosureURL), ep.GUID; episodeURL == "" {
				continue
			}
		}
		state := userPlayState(states[ep.PID], model.PID(r.uc.CatalogPID))
		if state == nil {
			continue
		}
		position, total, ok := gpodderPlayPosition(ep.DurationMS, state)
		if !ok {
			continue
		}
		seen := st.SeenNS / int64(time.Second)
		at := max(st.PositionNS, state.PlayedChangedAt)
		if at <= 0 {
			at = st.SeenNS
		}
		started := int64(0)
		out = append(out, wdb.GpodderAction{
			UserID: r.uc.ID, PodcastURL: show.feed, EpisodeURL: episodeURL, GUID: guid, DeviceID: GpodderOwnDevice,
			Action: "play", ActionTS: time.Unix(0, at).UTC().Format(gpodderTimeLayout),
			StartedSec: &started, PositionSec: &position, TotalSec: &total, UploadedSec: seen,
		})
	}
	return out, nil
}

// showOf is what a show's actions name it by, the account's own URL, and
// whether its links go out bare. The catalog fetched a show by the
// address of whoever added it last, so its links are that follower's: a
// private show's carry that follower's token, and another follower is told
// each episode by its guid and its link without query or login.
func (r *gpodderPlayReader) showOf(ctx context.Context, show model.PID) gpodderPlayShow {
	if s, ok := r.shows[show]; ok {
		return s
	}
	var s gpodderPlayShow
	if pod, err := r.l.lib.Podcasts().Get(ctx, show); err == nil && gpodderSyncs(pod) {
		own := r.followed[string(show)]
		s = gpodderPlayShow{feed: own, bare: own != pod.FeedURL && r.l.showIsPrivate(ctx, pod)}
	}
	r.shows[show] = s
	return s
}

// bareEpisodeURL is an episode link without its query, fragment or user
// info, "" for one that does not parse.
func bareEpisodeURL(raw string) string {
	u, err := url.Parse(raw)
	if err != nil {
		return ""
	}
	u.User, u.RawQuery, u.ForceQuery, u.Fragment, u.RawFragment = nil, "", false, "", ""
	return u.String()
}

// gpodderPlayPosition is where a play action puts the listener, in whole
// seconds, and the episode's length, the end once finished. ok is false
// for an episode of no known length, which a play action says nothing of:
// a client reads one without its total as no position at all.
func gpodderPlayPosition(durationMS int64, st *model.PlayState) (position, total int64, ok bool) {
	if durationMS <= 0 {
		return 0, 0, false
	}
	total = max(durationMS/1000, 1)
	position = st.PositionMS / 1000
	if st.Finished {
		position = total
	}
	return position, total, true
}

// --- device and event pass-throughs --------------------------------------------
//
// The gpodder tables live in the server DB; these wrappers exist so
// the adapter stays on the service layer like every other surface.

// GpodderUpsertDevice creates or updates one of the user's devices and
// stamps it seen. Empty caption or type leave the stored value unchanged;
// a fresh device with no type stores as "other". A device id runs to 128
// bytes and is never this server's own, and a caption is cut at 256.
//
// An account keeps 50 devices, and a new one past that takes the slot of
// the least recently seen that holds nothing; when all of them hold
// something, of the least recently seen of all, whose shows stay followed,
// and the inbox says which device went (the first few in a day by name).
func (l *Library) GpodderUpsertDevice(ctx context.Context, uc *UserCtx, deviceID, caption, devType string) error {
	if len(deviceID) > GpodderMaxDeviceIDLen {
		return errInvalid(fmt.Sprintf("a device id is at most %d bytes", GpodderMaxDeviceIDLen))
	}
	if deviceID == GpodderOwnDevice {
		return errInvalid(`the device id "` + GpodderOwnDevice + `" is this server's own`)
	}
	caption = truncateUTF8(caption, gpodderMaxCaptionLen)
	now := time.Now().UnixNano()
	evicted, err := l.db.RegisterGpodderDevice(ctx, wdb.GpodderDevice{
		UserID: uc.ID, DeviceID: deviceID, Caption: caption, Type: devType,
		CreatedAtNS: now, UpdatedAtNS: now,
	}, gpodderMaxDevices)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if evicted != nil {
		l.log.Info("gpodder device removed to make room", "user", uc.ID, "removed", evicted.DeviceID,
			"for", deviceID, "kept", evicted.Kept)
	}
	if evicted != nil && evicted.Held {
		l.noteGpodderEviction(ctx, uc, cmp.Or(caption, deviceID), evicted)
	}
	return nil
}

// noteGpodderEviction tells the account that a device which kept
// something made room for another: by name for the first few in a day,
// then once that more are going, so a client minting a device per launch
// files a handful of rows rather than one each.
func (l *Library) noteGpodderEviction(ctx context.Context, uc *UserCtx, newcomer string, evicted *wdb.GpodderEviction) {
	defer l.lockMembership(uc.ID)()
	filed, err := l.db.CountNotificationsSince(ctx, uc.ID, "gpodder-device-removed",
		time.Now().Add(-gpodderEvictionWindow).UnixNano())
	if err != nil {
		l.log.Warn("reading the inbox for a gpodder notice", "err", err)
		return
	}
	switch {
	case filed < gpodderEvictionsNamed:
		removed := cmp.Or(evicted.Caption, evicted.DeviceID)
		l.EmitNotificationFor(ctx, "gpodder-device-removed", "Podcast app removed: "+removed, fmt.Sprintf(
			"To make room for %s, %s, the least recently seen of this account's %d podcast app devices, was removed. What it kept followed stays followed.",
			newcomer, removed, gpodderMaxDevices), "", []string{uc.ID})
	case filed == gpodderEvictionsNamed:
		l.EmitNotificationFor(ctx, "gpodder-device-removed", "Podcast apps removed", fmt.Sprintf(
			"More of this account's %d podcast app devices are being removed, each to make room for a new one; what they kept followed stays followed. A day's first %d are named here, the rest are not.",
			gpodderMaxDevices, gpodderEvictionsNamed), "", []string{uc.ID})
	}
}

// GpodderSeeDevice stamps a registered device as seen, for a device that
// reads without uploading: least recently seen is what decides which
// device makes room for a new one.
func (l *Library) GpodderSeeDevice(ctx context.Context, uc *UserCtx, deviceID string) {
	if err := l.db.SeeGpodderDevice(ctx, uc.ID, deviceID, time.Now().UnixNano()); err != nil {
		l.log.Warn("stamping a gpodder device seen", "err", err)
	}
}

// GpodderDevices lists the user's devices.
func (l *Library) GpodderDevices(ctx context.Context, uc *UserCtx) ([]wdb.GpodderDevice, error) {
	devs, err := l.db.GpodderDevicesByUser(ctx, uc.ID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	return devs, nil
}

// GpodderDeviceExists reports whether the user has registered the
// device (explicitly or through an upload's auto-create).
func (l *Library) GpodderDeviceExists(ctx context.Context, uc *UserCtx, deviceID string) (bool, error) {
	ok, err := l.db.GpodderDeviceExists(ctx, uc.ID, deviceID)
	if err != nil {
		return false, &Error{Kind: KindInternal, Err: err}
	}
	return ok, nil
}

// GpodderSubChangesSince lists the user's subscription changes strictly
// after sinceSec, oldest first, with the cursor the delta answers: each
// show's latest, under the URL the device calls the show by, else the
// one the account does, or did when it left the show, never the
// catalog's. A device told a show is followed calls it by what it was
// told from then on. One told the account left a show lets go of what it
// called the show once it reads from past that: from the removal's
// second, or the answer of the read that told it when the removal falls
// in that answer's lag, whatever the log says of the show by then. An
// account that cannot see the podcast library reads none and is answered
// sinceSec back, so it skips nothing once the grant returns.
func (l *Library) GpodderSubChangesSince(ctx context.Context, uc *UserCtx, device string, sinceSec int64) ([]wdb.GpodderSubEvent, int64, error) {
	cursor, _ := l.gpodderCursor(uc.ID)
	if !l.podcastsVisible(ctx, uc) {
		return nil, sinceSec, nil
	}
	cursor = max(cursor, 0)
	own, removed, registered, err := l.gpodderReader(ctx, uc, device)
	if err != nil {
		return nil, 0, err
	}
	forget := false
	for show, at := range removed {
		if at <= sinceSec {
			delete(own, show)
			delete(removed, show)
			forget = true
		}
	}
	if forget {
		if err := l.db.ForgetRemovedGpodderDeviceURLs(ctx, uc.ID, device, sinceSec); err != nil {
			return nil, 0, &Error{Kind: KindInternal, Err: err}
		}
	}
	evs, err := l.db.GpodderSubEventsSince(ctx, uc.ID, sinceSec)
	if err != nil {
		return nil, 0, &Error{Kind: KindInternal, Err: err}
	}
	if len(evs) == 0 {
		return evs, cursor, nil
	}
	account, err := l.accountFeedURLs(ctx, uc.ID)
	if err != nil {
		return nil, 0, err
	}
	var told []wdb.ShowURL
	// A removal said under the device's URL marks it to go once the device
	// reads past the removal, and the show said again under it clears the
	// mark: the device never took the removal, and holds the URL still.
	var marks []wdb.GpodderDeviceURL
	// Two shows share a URL only when an address came to serve another
	// show; the device is told one change under it, a show the account
	// follows first.
	say := make(map[string]int, len(evs))
	for i := range evs {
		ev := &evs[i]
		u := own[ev.ShowPID]
		switch {
		case u == "":
			u = cmp.Or(account[ev.ShowPID], ev.FeedURL)
			if ev.Action == "add" {
				told = append(told, wdb.ShowURL{ShowPID: ev.ShowPID, FeedURL: u})
			}
		case ev.Action == "remove" && removed[ev.ShowPID] == 0:
			marks = append(marks, wdb.GpodderDeviceURL{ShowPID: ev.ShowPID, FeedURL: u, RemovedSec: max(min(ev.TsSec, cursor), 1)})
		case ev.Action == "add" && removed[ev.ShowPID] > 0:
			marks = append(marks, wdb.GpodderDeviceURL{ShowPID: ev.ShowPID, FeedURL: u})
		}
		ev.FeedURL = u
		if j, ok := say[u]; !ok || evs[j].Action != "add" || ev.Action == "add" {
			say[u] = i
		}
	}
	out := make([]wdb.GpodderSubEvent, 0, len(evs))
	for i, ev := range evs {
		if say[ev.FeedURL] == i {
			out = append(out, ev)
		}
	}
	if !registered {
		return out, cursor, nil
	}
	if testHookMembership != nil {
		testHookMembership("told")
	}
	if err := l.db.FillGpodderDeviceURLs(ctx, uc.ID, device, told); err != nil {
		return nil, 0, &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.MarkGpodderDeviceURLsRemoved(ctx, uc.ID, device, marks); err != nil {
		return nil, 0, &Error{Kind: KindInternal, Err: err}
	}
	return out, cursor, nil
}

// GpodderRememberRead keeps the cursor a device's subscription delta was
// answered, which GpodderUploadCursor gives back. A device nobody registered
// keeps none.
func (l *Library) GpodderRememberRead(ctx context.Context, uc *UserCtx, deviceID string, cursorSec int64) error {
	if err := l.db.SetGpodderDeviceCursor(ctx, uc.ID, deviceID, cursorSec); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// GpodderUploadCursor is the timestamp a device's subscription upload
// that arrived at arrived answers, taken before the upload's own work,
// which a client keeps as the since of its next delta, so it never passes
// what the device has read: the cursor its last delta answered (0 before
// it has read), no later than that of a read starting when the upload
// arrived.
func (l *Library) GpodderUploadCursor(ctx context.Context, uc *UserCtx, deviceID string, arrived time.Time) (int64, error) {
	read, err := l.db.GpodderDeviceCursor(ctx, uc.ID, deviceID)
	if err != nil {
		return 0, &Error{Kind: KindInternal, Err: err}
	}
	cursor, _ := l.gpodderCursorAt(uc.ID, arrived)
	return max(min(read, cursor), 0), nil
}
