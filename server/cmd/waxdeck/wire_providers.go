package main

import (
	"context"
	"fmt"
	"log/slog"
	"path/filepath"
	"strings"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/source"

	"github.com/colespringer/waxdeck/server/internal/db"
	waxproviders "github.com/colespringer/waxdeck/server/internal/providers"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/stubsource"
	"github.com/colespringer/waxdeck/server/internal/waxtapsource"
)

// acquisitionProviders are the bridges the catalog acquires media through.
func acquisitionProviders(cfg acquisitionConfig, dataDir, podcastDir string, store *db.DB, log *slog.Logger) []source.Provider {
	var providers []source.Provider
	if cfg.youtube {
		yt, err := waxtapsource.New(waxtapsource.Config{
			WorkDir:        filepath.Join(dataDir, "waxtap-work"),
			SealBaseURL:    cfg.sealURL,
			SealAPIKey:     cfg.sealKey,
			SponsorBlock:   cfg.sponsorBlock,
			EmbedThumbnail: cfg.ytThumbnail,
			EmbedMetadata:  true,
			Pending:        store,
			Logger:         log,
		})
		if err != nil {
			// The bridge is on by default, so a construction hiccup
			// degrades acquisition rather than downing the server; the
			// rest of the catalog is unaffected. Set WAXDECK_YOUTUBE=false
			// to opt out entirely.
			log.Warn("youtube acquisition bridge unavailable; URL downloads are disabled", "err", err)
		} else {
			providers = append(providers, yt)
			log.Info("youtube acquisition bridge enabled", "seal", cfg.sealURL != "")
		}
		// The bridge serves two independent paths: subscribing a
		// channel or playlist as a podcast (episodes land in the
		// podcast library) and acquiring a video, playlist, or channel
		// into a music or audiobook library by URL. Only the former
		// needs the podcast library, so its absence is a warning, not
		// a refusal: URL acquisition still works.
		if podcastDir == "" {
			log.Warn("youtube podcast subscriptions are unavailable without a podcast library; URL acquisition to music and audiobook libraries still works")
		}
	}
	if cfg.stubSource != "" {
		providers = append(providers, stubsource.New(cfg.stubSource))
		log.Warn("stub acquisition source enabled; this is a test bridge, never production", "url", cfg.stubSource)
	}
	return providers
}

// newMatchSource is the matching engine's candidate source; nil when
// matching is off.
func newMatchSource(cfg matchingConfig, agent string) *waxproviders.Source {
	var matchSource *waxproviders.Source
	if cfg.on {
		matchSource = &waxproviders.Source{
			MB: waxproviders.NewMusicBrainz(waxproviders.MusicBrainzConfig{BaseURL: cfg.musicBrainzBase, UserAgent: agent}),
			Acoust: waxproviders.NewAcoustID(waxproviders.AcoustIDConfig{
				APIKey: cfg.acoustIDKey, UserAgent: agent,
			}),
		}
	}
	return matchSource
}

