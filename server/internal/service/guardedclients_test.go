package service

import (
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"strings"
	"sync/atomic"
	"testing"
)

// guardedClientsChild marks the run of TestGuardedClientsDialDirectly that
// the test starts as a process of its own.
const guardedClientsChild = "WAXDECK_TEST_GUARDED_CLIENTS_CHILD"

// Every client that guards the address it dials dials the destination
// itself: through an environment's proxy the guard would judge the proxy's
// address and never the host asked for. A process reads its proxy settings
// once, so the clients are tried in a process of their own whose environment
// names a proxy, with LAN hosts allowed so the guard is not what keeps a
// request from it.
func TestGuardedClientsDialDirectly(t *testing.T) {
	if os.Getenv(guardedClientsChild) != "" {
		tryGuardedClients(t)
		return
	}
	t.Parallel()
	var asked atomic.Int32
	proxy := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		asked.Add(1)
	}))
	t.Cleanup(proxy.Close)
	cmd := exec.Command(os.Args[0], "-test.run=^TestGuardedClientsDialDirectly$", "-test.count=1", "-test.v")
	cmd.Env = append(os.Environ(), guardedClientsChild+"=1",
		"HTTP_PROXY="+proxy.URL, "http_proxy="+proxy.URL,
		"HTTPS_PROXY="+proxy.URL, "https_proxy="+proxy.URL,
		"NO_PROXY=", "no_proxy=", "REQUEST_METHOD=")
	out, err := cmd.CombinedOutput()
	if err != nil || !strings.Contains(string(out), "tried 5 clients") {
		t.Fatalf("the clients' own process: %v\n%s", err, out)
	}
	if n := asked.Load(); n != 0 {
		t.Errorf("the environment's proxy was asked %d times", n)
	}
}

func tryGuardedClients(t *testing.T) {
	_, svc, _ := newCatalogFixture(t)
	svc.allowPrivateFeedHosts = true
	svc.allowPrivateRadioHosts = true
	svc.allowPrivateNotifyHosts = true
	clients := map[string]*http.Client{
		"transcripts and chapters": svc.transcriptClient(),
		"the enclosure relay":      svc.enclosureClient(),
		"radio":                    svc.radioClient(),
		"notification delivery":    svc.guardedNotifyClient(),
		"scrobbling":               scrobbleHTTPClient(true),
	}
	for name, client := range clients {
		// A name that cannot resolve: dialed directly it fails, and only a
		// proxy could answer it.
		if resp, err := client.Get("http://guarded-client.invalid/"); err == nil {
			resp.Body.Close()
			t.Errorf("%s was answered for an address that does not resolve", name)
		}
	}
	t.Logf("tried %d clients", len(clients))
}

// The relay's client reads a bounded header block, so a host cannot make
// it hold megabytes of headers for each listener.
func TestTheRelayClientBoundsResponseHeaders(t *testing.T) {
	t.Parallel()
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Filler", strings.Repeat("y", 128<<10))
		w.Header().Set("Content-Type", "audio/mpeg")
	}))
	t.Cleanup(ts.Close)
	_, svc, _ := newCatalogFixture(t)
	svc.allowPrivateFeedHosts = true
	resp, err := svc.enclosureClient().Get(ts.URL + "/episode.mp3")
	if err == nil {
		resp.Body.Close()
		t.Fatal("a 128 KiB header block was read whole")
	}
}
