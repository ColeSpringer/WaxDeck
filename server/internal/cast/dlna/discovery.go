package dlna

import (
	"context"
	"time"

	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// Announcer is discovery's seam to the endpoint registry.
type Announcer interface {
	EndpointOnline(ctx context.Context, kind, deviceKey, name, address string, volumeControl, rateControl bool, dial connect.DialFunc) (connect.Endpoint, error)
	EndpointOffline(ctx context.Context, endpointID string)
}

// DiscoveryConfig configures RunDiscovery.
type DiscoveryConfig struct {
	Announce Announcer
	Group    *supervise.Group
	Logger   Logger
	// Interval is the sweep cadence; zero means 30 seconds.
	Interval time.Duration
	// StaticOnly suppresses SSDP entirely: static devices are still
	// announced (and retried), but no multicast search ever leaves
	// the host. The shape of discovery disabled by configuration.
	StaticOnly bool
	// Static devices are announced without SSDP ever finding them, for
	// tests and for networks where multicast is filtered.
	Static []Device
}

const (
	defaultDiscoveryInterval = 30 * time.Second
	// offlineAfterMisses is how many sweeps a device may miss before
	// its endpoint goes offline: one lost SSDP exchange is routine,
	// three in a row is an absent device.
	offlineAfterMisses = 3
	// placeholderName names a device whose description will not load
	// yet; the next sweep retries and the real friendlyName replaces
	// it through the announce upsert.
	placeholderName = "DLNA renderer"
)

// tracked is discovery's memory of one announced device between
// sweeps, keyed by the device's stable identity.
type tracked struct {
	endpointID string
	deviceKey  string
	name       string
	named      bool
	missed     int
}

// RunDiscovery sweeps for renderers until ctx ends, announcing finds
// and expiring devices that stop answering. Run it under the group
// (group.Go); it returns nil on cancel so the supervisor does not
// restart a clean shutdown.
func RunDiscovery(ctx context.Context, cfg DiscoveryConfig) error {
	if cfg.Interval <= 0 {
		cfg.Interval = defaultDiscoveryInterval
	}
	log := cfg.Logger
	if log == nil {
		log = nopLogger{}
	}
	devices := make(map[string]*tracked)
	sweep(ctx, cfg, log, devices)
	ticker := time.NewTicker(cfg.Interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			sweep(ctx, cfg, log, devices)
		}
	}
}

// sweep runs one discovery pass: static devices first so they work
// with multicast filtered entirely, then whatever SSDP heard. Every
// present device is re-announced; the registry upsert keeps names and
// last-seen fresh.
func sweep(ctx context.Context, cfg DiscoveryConfig, log Logger, devices map[string]*tracked) {
	candidates := make([]Device, 0, len(cfg.Static))
	candidates = append(candidates, cfg.Static...)
	if !cfg.StaticOnly {
		for _, f := range ssdpSearch(ctx, log) {
			candidates = append(candidates, Device{Location: f.Location, UDN: f.UDN})
		}
	}

	seen := make(map[string]bool)
	for _, dev := range candidates {
		// The tracking key must be stable across sweeps, so a static
		// entry without a configured UDN tracks by Location even after
		// its description reveals the real UDN.
		key := dev.UDN
		if key == "" {
			key = dev.Location
		}
		if seen[key] {
			continue
		}
		seen[key] = true
		st := devices[key]
		if st == nil {
			st = &tracked{}
			devices[key] = st
		}
		st.missed = 0
		announce(ctx, cfg, log, dev, key, st)
	}

	for key, st := range devices {
		if seen[key] {
			continue
		}
		st.missed++
		if st.missed < offlineAfterMisses {
			continue
		}
		if st.endpointID != "" {
			cfg.Announce.EndpointOffline(ctx, st.endpointID)
			log.Info("dlna: renderer offline", "name", st.name, "deviceKey", st.deviceKey)
		}
		delete(devices, key)
	}
}

// announce resolves the device's name and identity and upserts its
// endpoint. The description is fetched once per device; a fetch
// failure announces a placeholder so the endpoint exists now, and the
// next sweep retries for the real name.
func announce(ctx context.Context, cfg DiscoveryConfig, log Logger, dev Device, key string, st *tracked) {
	name := st.name
	named := st.named
	udn := dev.UDN
	if !named {
		desc, err := fetchDescription(ctx, dev.Location)
		if err != nil {
			log.Warn("dlna: fetching device description", "location", dev.Location, "err", err)
			name = placeholderName
		} else {
			named = true
			name = desc.FriendlyName
			if name == "" {
				name = placeholderName
			}
			if udn == "" {
				udn = desc.UDN
			}
		}
	}
	deviceKey := udn
	if deviceKey == "" {
		deviceKey = dev.Location
	}
	// The description can reveal a UDN a placeholder announce did not
	// have; retire the endpoint that was keyed by Location so one
	// device never shows up twice.
	if st.endpointID != "" && st.deviceKey != "" && st.deviceKey != deviceKey {
		cfg.Announce.EndpointOffline(ctx, st.endpointID)
		st.endpointID = ""
	}
	dial := Device{Location: dev.Location, UDN: udn, Name: name}.Dial(cfg.Group, log)
	ep, err := cfg.Announce.EndpointOnline(ctx, connect.KindDLNA, deviceKey, name, dev.Location, true, false, dial)
	if err != nil {
		log.Warn("dlna: announcing renderer", "name", name, "err", err)
		return
	}
	if st.endpointID == "" {
		log.Info("dlna: renderer online", "name", name, "deviceKey", deviceKey)
	}
	st.endpointID = ep.ID
	st.deviceKey = deviceKey
	st.name = name
	st.named = named
}
