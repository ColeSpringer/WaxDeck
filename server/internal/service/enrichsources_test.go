package service

import (
	"context"
	"slices"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
)

// answeringProvider answers every lookup with its own name as a publisher.
type answeringProvider struct {
	name string
	caps enrich.Capability
}

func (a answeringProvider) Name() string                    { return a.name }
func (a answeringProvider) Capabilities() enrich.Capability { return a.caps }
func (a answeringProvider) Enrich(context.Context, enrich.Request) (*enrich.Candidate, error) {
	return &enrich.Candidate{Publisher: a.name}, nil
}

func providerNames(ps []enrich.Provider) []string {
	out := make([]string, 0, len(ps))
	for _, p := range ps {
		out = append(out, p.Name())
	}
	return out
}

func threeSources() *enrichSources {
	return newEnrichSources([]enrich.Provider{
		answeringProvider{"a", enrich.CapLyrics},
		answeringProvider{"b", enrich.CapCover},
		answeringProvider{"c", enrich.CapFields},
	})
}

func TestEnrichSourcesMergeTheSavedOrderWithBootOrder(t *testing.T) {
	t.Parallel()
	s := threeSources()
	s.setStored([]EnrichmentSource{{"c", true}, {"gone", true}, {"a", false}})

	want := []EnrichmentSource{{"c", true}, {"a", false}, {"b", true},
		{"coverartarchive", true}, {"musicbrainz", true}, {"listenbrainz", true}, {"lrclib", true}}
	if got := s.resolved(); !slices.Equal(got, want) {
		t.Fatalf("resolved = %v, want %v", got, want)
	}
	if got := providerNames(s.live()); !slices.Equal(got, []string{"c", "b"}) {
		t.Fatalf("live = %v, want the enabled ones in order", got)
	}
}

func TestProviderListFollowsTheSavedOrder(t *testing.T) {
	t.Parallel()
	a, b := &lyricist{name: "a"}, &lyricist{name: "b"}
	caa, lrclib := &lyricist{name: enrich.ProviderCoverArt}, &lyricist{name: enrich.ProviderLRCLIB}
	fixed := []enrich.Provider{a, b, caa, lrclib}
	for _, tc := range []struct {
		name  string
		fixed []enrich.Provider
		saved []EnrichmentSource
		want  []enrich.Provider
	}{
		{"nothing saved", fixed, nil, fixed},
		{"a built-in first", fixed, []EnrichmentSource{{"lrclib", true}, {"b", true}, {"a", true}}, []enrich.Provider{lrclib, b, a, caa}},
		// Every install upgrading saved an order over its own providers alone.
		{"no built-in named", fixed, []EnrichmentSource{{"b", true}, {"a", true}}, []enrich.Provider{b, a, caa, lrclib}},
		{"a built-in off", fixed, []EnrichmentSource{{"coverartarchive", false}, {"a", true}, {"b", true}}, []enrich.Provider{a, b, lrclib}},
		{"an unwired name", fixed, []EnrichmentSource{{"gone", true}, {"b", true}}, []enrich.Provider{b, a, caa, lrclib}},
		// No contact, so no built-in in the catalog's list, and none made up.
		{"a built-in the catalog lacks", []enrich.Provider{a, b}, []EnrichmentSource{{"lrclib", true}, {"b", true}}, []enrich.Provider{b, a}},
	} {
		s := newEnrichSources([]enrich.Provider{a, b})
		if tc.saved != nil {
			s.setStored(tc.saved)
		}
		if got := s.providerList(slices.Clone(tc.fixed)); !slices.Equal(got, tc.want) {
			t.Errorf("%s: list = %v, want %v", tc.name, providerNames(got), providerNames(tc.want))
		}
	}
}

func openSourcesFixture(t *testing.T) (context.Context, *Library, *UserCtx) {
	t.Helper()
	return openEnrichFixture(t, func(c *Config) {
		c.EnrichmentProviders = []enrich.Provider{
			answeringProvider{"a", enrich.CapLyrics},
			answeringProvider{"b", enrich.CapLyrics},
			answeringProvider{"fanart", enrich.CapAuxArt},
		}
	})
}

