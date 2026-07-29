package service

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/url"
	"strings"
	"syscall"
	"time"

	"github.com/colespringer/waxbin/model"
)

// ErrEpisodeNotFetched marks the conflict an unfetched podcast episode
// answers from StreamSource and DirectPlayInfo. The URL-minting call
// sites match on it to fall back to enclosure passthrough; the kind and
// message are unchanged, so a caller that does not match still sees the
// same typed conflict it always did.
var ErrEpisodeNotFetched = errors.New("episode audio is not fetched to the server")

// EnclosureSource is what passthrough needs to relay one unfetched
// episode: the feed's enclosure URL and the facts play-info reports
// about it. The feed's declared enclosure size is deliberately absent;
// see the relay handler for why it is not used as a Content-Length.
//
// AuthUser and AuthPass carry the show's stored feed credentials when
// the caller is entitled to them; both empty means an open feed, or a
// caller this server will not spend the credentials on.
type EnclosureSource struct {
	URL        string
	MimeType   string
	DurationMS int64
	AuthUser   string
	AuthPass   string
}

// EnclosureStreamSource resolves an episode PID to its feed enclosure,
// for the passthrough relay and for the play-info that points at it.
//
// The URL comes from the catalog, never from the request. That is what
// keeps /media/enclosure from being an open proxy: a caller who holds a
// media token for an episode can reach that episode's enclosure and
// nothing else. Visibility is gated where the URL is minted, the same
// place it is gated for /media/download.
//
// userID identifies the listener, for the credential rule below; it is
// the media token's subject at the relay and the caller at every mint.
func (l *Library) EnclosureStreamSource(ctx context.Context, userID, apiEpisodePID string) (EnclosureSource, error) {
	det, err := l.getEpisode(ctx, apiEpisodePID)
	if err != nil {
		return EnclosureSource{}, err
	}
	ep := det.Episode
	raw := strings.TrimSpace(ep.EnclosureURL)
	if raw == "" {
		return EnclosureSource{}, errNotFound("episode " + apiEpisodePID + " has no enclosure to stream")
	}
	if !streamableEnclosure(raw) {
		return EnclosureSource{}, errNotFound("episode " + apiEpisodePID + " has no streamable enclosure")
	}
	mime := strings.TrimSpace(ep.EnclosureType)
	if mime == "" {
		mime = "audio/mpeg"
	}
	out := EnclosureSource{
		URL:        raw,
		MimeType:   mime,
		DurationMS: ep.DurationMS,
	}
	user, pass, err := l.feedCredentials(ctx, userID, ep.PodcastPID)
	if err != nil {
		return EnclosureSource{}, err
	}
	out.AuthUser, out.AuthPass = user, pass
	return out, nil
}

// streamableEnclosure reports whether a feed's enclosure URL is one the
// relay can actually fetch: present, and http or https.
//
// Only those two schemes relay. A feed carrying anything else is
// malformed, and refusing here keeps the scheme set the guarded client
// assumes from depending on what a feed said. Protocol-relative URLs
// (`//cdn.example/ep.mp3`) land here too: they parse cleanly with an
// empty scheme and do occur in real feeds.
//
// This is the single rule behind both the resolver and the
// `hasEnclosure` an episode row reports, so a client is never told an
// episode is playable by a rule the relay does not share.
func streamableEnclosure(rawURL string) bool {
	raw := strings.TrimSpace(rawURL)
	if raw == "" {
		return false
	}
	u, err := url.Parse(raw)
	return err == nil && (u.Scheme == "http" || u.Scheme == "https")
}

