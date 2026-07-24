package service

// Service-layer support for the gpodder compatibility adapter: Basic
// authentication against app passwords, the subscription bridges that
// key on feed URLs instead of PIDs, the playback write-through for
// uploaded play actions, and thin pass-throughs to the adapter's own
// device and event tables. The adapter sits above the ownership line
// and calls only these methods; every catalog access happens here.

import (
	"context"
	"crypto/subtle"
	"errors"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// VerifyAppPasswordBasic authenticates the HTTP Basic scheme: username
// plus an app password secret presented in the clear. The login
// password never works here. It returns the account, or nil on any
// failure (unknown user, disabled account, no matching password),
// never distinguishing them; the secret comparison is constant time
// per candidate.
func (l *Library) VerifyAppPasswordBasic(ctx context.Context, username, password string) (*wdb.User, error) {
	u, err := l.db.UserByUsername(ctx, username)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, nil
		}
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if u.Disabled {
		return nil, nil
	}
	for _, entry := range l.userAppSecrets(ctx, u.ID) {
		if subtle.ConstantTimeCompare([]byte(entry.secret), []byte(password)) == 1 {
			l.touchAppPassword(ctx, entry)
			return u, nil
		}
	}
	return nil, nil
}

// GpodderSessionUser resolves a validated session cookie's username to
// its account: nil when the account is unknown or disabled (the cookie
// may outlive the account).
func (l *Library) GpodderSessionUser(ctx context.Context, username string) (*wdb.User, error) {
	u, err := l.db.UserByUsername(ctx, username)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return nil, nil
		}
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	if u.Disabled {
		return nil, nil
	}
	return u, nil
}

