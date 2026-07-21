package castv2

import (
	"context"
	"encoding/binary"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// buildMDNSResponse hand-assembles the answer a real Chromecast sends
// to the cast PTR question: a PTR to the instance, with SRV, TXT, and
// A records in the additional section, using name compression the way
// devices do.
func buildMDNSResponse(t *testing.T) []byte {
	t.Helper()
	var pkt []byte
	u16 := func(v int) { pkt = binary.BigEndian.AppendUint16(pkt, uint16(v)) }
	u32 := func(v int) { pkt = binary.BigEndian.AppendUint32(pkt, uint32(v)) }

	// Header: response flags, one answer, three additionals.
	u16(0)
	u16(0x8400)
	u16(0) // questions
	u16(1) // answers
	u16(0) // authority
	u16(3) // additional

	// The answer's name is the full service name at offset 12; later
	// names compress against it, as real responses do.
	const serviceOffset = 12
	pkt = appendDNSName(pkt, mdnsService)

	// instanceName is one label plus a pointer back to the service
	// name, exercising the compression path.
	instanceName := append([]byte{19}, "Living-Room-speaker"...)
	instanceName = append(instanceName, 0xC0, serviceOffset)

	// Answer: PTR from the service name to the instance.
	u16(typePTR)
	u16(1)
	u32(120)
	u16(len(instanceName))
	pkt = append(pkt, instanceName...)

	// Additional: SRV for the instance.
	pkt = append(pkt, instanceName...)
	u16(typeSRV)
	u16(0x8001) // cache-flush bit set, as devices send
	u32(120)
	target := appendDNSName(nil, "abcdef123.local")
	u16(6 + len(target))
	u16(0) // priority
	u16(0) // weight
	u16(8009)
	pkt = append(pkt, target...)

	// Additional: TXT for the instance.
	pkt = append(pkt, instanceName...)
	u16(typeTXT)
	u16(0x8001)
	u32(120)
	var txt []byte
	for _, s := range []string{"id=deadbeef42", "fn=Living Room speaker", "md=Google Home"} {
		txt = append(txt, byte(len(s)))
		txt = append(txt, s...)
	}
	u16(len(txt))
	pkt = append(pkt, txt...)

	// Additional: A record for the SRV target.
	pkt = append(pkt, target...)
	u16(typeA)
	u16(0x8001)
	u32(120)
	u16(4)
	pkt = append(pkt, 192, 168, 1, 50)

	return pkt
}

func TestParseMDNSResponse(t *testing.T) {
	agg := newMDNSAggregate()
	agg.absorb(buildMDNSResponse(t))
	devices := agg.devices()
	if len(devices) != 1 {
		t.Fatalf("got %d devices, want 1: %+v", len(devices), devices)
	}
	want := Device{Host: "192.168.1.50", Port: 8009, Name: "Living Room speaker", ID: "deadbeef42"}
	if devices[0] != want {
		t.Errorf("device mismatch:\n got %+v\nwant %+v", devices[0], want)
	}
}

func TestParseMDNSResponseLenient(t *testing.T) {
	agg := newMDNSAggregate()
	// Garbage and truncated packets must be dropped without effect.
	agg.absorb(nil)
	agg.absorb([]byte{1, 2, 3})
	agg.absorb(buildMDNSResponse(t)[:20])
	if got := agg.devices(); len(got) != 0 {
		t.Errorf("got %d devices from garbage, want 0", len(got))
	}
}

type onlineCall struct {
	kind, deviceKey, name, address string
	volumeControl, rateControl     bool
	dial                           connect.DialFunc
}

// fakeAnnouncer records announcements and hands out predictable
// endpoint ids.
type fakeAnnouncer struct {
	mu      sync.Mutex
	online  []onlineCall
	offline []string
}

func (f *fakeAnnouncer) EndpointOnline(_ context.Context, kind, deviceKey, name, address string, volumeControl, rateControl bool, dial connect.DialFunc) (connect.Endpoint, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.online = append(f.online, onlineCall{kind, deviceKey, name, address, volumeControl, rateControl, dial})
	return connect.Endpoint{ID: "ep-" + deviceKey}, nil
}

func (f *fakeAnnouncer) EndpointOffline(_ context.Context, endpointID string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.offline = append(f.offline, endpointID)
}

func (f *fakeAnnouncer) onlineCalls() []onlineCall {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]onlineCall(nil), f.online...)
}

func (f *fakeAnnouncer) offlineCalls() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.offline...)
}