// buildEnrichmentProviders are the server's own enrichment providers, in
// their default order.
func buildEnrichmentProviders(ctx context.Context, cfg matchingConfig, agent string, deezer *waxproviders.Deezer,
	log *slog.Logger) ([]enrich.Provider, error) {
	// The artist-art switch is applied to the enrichment port itself:
	// hiding the capability is what takes the artist rung out of the
	// catalog's walk, since a provider that does not advertise it is
	// never dispatched for one.
	hideArtistArt := func(p enrich.Provider) enrich.Provider {
		if cfg.artistArt {
			return p
		}
		return waxproviders.WithoutArtistArt(p)
	}
	enrichProviders := []enrich.Provider{
		hideArtistArt(deezer),
		waxproviders.NewITunes(waxproviders.ITunesConfig{UserAgent: agent}),
	}
	if cfg.discogsToken != "" {
		enrichProviders = append(enrichProviders, waxproviders.NewDiscogs(waxproviders.DiscogsConfig{Token: cfg.discogsToken, UserAgent: agent}))
	}
	// The book ladder, identifier-anchored end first: Audnexus answers
	// the ASIN outright, Hardcover bridges an ASIN to the ISBN the two
	// fallbacks key on, and the fallbacks also take a name-gated title
	// search for books carrying neither identifier's answer yet.
	enrichProviders = append(enrichProviders, waxproviders.NewAudnexus(waxproviders.AudnexusConfig{UserAgent: agent}))
	if cfg.hardcoverKey != "" {
		enrichProviders = append(enrichProviders, waxproviders.NewHardcover(waxproviders.HardcoverConfig{Token: cfg.hardcoverKey, UserAgent: agent}))
	}
	enrichProviders = append(enrichProviders,
		waxproviders.NewGoogleBooks(waxproviders.GoogleBooksConfig{APIKey: cfg.googleBooksKey, UserAgent: agent}),
		waxproviders.NewOpenLibrary(waxproviders.OpenLibraryConfig{UserAgent: agent}),
	)
	// fanart.tv is registered ahead of the other art providers, so it
	// leads the default order: it is the only one answering per role.
	// One client for the same pacing reason as Deezer's.
	if cfg.fanartTVKey != "" {
		fanart := waxproviders.NewFanartTV(waxproviders.FanartTVConfig{APIKey: cfg.fanartTVKey, UserAgent: agent})
		enrichProviders = append([]enrich.Provider{hideArtistArt(fanart)}, enrichProviders...)
	}
	// Custom providers ride ahead of everything: an operator who wired a
	// regional service wants its answers to win. Each is validated at
	// startup, so a typo'd URL or a downed sidecar is a refusal naming
	// it rather than a provider that is silently absent.
	bridgePairs, err := parsePairs(cfg.enrichURLs, "enrich provider")
	if err != nil {
		return nil, err
	}
	authPairs, err := parsePairs(cfg.enrichAuth, "enrich provider auth")
	if err != nil {
		return nil, err
	}
	authFor := make(map[string]string, len(authPairs))
	bridgeNames := make(map[string]bool, len(bridgePairs))
	for _, p := range bridgePairs {
		bridgeNames[p[0]] = true
	}
	for _, p := range authPairs {
		if !bridgeNames[p[0]] {
			return nil, fmt.Errorf("WAXDECK_ENRICH_PROVIDER_AUTH names %q, which is not a configured enrich provider", p[0])
		}
		authFor[p[0]] = p[1]
	}
	if len(bridgePairs) > 0 {
		// The provenance mark must be unambiguous: a bridge advertising a
		// name a registered provider (or the catalog's own built-ins)
		// already stamps values with would make every conflict
		// unattributable.
		takenNames := map[string]bool{}
		for _, name := range service.ReservedEnrichNames {
			takenNames[name] = true
		}
		for _, p := range enrichProviders {
			takenNames[p.Name()] = true
		}
		bridged := make([]enrich.Provider, 0, len(bridgePairs))
		for _, p := range bridgePairs {
			bridge, err := waxproviders.NewHTTPBridge(ctx, waxproviders.HTTPBridgeConfig{
				Label: p[0], BaseURL: p[1], Token: authFor[p[0]], Log: log, UserAgent: agent,
			})
			if err != nil {
				return nil, err
			}
			// A remote serving nothing this build can ask for is version
			// skew, not misconfiguration: the URL answered and named itself.
			// Skipping it with a log line beats refusing to start.
			if bridge.Capabilities() == 0 {
				log.Warn("custom enrichment provider serves nothing this build can ask for, at any target type it knows; skipping it",
					"name", bridge.Name(), "label", p[0])
				continue
			}
			if takenNames[bridge.Name()] {
				return nil, fmt.Errorf("enrich provider %q advertises the name %q, which another provider already stamps its values with", p[0], bridge.Name())
			}
			takenNames[bridge.Name()] = true
			log.Info("custom enrichment provider connected", "name", bridge.Name(), "label", p[0])
			bridged = append(bridged, bridge)
		}
		enrichProviders = append(bridged, enrichProviders...)
	}
	return enrichProviders, nil
}

// parsePairs parses "name=value,name2=value2", order-preserving; what
// names the flag for the error. The error never echoes a value: one of
// these flags carries bearer tokens, and a malformed entry must not
// write its secret to the log on its way out.
func parsePairs(s, what string) ([][2]string, error) {
	if strings.TrimSpace(s) == "" {
		return nil, nil
	}
	var out [][2]string
	i := 0
	for part := range strings.SplitSeq(s, ",") {
		i++
		name, val, ok := strings.Cut(strings.TrimSpace(part), "=")
		if !ok || name == "" || val == "" {
			return nil, fmt.Errorf("bad %s entry %d: want name=value", what, i)
		}
		out = append(out, [2]string{name, val})
	}
	return out, nil
}