func TestEnrichProvidersWithFollowTheOperatorsOrder(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	if got := providerNames(svc.enrichProvidersWith(enrich.CapLyrics, enrich.TargetRecording)); !slices.Equal(got, []string{"a", "b"}) {
		t.Fatalf("boot order = %v", got)
	}

	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"b", true}, {"a", true}, {"fanart", true}}); err != nil {
		t.Fatal(err)
	}
	if got := providerNames(svc.enrichProvidersWith(enrich.CapLyrics, enrich.TargetRecording)); !slices.Equal(got, []string{"b", "a"}) {
		t.Fatalf("after a reorder = %v, want b first", got)
	}

	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"b", false}, {"a", true}, {"fanart", true}}); err != nil {
		t.Fatal(err)
	}
	if got := providerNames(svc.enrichProvidersWith(enrich.CapLyrics, enrich.TargetRecording)); !slices.Equal(got, []string{"a"}) {
		t.Fatalf("with b off = %v, want a alone", got)
	}
}

func TestPutEnrichmentSourcesRefusesWhatItCannotOrder(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	for name, list := range map[string][]EnrichmentSource{
		"unknown":   {{"nobody", true}, {"a", true}, {"b", true}, {"fanart", true}},
		"duplicate": {{"a", true}, {"a", false}},
	} {
		if _, err := svc.PutEnrichmentSources(ctx, uc, list); KindOf(err) != KindInvalid {
			t.Errorf("%s: err = %v, want invalid-request", name, err)
		}
	}
	listener := &UserCtx{ID: "us-listener"}
	if _, err := svc.PutEnrichmentSources(ctx, listener, nil); KindOf(err) != KindForbidden {
		t.Errorf("non-admin: err = %v, want forbidden", err)
	}
}

// The catalog's built-ins take part in the order and may be left out of a
// save, whether or not this install registered them.
func TestPutEnrichmentSourcesTakesTheBuiltins(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	st, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"lrclib", false}, {"a", true}, {"b", true}, {"fanart", true}})
	if err != nil {
		t.Fatalf("a save naming a built-in: %v", err)
	}
	if first := st.Providers[0]; first.Name != "lrclib" || first.Enabled || !first.Builtin || first.Configured {
		t.Fatalf("first source = %+v, want lrclib, off, built in, unregistered without a contact", first)
	}
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"a", true}, {"b", true}, {"fanart", true}}); err != nil {
		t.Fatalf("a save leaving the built-ins out: %v", err)
	}
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"bogus", true}, {"a", true}, {"b", true}, {"fanart", true}}); KindOf(err) != KindInvalid {
		t.Fatalf("a save naming no source = %v, want invalid-request", err)
	}
}

// An order saved before the built-ins could be ranked names none of them:
// they follow it, switched on, as the catalog's own instances.
func TestASavedOrderWithoutBuiltinsKeepsThemOn(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.EnrichmentContact = "waxdeck@example.test"
		c.EnrichmentProviders = []enrich.Provider{answeringProvider{"fanart", enrich.CapAuxArt}}
	})
	st, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"fanart", true}})
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, p := range st.Providers {
		if !p.Enabled || !p.Configured {
			t.Errorf("%s listed as %+v, want on and registered", p.Name, p)
		}
		got = append(got, p.Name)
	}
	if want := []string{"fanart", "coverartarchive", "musicbrainz", "listenbrainz", "lrclib"}; !slices.Equal(got, want) {
		t.Fatalf("order = %v, want %v", got, want)
	}
	// Only LRCLIB serves lyrics here, so the phase says whether the catalog
	// kept the instance it was handed.
	if !slices.Contains(st.Phases, "lyrics") {
		t.Fatalf("phases = %v, want lyrics from lrclib", st.Phases)
	}
	st, err = svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"fanart", true}, {"lrclib", false}})
	if err != nil {
		t.Fatal(err)
	}
	if slices.Contains(st.Phases, "lyrics") {
		t.Fatalf("phases = %v, want no lyrics with lrclib off", st.Phases)
	}
}

