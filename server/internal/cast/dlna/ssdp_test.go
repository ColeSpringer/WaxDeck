package dlna

import "testing"

func TestParseSSDPResponse(t *testing.T) {
	// Shaped like a MiniDLNA answer.
	minidlna := "HTTP/1.1 200 OK\r\n" +
		"CACHE-CONTROL: max-age=1800\r\n" +
		"DATE: Sat, 18 Jul 2026 10:00:00 GMT\r\n" +
		"EXT:\r\n" +
		"LOCATION: http://192.168.1.50:8200/rootDesc.xml\r\n" +
		"SERVER: Linux/5.10 UPnP/1.0 MiniDLNA/1.3.0\r\n" +
		"ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n" +
		"USN: uuid:4d696e69-444c-164e-9d41-b827eb8946fe::urn:schemas-upnp-org:device:MediaRenderer:1\r\n" +
		"\r\n"
	loc, udn, ok := parseSSDPResponse([]byte(minidlna))
	if !ok {
		t.Fatal("well-formed response rejected")
	}
	if loc != "http://192.168.1.50:8200/rootDesc.xml" {
		t.Errorf("location = %q", loc)
	}
	if udn != "uuid:4d696e69-444c-164e-9d41-b827eb8946fe" {
		t.Errorf("udn = %q", udn)
	}

	// Odd-case header names and a folded USN continuation line, both
	// legal per the header grammar SSDP borrows from HTTP.
	folded := "HTTP/1.1 200 OK\r\n" +
		"location:http://10.0.0.7:49152/description.xml\r\n" +
		"St: urn:schemas-upnp-org:device:MediaRenderer:1\r\n" +
		"Usn: uuid:abcdef00-1234-5678-9abc-def012345678::\r\n" +
		"\turn:schemas-upnp-org:device:MediaRenderer:1\r\n" +
		"eXt:\r\n" +
		"\r\n"
	loc, udn, ok = parseSSDPResponse([]byte(folded))
	if !ok {
		t.Fatal("folded response rejected")
	}
	if loc != "http://10.0.0.7:49152/description.xml" {
		t.Errorf("location = %q", loc)
	}
	if udn != "uuid:abcdef00-1234-5678-9abc-def012345678" {
		t.Errorf("udn = %q", udn)
	}

	// A bare uuid USN without the double colon suffix still yields the
	// UDN.
	bare := "HTTP/1.1 200 OK\r\n" +
		"LOCATION: http://10.0.0.8:49152/desc.xml\r\n" +
		"USN: uuid:11111111-2222-3333-4444-555555555555\r\n" +
		"\r\n"
	_, udn, ok = parseSSDPResponse([]byte(bare))
	if !ok || udn != "uuid:11111111-2222-3333-4444-555555555555" {
		t.Errorf("bare usn: udn = %q ok = %v", udn, ok)
	}

	rejects := map[string]string{
		"notify": "NOTIFY * HTTP/1.1\r\nLOCATION: http://x/d.xml\r\n\r\n",
		"no location": "HTTP/1.1 200 OK\r\n" +
			"USN: uuid:1::urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n",
		"wrong st": "HTTP/1.1 200 OK\r\n" +
			"LOCATION: http://x/d.xml\r\n" +
			"ST: urn:schemas-upnp-org:device:MediaServer:1\r\n\r\n",
		"empty": "",
	}
	for name, datagram := range rejects {
		if _, _, ok := parseSSDPResponse([]byte(datagram)); ok {
			t.Errorf("%s datagram accepted", name)
		}
	}

	// A garbage USN yields no UDN but the response still counts; the
	// caller falls back to keying by location.
	noUUID := "HTTP/1.1 200 OK\r\n" +
		"LOCATION: http://10.0.0.9:49152/desc.xml\r\n" +
		"USN: bogus\r\n" +
		"\r\n"
	loc, udn, ok = parseSSDPResponse([]byte(noUUID))
	if !ok || loc == "" || udn != "" {
		t.Errorf("garbage usn: loc = %q udn = %q ok = %v", loc, udn, ok)
	}
}
