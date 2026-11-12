package service

import (
	"context"
	"net/http"
	"sync"
	"sync/atomic"
	"time"

	"github.com/colespringer/waxdeck/server/internal/scrobble"
)

// Integrations is what reaches out or waits on a clock: notifications,
// the inbox, scrobbling and schedules.
type Integrations struct {
	*core
	// journalPruneHook stands in for the catalog's organize journal prune
	// in a test; nothing in the server sets it.
	journalPruneHook func(context.Context, time.Duration) (int, error)
	// lastfmPtr holds the swappable outbound Last.fm client (admin
	// credential changes rebuild it at runtime); envLastfmKey/Secret
	// keep the environment pair as the fallback when no runtime pair is
	// stored. listenbrainz needs no server credentials.
	lastfmPtr                 atomic.Value
	envLastfmKey              string
	envLastfmSecret           string
	listenbrainz              *scrobble.ListenBrainz
	allowPrivateScrobbleHosts bool
	// publicBase is where this server's web app answers, trailing slash
	// trimmed; empty leaves every notification link out.
	publicBase string
	// notifyGuardedHTTP is the dial-guarded client for user-pointed
	// notification destinations, built on first use;
	// allowPrivateNotifyHosts relaxes its SSRF guard.
	notifyGuardedHTTP       *http.Client
	notifyGuardedOnce       sync.Once
	allowPrivateNotifyHosts bool
}

func newIntegrations(c *core, cfg Config) *Integrations {
	// The ListenBrainz API base is caller-supplied, so its deliveries
	// ride a dial-guarded client like every other user-pointed fetch;
	// the flag opts LAN instances back in. The connection's write-time
	// check gives the friendly error, this guard is the boundary.
	listenbrainz := scrobble.NewListenBrainz()
	listenbrainz.HTTP = scrobbleHTTPClient(cfg.AllowPrivateScrobbleHosts)
	return &Integrations{
		core:                      c,
		listenbrainz:              listenbrainz,
		allowPrivateScrobbleHosts: cfg.AllowPrivateScrobbleHosts,
	}
}