func TestDisablingAPhasesOnlyProviderTakesThePhase(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	st, err := svc.EnrichmentStatusFor(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(st.Phases, "group-art") {
		t.Fatalf("phases = %v, want group-art from fanart", st.Phases)
	}

	st, err = svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"fanart", false}, {"a", true}, {"b", true}})
	if err != nil {
		t.Fatal(err)
	}
	if slices.Contains(st.Phases, "group-art") {
		t.Fatalf("phases = %v, want no group-art with its only provider off", st.Phases)
	}
	for _, p := range st.Providers {
		if p.Name == "fanart" && (p.Enabled || p.Builtin) {
			t.Fatalf("fanart listed as %+v, want disabled and its own", p)
		}
	}
	// The whole list, the missing ones appended in boot order.
	var got []string
	for _, p := range st.Providers {
		if !p.Builtin {
			got = append(got, p.Name)
		}
	}
	if !slices.Equal(got, []string{"fanart", "a", "b"}) {
		t.Fatalf("provider order = %v", got)
	}
}

func TestAProposalFromADisabledProviderIsRefused(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	proposal := EnrichProposalDTO{Fields: []EnrichFieldProposalDTO{{Name: "publisher", Proposed: "x", Provider: "a"}}}
	if err := svc.validateEnrichProposal([]string{enrichWantBook}, proposal); err != nil {
		t.Fatalf("an enabled provider's proposal was refused: %v", err)
	}
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"a", false}, {"b", true}, {"fanart", true}}); err != nil {
		t.Fatal(err)
	}
	if err := svc.validateEnrichProposal([]string{enrichWantBook}, proposal); KindOf(err) != KindInvalid {
		t.Fatalf("a disabled provider's proposal = %v, want invalid-request", err)
	}
}

func TestARunWithEverySourceOffSaysSo(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	off := []EnrichmentSource{{"a", false}, {"b", false}, {"fanart", false}}
	if _, err := svc.PutEnrichmentSources(ctx, uc, off); err != nil {
		t.Fatal(err)
	}
	_, err := svc.RunEnrichment(ctx, uc, false, nil)
	if KindOf(err) != KindUnsupported {
		t.Fatalf("err = %v, want unsupported", err)
	}
	if !strings.Contains(err.Error(), "switched off") {
		t.Fatalf("the refusal does not say the sources are off: %v", err)
	}
}

func TestAPutWhoseStatusCannotBeReadSavesNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	// The catalog gone: the coverage the answer carries cannot be read.
	if err := svc.lib.Close(); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"b", true}, {"a", true}, {"fanart", true}}); err == nil {
		t.Fatal("a put with no status to answer succeeded")
	}
	if got := providerNames(svc.sources.live()); !slices.Equal(got, []string{"a", "b", "fanart"}) {
		t.Fatalf("a refused put left the order %v", got)
	}
}

// lyricist answers a lyrics lookup with its own name; with a gate it
// signals asked and waits for the gate first.
type lyricist struct {
	name  string
	asked chan struct{}
	gate  chan struct{}
}