// GpodderFeedURLs returns the feed URL of every subscription the user
// holds, INCLUDING private shows. The first-party OPML export
// withholds private feed URLs, but gpodder sync is a per-user
// credentialed surface serving the subscriber's own list back to them,
// and clients like AntennaPod cannot sync a show at all without its
// URL; the deliberate decision is that the owning subscriber always
// sees their own private feed URLs here. Manual shows have no feed to
// sync and are skipped.
func (l *Library) GpodderFeedURLs(ctx context.Context, uc *UserCtx) ([]string, error) {
	rows, err := l.db.SubscriptionsByUser(ctx, uc.ID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	out := make([]string, 0, len(rows))
	for _, row := range rows {
		pod, err := l.lib.Podcasts().Get(ctx, model.PID(row.ShowPID))
		if err != nil {
			// A show removed out from under a subscription row is a
			// dangling reference; tolerate and skip.
			continue
		}
		if pod.SourceType == model.SourceManual || pod.FeedURL == "" {
			continue
		}
		out = append(out, pod.FeedURL)
	}
	return out, nil
}

// GpodderSubscribe subscribes the user to a feed URL, recording the
// originating device on the change event.
func (l *Library) GpodderSubscribe(ctx context.Context, uc *UserCtx, feedURL, deviceID string) error {
	_, _, err := l.subscribe(ctx, uc, SubscribeRequest{URL: feedURL}, subChangeMeta{deviceID: deviceID})
	return err
}

// GpodderUnsubscribe removes the user's subscription to a feed URL,
// recording the originating device. An unknown feed is a no-op: the
// end state (not subscribed) already holds.
func (l *Library) GpodderUnsubscribe(ctx context.Context, uc *UserCtx, feedURL, deviceID string) error {
	pod, err := l.podcastByFeedURL(ctx, feedURL)
	if err != nil {
		return err
	}
	if pod == nil {
		return nil
	}
	// A sync protocol never destroys server data: gpodder
	// unsubscribes always keep downloaded files.
	return l.unsubscribe(ctx, uc, apiPID(PrefixPodcast, pod.PID), false, subChangeMeta{deviceID: deviceID})
}

// GpodderApplyPlay writes an uploaded play action's position through
// to WaxDeck playback state. Everything about it is best effort:
// gpodder uploads reference feeds and episodes WaxDeck may not carry,
// and an unmatched action must never fail the batch, so unknown shows
// and episodes return nil silently. The action timestamp, when
// parseable, makes the checkpoint an offline replay so the per-medium
// reconciliation applies; without one it lands as a live checkpoint.
// totalSec rides along for signature completeness; played and finished
// derive from the catalog's own episode duration.
func (l *Library) GpodderApplyPlay(ctx context.Context, uc *UserCtx, podcastURL, episodeURL string, positionSec, totalSec *int64, actionTS string) error {
	if positionSec == nil {
		return nil
	}
	pod, err := l.podcastByFeedURL(ctx, podcastURL)
	if err != nil || pod == nil {
		return nil
	}
	eps, err := l.lib.Podcasts().Episodes(ctx, pod.PID, 0)
	if err != nil {
		return nil
	}
	for _, ep := range eps {
		if ep.EnclosureURL != episodeURL {
			continue
		}
		var recordedAt *time.Time
		if actionTS != "" {
			// gpodder timestamps are zoneless ISO 8601, treated as UTC;
			// an unparseable one degrades to live-checkpoint semantics.
			if t, perr := time.Parse("2006-01-02T15:04:05", actionTS); perr == nil {
				recordedAt = &t
			}
		}
		// The gpodder protocol has no way to report a skipped replay,
		// and a skip is a success there as it is everywhere else.
		_, err := l.Checkpoint(ctx, uc, apiPID(PrefixEpisode, ep.PID), *positionSec*1000, recordedAt)
		return err
	}
	return nil
}

// podcastByFeedURL resolves a cataloged show by exact feed URL, nil
// when the catalog does not carry it.
func (l *Library) podcastByFeedURL(ctx context.Context, feedURL string) (*model.Podcast, error) {
	pods, err := l.lib.Podcasts().List(ctx)
	if err != nil {
		return nil, classify(err)
	}
	for _, pod := range pods {
		if pod.FeedURL == feedURL {
			return pod, nil
		}
	}
	return nil, nil
}

// --- device and event pass-throughs --------------------------------------------
//
// The gpodder tables live in the server DB; these wrappers exist so
// the adapter stays on the service layer like every other surface.

// GpodderUpsertDevice creates or updates one of the user's devices.
// Empty caption or type leave the stored value unchanged; a fresh
// device with no type stores as "other".
func (l *Library) GpodderUpsertDevice(ctx context.Context, uc *UserCtx, deviceID, caption, devType string) error {
	now := time.Now().UnixNano()
	err := l.db.UpsertGpodderDevice(ctx, wdb.GpodderDevice{
		UserID: uc.ID, DeviceID: deviceID, Caption: caption, Type: devType,
		CreatedAtNS: now, UpdatedAtNS: now,
	})
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
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

// GpodderSubChangesSince lists the user's subscription change events
// strictly after sinceSec, oldest first.
func (l *Library) GpodderSubChangesSince(ctx context.Context, uc *UserCtx, sinceSec int64) ([]wdb.GpodderSubEvent, error) {
	evs, err := l.db.GpodderSubEventsSince(ctx, uc.ID, sinceSec)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	return evs, nil
}

// GpodderAppendAction stores one uploaded episode action for the user;
// the caller's identity overrides whatever the record carries.
func (l *Library) GpodderAppendAction(ctx context.Context, uc *UserCtx, a wdb.GpodderAction) error {
	a.UserID = uc.ID
	if err := l.db.AppendGpodderAction(ctx, a); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// GpodderActionsSince lists the user's stored episode actions strictly
// after sinceSec (upload time), oldest first, optionally filtered by
// feed URL and device.
func (l *Library) GpodderActionsSince(ctx context.Context, uc *UserCtx, sinceSec int64, podcastURL, deviceID string) ([]wdb.GpodderAction, error) {
	rows, err := l.db.GpodderActionsSince(ctx, uc.ID, sinceSec, podcastURL, deviceID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	return rows, nil
}
