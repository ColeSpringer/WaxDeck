package service

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"strings"
	"syscall"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/scrobble"
)

// Scrobbling service names on the wire and in storage.
const (
	ScrobblerLastfm       = "lastfm"
	ScrobblerListenBrainz = "listenbrainz"
)

// Scrobbler is one connection slot in the API shape.
type Scrobbler struct {
	Service       string
	Available     bool
	Connected     bool
	Username      string
	APIURL        string
	LastSuccessAt time.Time
	LastError     string
	LastErrorAt   time.Time
}

// Outbox delivery tuning. The horizon matches what the services accept
// (Last.fm rejects scrobbles much older than two weeks), and the
// backoff cap keeps multi-day outages cheap without losing listens.
const (
	scrobbleMaxAttempts   = 100
	scrobbleLeaseSeconds  = 120
	scrobbleHorizon       = 14 * 24 * time.Hour
	scrobbleBackoffCap    = 6 * time.Hour
	lastfmConnectStateTTL = 10 * time.Minute
)

// scrobbleHTTPClient is the outbound scrobbling client. The
// ListenBrainz API base is caller-supplied, so private destinations
// are refused at dial time (after DNS, defeating rebinding) like
// every other user-pointed fetch, unless the server opts LAN
// instances in.
func scrobbleHTTPClient(allowPrivate bool) *http.Client {
	dialer := &net.Dialer{Timeout: 10 * time.Second}
	if !allowPrivate {
		dialer.Control = func(network, address string, _ syscall.RawConn) error {
			return refusePrivateAddr(address)
		}
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.DialContext = dialer.DialContext
	return &http.Client{Transport: transport, Timeout: 15 * time.Second}
}

// hostResolvesPrivate reports whether a hostname or address literal
// resolves to a private address. Unresolvable names read as
// not-private: the dial-time guard still stands at fetch, this only
// shapes the write-time error.
func hostResolvesPrivate(host string) bool {
	if ip := net.ParseIP(host); ip != nil {
		return privateIP(ip)
	}
	if ips, err := net.LookupIP(host); err == nil {
		for _, ip := range ips {
			if privateIP(ip) {
				return true
			}
		}
	}
	return false
}

// ListScrobblers reports the caller's connection slots.
func (l *Library) ListScrobblers(ctx context.Context, uc *UserCtx) ([]Scrobbler, error) {
	conns, err := l.db.ScrobbleConnections(ctx, uc.ID)
	if err != nil {
		return nil, &Error{Kind: KindInternal, Err: err}
	}
	byService := map[string]wdb.ScrobbleConnection{}
	for _, c := range conns {
		byService[c.Service] = c
	}
	out := []Scrobbler{
		{Service: ScrobblerLastfm, Available: l.lastfmClient() != nil},
		{Service: ScrobblerListenBrainz, Available: true},
	}
	for i := range out {
		if c, ok := byService[out[i].Service]; ok {
			out[i].Connected = true
			out[i].Username = c.Username
			out[i].APIURL = c.APIURL
			if c.LastSuccessNS > 0 {
				out[i].LastSuccessAt = time.Unix(0, c.LastSuccessNS).UTC()
			}
			if c.LastError != "" {
				out[i].LastError = c.LastError
				out[i].LastErrorAt = time.Unix(0, c.LastErrorNS).UTC()
			}
		}
	}
	return out, nil
}

// ConnectListenBrainz validates and stores the caller's ListenBrainz
// token; a new token replaces the old one.
func (l *Library) ConnectListenBrainz(ctx context.Context, uc *UserCtx, token, apiURL string) (Scrobbler, error) {
	token = strings.TrimSpace(token)
	if token == "" {
		return Scrobbler{}, errInvalid("a token is required")
	}
	if apiURL != "" {
		u, err := url.Parse(apiURL)
		if err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" {
			return Scrobbler{}, errInvalid("apiUrl must be http or https")
		}
		// Write-time courtesy check with the friendly message; the
		// dial-time guard on the delivery client is the boundary.
		if !l.allowPrivateScrobbleHosts && hostResolvesPrivate(u.Hostname()) {
			return Scrobbler{}, errInvalid("apiUrl resolves to a private address; the server does not allow private scrobble hosts")
		}
	}
	username, err := l.listenbrainz.ValidateToken(ctx, apiURL, token)
	if err != nil {
		if scrobble.IsPermanent(err) {
			return Scrobbler{}, errInvalid("the service did not accept this token")
		}
		return Scrobbler{}, &Error{Kind: KindService, Msg: "the scrobbling service could not be reached to validate the token", Err: err}
	}
	if err := l.storeScrobbleConnection(ctx, uc.ID, ScrobblerListenBrainz, token, username, apiURL); err != nil {
		return Scrobbler{}, err
	}
	return Scrobbler{Service: ScrobblerListenBrainz, Available: true, Connected: true, Username: username, APIURL: apiURL}, nil
}

