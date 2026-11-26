package service

import (
	"context"
	"errors"
	"net"
	"testing"
)

// An acquisition refused for its address names why for a client, as a
// feed's does: a private or local host is a blocked address, and a link
// that is no web address, or whose host does not resolve, an invalid one.
func TestAnAddressRefusalNamesItsReason(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := acquireFixture(t, &stagingSource{}, func(cfg *Config) { cfg.AllowPrivateFeedHosts = false })
	svc.lookupHost = func(_ context.Context, host string) ([]net.IPAddr, error) {
		switch host {
		case "lan.example":
			return []net.IPAddr{{IP: net.ParseIP("192.168.1.20")}}, nil
		case "tube.example":
			return []net.IPAddr{{IP: net.ParseIP("203.0.113.7")}}, nil
		}
		return nil, errors.New("no such host")
	}
	for link, reason := range map[string]string{
		"https://lan.example/playlist?list=PLhome": "blocked-address",
		"http://127.0.0.1/watch?v=one":             "blocked-address",
		"https://gone.example/watch?v=one":         "invalid-address",
		"ftp://tube.example/watch?v=one":           "invalid-address",
		"tube.example/watch?v=one":                 "invalid-address",
	} {
		_, err := svc.Ingest.StartAcquisition(ctx, uc, link, false, "music", "", "", nil, nil)
		if KindOf(err) != KindInvalid || RefusalParams(err)["reason"] != reason {
			t.Errorf("acquiring %s = %v (params %v), want invalid-request for %s", link, err, RefusalParams(err), reason)
		}
	}
	if err := svc.Ingest.guardAcquireHost(ctx, "tube.example"); err != nil {
		t.Errorf("a public host = %v, want it let through", err)
	}
}
