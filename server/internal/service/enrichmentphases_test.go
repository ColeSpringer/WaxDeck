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
	"github.com/colespringer/waxbin/waxerr"

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

// The status names the catalog's own phases in the API's words: each one
// listed is a force the catalog accepts, and each one not listed is
// refused here, naming the phase.
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
			wantPhases: []string{"identity", "group-art", "album-art", "lyrics"},
		},
		{
			name:       "contact with the release match",
			contact:    "waxdeck@example.test",
			match:      true,
			wantPhases: []string{"identity", "releases", "group-art", "album-art", "lyrics"},
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
			// Deezer's shape: a portrait and no background.
			name:       "an artist portrait alone opens artist art",
			providers:  []enrich.Provider{fakeCapProvider{name: "portraits", caps: enrich.CapArtistFront}},
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
			// opens the front half of both art backfills.
			name:       "cover and genres open both art backfills",
			providers:  []enrich.Provider{fakeCapProvider{name: "art", caps: enrich.CapCover | enrich.CapGenres}},
			wantPhases: []string{"group-art", "album-art"},
		},
		{
			name:       "aux art opens both art backfills",
			providers:  []enrich.Provider{fakeCapProvider{name: "backs", caps: enrich.CapAuxArt}},
			wantPhases: []string{"group-art", "album-art"},
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
			// The library is empty, so an accepted force walks nothing.
			for _, name := range apiPhases() {
				if !slices.Contains(st.Phases, name) {
					_, err := svc.RunEnrichment(ctx, uc, false, []string{name}, nil)
					if KindOf(err) != KindUnsupported || !strings.Contains(err.Error(), "the "+name+" phase") {
						t.Errorf("forcing %s, not listed = %v, want it refused by name", name, err)
					}
					continue
				}
				pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{ForcePhases: phasesNamed(svc.lib.EnrichmentPhases(), name)})
				if err != nil {
					t.Errorf("forcing %s, listed: the catalog refused %v", name, err)
					continue
				}
				waitForJob(t, ctx, svc, pid)
			}
		})
	}
}

// apiPhases is every API phase name in run order.
func apiPhases() []string {
	return apiNames(model.EnrichPhases())
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
	if _, err := svc.RunEnrichment(ctx, uc, true, []string{"artist-art"}, nil); KindOf(err) != KindInvalid {
		t.Errorf("force beside forcePhases = %v, want invalid", err)
	}
	if _, err := svc.RunEnrichment(ctx, uc, false, []string{"everything"}, nil); KindOf(err) != KindInvalid {
		t.Errorf("an unknown phase = %v, want invalid", err)
	}
	// A phase this server does not run is refused in its own knobs'
	// words, not the catalog's.
	_, err := svc.RunEnrichment(ctx, uc, false, []string{"releases"}, nil)
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
	// Both art backfills open on covers or auxiliary art, and the
	// refusal says both.
	for _, phase := range []string{"group-art", "album-art"} {
		_, err = svc.RunEnrichment(ctx, uc, false, []string{phase}, nil)
		if KindOf(err) != KindUnsupported || !strings.Contains(err.Error(), "WAXDECK_ENRICHMENT_CONTACT") ||
			!strings.Contains(err.Error(), "auxiliary art") {
			t.Errorf("%s refusal = %v", phase, err)
		}
	}
	pid, err := svc.RunEnrichment(ctx, uc, false, []string{"artist-art"}, nil)
	if err != nil || !strings.HasPrefix(pid, PrefixJob+"-") {
		t.Fatalf("a runnable phase = %q, %v; want a job", pid, err)
	}
}

// A switch saved between this server's read of the phases and the start
// leaves the catalog to refuse the force: still a 501, in WaxDeck's words.
func TestRunEnrichmentForcePhasesBackstop(t *testing.T) {
	t.Parallel()
	_, svc, _ := openEnrichFixture(t, func(*Config) {})
	refusal := waxerr.New(waxerr.CodeUnsupported, "waxbin.StartEnrich",
		"phase album-release does not run on this install: it needs a MusicBrainz contact and enrichment.match_releases")
	err := svc.explainEnrichRefusal(refusal, []string{"releases"})
	if KindOf(err) != KindUnsupported {
		t.Fatalf("a refused force = %v, want unsupported", err)
	}
	if strings.Contains(err.Error(), "enrichment.match_releases") || !strings.Contains(err.Error(), "releases") {
		t.Errorf("refusal %q carries the catalog's sentence or names no phase", err)
	}
}

