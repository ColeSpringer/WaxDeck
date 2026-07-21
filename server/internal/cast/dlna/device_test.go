package dlna

import (
	"context"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/cast/dlna/testrenderer"
)

func TestFetchDescription(t *testing.T) {
	r := testrenderer.Start(t)
	desc, err := fetchDescription(context.Background(), r.Location())
	if err != nil {
		t.Fatalf("fetchDescription: %v", err)
	}
	if desc.FriendlyName != "Test Renderer" {
		t.Errorf("friendlyName = %q", desc.FriendlyName)
	}
	if desc.UDN != "uuid:waxdeck-test-renderer" {
		t.Errorf("udn = %q", desc.UDN)
	}
	// Control URLs are relative in the document and must come back
	// resolved against the description URL.
	base := strings.TrimSuffix(r.Location(), "/description.xml")
	for name, got := range map[string]string{
		"AVTransport":       desc.AVTransport,
		"RenderingControl":  desc.RenderingControl,
		"ConnectionManager": desc.ConnectionManager,
	} {
		want := base + "/control/" + name
		if got != want {
			t.Errorf("%s control url = %q, want %q", name, got, want)
		}
	}
}

func TestParseDescriptionVersionTolerance(t *testing.T) {
	// A renderer advertising AVTransport:2 still connects; v1 actions
	// are a subset.
	raw := []byte(`<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
<device>
<friendlyName>Living Room</friendlyName>
<UDN>uuid:test-v2</UDN>
<serviceList>
<service>
<serviceType>urn:schemas-upnp-org:service:AVTransport:2</serviceType>
<controlURL>ctl/av</controlURL>
</service>
</serviceList>
</device>
</root>`)
	desc, err := parseDescription("http://10.0.0.5:49152/dev/desc.xml", raw)
	if err != nil {
		t.Fatalf("parseDescription: %v", err)
	}
	if desc.AVTransport != "http://10.0.0.5:49152/dev/ctl/av" {
		t.Errorf("control url = %q", desc.AVTransport)
	}
	if desc.RenderingControl != "" || desc.ConnectionManager != "" {
		t.Errorf("absent services resolved: %+v", desc)
	}
}
