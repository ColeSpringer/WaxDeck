// Package testrenderer is an in-process fake DLNA MediaRenderer for
// tests, honest at the SOAP wire: real envelopes in, real envelopes and
// faults out, modeled on a plain AVTransport:1 renderer. Playback time
// is a mock clock stepped by the test, so item ends happen exactly when
// a test says so.
package testrenderer

import (
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"
)

const (
	svcAVTransport       = "urn:schemas-upnp-org:service:AVTransport:1"
	svcRenderingControl  = "urn:schemas-upnp-org:service:RenderingControl:1"
	svcConnectionManager = "urn:schemas-upnp-org:service:ConnectionManager:1"
)

// Action is one recorded SOAP call.
type Action struct {
	Service string
	Name    string
	Args    map[string]string
}

// Renderer is the fake device. All state sits behind one mutex; the
// httptest server calls in from its own goroutines.
type Renderer struct {
	srv       *httptest.Server
	closeOnce sync.Once

	mu           sync.Mutex
	state        string
	currentURI   string
	currentMeta  string
	nextURI      string
	nextMeta     string
	relMS        int64
	track        int
	volume       int
	gapless      bool
	durations    map[string]int64
	defaultDurMS int64
	sink         []string
	actions      []Action
	uris         []string
	metaByURI    map[string]string
}

// Start serves a renderer for the test's lifetime.
func Start(t *testing.T) *Renderer {
	t.Helper()
	r := &Renderer{
		state:        "NO_MEDIA_PRESENT",
		volume:       50,
		defaultDurMS: 30_000,
		durations:    make(map[string]int64),
		metaByURI:    make(map[string]string),
		sink:         []string{"http-get:*:audio/mpeg:*", "http-get:*:audio/wav:*"},
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/description.xml", r.serveDescription)
	mux.HandleFunc("/control/AVTransport", func(w http.ResponseWriter, req *http.Request) {
		r.serveControl(w, req, "AVTransport", svcAVTransport)
	})
	mux.HandleFunc("/control/RenderingControl", func(w http.ResponseWriter, req *http.Request) {
		r.serveControl(w, req, "RenderingControl", svcRenderingControl)
	})
	mux.HandleFunc("/control/ConnectionManager", func(w http.ResponseWriter, req *http.Request) {
		r.serveControl(w, req, "ConnectionManager", svcConnectionManager)
	})
	r.srv = httptest.NewServer(mux)
	t.Cleanup(r.Kill)
	return r
}

// Location is the device description URL, what discovery would learn
// from an SSDP response.
func (r *Renderer) Location() string { return r.srv.URL + "/description.xml" }

// Kill shuts the HTTP server down, simulating the device vanishing.
// Safe to call more than once; Start registers it as cleanup.
func (r *Renderer) Kill() { r.closeOnce.Do(r.srv.Close) }

// EnableGaplessNext makes the renderer honor SetNextAVTransportURI by
// promoting the next URI itself when the current item ends, like the
// better renderers do.
func (r *Renderer) EnableGaplessNext() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.gapless = true
}

// SetDuration overrides the playback length for one URI (default 30s).
func (r *Renderer) SetDuration(uri string, d time.Duration) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.durations[uri] = d.Milliseconds()
}

// SetSink replaces the protocolInfo entries GetProtocolInfo reports.
func (r *Renderer) SetSink(entries ...string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.sink = append([]string(nil), entries...)
}

// Advance steps the mock playback clock. Position only moves through
// this call, and only while playing; reaching the item's duration
// stops the renderer, or promotes the next URI when gapless is on.
func (r *Renderer) Advance(d time.Duration) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.state != "PLAYING" {
		return
	}
	r.relMS += d.Milliseconds()
	for {
		dur := r.durationLocked(r.currentURI)
		if r.relMS < dur {
			return
		}
		if r.gapless && r.nextURI != "" {
			r.relMS -= dur
			r.currentURI, r.currentMeta = r.nextURI, r.nextMeta
			r.nextURI, r.nextMeta = "", ""
			r.track++
			continue
		}
		r.state = "STOPPED"
		r.relMS = 0
		return
	}
}

// Actions returns every SOAP call received so far, in order.
func (r *Renderer) Actions() []Action {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]Action(nil), r.actions...)
}

// URIsSet returns every CurrentURI from SetAVTransportURI, in order.
func (r *Renderer) URIsSet() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]string(nil), r.uris...)
}

// MetadataFor returns the DIDL-Lite metadata last supplied for uri,
// through either the current or the next slot.
func (r *Renderer) MetadataFor(uri string) string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.metaByURI[uri]
}

// TransportState reports the current transport state.
func (r *Renderer) TransportState() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.state
}

// Volume reports the current volume.
func (r *Renderer) Volume() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.volume
}

