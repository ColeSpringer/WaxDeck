package dlna

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Service type urns the endpoint speaks. Matching is by prefix up to
// the version so a renderer advertising AVTransport:2 still connects;
// version 1 actions are a strict subset.
const (
	svcAVTransport       = "urn:schemas-upnp-org:service:AVTransport:1"
	svcRenderingControl  = "urn:schemas-upnp-org:service:RenderingControl:1"
	svcConnectionManager = "urn:schemas-upnp-org:service:ConnectionManager:1"
)

// descriptionTimeout bounds one description fetch; renderers answer
// from RAM, so anything slower is effectively gone.
const descriptionTimeout = 5 * time.Second

// description is the slice of a device description this package uses:
// identity plus the resolved control URLs of the three services.
type description struct {
	FriendlyName      string
	UDN               string
	AVTransport       string
	RenderingControl  string
	ConnectionManager string
}

// fetchDescription downloads and parses the device description at
// location, resolving each controlURL against the description URL as
// the UPnP architecture requires (devices publish relative paths).
func fetchDescription(ctx context.Context, location string) (description, error) {
	httpc := &http.Client{Timeout: descriptionTimeout}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, location, nil)
	if err != nil {
		return description{}, fmt.Errorf("dlna: fetching description: %w", err)
	}
	resp, err := httpc.Do(req)
	if err != nil {
		return description{}, fmt.Errorf("dlna: fetching description: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return description{}, fmt.Errorf("dlna: fetching description %s: status %d", location, resp.StatusCode)
	}
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return description{}, fmt.Errorf("dlna: fetching description: %w", err)
	}
	return parseDescription(location, raw)
}

// parseDescription reads the description XML against its base URL.
func parseDescription(location string, raw []byte) (description, error) {
	var doc struct {
		Device struct {
			FriendlyName string `xml:"friendlyName"`
			UDN          string `xml:"UDN"`
			Services     []struct {
				ServiceType string `xml:"serviceType"`
				ControlURL  string `xml:"controlURL"`
			} `xml:"serviceList>service"`
		} `xml:"device"`
	}
	if err := xml.Unmarshal(raw, &doc); err != nil {
		return description{}, fmt.Errorf("dlna: parsing description: %w", err)
	}
	base, err := url.Parse(location)
	if err != nil {
		return description{}, fmt.Errorf("dlna: parsing description url: %w", err)
	}
	desc := description{
		FriendlyName: strings.TrimSpace(doc.Device.FriendlyName),
		UDN:          strings.TrimSpace(doc.Device.UDN),
	}
	for _, s := range doc.Device.Services {
		ref, err := url.Parse(strings.TrimSpace(s.ControlURL))
		if err != nil {
			continue
		}
		control := base.ResolveReference(ref).String()
		switch {
		case serviceIs(s.ServiceType, svcAVTransport):
			desc.AVTransport = control
		case serviceIs(s.ServiceType, svcRenderingControl):
			desc.RenderingControl = control
		case serviceIs(s.ServiceType, svcConnectionManager):
			desc.ConnectionManager = control
		}
	}
	return desc, nil
}

// serviceIs matches an advertised service type against a v1 urn,
// accepting any version suffix.
func serviceIs(advertised, urn string) bool {
	base := urn[:strings.LastIndex(urn, ":")+1]
	return strings.HasPrefix(strings.TrimSpace(advertised), base)
}

// client speaks the renderer's control services over SOAP. All calls
// address InstanceID 0: renderers with multiple AVTransport instances
// exist on paper only.
type client struct {
	httpc *http.Client
	desc  description
}

func newClient(desc description) *client {
	return &client{httpc: &http.Client{Timeout: descriptionTimeout}, desc: desc}
}

func (c *client) av(ctx context.Context, action string, args ...soapArg) (map[string]string, error) {
	return soapCall(ctx, c.httpc, c.desc.AVTransport, svcAVTransport, action, args)
}

func (c *client) setURI(ctx context.Context, uri, metadata string) error {
	_, err := c.av(ctx, "SetAVTransportURI",
		soapArg{"InstanceID", "0"}, soapArg{"CurrentURI", uri}, soapArg{"CurrentURIMetaData", metadata})
	return err
}

func (c *client) setNextURI(ctx context.Context, uri, metadata string) error {
	_, err := c.av(ctx, "SetNextAVTransportURI",
		soapArg{"InstanceID", "0"}, soapArg{"NextURI", uri}, soapArg{"NextURIMetaData", metadata})
	return err
}