func (p *lyricist) Name() string                    { return p.name }
func (p *lyricist) Capabilities() enrich.Capability { return enrich.CapLyrics }
func (p *lyricist) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if p.gate != nil {
		select {
		case p.asked <- struct{}{}:
		default:
		}
		select {
		case <-p.gate:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	return &enrich.Candidate{Lyrics: &model.Lyrics{Unsynced: "sung by " + p.name}}, nil
}

// openLyricsFixture is a catalog of one scanned track over providers.
func openLyricsFixture(t *testing.T, providers ...enrich.Provider) (context.Context, *Library, *UserCtx, model.PID) {
	t.Helper()
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.EnrichmentProviders = providers
		if _, err := fixtures.Generate(c.Roots[0].Path, fixtures.Spec{
			Name: "amber", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Amber Waves", "ARTIST": "Test Ensemble", "ALBUM": "Signal Garden"},
		}); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	_, track := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	return ctx, svc, uc, track
}

// A pass is known to run however many jobs come after it: accepting an
// upload writes one import job per track.
func TestAPassOutlastsTheJobWindow(t *testing.T) {
	t.Parallel()
	a := &lyricist{name: "a", asked: make(chan struct{}, 1), gate: make(chan struct{})}
	ctx, svc, uc, _ := openLyricsFixture(t, a, &lyricist{name: "b"})
	pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	defer waitForJob(t, ctx, svc, pid)
	defer close(a.gate)
	<-a.asked
	for range enrichJobWindow + 1 {
		if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
			t.Fatal(err)
		}
	}

	if st, err := svc.EnrichmentStatusFor(ctx, uc); err != nil || !st.Running || st.RunningJob != apiPID(PrefixJob, pid) {
		t.Errorf("status = running %v, job %q (%v); want the pass", st.Running, st.RunningJob, err)
	}
	if running, err := svc.catalogJobRunning(ctx); err != nil || !running {
		t.Errorf("catalogJobRunning = %v (%v); want the pass", running, err)
	}
}

// A reorder saved while a pass walks is taken at once: that pass keeps
// the order it started with, and the next one asks by the new order.
func TestASaveDuringAPassAppliesToTheNextOne(t *testing.T) {
	t.Parallel()
	a := &lyricist{name: "a", asked: make(chan struct{}, 1), gate: make(chan struct{})}
	ctx, svc, uc, track := openLyricsFixture(t, a, &lyricist{name: "b"})

	pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	<-a.asked
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"b", true}, {"a", true}}); err != nil {
		t.Fatalf("a save during a pass: %v", err)
	}
	close(a.gate)
	waitForJob(t, ctx, svc, pid)
	if ly, err := svc.lib.Lyrics(ctx, track); err != nil || ly.Provider != "a" {
		t.Fatalf("lyrics = %+v (%v), want a's", ly, err)
	}

	if _, err := fixtures.Generate(svc.roots[0].Path, fixtures.Spec{
		Name: "cedar", Codec: fixtures.CodecFLAC, Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Cedar Lines", "ARTIST": "Test Ensemble", "ALBUM": "Signal Garden"},
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	_, next := fixtureTrackPID(t, ctx, svc, uc, "Cedar Lines")
	if pid, err = svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{}); err != nil {
		t.Fatal(err)
	}
	waitForJob(t, ctx, svc, pid)
	if ly, err := svc.lib.Lyrics(ctx, next); err != nil || ly.Provider != "b" {
		t.Fatalf("the next pass's lyrics = %+v (%v), want b's", ly, err)
	}
}

// A pass after a reorder asks, and credits, the new first source.
func TestAPassAfterAReorderCreditsTheNewFirstSource(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, track := openLyricsFixture(t, &lyricist{name: "a"}, &lyricist{name: "b"})
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"b", true}, {"a", true}}); err != nil {
		t.Fatal(err)
	}
	api, err := svc.RunEnrichment(ctx, uc, false, nil)
	if err != nil {
		t.Fatal(err)
	}
	_, pid, _ := parseAPIPID(api)
	waitForJob(t, ctx, svc, pid)
	if ly, err := svc.lib.Lyrics(ctx, track); err != nil || ly.Unsynced != "sung by b" || ly.Provider != "b" {
		t.Fatalf("lyrics = %+v (%v), want b's", ly, err)
	}
}

