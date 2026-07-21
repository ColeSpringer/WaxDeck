package castv2

import (
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"sort"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

const (
	mdnsService = "_googlecast._tcp.local"
	mdnsAddr    = "224.0.0.251:5353"

	defaultSweepInterval = 30 * time.Second
	mdnsWindow           = 3 * time.Second
	offlineAfterMisses   = 3
)

// DNS record types the parser keeps.
const (
	typeA   = 1
	typePTR = 12
	typeTXT = 16
	typeSRV = 33
)

// Announcer is the registry seam discovery drives.
type Announcer interface {
	EndpointOnline(ctx context.Context, kind, deviceKey, name, address string, volumeControl, rateControl bool, dial connect.DialFunc) (connect.Endpoint, error)
	EndpointOffline(ctx context.Context, endpointID string)
}

// DiscoveryConfig configures RunDiscovery.
type DiscoveryConfig struct {
	Announce Announcer
	Group    *supervise.Group
	Logger   Logger
	Interval time.Duration // sweep period, default 30s
	// StaticOnly suppresses mDNS entirely: static devices are still
	// announced (and retried), but no multicast query ever leaves the
	// host. The shape of discovery disabled by configuration.
	StaticOnly bool
	Static     []Device // devices announced without mDNS (tests, blocked-multicast networks)

	// query replaces the mDNS sweep in tests.
	query func(ctx context.Context) ([]Device, error)
}

// RunDiscovery announces cast devices to the registry: Static devices
// at start, mDNS finds every sweep, and a device missing for 3
// consecutive sweeps goes offline. It is written to run under
// group.Go from main and returns nil on context cancel. mDNS failure
// is never fatal: networks without multicast (Docker default
// networking) degrade to Static devices quietly.
func RunDiscovery(ctx context.Context, cfg DiscoveryConfig) error {
	log := cfg.Logger
	if log == nil {
		log = nopLogger{}
	}
	interval := cfg.Interval
	if interval <= 0 {
		interval = defaultSweepInterval
	}
	query := cfg.query
	if query == nil {
		query = queryMDNS
	}

	type trackedDevice struct {
		device     Device
		endpointID string
		announced  bool
		static     bool
		missed     int
	}
	tracked := make(map[string]*trackedDevice)
	for _, dev := range cfg.Static {
		tracked[dev.Key()] = &trackedDevice{device: dev, static: true}
	}

	announce := func(td *trackedDevice) {
		dev := td.device
		ep, err := cfg.Announce.EndpointOnline(ctx, connect.KindCast, dev.Key(), dev.Name, dev.address(),
			true, false, dev.Dial(cfg.Group, cfg.Logger))
		if err != nil {
			log.Warn("castv2: announcing device failed", "device", dev.Key(), "err", err)
			return
		}
		td.endpointID = ep.ID
		td.announced = true
		log.Info("castv2: device online", "device", dev.Key(), "name", dev.Name, "endpoint", ep.ID)
	}

	sweep := func() {
		// Static devices retry until announced; they never go offline.
		for _, td := range tracked {
			if td.static && !td.announced {
				announce(td)
			}
		}
		if cfg.StaticOnly {
			return
		}
		found, err := query(ctx)
		if err != nil {
			if ctx.Err() == nil {
				log.Warn("castv2: mdns sweep failed", "err", err)
			}
			return
		}
		seen := make(map[string]bool, len(found))
		for _, dev := range found {
			key := dev.Key()
			seen[key] = true
			td := tracked[key]
			if td == nil {
				td = &trackedDevice{device: dev}
				tracked[key] = td
			}
			td.missed = 0
			if !td.static {
				td.device = dev
			}
			if !td.announced {
				announce(td)
			}
		}
		for key, td := range tracked {
			if td.static || seen[key] {
				continue
			}
			td.missed++
			if td.missed >= offlineAfterMisses {
				if td.announced {
					cfg.Announce.EndpointOffline(ctx, td.endpointID)
					log.Info("castv2: device offline", "device", key, "endpoint", td.endpointID)
				}
				delete(tracked, key)
			}
		}
	}

	sweep()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			sweep()
		}
	}
}

// queryMDNS runs one question and collection window on a fresh
// ephemeral socket. The question sets the unicast-response bit, so
// devices reply straight to this socket's port and no multicast group
// membership is needed; sending to the default route's interface is
// enough for the LANs cast devices live on.
func queryMDNS(ctx context.Context) ([]Device, error) {
	pc, err := net.ListenPacket("udp4", "0.0.0.0:0")
	if err != nil {
		return nil, fmt.Errorf("castv2: opening mdns socket: %w", err)
	}
	defer pc.Close()
	dst, err := net.ResolveUDPAddr("udp4", mdnsAddr)
	if err != nil {
		return nil, fmt.Errorf("castv2: resolving mdns address: %w", err)
	}
	if _, err := pc.WriteTo(mdnsQuestion(), dst); err != nil {
		return nil, fmt.Errorf("castv2: sending mdns question: %w", err)
	}
	agg := newMDNSAggregate()
	deadline := time.Now().Add(mdnsWindow)
	buf := make([]byte, 9000)
	for time.Now().Before(deadline) && ctx.Err() == nil {
		// Short read deadlines keep cancellation prompt inside the
		// window.
		pc.SetReadDeadline(time.Now().Add(250 * time.Millisecond))
		n, _, err := pc.ReadFrom(buf)
		if err != nil {
			var ne net.Error
			if errors.As(err, &ne) && ne.Timeout() {
				continue
			}
			return nil, fmt.Errorf("castv2: reading mdns response: %w", err)
		}
		agg.absorb(buf[:n])
	}
	return agg.devices(), nil
}

