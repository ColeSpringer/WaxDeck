package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/events"
	waxproviders "github.com/colespringer/waxdeck/server/internal/providers"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// newServiceConfig builds what the service opens with.
func newServiceConfig(ctx context.Context, cfg *config, secret []byte, store *db.DB, agent string, log *slog.Logger) (service.Config, error) {
	sealer, err := auth.NewSealer(secret, "waxdeck-app-password-v1")
	if err != nil {
		return service.Config{}, err
	}
	// Catalog-held secrets (private-feed passwords) seal under their own
	// subkey; the catalog binds each secret's key as AAD.
	catalogCipher, err := auth.NewAADSealer(secret, "waxdeck-catalog-secret-v1")
	if err != nil {
		return service.Config{}, err
	}
	// Listing cursors that stand on a row the caller may not see travel
	// sealed, under a subkey of the same secret so they outlive a restart.
	cursorSealer, err := auth.NewSealer(secret, "waxdeck-cursor-v1")
	if err != nil {
		return service.Config{}, err
	}

	svcRoots, err := serviceRoots(cfg.core.libraryRoots, cfg.roots.managed, cfg.roots.audiobook)
	if err != nil {
		return service.Config{}, err
	}
	podcastDir, err := preparePodcastDir(cfg.podcasts.dir, cfg.podcasts.rootName, cfg.core.libraryRoots)
	if err != nil {
		return service.Config{}, err
	}
	providers := acquisitionProviders(cfg.acquisition, cfg.core.dataDir, podcastDir, store, log)

	// The matching engine's candidate source and the server's own
	// enrichment providers. Key-free providers are always registered;
	// keyed ones only when configured. All are paced and cached, and all
	// name this build.
	matchSource := newMatchSource(cfg.matching, agent)
	// One Deezer client, shared: radio's artwork rung and every
	// enrichment rung go at api.deezer.com, and more clients would be
	// that many unpaced callers.
	deezer := waxproviders.NewDeezer(waxproviders.DeezerConfig{UserAgent: agent})
	enrichProviders, err := buildEnrichmentProviders(ctx, cfg.matching, agent, deezer, log)
	if err != nil {
		return service.Config{}, err
	}

	svcCfg := service.Config{
		DataDir:                   cfg.core.dataDir,
		WorkerLocalPaths:          cfg.similarity.workerLocalPaths,
		SonicAnalysisDefault:      cfg.similarity.sonicAnalysis,
		WorkerAPIConfigured:       len(cfg.similarity.workerTokens) > 0,
		Roots:                     svcRoots,
		UploadFormats:             splitNonEmpty(cfg.roots.uploadFormats, ","),
		ScanOnStart:               cfg.core.scanOnStart && len(cfg.core.libraryRoots) > 0,
		WatchLibraries:            cfg.roots.watch,
		ResetStaleCatalog:         cfg.core.resetCatalog,
		Sealer:                    sealer,
		SecretCipher:              catalogCipher,
		CursorSealer:              cursorSealer,
		PodcastDir:                podcastDir,
		PodcastRootName:           cfg.podcasts.rootName,
		AllowPrivateFeedHosts:     cfg.podcasts.allowPrivateHosts,
		DefaultRetentionKeep:      cfg.podcasts.retentionKeep,
		SourceProviders:           providers,
		AllowPrivateRadioHosts:    cfg.radio.allowPrivateHosts,
		AllowPrivateScrobbleHosts: cfg.scrobble.allowPrivateScrobbleHosts,
		AllowPrivateNotifyHosts:   cfg.scrobble.allowPrivateNotifyHosts,
		PublicBase:                cfg.core.publicBase,
		Version:                   version,
		RadioDirectoryBase:        cfg.radio.directoryBase,
		PodcastDirectoryBase:      cfg.podcasts.directoryBase,
		LastfmAPIKey:              cfg.scrobble.lastfmKey,
		LastfmSecret:              cfg.scrobble.lastfmSecret,
		EnrichmentProviders:       enrichProviders,
		EnrichmentContact:         cfg.matching.enrichContact,
		EnrichmentMatchReleases:   cfg.matching.enrichMatch,
		EnrichmentRetryMissesDays: cfg.matching.enrichRetryDays,
		Logger:                    log,
	}
	// Radio's external artwork rung, Deezer first: it answers a title in a
	// third of a second against the archive's tens. Whether it reaches out
	// at all is the admin toggle's call.
	radioArt := waxproviders.CoverChain{
		Sources: []waxproviders.TitleCover{deezer},
		NoCover: service.ErrNoRadioArt,
	}
	if matchSource != nil {
		svcCfg.MatchSource = matchSource
		// The ISRC upgrade and the archive half of the rung above ride the
		// same paced client as matching: a second would be an unthrottled
		// caller against a service that allows one request a second.
		svcCfg.ISRCResolver = matchSource.MB
		// Behind Deezer because its licensing is the unambiguous one and it
		// holds the obscure and non-commercial releases Deezer has no entry
		// for, not because it is the better first ask.
		radioArt.Sources = append(radioArt.Sources, waxproviders.RecordingCover{
			MB:  matchSource.MB,
			CAA: waxproviders.NewCoverArt(waxproviders.CoverArtConfig{BaseURL: cfg.matching.coverArtBase, UserAgent: agent}),
		})
	}
	svcCfg.RadioArtResolver = radioArt
	return svcCfg, nil
}