// waitFor polls until check passes or the deadline hits.
func waitFor(t *testing.T, what string, check func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if check() {
			return
		}
		time.Sleep(2 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

func TestRunDiscoveryStaticAnnounce(t *testing.T) {
	fa := &fakeAnnouncer{}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- RunDiscovery(ctx, DiscoveryConfig{
			Announce: fa,
			Group:    supervise.NewGroup(nil),
			Interval: 5 * time.Millisecond,
			Static:   []Device{{Host: "10.0.0.9", Name: "Kitchen"}},
			query:    func(context.Context) ([]Device, error) { return nil, nil },
		})
	}()

	waitFor(t, "static announce", func() bool { return len(fa.onlineCalls()) == 1 })
	call := fa.onlineCalls()[0]
	if call.kind != connect.KindCast {
		t.Errorf("kind = %q, want %q", call.kind, connect.KindCast)
	}
	if call.deviceKey != "10.0.0.9:8009" {
		t.Errorf("deviceKey = %q, want 10.0.0.9:8009 (address fallback with default port)", call.deviceKey)
	}
	if call.name != "Kitchen" || call.address != "10.0.0.9:8009" {
		t.Errorf("name/address = %q/%q", call.name, call.address)
	}
	if !call.volumeControl || call.rateControl {
		t.Errorf("volumeControl/rateControl = %v/%v, want true/false", call.volumeControl, call.rateControl)
	}
	if call.dial == nil {
		t.Error("dial is nil")
	}

	cancel()
	if err := <-done; err != nil {
		t.Errorf("RunDiscovery returned %v, want nil on cancel", err)
	}
	if len(fa.offlineCalls()) != 0 {
		t.Errorf("static device went offline: %v", fa.offlineCalls())
	}
}

func TestRunDiscoveryLifecycle(t *testing.T) {
	fa := &fakeAnnouncer{}
	dev := Device{Host: "192.168.1.50", Port: 8009, Name: "Living Room", ID: "dev-1"}
	var mu sync.Mutex
	present := true
	setPresent := func(p bool) { mu.Lock(); present = p; mu.Unlock() }

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() {
		done <- RunDiscovery(ctx, DiscoveryConfig{
			Announce: fa,
			Group:    supervise.NewGroup(nil),
			Interval: 5 * time.Millisecond,
			query: func(context.Context) ([]Device, error) {
				mu.Lock()
				defer mu.Unlock()
				if present {
					return []Device{dev}, nil
				}
				return nil, nil
			},
		})
	}()

	waitFor(t, "device online", func() bool { return len(fa.onlineCalls()) == 1 })
	if got := fa.onlineCalls()[0].deviceKey; got != "dev-1" {
		t.Errorf("deviceKey = %q, want the mDNS id dev-1", got)
	}

	// Missing for 3 consecutive sweeps takes the device offline.
	setPresent(false)
	waitFor(t, "device offline", func() bool { return len(fa.offlineCalls()) == 1 })
	if got := fa.offlineCalls()[0]; got != "ep-dev-1" {
		t.Errorf("offline endpoint = %q, want ep-dev-1", got)
	}

	// Coming back announces again.
	setPresent(true)
	waitFor(t, "device back online", func() bool { return len(fa.onlineCalls()) == 2 })

	cancel()
	if err := <-done; err != nil {
		t.Errorf("RunDiscovery returned %v, want nil on cancel", err)
	}
}

func TestRunDiscoveryQueryErrorsAreNotFatal(t *testing.T) {
	fa := &fakeAnnouncer{}
	ctx, cancel := context.WithCancel(context.Background())
	sweeps := make(chan struct{}, 16)
	done := make(chan error, 1)
	go func() {
		done <- RunDiscovery(ctx, DiscoveryConfig{
			Announce: fa,
			Group:    supervise.NewGroup(nil),
			Interval: 5 * time.Millisecond,
			Static:   []Device{{Host: "10.0.0.9", Name: "Kitchen"}},
			query: func(context.Context) ([]Device, error) {
				select {
				case sweeps <- struct{}{}:
				default:
				}
				return nil, context.DeadlineExceeded
			},
		})
	}()

	// The static device announces and sweeps keep running despite the
	// failing queries.
	waitFor(t, "static announce", func() bool { return len(fa.onlineCalls()) == 1 })
	for range 3 {
		select {
		case <-sweeps:
		case <-time.After(5 * time.Second):
			t.Fatal("sweeps stopped after query errors")
		}
	}
	cancel()
	if err := <-done; err != nil {
		t.Errorf("RunDiscovery returned %v, want nil on cancel", err)
	}
}
