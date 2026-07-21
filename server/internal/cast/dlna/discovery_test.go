package dlna

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/cast/dlna/testrenderer"
	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

type onlineCall struct {
	Kind, DeviceKey, Name, Address string
	VolumeControl, RateControl     bool
	Dial                           connect.DialFunc
}

type fakeAnnouncer struct {
	mu      sync.Mutex
	online  []onlineCall
	offline []string
}

func (a *fakeAnnouncer) EndpointOnline(_ context.Context, kind, deviceKey, name, address string, volumeControl, rateControl bool, dial connect.DialFunc) (connect.Endpoint, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.online = append(a.online, onlineCall{kind, deviceKey, name, address, volumeControl, rateControl, dial})
	return connect.Endpoint{ID: "pe-" + deviceKey, Kind: kind, Name: name}, nil
}

func (a *fakeAnnouncer) EndpointOffline(_ context.Context, endpointID string) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.offline = append(a.offline, endpointID)
}

func (a *fakeAnnouncer) lastOnline(deviceKey string) (onlineCall, bool) {
	a.mu.Lock()
	defer a.mu.Unlock()
	for i := len(a.online) - 1; i >= 0; i-- {
		if a.online[i].DeviceKey == deviceKey {
			return a.online[i], true
		}
	}
	return onlineCall{}, false
}

func (a *fakeAnnouncer) wentOffline(endpointID string) bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	for _, id := range a.offline {
		if id == endpointID {
			return true
		}
	}
	return false
}

// shortSSDP shrinks the multicast listen window so sweeps finish in
// test time; nothing on the test network is expected to answer.
func shortSSDP(t *testing.T) {
	t.Helper()
	old := ssdpWindow
	ssdpWindow = 10 * time.Millisecond
	t.Cleanup(func() { ssdpWindow = old })
}

func waitFor(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

func TestDiscoveryStaticDevice(t *testing.T) {
	shortSSDP(t)
	r := testrenderer.Start(t)
	ann := &fakeAnnouncer{}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	done := make(chan error, 1)
	go func() {
		done <- RunDiscovery(ctx, DiscoveryConfig{
			Announce: ann,
			Group:    supervise.NewGroup(nil),
			Interval: 20 * time.Millisecond,
			Static:   []Device{{Location: r.Location()}},
		})
	}()

	waitFor(t, "static announce", func() bool {
		_, ok := ann.lastOnline("uuid:waxdeck-test-renderer")
		return ok
	})
	call, _ := ann.lastOnline("uuid:waxdeck-test-renderer")
	if call.Kind != "dlna" || call.Name != "Test Renderer" || call.Address != r.Location() {
		t.Errorf("announce = %+v", call)
	}
	if !call.VolumeControl || call.RateControl {
		t.Errorf("controls = volume %v rate %v, want true false", call.VolumeControl, call.RateControl)
	}
	if call.Dial == nil {
		t.Fatal("announce carries no dial")
	}
	drv, err := call.Dial(ctx)
	if err != nil {
		t.Fatalf("announced dial: %v", err)
	}
	_ = drv.Close()

	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Errorf("RunDiscovery = %v, want nil on cancel", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("RunDiscovery did not return on cancel")
	}
}

func TestDiscoveryStaticPlaceholderThenName(t *testing.T) {
	shortSSDP(t)
	// The device description is unreachable at first: the endpoint
	// still comes online under a placeholder name, keyed by location,
	// and the next sweep retries.
	var up atomic.Bool
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if !up.Load() {
			http.Error(w, "starting", http.StatusServiceUnavailable)
			return
		}
		fmt.Fprint(w, `<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0"><device>
<friendlyName>Bedroom Radio</friendlyName>
<UDN>uuid:bedroom-radio</UDN>
<serviceList><service>
<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
<controlURL>/ctl/av</controlURL>
</service></serviceList>
</device></root>`)
	}))
	t.Cleanup(srv.Close)
	loc := srv.URL + "/description.xml"

	ann := &fakeAnnouncer{}
	cfg := DiscoveryConfig{
		Announce: ann,
		Group:    supervise.NewGroup(nil),
		Static:   []Device{{Location: loc}},
	}
	devices := make(map[string]*tracked)
	ctx := context.Background()

	sweep(ctx, cfg, nopLogger{}, devices)
	call, ok := ann.lastOnline(loc)
	if !ok {
		t.Fatal("unreachable static device not announced")
	}
	if call.Name != placeholderName {
		t.Errorf("name = %q, want placeholder", call.Name)
	}

	// The device comes up: the retry learns the real name and UDN and
	// retires the location-keyed endpoint so it never shows up twice.
	up.Store(true)
	sweep(ctx, cfg, nopLogger{}, devices)
	call, ok = ann.lastOnline("uuid:bedroom-radio")
	if !ok || call.Name != "Bedroom Radio" {
		t.Fatalf("reachable static device announce = %+v ok = %v", call, ok)
	}
	if !ann.wentOffline("pe-" + loc) {
		t.Error("location-keyed endpoint not retired after udn learned")
	}
}

func TestDiscoveryOfflineAfterMisses(t *testing.T) {
	shortSSDP(t)
	ann := &fakeAnnouncer{}
	cfg := DiscoveryConfig{
		Announce: ann,
		Group:    supervise.NewGroup(nil),
	}
	// A device announced in some earlier sweep that SSDP no longer
	// hears: three quiet sweeps retire it, two do not.
	devices := map[string]*tracked{
		"uuid:gone-device": {endpointID: "pe-gone", deviceKey: "uuid:gone-device", name: "Gone", named: true},
	}
	log := nopLogger{}
	ctx := context.Background()

	sweep(ctx, cfg, log, devices)
	sweep(ctx, cfg, log, devices)
	if ann.wentOffline("pe-gone") {
		t.Fatal("device retired after two misses")
	}
	sweep(ctx, cfg, log, devices)
	if !ann.wentOffline("pe-gone") {
		t.Fatal("device not retired after three misses")
	}
	if _, still := devices["uuid:gone-device"]; still {
		t.Error("retired device still tracked")
	}
}
