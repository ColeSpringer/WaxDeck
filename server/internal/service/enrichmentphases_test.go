package service

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxbin/enrich"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// fakeCapProvider advertises a capability set and answers nothing. Only
// its bits matter here: the phase list is computed from them.
type fakeCapProvider struct {
	name string
	caps enrich.Capability
}

func (f fakeCapProvider) Name() string                    { return f.name }
func (f fakeCapProvider) Capabilities() enrich.Capability { return f.caps }
func (f fakeCapProvider) Enrich(context.Context, enrich.Request) (*enrich.Candidate, error) {
	return nil, nil
}

// openEnrichFixture opens a service over an empty library with the
// given enrichment configuration.
func openEnrichFixture(t *testing.T, mutate func(*Config)) (context.Context, *Library, *UserCtx) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	dataDir := t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	cfg := Config{
		DataDir: dataDir,
		Roots:   []Root{{Name: "lib", Path: t.TempDir()}},
		Logger:  log,
	}
	mutate(&cfg)
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, cfg, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "admin", Password: "correct-horse", Roles: []string{"admin"},
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return ctx, svc, uc
}

// TestEnrichmentPhasesFollowTheCatalogsOwnRule pins the copy. The phase
// list here restates the gating upstream's Run applies, because the
// facade exports no phase list; what the catalog itself will refuse is
// Doctor().EnrichmentEnabled, so the two must agree on every shape.
func TestEnrichmentPhasesFollowTheCatalogsOwnRule(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name       string
		contact    string
		match      bool
		providers  []enrich.Provider
		wantPhases []string
	}{
		{
			name:       "nothing configured",
			wantPhases: []string{},
		},
		{
			// LRCLIB rides along with the contact: it needs no key, but
			// the catalog registers it only when it has an identifying
			// agent to dial with, so lyrics is contact-gated too.
			name:       "contact alone",
			contact:    "waxdeck@example.test",
			wantPhases: []string{"identity", "lyrics"},
		},
		{
			name:       "contact with the release match",
			contact:    "waxdeck@example.test",
			match:      true,
			wantPhases: []string{"identity", "releases", "lyrics"},
		},
		{
			// And an injected lyrics provider opens the phase without
			// one, which is the half the contact does not gate.
			name:       "an injected lyrics provider and no contact",
			providers:  []enrich.Provider{fakeCapProvider{name: "words", caps: enrich.CapLyrics}},
			wantPhases: []string{"lyrics"},
		},
		{
			name:       "a provider and no contact",
			providers:  []enrich.Provider{fakeCapProvider{name: "faces", caps: enrich.CapArtistArt}},
			wantPhases: []string{"artist-art"},
		},
		{
			name: "the fields bit opens two rungs",
			providers: []enrich.Provider{
				fakeCapProvider{name: "facts", caps: enrich.CapFields | enrich.CapBookMeta},
			},
			wantPhases: []string{"track-fields", "book-fields", "album-fields"},
		},
		{
			// A capability that gates no phase of its own: covers and
			// genres ride the identity walk, so they open nothing.
			name:       "cover and genres alone open no phase",
			providers:  []enrich.Provider{fakeCapProvider{name: "art", caps: enrich.CapCover | enrich.CapGenres}},
			wantPhases: []string{},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
				c.EnrichmentContact = tc.contact
				c.EnrichmentMatchReleases = tc.match
				c.EnrichmentProviders = tc.providers
			})
			st, err := svc.EnrichmentStatusFor(ctx, uc)
			if err != nil {
				t.Fatal(err)
			}
			if !slices.Equal(st.Phases, tc.wantPhases) {
				t.Errorf("phases = %v, want %v", st.Phases, tc.wantPhases)
			}
			if got, want := st.MusicbrainzConfigured, tc.contact != ""; got != want {
				t.Errorf("musicbrainzConfigured = %v, want %v", got, want)
			}
			// The pin: configured must mean what the catalog will
			// actually accept, not what this file believes.
			rep, err := svc.lib.Doctor(ctx)
			if err != nil {
				t.Fatal(err)
			}
			if st.Configured != rep.EnrichmentEnabled {
				t.Errorf("configured = %v but the catalog reports enrichmentEnabled = %v",
					st.Configured, rep.EnrichmentEnabled)
			}
			if st.Configured != (len(st.Phases) > 0) {
				t.Errorf("configured = %v with phases %v", st.Configured, st.Phases)
			}
		})
	}
}

// TestScheduledEnrichmentRefusesWithNothingConfigured pins what the
// cron loop has to distinguish. The enrich schedule ships on, so on a
// server with nothing wired the nightly firing has to be an ordinary
// no-op rather than a failure recorded every night.
func TestScheduledEnrichmentRefusesWithNothingConfigured(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := openEnrichFixture(t, func(*Config) {})
	err := svc.RunScheduledEnrichment(ctx)
	if KindOf(err) != KindUnsupported {
		t.Fatalf("scheduled run = %v (kind %v), want unsupported", err, KindOf(err))
	}
}

// With a phase to run it starts a job, and the schedule is due at its
// default cron once a window has passed.
func TestScheduledEnrichmentStartsAPass(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := openEnrichFixture(t, func(c *Config) {
		c.EnrichmentProviders = []enrich.Provider{
			fakeCapProvider{name: "faces", caps: enrich.CapArtistArt},
		}
	})
	if err := svc.RunScheduledEnrichment(ctx); err != nil {
		t.Fatalf("scheduled run: %v", err)
	}
	// The cron loop's own gate: due at 03:45 for a window that spans it.
	base := time.Date(2026, 9, 6, 3, 0, 0, 0, time.Local)
	if !svc.DueSchedule(ctx, "enrich", base, base.Add(time.Hour)) {
		t.Error("the enrich schedule was not due across its default window")
	}
	if svc.DueSchedule(ctx, "enrich", base, base.Add(10*time.Minute)) {
		t.Error("the enrich schedule fired before its window")
	}
}