// feedCredentials resolves the show's stored basic-auth credentials for
// one listener, empty for an open feed.
//
// A private or paid feed refuses an unauthenticated GET, so passthrough
// without these is a 401 where fetching the same episode works: WaxBin's
// download passes the same pair, and so does the transcript fetch. This
// is what keeps the two paths at parity.
//
// The credentials are the show's, not the user's, and any subscriber
// shares them, which is how they got there. But they are spent only for
// a caller who subscribes: an episode read stays open to anyone who can
// see the podcast library, so without this check any account on the
// server could stream a paid feed on the strength of somebody else's
// subscription. A non-subscriber gets the same refusal an open feed's
// listener would never see, rather than a confusing 401 relayed from a
// host they cannot authenticate to.
func (l *Library) feedCredentials(ctx context.Context, userID string, showPID model.PID) (string, string, error) {
	pod, err := l.lib.Podcasts().Get(ctx, showPID)
	if err != nil || pod.AuthUser == "" {
		// A show that cannot be read is not a credential failure; the
		// enclosure fetch reports whatever the host says about it.
		return "", "", nil
	}
	// Bare catalog pid, which is what the subscriptions table keys on.
	if _, err := l.db.SubscriptionFor(ctx, userID, string(showPID)); err != nil {
		return "", "", &Error{Kind: KindForbidden,
			Msg: "this show's feed needs credentials, which are only used for its own subscribers; subscribe to stream it"}
	}
	pass, err := l.lib.GetSecret(ctx, "podcast.auth."+string(pod.PID))
	if err != nil {
		// Configured for auth with no stored secret: send the user half
		// alone rather than nothing, which is what the download path
		// does, and let the host decide.
		return pod.AuthUser, "", nil
	}
	return pod.AuthUser, pass, nil
}

// PassthroughEpisode reports whether an item is an episode that would
// stream by enclosure passthrough for this caller: an episode whose
// audio is not on this server but whose feed named an enclosure the
// caller is allowed to reach. The URL-minting call sites ask this after
// catching ErrEpisodeNotFetched, so a caller a credentialed feed will
// not be spent on keeps the conflict instead of getting a URL that
// would refuse at the relay.
func (l *Library) PassthroughEpisode(ctx context.Context, userID, apiItemPID string) (EnclosureSource, bool) {
	src, err := l.EnclosureStreamSource(ctx, userID, apiItemPID)
	if err != nil {
		return EnclosureSource{}, false
	}
	return src, true
}

// EnclosureHTTP is the guarded client the passthrough relay uses:
// private destinations refused at dial time (after DNS resolution,
// defeating rebinding) unless the server allows LAN feed hosts,
// redirects capped, response headers bounded, and deliberately no
// overall timeout. An episode is an hour of audio played in real time,
// so a client-level deadline would cut a listener off mid-episode; the
// request context is what bounds a relay.
//
// The guard follows allowPrivateFeedHosts rather than the radio flag:
// an enclosure is a feed's own file, so the deployment that hosts feeds
// on its own LAN is the one that needs it.
func (l *Library) EnclosureHTTP() *http.Client {
	l.enclosureHTTPOnce.Do(func() {
		dialer := &net.Dialer{Timeout: 10 * time.Second}
		if !l.allowPrivateFeedHosts {
			dialer.Control = func(network, address string, _ syscall.RawConn) error {
				return refusePrivateAddr(address)
			}
		}
		transport := http.DefaultTransport.(*http.Transport).Clone()
		transport.DialContext = dialer.DialContext
		transport.ResponseHeaderTimeout = 15 * time.Second
		l.enclosureHTTP = &http.Client{
			Transport: transport,
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				if len(via) >= 5 {
					return errors.New("too many redirects")
				}
				return nil
			},
		}
	})
	return l.enclosureHTTP
}

// notFetchedEpisode builds the conflict an unfetched episode answers.
// One constructor keeps the two resolvers' wording identical and both
// matchable with errors.Is.
func notFetchedEpisode() error {
	return &Error{
		Kind: KindConflict,
		Msg:  "episode audio is not fetched to the server yet; queue it with the fetch endpoint",
		Err:  ErrEpisodeNotFetched,
	}
}

// unfetchedEpisode reports whether an item view is an episode whose
// audio this server does not hold.
func unfetchedEpisode(it *model.ItemView) bool {
	return it.Kind == model.KindEpisode && it.State != model.StatePresent
}