func (r *Renderer) durationLocked(uri string) int64 {
	if d, ok := r.durations[uri]; ok {
		return d
	}
	return r.defaultDurMS
}

// serveDescription answers with a real MediaRenderer device document:
// relative control URLs, three services, the shape a driver must
// resolve against the description URL.
func (r *Renderer) serveDescription(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", `text/xml; charset="utf-8"`)
	fmt.Fprint(w, `<?xml version="1.0" encoding="utf-8"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
<specVersion><major>1</major><minor>0</minor></specVersion>
<device>
<deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
<friendlyName>Test Renderer</friendlyName>
<manufacturer>WaxDeck</manufacturer>
<modelName>testrenderer</modelName>
<UDN>uuid:waxdeck-test-renderer</UDN>
<serviceList>
<service>
<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
<serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
<controlURL>/control/AVTransport</controlURL>
<eventSubURL>/event/AVTransport</eventSubURL>
<SCPDURL>/scpd/AVTransport.xml</SCPDURL>
</service>
<service>
<serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
<serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
<controlURL>/control/RenderingControl</controlURL>
<eventSubURL>/event/RenderingControl</eventSubURL>
<SCPDURL>/scpd/RenderingControl.xml</SCPDURL>
</service>
<service>
<serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
<serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>
<controlURL>/control/ConnectionManager</controlURL>
<eventSubURL>/event/ConnectionManager</eventSubURL>
<SCPDURL>/scpd/ConnectionManager.xml</SCPDURL>
</service>
</serviceList>
</device>
</root>`)
}

// serveControl handles one SOAP request for a service: parse the
// envelope, record the action, dispatch, answer with a response or
// fault envelope like a real device would.
func (r *Renderer) serveControl(w http.ResponseWriter, req *http.Request, service, serviceType string) {
	body, err := io.ReadAll(io.LimitReader(req.Body, 1<<20))
	if err != nil {
		http.Error(w, "read failed", http.StatusBadRequest)
		return
	}
	action := actionFromHeader(req.Header.Get("SOAPACTION"))
	args, err := parseActionArgs(body, action)
	if err != nil || action == "" {
		writeFault(w, 402, "Invalid Args")
		return
	}
	r.mu.Lock()
	r.actions = append(r.actions, Action{Service: service, Name: action, Args: args})
	r.mu.Unlock()

	out, code, desc := r.dispatch(service, action, args)
	if code != 0 {
		writeFault(w, code, desc)
		return
	}
	writeResponse(w, serviceType, action, out)
}

// dispatch runs one action against renderer state. A nonzero code is a
// UPnP fault.
func (r *Renderer) dispatch(service, action string, args map[string]string) (out [][2]string, code int, desc string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	switch service + "#" + action {
	case "AVTransport#SetAVTransportURI":
		uri := args["CurrentURI"]
		r.currentURI, r.currentMeta = uri, args["CurrentURIMetaData"]
		r.nextURI, r.nextMeta = "", ""
		r.relMS = 0
		r.track = 1
		r.state = "STOPPED"
		r.uris = append(r.uris, uri)
		r.metaByURI[uri] = args["CurrentURIMetaData"]
		return nil, 0, ""
	case "AVTransport#SetNextAVTransportURI":
		r.nextURI, r.nextMeta = args["NextURI"], args["NextURIMetaData"]
		r.metaByURI[r.nextURI] = r.nextMeta
		return nil, 0, ""
	case "AVTransport#Play":
		if r.currentURI == "" {
			return nil, 701, "Transition not available"
		}
		r.state = "PLAYING"
		return nil, 0, ""
	case "AVTransport#Pause":
		if r.state == "PLAYING" {
			r.state = "PAUSED_PLAYBACK"
		}
		return nil, 0, ""
	case "AVTransport#Stop":
		r.state = "STOPPED"
		r.relMS = 0
		return nil, 0, ""
	case "AVTransport#Seek":
		if args["Unit"] != "REL_TIME" {
			return nil, 710, "Seek mode not supported"
		}
		ms, ok := parseHMS(args["Target"])
		if !ok {
			return nil, 711, "Illegal seek target"
		}
		r.relMS = ms
		return nil, 0, ""
	case "AVTransport#GetPositionInfo":
		return [][2]string{
			{"Track", strconv.Itoa(r.track)},
			{"TrackDuration", formatHMS(r.durationLocked(r.currentURI))},
			{"TrackMetaData", r.currentMeta},
			{"TrackURI", r.currentURI},
			{"RelTime", formatHMS(r.relMS)},
			{"AbsTime", "NOT_IMPLEMENTED"},
			{"RelCount", "2147483647"},
			{"AbsCount", "2147483647"},
		}, 0, ""
	case "AVTransport#GetTransportInfo":
		return [][2]string{
			{"CurrentTransportState", r.state},
			{"CurrentTransportStatus", "OK"},
			{"CurrentSpeed", "1"},
		}, 0, ""
	case "RenderingControl#SetVolume":
		v, err := strconv.Atoi(args["DesiredVolume"])
		if err != nil || v < 0 || v > 100 {
			return nil, 402, "Invalid Args"
		}
		r.volume = v
		return nil, 0, ""
	case "RenderingControl#GetVolume":
		return [][2]string{{"CurrentVolume", strconv.Itoa(r.volume)}}, 0, ""
	case "ConnectionManager#GetProtocolInfo":
		return [][2]string{
			{"Source", ""},
			{"Sink", strings.Join(r.sink, ",")},
		}, 0, ""
	}
	return nil, 401, "Invalid Action"
}