// DisconnectScrobbler removes the caller's connection to one service
// and drops its queued deliveries.
func (l *Library) DisconnectScrobbler(ctx context.Context, uc *UserCtx, service string) error {
	if err := l.db.DeleteScrobbleConnection(ctx, uc.ID, service); err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			return errNotFound(service + " is not connected")
		}
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// StartLastfmConnect mints a one-time state bound to the caller and
// returns the authorization URL. callbackURL is this server's callback
// endpoint, built by the API layer from the request origin; the state
// rides it as a query parameter and Last.fm appends the token.
func (l *Library) StartLastfmConnect(ctx context.Context, uc *UserCtx, callbackURL string) (string, error) {
	lastfm := l.lastfmClient()
	if lastfm == nil {
		return "", &Error{Kind: KindUnsupported, Msg: "this server has no Last.fm API credentials configured"}
	}
	buf := make([]byte, 24)
	if _, err := rand.Read(buf); err != nil {
		return "", &Error{Kind: KindInternal, Err: err}
	}
	state := base64.RawURLEncoding.EncodeToString(buf)
	// The OIDC state table stores this flow too: single use, expiring,
	// keyed by the opaque state. RedirectTo carries the user id.
	if err := l.db.PutOAuthState(ctx, wdb.OAuthState{
		State:      state,
		Provider:   ScrobblerLastfm,
		Mode:       "scrobble",
		RedirectTo: uc.ID,
		ExpiresAt:  time.Now().Add(lastfmConnectStateTTL),
	}); err != nil {
		return "", &Error{Kind: KindInternal, Err: err}
	}
	sep := "?"
	if strings.Contains(callbackURL, "?") {
		sep = "&"
	}
	return lastfm.AuthURL(callbackURL + sep + "state=" + url.QueryEscape(state)), nil
}

// CompleteLastfmConnect consumes the callback: the one-time state
// names the user, and the token exchanges for a session key stored
// sealed. Returns the linked username.
func (l *Library) CompleteLastfmConnect(ctx context.Context, state, token string) (string, error) {
	lastfm := l.lastfmClient()
	if lastfm == nil {
		return "", &Error{Kind: KindUnsupported, Msg: "this server has no Last.fm API credentials configured"}
	}
	st, err := l.db.TakeOAuthState(ctx, state)
	if err != nil || st.Provider != ScrobblerLastfm || st.Mode != "scrobble" || st.RedirectTo == "" {
		return "", errInvalid("unknown, expired, or already used authorization state")
	}
	sessionKey, username, err := lastfm.GetSession(ctx, token)
	if err != nil {
		if scrobble.IsPermanent(err) {
			return "", errInvalid("Last.fm did not accept the authorization")
		}
		return "", &Error{Kind: KindService, Msg: "Last.fm could not be reached to complete the exchange", Err: err}
	}
	if err := l.storeScrobbleConnection(ctx, st.RedirectTo, ScrobblerLastfm, sessionKey, username, ""); err != nil {
		return "", err
	}
	return username, nil
}

