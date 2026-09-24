package service

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"

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
		retryDays  *int
		providers  []enrich.Provider
		wantPhases []string
	}{
		{
			name:       "nothing configured",
			wantPhases: []string{},
		},
		{
			// The window rides the catalog's enrichment config, which
			// must not read as configured without a contact.
			name:       "a retry window alone",
			retryDays:  new(7),
			wantPhases: []string{},
		},
		{
			// The archive and LRCLIB ride along with the contact: they
			// need no key, but the catalog registers them only when it
			// has an identifying agent to dial with.
			name:       "contact alone",
			contact:    "waxdeck@example.test",
			wantPhases: []string{"identity", "album-art", "lyrics"},
		},
		{
			name:       "contact with the release match",
			contact:    "waxdeck@example.test",
			match:      true,
			wantPhases: []string{"identity", "releases", "album-art", "lyrics"},
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
			// Genres ride the identity walk and open nothing; a cover
			// opens the album-art backfill.
			name:       "cover and genres open the album-art backfill",
			providers:  []enrich.Provider{fakeCapProvider{name: "art", caps: enrich.CapCover | enrich.CapGenres}},
			wantPhases: []string{"album-art"},
		},
		{
			name:       "aux art opens both art backfills",
			providers:  []enrich.Provider{fakeCapProvider{name: "backs", caps: enrich.CapAuxArt}},
			wantPhases: []string{"aux-art", "album-art"},
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
				c.EnrichmentContact = tc.contact
				c.EnrichmentMatchReleases = tc.match
				c.EnrichmentRetryMissesDays = tc.retryDays
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
			// And phase by phase: the catalog forces exactly what the mirror
			// lists. The library is empty, so an accepted pass walks nothing.
			for _, spec := range enrichPhaseTable {
				pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{ForcePhases: spec.catalog})
				if listed := slices.Contains(st.Phases, spec.name); (err == nil) != listed {
					t.Errorf("%s: catalog accepted = %v (%v), mirror lists it = %v", spec.name, err == nil, err, listed)
				}
				if err == nil {
					waitForJob(t, ctx, svc, pid)
				}
			}
		})
	}
}

// waitForJob waits out a catalog job, so the next start is not a conflict.
func waitForJob(t *testing.T, ctx context.Context, svc *Library, pid model.PID) {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for {
		job, err := svc.lib.Job(ctx, pid)
		if err != nil {
			t.Fatal(err)
		}
		if job.State != model.JobRunning {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("job %s still running", pid)
		}
		time.Sleep(10 * time.Millisecond)
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

func TestRunEnrichmentForcePhases(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.EnrichmentProviders = []enrich.Provider{fakeCapProvider{name: "faces", caps: enrich.CapArtistArt}}
	})
	if _, err := svc.RunEnrichment(ctx, uc, true, []string{"artist-art"}); KindOf(err) != KindInvalid {
		t.Errorf("force beside forcePhases = %v, want invalid", err)
	}
	if _, err := svc.RunEnrichment(ctx, uc, false, []string{"everything"}); KindOf(err) != KindInvalid {
		t.Errorf("an unknown phase = %v, want invalid", err)
	}
	// A phase this server does not run is refused in its own knobs'
	// words, not the catalog's.
	_, err := svc.RunEnrichment(ctx, uc, false, []string{"releases"})
	if KindOf(err) != KindUnsupported {
		t.Fatalf("an unrunnable phase = %v, want unsupported", err)
	}
	for _, want := range []string{"WAXDECK_ENRICHMENT_CONTACT", "WAXDECK_ENRICHMENT_MATCH_RELEASES"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("refusal %q does not name %s", err, want)
		}
	}
	for _, leak := range []string{"enrichment.match_releases", "--force"} {
		if strings.Contains(err.Error(), leak) {
			t.Errorf("refusal %q carries the catalog's %s", err, leak)
		}
	}
	// Album art opens on covers or auxiliary art, and the refusal says both.
	_, err = svc.RunEnrichment(ctx, uc, false, []string{"album-art"})
	if KindOf(err) != KindUnsupported || !strings.Contains(err.Error(), "WAXDECK_ENRICHMENT_CONTACT") ||
		!strings.Contains(err.Error(), "auxiliary art") {
		t.Errorf("album-art refusal = %v", err)
	}
	pid, err := svc.RunEnrichment(ctx, uc, false, []string{"artist-art"})
	if err != nil || !strings.HasPrefix(pid, PrefixJob+"-") {
		t.Fatalf("a runnable phase = %q, %v; want a job", pid, err)
	}
}

// The catalog's own check is the backstop for a mirror that drifted:
// its refusal of a phase the mirror admitted is still a 501, in WaxDeck's words.
func TestRunEnrichmentForcePhasesBackstop(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.EnrichmentContact = "waxdeck@example.test"
	})
	svc.enrichmentMatchReleases = true // the catalog opened without it
	_, err := svc.RunEnrichment(ctx, uc, false, []string{"releases"})
	if KindOf(err) != KindUnsupported {
		t.Fatalf("a drifted phase = %v, want unsupported", err)
	}
	if strings.Contains(err.Error(), "enrichment.match_releases") || !strings.Contains(err.Error(), "releases") {
		t.Errorf("refusal %q carries the catalog's sentence or names no phase", err)
	}
}

// Every counter the pass keeps reaches the status surface under its own
// name, including one a later WaxBin adds.
func TestLastRunCarriesEveryCounter(t *testing.T) {
	t.Parallel()
	var r enrich.Result
	rv := reflect.ValueOf(&r).Elem()
	for i := range rv.NumField() {
		if f := rv.Field(i); f.Kind() == reflect.Int {
			f.SetInt(int64(i + 1))
		}
	}
	got := reflect.ValueOf(*lastRunFrom(r, 0))
	for i := range rv.NumField() {
		name := rv.Type().Field(i).Name
		if rv.Field(i).Kind() != reflect.Int {
			continue
		}
		g := got.FieldByName(name)
		if !g.IsValid() {
			t.Errorf("the last run has no %s", name)
		} else if g.Int() != rv.Field(i).Int() {
			t.Errorf("%s = %d, want %d", name, g.Int(), rv.Field(i).Int())
		}
	}
}

func TestEnrichCacheFromCarriesTheCensus(t *testing.T) {
	t.Parallel()
	got := enrichCacheFrom(&model.EnrichmentCacheReport{
		Rows: 3, Bytes: 700, OldestAt: 1, NewestAt: 9,
		Kinds: []model.EnrichmentCacheKind{
			{Kind: "mb:artist", Rows: 2, Bytes: 600},
			{Kind: "caa:rg-front", Rows: 1, Bytes: 100, Exempt: true},
		},
		ExemptRows: 1, ExemptBytes: 100,
	})
	want := EnrichCacheDTO{
		Rows: 3, Bytes: 700, OldestAtNS: 1, NewestAtNS: 9,
		Kinds: []EnrichCacheKindDTO{
			{Kind: "mb:artist", Rows: 2, Bytes: 600},
			{Kind: "caa:rg-front", Rows: 1, Bytes: 100, Exempt: true},
		},
		ExemptRows: 1, ExemptBytes: 100,
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("census = %+v\nwant     %+v", got, want)
	}
}