// mdnsQuestion is one PTR question for the cast service with the
// unicast-response bit set on the class.
func mdnsQuestion() []byte {
	b := make([]byte, 12, 64)
	binary.BigEndian.PutUint16(b[4:6], 1) // one question
	b = appendDNSName(b, mdnsService)
	b = binary.BigEndian.AppendUint16(b, typePTR)
	b = binary.BigEndian.AppendUint16(b, 0x8001) // IN, unicast response requested
	return b
}

func appendDNSName(b []byte, name string) []byte {
	for _, label := range strings.Split(name, ".") {
		if label == "" {
			continue
		}
		b = append(b, byte(len(label)))
		b = append(b, label...)
	}
	return append(b, 0)
}

// mdnsAggregate merges records across response packets: a device's
// PTR, SRV, TXT, and A records usually arrive together, but nothing
// requires it.
type mdnsAggregate struct {
	srv map[string]srvRecord         // instance name -> target and port
	txt map[string]map[string]string // instance name -> key=value pairs
	a   map[string]string            // hostname -> IPv4
}

type srvRecord struct {
	target string
	port   int
}

func newMDNSAggregate() *mdnsAggregate {
	return &mdnsAggregate{
		srv: make(map[string]srvRecord),
		txt: make(map[string]map[string]string),
		a:   make(map[string]string),
	}
}

// absorb parses one response packet, keeping the records it
// understands and skipping the rest. Malformed packets are dropped
// silently; mDNS is a noisy medium and lenience is the norm.
func (g *mdnsAggregate) absorb(pkt []byte) {
	if len(pkt) < 12 {
		return
	}
	qd := int(binary.BigEndian.Uint16(pkt[4:6]))
	records := int(binary.BigEndian.Uint16(pkt[6:8])) +
		int(binary.BigEndian.Uint16(pkt[8:10])) +
		int(binary.BigEndian.Uint16(pkt[10:12]))
	off := 12
	for range qd {
		_, next, ok := readDNSName(pkt, off)
		if !ok || next+4 > len(pkt) {
			return
		}
		off = next + 4
	}
	for range records {
		name, next, ok := readDNSName(pkt, off)
		if !ok || next+10 > len(pkt) {
			return
		}
		typ := binary.BigEndian.Uint16(pkt[next:])
		rdlen := int(binary.BigEndian.Uint16(pkt[next+8:]))
		rdOff := next + 10
		if rdOff+rdlen > len(pkt) {
			return
		}
		rd := pkt[rdOff : rdOff+rdlen]
		switch typ {
		case typeSRV:
			if len(rd) >= 6 {
				// The target name may be compressed against the whole
				// packet, so it is read with full packet context.
				if target, _, ok := readDNSName(pkt, rdOff+6); ok {
					g.srv[canonName(name)] = srvRecord{
						target: canonName(target),
						port:   int(binary.BigEndian.Uint16(rd[4:6])),
					}
				}
			}
		case typeTXT:
			kv := g.txt[canonName(name)]
			if kv == nil {
				kv = make(map[string]string)
				g.txt[canonName(name)] = kv
			}
			for p := 0; p < len(rd); {
				l := int(rd[p])
				p++
				if p+l > len(rd) {
					break
				}
				if k, v, found := strings.Cut(string(rd[p:p+l]), "="); found {
					kv[k] = v
				}
				p += l
			}
		case typeA:
			if len(rd) == 4 {
				g.a[canonName(name)] = netip.AddrFrom4([4]byte(rd)).String()
			}
		case typePTR:
			// The pointed-to instance carries its own SRV and TXT
			// records; the pointer itself adds nothing.
		}
		off = rdOff + rdlen
	}
}

// devices assembles a Device from every cast instance that produced
// an SRV record, sorted for deterministic sweeps.
func (g *mdnsAggregate) devices() []Device {
	var out []Device
	for instance, srv := range g.srv {
		if !strings.HasSuffix(instance, "."+mdnsService) {
			continue
		}
		txt := g.txt[instance]
		host := g.a[srv.target]
		if host == "" {
			host = srv.target
		}
		name := txt["fn"]
		if name == "" {
			name, _, _ = strings.Cut(instance, ".")
		}
		out = append(out, Device{Host: host, Port: srv.port, Name: name, ID: txt["id"]})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Key() < out[j].Key() })
	return out
}

// canonName lowercases a DNS name for matching; names compare
// case-insensitively.
func canonName(name string) string {
	return strings.ToLower(strings.TrimSuffix(name, "."))
}

// readDNSName decodes a possibly compressed name starting at off. It
// returns the dotted name and the offset just past the name in the
// uncompressed stream. The jump limit stops pointer loops.
func readDNSName(pkt []byte, off int) (string, int, bool) {
	var labels []string
	next := -1
	jumps := 0
	for {
		if off >= len(pkt) {
			return "", 0, false
		}
		b := int(pkt[off])
		switch {
		case b == 0:
			if next < 0 {
				next = off + 1
			}
			return strings.Join(labels, "."), next, true
		case b&0xC0 == 0xC0:
			if off+1 >= len(pkt) {
				return "", 0, false
			}
			if next < 0 {
				next = off + 2
			}
			if jumps++; jumps > 16 {
				return "", 0, false
			}
			off = (b&0x3F)<<8 | int(pkt[off+1])
		case b&0xC0 == 0:
			if off+1+b > len(pkt) {
				return "", 0, false
			}
			labels = append(labels, string(pkt[off+1:off+1+b]))
			off += 1 + b
		default:
			return "", 0, false
		}
	}
}