func (l *Library) storeScrobbleConnection(ctx context.Context, userID, service, secret, username, apiURL string) error {
	if l.sealer == nil {
		return &Error{Kind: KindInternal, Msg: "no sealing key is configured"}
	}
	sealed, err := l.sealer.Seal([]byte(secret))
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	now := time.Now().UnixNano()
	if err := l.db.UpsertScrobbleConnection(ctx, wdb.ScrobbleConnection{
		UserID:       userID,
		Service:      service,
		SealedSecret: sealed,
		Username:     username,
		APIURL:       apiURL,
		CreatedAtNS:  now,
		UpdatedAtNS:  now,
	}); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

// enqueueScrobbles queues one accepted music listen for every service
// the user has connected. Failures log and never fail the ingest; the
// listen itself is already durable.
func (l *Library) enqueueScrobbles(ctx context.Context, uc *UserCtx, it *model.ItemView, startedAt time.Time) {
	conns, err := l.db.ScrobbleConnections(ctx, uc.ID)
	if err != nil {
		l.log.Warn("reading scrobble connections", "err", err)
		return
	}
	if len(conns) == 0 {
		return
	}
	now := time.Now().UnixNano()
	for _, c := range conns {
		row := wdb.ScrobbleRow{
			UserID:       uc.ID,
			Service:      c.Service,
			ItemPID:      string(it.PID),
			Artist:       it.Artist,
			Title:        it.Title,
			Album:        it.Album,
			DurationMS:   it.DurationMS,
			ListenedAtNS: startedAt.UnixNano(),
		}
		if err := l.db.EnqueueScrobble(ctx, row, now); err != nil {
			l.log.Warn("queuing scrobble", "service", c.Service, "err", err)
		}
	}
}

// NowPlayingScrobble pushes a best-effort now-playing update to the
// caller's connected services. Nothing is queued: now playing is
// ephemeral by definition.
func (l *Library) NowPlayingScrobble(ctx context.Context, uc *UserCtx, apiItemPID string) error {
	it, err := l.getVisibleItem(ctx, uc, apiItemPID)
	if err != nil {
		return err
	}
	if it.Kind != model.KindTrack {
		return nil
	}
	conns, err := l.db.ScrobbleConnections(ctx, uc.ID)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	track := scrobble.Track{Artist: it.Artist, Title: it.Title, Album: it.Album, DurationMS: it.DurationMS}
	callCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	for _, c := range conns {
		secret, err := l.openScrobbleSecret(c)
		if err != nil {
			l.log.Warn("opening scrobble secret", "service", c.Service, "err", err)
			continue
		}
		switch c.Service {
		case ScrobblerLastfm:
			lastfm := l.lastfmClient()
			if lastfm == nil {
				continue
			}
			if err := lastfm.NowPlaying(callCtx, secret, track); err != nil {
				l.log.Debug("now-playing update failed", "service", c.Service, "err", err)
			}
		case ScrobblerListenBrainz:
			if err := l.listenbrainz.Submit(callCtx, c.APIURL, secret, track); err != nil {
				l.log.Debug("now-playing update failed", "service", c.Service, "err", err)
			}
		}
	}
	return nil
}

// DrainScrobbleOutbox delivers one queued scrobble; false when idle.
func (l *Library) DrainScrobbleOutbox(ctx context.Context) bool {
	now := time.Now().UnixNano()
	row, err := l.db.LeaseScrobble(ctx, now, int64(scrobbleLeaseSeconds)*int64(time.Second), scrobbleMaxAttempts)
	if err != nil {
		if !errors.Is(err, wdb.ErrNotFound) {
			l.log.Warn("leasing scrobble", "err", err)
		}
		return false
	}
	if err := l.deliverScrobble(ctx, row); err != nil {
		l.markScrobbleHealth(ctx, row, err)
		if scrobble.IsPermanent(err) {
			l.log.Warn("scrobble rejected permanently", "service", row.Service, "err", err)
			if err := l.db.DropScrobble(ctx, row.ID); err != nil {
				l.log.Warn("dropping rejected scrobble", "err", err)
			}
			return true
		}
		retryAt := time.Now().Add(queueRetryDelayCapped(row.Attempts, scrobbleBackoffCap)).UnixNano()
		if err := l.db.FailScrobble(ctx, row.ID, err.Error(), retryAt); err != nil {
			l.log.Warn("failing scrobble", "err", err)
		}
		return true
	}
	l.markScrobbleHealth(ctx, row, nil)
	if err := l.db.CompleteScrobble(ctx, row.ID); err != nil {
		l.log.Warn("completing scrobble", "err", err)
	}
	return true
}

// markScrobbleHealth records a delivery outcome on the row's
// connection so the settings surface can show why scrobbles are not
// arriving (a revoked session key would otherwise fail silently). A
// disconnected-since-queuing row matches no connection and records
// nothing.
func (l *Library) markScrobbleHealth(ctx context.Context, row wdb.ScrobbleRow, deliveryErr error) {
	msg := ""
	if deliveryErr != nil {
		msg = clipHealthMessage(deliveryErr.Error())
	}
	if err := l.db.MarkScrobbleDelivery(ctx, row.UserID, row.Service, deliveryErr == nil, msg, time.Now().UnixNano()); err != nil {
		l.log.Warn("marking scrobble delivery", "err", err)
	}
}

// deliverScrobble sends one row to its service.
func (l *Library) deliverScrobble(ctx context.Context, row wdb.ScrobbleRow) error {
	conn, err := l.db.ScrobbleConnectionFor(ctx, row.UserID, row.Service)
	if err != nil {
		if errors.Is(err, wdb.ErrNotFound) {
			// Disconnected since queuing; nothing to deliver to.
			return &scrobble.Permanent{Err: errors.New("connection removed")}
		}
		return err
	}
	secret, err := l.openScrobbleSecret(conn)
	if err != nil {
		return &scrobble.Permanent{Err: err}
	}
	track := scrobble.Track{
		Artist:     row.Artist,
		Title:      row.Title,
		Album:      row.Album,
		DurationMS: row.DurationMS,
		ListenedAt: row.ListenedAtNS / int64(time.Second),
	}
	callCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	switch row.Service {
	case ScrobblerLastfm:
		lastfm := l.lastfmClient()
		if lastfm == nil {
			return errors.New("no Last.fm API credentials configured")
		}
		return lastfm.Scrobble(callCtx, secret, track)
	case ScrobblerListenBrainz:
		return l.listenbrainz.Submit(callCtx, conn.APIURL, secret, track)
	}
	return &scrobble.Permanent{Err: fmt.Errorf("unknown scrobble service %s", row.Service)}
}

// PruneScrobbleOutbox drops rows past the delivery horizon or out of
// attempts.
func (l *Library) PruneScrobbleOutbox(ctx context.Context) {
	cutoff := time.Now().Add(-scrobbleHorizon).UnixNano()
	if n, err := l.db.PruneScrobbleOutbox(ctx, cutoff, scrobbleMaxAttempts); err != nil {
		l.log.Warn("pruning scrobble outbox", "err", err)
	} else if n > 0 {
		l.log.Info("pruned scrobble outbox", "rows", n)
	}
}

func (l *Library) openScrobbleSecret(c wdb.ScrobbleConnection) (string, error) {
	if l.sealer == nil {
		return "", errors.New("no sealing key is configured")
	}
	pt, err := l.sealer.Open(c.SealedSecret)
	if err != nil {
		return "", err
	}
	return string(pt), nil
}

// queueRetryDelayCapped is the shared exponential backoff with a
// caller-chosen ceiling.
func queueRetryDelayCapped(attempts int, cap time.Duration) time.Duration {
	d := time.Minute
	for i := 0; i < attempts && d < cap; i++ {
		d *= 2
	}
	if d > cap {
		d = cap
	}
	return d
}