func (c *client) play(ctx context.Context) error {
	_, err := c.av(ctx, "Play", soapArg{"InstanceID", "0"}, soapArg{"Speed", "1"})
	return err
}

func (c *client) pause(ctx context.Context) error {
	_, err := c.av(ctx, "Pause", soapArg{"InstanceID", "0"})
	return err
}

func (c *client) stop(ctx context.Context) error {
	_, err := c.av(ctx, "Stop", soapArg{"InstanceID", "0"})
	return err
}

func (c *client) seek(ctx context.Context, positionMS int64) error {
	_, err := c.av(ctx, "Seek",
		soapArg{"InstanceID", "0"}, soapArg{"Unit", "REL_TIME"}, soapArg{"Target", formatHMS(positionMS)})
	return err
}

// positionInfo is one GetPositionInfo observation. RelKnown is false
// when the renderer reported NOT_IMPLEMENTED or nothing; a stopped
// renderer's 0:00:00 still parses as known zero.
type positionInfo struct {
	Track      int
	TrackURI   string
	RelMS      int64
	RelKnown   bool
	DurationMS int64
}

func (c *client) positionInfo(ctx context.Context) (positionInfo, error) {
	out, err := c.av(ctx, "GetPositionInfo", soapArg{"InstanceID", "0"})
	if err != nil {
		return positionInfo{}, err
	}
	var pos positionInfo
	if t, err := strconv.Atoi(strings.TrimSpace(out["Track"])); err == nil {
		pos.Track = t
	}
	pos.TrackURI = strings.TrimSpace(out["TrackURI"])
	pos.RelMS, pos.RelKnown = parseHMS(out["RelTime"])
	pos.DurationMS, _ = parseHMS(out["TrackDuration"])
	return pos, nil
}

// Transport states GetTransportInfo reports.
const (
	stateStopped       = "STOPPED"
	statePlaying       = "PLAYING"
	statePaused        = "PAUSED_PLAYBACK"
	stateTransitioning = "TRANSITIONING"
	stateNoMedia       = "NO_MEDIA_PRESENT"
)

func (c *client) transportState(ctx context.Context) (string, error) {
	out, err := c.av(ctx, "GetTransportInfo", soapArg{"InstanceID", "0"})
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out["CurrentTransportState"]), nil
}

func (c *client) setVolume(ctx context.Context, volume int) error {
	_, err := soapCall(ctx, c.httpc, c.desc.RenderingControl, svcRenderingControl, "SetVolume", []soapArg{
		{"InstanceID", "0"}, {"Channel", "Master"}, {"DesiredVolume", strconv.Itoa(volume)},
	})
	return err
}

func (c *client) volume(ctx context.Context) (int, error) {
	out, err := soapCall(ctx, c.httpc, c.desc.RenderingControl, svcRenderingControl, "GetVolume", []soapArg{
		{"InstanceID", "0"}, {"Channel", "Master"},
	})
	if err != nil {
		return 0, err
	}
	v, err := strconv.Atoi(strings.TrimSpace(out["CurrentVolume"]))
	if err != nil {
		return 0, fmt.Errorf("dlna: GetVolume: bad CurrentVolume %q", out["CurrentVolume"])
	}
	return v, nil
}

// protocolInfo returns the mime types the renderer's Sink accepts over
// HTTP, lowercased. Wildcard and empty entries are dropped: a renderer
// that answers "*" constrains nothing.
//
// An entry is `<protocol>:<network>:<contentFormat>:<additionalInfo>`,
// and the protocol is not decoration. Renderers routinely list formats
// they play over transports this server does not speak -- `internal:*`
// for their own local playback, `rtsp-rtp-udp:*` for a streaming client
// -- and a format offered only there is not a format we can deliver. We
// serve over http-get and nothing else, so that is what counts, plus a
// bare wildcard protocol, which claims everything.
func (c *client) protocolInfo(ctx context.Context) (map[string]bool, error) {
	out, err := soapCall(ctx, c.httpc, c.desc.ConnectionManager, svcConnectionManager, "GetProtocolInfo", nil)
	if err != nil {
		return nil, err
	}
	mimes := make(map[string]bool)
	for _, entry := range strings.Split(out["Sink"], ",") {
		fields := strings.Split(strings.TrimSpace(entry), ":")
		if len(fields) < 3 {
			continue
		}
		switch strings.ToLower(strings.TrimSpace(fields[0])) {
		case "http-get", "*":
		default:
			continue
		}
		mime := strings.ToLower(strings.TrimSpace(fields[2]))
		if mime != "" && mime != "*" {
			mimes[mime] = true
		}
	}
	return mimes, nil
}
