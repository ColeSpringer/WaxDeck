package main

import (
	"context"
	"log/slog"
	"net"
	"strconv"
	"strings"

	"github.com/colespringer/waxdeck/server/internal/api"
	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/bridge/flow"
	"github.com/colespringer/waxdeck/server/internal/cast/castv2"
	"github.com/colespringer/waxdeck/server/internal/cast/dlna"
	"github.com/colespringer/waxdeck/server/internal/cast/jukebox"
	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/events"
	"github.com/colespringer/waxdeck/server/internal/service"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// startConnect starts the connect core and the cast endpoints, answering
// the core and the bases it advertises media from.
func startConnect(ctx context.Context, group *supervise.Group, casting castingConfig, addr, publicBase string,
	store *db.DB, svc *service.Library, bridge *flow.Bridge, media *auth.MediaTokens, hub *events.Hub,
	log *slog.Logger) (*connect.Service, connect.Bases, error) {
	// The connect core: endpoint registry, playback sessions, and the
	// command routing between controllers and endpoints. The advertise
	// bases are what cast devices and renderers fetch media from; the
	// LAN base auto-detects so plain-HTTP casting works with zero
	// setup, and the loopback base serves the jukebox.
	port := listenPort(addr)
	lanBase := casting.advertiseBase
	if lanBase == "" {
		if ip := detectLANIP(); ip != "" {
			lanBase = "http://" + ip + ":" + port
		}
	}
	bases := connect.Bases{
		Public:   strings.TrimRight(publicBase, "/"),
		LAN:      strings.TrimRight(lanBase, "/"),
		Loopback: "http://127.0.0.1:" + port,
	}
	connectSvc, err := connect.New(ctx, connect.Config{
		Store:                store,
		Group:                group,
		Resolver:             &api.ConnectResolver{Svc: svc, Bridge: bridge, Media: media},
		Sink:                 &api.ConnectSink{Svc: svc},
		Bases:                bases,
		InvalidatePlayer:     hub.MarkPlayerAll,
		SharedOutputsAllowed: svc.UserSharedOutputsAllowed,
		EntriesVisible:       svc.QueueEntriesVisible,
		Logger:               log,
	})
	if err != nil {
		return nil, connect.Bases{}, err
	}
	group.Go(ctx, "connect", connectSvc.Run)

	// Device discovery: multicast on the LAN plus statically configured
	// devices for networks where multicast never arrives (the compose
	// stack runs the server on the host network for this).
	if casting.discovery || casting.devices != "" {
		cfg := castv2.DiscoveryConfig{
			Announce:   connectSvc,
			Group:      group,
			Logger:     log,
			Static:     parseCastDevices(casting.devices),
			StaticOnly: !casting.discovery,
		}
		group.Go(ctx, "cast-discovery", func(c context.Context) error {
			return castv2.RunDiscovery(c, cfg)
		})
	}
	if casting.discovery || casting.dlnaDevices != "" {
		cfg := dlna.DiscoveryConfig{
			Announce:   connectSvc,
			Group:      group,
			Logger:     log,
			Static:     parseDLNADevices(casting.dlnaDevices),
			StaticOnly: !casting.discovery,
		}
		group.Go(ctx, "dlna-discovery", func(c context.Context) error {
			return dlna.RunDiscovery(c, cfg)
		})
	}
	if casting.jukebox {
		if bridge == nil {
			log.Warn("jukebox needs the streaming engine for WAV output; not registering the endpoint")
		} else {
			jbCfg := jukebox.Config{Name: casting.jukeboxName, Log: log}
			if casting.jukeboxCmd != "" {
				jbCfg.Command = strings.Fields(casting.jukeboxCmd)
			}
			if _, err := connectSvc.EndpointOnline(ctx, "jukebox", "jukebox", casting.jukeboxName, "", true, false, jukebox.Dial(jbCfg, group)); err != nil {
				log.Warn("registering jukebox endpoint", "err", err)
			}
		}
	}
	return connectSvc, bases, nil
}

// listenPort extracts the port from a listen address, defaulting to
// the standard port when the address carries none.
func listenPort(addr string) string {
	_, port, err := net.SplitHostPort(addr)
	if err != nil || port == "" {
		return "4420"
	}
	return port
}

// detectLANIP picks the machine's most plausible LAN IPv4: the first
// global unicast address on an up, non-loopback interface. Cast
// devices resolve nothing, so an address beats any name.
func detectLANIP() string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return ""
	}
	var list []lanIface
	for _, iface := range ifaces {
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		list = append(list, lanIface{
			name: iface.Name, up: iface.Flags&net.FlagUp != 0,
			loopback: iface.Flags&net.FlagLoopback != 0, addrs: addrs,
		})
	}
	return scanLANIP(list)
}

// lanIface is what detectLANIP reads off an interface, so the choice can
// be tested without one.
type lanIface struct {
	name     string
	up       bool
	loopback bool
	addrs    []net.Addr
}

// scanLANIP picks the first routable IPv4 of an interface that is up and
// neither loopback nor virtual: on the host network docker0, compose's
// br-* and VPN tunnels carry routable addresses no cast device can reach.
func scanLANIP(ifaces []lanIface) string {
	for _, iface := range ifaces {
		if !iface.up || iface.loopback || virtualInterface(iface.name) {
			continue
		}
		for _, a := range iface.addrs {
			ipNet, ok := a.(*net.IPNet)
			if !ok {
				continue
			}
			ip := ipNet.IP.To4()
			if ip == nil || !ip.IsGlobalUnicast() {
				continue
			}
			return ip.String()
		}
	}
	return ""
}

func virtualInterface(name string) bool {
	for _, p := range []string{"docker", "br-", "veth", "virbr", "podman", "cni", "flannel", "tun", "tap", "wg", "tailscale"} {
		if strings.HasPrefix(name, p) {
			return true
		}
	}
	return false
}

// parseCastDevices parses name=host:port pairs into static devices.
func parseCastDevices(s string) []castv2.Device {
	var out []castv2.Device
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		name, addr, ok := strings.Cut(part, "=")
		if !ok {
			continue
		}
		host, portStr, err := net.SplitHostPort(addr)
		if err != nil {
			continue
		}
		port, err := strconv.Atoi(portStr)
		if err != nil {
			continue
		}
		out = append(out, castv2.Device{Host: host, Port: port, Name: name})
	}
	return out
}

// parseDLNADevices parses description URLs into static devices.
func parseDLNADevices(s string) []dlna.Device {
	var out []dlna.Device
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		out = append(out, dlna.Device{Location: part})
	}
	return out
}
