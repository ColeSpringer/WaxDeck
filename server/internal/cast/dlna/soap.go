package dlna

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/colespringer/waxdeck/server/internal/connect"
)

// UPnPError is a SOAP fault carrying the renderer's UPnP error code
// (718 invalid instance, 701 transition not available, and so on).
// Callers branch on Code for the best-effort actions.
type UPnPError struct {
	Code int
	Desc string
}

func (e *UPnPError) Error() string {
	if e.Desc == "" {
		return fmt.Sprintf("dlna: upnp error %d", e.Code)
	}
	return fmt.Sprintf("dlna: upnp error %d: %s", e.Code, e.Desc)
}

// soapArg is one ordered action argument. Order matters on the wire:
// some renderers reject envelopes whose arguments arrive out of the
// declared order.
type soapArg struct {
	Name  string
	Value string
}

// soapCall posts one UPnP action to a control URL and returns the
// response arguments as a flat name to text map. A fault response comes
// back as a *UPnPError.
func soapCall(ctx context.Context, httpc *http.Client, controlURL, serviceType, action string, args []soapArg) (map[string]string, error) {
	var body strings.Builder
	body.WriteString(`<?xml version="1.0" encoding="utf-8"?>`)
	body.WriteString(`<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>`)
	body.WriteString(`<u:` + action + ` xmlns:u="` + serviceType + `">`)
	for _, a := range args {
		body.WriteString("<" + a.Name + ">")
		body.WriteString(xmlEscape(a.Value))
		body.WriteString("</" + a.Name + ">")
	}
	body.WriteString(`</u:` + action + `></s:Body></s:Envelope>`)

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, controlURL, strings.NewReader(body.String()))
	if err != nil {
		return nil, fmt.Errorf("dlna: %s: %w", action, err)
	}
	req.Header.Set("Content-Type", `text/xml; charset="utf-8"`)
	req.Header.Set("SOAPACTION", `"`+serviceType+`#`+action+`"`)
	resp, err := httpc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("dlna: %s: %w", action, err)
	}
	defer resp.Body.Close()

	out, fault, err := parseSOAPResponse(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, fmt.Errorf("dlna: %s: parsing response: %w", action, err)
	}
	if fault != nil {
		return nil, fmt.Errorf("dlna: %s: %w", action, fault)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("dlna: %s: status %d", action, resp.StatusCode)
	}
	return out, nil
}

// parseSOAPResponse walks the envelope collecting leaf element text by
// local name. Response argument names never collide inside one action,
// so a flat map is enough; a Fault element switches the result to a
// *UPnPError built from the UPnPError detail block.
func parseSOAPResponse(r io.Reader) (map[string]string, *UPnPError, error) {
	dec := xml.NewDecoder(r)
	out := make(map[string]string)
	inFault := false
	var name string
	var text strings.Builder
	for {
		tok, err := dec.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, nil, err
		}
		switch t := tok.(type) {
		case xml.StartElement:
			if t.Name.Local == "Fault" {
				inFault = true
			}
			name = t.Name.Local
			text.Reset()
		case xml.CharData:
			text.Write(t)
		case xml.EndElement:
			if t.Name.Local == name {
				out[name] = text.String()
			}
			name = ""
		}
	}
	if inFault {
		fault := &UPnPError{Desc: out["errorDescription"]}
		if c, err := strconv.Atoi(strings.TrimSpace(out["errorCode"])); err == nil {
			fault.Code = c
		}
		return nil, fault, nil
	}
	return out, nil, nil
}

// xmlEscape escapes text for element content and attribute values.
func xmlEscape(s string) string {
	var b strings.Builder
	if err := xml.EscapeText(&b, []byte(s)); err != nil {
		return ""
	}
	return b.String()
}

// didlLite renders the CurrentURIMetaData payload for one item: a
// DIDL-Lite document the renderer shows on its own UI. Every field is
// escaped here and the whole document is escaped again by soapCall when
// it rides inside the envelope; that double escaping is the wire
// format, not an accident.
func didlLite(item connect.MediaItem) string {
	var b strings.Builder
	b.WriteString(`<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">`)
	b.WriteString(`<item id="` + xmlEscape(item.PID) + `" parentID="0" restricted="1">`)
	b.WriteString(`<dc:title>` + xmlEscape(item.Title) + `</dc:title>`)
	if item.Artist != "" {
		b.WriteString(`<upnp:artist>` + xmlEscape(item.Artist) + `</upnp:artist>`)
	}
	b.WriteString(`<upnp:class>object.item.audioItem.musicTrack</upnp:class>`)
	if item.ArtURL != "" {
		b.WriteString(`<upnp:albumArtURI>` + xmlEscape(item.ArtURL) + `</upnp:albumArtURI>`)
	}
	b.WriteString(`<res protocolInfo="http-get:*:` + xmlEscape(item.MimeType) + `:*"`)
	if item.DurationMS > 0 {
		b.WriteString(` duration="` + formatHMS(item.DurationMS) + `"`)
	}
	b.WriteString(`>` + xmlEscape(item.URL) + `</res>`)
	b.WriteString(`</item></DIDL-Lite>`)
	return b.String()
}

// formatHMS renders milliseconds in the UPnP H+:MM:SS time form.
func formatHMS(ms int64) string {
	if ms < 0 {
		ms = 0
	}
	s := ms / 1000
	return fmt.Sprintf("%d:%02d:%02d", s/3600, s/60%60, s%60)
}

// parseHMS parses the UPnP H+:MM:SS form, with an optional fractional
// second, into milliseconds. Empty and NOT_IMPLEMENTED values report
// false; renderers send both while stopped.
func parseHMS(v string) (int64, bool) {
	v = strings.TrimSpace(v)
	if v == "" || strings.EqualFold(v, "NOT_IMPLEMENTED") {
		return 0, false
	}
	parts := strings.Split(v, ":")
	if len(parts) != 3 {
		return 0, false
	}
	h, err := strconv.Atoi(parts[0])
	if err != nil || h < 0 {
		return 0, false
	}
	m, err := strconv.Atoi(parts[1])
	if err != nil || m < 0 || m > 59 {
		return 0, false
	}
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
	s, err := strconv.Atoi(sec)
	if err != nil || s < 0 || s > 59 {
		return 0, false
	}
	return (int64(h)*3600+int64(m)*60+int64(s))*1000 + fracMS, true
}