// A forced run while a pass walks meets the catalog's lease, even for a
// phase only a source switched on since then supplies.
func TestAForcedRunDuringAPassIsAConflict(t *testing.T) {
	t.Parallel()
	a := &lyricist{name: "a", asked: make(chan struct{}, 1), gate: make(chan struct{})}
	ctx, svc, uc, _ := openLyricsFixture(t, a, answeringProvider{"fanart", enrich.CapAuxArt})
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"a", true}, {"fanart", false}}); err != nil {
		t.Fatal(err)
	}
	api, err := svc.RunEnrichment(ctx, uc, false, nil)
	if err != nil {
		t.Fatal(err)
	}
	_, pid, _ := parseAPIPID(api)
	<-a.asked
	defer func() { close(a.gate); waitForJob(t, ctx, svc, pid) }()
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"a", true}, {"fanart", true}}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.RunEnrichment(ctx, uc, false, []string{"group-art"}); KindOf(err) != KindConflict {
		t.Fatalf("a forced run during a pass = %v, want conflict", err)
	}
}

// A save names every source this server has: an empty or partial body is
// a malformed request, not an order that resets the rest.
func TestAPutMustNameEverySource(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	for name, list := range map[string][]EnrichmentSource{
		"empty":   nil,
		"partial": {{"a", true}},
	} {
		if _, err := svc.PutEnrichmentSources(ctx, uc, list); KindOf(err) != KindInvalid {
			t.Errorf("%s: err = %v, want invalid-request", name, err)
		}
	}
}

// A source not wired now (its key unset) keeps the switch it was saved
// with, so it comes back as the operator left it.
func TestASourceNotWiredKeepsItsSwitch(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	if err := svc.db.SettingSet(ctx, settingEnrichmentSources, `[{"name":"gone","enabled":false}]`, 1); err != nil {
		t.Fatal(err)
	}
	svc.loadEnrichSources(ctx)
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"b", true}, {"a", true}, {"fanart", true}}); err != nil {
		t.Fatal(err)
	}
	raw, err := svc.db.SettingGet(ctx, settingEnrichmentSources)
	if err != nil || !strings.Contains(raw, `{"name":"gone","enabled":false}`) {
		t.Fatalf("saved %s (%v), want gone kept switched off", raw, err)
	}
}

// A refusal about a source that is only switched off says so.
func TestASwitchedOffSourceIsCalledThat(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"a", false}, {"b", true}, {"fanart", false}}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.RunEnrichment(ctx, uc, false, []string{"group-art"}); err == nil || !strings.Contains(err.Error(), "switched off") {
		t.Fatalf("forcing a switched-off source's phase = %v, want it called switched off", err)
	}
	proposal := EnrichProposalDTO{Fields: []EnrichFieldProposalDTO{{Name: "publisher", Proposed: "x", Provider: "a"}}}
	if err := svc.validateEnrichProposal([]string{enrichWantBook}, proposal); err == nil || !strings.Contains(err.Error(), "switched off") {
		t.Fatalf("a switched-off source's proposal = %v, want it called switched off", err)
	}
}

// The status names the running pass's job, so a console can follow that
// one row rather than rebuilding the whole status.
func TestTheStatusNamesTheRunningPass(t *testing.T) {
	t.Parallel()
	a := &lyricist{name: "a", asked: make(chan struct{}, 1), gate: make(chan struct{})}
	ctx, svc, uc, _ := openLyricsFixture(t, a)
	api, err := svc.RunEnrichment(ctx, uc, false, nil)
	if err != nil {
		t.Fatal(err)
	}
	_, pid, _ := parseAPIPID(api)
	<-a.asked
	st, err := svc.EnrichmentStatusFor(ctx, uc)
	close(a.gate)
	waitForJob(t, ctx, svc, pid)
	if err != nil || !st.Running || st.RunningJob != api {
		t.Fatalf("status while running = running %v, job %q (%v); want %s", st.Running, st.RunningJob, err, api)
	}
}

// rungProvider serves fields for albums alone, and counts its asks.
type rungProvider struct{ asked atomic.Int32 }

