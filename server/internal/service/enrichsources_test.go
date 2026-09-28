package service

import (
	"context"
	"slices"
	"strings"
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

	want := []EnrichmentSource{{"c", true}, {"a", false}, {"b", true}}
	if got := s.resolved(); !slices.Equal(got, want) {
		t.Fatalf("resolved = %v, want %v", got, want)
	}
	if got := providerNames(s.live()); !slices.Equal(got, []string{"c", "b"}) {
		t.Fatalf("live = %v, want the enabled ones in order", got)
	}
}

func TestSourceSlotsAnswerForTheirRank(t *testing.T) {
	t.Parallel()
	s := threeSources()
	s.setStored([]EnrichmentSource{{"b", true}, {"a", true}, {"c", false}})
	slots := s.slots()
	if len(slots) != 3 {
		t.Fatalf("%d slots for three providers", len(slots))
	}

	first := slots[0]
	if first.Name() != "b" || first.Capabilities() != enrich.CapCover {
		t.Fatalf("slot 0 = %s/%v, want b", first.Name(), first.Capabilities())
	}
	cand, err := first.Enrich(context.Background(), enrich.Request{})
	if err != nil || cand == nil || cand.Publisher != "b" {
		t.Fatalf("slot 0 answered %+v, %v", cand, err)
	}

	// Two enabled providers leave the third rank empty: named, so the
	// catalog keeps it, and capable of nothing, so it is never asked.
	empty := slots[2]
	if empty.Name() == "" || empty.Capabilities() != 0 {
		t.Fatalf("empty slot = %q/%v", empty.Name(), empty.Capabilities())
	}
	if cand, err := empty.Enrich(context.Background(), enrich.Request{}); cand != nil || err != nil {
		t.Fatalf("empty slot answered %+v, %v", cand, err)
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
	if got := providerNames(svc.enrichProvidersWith(enrich.CapLyrics)); !slices.Equal(got, []string{"a", "b"}) {
		t.Fatalf("boot order = %v", got)
	}

	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"b", true}, {"a", true}, {"fanart", true}}); err != nil {
		t.Fatal(err)
	}
	if got := providerNames(svc.enrichProvidersWith(enrich.CapLyrics)); !slices.Equal(got, []string{"b", "a"}) {
		t.Fatalf("after a reorder = %v, want b first", got)
	}

	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"b", false}, {"a", true}, {"fanart", true}}); err != nil {
		t.Fatal(err)
	}
	if got := providerNames(svc.enrichProvidersWith(enrich.CapLyrics)); !slices.Equal(got, []string{"a"}) {
		t.Fatalf("with b off = %v, want a alone", got)
	}
}

func TestPutEnrichmentSourcesRefusesWhatItCannotOrder(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	for name, list := range map[string][]EnrichmentSource{
		"unknown":   {{"nobody", true}},
		"duplicate": {{"a", true}, {"a", false}},
		"built-in":  {{"lrclib", false}},
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

func TestDisablingAPhasesOnlyProviderTakesThePhase(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	st, err := svc.EnrichmentStatusFor(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(st.Phases, "aux-art") {
		t.Fatalf("phases = %v, want aux-art from fanart", st.Phases)
	}

	st, err = svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"fanart", false}, {"a", true}, {"b", true}})
	if err != nil {
		t.Fatal(err)
	}
	if slices.Contains(st.Phases, "aux-art") {
		t.Fatalf("phases = %v, want no aux-art with its only provider off", st.Phases)
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

func TestAPassAfterAnEndedOneTakesTheNewOrder(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openSourcesFixture(t)
	// The waiter never polls here: the next run applies the order itself.
	svc.enrichWatchEvery = time.Hour

	first, err := svc.RunEnrichment(ctx, uc, false, nil)
	if err != nil {
		t.Fatal(err)
	}
	_, pid, _ := parseAPIPID(first)
	waitForJob(t, ctx, svc, pid)
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"b", true}, {"a", true}, {"fanart", true}}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.RunEnrichment(ctx, uc, false, nil); err != nil {
		t.Fatal(err)
	}
	if got := svc.sources.slots()[0].Name(); got != "b" {
		t.Fatalf("the next pass's first source is %s, want the new order's b", got)
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

	if !svc.enrichPassRunning(ctx)() {
		t.Error("the pass reads as finished once other jobs outnumber the window")
	}
	if st, err := svc.EnrichmentStatusFor(ctx, uc); err != nil || !st.Running || st.RunningJob != apiPID(PrefixJob, pid) {
		t.Errorf("status = running %v, job %q (%v); want the pass", st.Running, st.RunningJob, err)
	}
	if running, err := svc.catalogJobRunning(ctx); err != nil || !running {
		t.Errorf("catalogJobRunning = %v (%v); want the pass", running, err)
	}
}

// A reorder saved while a pass walks waits for it, whoever started it:
// a pass off the IPC socket never passes through this server.
func TestAPassKeepsTheOrderItStartedOn(t *testing.T) {
	t.Parallel()
	a := &lyricist{name: "a", asked: make(chan struct{}, 1), gate: make(chan struct{})}
	ctx, svc, uc, track := openLyricsFixture(t, a, &lyricist{name: "b"})
	svc.enrichWatchEvery = 20 * time.Millisecond

	pid, err := svc.lib.StartEnrich(ctx, waxbin.EnrichOptions{})
	if err != nil {
		t.Fatal(err)
	}
	<-a.asked
	if _, err := svc.PutEnrichmentSources(ctx, uc, []EnrichmentSource{{"b", true}, {"a", true}}); err != nil {
		t.Fatal(err)
	}
	close(a.gate)
	waitForJob(t, ctx, svc, pid)

	ly, err := svc.lib.Lyrics(ctx, track)
	if err != nil || ly.Unsynced != "sung by a" || ly.Provider != "a" {
		t.Fatalf("lyrics = %+v (%v), want a's, credited to a", ly, err)
	}
	deadline := time.Now().Add(10 * time.Second)
	for svc.sources.slots()[0].Name() != "b" {
		if time.Now().After(deadline) {
			t.Fatal("the saved order never took effect after the pass")
		}
		time.Sleep(10 * time.Millisecond)
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

// A forced run while a pass walks is the conflict a second pass meets,
// even for a phase only a source switched on since then supplies.
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
	if _, err := svc.RunEnrichment(ctx, uc, false, []string{"aux-art"}); KindOf(err) != KindConflict {
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
	if _, err := svc.RunEnrichment(ctx, uc, false, []string{"aux-art"}); err == nil || !strings.Contains(err.Error(), "switched off") {
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
