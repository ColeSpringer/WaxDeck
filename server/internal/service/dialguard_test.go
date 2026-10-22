package service

import (
	"context"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"sync/atomic"
	"testing"
)

// The guard refuses what the catalog's own feed client refuses, in every
// form an address can reach it in: loopback, private and unique-local,
// link-local, unspecified, interface-local multicast, carrier-grade NAT
// and the IETF protocol block, as themselves, IPv4-mapped, or behind
// NAT64's well-known prefix.
func TestTheDialGuardRefusesWhatTheCatalogRefuses(t *testing.T) {
	t.Parallel()
	refused := []string{
		"127.0.0.1", "127.255.255.254", "::1",
		"10.0.0.1", "10.255.255.255", "172.16.0.1", "172.31.255.255", "192.168.0.1", "192.168.255.255",
		"fc00::1", "fdff:ffff::1",
		"169.254.0.1", "169.254.169.254", "fe80::1", "febf::1",
		"224.0.0.1", "224.0.0.255", "ff02::1", "ff01::1",
		"0.0.0.0", "::",
		"100.64.0.0", "100.100.100.200", "100.101.102.103", "100.127.255.255",
		"192.0.0.0", "192.0.0.8", "192.0.0.255",
		"::ffff:127.0.0.1", "::ffff:10.0.0.1", "::ffff:169.254.169.254", "::ffff:100.64.0.1", "::ffff:192.0.0.9",
		"64:ff9b::7f00:1", "64:ff9b::a00:1", "64:ff9b::a9fe:a9fe", "64:ff9b::6464:64c8", "64:ff9b::c000:8",
	}
	allowed := []string{
		"8.8.8.8", "1.1.1.1", "100.63.255.255", "100.128.0.0", "191.255.255.255", "192.0.1.0", "192.0.2.1",
		"172.32.0.1", "11.0.0.1", "169.255.0.1", "224.0.1.1",
		"2606:4700:4700::1111", "2001:4860:4860::8888",
		"::ffff:8.8.8.8", "64:ff9b::808:808", "64:ff9b::6440:0:0",
	}
	l := &Library{}
	for _, s := range refused {
		if !privateIP(net.ParseIP(s)) {
			t.Errorf("%s is not refused", s)
		}
		if err := refusePrivateAddr(net.JoinHostPort(s, "443")); !errors.Is(err, errPrivateAddress) {
			t.Errorf("dialing %s: %v, want the private-address refusal", s, err)
		}
		if err := l.guardAcquireHost(context.Background(), s); KindOf(err) != KindInvalid {
			t.Errorf("acquiring from %s: %v, want a refusal", s, err)
		}
	}
	for _, s := range allowed {
		if privateIP(net.ParseIP(s)) {
			t.Errorf("%s is refused", s)
		}
	}
}

// Every client that fetches an address someone else named dials through
// the one guard, so none of them reaches a private host while its switch
// is off.
func TestEveryGuardedClientRefusesAPrivateHost(t *testing.T) {
	t.Parallel()
	var asked atomic.Int32
	ts := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { asked.Add(1) }))
	t.Cleanup(ts.Close)
	l := &Library{}
	clients := map[string]*http.Client{
		"transcripts and chapters": l.transcriptClient(),
		"the enclosure relay":      l.enclosureClient(),
		"radio":                    l.radioClient(),
		"notification delivery":    l.guardedNotifyClient(),
		"scrobbling":               scrobbleHTTPClient(false),
	}
	for name, client := range clients {
		resp, err := client.Get(ts.URL)
		if err == nil {
			resp.Body.Close()
		}
		if !errors.Is(err, errPrivateAddress) {
			t.Errorf("%s: %v, want the private-address refusal", name, err)
		}
	}
	if n := asked.Load(); n != 0 {
		t.Errorf("the private host was asked %d times", n)
	}
}

// A feed whose host is a NAT64 literal of a refused address is refused
// at the subscribe door, which the catalog's own guard would dial; a NAT64
// form of a public address, or a name, is not the door's to refuse. Only
// the refused literals go through a subscribe, which then dials nothing.
func TestASubscribeRefusesANAT64PrivateLiteral(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
	})
	for _, host := range []string{"[64:ff9b::a9fe:a9fe]", "[64:ff9b::a00:1]", "[64:ff9b::7f00:1]:8080"} {
		_, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: "http://" + host + "/latest/meta-data/"})
		if KindOf(err) != KindInvalid || FeedFailureReason(err) != reasonBlockedAddress {
			t.Errorf("subscribing to %s: %v (%s), want blocked-address", host, err, FeedFailureReason(err))
		}
	}
	for _, rawURL := range []string{"http://[64:ff9b::808:808]/feed.xml", "http://8.8.8.8/feed.xml", "http://feeds.example/feed.xml", "http://[::1]/feed.xml"} {
		if refusedNAT64Host(rawURL) {
			t.Errorf("%s is refused at the door", rawURL)
		}
	}
}
