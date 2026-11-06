package main

import (
	"net"
	"testing"
)

// Container bridges are skipped: on the host network docker0 is an up
// interface with a routable address that no cast device can reach.
func TestScanLANIPSkipsContainerBridges(t *testing.T) {
	addr := func(ip, cidr string) net.Addr {
		_, n, err := net.ParseCIDR(cidr)
		if err != nil {
			t.Fatal(err)
		}
		return &net.IPNet{IP: net.ParseIP(ip), Mask: n.Mask}
	}
	ifaces := []lanIface{
		{name: "lo", up: true, loopback: true, addrs: []net.Addr{addr("127.0.0.1", "127.0.0.0/8")}},
		{name: "docker0", up: true, addrs: []net.Addr{addr("172.17.0.1", "172.17.0.0/16")}},
		{name: "br-1a2b3c", up: true, addrs: []net.Addr{addr("172.18.0.1", "172.18.0.0/16")}},
		{name: "veth9f", up: true, addrs: []net.Addr{addr("169.254.3.4", "169.254.0.0/16")}},
		{name: "eth0", up: true, addrs: []net.Addr{addr("192.168.1.20", "192.168.1.0/24")}},
	}
	if got := scanLANIP(ifaces); got != "192.168.1.20" {
		t.Errorf("scanLANIP = %q, want the LAN interface's address", got)
	}
	if got := scanLANIP(ifaces[:4]); got != "" {
		t.Errorf("scanLANIP with only bridges = %q, want none", got)
	}
	// A real bridge used as the LAN interface (br0 on a libvirt host) is
	// not a container bridge.
	if got := scanLANIP([]lanIface{{name: "br0", up: true, addrs: []net.Addr{addr("10.0.0.5", "10.0.0.0/24")}}}); got != "10.0.0.5" {
		t.Errorf("scanLANIP with br0 = %q, want 10.0.0.5", got)
	}
}