func (p *rungProvider) Name() string                    { return "albums-only" }
func (p *rungProvider) Capabilities() enrich.Capability { return enrich.CapFields }
func (p *rungProvider) CapabilitiesAt(t enrich.TargetType) enrich.Capability {
	if t == enrich.TargetRelease {
		return enrich.CapFields
	}
	return 0
}
func (p *rungProvider) Enrich(context.Context, enrich.Request) (*enrich.Candidate, error) {
	p.asked.Add(1)
	return &enrich.Candidate{Fields: map[string]string{"bpm": "120"}}, nil
}

// An item's fetch asks a provider only at the rungs it declares, as the
// catalog's own pass does.
func TestEnrichItemAsksAtTheDeclaredRungsOnly(t *testing.T) {
	t.Parallel()
	p := &rungProvider{}
	ctx, svc, _, track := openLyricsFixture(t, p)
	_, skipped, err := svc.EnrichItemNow(ctx, track, []string{enrichWantFields})
	if err != nil {
		t.Fatal(err)
	}
	if n := p.asked.Load(); n != 0 {
		t.Errorf("asked %d times about a track, a rung it declares empty", n)
	}
	if !slices.Contains(skipped, "fields: no provider") {
		t.Errorf("skipped = %v, want no provider for a track's fields", skipped)
	}
}

// quietLyricist answers no lyrics and counts its asks.
type quietLyricist struct{ asked atomic.Int32 }

func (p *quietLyricist) Name() string                    { return "quiet" }
func (p *quietLyricist) Capabilities() enrich.Capability { return enrich.CapLyrics }
func (p *quietLyricist) Enrich(context.Context, enrich.Request) (*enrich.Candidate, error) {
	p.asked.Add(1)
	return nil, nil
}

// An item's fetch runs the catalog's pass only for a want a registered,
// switched-on built-in serves: that pass asks every other source again.
func TestAnItemFetchRunsTheCatalogPassOnlyForALiveBuiltin(t *testing.T) {
	t.Parallel()
	p := &quietLyricist{}
	ctx, svc, uc, _ := openLyricsFixture(t, p)
	apiPID, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	fetch := func() int32 {
		t.Helper()
		p.asked.Store(0)
		if _, _, err := svc.EnrichItemFor(ctx, uc, apiPID, []string{enrichWantLyrics}, nil); err != nil {
			t.Fatal(err)
		}
		return p.asked.Load()
	}
	if n := fetch(); n != 1 {
		t.Errorf("no contact, so no lrclib: asked %d times, want once", n)
	}
	// Standing in for the registration a contact brings.
	svc.sources.builtins = []enrich.Provider{&lyricist{name: enrich.ProviderLRCLIB}}
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"quiet", true}, {"lrclib", false}}); err != nil {
		t.Fatal(err)
	}
	if n := fetch(); n != 1 {
		t.Errorf("lrclib switched off: asked %d times, want once", n)
	}
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"quiet", true}, {"lrclib", true}}); err != nil {
		t.Fatal(err)
	}
	if n := fetch(); n != 2 {
		t.Errorf("lrclib on: asked %d times, want once more by the catalog's pass", n)
	}
}