// Every phase the catalog can build has an API name the spec lists.
func TestEveryCatalogPhaseHasAnAPIName(t *testing.T) {
	t.Parallel()
	for _, p := range model.EnrichPhases() {
		if !slices.Contains(apiPhases(), apiPhaseOf(p)) {
			t.Errorf("%s maps to %q, which the API does not list", p, apiPhaseOf(p))
		}
	}
	want := []string{"identity", "releases", "group-art", "artist-art", "album-art", "lyrics", "track-fields", "book-fields", "album-fields"}
	if got := apiPhases(); !slices.Equal(got, want) {
		t.Errorf("API phases = %v, want %v", got, want)
	}
	_, svc, _ := openEnrichFixture(t, func(*Config) {})
	for _, name := range want {
		if _, ok := svc.phaseNeed(name); !ok {
			t.Errorf("no requirement worded for %s", name)
		}
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

// A stalled phase reaches the status under its API name, once.
func TestLastRunNamesTheStalledPhases(t *testing.T) {
	t.Parallel()
	r := enrich.Result{Stalled: []model.EnrichPhase{model.EnrichPhaseArtist, model.EnrichPhaseLyrics, model.EnrichPhaseBook}}
	if got := lastRunFrom(r, 0).Stalled; !slices.Equal(got, []string{"identity", "lyrics"}) {
		t.Fatalf("stalled = %v, want identity and lyrics", got)
	}
	if got := lastRunFrom(enrich.Result{}, 0).Stalled; got == nil || len(got) != 0 {
		t.Fatalf("stalled with none = %#v, want an empty list", got)
	}
}

// Lyrics coverage is the catalog's own count: tracks holding lyrics over
// every track, and the ones asked that no source could answer.
func TestCoverageCountsLyrics(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name          string
		provider      enrich.Provider
		enriched, ask int
	}{
		{"answered", &lyricist{name: "words"}, 1, 0},
		{"none found", fakeCapProvider{name: "silence", caps: enrich.CapLyrics}, 0, 1},
	} {
		ctx, svc, uc, _ := openLyricsFixture(t, tc.provider)
		pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
		if err != nil {
			t.Fatal(err)
		}
		waitForJob(t, ctx, svc, pid)
		st, err := svc.EnrichmentStatusFor(ctx, uc)
		if err != nil {
			t.Fatal(err)
		}
		if got := st.Coverage.Lyrics; got.Enriched != tc.enriched || got.Total != 1 || st.Coverage.LyricsAsked != tc.ask {
			t.Errorf("%s: lyrics %d/%d, asked %d; want %d/1, asked %d",
				tc.name, got.Enriched, got.Total, st.Coverage.LyricsAsked, tc.enriched, tc.ask)
		}
	}
}

// With the contact set, a refusal names what is missing and does not ask
// for the contact again.
func TestAPhaseRefusalWithTheContactSetDoesNotAskForIt(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.EnrichmentContact = "waxdeck@example.test"
	})
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"lrclib", false}}); err != nil {
		t.Fatal(err)
	}
	for phase, want := range map[string]string{
		"lyrics":   "switched off",
		"releases": "WAXDECK_ENRICHMENT_MATCH_RELEASES",
	} {
		_, err := svc.RunEnrichment(ctx, uc, false, []string{phase}, nil)
		if KindOf(err) != KindUnsupported || !strings.Contains(err.Error(), want) ||
			strings.Contains(err.Error(), "WAXDECK_ENRICHMENT_CONTACT") {
			t.Errorf("forcing %s = %v; want it to say %s and not ask for the contact", phase, err, want)
		}
	}
}

// rungFake serves caps at one rung only.
type rungFake struct {
	caps enrich.Capability
	rung enrich.TargetType
}

func (f rungFake) Name() string                    { return "rung" }
func (f rungFake) Capabilities() enrich.Capability { return f.caps }
func (f rungFake) CapabilitiesAt(t enrich.TargetType) enrich.Capability {
	if t == f.rung {
		return f.caps
	}
	return 0
}
func (f rungFake) Enrich(context.Context, enrich.Request) (*enrich.Candidate, error) { return nil, nil }

// The rung each provider phase opens at, which words a refusal, is the
// catalog's: a provider serving exactly that opens the phase.
func TestPhaseRungsAreTheCatalogs(t *testing.T) {
	t.Parallel()
	for phase, g := range phaseRungs {
		ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
			c.EnrichmentProviders = []enrich.Provider{rungFake{caps: g.cap, rung: g.rung}}
		})
		st, err := svc.EnrichmentStatusFor(ctx, uc)
		if err != nil {
			t.Fatal(err)
		}
		if !slices.Contains(st.Phases, phase) {
			t.Errorf("%v at %s opens %v, not %s", g.cap, g.rung, st.Phases, phase)
		}
	}
}

// A refusal blames the switches only when a source switched off could
// open the phase.
func TestARefusalBlamesOnlySwitchesThatMatter(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"a", false}, {"b", true}, {"fanart", true}}); err != nil {
		t.Fatal(err)
	}
	_, err := svc.RunEnrichment(ctx, uc, false, []string{"book-fields"}, nil)
	if KindOf(err) != KindUnsupported || strings.Contains(err.Error(), "switched off") {
		t.Errorf("forcing book-fields with a lyrics source off = %v, want no blame on the switch", err)
	}
}
