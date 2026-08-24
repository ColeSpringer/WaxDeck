package service

import (
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

// waitForWarmLogo polls the cache until the create-time worker stores
// its answer, hit or miss.
func waitForWarmLogo(t *testing.T, svc *Library, apiStationPID string) RadioLogo {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for {
		if logo, ok := cachedLogo(svc, apiStationPID); ok {
			return logo
		}
		if time.Now().After(deadline) {
			t.Fatal("the warm logo fetch never landed")
		}
		time.Sleep(5 * time.Millisecond)
	}
}

// Adding a station warms its logo with nobody waiting: the first paint
// answers from the cache, and tuned clients are woken when it lands.
func TestCreateRadioStationWarmsTheLogo(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	svc.allowPrivateRadioHosts = true
	var woke atomic.Int64
	svc.SetRadioInvalidator(func() { woke.Add(1) })
	var hits atomic.Int64
	host := artHost(t, &hits, "image/png", coverPNG(t, 80))

	station, err := svc.CreateRadioStation(ctx, uc, RadioStationEdit{
		Name: "Warm FM", StreamURL: "http://198.51.100.7/stream",
		LogoURL: host.URL + "/logo.png",
	})
	if err != nil {
		t.Fatal(err)
	}
	if logo := waitForWarmLogo(t, svc, station.PID); len(logo.Bytes) == 0 {
		t.Fatal("the warm fetch cached a miss for a station with a logo")
	}
	if got := hits.Load(); got != 1 {
		t.Fatalf("logo host asked %d times, want 1", got)
	}
	if woke.Load() == 0 {
		t.Fatal("a warmed logo landed without waking tuned clients")
	}

	// The first paint answers from the cache without another fetch.
	served, err := svc.RadioStationLogo(ctx, station.PID)
	if err != nil || len(served.Bytes) == 0 {
		t.Fatalf("first paint = %v (%d bytes)", err, len(served.Bytes))
	}
	if got := hits.Load(); got != 1 {
		t.Fatalf("first paint refetched: %d hits", got)
	}
}

// A warm miss is remembered too - caching it with nobody waiting is the
// point of the server-owned context - and remembered quietly: no wake
// for a monogram.
func TestCreateRadioStationCachesAWarmMiss(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	svc.allowPrivateRadioHosts = true
	var woke atomic.Int64
	svc.SetRadioInvalidator(func() { woke.Add(1) })
	var hits atomic.Int64
	host := artHost(t, &hits, "text/html", []byte("<html>not a logo</html>"))

	station, err := svc.CreateRadioStation(ctx, uc, RadioStationEdit{
		Name: "Miss FM", StreamURL: "http://198.51.100.8/stream",
		LogoURL: host.URL + "/logo.png",
	})
	if err != nil {
		t.Fatal(err)
	}
	if logo := waitForWarmLogo(t, svc, station.PID); len(logo.Bytes) != 0 {
		t.Fatal("markup was cached as a logo")
	}
	if _, err := svc.RadioStationLogo(ctx, station.PID); err == nil {
		t.Fatal("a cached miss should answer not-found")
	}
	if got := hits.Load(); got != 1 {
		t.Fatalf("logo host asked %d times, want 1", got)
	}
	if woke.Load() != 0 {
		t.Fatal("a miss woke tuned clients with nothing to draw")
	}
}

// A hint the stream produces while the warm search runs is tried before
// the miss is stored, so add-then-play cannot bury the station's own
// mark under an hour of remembered nothing.
func TestWarmLogoTriesAHintNotedMidFlight(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	svc.allowPrivateRadioHosts = true
	var hits atomic.Int64
	mark := artHost(t, &hits, "image/png", coverPNG(t, 70))
	gate := make(chan struct{})
	slow := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-gate:
		case <-r.Context().Done():
		}
		w.WriteHeader(http.StatusNotFound)
	}))
	t.Cleanup(slow.Close)

	station, err := svc.CreateRadioStation(ctx, uc, RadioStationEdit{
		Name: "Late Mark FM", StreamURL: "http://198.51.100.12/stream",
		LogoURL: slow.URL + "/logo.png",
	})
	if err != nil {
		t.Fatal(err)
	}
	// The stream names its mark while the warm fetch is still held open.
	svc.NoteRadioLogoHint(station.PID, mark.URL+"/mark.png")
	close(gate)

	if logo := waitForWarmLogo(t, svc, station.PID); len(logo.Bytes) == 0 {
		t.Fatal("the late hint was buried under a cached miss")
	}
	if got := hits.Load(); got != 1 {
		t.Fatalf("mark host asked %d times, want 1", got)
	}
}

// An edit that moves any logo input drops the old answer and warms the
// new one, so the fresh mark is resolved now rather than at somebody's
// first paint - and the create-time flight, resolving stale inputs,
// must not store over it.
func TestUpdateRadioStationRewarmsTheLogo(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	svc.allowPrivateRadioHosts = true
	var oldHits, newHits atomic.Int64
	oldHost := artHost(t, &oldHits, "image/png", coverPNG(t, 60))
	newHost := artHost(t, &newHits, "image/png", coverPNG(t, 90))

	station, err := svc.CreateRadioStation(ctx, uc, RadioStationEdit{
		Name: "Edit FM", StreamURL: "http://198.51.100.14/stream",
		LogoURL: oldHost.URL + "/logo.png",
	})
	if err != nil {
		t.Fatal(err)
	}
	first := waitForWarmLogo(t, svc, station.PID)

	if _, err := svc.UpdateRadioStation(ctx, station.PID, RadioStationEdit{
		Name: "Edit FM", StreamURL: "http://198.51.100.14/stream",
		LogoURL: newHost.URL + "/logo.png",
	}); err != nil {
		t.Fatal(err)
	}
	second := waitForWarmLogo(t, svc, station.PID)
	if len(second.Bytes) == 0 || string(second.Bytes) == string(first.Bytes) {
		t.Fatal("the edit did not warm the new logo")
	}
	if got := newHits.Load(); got != 1 {
		t.Fatalf("new logo host asked %d times, want 1", got)
	}
	// The paint answers the new mark from the cache alone.
	served, err := svc.RadioStationLogo(ctx, station.PID)
	if err != nil || string(served.Bytes) != string(second.Bytes) {
		t.Fatalf("paint after the edit = %v (%d bytes)", err, len(served.Bytes))
	}
	if got := newHits.Load(); got != 1 {
		t.Fatalf("paint refetched the new logo: %d hits", got)
	}
}