// preparePodcastDir makes the podcast dir absolute and creates it, when
// podcasts are on.
func preparePodcastDir(dir, rootName string, roots []root) (string, error) {
	if dir != "" {
		abs, err := filepath.Abs(dir)
		if err != nil {
			return "", fmt.Errorf("bad podcast dir: %w", err)
		}
		dir = abs
		if err := os.MkdirAll(abs, 0o755); err != nil {
			return "", fmt.Errorf("creating podcast dir: %w", err)
		}
		if err := checkPodcastRootName(roots, rootName); err != nil {
			return "", err
		}
	}
	return dir, nil
}

// checkPodcastRootName refuses a podcast root named like a library root:
// the engine refuses duplicate root names at start.
func checkPodcastRootName(roots []root, name string) error {
	for _, r := range roots {
		if r.Name == name {
			return fmt.Errorf("WAXDECK_PODCAST_ROOT_NAME %q is also a library root in WAXDECK_LIBRARY_ROOTS; give one of them another name", name)
		}
	}
	return nil
}

// serviceRoots marks the configured roots that managedRoots and bookRoots
// (comma-separated names) name as managed or as holding audiobooks. A name
// that is no configured root is refused: a typo would otherwise leave a
// root unmanaged, or its books cataloged as music, with nothing to say so.
func serviceRoots(roots []root, managedRoots, bookRoots string) ([]service.Root, error) {
	managed := map[string]bool{}
	for name := range strings.SplitSeq(managedRoots, ",") {
		if name = strings.TrimSpace(name); name != "" {
			managed[name] = true
		}
	}
	books := map[string]bool{}
	for _, name := range splitNonEmpty(bookRoots, ",") {
		books[name] = true
	}
	svcRoots := make([]service.Root, len(roots))
	for i, r := range roots {
		svcRoots[i] = service.Root{Name: r.Name, Path: r.Path, Managed: managed[r.Name]}
		if books[r.Name] {
			svcRoots[i].Media = "audiobook"
		}
		delete(managed, r.Name)
		delete(books, r.Name)
	}
	if len(managed) > 0 {
		for name := range managed {
			return nil, fmt.Errorf("WAXDECK_MANAGED_ROOTS names %q, which is not a configured library root", name)
		}
	}
	for name := range books {
		return nil, fmt.Errorf("WAXDECK_AUDIOBOOK_ROOTS names %q, which is not a configured library root", name)
	}
	return svcRoots, nil
}

// newOIDC connects to the identity provider, when one is configured.
func newOIDC(ctx context.Context, cfg oidcConfig, store *db.DB, log *slog.Logger) (*auth.OIDC, error) {
	if cfg.issuer == "" {
		return nil, nil
	}
	oidc, err := auth.NewOIDC(ctx, auth.OIDCConfig{
		ID:           cfg.id,
		DisplayName:  cfg.name,
		Issuer:       cfg.issuer,
		ClientID:     cfg.clientID,
		ClientSecret: cfg.clientSecret,
		GroupsClaim:  cfg.groupsClaim,
		AdminGroup:   cfg.adminGroup,
	}, store)
	if err != nil {
		return nil, err
	}
	log.Info("single sign-on enabled", "issuer", cfg.issuer, "provider", cfg.id)
	return oidc, nil
}

// startEventHub wires the event hub to the service and starts it.
func startEventHub(ctx context.Context, group *supervise.Group, svc *service.Library) *events.Hub {
	// The event hub fans the service's change wakeups out to WebSocket
	// subscribers as coalesced invalidation frames.
	hub := events.New(svc)
	// A station's new song or cover wakes the faces tuned to it, which
	// would otherwise wait out a poll interval.
	svc.Radio.SetRadioInvalidator(hub.MarkRadio)
	// A replaced catalog (a restore) sends every client back to a snapshot.
	svc.SetCatalogResyncer(hub.MarkCatalogReplaced)
	group.Go(ctx, "event-hub", hub.Run)
	return hub
}
