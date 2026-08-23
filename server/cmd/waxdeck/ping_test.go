package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestPingURLMapsWildcardHostsToLoopback(t *testing.T) {
	cases := map[string]string{
		":4420":            "http://127.0.0.1:4420/api/v1/health",
		"0.0.0.0:4420":     "http://127.0.0.1:4420/api/v1/health",
		"[::]:4420":        "http://127.0.0.1:4420/api/v1/health",
		"192.168.1.5:9000": "http://192.168.1.5:9000/api/v1/health",
	}
	for addr, want := range cases {
		got, err := pingURL(addr)
		if err != nil {
			t.Errorf("pingURL(%q): %v", addr, err)
			continue
		}
		if got != want {
			t.Errorf("pingURL(%q) = %q, want %q", addr, got, want)
		}
	}
}

func TestPingURLRejectsAnUnparseableAddress(t *testing.T) {
	if _, err := pingURL("no-port-here"); err == nil {
		t.Fatal("pingURL accepted an address without a port")
	}
}

func TestPingServerAgainstAHealthyServer(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/health" {
			http.NotFound(w, r)
			return
		}
		w.Write([]byte(`{"status":"ok"}`))
	}))
	defer srv.Close()

	addr := strings.TrimPrefix(srv.URL, "http://")
	if err := pingServer(addr); err != nil {
		t.Fatalf("pingServer against a healthy server: %v", err)
	}
}

func TestPingServerFailsOnANonOKStatus(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer srv.Close()

	if err := pingServer(strings.TrimPrefix(srv.URL, "http://")); err == nil {
		t.Fatal("pingServer accepted a 503")
	}
}

func TestPingServerFailsWhenNothingListens(t *testing.T) {
	// A listener opened and closed again: the port existed and now
	// refuses, which is as close to "server down" as a test can pin.
	srv := httptest.NewServer(http.NotFoundHandler())
	addr := strings.TrimPrefix(srv.URL, "http://")
	srv.Close()

	if err := pingServer(addr); err == nil {
		t.Fatal("pingServer accepted a dead address")
	}
}