// A built-in ranked ahead of a provider is asked first on an item too: the
// fetch and the preview leave the want to the catalog's pass, which asks in
// order. The health fixer, which runs no such pass, asks the providers.
func TestAnItemFetchKeepsTheSourceOrder(t *testing.T) {
	t.Parallel()
	p := &quietLyricist{}
	ctx, svc, uc, _ := openLyricsFixture(t, p)
	apiPID, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	svc.sources.builtins = []enrich.Provider{&lyricist{name: enrich.ProviderLRCLIB}}
	order := func(list ...EnrichmentSource) {
		t.Helper()
		if _, err := svc.PutEnrichmentSources(ctx, uc, list); err != nil {
			t.Fatal(err)
		}
	}
	ask := func(catalogAfter bool) ([]string, bool) {
		got, viaCatalog := svc.itemProviders(enrichItemState{catalogAfter: catalogAfter},
			enrichWantLyrics, enrich.CapLyrics, enrich.TargetRecording)
		return providerNames(got), viaCatalog
	}

	order(EnrichmentSource{"lrclib", true}, EnrichmentSource{"quiet", true})
	if got, via := ask(true); len(got) != 0 || !via {
		t.Errorf("lrclib first, a fetch asks %v (via catalog %v), want none, via the catalog", got, via)
	}
	if got, via := ask(false); !slices.Equal(got, []string{"quiet"}) || via {
		t.Errorf("the health fixer asks %v (via catalog %v), want quiet", got, via)
	}
	pre, err := svc.EnrichPreviewFor(ctx, uc, apiPID, []string{enrichWantLyrics})
	if err != nil {
		t.Fatal(err)
	}
	if p.asked.Load() != 0 || !slices.Contains(pre.Skipped, "lyrics: asked through the catalog") {
		t.Errorf("preview asked quiet %d times, skipped %v; want it left to the catalog", p.asked.Load(), pre.Skipped)
	}

	order(EnrichmentSource{"quiet", true}, EnrichmentSource{"lrclib", true})
	if got, via := ask(true); !slices.Equal(got, []string{"quiet"}) || via {
		t.Errorf("quiet first, a fetch asks %v (via catalog %v), want quiet", got, via)
	}
	order(EnrichmentSource{"lrclib", false}, EnrichmentSource{"quiet", true})
	if got, via := ask(true); !slices.Equal(got, []string{"quiet"}) || via {
		t.Errorf("lrclib off, a fetch asks %v (via catalog %v), want quiet", got, via)
	}
}

// forcedLyricist answers only a forced ask, which the catalog's item pass
// makes and the item's own ask does not.
type forcedLyricist struct{}

func (forcedLyricist) Name() string                    { return "passlyrics" }
func (forcedLyricist) Capabilities() enrich.Capability { return enrich.CapLyrics }
func (forcedLyricist) Enrich(_ context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if !req.Force || req.Type != enrich.TargetRecording {
		return nil, nil
	}
	return &enrich.Candidate{Lyrics: &model.Lyrics{Unsynced: "la la la"}}, nil
}

// What the catalog's pass filled is credited to whoever filled it, which is
// not the built-in the want is named after.
func TestAnItemPassCreditsWhoFilledIt(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openLyricsFixture(t, forcedLyricist{})
	apiPID, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	// Standing in for the registration a contact brings.
	svc.sources.builtins = []enrich.Provider{&lyricist{name: enrich.ProviderLRCLIB}}
	applied, _, err := svc.EnrichItemFor(ctx, uc, apiPID, []string{enrichWantLyrics}, nil)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(applied, "lyrics: passlyrics") {
		t.Errorf("applied = %v, want the lyrics credited to passlyrics", applied)
	}
}

// A save that leaves out a source not wired now keeps its switch, a
// built-in the catalog has not registered included; a registered built-in
// left out follows the rest, switched on.
func TestASaveKeepsTheSwitchOfWhatIsNotWired(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	lrclibOn := func(st EnrichmentStatusDTO) bool {
		for _, p := range st.Providers {
			if p.Name == "lrclib" {
				return p.Enabled
			}
		}
		t.Fatal("lrclib is not listed")
		return false
	}
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"lrclib", false}, {"a", true}, {"b", true}, {"fanart", true}}); err != nil {
		t.Fatal(err)
	}
	st, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"a", true}, {"b", true}, {"fanart", true}})
	if err != nil {
		t.Fatal(err)
	}
	if lrclibOn(st) {
		t.Error("an unregistered lrclib left out of a save came back switched on")
	}
	// Standing in for the registration a contact brings.
	svc.sources.builtins = []enrich.Provider{&lyricist{name: enrich.ProviderLRCLIB}}
	st, err = svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"a", true}, {"b", true}, {"fanart", true}})
	if err != nil {
		t.Fatal(err)
	}
	if !lrclibOn(st) {
		t.Error("a registered lrclib left out of a save stayed switched off")
	}
}