// actionFromHeader extracts the action name from a SOAPACTION header,
// quoted urn#Action per spec.
func actionFromHeader(h string) string {
	h = strings.Trim(strings.TrimSpace(h), `"`)
	if i := strings.LastIndexByte(h, '#'); i >= 0 {
		return h[i+1:]
	}
	return ""
}

// parseActionArgs walks the request envelope to the element named
// action and collects its child elements as name to text pairs.
func parseActionArgs(body []byte, action string) (map[string]string, error) {
	dec := xml.NewDecoder(strings.NewReader(string(body)))
	args := make(map[string]string)
	inAction := false
	var name string
	var text strings.Builder
	for {
		tok, err := dec.Token()
		if err == io.EOF {
			return args, nil
		}
		if err != nil {
			return nil, err
		}
		switch t := tok.(type) {
		case xml.StartElement:
			if t.Name.Local == action {
				inAction = true
				continue
			}
			if inAction {
				name = t.Name.Local
				text.Reset()
			}
		case xml.CharData:
			if inAction && name != "" {
				text.Write(t)
			}
		case xml.EndElement:
			if t.Name.Local == action {
				inAction = false
				continue
			}
			if inAction && t.Name.Local == name {
				args[name] = text.String()
				name = ""
			}
		}
	}
}

func writeResponse(w http.ResponseWriter, serviceType, action string, args [][2]string) {
	var b strings.Builder
	b.WriteString(`<?xml version="1.0" encoding="utf-8"?>`)
	b.WriteString(`<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>`)
	b.WriteString(`<u:` + action + `Response xmlns:u="` + serviceType + `">`)
	for _, a := range args {
		b.WriteString("<" + a[0] + ">" + escape(a[1]) + "</" + a[0] + ">")
	}
	b.WriteString(`</u:` + action + `Response></s:Body></s:Envelope>`)
	w.Header().Set("Content-Type", `text/xml; charset="utf-8"`)
	fmt.Fprint(w, b.String())
}

// writeFault answers like a real device: HTTP 500 with a SOAP fault
// wrapping a UPnPError detail.
func writeFault(w http.ResponseWriter, code int, desc string) {
	w.Header().Set("Content-Type", `text/xml; charset="utf-8"`)
	w.WriteHeader(http.StatusInternalServerError)
	fmt.Fprintf(w, `<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>
<s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring>
<detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>%d</errorCode><errorDescription>%s</errorDescription></UPnPError></detail>
</s:Fault></s:Body></s:Envelope>`, code, escape(desc))
}

func escape(s string) string {
	var b strings.Builder
	if err := xml.EscapeText(&b, []byte(s)); err != nil {
		return ""
	}
	return b.String()
}

// formatHMS renders milliseconds in the UPnP H+:MM:SS form.
func formatHMS(ms int64) string {
	if ms < 0 {
		ms = 0
	}
	s := ms / 1000
	return fmt.Sprintf("%d:%02d:%02d", s/3600, s/60%60, s%60)
}

// parseHMS parses the UPnP H+:MM:SS form into milliseconds.
func parseHMS(v string) (int64, bool) {
	parts := strings.Split(strings.TrimSpace(v), ":")
	if len(parts) != 3 {
		return 0, false
	}
	h, err1 := strconv.Atoi(parts[0])
	m, err2 := strconv.Atoi(parts[1])
	sec := parts[2]
	var fracMS int64
	if i := strings.IndexByte(sec, '.'); i >= 0 {
		frac := sec[i+1:] + "000"
		f, err := strconv.Atoi(frac[:3])
		if err != nil {
			return 0, false
		}
		fracMS = int64(f)
		sec = sec[:i]
	}
	s, err3 := strconv.Atoi(sec)
	if err1 != nil || err2 != nil || err3 != nil || h < 0 || m < 0 || s < 0 {
		return 0, false
	}
	return (int64(h)*3600+int64(m)*60+int64(s))*1000 + fracMS, true
}
